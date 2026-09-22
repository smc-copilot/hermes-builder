param(
    [Parameter(Mandatory)]$Config,
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$PayloadDir,
    [Parameter(Mandatory)][string]$AgentDir
)

. (Join-Path $PSScriptRoot 'Common.ps1')

Write-Step 'Stage enterprise templates, launchers, skills, plugins, bootstrap scripts'
Assert-EnvTemplate (Join-Path $ProjectRoot 'enterprise\config\.env.template')
$defaults = Join-Path $PayloadDir 'defaults'
Ensure-Directory $defaults
Copy-Tree (Join-Path $ProjectRoot 'enterprise\config') (Join-Path $defaults 'config')
& (Join-Path $PSScriptRoot 'Prepare-Skills.ps1') -SourceDir (Join-Path $ProjectRoot 'enterprise\skills') -DestinationDir (Join-Path $defaults 'enterprise-skills')

$enterprisePlugins = Join-Path $ProjectRoot 'enterprise\plugins'
$pluginDest = Join-Path $AgentDir 'plugins\enterprise'
Ensure-Directory $pluginDest
Copy-Tree $enterprisePlugins $pluginDest

$bin = Join-Path $PayloadDir 'bin'
Ensure-Directory $bin
Copy-Item (Join-Path $ProjectRoot 'enterprise\launchers\hermes.ps1') (Join-Path $bin 'hermes.ps1') -Force
Copy-Item (Join-Path $ProjectRoot 'enterprise\launchers\hermes.cmd') (Join-Path $bin 'hermes.cmd') -Force

$bootstrap = Join-Path $PayloadDir 'bootstrap'
Ensure-Directory $bootstrap
foreach ($name in @('Preflight-HermesInstall.ps1', 'Initialize-Hermes.ps1', 'Install-EnterpriseSkills.ps1', 'Cleanup-Hermes.ps1', 'Repair-Hermes.ps1', 'Verify-Installation.ps1')) {
    Copy-Item (Join-Path $ProjectRoot "scripts\$name") (Join-Path $bootstrap $name) -Force
}
