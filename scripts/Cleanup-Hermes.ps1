param(
    [string]$HermesHome = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { "$env:LOCALAPPDATA\hermes" })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Generated runtime only. User state is intentionally preserved.
$venv = Join-Path $HermesHome 'hermes-agent\venv'
if (Test-Path $venv) { Remove-Item $venv -Recurse -Force -ErrorAction SilentlyContinue }
$agent = Join-Path $HermesHome 'hermes-agent'
if (Test-Path $agent) {
    Get-ChildItem -LiteralPath $agent -Directory -Recurse -Filter 'node_modules' -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
}
$marker = Join-Path $HermesHome 'state\bundle-install.json'
if (Test-Path $marker) { Remove-Item $marker -Force -ErrorAction SilentlyContinue }

$bin = (Join-Path $HermesHome 'bin').TrimEnd('\\')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath) {
    $parts = @($userPath -split ';' | Where-Object { $_ -and $_.Trim().TrimEnd('\\') -ine $bin })
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
}

$currentHome = [Environment]::GetEnvironmentVariable('HERMES_HOME', 'User')
if ($currentHome -and $currentHome.TrimEnd('\\') -ieq $HermesHome.TrimEnd('\\')) {
    [Environment]::SetEnvironmentVariable('HERMES_HOME', $null, 'User')
}
$currentGitBash = [Environment]::GetEnvironmentVariable('HERMES_GIT_BASH_PATH', 'User')
$ownedGitBash = Join-Path $HermesHome 'git\bin\bash.exe'
if ($currentGitBash -and $currentGitBash -ieq $ownedGitBash) {
    [Environment]::SetEnvironmentVariable('HERMES_GIT_BASH_PATH', $null, 'User')
}

Write-Host 'Hermes generated runtime cleaned. User configuration/state preserved.'
