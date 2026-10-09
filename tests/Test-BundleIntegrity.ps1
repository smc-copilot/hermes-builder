Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$preflight = Join-Path $repoRoot 'scripts\Preflight-HermesInstall.ps1'
$preflightText = Get-Content -LiteralPath $preflight -Raw
if ($preflightText -match 'uv\s+sync') { throw 'Preflight must not invoke uv sync' }

function New-StubExe {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Stdout)
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $src = Join-Path $dir ('_stub_' + [guid]::NewGuid().ToString('n') + '.cs')
    $escaped = $Stdout.Replace('\', '\\').Replace('"', '\"')
    $className = 'Stub' + [guid]::NewGuid().ToString('n')
    @"
using System;
public class $className {
  public static void Main() { Console.WriteLine("$escaped"); }
}
"@ | Set-Content -LiteralPath $src -Encoding ASCII
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $csc /nologo /out:$Path $src | Out-Host
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Path)) { throw "failed to compile stub $Path" }
}

function New-Fixture {
    param([Parameter(Mandatory)][string]$Root)
    $files = @(
        'bin\uv.exe',
        'bin\rg.exe',
        'bin\ffmpeg.exe',
        'bin\ffprobe.exe',
        'node\node.exe',
        'hermes-agent\pyproject.toml',
        'hermes-agent\uv.lock',
        'offline\bundle-settings.json'
    )
    $hashes = [ordered]@{}
    foreach ($rel in $files) {
        $full = Join-Path $Root $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
        if ($rel -eq 'node\node.exe') {
            New-StubExe -Path $full -Stdout 'v22.0.0'
        } elseif ($rel -eq 'offline\bundle-settings.json') {
            '{"schemaVersion":1,"hermesVersion":"0.21.0","pythonExecutable":"python\\python.exe","sourceCommit":"041b6985a00d01b54f830c1607dd370007a306bf"}' | Set-Content -LiteralPath $full -Encoding UTF8
        } else {
            "fixture $rel" | Set-Content -LiteralPath $full -Encoding UTF8
        }
        $hashes[$rel] = (Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToLowerInvariant()
    }
    New-Item -ItemType Directory -Path (Join-Path $Root 'bootstrap') -Force | Out-Null
    'preflight-placeholder' | Set-Content (Join-Path $Root 'bootstrap\Initialize-Hermes.ps1') -Encoding UTF8
    $python = Join-Path $Root 'python\python.exe'
    New-Item -ItemType Directory -Path (Split-Path $python) -Force | Out-Null
    'python' | Set-Content -LiteralPath $python -Encoding ASCII
    $cache = Join-Path $Root 'offline\uv-cache'
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    'wheel' | Set-Content (Join-Path $cache 'placeholder') -Encoding ASCII
    $manifest = [ordered]@{ schemaVersion = 1; hashes = $hashes }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Root 'runtime-manifest.json') -Encoding UTF8
}

function Invoke-Preflight {
    param([Parameter(Mandatory)][string]$Root)
    $stdout = Join-Path $env:TEMP ('pf-out-' + [guid]::NewGuid().ToString('n') + '.txt')
    $stderr = Join-Path $env:TEMP ('pf-err-' + [guid]::NewGuid().ToString('n') + '.txt')
    $proc = Start-Process -FilePath powershell.exe -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $preflight, '-HermesHome', $Root
    ) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $text = ''
    if (Test-Path -LiteralPath $stdout) { $text += [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) }
    if (Test-Path -LiteralPath $stderr) { $text += [string](Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) }
    return [pscustomobject]@{ Exit = $proc.ExitCode; Output = $text }
}

$root = Join-Path $env:TEMP ('hermes-bundle-ok-' + [guid]::NewGuid().ToString('n'))
New-Fixture $root
$ok = Invoke-Preflight $root
if ($ok.Exit -ne 0) { throw "A-BUNDLE-001 failed: exit=$($ok.Exit) $($ok.Output)" }

$bad = Join-Path $env:TEMP ('hermes-bundle-bad-' + [guid]::NewGuid().ToString('n'))
New-Fixture $bad
Add-Content -LiteralPath (Join-Path $bad 'bin\uv.exe') -Value 'tamper' -Encoding ASCII
$fail = Invoke-Preflight $bad
if ($fail.Exit -eq 0) { throw 'A-BUNDLE-002 failed: tamper was accepted' }
if ($fail.Output -notmatch 'BUNDLE_INTEGRITY_FAILED') { throw "A-BUNDLE-002 missing error code: $($fail.Output)" }

$evidence = Join-Path $repoRoot 'evidence'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
@{ id = 'A-BUNDLE-001'; result = 'PASS'; utc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $evidence 'A-BUNDLE-001.json') -Encoding UTF8
@{ id = 'A-BUNDLE-002'; result = 'PASS'; utc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $evidence 'A-BUNDLE-002.json') -Encoding UTF8
Write-Host 'PASS: A-BUNDLE-001 A-BUNDLE-002'
