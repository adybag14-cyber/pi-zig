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
retry, deadline and final-response assertions. Global/project settings run
through `zig build test-project-settings-process`; the fixture explicitly starts
in regular mode before verifying the project fullscreen override, because Pi 1
now defaults to fullscreen. Settings-screen transactions, reload, tree filters
and quiet startup run through `zig build test-settings-screen-process`; all
fourteen report fields match the original fixture byte for byte. Staged
authentication and credential-source labels run through
`zig build test-auth-flow-process`; the unfiltered provider inventory is captured
instead of hardcoding an old total. Live credential rebinding and configured
fallback run through `zig build test-auth-live-process`, with authorization
headers asserted on actual HTTP requests. Tree controls run through
`zig build test-tree-controls-process`, creating real history over RPC and
checking durable label targets, selection, timestamps, filters and decoded
OSC 52 clipboard contents over PTY. The fixture explicitly uses a remote
session environment so desktop clipboard tools cannot replace OSC 52 output.
Summary request options run through `zig build test-summary-options-process`,
checking the actual summary output cap, absent affinity/cache fields, and
durably stored branch summary against the original fixture's thirteen gates.
Media privacy and live skill commands run through
`zig build test-media-skills-process` on Linux with the image converter available.
BMP input now normalizes to PNG before session storage, matching current Pi;
the native fixture verifies PNG CRCs, dimensions and decoded RGB pixel value,
in addition to blocked/allowed provider payloads and atomic live skill reload.
Compaction policy runs through `zig build test-compaction-policy-process`,
preserving all seventeen report gates with real extension input and RPC.
Its Zig harness currently exercises the production legacy extension backend;
the same fixture must pass after the native production-backend switch.
Branch-summary policy runs through `zig build test-branch-policy-process`,
preserving fourteen report gates, custom instructions, durable usage/label
targets and both after-tree actions. Settings inspection uses the current
selector and captures its inventory instead of old plain-text settings output.
Clipboard copying runs through `zig build test-clipboard-copy-process`, using
a native Zig helper instead of the old shell stand-in. Local, remote OSC 52
and extension-export cases verify exact bytes, one copy call and no assistant
reprint. The transcript-count fixture explicitly uses regular mode.
Clipboard pasting runs through `zig build test-clipboard-paste-process`,
retaining the exact3x2 PNG fixture, sanitized text and two durable user messages.
It also checks the actual staged image bytes/private permissions and shutdown
cleanup beneath its own TMPDIR, preserving unrelated concurrent sessions.
Session hooks run through `zig build test-session-hooks-process`, preserving
replacement, usage/cost, immediate cancel actions, durable session names and
tree label targets. An explicit20-token recent-history budget makes the small
fixture compactable; Pi's normal20000-token budget retains its whole history.
Session resume and task-owned self-update checks run through
`zig build test-session-update-process`. Model selection, lifecycle telemetry
and actual managed-tool archive/cache reuse run through
`zig build test-model-update-process`. Both use the compiled Zig tool fixture
instead of shell implementation stand-ins. All four executable image
normalization cases run through `zig build test-image-processing-process`,
including exact resize-disabled PNG bytes, BMP conversion, EXIF orientation,
base64 ceilings, read-tool persistence and extension post-hook normalization.
The image converter must be available on Linux. No Python scripts remain.
This target does
not certify complete Pi 1.x parity or an all-Zig/C implementation tree.
