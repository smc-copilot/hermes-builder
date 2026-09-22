param(
    [Parameter(Mandatory)]$Config,
    [Parameter(Mandatory)][string]$PayloadDir,
    [Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)][string]$SourceRef
)

. (Join-Path $PSScriptRoot 'Common.ps1')

Write-Step 'Generate runtime-manifest.json and official-source.json'
$keyFiles = @(
    'bin\uv.exe',
    'bin\rg.exe',
    'bin\ffmpeg.exe',
    'bin\ffprobe.exe',
    'node\node.exe',
    'hermes-agent\pyproject.toml',
    'hermes-agent\uv.lock',
    'offline\bundle-settings.json'
)
$hashes = [ordered]@{}
foreach ($relative in $keyFiles) {
    $full = Join-Path $PayloadDir $relative
    if (Test-Path $full) { $hashes[$relative] = Get-Sha256 $full }
}

$manifest = [ordered]@{
    schemaVersion = 1
    product = [string]$Config.product.name
    productVersion = [string]$Config.product.version
    hermesVersion = [string]$Config.source.expectedVersion
    repository = [string]$Config.source.repository
    sourceRef = $SourceRef
    sourceCommit = $SourceCommit
    architecture = [string]$Config.target.architecture
    installScope = 'per-user'
    installRoot = [string]$Config.target.installRoot
    pythonVersion = [string]$Config.python.version
    extras = @($Config.python.extras | ForEach-Object { [string]$_ })
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    hashes = $hashes
}
Write-JsonFile $manifest (Join-Path $PayloadDir 'runtime-manifest.json')

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
