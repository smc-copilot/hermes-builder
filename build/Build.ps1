param(
    [string]$ConfigPath = '',
    [string]$SourceRef = '',
    [switch]$KeepWorkDir,
    [switch]$SkipMsi
)

. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Windows

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ConfigPath) { $ConfigPath = Join-Path $projectRoot 'build-config.json' }
$ConfigPath = (Resolve-Path $ConfigPath).Path
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

if ([string]$config.source.mode -ne 'local-preferred') { throw 'This project requires local-preferred source mode.' }
if ([string]$config.target.architecture -ne 'x64') { throw 'v1.0 build pipeline currently supports Windows x64 only.' }
if ($config.target.includeDesktop) { throw 'Core MSI v1.0 intentionally rejects includeDesktop=true. Build a separate Desktop SKU.' }
if ($config.target.includePlatformSdks) { throw 'Core MSI v1.0 intentionally rejects includePlatformSdks=true. Build a separate Full SKU after license/relocation validation.' }

$workDir = Join-Path $projectRoot ([string]$config.build.workDir)
$payloadDir = Join-Path $projectRoot 'payload'
$distDir = Join-Path $projectRoot ([string]$config.build.distDir)
Reset-Directory $workDir
Reset-Directory $payloadDir
Reset-Directory $distDir

try {
    $source = & (Join-Path $PSScriptRoot 'Prepare-Source.ps1') -Config $config -WorkDir $workDir -PayloadDir $payloadDir -SourceRef $SourceRef
    & (Join-Path $PSScriptRoot 'Prepare-Runtime.ps1') -Config $config -PayloadDir $payloadDir -AgentDir $source.AgentDir
    & (Join-Path $PSScriptRoot 'Prepare-OfflineDependencies.ps1') -Config $config -PayloadDir $payloadDir -AgentDir $source.AgentDir -SourceCommit $source.Commit
    & (Join-Path $PSScriptRoot 'Prepare-EnterpriseContent.ps1') -Config $config -ProjectRoot $projectRoot -PayloadDir $payloadDir -AgentDir $source.AgentDir
    & (Join-Path $PSScriptRoot 'Generate-Manifest.ps1') -Config $config -PayloadDir $payloadDir -SourceCommit $source.Commit -SourceRef $source.Ref

    if (-not $SkipMsi) {
        Write-Step 'Build single per-user MSI with WiX Toolset 4'
        $wixProject = Join-Path $projectRoot 'installer\HermesEnterprise.Setup.wixproj'
        $payloadEscaped = $payloadDir
        $version = [string]$config.product.version
        Invoke-Native 'dotnet' @(
            'build', $wixProject,
            '-c', [string]$config.build.configuration,
            "-p:ProductVersion=$version",
            "-p:PayloadDir=$payloadEscaped"
        ) $projectRoot

        $msi = Get-ChildItem (Join-Path $projectRoot 'installer\bin') -Recurse -Filter '*.msi' |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if (-not $msi) { throw 'WiX build completed but no MSI was found under installer/bin.' }
        $finalName = "copilot-hermes-enterprise-$version-win-x64.msi"
        $finalMsi = Join-Path $distDir $finalName
        Copy-Item $msi.FullName $finalMsi -Force
        $sha = Get-Sha256 $finalMsi
        "$sha  $finalName" | Set-Content -LiteralPath "$finalMsi.sha256" -Encoding ASCII

        $buildInfo = [ordered]@{
            schemaVersion = 1
            productVersion = $version
            hermesVersion = $source.Version
            sourceRepository = $source.Repository
            sourceRef = $source.Ref
            sourceCommit = $source.Commit
            architecture = 'x64'
            installScope = 'per-user'
            msi = $finalName
            sha256 = $sha
            builtAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        Write-JsonFile $buildInfo (Join-Path $distDir 'build-info.json')
        Write-Host "`nMSI: $finalMsi" -ForegroundColor Green
        Write-Host "SHA256: $sha" -ForegroundColor Green
    } else {
        Write-Host "Payload prepared at: $payloadDir" -ForegroundColor Green
    }
} finally {
    $keep = $KeepWorkDir -or [bool]$config.build.keepWorkDir
    if (-not $keep -and (Test-Path $workDir)) { Remove-Item $workDir -Recurse -Force }
}
