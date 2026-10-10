
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
