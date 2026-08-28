#!/usr/bin/env python3
"""Fail if synthetic/generated surface code is reintroduced into pi-zig."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
FORBIDDEN_NAMES = {"generated_root.zig", "tools_extended.zig", "tools_dispatch.zig", "catalog_index.zig", "routes_all.zig", "methods_all.zig"}
FORBIDDEN_FRAGMENTS = ("_shard_",)

zig_files = sorted(SRC.rglob("*.zig"))
bad = [p for p in zig_files if p.name in FORBIDDEN_NAMES or any(x in p.name for x in FORBIDDEN_FRAGMENTS)]
if (ROOT / "scripts" / "gen_surface.py").exists():
    bad.append(ROOT / "scripts" / "gen_surface.py")

loc = sum(sum(1 for _ in p.open("r", encoding="utf-8", errors="replace")) for p in zig_files)
print(f"zig_files={len(zig_files)}")
print(f"zig_loc={loc}")
print(f"synthetic_files={len(bad)}")
for p in bad:
    print(f"forbidden: {p.relative_to(ROOT)}")
sys.exit(1 if bad else 0)
