# Pi-zig project container

Keep all project checkouts, upstream references, evidence, generated staging
files and toolchains inside this folder. Do not create new `pi-zig-*` or
`pi-upstream-*` directories beside it.

- `main/` is Root's exclusive integration checkout. Agents must not edit it.
- `worktrees/` holds assigned agent branches. Create new worktrees there through
  `main/`; use the exact assigned worktree and coordinate shared-file changes.
- `upstream/` holds official source snapshots and pinned runtime dependencies.
  Treat accepted references as immutable. The deleted 19cb runtime must pass its
  complete original manifest before it becomes usable authority again.
- `evidence/` retains original proofs, negatives, raw captures and move receipts.
  Never rewrite historical observations or receipts to accommodate relocation.
- `toolchain/` contains the pinned Zig 0.16.0 compiler. Do not use the different
  Zig version on the global PATH.

Read `.pi-zig-workspace.json` for current paths and `path-relocations.json` when
checking an old absolute path. Explicitly distinguish relocation from a new test
execution. Existing missing/locked historical worktree records remain preserved.

No native build, Node reference capture or source generator starts without Root's
specific resource/ownership grant. Preserve the proven bounded process owners,
serial native lease, fresh 16 GiB admission, exact metadata, complete pre/post
seals and independent process absence. Source-only edits and static review do
not establish runtime or whole-application qualification.

The implementation remains Zig 0.16 plus permitted direct C interoperability.
User JavaScript/TypeScript extensions run through the linked C runtime; they do
not authorize retaining a production Node, Python or TypeScript host bridge.

Cleanup follows the user's Recycle Bin requirement. Only retire unnecessary
material after its exact source/evidence is published and no live dependency
needs it. Never permanently delete or empty the bin.
