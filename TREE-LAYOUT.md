# Checkpoint 185 tree layout

This checkpoint is intentionally self-contained.

- The repository root is the Zig rewrite and remains directly buildable with `zig build` and `zig build test`.
- `upstream/pi-main/` is the complete 1,366-file TypeScript/JavaScript reference snapshot supplied for parity comparison.
- `upstream/source-archive/pi-main-20260823-194058.zip` is the untouched supplied upstream ZIP.
- `UPSTREAM-PI-MAIN-FILES.sha256` inventories every extracted upstream file.
- `UPSTREAM-PI-MAIN-SOURCE.sha256` authenticates the embedded upstream ZIP.
- `FILES.sha256` inventories the complete checkpoint after all reports are finalized.
- `verification/checkpoint-185/` contains the focused and full validation logs.

Generated Zig caches, `zig-out`, `.git`, Python bytecode, and transient test directories are deliberately excluded from the release archive.
