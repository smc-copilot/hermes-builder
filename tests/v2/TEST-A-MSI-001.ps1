$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$wxs = Get-Content (Join-Path $root 'installer\Package.wxs') -Raw
foreach ($forbidden in @('InitializeHermes', 'PreflightHermes', 'CleanupHermes', 'WixQuietExec', 'uv.exe')) {
    if ($wxs -match [regex]::Escape($forbidden)) { throw "MSI still contains $forbidden" }
}
foreach ($required in @('Scope="perUser"', '7F5E14D8-61A1-48D3-9EA5-503A84C61F6F', 'S-1-5-18', 'PayloadDir')) {
    if ($wxs -notmatch [regex]::Escape($required)) { throw "MSI missing $required" }
}
$stage = Get-Content (Join-Path $root 'build\Prepare-EnterpriseContent.ps1') -Raw
if ($stage -match 'Initialize-Hermes.ps1') { throw 'payload staging still copies Initialize-Hermes.ps1' }
Write-Host 'PASS: TEST-A-MSI-001'
