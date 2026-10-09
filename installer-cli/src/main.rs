use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

use installer_core::{export_diagnostics, failure_line, initialize, mutate_exit, status, ErrorCode};

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.iter().any(|a| a == "--purge-generated-runtime") {
        eprintln!("unknown command");
        return ExitCode::from(1);
    }
    let root = hermes_root();
    if args.iter().any(|a| a == "--status") {
        let (code, line) = status(&root);
        println!("{line}");
        return ExitCode::from(code as u8);
    }
    if args.iter().any(|a| a == "--export-diagnostics") {
        let output = flag_value(&args, "--output");
        let op = flag_value(&args, "--operation-id");
        let Some(output) = output else {
            println!("{}", failure_line(&installer_core::error::EngineError::new(ErrorCode::ExportTargetNotEmpty)));
            return ExitCode::from(1);
        };
        return match export_diagnostics(&root, &PathBuf::from(output), op.as_deref()) {
            Ok(()) => ExitCode::from(0),
            Err(err) => {
                println!("{}", failure_line(&err));
                ExitCode::from(mutate_exit(&err) as u8)
            }
        };
    }
    let repair = args.iter().any(|a| a == "--repair");
    let init = args.iter().any(|a| a == "--initialize");
    if !repair && !init {
        eprintln!("usage: HermesRuntimeInit.exe --initialize|--repair|--status|--export-diagnostics");
        return ExitCode::from(1);
    }
    let Some(manifest) = flag_value(&args, "--manifest") else {
        let err = installer_core::error::EngineError::new(ErrorCode::PathEscapeDenied);
        println!("{}", failure_line(&err));
        return ExitCode::from(1);
    };
    match initialize(&root, &PathBuf::from(&manifest), repair) {
        Ok(operation_id) => {
            println!("{{\"ok\":true,\"runtimeState\":\"READY\",\"operationId\":\"{operation_id}\"}}");
            ExitCode::from(0)
        }
        Err(err) => {
            let code = mutate_exit(&err);
            println!("{}", failure_line(&err));
            ExitCode::from(code as u8)
        }
    }
}

fn hermes_root() -> PathBuf {
    if let Ok(value) = env::var("HERMES_HOME") {
        if !value.is_empty() {
            return PathBuf::from(value);
        }
    }
    let local = env::var("LOCALAPPDATA").unwrap_or_else(|_| ".".into());
    PathBuf::from(local).join("hermes")
}

fn flag_value(args: &[String], name: &str) -> Option<String> {
    args.iter().position(|a| a == name).and_then(|i| args.get(i + 1).cloned())
}
