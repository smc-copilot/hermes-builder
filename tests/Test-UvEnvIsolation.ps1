Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$candidates = @(
    @{
        Uv = Join-Path $repoRoot 'payload\bin\uv.exe'
        Agent = Join-Path $repoRoot 'payload\hermes-agent'
        Cache = Join-Path $repoRoot 'payload\offline\uv-cache'
        PythonRoot = Join-Path $repoRoot 'payload\python'
    },
    @{
        Uv = Join-Path $env:LOCALAPPDATA 'hermes\bin\uv.exe'
        Agent = Join-Path $repoRoot 'src\hermes-agent'
        Cache = Join-Path $env:LOCALAPPDATA 'hermes\offline\uv-cache'
        PythonRoot = Join-Path $env:LOCALAPPDATA 'hermes\python'
    }
)
$layout = $candidates | Where-Object {
    (Test-Path -LiteralPath $_.Uv) -and (Test-Path -LiteralPath (Join-Path $_.Agent 'pyproject.toml')) -and (Test-Path -LiteralPath $_.Cache)
} | Select-Object -First 1
if (-not $layout) { throw 'A-ENV-001 prerequisites missing: uv, hermes-agent, and uv-cache' }
$python = Get-ChildItem -LiteralPath $layout.PythonRoot -Recurse -Filter 'python.exe' -File -ErrorAction SilentlyContinue |
    Sort-Object { $_.FullName.Length } | Select-Object -First 1
if (-not $python) { throw 'A-ENV-001 packaged python.exe not found' }

function Invoke-Sync {
    param([Parameter(Mandatory)][string]$Venv, [switch]$Protected)
    if (Test-Path $Venv) { Remove-Item $Venv -Recurse -Force }
    $saved = @{}
    foreach ($name in @([Environment]::GetEnvironmentVariables().Keys)) {
        if ($name -like 'UV_*' -or $name -eq 'VIRTUAL_ENV') {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
    }
    try {
        $env:UV_CACHE_DIR = $layout.Cache
        $env:UV_PROJECT_ENVIRONMENT = $Venv
        $env:UV_PYTHON_INSTALL_DIR = $layout.PythonRoot
        $env:UV_NO_INSTALL_PROJECT = '1'
        $env:UV_NO_SYNC = '1'
        $env:VIRTUAL_ENV = Join-Path $env:TEMP 'hermes-foreign-venv'
        $syncArgs = @('sync', '--offline', '--locked', '--python', $python.FullName, '--project', $layout.Agent, '--directory', $layout.Agent)
        if ($Protected) {
            $toml = Join-Path $env:TEMP 'hermes-malicious-uv.toml'
            "link-mode = `"copy`"`r`n" | Set-Content -LiteralPath $toml -Encoding ASCII
            $env:UV_CONFIG_FILE = $toml
            foreach ($name in @([Environment]::GetEnvironmentVariables().Keys)) {
                if ($name -like 'UV_*' -or $name -eq 'VIRTUAL_ENV') {
                    Remove-Item "Env:$name" -ErrorAction SilentlyContinue
                }
            }
            $env:UV_CACHE_DIR = $layout.Cache
            $env:UV_PROJECT_ENVIRONMENT = $Venv
            $env:UV_PYTHON_INSTALL_DIR = $layout.PythonRoot
            $env:NO_COLOR = '1'
            $syncArgs = @('sync', '--offline', '--frozen', '--link-mode', 'copy', '--no-config', '--python', $python.FullName, '--project', $layout.Agent, '--directory', $layout.Agent)
            if ($syncArgs -notcontains '--no-config') { throw 'A-ENV-001 protected argv missing --no-config' }
        }
        Write-Host ("uv argv: {0} {1}" -f $layout.Uv, ($syncArgs -join ' '))
        & $layout.Uv @syncArgs
        return $LASTEXITCODE
    } finally {
        foreach ($name in @([Environment]::GetEnvironmentVariables().Keys)) {
            if ($name -like 'UV_*' -or $name -eq 'VIRTUAL_ENV') { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        }
        foreach ($name in @($saved.Keys)) { Set-Item "Env:$name" -Value $saved[$name] }
    }
}

$controlVenv = Join-Path $env:TEMP ('hermes-env-control-' + [guid]::NewGuid().ToString('n'))
$controlExit = Invoke-Sync $controlVenv
$controlExe = Join-Path $controlVenv 'Scripts\hermes.exe'
if ($controlExit -eq 0 -and (Test-Path -LiteralPath $controlExe)) {
    throw 'P-006 falsified: unprotected uv sync still produced hermes.exe. Re-investigate the missing-CLI mechanism before treating A-ENV-001 as proven.'
}
if ($controlExit -ne 0 -or (Test-Path -LiteralPath $controlExe)) {
    throw "P-006 falsified: control did not reproduce exit=0 without CLI (exit=$controlExit, exe=$(Test-Path -LiteralPath $controlExe))"
}

$protectedVenv = Join-Path $env:TEMP ('hermes-env-protected-' + [guid]::NewGuid().ToString('n'))
$protectedExit = Invoke-Sync $protectedVenv -Protected
$protectedExe = Join-Path $protectedVenv 'Scripts\hermes.exe'
if ($protectedExit -ne 0 -or -not (Test-Path -LiteralPath $protectedExe)) {
    throw "A-ENV-001 protected sync failed: exit=$protectedExit exe=$(Test-Path -LiteralPath $protectedExe)"
}
& $protectedExe --version | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'A-ENV-001 protected hermes.exe --version failed' }
if ($layout.Uv -notmatch '\\bin\\uv\.exe$') { throw "A-ENV-001 uv path is not bundled: $($layout.Uv)" }
if ($python.FullName -notmatch '\\python\.exe$') { throw 'A-ENV-001 python path is not packaged' }

$evidence = Join-Path $repoRoot 'evidence'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
@{ id = 'A-ENV-001'; result = 'PASS'; utc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json |
    Set-Content (Join-Path $evidence 'A-ENV-001.json') -Encoding UTF8
Write-Host 'PASS: A-ENV-001'
