# Checkpoint 187 tree layout

This is the final Zig-only rewrite tree.

- The repository root is directly buildable with `zig build` and `zig build test` using Zig 0.16.0.
- `src/` contains the native implementation plus the JavaScript extension bridge required to execute user extensions.
- `src/ai/catalog_source.json` is the exact language-neutral Pi AI 0.84.1 model-data input.
- `src/ai/catalog_generated.zig` is generated deterministically from that input by `scripts/generate_builtin_catalog.mjs`.
- `checkpoint-tests/` contains executable custom-provider and compatibility fixtures.
- `verification/` and the checkpoint reports retain the historical evidence without retaining the reference source tree.
- `FILES.sha256` inventories the final tracked artifact after all reports are finalized.

The 1,366-file `upstream/pi-main` TypeScript/JavaScript snapshot and its source ZIP were removed only after checkpoint 187 passed the local ReleaseSafe/test gates and uncached Windows, Ubuntu, and ARM64 macOS CI. Generated Zig caches, `zig-out`, `.git`, Python bytecode, dependencies, and transient test directories are excluded from the repository artifact.
