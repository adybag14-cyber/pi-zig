
### Current source target and pending contract capture — 17 October 2026

The reviewed source target is now
`c268154ca1171c2f9eefe75d3d7372a68aada2d5` (Pi 1.3.0). This source-only
marker follows the 25-file SQLite export migration and reviewed native source
ports. Combined native and complete application qualification remain pending.

The scheduled whole-tree checker still uses historical `tree-97195ec3.json`.
The c268 contract must be produced by `tools/upstream_contract.zig` through the
native maintenance capture command, then independently checked against a clean
detached authority checkout. No generated inventory or catalog was changed in
this marker update. The [c268 preparation record](verification/c268-authority-docs-contracts-sourceonly-20261017/README.md)
pins the exact machinery and distinguishes the expected 25-file immediate delta
from the much older scheduled baseline. The following records are historical;
their counts and validations continue to describe their original source heads.

### Registry dispatch and hosted validation follow-up

The hosted run of 565ea055 identified a macOS stale-registry phase dispatch and cold-build timeouts. The native task manager now refreshes its registry at every owner dispatch boundary. A deterministic regression fails on the previous code and passes with the repair on Windows and Linux in Debug and ReleaseSafe. The original full checkpoint-210 receipt still describes its original source image; the additive repair has its own verification record. The CI workflow uses a dedicated exhaustive allocation target, retains the full OS test matrix, and bounds both cold builds and individual tests. Exact-head hosted validation remains required, and native parity remains uncertified.
### Latest context discovery and source drift baseline

The selected upstream target is Pi 1.1.0 at
`f1b2e77f5b13b2a199b1052cb79c235451afe7d7`, checked against upstream main on
October 9. The added context-file fix handles symlinked nested worktrees while
preserving global-first and ancestor-to-child instruction order. Both the CLI
and native SDK resource loader use the shared Zig implementation. All four
focused Windows/Linux Debug/ReleaseSafe configurations passed, including
allocation-failure cleanup and the original-source filesystem cases.

The generated whole-tree drift manifest records all 1,947 upstream paths and
is the scheduled workflow's selected-source baseline. It detects future source
changes for review. Full native parity and release certification remain pending.
