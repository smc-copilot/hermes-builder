param(
    [string]$HermesHome = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { "$env:LOCALAPPDATA\hermes" }),
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# MSI directory properties end with '\'; QuietExec passes "[HermesRoot]." — normalize.
$HermesHome = [IO.Path]::GetFullPath(($HermesHome.Trim().Trim('"').Trim("'")))
$HermesHome = $HermesHome.TrimEnd('\')

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

function Restore-HermesAgentFromBrokenBackup {
    param(
        [Parameter(Mandatory)][string]$HermesHome,
        [Parameter(Mandatory)][string]$HermesAgentHome
    )
    $pyproject = Join-Path $HermesAgentHome 'pyproject.toml'
    if (Test-Path -LiteralPath $pyproject) { return $false }

    # Upstream install.ps1 Install-Repository moves an "invalid git repo" aside as
    # hermes-agent.broken-* then tries to git clone. MSI payload has no usable
    # .git; that path destroys the offline tree and can leave a .git-only stub
    # (or a half-finished clone). Recover the newest backup that still has
    # pyproject.toml.
    $backup = Get-ChildItem -LiteralPath $HermesHome -Directory -Filter 'hermes-agent.broken-*' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'pyproject.toml') } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $backup) { return $false }

    Write-InstallLog "hermes-agent is incomplete (missing pyproject.toml); restoring from $($backup.Name)"
    Write-InstallLog 'Tip: do not run install.ps1 repository/update against an MSI install; it renames the payload tree to hermes-agent.broken-*.'

    # Drop locks from gateway / half-finished git clone into hermes-agent.
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and (
            $_.CommandLine -match [regex]::Escape($HermesAgentHome) -or
            $_.CommandLine -match 'hermes_cli\.main gateway' -or
            ($_.CommandLine -match 'git .*clone' -and $_.CommandLine -match 'hermes-agent')
        )
    } | ForEach-Object {
        Write-InstallLog "Stopping locking process PID=$($_.ProcessId) Name=$($_.Name)"
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1

    if (Test-Path -LiteralPath $HermesAgentHome) {
        $stubBackup = Join-Path $HermesHome ('hermes-agent.incomplete-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        try {
            Move-Item -LiteralPath $HermesAgentHome -Destination $stubBackup -Force -ErrorAction Stop
            Write-InstallLog "Moved incomplete hermes-agent aside to $stubBackup"
        } catch {
            Write-InstallLog "Move-Item failed ($_); forcing remove of incomplete hermes-agent"
            cmd.exe /c "rd /s /q `"$HermesAgentHome`"" | Out-Null
            if (Test-Path -LiteralPath $HermesAgentHome) {
                throw "Could not clear incomplete hermes-agent (in use). Close hermes gateway/git and retry. $_"
            }
        }
    }
    Move-Item -LiteralPath $backup.FullName -Destination $HermesAgentHome -Force
    Write-InstallLog "Restored HermesAgentHome from $($backup.Name)"
    return $true
}

$logsDir = Join-Path $HermesHome 'logs'
$installLog = Join-Path $logsDir 'install.log'
$initLog = Join-Path $env:TEMP 'hermes-msi-initialize.log'
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
function Write-InstallLog([string]$Message) {
    $line = '{0} [initialize] {1}' -f (Get-Date -Format 'o'), $Message
    Add-Content -LiteralPath $installLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Host $line
}
try { Start-Transcript -Path $initLog -Force | Out-Null } catch { }
Write-InstallLog "Initializing Hermes at $HermesHome (transcript: $initLog, install.log: $installLog)"
$HermesAgentHome = Join-Path $HermesHome 'hermes-agent'
$offline = Join-Path $HermesHome 'offline'
$settingsPath = Join-Path $offline 'bundle-settings.json'
$uvCache = Join-Path $offline 'uv-cache'
$UvPath = Join-Path $HermesHome 'bin\uv.exe'
$venv = Join-Path $HermesAgentHome 'venv'
$marker = Join-Path $HermesHome 'state\bundle-install.json'
$pyproject = Join-Path $HermesAgentHome 'pyproject.toml'
$uvLock = Join-Path $HermesAgentHome 'uv.lock'

[void](Restore-HermesAgentFromBrokenBackup -HermesHome $HermesHome -HermesAgentHome $HermesAgentHome)
# Recompute paths after a possible restore.
$venv = Join-Path $HermesAgentHome 'venv'
$pyproject = Join-Path $HermesAgentHome 'pyproject.toml'
$uvLock = Join-Path $HermesAgentHome 'uv.lock'

foreach ($required in @($HermesAgentHome, $settingsPath, $UvPath, $uvCache, $pyproject, $uvLock)) {
    if (-not (Test-Path -LiteralPath $required)) {
        $hint = ''
        if ($required -eq $pyproject -or $required -eq $uvLock) {
            $hint = ' The MSI source tree may have been moved aside by install.ps1/update (look for hermes-agent.broken-*). Reinstall the MSI or restore that backup.'
        }
        throw "Required bundle path is missing: $required.$hint"
    }
}
Write-InstallLog "HermesAgentHome=$HermesAgentHome"
Write-InstallLog "pyproject exists=$([bool](Test-Path -LiteralPath $pyproject))"
Write-InstallLog "uv.lock exists=$([bool](Test-Path -LiteralPath $uvLock))"
Write-InstallLog "uv-cache exists=$([bool](Test-Path -LiteralPath $uvCache))"
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json

$env:HERMES_HOME = $HermesHome
$env:UV_CACHE_DIR = $uvCache
$env:UV_PROJECT_ENVIRONMENT = $venv
$env:UV_PYTHON_INSTALL_DIR = Join-Path $HermesHome 'python'
$env:NO_COLOR = '1'
$pythonExe = if ($settings.pythonExecutable) {
    Join-Path $HermesHome ([string]$settings.pythonExecutable)
} else {
    Get-ChildItem (Join-Path $HermesHome 'python') -Recurse -Filter 'python.exe' -File -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } | Select-Object -First 1 | ForEach-Object { $_.FullName }
}
if (-not $pythonExe -or -not (Test-Path $pythonExe)) { throw "Packaged Python executable not found: $pythonExe" }
Write-InstallLog "Using Python: $pythonExe"

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
    Write-InstallLog 'Creating/updating Python venv from packaged uv cache (offline, locked)...'
    # Avoid PowerShell automatic $args; always pin project dir (do not rely on caller cwd).
    $syncArgs = @(
        'sync',
        '--offline',
        '--locked',
        '--python', $pythonExe,
        '--project', $HermesAgentHome,
        '--directory', $HermesAgentHome
    )
    foreach ($extra in $settings.extras) { $syncArgs += @('--extra', [string]$extra) }

    Push-Location -LiteralPath $HermesAgentHome
    try {
        Write-InstallLog "CurrentDirectory=$(Get-Location)"
        Write-InstallLog "UV_CACHE_DIR=$($env:UV_CACHE_DIR)"
        & $UvPath @syncArgs
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
$installScript = Join-Path $HermesAgentHome 'scripts\install.ps1'
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
        Write-InstallLog 'Installing Node dependencies from packaged npm cache (offline)...'
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installScript `
            -HermesHome $HermesHome -InstallDir $HermesAgentHome -Stage 'node-deps' -NonInteractive -SkipSetup
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
Write-InstallLog "Hermes executable OK: $hermesExe"

# SMC Copilot / native contract expects %HERMES_HOME%\bin\hermes.exe (not only
# hermes.cmd). Mirror upstream Install-HermesCommandLaunchers: copy console
# trampolines out of venv\Scripts into the managed bin dir.
$hermesBin = Join-Path $HermesHome 'bin'
New-Item -ItemType Directory -Path $hermesBin -Force | Out-Null
$scriptsDir = Join-Path $venv 'Scripts'
$pyvenvCfg = Join-Path $venv 'pyvenv.cfg'
$venvRelocatable = $false
if (Test-Path -LiteralPath $pyvenvCfg) {
    $venvRelocatable = [bool](Select-String -Path $pyvenvCfg -Pattern '^\s*relocatable\s*=\s*true\s*$' -Quiet)
}
foreach ($launcher in @('hermes', 'hermes-acp', 'hermes-agent')) {
    $src = Join-Path $scriptsDir "$launcher.exe"
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }
    if ($venvRelocatable) {
        Remove-Item (Join-Path $hermesBin "$launcher.exe") -Force -ErrorAction SilentlyContinue
        Set-Content -Path (Join-Path $hermesBin "$launcher.cmd") -Value "@echo off`r`n`"$src`" %*" -Encoding Ascii
        Write-InstallLog "Staged relocatable launcher: $launcher.cmd -> $src"
    } else {
        Remove-Item (Join-Path $hermesBin "$launcher.cmd") -Force -ErrorAction SilentlyContinue
        Copy-Item -Force -LiteralPath $src -Destination (Join-Path $hermesBin "$launcher.exe")
        Write-InstallLog "Staged bin\$launcher.exe"
    }
}
$binHermes = Join-Path $hermesBin 'hermes.exe'
$binHermesCmd = Join-Path $hermesBin 'hermes.cmd'
if (-not ((Test-Path -LiteralPath $binHermes -PathType Leaf) -or (Test-Path -LiteralPath $binHermesCmd -PathType Leaf))) {
    throw "Failed to stage hermes launcher into $hermesBin"
}
if (Test-Path -LiteralPath $binHermes -PathType Leaf) {
    Write-InstallLog "bin\hermes.exe ready for SMC Copilot runtime probe"
}

Write-InstallLog 'Hermes initialization complete.'
try { Stop-Transcript | Out-Null } catch { }
