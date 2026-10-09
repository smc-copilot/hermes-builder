fn main() {
    let out = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap());
    copy_or_empty("HERMES_RELEASE_MANIFEST", &out.join("release.json"));
    println!("cargo:rerun-if-env-changed=HERMES_RELEASE_MANIFEST");
    // The Core MSI is appended to the finished EXE by Build.ps1. include_bytes
    // of that multi-gigabyte file makes rustc allocate several times its size.
    tauri_build::build();
}

fn copy_or_empty(var: &str, dest: &std::path::Path) {
    match std::env::var(var) {
        Ok(path) if !path.is_empty() && std::path::Path::new(&path).is_file() => {
            std::fs::copy(path, dest).expect("embed release manifest");
        }
        _ => {
            std::fs::write(dest, []).expect("write empty embed");
        }
    }
}
