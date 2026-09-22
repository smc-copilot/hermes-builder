param([string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build-config.json'))

$ErrorActionPreference = 'Stop'
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
if ($config.source.mode -ne 'local-preferred') { throw 'Expected local-preferred source mode.' }
if ($config.source.localPath -ne 'src/hermes-agent') { throw 'Expected local source path src/hermes-agent.' }
if ($config.source.defaultBranch -ne 'main') { throw 'Expected local source branch main.' }
if ($config.source.expectedVersion -ne '0.21.0') { throw 'Expected Hermes 0.21.0.' }
if ($config.target.architecture -ne 'x64') { throw 'Expected x64 target.' }
if (-not $config.target.perUser) { throw 'Expected per-user target.' }
foreach ($cmd in @('git', 'dotnet')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Build prerequisite missing: $cmd" }
}
Write-Host 'Build input smoke checks passed.'
