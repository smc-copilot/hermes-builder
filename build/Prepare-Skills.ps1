param(
    [Parameter(Mandatory)][string]$SourceDir,
    [Parameter(Mandatory)][string]$DestinationDir
)

. (Join-Path $PSScriptRoot 'Common.ps1')

function ConvertTo-SkillName {
    param([string]$Name)
    $slug = [regex]::Replace($Name, '([A-Z]+)([A-Z][a-z])', '$1-$2')
    $slug = [regex]::Replace($slug, '([a-z0-9])([A-Z])', '$1-$2')
    $slug = [regex]::Replace($slug, '[\s_]+', '-').ToLowerInvariant()
    $slug = [regex]::Replace($slug, '-+', '-').Trim('-')
    if ($slug -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$' -or
        $slug -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])$') {
        throw "Invalid skill/category directory name: $Name"
    }
    return $slug
}

# Validate the entire mapping before replacing the generated staging tree.
# A root child is either a package (SKILL.md) or a category of packages.
$packages = @()
$categories = @()
$roots = @{}
$targets = @{}
foreach ($entry in Get-ChildItem -LiteralPath $SourceDir -Directory -Force) {
    $rootName = ConvertTo-SkillName $entry.Name
    if ($roots.ContainsKey($rootName)) { throw "Skill/category name collision: $rootName" }
    $roots[$rootName] = $true
    $isPackage = Test-Path -LiteralPath (Join-Path $entry.FullName 'SKILL.md') -PathType Leaf
    if (-not $isPackage) { $categories += [pscustomobject]@{ Source = $entry.FullName; Relative = $rootName } }
    $children = if ($isPackage) { @($entry) } else { @(Get-ChildItem -LiteralPath $entry.FullName -Directory -Force) }
    foreach ($package in $children) {
        if (-not (Test-Path -LiteralPath (Join-Path $package.FullName 'SKILL.md') -PathType Leaf)) {
            throw "Expected a complete skill package at depth 1 or 2: $($package.FullName)"
        }
        $relative = if ($isPackage) { $rootName } else { Join-Path $rootName (ConvertTo-SkillName $package.Name) }
        if ($targets.ContainsKey($relative)) { throw "Skill name collision: $relative" }
        $targets[$relative] = $true
        $packages += [pscustomobject]@{ Source = $package.FullName; Relative = $relative }
    }
}

Reset-Directory $DestinationDir
# Preserve category descriptions and root documentation alongside the packages.
foreach ($container in (@([pscustomobject]@{ Source = $SourceDir; Relative = '' }) + $categories)) {
    $target = if ($container.Relative) { Join-Path $DestinationDir $container.Relative } else { $DestinationDir }
    Ensure-Directory $target
    Get-ChildItem -LiteralPath $container.Source -File -Force | Where-Object { $_.Extension -ne '.pyc' } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
}
foreach ($package in $packages) {
    Copy-Tree $package.Source (Join-Path $DestinationDir $package.Relative) @('.git', '__pycache__') @('*.pyc')
}
