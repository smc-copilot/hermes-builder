Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$infoPath = Join-Path $repoRoot 'dist\build-info.json'
$payload = Join-Path $repoRoot 'payload'
if (-not (Test-Path -LiteralPath $infoPath)) { throw "A-BUILD-001 missing $infoPath" }
$info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
if ($info.unreleasable) { throw 'A-BUILD-001 release build-info is marked unreleasable' }
if (-not $info.offlineProof -or -not $info.offlineProof.steps) { throw 'A-BUILD-001 offlineProof missing' }
$steps = @($info.offlineProof.steps)
$required = @('uv-offline-sync', 'hermes-version', 'core-imports', 'node-deps-offline', 'chromium-present')
foreach ($name in $required) {
    $step = $steps | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $step) { throw "A-BUILD-001 missing proof step $name" }
    if ([int]$step.exitCode -ne 0) { throw "A-BUILD-001 step $name exit=$($step.exitCode)" }
}
if (-not $info.sha256 -or -not $info.sourceCommit) { throw 'A-SRC-002 build-info missing sha256 or sourceCommit' }
$msi = Join-Path $repoRoot ('dist\' + [string]$info.msi)
if (-not (Test-Path -LiteralPath $msi)) { throw "A-SRC-002 missing $msi" }
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $msi).Hash.ToLowerInvariant()
if ($actual -ne ([string]$info.sha256).ToLowerInvariant()) { throw 'A-SRC-002 MSI sha256 mismatch' }

if (Test-Path -LiteralPath (Join-Path $payload 'hermes-agent\venv')) { throw 'A-BUILD-001 payload still contains venv' }
$modules = @(Get-ChildItem -LiteralPath (Join-Path $payload 'hermes-agent') -Directory -Recurse -Filter 'node_modules' -ErrorAction SilentlyContinue)
if ($modules.Count -gt 0) { throw 'A-BUILD-002 payload still contains node_modules' }
$browser = @(Get-ChildItem -LiteralPath (Join-Path $payload 'playwright') -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @('chrome.exe', 'headless_shell.exe') })
if ($browser.Count -eq 0) { throw 'A-BUILD-002 Chromium missing from payload\playwright' }

$evidence = Join-Path $repoRoot 'evidence'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
foreach ($id in @('A-BUILD-001', 'A-BUILD-002', 'A-SRC-002')) {
    @{ id = $id; result = 'PASS'; utc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json |
        Set-Content (Join-Path $evidence "$id.json") -Encoding UTF8
}
Write-Host 'PASS: A-BUILD-001 A-BUILD-002 A-SRC-002'
