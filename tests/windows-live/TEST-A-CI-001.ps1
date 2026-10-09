$ErrorActionPreference = 'Stop'
$caption = (Get-CimInstance Win32_OperatingSystem).Caption
$isClientWin10 = $caption -match 'Windows 10' -and $caption -notmatch 'Server'
if (-not $isClientWin10) {
    Write-Host "GOLDEN_CONSUMER_BLOCKED: $caption is not a Windows 10 client"
    exit 2
}
Write-Host 'Windows 10 client detected. Golden consumer still requires the manual protocol in docs/runbooks/hermes-installer-v2.md.'
exit 2
