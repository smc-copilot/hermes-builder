Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Assert-Windows {
    $isWindowsHost = if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
        [bool]$IsWindows
    } else {
        $env:OS -eq 'Windows_NT'
    }
    if (-not $isWindowsHost) {
        throw 'This packaging pipeline must run on Windows x64 because it prepares Windows-native Python/Node dependencies.'
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'Windows x64 build host required.'
    }
}

function Reset-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = ''
    )
    $old = Get-Location
    try {
        if ($WorkingDirectory) { Set-Location -LiteralPath $WorkingDirectory }
        Write-Host "> $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray
        & $FilePath @Arguments | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
        }
    } finally {
        Set-Location $old
    }
}

function Copy-Tree {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [string[]]$ExcludeDirs = @(),
        [string[]]$ExcludeFiles = @()
    )
    Ensure-Directory $Destination
    $args = @($Source, $Destination, '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($ExcludeDirs.Count -gt 0) { $args += '/XD'; $args += $ExcludeDirs }
    if ($ExcludeFiles.Count -gt 0) { $args += '/XF'; $args += $ExcludeFiles }
    & robocopy @args | Out-Host
    if ($LASTEXITCODE -gt 7) { throw "robocopy failed with code $LASTEXITCODE" }
}

function Assert-EnvTemplate {
    param([Parameter(Mandatory)][string]$Path)
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $lineNumber++
        if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
        # Validate definitions only. Empty values and deployment-specific
        # credentials/URLs are valid; never echo their contents in errors.
        if ($line -notmatch '^\s*(?:export\s+)?[A-Za-z_][A-Za-z0-9_]*\s*=.*$') {
            throw "Invalid environment variable definition at line $lineNumber in $Path"
        }
    }
}

function Download-File {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$OutFile)
    Ensure-Directory (Split-Path -Parent $OutFile)
    Write-Host "Downloading $Url" -ForegroundColor DarkGray
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutFile
    } finally {
        $ProgressPreference = $oldProgress
    }
}

function Get-GitHubReleaseAsset {
    param(
        [Parameter(Mandatory)][string]$ReleaseApi,
        [Parameter(Mandatory)][string]$AssetRegex
    )
    $headers = @{ 'User-Agent' = 'copilot-hermes-msi-builder' }
    if ($env:GITHUB_TOKEN) { $headers.Authorization = "Bearer $env:GITHUB_TOKEN" }
    $release = Invoke-RestMethod -Uri $ReleaseApi -Headers $headers
    $asset = $release.assets | Where-Object { $_.name -match $AssetRegex } | Select-Object -First 1
    if (-not $asset) { throw "No GitHub release asset matched '$AssetRegex' from $ReleaseApi" }
    return $asset
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Write-JsonFile {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path, [int]$Depth = 12)
    Ensure-Directory (Split-Path -Parent $Path)
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-ProjectVersion {
    param([Parameter(Mandatory)][string]$PyProject)
    $text = Get-Content -LiteralPath $PyProject -Raw
    $m = [regex]::Match($text, '(?m)^version\s*=\s*"([^"]+)"')
    if (-not $m.Success) { throw "Unable to read project version from $PyProject" }
    return $m.Groups[1].Value
}
