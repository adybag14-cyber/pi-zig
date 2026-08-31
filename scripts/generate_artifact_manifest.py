#!/usr/bin/env python3
"""Regenerate the tracked-source artifact manifest and SHA-256 inventory."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FILES_MANIFEST = "FILES.sha256"
ARTIFACT_MANIFEST = "ARTIFACT-MANIFEST.json"


def inventory_paths() -> list[str]:
    raw = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
    )
    paths = []
    for item in raw.split(b"\0"):
        if not item:
            continue
        path = item.decode("utf-8").replace("\\", "/")
        if path == FILES_MANIFEST:
            continue
        if any(part in {".git", ".zig-cache", "zig-out", "node_modules", "__pycache__"} for part in Path(path).parts):
            continue
        if (ROOT / path).is_file():
            paths.append(path)
    return sorted(set(paths), key=lambda value: value.encode("utf-8"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


paths = inventory_paths()
catalog_path = ROOT / "src/ai/catalog_source.json"
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
zig_files = sorted((ROOT / "src").rglob("*.zig"))
zig_lines = sum(sum(1 for _ in path.open("r", encoding="utf-8", errors="replace")) for path in zig_files)
total_bytes = sum((ROOT / path).stat().st_size for path in paths if path != ARTIFACT_MANIFEST)

artifact = {
    "checkpoint": 188,
    "release_version": "1.1.0",
    "complete_inventory": FILES_MANIFEST,
    "continuation": "CONTINUATION.md",
    "excluded_generated_paths": [".git", ".zig-cache", "zig-out", "node_modules", "__pycache__"],
    "file_count_excluding_FILES_sha256": len(paths),
    "root": "pi-zig",
    "total_bytes_excluding_FILES_sha256_and_ARTIFACT_MANIFEST": total_bytes,
    "generated_catalog": {
        "generated": "src/ai/catalog_generated.zig",
        "models": catalog["modelCount"],
        "providers": catalog["providerCount"],
        "source": "src/ai/catalog_source.json",
        "source_sha256": sha256(catalog_path),
        "upstream_commit": catalog["upstreamCommit"],
        "upstream_release": catalog["upstreamVersion"],
        "upstream_release_archive_sha256": catalog["upstreamReleaseArchiveSha256"],
        "upstream_structure_sha256": catalog["upstreamModelDataStructureHash"],
    },
    "retired_reference": {
        "archive_sha256": "42162e1ea09cfaf78ec737862255b919789eef7defd73f413dbb58c8dee0aa1a",
        "files_removed": 1366,
        "removed_at_checkpoint": 187,
        "restored": False,
    },
    "verification": "verification/checkpoint-188/verification-summary.json",
    "zig_source": {"files": len(zig_files), "lines": zig_lines},
}
(ROOT / ARTIFACT_MANIFEST).write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8", newline="\n")

paths = inventory_paths()
lines = [f"{sha256(ROOT / path)}  {path}" for path in paths]
(ROOT / FILES_MANIFEST).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
print(f"files={len(paths)}")
print(f"bytes_without_manifests={total_bytes}")
print(f"zig_files={len(zig_files)}")
print(f"zig_lines={zig_lines}")
