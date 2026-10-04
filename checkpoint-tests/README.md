# Provider contract checks

Run `zig build test-provider-contracts -j2 --summary all` with final Zig 0.16.0.
On Windows, provide the existing native SQLite development library through
`-Dsqlite-lib-dir=<directory>` as for the full `zig build test` graph.

This target replaces the four Python audits that checked source substrings.
It runs the production Zig adapters' behavioral tests for persistent callback
ownership, registration replacement, OAuth interaction and cancellation,
rotated-token persistence, model publication and stale generations, atomic
model storage, and provider streams. It also runs the linked C engine's provider
binding tests and the real native worker protocol fixture with Node absent from
the child process's PATH. Those native worker checks include explicit rejection
of the signal surface that has not yet been implemented.

Production extension discovery still uses the legacy bridge. The four `.mjs`
files in this directory retain additional raw-protocol, publication and stream
cases until their harnesses have been migrated to Zig. The remaining Python PTY
scripts under `scripts/` also still need native replacements. This target does
not certify complete Pi 1.x parity or an all-Zig/C implementation tree.
