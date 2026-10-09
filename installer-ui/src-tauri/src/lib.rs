use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::PathBuf;
use std::process::Command;

use installer_core::{failure_line, initialize, preflight_release, ErrorCode};
use serde_json::json;
use sha2::{Digest, Sha256};

const RELEASE: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/release.json"));
const OVERLAY_MAGIC: &[u8; 8] = b"HERMESM1";

fn hermes_root() -> PathBuf {
    let local = std::env::var("LOCALAPPDATA").unwrap_or_else(|_| ".".into());
    PathBuf::from(local).join("hermes")
}

fn free_bytes(path: &std::path::Path) -> u64 {
    let text = path.to_string_lossy();
    let mut wide: Vec<u16> = text.encode_utf16().collect();
    wide.push(0);
    unsafe {
        use windows_sys::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;
        let mut free = 0u64;
        if GetDiskFreeSpaceExW(wide.as_ptr(), &mut free, std::ptr::null_mut(), std::ptr::null_mut()) == 0 {
            return 0;
        }
        free
    }
}

#[tauri::command]
fn preflight() -> String {
    let release: serde_json::Value = serde_json::from_slice(RELEASE).unwrap_or(json!({}));
    let uncompressed = release["runtime"]["uncompressedPayloadBytes"].as_u64().unwrap_or(0);
    let venv = release["runtime"]["venvEstimatedBytes"].as_u64().unwrap_or(0);
    let root = hermes_root();
    match preflight_release(&root, uncompressed, venv, free_bytes(&root)) {
        Ok(()) => json!({"ok": true, "stage": "PREFLIGHT", "progress": 20}).to_string(),
        Err(err) => failure_line(&err),
    }
}

fn extract_embedded_msi(dest: &std::path::Path) -> Result<String, ()> {
    let exe = std::env::current_exe().map_err(|_| ())?;
    let mut file = File::open(exe).map_err(|_| ())?;
    let len = file.metadata().map_err(|_| ())?.len();
    if len < 16 {
        return Err(());
    }
    file.seek(SeekFrom::End(-16)).map_err(|_| ())?;
    let mut tail = [0u8; 16];
    file.read_exact(&mut tail).map_err(|_| ())?;
    if &tail[8..] != OVERLAY_MAGIC {
        return Err(());
    }
    let msi_len = u64::from_le_bytes(tail[..8].try_into().unwrap());
    if msi_len == 0 || msi_len + 16 > len {
        return Err(());
    }
    file.seek(SeekFrom::Start(len - 16 - msi_len)).map_err(|_| ())?;
    let mut remaining = msi_len;
    let mut hasher = Sha256::new();
    let mut out = File::create(dest).map_err(|_| ())?;
    let mut buf = [0u8; 1024 * 1024];
    while remaining > 0 {
        let take = remaining.min(buf.len() as u64) as usize;
        file.read_exact(&mut buf[..take]).map_err(|_| ())?;
        hasher.update(&buf[..take]);
        out.write_all(&buf[..take]).map_err(|_| ())?;
        remaining -= take as u64;
    }
    out.sync_all().map_err(|_| ())?;
    Ok(format!("{:x}", hasher.finalize()))
}

#[tauri::command]
fn install_payload() -> String {
    let release: serde_json::Value = serde_json::from_slice(RELEASE).unwrap_or(json!({}));
    let expected = release["msiSha256"].as_str().unwrap_or("");
    let dir = std::env::temp_dir().join("hermes-setup-msi");
    if fs::create_dir_all(&dir).is_err() {
        return failure_line(&installer_core::error::EngineError::new(ErrorCode::MsiInstallFailed));
    }
    let msi = dir.join("Hermes-Core-2.0.0-win-x64.msi");
    let actual = match extract_embedded_msi(&msi) {
        Ok(sha) => sha,
        Err(()) => return failure_line(&installer_core::error::EngineError::new(ErrorCode::MsiInstallFailed)),
    };
    if !expected.is_empty() && !actual.eq_ignore_ascii_case(expected) {
        return failure_line(&installer_core::error::EngineError::new(ErrorCode::ReleaseIdentityMismatch));
    }
    let log = dir.join("msiexec.log");
    let status = Command::new("msiexec.exe")
        .arg("/i")
        .arg(&msi)
        .arg("/qn")
        .arg("/norestart")
        .arg("/L*V!")
        .arg(&log)
        .status();
    match status {
        Ok(code) if code.code() == Some(0) => json!({"ok": true, "stage": "MSI_INSTALL", "progress": 50, "exitCode": 0}).to_string(),
        Ok(code) if code.code() == Some(3010) => failure_line(&installer_core::error::EngineError::new(ErrorCode::RebootRequired)),
        _ => failure_line(&installer_core::error::EngineError::new(ErrorCode::MsiInstallFailed)),
    }
}

#[tauri::command]
fn initialize_runtime() -> String {
    let root = hermes_root();
    let manifest = root.join("runtime-manifest-v2.json");
    match initialize(&root, &manifest, false) {
        Ok(operation_id) => json!({"ok": true, "stage": "COMPLETED", "progress": 100, "operationId": operation_id, "runtimeState": "READY"}).to_string(),
        Err(err) => failure_line(&err),
    }
}

#[tauri::command]
fn repair_runtime() -> String {
    let root = hermes_root();
    let manifest = root.join("runtime-manifest-v2.json");
    match initialize(&root, &manifest, true) {
        Ok(operation_id) => json!({"ok": true, "stage": "COMPLETED", "runtimeState": "READY", "operationId": operation_id}).to_string(),
        Err(err) => failure_line(&err),
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![preflight, install_payload, initialize_runtime, repair_runtime])
        .run(tauri::generate_context!())
        .expect("failed to run Hermes Setup");
}
