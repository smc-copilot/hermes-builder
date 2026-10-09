use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use uuid::Uuid;
use winreg::enums::{HKEY_CURRENT_USER, KEY_READ, KEY_WRITE};
use winreg::RegKey;

use crate::error::{
    ErrorCode, EngineError, RuntimeState, AGENT_VERSION, COMMIT_ORDER, INSTALLER_VERSION, SOURCE_COMMIT,
};
use crate::holders::{hermes_root_reboot_pending, scan_holders, sharing_violation};
use crate::manifest::{verify_manifest_file, RuntimeManifest};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StatusReport {
    #[serde(rename = "schemaVersion")]
    pub schema_version: u32,
    #[serde(rename = "runtimeState")]
    pub runtime_state: String,
    #[serde(rename = "installerVersion")]
    pub installer_version: String,
    #[serde(rename = "agentVersion")]
    pub agent_version: String,
    #[serde(rename = "sourceCommit")]
    pub source_commit: String,
    #[serde(rename = "errorCode")]
    pub error_code: Option<String>,
    #[serde(rename = "lastOperationId")]
    pub last_operation_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct LockFile {
    #[serde(rename = "operationId")]
    operation_id: String,
    pid: u32,
    exe: String,
    #[serde(rename = "startedAtUtc")]
    started_at_utc: String,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Receipt {
    #[serde(rename = "schemaVersion")]
    schema_version: u32,
    #[serde(rename = "runtimeState")]
    runtime_state: String,
    #[serde(rename = "installerVersion")]
    installer_version: String,
    #[serde(rename = "agentVersion")]
    agent_version: String,
    #[serde(rename = "sourceCommit")]
    source_commit: String,
    #[serde(rename = "payloadTreeSha256")]
    payload_tree_sha256: String,
    #[serde(rename = "msiProductCode")]
    msi_product_code: String,
    #[serde(rename = "activeProfile")]
    active_profile: String,
    #[serde(rename = "cliVersionFirstLine")]
    cli_version_first_line: String,
    #[serde(rename = "verifiedAtUtc")]
    verified_at_utc: String,
    #[serde(rename = "operationId")]
    operation_id: String,
}

pub fn commit_order() -> &'static [&'static str] {
    COMMIT_ORDER
}

pub fn venv_gate_passes(version_line: &str, import_ok: bool, exe_exists: bool) -> bool {
    exe_exists && import_ok && version_matches(version_line)
}

pub fn version_matches(line: &str) -> bool {
    let prefix = format!("Hermes Agent v{AGENT_VERSION} (");
    line.starts_with(&prefix)
}

pub fn status(root: &Path) -> (i32, String) {
    let report = probe(root);
    let code = report.0.status_exit();
    let body = serde_json::to_string(&report.1).unwrap_or_else(|_| "{}".to_string());
    (code, body)
}

fn probe(root: &Path) -> (RuntimeState, StatusReport) {
    let installed = msi_registered();
    let reboot = installed && (hermes_root_reboot_pending(root));
    let lock = read_lock(root);
    let receipt = read_receipt(root);
    let op = read_operation_error(root);
    let state = if !installed {
        RuntimeState::Absent
    } else if reboot {
        RuntimeState::PayloadInstalledRebootRequired
    } else if lock.as_ref().map(|l| pid_alive(l.pid) && exe_matches(&l.exe)).unwrap_or(false) {
        RuntimeState::Initializing
    } else if lock.is_some() {
        RuntimeState::Interrupted
    } else if receipt_ready(&receipt) {
        RuntimeState::Ready
    } else if op.is_some() || receipt.is_some() {
        RuntimeState::RepairRequired
    } else {
        RuntimeState::PayloadInstalled
    };
    let error = if state == RuntimeState::Interrupted {
        Some(ErrorCode::EngineInterrupted.as_str().to_string())
    } else {
        op
    };
    let report = StatusReport {
        schema_version: 2,
        runtime_state: state.as_str().to_string(),
        installer_version: receipt.as_ref().map(|r| r.installer_version.clone()).unwrap_or_else(|| INSTALLER_VERSION.to_string()),
        agent_version: receipt.as_ref().map(|r| r.agent_version.clone()).unwrap_or_else(|| AGENT_VERSION.to_string()),
        source_commit: receipt.as_ref().map(|r| r.source_commit.clone()).unwrap_or_else(|| SOURCE_COMMIT.to_string()),
        error_code: error,
        last_operation_id: lock.as_ref().map(|l| l.operation_id.clone()).or_else(|| receipt.map(|r| r.operation_id)),
    };
    (state, report)
}

pub fn initialize(root: &Path, manifest: &Path, repair: bool) -> Result<String, EngineError> {
    if current_user_is_system() {
        return Err(EngineError::new(ErrorCode::InstallIdentityDenied));
    }
    if !msi_registered() {
        return Err(EngineError::new(ErrorCode::StateTransitionDenied).with_exit_absent());
    }
    if hermes_root_reboot_pending(root) {
        return Err(EngineError::new(ErrorCode::RebootRequired));
    }
    if let Some(lock) = read_lock(root) {
        if pid_alive(lock.pid) && exe_matches(&lock.exe) {
            return Err(EngineError::new(ErrorCode::InstallBusy));
        }
    }
    let holders = scan_holders(root)?;
    if !holders.is_empty() {
        return Err(EngineError::new(ErrorCode::RuntimeInUse));
    }
    let manifest_doc = verify_manifest_file(root, manifest)?;
    let operation_id = Uuid::new_v4().to_string();
    let diagnostics = diagnostics_dir(&operation_id);
    if let Err(err) = fs::create_dir_all(&diagnostics) {
        if sharing_violation(&err) {
            return Err(EngineError::new(ErrorCode::RuntimeInUse));
        }
        return Err(EngineError::new(ErrorCode::DiagnosticsUnavailable));
    }
    write_lock(root, &operation_id)?;
    let result = run_txn(root, &manifest_doc, &operation_id, &diagnostics, repair);
    let _ = release_lock(root);
    result
}

fn run_txn(root: &Path, manifest: &RuntimeManifest, operation_id: &str, diagnostics: &Path, repair: bool) -> Result<String, EngineError> {
    let venv = root.join("hermes-agent").join("venv");
    let bin_exe = root.join("bin").join("hermes.exe");
    let t0_bin = if bin_exe.exists() { Some(fs::read(&bin_exe).map_err(map_io)?) } else { None };
    let skip_uv = !repair && venv_cli_ok(&venv);
    ensure_disk(root, manifest, repair, skip_uv)?;
    if !skip_uv {
        if venv.exists() {
            isolate_tree(&venv, root, operation_id).map_err(map_io)?;
        }
        uv_sync(root).map_err(|e| tagged(e, operation_id, diagnostics))?;
        import_verify(root)?;
        cli_verify(&venv.join("Scripts").join("hermes.exe"))?;
    } else {
        import_verify(root)?;
        cli_verify(&venv.join("Scripts").join("hermes.exe"))?;
    }
    let created = seed_templates(root)?;
    if let Err(err) = merge_skills(root) {
        let _ = undo_created(&created);
        let _ = restore_bin(&bin_exe, t0_bin.as_deref());
        return Err(tagged(err, operation_id, diagnostics));
    }
    let hkcu_t0 = capture_hkcu();
    if let Err(err) = apply_env(root) {
        let _ = undo_created(&created);
        let _ = restore_bin(&bin_exe, t0_bin.as_deref());
        restore_hkcu(&hkcu_t0);
        return Err(tagged(err, operation_id, diagnostics));
    }
    if let Err(err) = stage_bin(&venv, &bin_exe) {
        let _ = undo_created(&created);
        let _ = restore_bin(&bin_exe, t0_bin.as_deref());
        restore_hkcu(&hkcu_t0);
        return Err(tagged(err, operation_id, diagnostics));
    }
    let line = match cli_verify(&bin_exe) {
        Ok(line) => line,
        Err(err) => {
            let _ = restore_bin(&bin_exe, t0_bin.as_deref());
            let _ = undo_created(&created);
            restore_hkcu(&hkcu_t0);
            return Err(tagged(err, operation_id, diagnostics));
        }
    };
    publish_receipt(root, manifest, operation_id, &line).map_err(|err| tagged(err, operation_id, diagnostics))?;
    let _ = fs::remove_dir_all(root.join("state").join("runtime-backups").join(operation_id));
    Ok(operation_id.to_string())
}

fn tagged(mut err: EngineError, operation_id: &str, diagnostics: &Path) -> EngineError {
    err.operation_id = operation_id.to_string();
    err.diagnostics_dir = diagnostics.display().to_string();
    err
}

impl EngineError {
    fn with_exit_absent(self) -> Self {
        self
    }
}

pub fn mutate_exit(err: &EngineError) -> i32 {
    match err.code {
        ErrorCode::StateTransitionDenied => 20,
        ErrorCode::InstallBusy => 24,
        ErrorCode::RebootRequired => 25,
        _ => 1,
    }
}

pub fn failure_line(err: &EngineError) -> String {
    json!({
        "ok": false,
        "errorCode": err.code.as_str(),
        "operationId": err.operation_id,
        "diagnosticsDir": err.diagnostics_dir,
    })
    .to_string()
}

fn map_io(err: std::io::Error) -> EngineError {
    if sharing_violation(&err) {
        EngineError::new(ErrorCode::RuntimeInUse)
    } else {
        EngineError::new(ErrorCode::RuntimeRollbackFailed)
    }
}

fn isolate_tree(venv: &Path, root: &Path, operation_id: &str) -> std::io::Result<()> {
    let dest = root.join("state").join("runtime-backups").join(operation_id).join("venv");
    fs::create_dir_all(dest.parent().unwrap())?;
    fs::rename(venv, dest)
}

fn uv_sync(root: &Path) -> Result<(), EngineError> {
    let uv = root.join("bin").join("uv.exe");
    let python = root.join("python").join("python.exe");
    let agent = root.join("hermes-agent");
    if !uv.exists() || !python.exists() {
        return Err(EngineError::new(ErrorCode::HermesCliMissing));
    }
    let mut cmd = Command::new(&uv);
    cmd.env_clear();
    for key in ["SYSTEMROOT", "WINDIR", "TEMP", "TMP", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "HOMEDRIVE", "HOMEPATH"] {
        if let Ok(value) = std::env::var(key) {
            cmd.env(key, value);
        }
    }
    let system32 = std::env::var("SYSTEMROOT").unwrap_or_else(|_| r"C:\Windows".to_string());
    cmd.env("PATH", format!("{};{}\\System32", root.join("bin").display(), system32));
    cmd.env("UV_CACHE_DIR", root.join("offline").join("uv-cache"));
    cmd.env("UV_PROJECT_ENVIRONMENT", agent.join("venv"));
    cmd.env("HERMES_HOME", root);
    cmd.current_dir(&agent);
    cmd.arg("sync").arg("--offline").arg("--frozen").arg("--no-config").arg("--link-mode").arg("copy");
    cmd.arg("--python").arg(&python);
    if let Ok(settings) = fs::read_to_string(root.join("offline").join("bundle-settings.json")) {
        if let Ok(value) = serde_json::from_str::<serde_json::Value>(&settings) {
            if let Some(extras) = value.get("extras").and_then(|v| v.as_array()) {
                for extra in extras {
                    if let Some(name) = extra.as_str() {
                        cmd.arg("--extra").arg(name);
                    }
                }
            }
        }
    }
    let child = cmd.output().map_err(|_| EngineError::new(ErrorCode::HermesCliMissing))?;
    if !child.status.success() {
        return Err(EngineError::new(ErrorCode::UvSyncFailed));
    }
    Ok(())
}

fn import_verify(root: &Path) -> Result<(), EngineError> {
    let python = root.join("hermes-agent").join("venv").join("Scripts").join("python.exe");
    let out = Command::new(&python).arg("-c").arg("import yaml, openai").output();
    match out {
        Ok(output) if output.status.success() => Ok(()),
        Ok(_) => Err(EngineError::new(ErrorCode::HermesCliVerifyFailed)),
        Err(_) => Err(EngineError::new(ErrorCode::HermesCliMissing)),
    }
}

fn cli_verify(exe: &Path) -> Result<String, EngineError> {
    if !exe.exists() {
        return Err(EngineError::new(ErrorCode::HermesCliMissing));
    }
    let output = Command::new(exe).arg("--version").output().map_err(|_| EngineError::new(ErrorCode::HermesCliMissing))?;
    if !output.status.success() {
        return Err(EngineError::new(ErrorCode::HermesCliVerifyFailed));
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let line = text.lines().next().unwrap_or("").trim().to_string();
    if !version_matches(&line) {
        return Err(EngineError::new(ErrorCode::HermesCliVerifyFailed));
    }
    Ok(line)
}

fn venv_cli_ok(venv: &Path) -> bool {
    let exe = venv.join("Scripts").join("hermes.exe");
    if !exe.exists() {
        return false;
    }
    import_verify(venv.parent().and_then(|p| p.parent()).unwrap_or(venv)).is_ok() && cli_verify(&exe).is_ok()
}

fn seed_templates(root: &Path) -> Result<Vec<PathBuf>, EngineError> {
    let mut created = Vec::new();
    for (src, dest) in [
        ("defaults/config/.env.template", ".env"),
        ("defaults/config/config.yaml.template", "config.yaml"),
        ("defaults/config/SOUL.md.template", "SOUL.md"),
    ] {
        let from = root.join(src);
        let to = root.join(dest);
        if to.exists() || !from.exists() {
            continue;
        }
        fs::copy(&from, &to).map_err(map_io)?;
        created.push(to);
    }
    Ok(created)
}

fn undo_created(paths: &[PathBuf]) -> std::io::Result<()> {
    for path in paths {
        if path.exists() {
            fs::remove_file(path)?;
        }
    }
    Ok(())
}

fn restore_bin(path: &Path, previous: Option<&[u8]>) -> std::io::Result<()> {
    match previous {
        Some(bytes) => {
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::write(path, bytes)
        }
        None => {
            if path.exists() {
                fs::remove_file(path)?;
            }
            Ok(())
        }
    }
}

fn merge_skills(root: &Path) -> Result<(), EngineError> {
    let source = root.join("defaults").join("enterprise-skills");
    if !source.exists() {
        return Ok(());
    }
    let dest_root = root.join("skills");
    let ledger_path = root.join("state").join("enterprise-skill-ledger-v2.json");
    let ledger = read_ledger(&ledger_path);
    let mut planned: Vec<(PathBuf, PathBuf, String)> = Vec::new();
    for file in walk_files(&source) {
        let rel = file.strip_prefix(&source).unwrap();
        let dest = dest_root.join(rel);
        let next = hex_file(&file);
        if dest.exists() {
            let current = hex_file(&dest);
            let owned = ledger.get(&rel_key(rel)).cloned();
            if owned.as_deref() != Some(current.as_str()) {
                return Err(EngineError::new(ErrorCode::SkillOwnershipConflict));
            }
        }
        planned.push((file, dest, next));
    }
    fs::create_dir_all(&dest_root).map_err(map_io)?;
    let mut new_ledger = ledger;
    for (src, dest, digest) in planned {
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent).map_err(map_io)?;
        }
        fs::copy(&src, &dest).map_err(map_io)?;
        new_ledger.insert(rel_key(dest.strip_prefix(&dest_root).unwrap()), digest);
    }
    atomic_write(&ledger_path, serde_json::to_vec(&new_ledger).unwrap()).map_err(|_| EngineError::new(ErrorCode::RuntimeInitializationFailed))?;
    Ok(())
}

fn rel_key(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn read_ledger(path: &Path) -> std::collections::BTreeMap<String, String> {
    fs::read(path).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

fn walk_files(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(rd) = fs::read_dir(&dir) else { continue };
        for entry in rd.flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else {
                out.push(path);
            }
        }
    }
    out
}

fn hex_file(path: &Path) -> String {
    let bytes = fs::read(path).unwrap_or_default();
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

fn capture_hkcu() -> [String; 3] {
    [read_env("HERMES_HOME"), read_env("HERMES_GIT_BASH_PATH"), read_env("PATH")]
}

fn read_env(name: &str) -> String {
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    hkcu.open_subkey("Environment").ok().and_then(|k| k.get_value(name).ok()).unwrap_or_default()
}

fn apply_env(root: &Path) -> Result<(), EngineError> {
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let (key, _) = hkcu.create_subkey("Environment").map_err(|_| EngineError::new(ErrorCode::RuntimeInitializationFailed))?;
    key.set_value("HERMES_HOME", &root.display().to_string()).map_err(|_| EngineError::new(ErrorCode::RuntimeInitializationFailed))?;
    let bin = root.join("bin").display().to_string();
    let path = read_env("PATH");
    if !path.to_lowercase().contains(&bin.to_lowercase()) {
        let next = if path.is_empty() { bin } else { format!("{path};{bin}") };
        key.set_value("PATH", &next).map_err(|_| EngineError::new(ErrorCode::RuntimeInitializationFailed))?;
    }
    let git = root.join("git").join("bin").join("bash.exe");
    if git.exists() {
        key.set_value("HERMES_GIT_BASH_PATH", &git.display().to_string()).map_err(|_| EngineError::new(ErrorCode::RuntimeInitializationFailed))?;
    }
    let _ = KEY_READ;
    let _ = KEY_WRITE;
    Ok(())
}

fn restore_hkcu(values: &[String; 3]) {
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    if let Ok((key, _)) = hkcu.create_subkey("Environment") {
        let _ = key.set_value("HERMES_HOME", &values[0]);
        let _ = key.set_value("HERMES_GIT_BASH_PATH", &values[1]);
        let _ = key.set_value("PATH", &values[2]);
    }
}

fn stage_bin(venv: &Path, dest: &Path) -> Result<(), EngineError> {
    let src = venv.join("Scripts").join("hermes.exe");
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent).map_err(map_io)?;
    }
    fs::copy(src, dest).map_err(map_io)?;
    Ok(())
}

fn publish_receipt(root: &Path, manifest: &RuntimeManifest, operation_id: &str, line: &str) -> Result<(), EngineError> {
    let receipt = Receipt {
        schema_version: 2,
        runtime_state: "READY".to_string(),
        installer_version: INSTALLER_VERSION.to_string(),
        agent_version: AGENT_VERSION.to_string(),
        source_commit: manifest.source_commit.clone(),
        payload_tree_sha256: manifest.payload_tree_sha256.clone(),
        msi_product_code: product_code().unwrap_or_default(),
        active_profile: "default".to_string(),
        cli_version_first_line: line.to_string(),
        verified_at_utc: now_rfc3339(),
        operation_id: operation_id.to_string(),
    };
    if manifest.agent_version != AGENT_VERSION || manifest.source_commit != SOURCE_COMMIT {
        return Err(EngineError::new(ErrorCode::ReleaseIdentityMismatch));
    }
    let path = root.join("state").join("runtime-receipt-v2.json");
    atomic_write(&path, serde_json::to_vec(&receipt).unwrap()).map_err(|_| EngineError::new(ErrorCode::ReceiptCommitFailed))
}

fn atomic_write(path: &Path, bytes: Vec<u8>) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension("json.tmp");
    {
        let mut file = File::create(&tmp)?;
        file.write_all(&bytes)?;
        file.sync_all()?;
    }
    fs::rename(&tmp, path).or_else(|_| {
        let _ = fs::remove_file(path);
        fs::rename(&tmp, path)
    })
}

pub fn export_diagnostics(root: &Path, output: &Path, operation_id: Option<&str>) -> Result<(), EngineError> {
    if output.exists() && fs::read_dir(output).map(|mut d| d.next().is_some()).unwrap_or(true) {
        return Err(EngineError::new(ErrorCode::ExportTargetNotEmpty));
    }
    fs::create_dir_all(output).map_err(|_| EngineError::new(ErrorCode::DiagnosticsUnavailable))?;
    let op = operation_id.map(|s| s.to_string()).or_else(|| latest_operation());
    if let Some(op) = op {
        let src = diagnostics_dir(&op);
        if src.exists() {
            copy_tree(&src, &output.join("InstallerLogs"))?;
        }
    }
    for name in ["runtime-receipt-v2.json", "bootstrap-operation-v2.json", "enterprise-skill-ledger-v2.json"] {
        let src = root.join("state").join(name);
        if src.exists() {
            fs::copy(&src, output.join(name)).map_err(|_| EngineError::new(ErrorCode::DiagnosticsUnavailable))?;
        }
    }
    Ok(())
}

fn copy_tree(src: &Path, dest: &Path) -> Result<(), EngineError> {
    fs::create_dir_all(dest).map_err(|_| EngineError::new(ErrorCode::DiagnosticsUnavailable))?;
    for file in walk_files(src) {
        let rel = file.strip_prefix(src).unwrap();
        let target = dest.join(rel);
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent).map_err(|_| EngineError::new(ErrorCode::DiagnosticsUnavailable))?;
        }
        fs::copy(file, target).map_err(|_| EngineError::new(ErrorCode::DiagnosticsUnavailable))?;
    }
    Ok(())
}

fn diagnostics_dir(operation_id: &str) -> PathBuf {
    let local = std::env::var("LOCALAPPDATA").unwrap_or_else(|_| ".".into());
    PathBuf::from(local).join("SMC").join("HermesInstaller").join("InstallerLogs").join(operation_id)
}

fn latest_operation() -> Option<String> {
    let local = std::env::var("LOCALAPPDATA").ok()?;
    let dir = PathBuf::from(local).join("SMC").join("HermesInstaller").join("InstallerLogs");
    let mut best: Option<(SystemTime, String)> = None;
    let rd = fs::read_dir(dir).ok()?;
    for entry in rd.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if let Ok(meta) = entry.metadata() {
            if let Ok(modified) = meta.modified() {
                if best.as_ref().map(|(t, _)| modified > *t).unwrap_or(true) {
                    best = Some((modified, name));
                }
            }
        }
    }
    best.map(|(_, name)| name)
}

fn ensure_disk(root: &Path, manifest: &RuntimeManifest, repair: bool, skip_uv: bool) -> Result<(), EngineError> {
    let need = if repair {
        manifest.venv_estimated_bytes.saturating_mul(2) + 512 * 1024 * 1024
    } else if skip_uv {
        512 * 1024 * 1024
    } else {
        manifest.venv_estimated_bytes + 512 * 1024 * 1024
    };
    let free = free_bytes(root);
    if free < need {
        return Err(EngineError::new(ErrorCode::DiskSpaceInsufficient));
    }
    Ok(())
}

fn free_bytes(root: &Path) -> u64 {
    let path = root.to_string_lossy();
    let mut wide: Vec<u16> = path.encode_utf16().collect();
    wide.push(0);
    unsafe {
        use windows_sys::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;
        let mut free = 0u64;
        if GetDiskFreeSpaceExW(wide.as_ptr(), &mut free, std::ptr::null_mut(), std::ptr::null_mut()) == 0 {
            return u64::MAX;
        }
        free
    }
}

pub fn setup_disk_ok(manifest: &RuntimeManifest, free: u64) -> bool {
    let base = manifest.uncompressed_payload_bytes.saturating_add(manifest.venv_estimated_bytes);
    let scaled = (base.saturating_mul(3) + 1) / 2;
    let need = scaled.max(8 * 1024 * 1024 * 1024);
    free >= need
}

fn msi_registered() -> bool {
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let Ok(uninstall) = hkcu.open_subkey(r"Software\Microsoft\Windows\CurrentVersion\Uninstall") else {
        return false;
    };
    for key in uninstall.enum_keys().flatten() {
        if let Ok(sub) = uninstall.open_subkey(&key) {
            let name: String = sub.get_value("DisplayName").unwrap_or_default();
            if name == "SMC Copilot Hermes" {
                return true;
            }
        }
    }
    false
}

fn product_code() -> Option<String> {
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let uninstall = hkcu.open_subkey(r"Software\Microsoft\Windows\CurrentVersion\Uninstall").ok()?;
    for key in uninstall.enum_keys().flatten() {
        if let Ok(sub) = uninstall.open_subkey(&key) {
            let name: String = sub.get_value("DisplayName").unwrap_or_default();
            if name == "SMC Copilot Hermes" {
                return Some(key);
            }
        }
    }
    None
}

fn current_user_is_system() -> bool {
    std::env::var("USERNAME").map(|n| n.eq_ignore_ascii_case("SYSTEM")).unwrap_or(false)
}

fn read_lock(root: &Path) -> Option<LockFile> {
    let path = root.join("state").join("runtime-init.lock");
    let bytes = fs::read(path).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn write_lock(root: &Path, operation_id: &str) -> Result<(), EngineError> {
    let path = root.join("state").join("runtime-init.lock");
    let lock = LockFile {
        operation_id: operation_id.to_string(),
        pid: std::process::id(),
        exe: std::env::current_exe().map(|p| p.display().to_string()).unwrap_or_default(),
        started_at_utc: now_rfc3339(),
    };
    atomic_write(&path, serde_json::to_vec(&lock).unwrap()).map_err(|_| EngineError::new(ErrorCode::RuntimeInitializationFailed))
}

fn release_lock(root: &Path) -> std::io::Result<()> {
    fs::remove_file(root.join("state").join("runtime-init.lock"))
}

fn read_receipt(root: &Path) -> Option<Receipt> {
    let bytes = fs::read(root.join("state").join("runtime-receipt-v2.json")).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn receipt_ready(receipt: &Option<Receipt>) -> bool {
    receipt.as_ref().map(|r| r.runtime_state == "READY" && r.schema_version == 2 && r.agent_version == AGENT_VERSION).unwrap_or(false)
}

fn read_operation_error(root: &Path) -> Option<String> {
    let bytes = fs::read(root.join("state").join("bootstrap-operation-v2.json")).ok()?;
    let value: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    if value.get("schemaVersion").and_then(|v| v.as_u64()) != Some(2) {
        return Some(ErrorCode::OperationSchemaUnsupported.as_str().to_string());
    }
    value.get("errorCode").and_then(|v| v.as_str()).map(|s| s.to_string())
}

fn pid_alive(pid: u32) -> bool {
    unsafe {
        use windows_sys::Win32::System::Threading::{GetExitCodeProcess, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION};
        let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if handle.is_null() {
            return false;
        }
        let mut code = 0u32;
        let ok = GetExitCodeProcess(handle, &mut code);
        windows_sys::Win32::Foundation::CloseHandle(handle);
        ok != 0 && code == 259
    }
}

fn exe_matches(recorded: &str) -> bool {
    std::env::current_exe().map(|p| p.display().to_string().eq_ignore_ascii_case(recorded)).unwrap_or(false)
}

fn now_rfc3339() -> String {
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    format!("{secs}")
}

pub fn user_owned_digest(root: &Path) -> String {
    let mut hasher = Sha256::new();
    for rel in [".env", "config.yaml", "SOUL.md"] {
        let path = root.join(rel);
        hasher.update(rel.as_bytes());
        hasher.update(fs::read(path).unwrap_or_default());
    }
    format!("{:x}", hasher.finalize())
}

pub fn preflight_release(root: &Path, uncompressed: u64, venv_bytes: u64, free: u64) -> Result<(), EngineError> {
    let manifest = RuntimeManifest {
        schema_version: 2,
        installer_version: INSTALLER_VERSION.to_string(),
        agent_version: AGENT_VERSION.to_string(),
        source_commit: SOURCE_COMMIT.to_string(),
        payload_tree_sha256: String::new(),
        uncompressed_payload_bytes: uncompressed,
        venv_estimated_bytes: venv_bytes,
        key_id: crate::error::KEY_ID.to_string(),
        files: Vec::new(),
    };
    preflight_blocks_msi(root, &manifest, free)
}

pub fn preflight_blocks_msi(root: &Path, manifest: &RuntimeManifest, free: u64) -> Result<(), EngineError> {
    if current_user_is_system() {
        return Err(EngineError::new(ErrorCode::InstallIdentityDenied));
    }
    if !setup_disk_ok(manifest, free) {
        return Err(EngineError::new(ErrorCode::DiskSpaceInsufficient));
    }
    let holders = scan_holders(root)?;
    if !holders.is_empty() {
        return Err(EngineError::new(ErrorCode::RuntimeInUse));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_gate_ignores_parenthetical_date() {
        assert!(version_matches("Hermes Agent v0.21.0 (2026.8.31)"));
        assert!(!version_matches("Hermes Agent v0.22.0 (2026.8.31)"));
        assert!(venv_gate_passes("Hermes Agent v0.21.0 (1999.1.1)", true, true));
        assert!(!venv_gate_passes("Hermes Agent v0.21.0 (1999.1.1)", true, false));
    }

    #[test]
    fn commit_order_is_unique() {
        assert_eq!(commit_order()[0], "UV_SYNC");
        assert_eq!(commit_order().last().copied(), Some("RECEIPT_COMMIT"));
        assert_eq!(commit_order().len(), 8);
    }

    #[test]
    fn setup_disk_uses_manifest_fields() {
        let manifest = RuntimeManifest {
            schema_version: 2,
            installer_version: "2.0.0".into(),
            agent_version: "0.21.0".into(),
            source_commit: SOURCE_COMMIT.into(),
            payload_tree_sha256: "ab".into(),
            uncompressed_payload_bytes: 100,
            venv_estimated_bytes: 100,
            key_id: "e6199f4b558ab9c4".into(),
            files: vec![],
        };
        assert!(!setup_disk_ok(&manifest, 1024));
        assert!(setup_disk_ok(&manifest, 9 * 1024 * 1024 * 1024));
    }

    #[test]
    fn status_does_not_create_files() {
        let dir = std::env::temp_dir().join(format!("hermes-status-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&dir).unwrap();
        let before = fs::read_dir(&dir).unwrap().count();
        let (code, _) = status(&dir);
        let after = fs::read_dir(&dir).unwrap().count();
        assert_eq!(before, after);
        assert!((0..=25).contains(&code));
        let _ = fs::remove_dir_all(dir);
    }
}
