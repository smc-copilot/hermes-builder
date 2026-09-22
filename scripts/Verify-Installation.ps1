param(
    [string]$HermesHome = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { "$env:LOCALAPPDATA\hermes" }),
    [switch]$RunDoctor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$checks = [ordered]@{
    uv = Join-Path $HermesHome 'bin\uv.exe'
    git = Join-Path $HermesHome 'git'
    node = Join-Path $HermesHome 'node\node.exe'
    source = Join-Path $HermesHome 'hermes-agent\pyproject.toml'
    lock = Join-Path $HermesHome 'hermes-agent\uv.lock'
    offlineCache = Join-Path $HermesHome 'offline\uv-cache'
    hermes = Join-Path $HermesHome 'hermes-agent\venv\Scripts\hermes.exe'
    runtimeManifest = Join-Path $HermesHome 'runtime-manifest.json'
}

$failed = @()
foreach ($kv in $checks.GetEnumerator()) {
    $ok = Test-Path $kv.Value
    Write-Host ("{0,-18} {1}  {2}" -f $kv.Key, $(if ($ok) {'OK'} else {'MISSING'}), $kv.Value)
    if (-not $ok) { $failed += $kv.Key }
}
if ($failed.Count -gt 0) { throw "Installation validation failed: $($failed -join ', ')" }

$env:HERMES_HOME = $HermesHome
$env:NO_COLOR = '1'
$hermesExe = $checks.hermes
& $hermesExe --version
if ($LASTEXITCODE -ne 0) { throw "hermes --version failed with $LASTEXITCODE" }
if ($RunDoctor) {
    & $hermesExe doctor
    if ($LASTEXITCODE -ne 0) { throw "hermes doctor failed with $LASTEXITCODE" }
}
Write-Host 'Hermes installation validation passed.'
