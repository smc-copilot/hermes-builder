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

$operationId = [guid]::NewGuid().ToString()
if (-not $LogDirectory) {
    $LogDirectory = Join-Path $env:LOCALAPPDATA "SMC\HermesInstaller\InstallerLogs\$operationId"
}
$LogDirectory = [IO.Path]::GetFullPath($LogDirectory)
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

$msiLog = Join-Path $LogDirectory 'msiexec.log'
$args = @('/i', $MsiPath, '/norestart', '/L*V!', $msiLog)
if ($Quiet) { $args = @('/i', $MsiPath, '/qn', '/norestart', '/L*V!', $msiLog) }

$proc = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $args -Wait -PassThru -NoNewWindow
$exit = $proc.ExitCode
Set-Content -LiteralPath (Join-Path $LogDirectory 'install-result.txt') -Value "exit=$exit`r\noperationId=$operationId" -Encoding UTF8
if ($exit -eq 3010) { exit 3010 }
if ($exit -ne 0) { exit $exit }

$init = Join-Path $env:LOCALAPPDATA 'hermes\bootstrap\HermesRuntimeInit.exe'
$manifest = Join-Path $env:LOCALAPPDATA 'hermes\runtime-manifest-v2.json'
if (-not (Test-Path -LiteralPath $init)) { throw "HermesRuntimeInit.exe missing: $init" }
& $init --initialize --quiet --manifest $manifest
exit $LASTEXITCODE
