param(
    [string]$ConfigPath = '',
    [string]$SourceRef = '',
    [switch]$KeepWorkDir,
    [switch]$SkipMsi,
    [switch]$DevelopmentMode
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
    $sourceArgs = @{
        Config = $config
        WorkDir = $workDir
        PayloadDir = $payloadDir
        SourceRef = $SourceRef
    }
    if ($DevelopmentMode) { $sourceArgs.DevelopmentMode = $true }
    $source = & (Join-Path $PSScriptRoot 'Prepare-Source.ps1') @sourceArgs
    if ($source.Unreleasable -and -not $DevelopmentMode) {
        throw 'SOURCE_REF_MISMATCH: unreleasable source reached a release build'
    }
    & (Join-Path $PSScriptRoot 'Prepare-Runtime.ps1') -Config $config -PayloadDir $payloadDir -AgentDir $source.AgentDir
    $offlineResult = & (Join-Path $PSScriptRoot 'Prepare-OfflineDependencies.ps1') -Config $config -PayloadDir $payloadDir -AgentDir $source.AgentDir -SourceCommit $source.Commit
    $offlineProof = @($offlineResult | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'steps' }) | Select-Object -Last 1
    if (-not $offlineProof -or @($offlineProof.steps).Count -lt 4) {
        throw 'OFFLINE_REBUILD_FAILED: Build Gate did not return offlineProof'
    }
    foreach ($step in @($offlineProof.steps)) {
        if ([int]$step.exitCode -ne 0) {
            throw "OFFLINE_REBUILD_FAILED: step $($step.name) exited $($step.exitCode)"
        }
    }
    & (Join-Path $PSScriptRoot 'Prepare-EnterpriseContent.ps1') -Config $config -ProjectRoot $projectRoot -PayloadDir $payloadDir -AgentDir $source.AgentDir

    $installerVersion = [string]$config.identity.installerVersion
    $agentVersion = [string]$config.identity.agentVersion
    if ($installerVersion -ne '2.0.0' -or $agentVersion -ne '0.21.0') { throw 'AGENT_VERSION_CHANGE_DENIED' }
    if ([string]$config.product.version -ne $installerVersion) { throw 'AGENT_VERSION_CHANGE_DENIED' }
    if ([string]$config.source.repository -match 'smc-copilot/hermes-agent') { throw 'AGENT_VERSION_CHANGE_DENIED' }

    Write-Step 'Compile HermesRuntimeInit.exe before the payload tree is frozen'
    $cargo = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
    if (-not (Test-Path -LiteralPath $cargo)) { throw 'BUNDLE_INCOMPLETE: cargo is not installed' }
    Invoke-Native $cargo @('build', '-p', 'installer-cli', '--release') $projectRoot
    $initExe = Join-Path $projectRoot 'target\release\HermesRuntimeInit.exe'
    if (-not (Test-Path -LiteralPath $initExe)) { throw 'BUNDLE_INCOMPLETE: HermesRuntimeInit.exe was not produced' }
    $bootstrapDir = Join-Path $payloadDir 'bootstrap'
    New-Item -ItemType Directory -Path $bootstrapDir -Force | Out-Null
    Copy-Item -LiteralPath $initExe -Destination (Join-Path $bootstrapDir 'HermesRuntimeInit.exe') -Force

    $venvEstimated = [int64]$offlineProof.venvEstimatedBytes
    & (Join-Path $PSScriptRoot 'Generate-Manifest.ps1') -Config $config -PayloadDir $payloadDir -SourceCommit $source.Commit -SourceRef $source.Ref -VenvEstimatedBytes $venvEstimated

    if (-not $SkipMsi) {
        Write-Step 'Build single per-user Files-Only MSI with WiX Toolset 5'
        $wixProject = Join-Path $projectRoot 'installer\HermesEnterprise.Setup.wixproj'
        $payloadEscaped = $payloadDir
        Invoke-Native 'dotnet' @(
            'build', $wixProject,
            '-c', [string]$config.build.configuration,
            "-p:ProductVersion=$installerVersion",
            "-p:PayloadDir=$payloadEscaped"
        ) $projectRoot

        $msi = Get-ChildItem (Join-Path $projectRoot 'installer\bin') -Recurse -Filter '*.msi' |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if (-not $msi) { throw 'WiX build completed but no MSI was found under installer/bin.' }
        $finalName = "Hermes-Core-$installerVersion-win-x64.msi"
        $finalMsi = Join-Path $distDir $finalName
        Copy-Item $msi.FullName $finalMsi -Force
        $sha = Get-Sha256 $finalMsi
        "$sha  $finalName" | Set-Content -LiteralPath "$finalMsi.sha256" -Encoding ASCII

        $runtimeManifestPath = Join-Path $payloadDir 'runtime-manifest-v2.json'
        $runtimeManifest = Get-Content -LiteralPath $runtimeManifestPath -Raw | ConvertFrom-Json
        if ([int64]$runtimeManifest.uncompressedPayloadBytes -le 0 -or [int64]$runtimeManifest.venvEstimatedBytes -le 0) {
            throw 'BUNDLE_INCOMPLETE: manifest sizes must be > 0'
        }
        $release = [ordered]@{
            schemaVersion = 2
            installerVersion = $installerVersion
            msiProductVersion = $installerVersion
            msiUpgradeCode = [string]$config.product.upgradeCode
            msiSha256 = $sha
            source = [ordered]@{
                repository = [string]$source.Repository
                commit = [string]$source.Commit
                agentVersion = $agentVersion
            }
            runtime = [ordered]@{
                pythonVersion = [string]$config.python.version
                architecture = 'x64'
                offline = $true
                payloadTreeSha256 = [string]$runtimeManifest.payloadTreeSha256
                uncompressedPayloadBytes = [int64]$runtimeManifest.uncompressedPayloadBytes
                venvEstimatedBytes = [int64]$runtimeManifest.venvEstimatedBytes
            }
            policy = [ordered]@{
                autoUpdateAgent = $false
                requiresInteractiveUser = $true
            }
        }
        $releasePath = Join-Path $distDir 'release-manifest-v2.json'
        Write-JsonFile $release $releasePath

        Write-Step 'Compile Hermes-Setup.exe with the Core MSI embedded'
        $env:HERMES_RELEASE_MANIFEST = $releasePath
        Invoke-Native $cargo @('build', '--release', '--manifest-path', (Join-Path $projectRoot 'installer-ui\src-tauri\Cargo.toml')) $projectRoot
        $setupBuilt = Join-Path $projectRoot 'installer-ui\src-tauri\target\release\hermes-setup.exe'
        if (-not (Test-Path -LiteralPath $setupBuilt)) { throw 'BUNDLE_INCOMPLETE: Hermes-Setup.exe was not produced' }
        $setupName = "Hermes-Setup-$installerVersion-win-x64.exe"
        $setupFinal = Join-Path $distDir $setupName
        Copy-Item -LiteralPath $setupBuilt -Destination $setupFinal -Force
        Add-MsiOverlay -SetupPath $setupFinal -MsiPath $finalMsi
        $setupSha = Get-Sha256 $setupFinal
        "$setupSha  $setupName" | Set-Content -LiteralPath "$setupFinal.sha256" -Encoding ASCII

        $buildInfo = [ordered]@{
            schemaVersion = 2
            installerVersion = $installerVersion
            productVersion = $installerVersion
            agentVersion = $agentVersion
            hermesVersion = $source.Version
            sourceRepository = $source.Repository
            sourceRef = $source.Ref
            sourceCommit = $source.Commit
            architecture = 'x64'
            installScope = 'per-user'
            authenticodeRequired = $false
            msi = $finalName
            sha256 = $sha
            setup = $setupName
            setupSha256 = $setupSha
            unreleasable = [bool]$source.Unreleasable
            offlineProof = $offlineProof
            venvEstimatedBytes = [int64]$runtimeManifest.venvEstimatedBytes
            uncompressedPayloadBytes = [int64]$runtimeManifest.uncompressedPayloadBytes
            builtAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        Write-JsonFile $buildInfo (Join-Path $distDir 'build-info.json')
        Write-Host "`nMSI: $finalMsi" -ForegroundColor Green
        Write-Host "SHA256: $sha" -ForegroundColor Green
        Write-Host "Setup: $setupFinal" -ForegroundColor Green
    } else {
        Write-Host "Payload prepared at: $payloadDir" -ForegroundColor Green
    }
} finally {
    $keep = $KeepWorkDir -or [bool]$config.build.keepWorkDir
    if (-not $keep -and (Test-Path $workDir)) { Remove-Item $workDir -Recurse -Force }
}
