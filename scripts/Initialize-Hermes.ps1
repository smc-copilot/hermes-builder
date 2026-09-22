param(
    [string]$HermesHome = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { "$env:LOCALAPPDATA\hermes" }),
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Add-UserPathEntry {
    param([Parameter(Mandatory)][string]$Entry)
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($current) { $parts = @($current -split ';' | Where-Object { $_ -and $_.Trim() }) }
    if (-not ($parts | Where-Object { $_.TrimEnd('\\') -ieq $Entry.TrimEnd('\\') })) {
        $newPath = (($parts + $Entry) -join ';')
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    }
}

function Copy-IfMissing {
    param([string]$Source, [string]$Destination)
    if ((Test-Path $Source) -and -not (Test-Path $Destination)) {
        Copy-Item -LiteralPath $Source -Destination $Destination
    }
}

$initLog = Join-Path $env:TEMP 'hermes-msi-initialize.log'
try { Start-Transcript -Path $initLog -Force | Out-Null } catch { }
Write-Host "Initializing Hermes at $HermesHome (log: $initLog)"
$agent = Join-Path $HermesHome 'hermes-agent'
$offline = Join-Path $HermesHome 'offline'
$settingsPath = Join-Path $offline 'bundle-settings.json'
$uv = Join-Path $HermesHome 'bin\uv.exe'
$venv = Join-Path $agent 'venv'
$marker = Join-Path $HermesHome 'state\bundle-install.json'

foreach ($required in @($agent, $settingsPath, $uv)) {
    if (-not (Test-Path $required)) { throw "Required bundle path is missing: $required" }
}
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json

$env:HERMES_HOME = $HermesHome
$env:UV_CACHE_DIR = Join-Path $offline 'uv-cache'
$env:UV_PROJECT_ENVIRONMENT = $venv
$env:UV_PYTHON_INSTALL_DIR = Join-Path $HermesHome 'python'
$env:NO_COLOR = '1'
$pythonExe = if ($settings.pythonExecutable) {
    Join-Path $HermesHome ([string]$settings.pythonExecutable)
} else {
    Get-ChildItem (Join-Path $HermesHome 'python') -Recurse -Filter 'python.exe' -File -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } | Select-Object -First 1 | ForEach-Object { $_.FullName }
}
if (-not $pythonExe -or -not (Test-Path $pythonExe)) { throw "Packaged Python executable not found: $pythonExe" }

[Environment]::SetEnvironmentVariable('HERMES_HOME', $HermesHome, 'User')
$gitBash = Join-Path $HermesHome 'git\bin\bash.exe'
if (Test-Path $gitBash) {
    [Environment]::SetEnvironmentVariable('HERMES_GIT_BASH_PATH', $gitBash, 'User')
}
Add-UserPathEntry (Join-Path $HermesHome 'bin')

$needsSync = $Force -or -not (Test-Path (Join-Path $venv 'Scripts\hermes.exe'))
if (-not $needsSync -and (Test-Path $marker)) {
    try {
        $installed = Get-Content $marker -Raw | ConvertFrom-Json
        if ([string]$installed.sourceCommit -ne [string]$settings.sourceCommit) { $needsSync = $true }
    } catch { $needsSync = $true }
} elseif (-not (Test-Path $marker)) {
    $needsSync = $true
}

if ($needsSync) {
    Write-Host 'Creating/updating Python venv from packaged uv cache (offline, locked)...'
    $args = @('sync', '--offline', '--locked', '--python', $pythonExe)
    foreach ($extra in $settings.extras) { $args += @('--extra', [string]$extra) }
    Push-Location $agent
    try {
        & $uv @args
        if ($LASTEXITCODE -ne 0) { throw "uv sync failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

# Recreate Node dependencies at the final per-user path from the packaged npm
# cache. This avoids shipping build-path-bound workspace junctions while still
# guaranteeing no registry download on the endpoint. Playwright Chromium was
# already staged into %HERMES_HOME%\playwright at build time.
$nodeExe = Join-Path $HermesHome 'node\node.exe'
$installScript = Join-Path $agent 'scripts\install.ps1'
if ((Test-Path $nodeExe) -and (Test-Path $installScript)) {
    $oldNodeEnv = @{
        PATH = $env:Path
        npm_config_cache = $env:npm_config_cache
        npm_config_offline = $env:npm_config_offline
        npm_config_prefer_offline = $env:npm_config_prefer_offline
        PLAYWRIGHT_BROWSERS_PATH = $env:PLAYWRIGHT_BROWSERS_PATH
    }
    try {
        $env:Path = (Join-Path $HermesHome 'node') + ';' + (Join-Path $HermesHome 'bin') + ';' + $env:Path
        $env:npm_config_cache = Join-Path $HermesHome ([string]$settings.npmCache)
        $env:npm_config_offline = 'true'
        $env:npm_config_prefer_offline = 'true'
        $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $HermesHome ([string]$settings.playwrightBrowsersPath)
        Write-Host 'Installing Node dependencies from packaged npm cache (offline)...'
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installScript `
            -HermesHome $HermesHome -InstallDir $agent -Stage 'node-deps' -NonInteractive -SkipSetup
        if ($LASTEXITCODE -ne 0) { throw "Offline node-deps initialization failed with $LASTEXITCODE" }
    } finally {
        $env:Path = $oldNodeEnv.PATH
        $env:npm_config_cache = $oldNodeEnv.npm_config_cache
        $env:npm_config_offline = $oldNodeEnv.npm_config_offline
        $env:npm_config_prefer_offline = $oldNodeEnv.npm_config_prefer_offline
        $env:PLAYWRIGHT_BROWSERS_PATH = $oldNodeEnv.PLAYWRIGHT_BROWSERS_PATH
    }
}

$defaults = Join-Path $HermesHome 'defaults\config'
Copy-IfMissing (Join-Path $defaults '.env.template') (Join-Path $HermesHome '.env')
Copy-IfMissing (Join-Path $defaults 'config.yaml.template') (Join-Path $HermesHome 'config.yaml')
Copy-IfMissing (Join-Path $defaults 'SOUL.md.template') (Join-Path $HermesHome 'SOUL.md')

& (Join-Path $PSScriptRoot 'Install-EnterpriseSkills.ps1') -HermesHome $HermesHome

$stateDir = Join-Path $HermesHome 'state'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$markerData = [ordered]@{
    schemaVersion = 1
    hermesVersion = [string]$settings.hermesVersion
    sourceCommit = [string]$settings.sourceCommit
    initializedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$markerData | ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8

$hermesExe = Join-Path $venv 'Scripts\hermes.exe'
if (-not (Test-Path $hermesExe)) { throw "Hermes executable missing after offline sync: $hermesExe" }
Write-Host 'Hermes initialization complete.'
try { Stop-Transcript | Out-Null } catch { }
