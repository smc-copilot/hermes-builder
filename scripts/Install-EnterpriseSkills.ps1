param([Parameter(Mandatory)][string]$HermesHome)

$ErrorActionPreference = 'Stop'
$source = Join-Path $HermesHome 'defaults\enterprise-skills'
$destination = Join-Path $HermesHome 'skills'
if (Test-Path -LiteralPath $source -PathType Container) {
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    # Merge at the skills root, retaining category paths and unrelated user files.
    # Do not use /MIR: this directory also contains user-installed skills.
    & robocopy $source $destination /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Host
    if ($LASTEXITCODE -gt 7) { throw "Skill installation failed with robocopy code $LASTEXITCODE" }
}
