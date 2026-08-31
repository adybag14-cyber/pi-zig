# Checkpoint 188 tree layout

This is the final Zig-only rewrite tree.

- The repository root is directly buildable with `zig build` and `zig build test` using Zig 0.16.0.
- `src/` contains the native implementation plus the JavaScript extension bridge required to execute user extensions.
- `src/ai/catalog_source.json` is the exact language-neutral Pi AI 0.84.4
  release model-data input, imported from the verified release archive.
- `src/ai/catalog_generated.zig` is generated deterministically from that input by `scripts/generate_builtin_catalog.mjs`.
- `scripts/import_upstream_catalog.mjs` and
  `scripts/import_upstream_changelog.mjs` require a commit-pinned isolated
  upstream checkout and reproduce the two retained upstream projections.
- `checkpoint-tests/` contains executable custom-provider and compatibility fixtures.
- `verification/` and the checkpoint reports retain the historical evidence without retaining the reference source tree.
- `FILES.sha256` inventories the final tracked artifact after all reports are finalized.

The 1,366-file `upstream/pi-main` TypeScript/JavaScript snapshot and its source
ZIP remain retired. Pi 0.84.4 was audited from the isolated checkout
`C:\Users\adyba\pi-upstream-audit-853a80d`, which is not part of this tree or
release artifact. Generated Zig caches, `zig-out`, `.git`, Python bytecode,
dependencies, upstream audit checkouts, and transient test directories are
excluded from the repository artifact.
