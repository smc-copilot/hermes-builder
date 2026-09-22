param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$HermesArgs
)

$ErrorActionPreference = 'Stop'
$hermesRoot = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
$env:HERMES_HOME = $hermesRoot
# Process-local only. This avoids ANSI/encoding mojibake seen in some Windows terminals.
$env:NO_COLOR = '1'

# Node, npm.cmd and npx.cmd share this directory. Child processes (including
# cmd.exe-based MCP servers) inherit this process-local PATH.
$nodeDir = Join-Path $hermesRoot 'node'
foreach ($command in @('node.exe', 'npm.cmd', 'npx.cmd')) {
    if (-not (Test-Path -LiteralPath (Join-Path $nodeDir $command) -PathType Leaf)) {
        throw "Packaged Node command missing: $command in $nodeDir"
    }
}
$remainingPath = @($env:Path -split ';' | Where-Object {
    $_ -and $_.Trim().Trim('"').TrimEnd('\') -ine $nodeDir.TrimEnd('\')
})
$env:Path = (@($nodeDir) + $remainingPath) -join ';'

$hermesExe = Join-Path $hermesRoot 'hermes-agent\venv\Scripts\hermes.exe'
$init = Join-Path $hermesRoot 'bootstrap\Initialize-Hermes.ps1'
if (-not (Test-Path $hermesExe)) {
    if (-not (Test-Path $init)) {
        throw "Hermes bootstrap script not found: $init"
    }
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $init -HermesHome $hermesRoot
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

& $hermesExe @HermesArgs
exit $LASTEXITCODE
