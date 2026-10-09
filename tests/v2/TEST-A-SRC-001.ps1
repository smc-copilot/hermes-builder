$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cfg = Get-Content (Join-Path $root 'build-config.json') -Raw | ConvertFrom-Json
if ($cfg.product.version -ne '2.0.0') { throw 'installer ProductVersion must be 2.0.0' }
if ($cfg.identity.installerVersion -ne '2.0.0') { throw 'installerVersion must be 2.0.0' }
if ($cfg.identity.agentVersion -ne '0.21.0') { throw 'agentVersion must be 0.21.0' }
if ($cfg.source.expectedVersion -ne '0.21.0') { throw 'expectedVersion must be 0.21.0' }
if ($cfg.source.ref -ne '041b6985a00d01b54f830c1607dd370007a306bf') { throw 'SOURCE_REF_MISMATCH' }
if ($cfg.source.repository -match 'smc-copilot/hermes-agent') { throw 'AGENT_VERSION_CHANGE_DENIED' }
if ($cfg.identity.autoUpdateAgent) { throw 'autoUpdateAgent must be false' }
if ($cfg.product.upgradeCode -ne '7F5E14D8-61A1-48D3-9EA5-503A84C61F6F') { throw 'UpgradeCode changed' }
Write-Host 'PASS: TEST-A-SRC-001 TEST-A-UPD-001'
