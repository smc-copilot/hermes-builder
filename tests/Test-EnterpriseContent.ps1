param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'build\Common.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hermes-content-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Write-Fixture {
    param([string]$Relative, [string]$Text)
    $path = Join-Path $testRoot $Relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $Text)
}

function Assert-File {
    param([string]$Relative)
    if (-not (Test-Path -LiteralPath (Join-Path $testRoot $Relative) -PathType Leaf)) {
        throw "Missing expected test file: $Relative"
    }
}

function Assert-Fails {
    param([scriptblock]$Action, [string]$Pattern)
    $caught = $false
    try { & $Action } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        $caught = $true
    }
    if (-not $caught) { throw "Expected failure matching: $Pattern" }
}

try {
    $prepare = Join-Path $projectRoot 'build\Prepare-Skills.ps1'
    $install = Join-Path $projectRoot 'scripts\Install-EnterpriseSkills.ps1'
    $fixtureSource = Join-Path $testRoot 'source'
    $fixtureHome = Join-Path $testRoot 'installed'
    $stagedSkills = Join-Path $fixtureHome 'defaults\enterprise-skills'

    Write-Fixture 'source\BaiduSearch\SKILL.md' "---`nname: baidu-search`n---`nSearch"
    Write-Fixture 'source\BaiduSearch\scripts\search.py' 'print("fixture")'
    Write-Fixture 'source\ResearchTools\HTTPReader\SKILL.md' "---`nname: http-reader`n---`nReader"
    Write-Fixture 'source\ResearchTools\DESCRIPTION.md' 'research category'
    Write-Fixture 'source\ResearchTools\HTTPReader\references\guide.md' 'reference'
    Write-Fixture 'source\BaiduSearch\__pycache__\search.pyc' 'generated'
    Write-Fixture 'installed\defaults\enterprise-skills\obsolete\SKILL.md' 'old staging'
    Write-Fixture 'installed\skills\personal\SKILL.md' 'user skill'

    & $prepare -SourceDir $fixtureSource -DestinationDir $stagedSkills
    Assert-File 'installed\defaults\enterprise-skills\baidu-search\scripts\search.py'
    Assert-File 'installed\defaults\enterprise-skills\research-tools\http-reader\references\guide.md'
    foreach ($unexpected in @('obsolete', 'BaiduSearch', 'baidu-search\__pycache__')) {
        if (Test-Path -LiteralPath (Join-Path $stagedSkills $unexpected)) { throw "Unexpected staging path: $unexpected" }
    }
    & $install -HermesHome $fixtureHome
    Assert-File 'installed\skills\baidu-search\scripts\search.py'
    Assert-File 'installed\skills\research-tools\http-reader\references\guide.md'
    Assert-File 'installed\skills\research-tools\DESCRIPTION.md'
    Assert-File 'installed\skills\personal\SKILL.md'
    if (Test-Path -LiteralPath (Join-Path $fixtureHome 'skills\enterprise')) { throw 'Unexpected enterprise layer' }
    & $install -HermesHome $fixtureHome
    if (Test-Path -LiteralPath (Join-Path $fixtureHome 'skills\research-tools\research-tools')) { throw 'Repeated installation nested a category' }

    Write-Fixture 'collision\BaiduSearch\SKILL.md' 'first'
    Write-Fixture 'collision\baidu-search\SKILL.md' 'second'
    Assert-Fails { & $prepare -SourceDir (Join-Path $testRoot 'collision') -DestinationDir $stagedSkills } 'collision'
    Assert-File 'installed\defaults\enterprise-skills\baidu-search\scripts\search.py'
    Write-Fixture 'deep\research\nested\BaiduSearch\SKILL.md' 'too deep'
    Assert-Fails { & $prepare -SourceDir (Join-Path $testRoot 'deep') -DestinationDir $stagedSkills } 'depth 1 or 2'

    # Values are opaque defaults, including empty, quoted and non-working values.
    Write-Fixture 'valid.env' "# defaults`nBAIDU_API_KEY=`nSMC_KB_API_URL=not-a-url`nexport SMC_KB_API_TOKEN='fixture value'`n"
    Assert-EnvTemplate (Join-Path $testRoot 'valid.env')
    Write-Fixture 'invalid.env' 'INVALID-NAME=value'
    Assert-Fails { Assert-EnvTemplate (Join-Path $testRoot 'invalid.env') } 'line 1'

    # Run the real staging entrypoint against today's enterprise files. This
    # copies template bytes but does not execute plugins or contact services.
    $realStage = Join-Path $testRoot 'real-stage'
    $config = Get-Content (Join-Path $projectRoot 'build-config.json') -Raw | ConvertFrom-Json
    & (Join-Path $projectRoot 'build\Prepare-EnterpriseContent.ps1') -Config $config -ProjectRoot $projectRoot -PayloadDir $realStage -AgentDir (Join-Path $realStage 'hermes-agent')
    $sourceHash = Get-Sha256 (Join-Path $projectRoot 'enterprise\config\.env.template')
    $stagedHash = Get-Sha256 (Join-Path $realStage 'defaults\config\.env.template')
    if ($sourceHash -ne $stagedHash) { throw 'Environment template values were changed while staging' }
    Assert-File 'real-stage\defaults\enterprise-skills\baidu-search\SKILL.md'
    Assert-File 'real-stage\bootstrap\Install-EnterpriseSkills.ps1'
    & (Join-Path $realStage 'bootstrap\Install-EnterpriseSkills.ps1') -HermesHome $realStage
    Assert-File 'real-stage\skills\baidu-search\scripts\search.py'
    $expectedSkills = @(Get-ChildItem (Join-Path $projectRoot 'enterprise\skills') -Recurse -File -Filter SKILL.md).Count
    $installedSkills = @(Get-ChildItem (Join-Path $realStage 'skills') -Recurse -File -Filter SKILL.md).Count
    if ($expectedSkills -ne $installedSkills) { throw 'Actual enterprise skill package count changed during staging/install' }
    Write-Host "Installed enterprise skill packages in test: $installedSkills"

    Write-Host 'PASS: skill paths, naming, collision/depth checks, repeat install, user-file preservation and env template staging'
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notlike 'hermes-content-test-*') { throw 'Unsafe test cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
exit 0
