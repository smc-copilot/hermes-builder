param(
    [Parameter(Mandatory)]$Config,
    [Parameter(Mandatory)][string]$PayloadDir,
    [Parameter(Mandatory)][string]$AgentDir
)

. (Join-Path $PSScriptRoot 'Common.ps1')

function Resolve-CommandPath {
    param([Parameter(Mandatory)]$Command)
    $item = Get-Item -LiteralPath $Command.Source -Force
    if ($item.Target) {
        $target = [string]$item.Target
        if (-not [IO.Path]::IsPathRooted($target)) {
            $target = Join-Path $item.DirectoryName $target
        }
        return (Resolve-Path -LiteralPath $target).Path
    }
    return $item.FullName
}

$installScript = Join-Path $AgentDir 'scripts\install.ps1'
if (-not (Test-Path $installScript)) { throw "Hermes install.ps1 not found: $installScript" }

Write-Step 'Prepare Hermes managed uv / Python / Git / Node using upstream Stage Protocol'
$oldHome = $env:HERMES_HOME
$oldNoColor = $env:NO_COLOR
$oldPythonInstallDir = $env:UV_PYTHON_INSTALL_DIR
$oldProcessPath = $env:Path
# Upstream runtime stages intentionally update the *user* PATH/Git Bash settings
# during an interactive install. A packaging build must not leak those changes
# into the build account, so snapshot and restore them around the stage calls.
$userPathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
$userHermesHomeBefore = [Environment]::GetEnvironmentVariable('HERMES_HOME', 'User')
$userGitBashBefore = [Environment]::GetEnvironmentVariable('HERMES_GIT_BASH_PATH', 'User')
try {
    $env:HERMES_HOME = $PayloadDir
    $env:NO_COLOR = '1'
    # uv normally installs managed Python into its global data directory. Force
    # it into the MSI payload so the endpoint never has to download Python.
    $env:UV_PYTHON_INSTALL_DIR = Join-Path $PayloadDir 'python'
    foreach ($stage in @('uv', 'python', 'git', 'node')) {
        $env:Path = $oldProcessPath
        if ($stage -eq 'node') {
            # The upstream node stage intentionally reuses a compatible system
            # Node. Packaging needs a self-contained payload, so hide only
            # system Node.js directories from this child process and force the
            # stage to provision Hermes-managed Node under $PayloadDir.
            $env:Path = @($oldProcessPath -split ';' |
                Where-Object {
                    $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'node.exe'))
                }) -join ';'
        }
        Write-Host "Preparing upstream stage: $stage" -ForegroundColor Yellow
        $stageArgs = @(
            '-HermesHome', $PayloadDir,
            '-InstallDir', $AgentDir,
            '-NonInteractive',
            '-SkipSetup'
        )
        if ($stage -eq 'node') {
            # -Stage refreshes PATH from the registry before probing Node. The
            # ensure branch uses the filtered process PATH and provisions the
            # managed copy required by this payload.
            $stageArgs += @('-Ensure', 'node')
        } else {
            $stageArgs += @('-Stage', $stage)
        }
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installScript @stageArgs
        if ($LASTEXITCODE -ne 0) { throw "Hermes install stage '$stage' failed with $LASTEXITCODE" }
    }
} finally {
    $env:HERMES_HOME = $oldHome
    $env:NO_COLOR = $oldNoColor
    $env:UV_PYTHON_INSTALL_DIR = $oldPythonInstallDir
    $env:Path = $oldProcessPath
    [Environment]::SetEnvironmentVariable('Path', $userPathBefore, 'User')
    [Environment]::SetEnvironmentVariable('HERMES_HOME', $userHermesHomeBefore, 'User')
    [Environment]::SetEnvironmentVariable('HERMES_GIT_BASH_PATH', $userGitBashBefore, 'User')
}

$gitDir = Join-Path $PayloadDir 'git'
if (-not (Test-Path -LiteralPath $gitDir)) {
    # Upstream Install-Git intentionally reuses a healthy system Git. The MSI
    # still needs its own relocatable Git/Bash tree, so stage the verified Git
    # for Windows installation when the upstream stage did not create one.
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) { throw 'Git was neither staged by Hermes nor available on the build host.' }
    $gitCmdDir = Split-Path -Parent $gitCommand.Source
    $gitRoot = Split-Path -Parent $gitCmdDir
    if (-not (Test-Path -LiteralPath (Join-Path $gitRoot 'bin\bash.exe'))) {
        throw "Build-host Git does not contain a relocatable Git Bash tree: $gitRoot"
    }
    Write-Step 'Stage build-host Git for the self-contained MSI payload'
    Copy-Tree $gitRoot $gitDir @('tmp')
}

$uv = Join-Path $PayloadDir 'bin\uv.exe'
$node = Join-Path $PayloadDir 'node\node.exe'
if (-not (Test-Path $uv)) { throw "Managed uv missing after stage execution: $uv" }
if (-not (Test-Path $node)) { throw "Managed Node missing after stage execution: $node" }
foreach ($relative in @('node\npm.cmd', 'node\npx.cmd', 'node\node_modules\npm\bin\npm-cli.js', 'node\node_modules\npm\bin\npx-cli.js')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PayloadDir $relative) -PathType Leaf)) {
        throw "Managed npm/npx incomplete after stage execution: $relative"
    }
}
if (-not (Test-Path $gitDir)) { throw 'Managed Git directory missing after stage execution.' }

$pythonInstallDir = Join-Path $PayloadDir 'python'
$pythonExe = Get-ChildItem $pythonInstallDir -Recurse -Filter 'python.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pythonExe) {
    Write-Step 'Install managed Python into the self-contained MSI payload'
    $oldManagedPythonDir = $env:UV_PYTHON_INSTALL_DIR
    try {
        $env:UV_PYTHON_INSTALL_DIR = $pythonInstallDir
        & $uv python install ([string]$Config.python.version) | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "uv python install failed with $LASTEXITCODE" }
    } finally {
        $env:UV_PYTHON_INSTALL_DIR = $oldManagedPythonDir
    }
}

if (-not (Test-Path (Join-Path $PayloadDir 'python'))) {
    throw 'Managed Python was not staged under payload\python. UV_PYTHON_INSTALL_DIR isolation failed.'
}

Write-Step 'Add portable ripgrep and ffmpeg to payload/bin'
$bin = Join-Path $PayloadDir 'bin'
Ensure-Directory $bin
$temp = Join-Path $PayloadDir '.download'
Reset-Directory $temp

if ($Config.systemTools.ripgrep.enabled) {
    $rgCommand = Get-Command rg -ErrorAction SilentlyContinue
    $rgLocal = if ($rgCommand) { Resolve-CommandPath $rgCommand } else { $null }
    if ($rgLocal -and (Test-Path -LiteralPath $rgLocal)) {
        Write-Step 'Stage locally installed ripgrep'
        Copy-Item -LiteralPath $rgLocal -Destination (Join-Path $bin 'rg.exe') -Force
    } else {
        $asset = Get-GitHubReleaseAsset ([string]$Config.systemTools.ripgrep.releaseApi) ([string]$Config.systemTools.ripgrep.assetRegex)
        $zip = Join-Path $temp $asset.name
        Download-File $asset.browser_download_url $zip
        $extract = Join-Path $temp 'ripgrep'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $rg = Get-ChildItem $extract -Recurse -Filter 'rg.exe' | Select-Object -First 1
        if (-not $rg) { throw 'rg.exe not found after extracting ripgrep release.' }
        Copy-Item $rg.FullName (Join-Path $bin 'rg.exe') -Force
    }
}

if ($Config.systemTools.ffmpeg.enabled) {
    $ffmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
    $ffprobeCommand = Get-Command ffprobe -ErrorAction SilentlyContinue
    $ffmpegLocal = if ($ffmpegCommand) { Resolve-CommandPath $ffmpegCommand } else { $null }
    $ffprobeLocal = if ($ffprobeCommand) { Resolve-CommandPath $ffprobeCommand } else { $null }
    if ($ffmpegLocal -and $ffprobeLocal -and (Test-Path -LiteralPath $ffmpegLocal) -and (Test-Path -LiteralPath $ffprobeLocal)) {
        Write-Step 'Stage locally installed ffmpeg and ffprobe'
        Copy-Item -LiteralPath $ffmpegLocal -Destination (Join-Path $bin 'ffmpeg.exe') -Force
        Copy-Item -LiteralPath $ffprobeLocal -Destination (Join-Path $bin 'ffprobe.exe') -Force
        foreach ($sourceDir in @((Split-Path -Parent $ffmpegLocal), (Split-Path -Parent $ffprobeLocal)) | Select-Object -Unique) {
            Get-ChildItem -LiteralPath $sourceDir -Filter '*.dll' -File -ErrorAction SilentlyContinue |
                Copy-Item -Destination $bin -Force
        }
    } else {
        $zip = Join-Path $temp 'ffmpeg.zip'
        Download-File ([string]$Config.systemTools.ffmpeg.url) $zip
        $extract = Join-Path $temp 'ffmpeg'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) {
            $f = Get-ChildItem $extract -Recurse -Filter $name | Select-Object -First 1
            if (-not $f) { throw "$name not found after extracting ffmpeg package." }
            Copy-Item $f.FullName (Join-Path $bin $name) -Force
        }
    }
}

Remove-Item $temp -Recurse -Force
