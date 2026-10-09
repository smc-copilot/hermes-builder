param(
    [Parameter(Mandatory)][string]$MsiPath,
    [string]$LogDirectory = '',
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MsiPath = [IO.Path]::GetFullPath(($MsiPath.Trim().Trim('"').Trim("'")))
if (-not (Test-Path -LiteralPath $MsiPath -PathType Leaf)) {
    throw "MSI not found: $MsiPath"
}

if (-not $LogDirectory) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $LogDirectory = Join-Path (Split-Path -Parent $MsiPath) "install-logs\$stamp"
}
$LogDirectory = [IO.Path]::GetFullPath($LogDirectory)
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

$msiLog = Join-Path $LogDirectory 'msiexec.log'
$args = @('/i', $MsiPath, '/norestart', '/l*v', $msiLog)
if ($Quiet) { $args = @('/i', $MsiPath, '/qn', '/norestart', '/l*v', $msiLog) }

Write-Host "MSI: $MsiPath"
Write-Host "Logs: $LogDirectory"
Write-Host "Starting msiexec $($args -join ' ')"

$proc = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $args -Wait -PassThru
$exit = $proc.ExitCode

$sources = @(
    (Join-Path $env:TEMP 'hermes-msi-preflight.log'),
    (Join-Path $env:TEMP 'hermes-msi-initialize.log'),
    (Join-Path $env:TEMP 'hermes-msi-uv-sync.out.log'),
    (Join-Path $env:TEMP 'hermes-msi-uv-sync.err.log')
)
foreach ($source in $sources) {
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $LogDirectory (Split-Path -Leaf $source)) -Force
    }
}

$summary = @(
    "exit=$exit",
    "msi=$MsiPath",
    "finished=$(Get-Date -Format 'o')"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $LogDirectory 'install-result.txt') -Value $summary -Encoding UTF8

Write-Host "msiexec exit=$exit"
Write-Host "Saved logs under $LogDirectory"
if ($exit -ne 0 -and $exit -ne 3010) { exit $exit }
exit 0
