"""Build runtime-manifest-v2.json and a detached Ed25519 signature.

The seed is read only from HERMES_MANIFEST_ED25519_SEED_B64. It is never printed.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
import unicodedata
from pathlib import Path

KEY_ID = "e6199f4b558ab9c4"
PUB_HEX = "77bab465c8de1e57e3738cb6ca6fd526378d6589f772e914626f5417909f8de1"
REQUIRED = (
    "bin/uv.exe",
    "bin/rg.exe",
    "bin/ffmpeg.exe",
    "bin/ffprobe.exe",
    "node/node.exe",
    "hermes-agent/pyproject.toml",
    "hermes-agent/uv.lock",
    "offline/bundle-settings.json",
)
EXCLUDED_NAMES = {"runtime-manifest-v2.json", "runtime-manifest-v2.sig"}
EXCLUDED_PARTS = {"venv", "node_modules", ".work", "dist", "evidence"}


def fail(code: str) -> None:
    print(code, file=sys.stderr)
    raise SystemExit(1)


def canonical(rel: str) -> str:
    text = rel.replace("\\", "/")
    text = unicodedata.normalize("NFC", text)
    if text.startswith("/") or ".." in text.split("/"):
        fail(f"PATH_ESCAPE_DENIED: {text}")
    return text


def tree_digest(entries: list[tuple[str, str, int]]) -> str:
    ordered = sorted(entries, key=lambda item: item[0].encode("utf-8"))
    buf = bytearray()
    for path, digest, size in ordered:
        buf += path.encode("utf-8")
        buf += b"\x00"
        buf += digest.encode("ascii")
        buf += b"\x00"
        buf += str(size).encode("ascii")
        buf += b"\n"
    return hashlib.sha256(buf).hexdigest()


def collect(payload: Path) -> list[tuple[str, str, int]]:
    found: dict[str, tuple[str, str, int]] = {}
    for path in payload.rglob("*"):
        if not path.is_file():
            continue
        rel = canonical(str(path.relative_to(payload)))
        if Path(rel).name in EXCLUDED_NAMES:
            continue
        parts = {part.casefold() for part in rel.split("/")}
        if parts & {item.casefold() for item in EXCLUDED_PARTS}:
            continue
        key = rel.casefold()
        if key in found and found[key][0] != rel:
            fail(f"PATH_CASE_COLLISION: {found[key][0]} vs {rel}")
        data = path.read_bytes()
        found[key] = (rel, hashlib.sha256(data).hexdigest(), len(data))
    entries = list(found.values())
    present = {item[0].casefold() for item in entries}
    for required in REQUIRED:
        if required.casefold() not in present:
            fail(f"BUILD_PROVENANCE_MISSING: required payload file missing: {required}")
    return entries


def load_seed() -> bytes:
    raw = os.environ.get("HERMES_MANIFEST_ED25519_SEED_B64", "").strip()
    if not raw:
        fail("MANIFEST_SIGNING_KEY_MISSING")
    try:
        seed = base64.b64decode(raw, validate=True)
    except Exception:
        fail("MANIFEST_SIGNING_KEY_MISSING")
    if len(seed) != 32:
        fail("MANIFEST_SIGNING_KEY_MISSING")
    return seed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--installer-version", required=True)
    parser.add_argument("--agent-version", required=True)
    parser.add_argument("--venv-estimated-bytes", required=True, type=int)
    args = parser.parse_args()
    if args.venv_estimated_bytes <= 0:
        fail("BUNDLE_INCOMPLETE: venvEstimatedBytes must be > 0")
    payload = Path(args.payload)
    entries = collect(payload)
    digest = tree_digest(entries)
    total = sum(item[2] for item in entries)
    if total <= 0:
        fail("BUNDLE_INCOMPLETE: uncompressedPayloadBytes must be > 0")
    manifest = {
        "schemaVersion": 2,
        "installerVersion": args.installer_version,
        "agentVersion": args.agent_version,
        "sourceCommit": args.source_commit,
        "payloadTreeSha256": digest,
        "uncompressedPayloadBytes": total,
        "venvEstimatedBytes": args.venv_estimated_bytes,
        "keyId": KEY_ID,
        "files": [
            {"path": path, "sha256": file_hash, "size": size}
            for path, file_hash, size in sorted(entries, key=lambda item: item[0].encode("utf-8"))
        ],
    }
    body = json.dumps(manifest, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    out = payload / "runtime-manifest-v2.json"
    out.write_bytes(body)
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization

    seed = load_seed()
    key = Ed25519PrivateKey.from_private_bytes(seed)
    pub = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    if pub.hex() != PUB_HEX or hashlib.sha256(pub).hexdigest()[:16] != KEY_ID:
        fail("MANIFEST_SIGNING_KEY_MISSING")
    sig = key.sign(body)
    (payload / "runtime-manifest-v2.sig").write_text(base64.b64encode(sig).decode("ascii"), encoding="ascii")
    print(f"payloadTreeSha256={digest}")
    print(f"uncompressedPayloadBytes={total}")
    print(f"keyId={KEY_ID}")


if __name__ == "__main__":
    main()
