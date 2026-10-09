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
    binHermes = Join-Path $HermesHome 'bin\hermes.exe'
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
$expectedVersion = '0.21.0'
$settingsPath = Join-Path $HermesHome 'offline\bundle-settings.json'
if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if ($settings.hermesVersion) { $expectedVersion = [string]$settings.hermesVersion }
}
$pattern = '^Hermes Agent v' + [regex]::Escape($expectedVersion) + ' \('
foreach ($exe in @($checks.hermes, $checks.binHermes)) {
    $output = @(& $exe --version 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "hermes --version failed for $exe with $LASTEXITCODE" }
    $first = if ($output.Count -gt 0) { [string]$output[0] } else { '' }
    if ($first -notmatch $pattern) {
        throw "hermes --version first line mismatch for ${exe}: '$first'"
    }
}
if ($RunDoctor) {
    & $checks.binHermes doctor
    if ($LASTEXITCODE -ne 0) { throw "hermes doctor failed with $LASTEXITCODE" }
}
Write-Host 'Hermes installation validation passed.'
