param(
    [Parameter(Mandatory)][string]$HermesHome,
    [long]$MinFreeBytes = 4GB
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# MSI directory properties end with '\'. Quoting that as "dir\" escapes the
# closing quote; we pass "dir\." from WiX and normalize here.
$HermesHome = [IO.Path]::GetFullPath(($HermesHome.Trim().Trim('"').Trim("'")))
$HermesHome = $HermesHome.TrimEnd('\')

$tempLog = Join-Path $env:TEMP 'hermes-msi-preflight.log'
$logsDir = Join-Path $HermesHome 'logs'
$installLog = Join-Path $logsDir 'install.log'

function Write-Log([string]$Message) {
    $line = '{0} [preflight] {1}' -f (Get-Date -Format 'o'), $Message
    Add-Content -LiteralPath $tempLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $logsDir) {
        Add-Content -LiteralPath $installLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    Write-Host $line
}

try {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
} catch {
    # Still proceed; temp log remains the fallback.
}

Remove-Item -LiteralPath $tempLog -Force -ErrorAction SilentlyContinue
Write-Log "Preflight start HermesHome=$HermesHome"

# Fail clearly before the long offline uv/npm init.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User -and $identity.User.Value -eq 'S-1-5-18') {
    throw 'This per-user MSI must not run as SYSTEM. Install from an interactive user session.'
}

$psMajor = $PSVersionTable.PSVersion.Major
if ($psMajor -lt 5) {
    throw "Windows PowerShell 5.1+ is required. Found $psMajor."
}
Write-Log "PowerShell version=$($PSVersionTable.PSVersion)"

if (-not [Environment]::Is64BitOperatingSystem) {
    throw '64-bit Windows is required.'
}

$hermesHomeFull = [IO.Path]::GetFullPath($HermesHome)
if ($hermesHomeFull.Length -gt 120) {
    throw "Install path is too long ($($hermesHomeFull.Length) chars). Keep %LOCALAPPDATA%\hermes shorter than 120 characters to avoid Windows path limits during npm install."
}
Write-Log "HermesHomeFull=$hermesHomeFull length=$($hermesHomeFull.Length)"

$drive = [IO.Path]::GetPathRoot($hermesHomeFull).TrimEnd('\')
$free = $null
$psDrive = Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction SilentlyContinue
if ($psDrive -and $null -ne $psDrive.Free) {
    $free = [int64]$psDrive.Free
} else {
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction SilentlyContinue
    if ($disk) { $free = [int64]$disk.FreeSpace }
}
if ($null -eq $free) {
    Write-Log "Warning: could not determine free space for $drive; continuing."
} elseif ($free -lt $MinFreeBytes) {
    $needGb = [math]::Round($MinFreeBytes / 1GB, 1)
    $freeGb = [math]::Round($free / 1GB, 1)
    throw "Not enough free disk space on $drive. Need at least ${needGb} GB free for venv/node_modules initialization; found ${freeGb} GB."
} else {
    Write-Log ("Free space on {0}: {1:N1} GB" -f $drive, ($free / 1GB))
}

$required = @(
    'bootstrap\Initialize-Hermes.ps1',
    'bin\uv.exe',
    'offline\bundle-settings.json',
    'offline\uv-cache',
    'hermes-agent\pyproject.toml',
    'hermes-agent\uv.lock',
    'node\node.exe'
)
foreach ($rel in $required) {
    $path = Join-Path $hermesHomeFull $rel
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Installed payload is incomplete. Missing: $path"
    }
    Write-Log "OK: $rel"
}

$settingsPath = Join-Path $hermesHomeFull 'offline\bundle-settings.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$pythonRel = [string]$settings.pythonExecutable
if (-not $pythonRel) { throw 'bundle-settings.json is missing pythonExecutable.' }
$pythonExe = Join-Path $hermesHomeFull $pythonRel
if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw "Packaged Python executable not found: $pythonExe"
}
Write-Log "Python OK: $pythonExe"

$nodeExe = Join-Path $hermesHomeFull 'node\node.exe'
$nodeVer = & $nodeExe --version 2>$null
Write-Log "Node OK: $nodeExe version=$nodeVer"

$uvCache = Join-Path $hermesHomeFull 'offline\uv-cache'
$uvCacheItems = @(Get-ChildItem -LiteralPath $uvCache -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($uvCacheItems.Count -eq 0) {
    throw "Packaged uv cache is empty: $uvCache"
}
Write-Log 'uv-cache OK'

Write-Log 'Preflight OK'
exit 0
