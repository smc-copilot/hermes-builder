$ErrorActionPreference = 'Stop'
$required = @(
    'A-SRC-001','A-BUILD-001','A-BUILD-002','A-UPD-001','A-MSI-001','A-MSI-002','A-ENTRY-001',
    'A-PRE-001','A-PRE-002','A-GW-001','A-PY-001','A-PY-002','A-TXN-001','A-TXN-002',
    'A-OWN-001','A-OWN-002','A-SKILL-001','A-ENV-001','A-OBS-001','A-OBS-002','A-SEC-001','A-SEC-002',
    'A-REPAIR-001','A-REPAIR-002','A-UI-001','A-MIG-001','A-CI-001','A-CI-002'
)
if ($required.Count -ne 28) { throw 'Required AC count drifted' }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$evidenceRoot = Join-Path $root 'evidence\v2'
$failed = @()
foreach ($id in $required) {
    $path = Join-Path $evidenceRoot "$id.json"
    if (-not (Test-Path -LiteralPath $path)) {
        $failed += "$id=BLOCKED"
        continue
    }
    $doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($doc.status -ne 'PASS' -or $doc.oracle.pass -ne $true) { $failed += "$id=$($doc.status)" }
    if ($id -eq 'A-CI-001' -and [string]$doc.platform.os -notmatch 'Windows 10') { $failed += 'A-CI-001=GOLDEN_CONSUMER_BLOCKED' }
}
if ($failed.Count -gt 0) {
    Write-Host ("GOLDEN_CONSUMER_BLOCKED " + ($failed -join ', '))
    exit 2
}
Write-Host 'PASS: release gate'
exit 0
