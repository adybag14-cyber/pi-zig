# Pi Zig V8 checkpoint 147

Checkpoint 147 continues the native Zig 0.16.0 rewrite from the exact uploaded
checkpoint-146 archive and uses the supplied Pi 0.84.1 source tree as the
behavioral reference. This pass closes a large part of the original script
extension UI and live-context boundary rather than adding generated surface
code.

## Source measurements

```text
Native Zig files under src/:              168
Native Zig logical lines under src/:      81,047
Embedded JavaScript bridge lines:            602
Zig test declarations:                       758
Gain over checkpoint 146:                  1 Zig file / 1,817 Zig lines
Implementation files changed:                  8
Implementation additions/deletions:       +2,161 / -100
Synthetic/generated feature shards:            0
```

## Bidirectional script-extension UI

The persistent JavaScript/TypeScript worker can now suspend an extension call,
issue one or more native UI requests, receive correlated results, and then
continue the same async handler. The protocol supports interleaved synchronous
UI mutations without mistaking extension stdout for protocol traffic.

Implemented request paths include:

- `ctx.ui.select()` with native choice selection;
- `ctx.ui.confirm()`;
- `ctx.ui.input()`;
- `ctx.ui.editor()` with caller-supplied initial text;
- `ctx.ui.custom()` with a bounded native compatibility surface;
- deterministic `null`/`false` fallbacks in print, JSON and RPC modes.

Implemented retained UI actions include:

- notifications and status items;
- above-editor and below-editor widgets;
- custom header and footer lines;
- terminal-title changes with control-character sanitization;
- working-indicator frames and hidden-thinking labels;
- editor replacement and paste-to-editor behavior;
- retained custom-surface and theme metadata.

Every script worker receives a host-owned bridge. UI failures are isolated to
the requesting extension, response JSON is validated before it crosses the
worker protocol, and the native controller serializes retained state updates.

## Nested editor and terminal behavior

The native line editor now accepts prefilled text through the same Unicode,
history, paste, completion, keybinding and shortcut path as the main REPL.
Nested dialogs preserve an already-active raw terminal mode and restore the
outer editor correctly after the extension dialog closes.

The interactive shell consumes pending `setEditorText()`/`pasteToEditor()`
state, permits extension-owned headers and footers, and flushes retained status
and widget output at safe prompt boundaries.

## Live extension context and session manager

Script calls now receive a fresh, owned context snapshot containing:

- execution mode, UI availability, cwd, width and current editor text;
- active provider/model/thinking level and project-trust state;
- active tools and the complete deduplicated native/extension tool registry;
- the available model catalog and configured provider identities;
- session ID, name, file and directory;
- canonical session header;
- all durable entries;
- active branch entries and leaf ID.

The compatibility session manager implements defensive snapshots for
`getEntries`, `getBranch`, `getEntry`, `getLeafId`, `getLeafEntry`, `getLabel`,
`getHeader`, `getTree`, `getSessionId`, `getSessionFile`, `getSessionDir`,
`getSessionName`, `getCwd`, and `buildContextEntries`.

## Runtime actions are no longer discarded

Command and shortcut results now apply these actions to the live native agent:

- `setSessionName` and durable custom entries;
- append-only entry labels;
- `setModel` with native provider/model resolution and session persistence;
- `setThinkingLevel` with model-capability clamping and persistence;
- `setActiveTools` with rebuilt built-in filtering and extension tool schemas;
- prompt-delivery mode and abort/termination state where supported by the
  invoking path.

Unknown tool names are ignored instead of weakening the requested allow-list.
The worker sees the effective active tool set on its next invocation.

## Extension-tool ownership correction

Parallel extension tools execute with per-worker allocators. Checkpoint 146
could transfer a host-owned output buffer into an agent-owned result and leave
the original allocation live. The integration bridge now clones into the
caller's allocator and always releases the host-owned output with the host
allocator. The filtered-tool end-to-end run is clean under Zig's DebugAllocator.

## Validation closure

```text
Whole-tree Zig formatting:                 PASS
Node bridge syntax check:                  PASS
Real-source audit:                         PASS
All-package root graph:                    741 passed / 7 isolated / 0 failed
Root declarations:                         748
Dedicated SQLite repository:               11/11 passed
Dedicated SQLite CLI/ABI/schema:            8 passed / 6 isolated / 0 failed
Dedicated live SQLite persistence:           5/5 passed
Ordinary executable tests:                   4/4 passed
SQLite-enabled executable tests:             4/4 passed
All 758 unique declarations executed:       PASS
Debug build `pi`:                           PASS
Debug build `pi-sqlite`:                    PASS
Debug build `pi-sqlite-live`:               PASS
Interactive extension UI E2E:               PASS
Runtime actions/session-manager E2E:         PASS
Active-tool enforcement/tool-result E2E:     PASS
DebugAllocator leak check in tool E2E:       PASS
```

The seven all-package isolates are the SQLite CLI live integration case and six
C-backed repository cases. The CLI case passes in the linked SQLite CLI process
and all six repository cases pass in the dedicated repository process.

## Remaining parity boundary

Checkpoint 147 materially closes extension-owned dialogs and retained shell
state, but complete Pi 0.84.1 equivalence is not claimed. The largest remaining
areas are:

1. arbitrary extension-defined component rendering, overlays, dialogs and
   custom message/tool renderers rather than the bounded native compatibility
   surface;
2. applying every side-effect action emitted from every lifecycle/tool hook,
   including a general ordered hook-action queue;
3. script-side provider registration, model injection, OAuth/login and runtime
   reload semantics;
4. automatic installation and lifecycle management of extension npm
   dependencies;
5. complete wiring of every original coding-agent screen into the retained
   fullscreen shell;
6. native server-side TLS/mTLS, automatic image resizing/transcoding and the
   remaining enterprise credential/proxy/retry matrix;
7. broader remote-repository and cross-language byte-exact fixtures.
