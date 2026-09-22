param(
    [string]$HermesHome = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { "$env:LOCALAPPDATA\hermes" })
)

$init = Join-Path $HermesHome 'bootstrap\Initialize-Hermes.ps1'
if (-not (Test-Path $init)) { throw "Initialize-Hermes.ps1 not found: $init" }
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $init -HermesHome $HermesHome -Force
exit $LASTEXITCODE
