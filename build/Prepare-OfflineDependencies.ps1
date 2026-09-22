param(
    [Parameter(Mandatory)]$Config,
    [Parameter(Mandatory)][string]$PayloadDir,
    [Parameter(Mandatory)][string]$AgentDir,
    [Parameter(Mandatory)][string]$SourceCommit
)

. (Join-Path $PSScriptRoot 'Common.ps1')

function Remove-NodeModulesTrees {
    param([Parameter(Mandatory)][string]$Root)
    # Only delete root node_modules trees (not nested ones under another
    # node_modules). Nested paths vanish with the parent, and enumerating them
    # separately races on Windows junctions / already-removed paths.
    $all = @(Get-ChildItem -LiteralPath $Root -Directory -Recurse -Filter 'node_modules' -ErrorAction SilentlyContinue)
    $dirs = @($all | Where-Object {
        $path = $_.FullName
        -not ($all | Where-Object {
            $_.FullName -ne $path -and
            $path.StartsWith(($_.FullName.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)
        })
    } | Sort-Object { $_.FullName.Length } -Descending)

    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir.FullName)) { continue }
        # rd handles long paths and reparse points more reliably than Remove-Item -Recurse.
        cmd.exe /c "rd /s /q `"$($dir.FullName)`"" | Out-Null
        if (Test-Path -LiteralPath $dir.FullName) {
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $dir.FullName) {
            throw "Failed to remove node_modules directory: $($dir.FullName)"
        }
    }
}

$uv = Join-Path $PayloadDir 'bin\uv.exe'
if (-not (Test-Path $uv)) { throw "uv missing: $uv" }
$offline = Join-Path $PayloadDir 'offline'
$uvCache = Join-Path $offline 'uv-cache'
$npmCache = Join-Path $offline 'npm-cache'
$playwright = Join-Path $PayloadDir 'playwright'
Ensure-Directory $uvCache
Ensure-Directory $npmCache
Ensure-Directory $playwright

$venv = Join-Path $AgentDir 'venv'
if (Test-Path $venv) { Remove-Item $venv -Recurse -Force }
$pythonExe = Get-ChildItem (Join-Path $PayloadDir 'python') -Recurse -Filter 'python.exe' -File -ErrorAction SilentlyContinue |
    Sort-Object { $_.FullName.Length } | Select-Object -First 1
if (-not $pythonExe) { throw 'No packaged python.exe found under payload\python.' }
$payloadPrefix = $PayloadDir.TrimEnd('\')
$pythonRelative = $pythonExe.FullName.Substring($payloadPrefix.Length).TrimStart('\')

Write-Step 'Populate complete uv cache from uv.lock and enterprise extras'
$oldCache = $env:UV_CACHE_DIR
$oldProjectEnv = $env:UV_PROJECT_ENVIRONMENT
$oldPythonDir = $env:UV_PYTHON_INSTALL_DIR
$oldHome = $env:HERMES_HOME
try {
    $env:UV_CACHE_DIR = $uvCache
    $env:UV_PROJECT_ENVIRONMENT = $venv
    $env:UV_PYTHON_INSTALL_DIR = Join-Path $PayloadDir 'python'
    $env:HERMES_HOME = $PayloadDir

    $syncArgs = @('sync', '--locked', '--python', $pythonExe.FullName)
    foreach ($extra in $Config.python.extras) { $syncArgs += @('--extra', [string]$extra) }
    Invoke-Native $uv $syncArgs $AgentDir

    # Prove the packaged uv cache is sufficient without registry/network access.
    if (Test-Path $venv) { Remove-Item $venv -Recurse -Force }
    $offlineArgs = @('sync', '--offline', '--locked', '--python', $pythonExe.FullName)
    foreach ($extra in $Config.python.extras) { $offlineArgs += @('--extra', [string]$extra) }
    Invoke-Native $uv $offlineArgs $AgentDir
    $hermesExe = Join-Path $venv 'Scripts\hermes.exe'
    if (-not (Test-Path $hermesExe)) { throw 'Offline uv verification did not produce venv\Scripts\hermes.exe.' }
    Invoke-Native $hermesExe @('--version') $AgentDir
} finally {
    if (Test-Path $venv) { Remove-Item $venv -Recurse -Force }
    $env:UV_CACHE_DIR = $oldCache
    $env:UV_PROJECT_ENVIRONMENT = $oldProjectEnv
    $env:UV_PYTHON_INSTALL_DIR = $oldPythonDir
    $env:HERMES_HOME = $oldHome
}

Write-Step 'Populate npm cache + Playwright Chromium, then prove node-deps works offline'
$installScript = Join-Path $AgentDir 'scripts\install.ps1'
$oldEnv = @{
    HERMES_HOME = $env:HERMES_HOME
    NO_COLOR = $env:NO_COLOR
    npm_config_cache = $env:npm_config_cache
    npm_config_offline = $env:npm_config_offline
    npm_config_prefer_offline = $env:npm_config_prefer_offline
    PLAYWRIGHT_BROWSERS_PATH = $env:PLAYWRIGHT_BROWSERS_PATH
    PATH = $env:Path
}
$userPathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
$userGitBashBefore = [Environment]::GetEnvironmentVariable('HERMES_GIT_BASH_PATH', 'User')
try {
    $env:HERMES_HOME = $PayloadDir
    $env:NO_COLOR = '1'
    $env:npm_config_cache = $npmCache
    $env:npm_config_offline = $null
    $env:npm_config_prefer_offline = 'true'
    $env:PLAYWRIGHT_BROWSERS_PATH = $playwright
    $payloadNodeDir = Join-Path $PayloadDir 'node'
    $nodeUserPath = if ($userPathBefore) { "$payloadNodeDir;$userPathBefore" } else { $payloadNodeDir }
    # The upstream node-deps stage refreshes PATH from User+Machine registry
    # values. Put the payload Node first in User PATH for this child process so
    # npm/npx and Playwright cannot silently fall back to system Node.
    [Environment]::SetEnvironmentVariable('Path', $nodeUserPath, 'User')
    $env:Path = $payloadNodeDir + ';' + (Join-Path $PayloadDir 'bin') + ';' + $oldEnv.PATH

    # Online hydration: fill npm cache and put Chromium inside the MSI payload.
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installScript `
        -HermesHome $PayloadDir -InstallDir $AgentDir -Stage 'node-deps' -NonInteractive -SkipSetup
    if ($LASTEXITCODE -ne 0) { throw "Hermes online node-deps hydration failed with $LASTEXITCODE" }

    # The upstream Windows installer treats npm's workspace return code as
    # best-effort and may skip its internal Playwright step even when the
    # package tree and payload npx are usable. Make the browser payload an
    # explicit build contract instead of inheriting that ambiguity.
    $browserExe = Get-ChildItem $playwright -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('chrome.exe', 'headless_shell.exe') } | Select-Object -First 1
    if (-not $browserExe) {
        $npxPath = Join-Path $payloadNodeDir 'npx.cmd'
        if (-not (Test-Path $npxPath)) { throw "payload npx missing: $npxPath" }
        Write-Step 'Explicitly stage Playwright Chromium with payload npx'
        & $npxPath '--yes' 'playwright' 'install' 'chromium' | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Playwright Chromium staging failed with $LASTEXITCODE" }
    }

    $browserExe = Get-ChildItem $playwright -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('chrome.exe', 'headless_shell.exe') } | Select-Object -First 1
    if (-not $browserExe) {
        throw 'Playwright Chromium was not staged under payload\playwright. The MSI would not be browser-offline.'
    }

    # Never ship build-path-bound node_modules/workspace junctions.
    Remove-NodeModulesTrees $AgentDir

    # Offline proof: run the SAME upstream stage with npm hard-offline and the
    # packaged Playwright path. If a lifecycle script needs an uncached network
    # artifact this build fails here rather than on an endpoint.
    $env:npm_config_offline = 'true'
    $env:npm_config_prefer_offline = 'true'
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installScript `
        -HermesHome $PayloadDir -InstallDir $AgentDir -Stage 'node-deps' -NonInteractive -SkipSetup
    if ($LASTEXITCODE -ne 0) { throw "Hermes node-deps OFFLINE verification failed with $LASTEXITCODE" }

    $nodeModuleDirs = @(Get-ChildItem -LiteralPath $AgentDir -Directory -Recurse -Filter 'node_modules' -ErrorAction SilentlyContinue)
    if ($nodeModuleDirs.Count -eq 0) { throw 'Offline node-deps verification produced no node_modules tree.' }

    # Endpoint recreates node_modules at its real per-user path from npm-cache.
    Remove-NodeModulesTrees $AgentDir
} finally {
    $env:HERMES_HOME = $oldEnv.HERMES_HOME
    $env:NO_COLOR = $oldEnv.NO_COLOR
    $env:npm_config_cache = $oldEnv.npm_config_cache
    $env:npm_config_offline = $oldEnv.npm_config_offline
    $env:npm_config_prefer_offline = $oldEnv.npm_config_prefer_offline
    $env:PLAYWRIGHT_BROWSERS_PATH = $oldEnv.PLAYWRIGHT_BROWSERS_PATH
    $env:Path = $oldEnv.PATH
    [Environment]::SetEnvironmentVariable('Path', $userPathBefore, 'User')
    [Environment]::SetEnvironmentVariable('HERMES_GIT_BASH_PATH', $userGitBashBefore, 'User')
}

$settings = [ordered]@{
    schemaVersion = 1
    hermesVersion = [string]$Config.source.expectedVersion
    sourceCommit = $SourceCommit
    pythonVersion = [string]$Config.python.version
    pythonExecutable = $pythonRelative
    extras = @($Config.python.extras | ForEach-Object { [string]$_ })
    offline = $true
    nodeDependenciesMode = 'offline-install-on-target'
    npmCache = 'offline\npm-cache'
    playwrightBrowsersPath = 'playwright'
}
Write-JsonFile $settings (Join-Path $offline 'bundle-settings.json')
