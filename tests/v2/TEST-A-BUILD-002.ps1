$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$py = Join-Path $root 'build\runtime_manifest_v2.py'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('hermes-manifest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
try {
    $errFile = Join-Path $fixture 'stderr.txt'
    $outFile = Join-Path $fixture 'stdout.txt'
    $proc = Start-Process -FilePath 'python' -ArgumentList @(
        $py, '--payload', $fixture,
        '--source-commit', '041b6985a00d01b54f830c1607dd370007a306bf',
        '--installer-version', '2.0.0', '--agent-version', '0.21.0',
        '--venv-estimated-bytes', '1'
    ) -Wait -PassThru -NoNewWindow -RedirectStandardError $errFile -RedirectStandardOutput $outFile
    if ($proc.ExitCode -eq 0) { throw 'incomplete payload must not sign' }
    $text = (Get-Content -LiteralPath $errFile -Raw) + (Get-Content -LiteralPath $outFile -Raw)
    if ($text -notmatch 'BUILD_PROVENANCE_MISSING') { throw "expected BUILD_PROVENANCE_MISSING, got $text" }
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-Item Env:HERMES_MANIFEST_ED25519_SEED_B64 -ErrorAction SilentlyContinue
$secret = Join-Path $env:USERPROFILE '.hermes-builder-secrets\HERMES_MANIFEST_ED25519_SEED_B64.txt'
if (-not (Test-Path $secret)) {
    $env:HERMES_MANIFEST_ED25519_SEED_B64 = ''
}
Write-Host 'PASS: TEST-A-BUILD-002 schema rejection'
