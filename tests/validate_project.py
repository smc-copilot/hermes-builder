from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "build-config.json",
    "build/Build.ps1",
    "build/Prepare-Source.ps1",
    "build/Prepare-Runtime.ps1",
    "build/Prepare-OfflineDependencies.ps1",
    "build/Prepare-EnterpriseContent.ps1",
    "build/Prepare-Skills.ps1",
    "build/Generate-Manifest.ps1",
    "scripts/Initialize-Hermes.ps1",
    "scripts/Install-EnterpriseSkills.ps1",
    "scripts/Cleanup-Hermes.ps1",
    "scripts/Repair-Hermes.ps1",
    "scripts/Verify-Installation.ps1",
    "installer/HermesEnterprise.Setup.wixproj",
    "installer/Package.wxs",
]


def fail(msg: str) -> None:
    print(f"FAIL: {msg}")
    raise SystemExit(1)


for rel in REQUIRED:
    if not (ROOT / rel).is_file():
        fail(f"missing required file: {rel}")

cfg = json.loads((ROOT / "build-config.json").read_text(encoding="utf-8"))
if cfg["source"]["mode"] != "local-preferred":
    fail("source.mode must prefer the local Hermes checkout")
if cfg["source"].get("localPath") != "src/hermes-agent":
    fail("source.localPath must be src/hermes-agent")
if cfg["source"].get("defaultBranch") != "main":
    fail("local source checkout must use the main branch")
if cfg["source"]["repository"] != "https://github.com/loudon84/copilot-hermes.git":
    fail("unexpected source repository")
if cfg["source"]["expectedVersion"] != "0.21.0":
    fail("expected Hermes version must be 0.21.0")
if not re.fullmatch(r"[0-9a-f]{40}", cfg["source"]["ref"]):
    fail("default source ref must be a pinned 40-char commit SHA")
if cfg["target"]["architecture"] != "x64" or not cfg["target"]["perUser"]:
    fail("v1 package must be Windows x64 per-user")
if cfg["target"]["includeDesktop"] or cfg["target"]["includePlatformSdks"]:
    fail("core v1 package must keep Desktop/Platform SDK disabled")

wix = ROOT / "installer/Package.wxs"
ET.parse(wix)
wix_text = wix.read_text(encoding="utf-8")
wixproj_text = (ROOT / "installer/HermesEnterprise.Setup.wixproj").read_text(encoding="utf-8")
if "WixToolset.Sdk/5.0.2" not in wixproj_text or "WixToolset.Util.wixext\" Version=\"5.0.2\"" not in wixproj_text:
    fail("WiX project must use the WiX 5 SDK for Files harvesting")
if "<SuppressIces>ICE38;ICE64</SuppressIces>" not in wixproj_text:
    fail("WiX per-user project must explicitly suppress only ICE38 and ICE64")
for expected in [
    'Scope="perUser"',
    'Id="LocalAppDataFolder"',
    'Id="InitializeHermes"',
    'Wix4UtilCA_X64',
    'Include="$(var.PayloadDir)\\**"',
]:
    if expected not in wix_text:
        fail(f"WiX authoring missing: {expected}")

build_text = (ROOT / "build/Build.ps1").read_text(encoding="utf-8")
if "Prepare-Source.ps1" not in build_text or "dotnet" not in build_text:
    fail("Build.ps1 does not orchestrate source checkout and WiX build")

common_text = (ROOT / "build/Common.ps1").read_text(encoding="utf-8")
if "& $FilePath @Arguments | Out-Host" not in common_text:
    fail("Invoke-Native must keep command output out of captured return values")
if '<Files Directory="HermesRoot"' in wix_text or '<Files Include="$(var.PayloadDir)\\**"' not in wix_text:
    fail("WiX payload harvest must use the payload include pattern")
for expected in ['<Feature Id="MainFeature"', '<ComponentGroupRef Id="PayloadComponents"', '<ComponentGroup Id="PayloadComponents" Directory="HermesRoot">']:
    if expected not in wix_text:
        fail(f"WiX payload harvest missing component group wiring: {expected}")

source_text = (ROOT / "build/Prepare-Source.ps1").read_text(encoding="utf-8")
for token in ["localPath", "branch --show-current", "pull", "--ff-only", "clone"]:
    if token not in source_text:
        fail(f"Prepare-Source.ps1 missing local-first source behavior: {token}")

runtime_text = (ROOT / "build/Prepare-Runtime.ps1").read_text(encoding="utf-8")
for stage in ["'uv'", "'python'", "'git'", "'node'"]:
    if stage not in runtime_text:
        fail(f"runtime preparation missing upstream stage {stage}")
for token in ["$stage -eq 'node'", "$env:Path", "Join-Path $_ 'node.exe'", "-Ensure", "'node'"]:
    if token not in runtime_text:
        fail(f"runtime preparation must isolate system Node during packaging: {token}")
for token in ["Get-Command git", "$gitRoot", "Copy-Tree $gitRoot"]:
    if token not in runtime_text:
        fail(f"runtime preparation must stage a Git runtime when upstream reuses system Git: {token}")
if "python install" not in runtime_text:
    fail("runtime preparation must install managed Python into the payload")
for token in ["Get-Command rg", "Get-Command ffmpeg", "Get-Command ffprobe"]:
    if token not in runtime_text:
        fail(f"runtime preparation must prefer locally installed system tools: {token}")

offline_text = (ROOT / "build/Prepare-OfflineDependencies.ps1").read_text(encoding="utf-8")
for token in ["$payloadNodeDir", "$nodeUserPath"]:
    if token not in offline_text:
        fail(f"offline node dependency preparation must prioritize payload Node: {token}")

offline_text = (ROOT / "build/Prepare-OfflineDependencies.ps1").read_text(encoding="utf-8")
for token in ["--locked", "--offline", "UV_CACHE_DIR", "node-deps", "npm_config_offline", "PLAYWRIGHT_BROWSERS_PATH", "Remove-NodeModulesTrees", "$npxPath", "npx.cmd"]:
    if token not in offline_text:
        fail(f"offline dependency preparation missing token: {token}")

init_text = (ROOT / "scripts/Initialize-Hermes.ps1").read_text(encoding="utf-8")
for token in ["--offline", "--locked", "Copy-IfMissing", "HERMES_HOME"]:
    if token not in init_text:
        fail(f"initializer missing token: {token}")

# The local source checkout is an accepted build input; generated payload is not.
for forbidden in [ROOT / "payload"]:
    if forbidden.exists():
        fail(f"generated/vendor directory must not ship in source project: {forbidden.relative_to(ROOT)}")

# Environment templates intentionally hold deployment defaults, including
# empty values. Validate variable definitions, not credential/URL validity.
env_template = ROOT / "enterprise/config/.env.template"
for line_number, line in enumerate(env_template.read_text(encoding="utf-8-sig").splitlines(), 1):
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    if not re.fullmatch(r"\s*(?:export\s+)?[A-Za-z_][A-Za-z0-9_]*\s*=.*", line):
        fail(f"invalid environment variable definition at line {line_number}")

# Basic secret hygiene in other packaging templates/scripts. The local Hermes
# checkout is upstream input and may contain intentionally fake .env examples.
secret_patterns = [r"sk-[A-Za-z0-9]{20,}", r"ghp_[A-Za-z0-9]{20,}"]
local_source = ROOT / "src/hermes-agent"
for p in ROOT.rglob("*"):
    if not p.is_file() or p.suffix.lower() in {".png", ".jpg", ".zip"}:
        continue
    if local_source in p.parents:
        continue
    if p == env_template:
        continue
    try:
        text = p.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    for pattern in secret_patterns:
        if re.search(pattern, text):
            fail(f"possible secret detected in {p.relative_to(ROOT)}")

print("PASS: packaging project static validation")
