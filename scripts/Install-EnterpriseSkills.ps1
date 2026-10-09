param([Parameter(Mandatory)][string]$HermesHome)

$ErrorActionPreference = 'Stop'
$source = Join-Path $HermesHome 'defaults\enterprise-skills'
$destination = Join-Path $HermesHome 'skills'
$ledgerPath = Join-Path $HermesHome 'state\enterprise-skill-ledger-v2.json'
if (-not (Test-Path -LiteralPath $source -PathType Container)) { return }

$ledger = @{}
if (Test-Path -LiteralPath $ledgerPath) {
    $parsed = Get-Content -LiteralPath $ledgerPath -Raw | ConvertFrom-Json
    foreach ($prop in $parsed.psobject.Properties) { $ledger[$prop.Name] = [string]$prop.Value }
}

$files = @(Get-ChildItem -LiteralPath $source -Recurse -File)
foreach ($file in $files) {
    $rel = $file.FullName.Substring($source.Length).TrimStart('\')
    $dest = Join-Path $destination $rel
    if (Test-Path -LiteralPath $dest) {
        $current = (Get-FileHash -Algorithm SHA256 -LiteralPath $dest).Hash.ToLowerInvariant()
        $owned = [string]$ledger[$rel.Replace('\','/')]
        if ($owned -ne $current) { throw 'SKILL_OWNERSHIP_CONFLICT' }
    }
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
& robocopy $source $destination /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Host
if ($LASTEXITCODE -gt 7) { throw "Skill installation failed with robocopy code $LASTEXITCODE" }

$next = [ordered]@{}
foreach ($file in @(Get-ChildItem -LiteralPath $source -Recurse -File)) {
    $rel = $file.FullName.Substring($source.Length).TrimStart('\').Replace('\','/')
    $next[$rel] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
}
New-Item -ItemType Directory -Path (Split-Path -Parent $ledgerPath) -Force | Out-Null
$next | ConvertTo-Json | Set-Content -LiteralPath $ledgerPath -Encoding UTF8
