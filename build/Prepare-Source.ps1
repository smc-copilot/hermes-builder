param(
    [Parameter(Mandatory)]$Config,
    [Parameter(Mandatory)][string]$WorkDir,
    [Parameter(Mandatory)][string]$PayloadDir,
    [string]$SourceRef = '',
    [switch]$DevelopmentMode
)

. (Join-Path $PSScriptRoot 'Common.ps1')

$projectRoot = Split-Path -Parent $PSScriptRoot
$repo = [string]$Config.source.repository
$configuredRef = if ($SourceRef) { $SourceRef } else { [string]$Config.source.ref }
$localRelative = [string]$Config.source.localPath
if (-not $localRelative) { throw 'source.localPath is required in local-preferred mode.' }
$sourceDir = [IO.Path]::GetFullPath((Join-Path $projectRoot $localRelative))
$unreleasable = $false

function Get-GitHead {
    param([Parameter(Mandatory)][string]$Dir)
    $head = (& git -C $Dir rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $head) { throw 'SOURCE_REF_MISMATCH: git rev-parse failed' }
    return $head
}

function Get-PorcelainPath {
    param([Parameter(Mandatory)][string]$Line)
    $rest = $Line.Substring(3)
    if ($rest -match ' -> ') { $rest = ($rest -split ' -> ', 2)[-1] }
    return $rest.Trim('"')
}

function Test-GitCaseCollision {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][string]$Relative
    )
    $norm = $Relative.Replace('\', '/').ToLowerInvariant()
    $tracked = @(& git -C $Dir ls-files)
    $hits = @($tracked | Where-Object { $_.Replace('\', '/').ToLowerInvariant() -eq $norm })
    return $hits.Count -gt 1
}

function Assert-SourceClean {
    param([Parameter(Mandatory)][string]$Dir)
    $porcelain = (& git -C $Dir status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw 'SOURCE_DIRTY: git status failed' }
    $dirty = @()
    foreach ($line in @($porcelain | Where-Object { $_ -and $_.Trim() })) {
        $rel = Get-PorcelainPath $line
        if (Test-GitCaseCollision -Dir $Dir -Relative $rel) {
            Write-Host "Ignoring Windows case-collision dirty path: $rel" -ForegroundColor Yellow
            continue
        }
        $dirty += $line
    }
    if ($dirty.Count -gt 0) {
        throw "SOURCE_DIRTY: work tree is not clean ($($dirty.Count) entries)"
    }
    $submodules = (& git -C $Dir submodule status --recursive)
    if ($LASTEXITCODE -ne 0) { throw 'SOURCE_DIRTY: git submodule status failed' }
    foreach ($line in @($submodules | Where-Object { $_ })) {
        if ($line.Length -gt 0 -and $line[0] -ne ' ') {
            throw "SOURCE_DIRTY: submodule is not clean: $($line.Trim())"
        }
    }
}

if (Test-Path -LiteralPath $sourceDir) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir '.git'))) {
        throw "Local Hermes source exists but is not a Git checkout: $sourceDir"
    }
    $isWorkTree = (& git -C $sourceDir rev-parse --is-inside-work-tree).Trim()
    if ($LASTEXITCODE -ne 0 -or $isWorkTree -ne 'true') {
        throw "Local Hermes source is not a valid Git work tree: $sourceDir"
    }

    if ($DevelopmentMode) {
        Write-Step 'DevelopmentMode: fast-forward local Hermes source from origin/main (unreleasable)'
        $branch = (& git -C $sourceDir branch --show-current).Trim()
        if ($LASTEXITCODE -ne 0 -or $branch -ne [string]$Config.source.defaultBranch) {
            throw "Local Hermes source must be on branch '$($Config.source.defaultBranch)', found '$branch'."
        }
        Invoke-Native 'git' @('pull', '--ff-only') $sourceDir
        Invoke-Native 'git' @('submodule', 'update', '--init', '--recursive') $sourceDir
        $ref = $branch
        $unreleasable = $true
    } else {
        Write-Step "Release source pin: require HEAD == $configuredRef and a clean work tree"
        if ($configuredRef -notmatch '^[a-f0-9]{40}$') {
            throw "SOURCE_REF_MISMATCH: release source.ref must be a 40-char lowercase SHA, found '$configuredRef'"
        }
        $head = Get-GitHead $sourceDir
        if ($head -ne $configuredRef) {
            throw "SOURCE_REF_MISMATCH: HEAD $head != source.ref $configuredRef"
        }
        Assert-SourceClean $sourceDir
        $ref = $configuredRef
    }
} else {
    Write-Step 'Clone Hermes source because the local checkout is missing'
    Ensure-Directory (Split-Path -Parent $sourceDir)
    Invoke-Native 'git' @('clone', $repo, $sourceDir)
    Invoke-Native 'git' @('checkout', '--detach', $configuredRef) $sourceDir
    Invoke-Native 'git' @('submodule', 'update', '--init', '--recursive') $sourceDir
    $head = Get-GitHead $sourceDir
    if (-not $DevelopmentMode -and $head -ne $configuredRef) {
        throw "SOURCE_REF_MISMATCH: cloned HEAD $head != source.ref $configuredRef"
    }
    if (-not $DevelopmentMode) { Assert-SourceClean $sourceDir }
    $ref = $configuredRef
    if ($DevelopmentMode) { $unreleasable = $true }
}

$commit = Get-GitHead $sourceDir
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
    Unreleasable = $unreleasable
}
