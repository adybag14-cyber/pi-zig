# Native repository tree

The active update targets upstream Pi commit
`4c6fb7cfe8c538a668726f6f8b3554098c39faee` (package version 1.0.1).
Complete behavioral parity remains in progress; see
`UPSTREAM-UPDATE-20261003.md` for the completed gates and outstanding work.

- The repository root builds with `zig build` and `zig build test` using final
  Zig 0.16.0.
- `src/` contains the native implementation and the legacy extension bridge.
  Production discovery keeps that bridge until the replacement passes the
  compatibility gates. User-authored extension input will run through the
  directly linked C engine and parser; host implementation remains Zig/C.
- `vendor/` contains pinned C engine/parser dependencies, their licenses and
  per-file digest manifests checked by `zig build maintenance -- verify-vendors`.
- `src/ai/catalog_source.json` records the exact typed, immutable catalog input
  and separate source-archive/catalog provenance. `tools/catalog.zig` generates
  `src/ai/catalog_generated.zig`; `zig build maintenance -- catalog --check`
  verifies byte-exact regeneration.
- `zig build maintenance -- import-catalog <json> <version> <commit>
  <source-archive> <revision> <destination>` validates catalog revision digests
  before recording the language-neutral input. It executes no upstream code.
- `zig build maintenance -- import-changelog <upstream-checkout>
  <expected-commit>` reads committed package/changelog Git objects and imports
  the text into `src/coding_agent/assets/UPSTREAM-CHANGELOG.md`.
- `tools/maintenance.zig` retains the structural surface audit. The separate
  `audit-source` command enforces implementation languages and deliberately
  fails while remaining Python/JavaScript scripts are being ported.
- `checkpoint-tests/` and `scripts/` contain remaining compatibility fixtures
  to port. Their behavior must remain covered before retirement.
- `verification/` and historical checkpoint reports retain prior evidence.
  `zig build maintenance -- artifact-manifest 189` regenerates `FILES.sha256`
  and `ARTIFACT-MANIFEST.json` for the active checkpoint, without certifying
  behavioral parity. `zig build maintenance -- verify-artifacts` rejects stale
  inventories and changed digests. Regenerate after any retained source change.

The retired reference snapshot remains outside this repository. Current
upstream investigation uses an isolated reference checkout; its TypeScript
implementation is not imported into the native tree. Build caches, `zig-out`,
Git internals, dependencies and transient fixture directories are excluded.
