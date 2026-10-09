param(
    [Parameter(Mandatory)]$Config,
    [Parameter(Mandatory)][string]$PayloadDir,
    [Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)][string]$SourceRef,
    [Parameter(Mandatory)][int64]$VenvEstimatedBytes
)

. (Join-Path $PSScriptRoot 'Common.ps1')

Write-Step 'Generate runtime-manifest-v2.json and detached Ed25519 signature'
if (-not $env:HERMES_MANIFEST_ED25519_SEED_B64) {
    $secretFile = Join-Path $env:USERPROFILE '.hermes-builder-secrets\HERMES_MANIFEST_ED25519_SEED_B64.txt'
    if (Test-Path -LiteralPath $secretFile) {
        $env:HERMES_MANIFEST_ED25519_SEED_B64 = (Get-Content -LiteralPath $secretFile -Raw).Trim()
    }
}
if (-not $env:HERMES_MANIFEST_ED25519_SEED_B64) {
    throw 'MANIFEST_SIGNING_KEY_MISSING'
}

$installerVersion = [string]$Config.identity.installerVersion
$agentVersion = [string]$Config.identity.agentVersion
if ($installerVersion -ne '2.0.0' -or $agentVersion -ne '0.21.0') {
    throw 'AGENT_VERSION_CHANGE_DENIED'
}
if ($SourceRef -ne [string]$Config.source.ref) {
    throw "SOURCE_REF_MISMATCH: $SourceRef"
}

$origin = [ordered]@{}
$Config.source.originUrls.psobject.Properties | ForEach-Object { $origin[$_.Name] = [string]$_.Value }
$official = [ordered]@{
    schemaVersion = 1
    distribution = 'smc-copilot-hermes'
    installUrl = [string]$Config.source.repository
    originUrls = $origin
    defaultBranch = [string]$Config.source.defaultBranch
    sourceCommit = $SourceCommit
}
Write-JsonFile $official (Join-Path $PayloadDir 'official-source.json')

$py = Join-Path $PSScriptRoot 'runtime_manifest_v2.py'
& python $py `
    --payload $PayloadDir `
    --source-commit $SourceCommit `
    --installer-version $installerVersion `
    --agent-version $agentVersion `
    --venv-estimated-bytes $VenvEstimatedBytes
if ($LASTEXITCODE -ne 0) { throw "MANIFEST_SIGNING_FAILED: python exited $LASTEXITCODE" }
