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

$script:ErrorCode = $null

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

function Fail-Install {
    param(
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message
    )
    $script:ErrorCode = $Code
    throw "${Code}: $Message"
}

$logsDir = Join-Path $HermesHome 'logs'
$installLog = Join-Path $logsDir 'install.log'
$initLog = Join-Path $env:TEMP 'hermes-msi-initialize.log'
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
function Write-InstallLog([string]$Message) {
    $line = '{0} [initialize] {1}' -f (Get-Date -Format 'o'), $Message
    Add-Content -LiteralPath $installLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    Add-Content -LiteralPath $initLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Host $line
}

$transcriptStarted = $false
try {
    try { Start-Transcript -Path $initLog -Force | Out-Null; $transcriptStarted = $true } catch { }
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

    if (-not (Test-Path -LiteralPath $pyproject)) {
        Fail-Install 'HERMES_SOURCE_TREE_MISSING' @"
$pyproject does not exist. Uninstall SMC Copilot Hermes and reinstall the same MSI. Leave any hermes-agent.broken-* directory untouched; the installer will not restore or delete it.
"@.Trim()
    }

    foreach ($required in @($HermesAgentHome, $settingsPath, $UvPath, $uvCache, $uvLock)) {
        if (-not (Test-Path -LiteralPath $required)) {
            Fail-Install 'BUNDLE_INTEGRITY_FAILED' "Required bundle path is missing: $required"
        }
    }
    Write-InstallLog "HermesAgentHome=$HermesAgentHome"
    Write-InstallLog "pyproject exists=True"
    Write-InstallLog "uv.lock exists=True"
    Write-InstallLog "uv-cache exists=True"
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $expectedVersion = [string]$settings.hermesVersion
    if (-not $expectedVersion) { Fail-Install 'BUNDLE_INTEGRITY_FAILED' 'bundle-settings.json is missing hermesVersion' }

    $env:HERMES_HOME = $HermesHome
    $env:NO_COLOR = '1'
    $pythonExe = if ($settings.pythonExecutable) {
        Join-Path $HermesHome ([string]$settings.pythonExecutable)
    } else {
        Get-ChildItem (Join-Path $HermesHome 'python') -Recurse -Filter 'python.exe' -File -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } | Select-Object -First 1 | ForEach-Object { $_.FullName }
    }
    if (-not $pythonExe -or -not (Test-Path -LiteralPath $pythonExe)) {
        Fail-Install 'BUNDLE_INTEGRITY_FAILED' "Packaged Python executable not found: $pythonExe"
    }
    Write-InstallLog "Using Python: $pythonExe"

    [Environment]::SetEnvironmentVariable('HERMES_HOME', $HermesHome, 'User')
    $gitBash = Join-Path $HermesHome 'git\bin\bash.exe'
    if (Test-Path $gitBash) {
        [Environment]::SetEnvironmentVariable('HERMES_GIT_BASH_PATH', $gitBash, 'User')
    }
    Add-UserPathEntry (Join-Path $HermesHome 'bin')

    $venvHermes = Join-Path $venv 'Scripts\hermes.exe'
    $needsSync = $Force -or -not (Test-Path -LiteralPath $venvHermes)
    if (-not $needsSync -and (Test-Path $marker)) {
        try {
            $installed = Get-Content $marker -Raw | ConvertFrom-Json
            if ([string]$installed.sourceCommit -ne [string]$settings.sourceCommit) { $needsSync = $true }
        } catch { $needsSync = $true }
    } elseif (-not (Test-Path $marker)) {
        $needsSync = $true
    }

    if ($needsSync) {
        Write-InstallLog 'Creating/updating Python venv from packaged uv cache (offline, frozen)...'
        # Keep project metadata visible to uv. Disabling config discovery makes a
        # per-user path rebuild exit 0 after "Prepared 1 package" with no
        # yaml/openai. A replacement UV_CONFIG_FILE drops tool.uv exclude-newer
        # so --locked re-resolves offline and fails. --frozen installs uv.lock.
        $syncArgs = @(
            'sync',
            '--offline',
            '--frozen',
            '--link-mode', 'copy',
            '--no-progress',
            '--python', $pythonExe,
            '--project', $HermesAgentHome,
            '--directory', $HermesAgentHome
        )
        if ($settings.PSObject.Properties.Name -contains 'extras' -and $settings.extras) {
            foreach ($extra in @($settings.extras)) {
                if ($extra) { $syncArgs += @('--extra', [string]$extra) }
            }
        }

        $savedUv = @{}
        foreach ($name in @([Environment]::GetEnvironmentVariables().Keys)) {
            if ($name -like 'UV_*' -or $name -eq 'VIRTUAL_ENV') {
                $savedUv[$name] = [Environment]::GetEnvironmentVariable($name)
                Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
            }
        }
        $uvExit = 1
        $uvStdout = Join-Path $env:TEMP 'hermes-msi-uv-sync.out.log'
        $uvStderr = Join-Path $env:TEMP 'hermes-msi-uv-sync.err.log'
        if (Test-Path -LiteralPath $venv) { Remove-Item -LiteralPath $venv -Recurse -Force }
        Push-Location -LiteralPath $HermesAgentHome
        try {
            $env:UV_CACHE_DIR = $uvCache
            $env:UV_PROJECT_ENVIRONMENT = $venv
            $env:UV_PYTHON_INSTALL_DIR = Join-Path $HermesHome 'python'
            $env:UV_NO_PROGRESS = '1'
            $env:HERMES_HOME = $HermesHome
            $env:NO_COLOR = '1'
            Write-InstallLog "CurrentDirectory=$(Get-Location)"
            Write-InstallLog "uv argv: $UvPath $($syncArgs -join ' ')"
            $uvSnap = @(Get-ChildItem Env:UV_* -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)=$($_.Value)" })
            Write-InstallLog ("UV_* after allowlist: {0}" -f ($uvSnap -join '; '))
            $proc = Start-Process -FilePath $UvPath -ArgumentList $syncArgs -WorkingDirectory $HermesAgentHome -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $uvStdout -RedirectStandardError $uvStderr
            $uvExit = $proc.ExitCode
        } finally {
            Pop-Location
            foreach ($name in @([Environment]::GetEnvironmentVariables().Keys)) {
                if ($name -like 'UV_*' -or $name -eq 'VIRTUAL_ENV') {
                    Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
                }
            }
            foreach ($name in @($savedUv.Keys)) {
                Set-Item -Path "Env:$name" -Value $savedUv[$name]
            }
        }
        foreach ($f in @($uvStdout, $uvStderr)) {
            if (Test-Path -LiteralPath $f) {
                $chunk = [string](Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue)
                foreach ($line in @($chunk -split "`r?`n")) {
                    if ($line) { Write-InstallLog $line }
                }
            }
        }
        Write-InstallLog "uv sync exit=$uvExit"
        if ($uvExit -ne 0) { Fail-Install 'UV_SYNC_FAILED' "uv sync failed with exit code $uvExit" }
    }

    $pyvenvCfg = Join-Path $venv 'pyvenv.cfg'
    if (Test-Path -LiteralPath $pyvenvCfg) {
        $relocatable = [bool](Select-String -Path $pyvenvCfg -Pattern '^\s*relocatable\s*=\s*true\s*$' -Quiet)
        if ($relocatable) {
            Fail-Install 'VENV_RELOCATABLE' "pyvenv.cfg contains relocatable=true. Refusing to replace bin\hermes.exe with a .cmd launcher."
        }
    }

    if (-not (Test-Path -LiteralPath $venvHermes -PathType Leaf)) {
        Fail-Install 'HERMES_CLI_MISSING_POST_SYNC' "Hermes executable missing after offline sync: $venvHermes"
    }

    function Assert-HermesCli {
        param([Parameter(Mandatory)][string]$Exe)
        $output = @(& $Exe --version 2>&1)
        $code = $LASTEXITCODE
        $first = if ($output.Count -gt 0) { [string]$output[0] } else { '' }
        Write-InstallLog "verify exe=$Exe exit=$code first=$first"
        $pattern = '^Hermes Agent v' + [regex]::Escape($expectedVersion) + ' \('
        if ($code -ne 0 -or $first -notmatch $pattern) {
            Fail-Install 'HERMES_CLI_VERIFY_FAILED' "hermes --version failed for $Exe (exit=$code, first='$first')"
        }
    }

    $venvPython = Join-Path $venv 'Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
        Fail-Install 'HERMES_CLI_VERIFY_FAILED' "venv python missing after sync: $venvPython"
    }
    $depOut = @(& $venvPython -c "import yaml, openai; print('DEPS_OK')" 2>&1)
    $depCode = $LASTEXITCODE
    Write-InstallLog "venv python import yaml,openai exit=$depCode out=$($depOut -join ' | ')"
    if ($depCode -ne 0 -or ($depOut -join ' ') -notmatch 'DEPS_OK') {
        Fail-Install 'HERMES_CLI_VERIFY_FAILED' "venv is missing PyYAML or OpenAI after uv sync. $(($depOut | Out-String).Trim())"
    }

    Assert-HermesCli $venvHermes
    if (-not (Test-Path -LiteralPath $venvHermes -PathType Leaf)) {
        Fail-Install 'HERMES_CLI_MISSING_POST_SYNC' "Hermes executable disappeared before bin copy: $venvHermes"
    }

    $hermesBin = Join-Path $HermesHome 'bin'
    New-Item -ItemType Directory -Path $hermesBin -Force | Out-Null
    $scriptsDir = Join-Path $venv 'Scripts'
    foreach ($launcher in @('hermes', 'hermes-acp', 'hermes-agent')) {
        $src = Join-Path $scriptsDir "$launcher.exe"
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
            if ($launcher -eq 'hermes') {
                Fail-Install 'HERMES_CLI_VERIFY_FAILED' "Failed to stage hermes launcher into $hermesBin"
            }
            continue
        }
        $dest = Join-Path $hermesBin "$launcher.exe"
        try {
            Copy-Item -Force -LiteralPath $src -Destination $dest
        } catch {
            Fail-Install 'HERMES_CLI_VERIFY_FAILED' "Failed to copy $src to $dest. $_"
        }
        if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
            Fail-Install 'HERMES_CLI_VERIFY_FAILED' "Copy reported success but $dest is missing"
        }
        Write-InstallLog "Staged bin\$launcher.exe"
    }
    $binHermes = Join-Path $hermesBin 'hermes.exe'
    Assert-HermesCli $binHermes
    Write-InstallLog 'bin\hermes.exe ready for SMC Copilot runtime probe'

    $defaults = Join-Path $HermesHome 'defaults\config'
    Copy-IfMissing (Join-Path $defaults '.env.template') (Join-Path $HermesHome '.env')
    Copy-IfMissing (Join-Path $defaults 'config.yaml.template') (Join-Path $HermesHome 'config.yaml')
    Copy-IfMissing (Join-Path $defaults 'SOUL.md.template') (Join-Path $HermesHome 'SOUL.md')

    & (Join-Path $PSScriptRoot 'Install-EnterpriseSkills.ps1') -HermesHome $HermesHome

    $stateDir = Join-Path $HermesHome 'state'
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $markerData = [ordered]@{
        schemaVersion = 1
        hermesVersion = $expectedVersion
        sourceCommit = [string]$settings.sourceCommit
        initializedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $markerData | ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8

    Write-InstallLog 'Hermes initialization complete.'
    exit 0
} catch {
    $code = if ($script:ErrorCode) { $script:ErrorCode } else { 'UV_SYNC_FAILED' }
    $detail = $_.Exception.Message
    Write-InstallLog "ERROR $code $detail"
    if (-not $script:ErrorCode) { $script:ErrorCode = $code }
    exit 1
} finally {
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}
