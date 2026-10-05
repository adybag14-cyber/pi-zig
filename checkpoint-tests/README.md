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
the child process's PATH. Those native worker checks also pass real native signal objects to providers.
Concurrent cancellation while an asynchronous request is pending remains a port.

Production extension discovery still uses the legacy bridge. The four `.mjs`
files in this directory retain additional raw-protocol, publication and stream
cases until their harnesses have been migrated to Zig. The remaining Python PTY
scripts under `scripts/` also still need native replacements. The authentication
screen fixture now runs through `zig build test-auth-screen` on Linux using a
native Zig PTY harness; its eleven report fields match the former Python fixture.
The OAuth dialog fixture runs through `zig build test-auth-dialog`, including
a native browser-opener fixture and loopback OAuth service. Bootstrap network
gates run through `zig build test-bootstrap-network`, covering retry headers,
timeouts, token persistence, proxy fallback and target-aware bypass. Windows
and macOS explicitly skip these Linux fixtures. Provider retry and live RPC
reload gates run through `zig build test-provider-retry-process`. Its Responses
mock matches the current upstream gpt-4o catalog while preserving the original
retry, deadline and final-response assertions. Fifteen Python scripts remain.
This target does
not certify complete Pi 1.x parity or an all-Zig/C implementation tree.
