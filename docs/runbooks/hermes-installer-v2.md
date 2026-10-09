# Hermes Enterprise Installer v2 runbook

Installer ProductVersion is `2.0.0`. Agent stays `0.21.0` at `041b6985a00d01b54f830c1607dd370007a306bf`. This round does not require Authenticode. A missing PE certificate is not a failure.

## End user

Double-click `Hermes-Setup-2.0.0-win-x64.exe`. The window runs Preflight, Install Payload, Initialize Python, Verify CLI, then Complete. Retry calls `HermesRuntimeInit.exe --initialize`. Rebuild Runtime calls `--repair`. Progress is not marked complete until the engine reports `READY`.

## Enterprise direct MSI

Run in the interactive user session. Do not run as SYSTEM (`S-1-5-18`). OPSI must use that user context.

```powershell
$op = [guid]::NewGuid().ToString()
$logDir = Join-Path $env:LOCALAPPDATA "SMC\HermesInstaller\InstallerLogs\$op"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$msi = 'D:\Release\Hermes-Core-2.0.0-win-x64.msi'
$msiLog = Join-Path $logDir 'msiexec.log'
$proc = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList @('/i', $msi, '/qn', '/norestart', '/L*V!', $msiLog) -Wait -PassThru
if ($proc.ExitCode -eq 3010) { exit 3010 }
if ($proc.ExitCode -ne 0) { exit $proc.ExitCode }
$home = Join-Path $env:LOCALAPPDATA 'hermes'
& (Join-Path $home 'bootstrap\HermesRuntimeInit.exe') --initialize --quiet --manifest (Join-Path $home 'runtime-manifest-v2.json')
exit $LASTEXITCODE
```

`3010` means Hermes files still need replacement. Do not call Init. Init itself refuses with `REBOOT_REQUIRED` when the Hermes root is pending replacement. A pending Windows Update reboot that does not name the Hermes root is not a block.

## Status exits

| runtimeState | exit |
|---|---|
| READY | 0 |
| ABSENT | 20 |
| PAYLOAD_INSTALLED | 21 |
| REPAIR_REQUIRED | 22 |
| INTERRUPTED | 23 |
| INITIALIZING | 24 |
| PAYLOAD_INSTALLED_REBOOT_REQUIRED | 25 |

`--initialize` / `--repair`: READY = 0, product absent = 20, `INSTALL_BUSY` = 24, `REBOOT_REQUIRED` = 25, any other failure = 1 with one JSON line `errorCode`, `operationId`, `diagnosticsDir`.

## Export

```powershell
& "$env:LOCALAPPDATA\hermes\bootstrap\HermesRuntimeInit.exe" --export-diagnostics --output C:\Temp\hermes-empty-export-dir
```

The output directory must be missing or empty (`EXPORT_TARGET_NOT_EMPTY`). The export does not copy `venv`, `runtime-backups`, raw `.env`, sessions, or memories.

## Uninstall

`msiexec /x` removes MSI-owned files only. It does not delete `hermes-agent\venv`, `state\enterprise-skill-ledger-v2.json`, diagnostics, or user config. There is no `--purge-generated-runtime`.
