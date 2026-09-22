param(
    [Parameter(Mandatory)]$Config,
    [Parameter(Mandatory)][string]$WorkDir,
    [Parameter(Mandatory)][string]$PayloadDir,
    [string]$SourceRef = ''
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$projectRoot = Split-Path -Parent $PSScriptRoot
$repo = [string]$Config.source.repository
$configuredRef = if ($SourceRef) { $SourceRef } else { [string]$Config.source.ref }
$localRelative = [string]$Config.source.localPath
if (-not $localRelative) { throw 'source.localPath is required in local-preferred mode.' }
$sourceDir = [IO.Path]::GetFullPath((Join-Path $projectRoot $localRelative))

if (Test-Path -LiteralPath $sourceDir) {
    Write-Step 'Use local Hermes source checkout and fast-forward it from origin/main'
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir '.git'))) {
        throw "Local Hermes source exists but is not a Git checkout: $sourceDir"
    }

    $isWorkTree = (& git -C $sourceDir rev-parse --is-inside-work-tree).Trim()
    if ($LASTEXITCODE -ne 0 -or $isWorkTree -ne 'true') {
        throw "Local Hermes source is not a valid Git work tree: $sourceDir"
    }
    $branch = (& git -C $sourceDir branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $branch -ne [string]$Config.source.defaultBranch) {
        throw "Local Hermes source must be on branch '$($Config.source.defaultBranch)', found '$branch'."
    }

    Invoke-Native 'git' @('pull', '--ff-only') $sourceDir
    Invoke-Native 'git' @('submodule', 'update', '--init', '--recursive') $sourceDir
    $ref = $branch
} else {
    Write-Step 'Clone Hermes source because the local checkout is missing'
    Ensure-Directory (Split-Path -Parent $sourceDir)
    Invoke-Native 'git' @('clone', $repo, $sourceDir)
    Invoke-Native 'git' @('checkout', '--detach', $configuredRef) $sourceDir
    Invoke-Native 'git' @('submodule', 'update', '--init', '--recursive') $sourceDir
    $ref = $configuredRef
}

$commit = (& git -C $sourceDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'git rev-parse failed' }
$version = Read-ProjectVersion (Join-Path $sourceDir 'pyproject.toml')
$expected = [string]$Config.source.expectedVersion
if ($version -ne $expected) {
    throw "Source version mismatch. Expected $expected but pyproject.toml reports $version at $commit"
}

$agentDir = Join-Path $PayloadDir 'hermes-agent'
if (Test-Path $agentDir) { Remove-Item $agentDir -Recurse -Force }
Copy-Tree $sourceDir $agentDir @('.git', 'venv', '.venv', 'node_modules', '__pycache__')

[pscustomobject]@{
    Repository = $repo
    Ref = $ref
    Commit = $commit
    Version = $version
    SourceDir = $sourceDir
    AgentDir = $agentDir
}
