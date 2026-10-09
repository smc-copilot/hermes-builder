param(
    [string]$HermesHome = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { "$env:LOCALAPPDATA\hermes" })
)

$ErrorActionPreference = 'Stop'
$init = Join-Path $HermesHome 'bootstrap\HermesRuntimeInit.exe'
$manifest = Join-Path $HermesHome 'runtime-manifest-v2.json'
if (-not (Test-Path -LiteralPath $init)) { throw "HermesRuntimeInit.exe not found: $init" }
& $init --repair --quiet --manifest $manifest
exit $LASTEXITCODE
