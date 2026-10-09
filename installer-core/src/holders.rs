use std::path::Path;

use crate::error::{ErrorCode, EngineError};

pub fn sharing_violation(err: &std::io::Error) -> bool {
    matches!(err.raw_os_error(), Some(5 | 32 | 33))
}

pub fn scan_holders(root: &Path) -> Result<Vec<u32>, EngineError> {
    let venv = root.join("hermes-agent").join("venv");
    let bin = root.join("bin").join("hermes.exe");
    let mut existing = Vec::new();
    if venv.exists() {
        existing.push(venv);
    }
    if bin.exists() {
        existing.push(bin);
    }
    if existing.is_empty() {
        return Ok(Vec::new());
    }
    unsafe { rm_holders(&existing) }
}

unsafe fn rm_holders(paths: &[std::path::PathBuf]) -> Result<Vec<u32>, EngineError> {
    use windows_sys::Win32::System::RestartManager::{
        RmEndSession, RmGetList, RmRegisterResources, RmStartSession, CCH_RM_SESSION_KEY, RM_PROCESS_INFO,
    };
    let mut session = 0u32;
    let mut key = [0u16; CCH_RM_SESSION_KEY as usize];
    let start = RmStartSession(&mut session, 0, key.as_mut_ptr());
    if start != 0 {
        return Err(EngineError::new(ErrorCode::RuntimeInUse));
    }
    let wides: Vec<Vec<u16>> = paths
        .iter()
        .map(|p| {
            let mut v: Vec<u16> = p.to_string_lossy().encode_utf16().collect();
            v.push(0);
            v
        })
        .collect();
    let ptrs: Vec<*const u16> = wides.iter().map(|w| w.as_ptr()).collect();
    let reg = RmRegisterResources(session, ptrs.len() as u32, ptrs.as_ptr(), 0, std::ptr::null(), 0, std::ptr::null());
    if reg != 0 {
        RmEndSession(session);
        return Err(EngineError::new(ErrorCode::RuntimeInUse));
    }
    let mut needed = 0u32;
    let mut count = 0u32;
    let mut reboot = 0u32;
    let first = RmGetList(session, &mut needed, &mut count, std::ptr::null_mut(), &mut reboot);
    if reboot != 0 {
        RmEndSession(session);
        return Err(EngineError::new(ErrorCode::RebootRequired));
    }
    if first != 0 && first != 234 {
        RmEndSession(session);
        return Err(EngineError::new(ErrorCode::RuntimeInUse));
    }
    let mut infos = vec![std::mem::zeroed::<RM_PROCESS_INFO>(); needed.max(1) as usize];
    count = needed;
    let second = RmGetList(session, &mut needed, &mut count, infos.as_mut_ptr(), &mut reboot);
    RmEndSession(session);
    if reboot != 0 {
        return Err(EngineError::new(ErrorCode::RebootRequired));
    }
    if second != 0 && second != 234 {
        return Err(EngineError::new(ErrorCode::RuntimeInUse));
    }
    let mut pids = Vec::new();
    for info in infos.into_iter().take(count as usize) {
        let pid = info.Process.dwProcessId;
        if pid != 0 {
            pids.push(pid);
        }
    }
    Ok(pids)
}

pub fn hermes_root_reboot_pending(root: &Path) -> bool {
    use winreg::enums::HKEY_LOCAL_MACHINE;
    use winreg::RegKey;
    let hk = RegKey::predef(HKEY_LOCAL_MACHINE);
    let Ok(key) = hk.open_subkey(r"SYSTEM\CurrentControlSet\Control\Session Manager") else {
        return false;
    };
    let Ok(values) = key.get_value::<Vec<std::ffi::OsString>, _>("PendingFileRenameOperations") else {
        return false;
    };
    let text = values.iter().map(|v| v.to_string_lossy().to_string()).collect::<String>().to_lowercase();
    let needle = root.to_string_lossy().to_lowercase();
    text.contains(&needle)
}
