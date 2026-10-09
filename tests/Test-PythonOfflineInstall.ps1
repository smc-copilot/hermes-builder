Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$init = Join-Path $repoRoot 'scripts\Initialize-Hermes.ps1'
$savedUserHome = [Environment]::GetEnvironmentVariable('HERMES_HOME', 'User')
$savedUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')

function New-CompiledExe {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Source)
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $src = Join-Path $env:TEMP ('stub-' + [guid]::NewGuid().ToString('n') + '.cs')
    Set-Content -LiteralPath $src -Value $Source -Encoding ASCII
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $csc /nologo /out:$Path $src | Out-Host
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Path)) { throw "compile failed: $Path" }
}

$toolDir = Join-Path $env:TEMP ('hermes-stubs-' + [guid]::NewGuid().ToString('n'))
$hermesStub = Join-Path $toolDir 'hermes-stub.exe'
$pythonStub = Join-Path $toolDir 'python-stub.exe'
$uvStub = Join-Path $toolDir 'uv-stub.exe'
New-CompiledExe $hermesStub @'
using System;
using System.IO;
using System.Reflection;
public class HermesStub {
  public static void Main() {
    Console.WriteLine("Hermes Agent v0.21.0 (2026.8.31)");
    if (Environment.GetEnvironmentVariable("HERMES_STUB_DELETE_SELF") == "1") {
      string loc = Assembly.GetExecutingAssembly().Location;
      File.Move(loc, loc + ".ran");
    }
  }
}
'@
New-CompiledExe $pythonStub @'
using System;
public class PythonStub {
  public static void Main() {
    if (Environment.GetEnvironmentVariable("HERMES_STUB_FAIL_IMPORT") == "1") {
      Console.Error.WriteLine("ModuleNotFoundError: No module named 'yaml'");
      Environment.Exit(1);
    }
    Console.WriteLine("DEPS_OK");
  }
}
'@
New-CompiledExe $uvStub @'
using System;
using System.IO;
public class UvStub {
  public static void Main() {
    Console.WriteLine("Installed 67 packages");
    string env = Environment.GetEnvironmentVariable("UV_PROJECT_ENVIRONMENT");
    if (string.IsNullOrEmpty(env)) return;
    string destDir = Path.Combine(env, "Scripts");
    Directory.CreateDirectory(destDir);
    string py = Environment.GetEnvironmentVariable("HERMES_STUB_PYTHON");
    if (!string.IsNullOrEmpty(py) && File.Exists(py)) {
      File.Copy(py, Path.Combine(destDir, "python.exe"), true);
    }
    string src = Environment.GetEnvironmentVariable("HERMES_STUB_SOURCE");
    if (!string.IsNullOrEmpty(src) && File.Exists(src)) {
      File.Copy(src, Path.Combine(destDir, "hermes.exe"), true);
    }
  }
}
'@

function New-Home {
    param([Parameter(Mandatory)][string]$Root, [switch]$WithPyproject)
    foreach ($rel in @(
        'bin', 'offline\uv-cache', 'hermes-agent', 'python', 'defaults\config'
    )) {
        New-Item -ItemType Directory -Path (Join-Path $Root $rel) -Force | Out-Null
    }
    Copy-Item $uvStub (Join-Path $Root 'bin\uv.exe') -Force
    'wheel' | Set-Content (Join-Path $Root 'offline\uv-cache\placeholder') -Encoding ASCII
    if ($WithPyproject) { 'version = "0.21.0"' | Set-Content (Join-Path $Root 'hermes-agent\pyproject.toml') -Encoding ASCII }
    'lock' | Set-Content (Join-Path $Root 'hermes-agent\uv.lock') -Encoding ASCII
    'py' | Set-Content (Join-Path $Root 'python\python.exe') -Encoding ASCII
    @{
        schemaVersion = 1
        hermesVersion = '0.21.0'
        sourceCommit = '041b6985a00d01b54f830c1607dd370007a306bf'
        pythonExecutable = 'python\python.exe'
        extras = @()
    } | ConvertTo-Json | Set-Content (Join-Path $Root 'offline\bundle-settings.json') -Encoding UTF8
}

function Invoke-Init {
    param([Parameter(Mandatory)][string]$Root)
    $stdout = Join-Path $env:TEMP ('init-out-' + [guid]::NewGuid().ToString('n') + '.txt')
    $stderr = Join-Path $env:TEMP ('init-err-' + [guid]::NewGuid().ToString('n') + '.txt')
    $proc = Start-Process -FilePath powershell.exe -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $init, '-HermesHome', $Root
    ) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $text = ''
    if (Test-Path -LiteralPath $stdout) { $text += [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) }
    if (Test-Path -LiteralPath $stderr) { $text += [string](Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) }
    [pscustomobject]@{ Exit = $proc.ExitCode; Output = $text; Log = Join-Path $env:TEMP 'hermes-msi-initialize.log' }
}

function Assert-LogOutsideInstallRoot {
    param($Result, [string]$Code)
    if (-not (Test-Path -LiteralPath $Result.Log)) { throw "missing initialize log for $Code" }
    $logFull = [IO.Path]::GetFullPath($Result.Log)
    $userRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'hermes'))
    if ($logFull.StartsWith($userRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "log is inside the install root: $logFull"
    }
    $text = Get-Content -LiteralPath $Result.Log -Raw
    if ($text -notmatch [regex]::Escape($Code)) { throw "log missing $Code : $text" }
}

try {
    $env:HERMES_STUB_SOURCE = ''
    $env:HERMES_STUB_PYTHON = $pythonStub
    $env:HERMES_STUB_DELETE_SELF = ''
    $env:HERMES_STUB_FAIL_IMPORT = ''

    $missing = Join-Path $env:TEMP ('hermes-missing-' + [guid]::NewGuid().ToString('n'))
    New-Home $missing
    $broken = Join-Path $missing 'hermes-agent.broken-test'
    New-Item -ItemType Directory -Path $broken -Force | Out-Null
    'keep' | Set-Content (Join-Path $broken 'pyproject.toml') -Encoding ASCII
    $r = Invoke-Init $missing
    if ($r.Exit -eq 0) { throw 'A-PY-005 expected failure' }
    if ($r.Output -notmatch 'HERMES_SOURCE_TREE_MISSING') { throw "A-PY-005 output: $($r.Output)" }
    if (-not (Test-Path -LiteralPath (Join-Path $broken 'pyproject.toml'))) { throw 'A-PY-005 deleted the backup' }
    Assert-LogOutsideInstallRoot $r 'HERMES_SOURCE_TREE_MISSING'

    $reloc = Join-Path $env:TEMP ('hermes-reloc-' + [guid]::NewGuid().ToString('n'))
    New-Home $reloc -WithPyproject
    $scripts = Join-Path $reloc 'hermes-agent\venv\Scripts'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null
    Copy-Item $hermesStub (Join-Path $scripts 'hermes.exe') -Force
    "relocatable = true" | Set-Content (Join-Path $reloc 'hermes-agent\venv\pyvenv.cfg') -Encoding ASCII
    New-Item -ItemType Directory -Path (Join-Path $reloc 'state') -Force | Out-Null
    @{ schemaVersion = 1; sourceCommit = '041b6985a00d01b54f830c1607dd370007a306bf' } | ConvertTo-Json |
        Set-Content (Join-Path $reloc 'state\bundle-install.json') -Encoding UTF8
    $r = Invoke-Init $reloc
    if ($r.Exit -eq 0 -or $r.Output -notmatch 'VENV_RELOCATABLE') { throw "A-PY-004 output: $($r.Output)" }
    if (Test-Path (Join-Path $reloc 'bin\hermes.cmd')) { throw 'A-PY-004 wrote hermes.cmd' }
    Assert-LogOutsideInstallRoot $r 'VENV_RELOCATABLE'

    $noCli = Join-Path $env:TEMP ('hermes-nocli-' + [guid]::NewGuid().ToString('n'))
    New-Home $noCli -WithPyproject
    $env:HERMES_STUB_SOURCE = ''
    $r = Invoke-Init $noCli
    if ($r.Exit -eq 0 -or $r.Output -notmatch 'HERMES_CLI_MISSING_POST_SYNC') { throw "A-PY-002 output: $($r.Output)" }
    Assert-LogOutsideInstallRoot $r 'HERMES_CLI_MISSING_POST_SYNC'

    $noDeps = Join-Path $env:TEMP ('hermes-nodeps-' + [guid]::NewGuid().ToString('n'))
    New-Home $noDeps -WithPyproject
    $env:HERMES_STUB_SOURCE = $hermesStub
    $env:HERMES_STUB_FAIL_IMPORT = '1'
    $r = Invoke-Init $noDeps
    $env:HERMES_STUB_FAIL_IMPORT = ''
    if ($r.Exit -eq 0 -or $r.Output -notmatch 'UV_SYNC_FAILED') { throw "hollow venv accepted: $($r.Output)" }
    Assert-LogOutsideInstallRoot $r 'UV_SYNC_FAILED'

    $vanish = Join-Path $env:TEMP ('hermes-vanish-' + [guid]::NewGuid().ToString('n'))
    New-Home $vanish -WithPyproject
    $scripts = Join-Path $vanish 'hermes-agent\venv\Scripts'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null
    Copy-Item $hermesStub (Join-Path $scripts 'hermes.exe') -Force
    Copy-Item $pythonStub (Join-Path $scripts 'python.exe') -Force
    "relocatable = false" | Set-Content (Join-Path $vanish 'hermes-agent\venv\pyvenv.cfg') -Encoding ASCII
    New-Item -ItemType Directory -Path (Join-Path $vanish 'state') -Force | Out-Null
    @{ schemaVersion = 1; sourceCommit = '041b6985a00d01b54f830c1607dd370007a306bf' } | ConvertTo-Json |
        Set-Content (Join-Path $vanish 'state\bundle-install.json') -Encoding UTF8
    $env:HERMES_STUB_DELETE_SELF = '1'
    $r = Invoke-Init $vanish
    $env:HERMES_STUB_DELETE_SELF = ''
    if ($r.Exit -eq 0 -or $r.Output -notmatch 'HERMES_CLI_MISSING_POST_SYNC') { throw "A-PY-003 output: $($r.Output)" }
    Assert-LogOutsideInstallRoot $r 'HERMES_CLI_MISSING_POST_SYNC'

    $ok = Join-Path $env:TEMP ('hermes-ok-' + [guid]::NewGuid().ToString('n'))
    New-Home $ok -WithPyproject
    $env:HERMES_STUB_SOURCE = $hermesStub
    $env:HERMES_STUB_DELETE_SELF = ''
    $r = Invoke-Init $ok
    if ($r.Exit -ne 0) { throw "A-PY-001 output: $($r.Output)" }
    if ($r.Output -match 'install\.ps1|git clone') { throw 'A-PY-001 invoked a forbidden command' }
    foreach ($exe in @(
        (Join-Path $ok 'hermes-agent\venv\Scripts\hermes.exe'),
        (Join-Path $ok 'bin\hermes.exe')
    )) {
        if (-not (Test-Path -LiteralPath $exe)) { throw "missing $exe" }
        $ver = @(& $exe --version 2>&1)
        if ($LASTEXITCODE -ne 0 -or [string]$ver[0] -notmatch '^Hermes Agent v0\.21\.0 \(') {
            throw "version failed for $exe : $ver"
        }
    }
    $marker = Get-Content (Join-Path $ok 'state\bundle-install.json') -Raw
    if ($marker -match 'COMMITTED') { throw 'marker wrote COMMITTED' }

    $evidence = Join-Path $repoRoot 'evidence'
    New-Item -ItemType Directory -Path $evidence -Force | Out-Null
    foreach ($id in @('A-PY-001', 'A-PY-002', 'A-PY-003', 'A-PY-004', 'A-PY-005', 'A-OBS-003')) {
        @{ id = $id; result = 'PASS'; utc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json |
            Set-Content (Join-Path $evidence "$id.json") -Encoding UTF8
    }
    Write-Host 'PASS: A-PY-001 A-PY-002 A-PY-003 A-PY-004 A-PY-005 A-OBS-003'
} finally {
    [Environment]::SetEnvironmentVariable('HERMES_HOME', $savedUserHome, 'User')
    [Environment]::SetEnvironmentVariable('Path', $savedUserPath, 'User')
    Remove-Item Env:HERMES_STUB_SOURCE -ErrorAction SilentlyContinue
    Remove-Item Env:HERMES_STUB_PYTHON -ErrorAction SilentlyContinue
    Remove-Item Env:HERMES_STUB_FAIL_IMPORT -ErrorAction SilentlyContinue
    Remove-Item Env:HERMES_STUB_DELETE_SELF -ErrorAction SilentlyContinue
}
