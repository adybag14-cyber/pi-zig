# Pi Zig checkpoint 164

Checkpoint 164 continues from the uploaded native checkpoint 163 against the newly supplied original Pi coding-agent **0.84.1** source tree, using the supplied Zig **0.16.0** compiler. This pass closes the original compaction and session-tree extension lifecycle boundary across the actual native execution paths rather than exposing hook names without awaited runtime effects.

## Major native port additions

### Native compaction hook contracts

The Zig compactor now exposes original-style callback contracts for:

```text
session_before_compact
session_compact
```

The before-hook receives a live session projection containing the active branch, first retained entry, estimated tokens, previous summary, custom instructions, compaction reason, retry intent, and the extension abort signal. A JavaScript or TypeScript extension can:

- cancel compaction;
- supply a complete summary replacement;
- select the retained entry;
- preserve its own `tokensBefore` value;
- attach structured details;
- attach complete usage and cost metadata.

Replacement summaries are validated before persistence. Empty summaries and retained-entry IDs outside the active branch are rejected without mutating the append-only session tree.

The after-hook receives the exact saved compaction entry together with `fromExtension`, reason, and `willRetry`. Extension-provided details, usage, cost, and `fromHook` remain durable through JSONL save/load and RPC entry projection.

### Automatic, manual, and RPC integration

The lifecycle is wired into all implemented compaction paths:

- threshold-triggered automatic compaction;
- context-overflow recovery compaction;
- interactive `/compact`;
- JSONL RPC `compact`.

Automatic overflow compaction forwards `willRetry:true`; ordinary threshold and manual compaction forward `false`. The original reason identity—manual, threshold, or overflow—is retained in hook payloads.

RPC cancellation is now a typed command failure rather than a process-fatal error. Cancellation-hook actions are still drained, applied, saved, and visible to following RPC commands.

### Native session-tree hook contracts

The native tree workflow now exposes:

```text
session_before_tree
session_tree
```

The before-hook receives the target, old leaf, deepest common ancestor, abandoned entries, summary request, custom instructions, replacement flag, label, and live abort signal. It can:

- cancel navigation;
- provide a complete branch summary without a model call;
- replace or augment summarization instructions;
- provide a branch label;
- attach structured details and complete usage/cost metadata.

The after-hook receives the final leaf, old leaf, saved branch-summary entry when present, and extension-origin metadata.

### Original navigation position behavior

Selecting a user or custom message through `/tree` now follows the original editing contract:

- the new branch starts at the selected entry's parent;
- the selected text is returned for editor prefill;
- non-user entries remain direct navigation targets;
- summaries attach at the resulting navigation position;
- labels attach to the summary when one exists, otherwise to the selected target.

Branch summaries preserve `fromHook`, details, usage/cost data, and labels through JSONL save/load.

### Awaited extension side effects

Actions emitted by compaction and tree hooks are no longer left queued until a later agent turn. Manual slash commands, RPC compaction, and automatic compaction drain the ordered extension action FIFO immediately after the awaited hook boundary.

This includes:

- session naming;
- durable custom entries and labels;
- model and thinking-level changes;
- active-tool changes and schema rebuilding;
- steering and follow-up messages;
- abort and shutdown requests.

The native flush path preserves ownership and forwards queued steering/follow-up messages into the appropriate interactive or RPC queues.

### Extension event fidelity

The persistent JavaScript/TypeScript bridge now serializes original-shaped entries and message projections for all four events. Hook invocations receive a live `AbortSignal`, and `ctx.signal` is the same object exposed on the event.

The bridge parses the last effective replacement across extension handlers, isolates malformed handler results, and preserves canonical action ordering. The generic event bridge now supplies the event `type` consistently to original handlers.

## Real executable lifecycle gate

`scripts/session_hooks_e2e.py` uses both a persistent JSONL RPC process and a real pseudo-terminal process.

The RPC phase:

1. creates four user/assistant turns;
2. invokes extension-replaced compaction;
3. verifies the replacement summary and details in the RPC response;
4. verifies `session_compact` actions are visible immediately through `get_state` and `get_entries`;
5. invokes a cancellation path;
6. verifies cancellation actions are visible immediately and no second boundary is appended;
7. exits cleanly with zero stderr.

The pseudo-terminal phase reopens the same session and runs a real `/tree ... --summary` command. It verifies:

- extension-supplied branch summary;
- `fromHook:true`;
- structured details;
- usage total 90;
- label `tree-label-164`;
- immediate `session_tree` custom entry;
- final session name `tree-hooked-164`;
- clean process exit with zero stderr.

The complete observed record is stored in `SESSION-HOOKS-E2E-164.txt`.

## Development-tree validation

```text
Supplied Zig compiler:                     0.16.0
Native Zig source files:                   179
Native Zig logical lines:                  100,988
Embedded JavaScript bridge lines:          984
Named Zig test declarations:               887
Synthetic/generated feature shards:        0

Direct complete root closure:              889/889 passed
Normal all-package module process:          882 passed, 7 isolated, 0 failed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                   8 passed, 6 isolated, 0 failed
Ordinary executable process:                 9/9 passed
SQLite live-persistence process:             5/5 passed
SQLite-enabled executable process:           9/9 passed
Build-test graph:                          13/13 steps succeeded

Whole-tree Zig formatting:                 passed
Node bridge syntax validation:             passed
Real-source audit:                         passed
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug build:                passed
Session hook executable E2E:               passed
Child-process stderr:                       0 bytes
```

The direct root command explicitly linked SQLite and libc and executed all 889 cases without skips. The normal build graph deliberately isolates seven C-linked SQLite cases from the large module process; all seven execute successfully in their dedicated linked repository and CLI processes.

Final archive, patch-reconstruction, executable, and transfer gates are recorded in `VALIDATION-164.txt`.

## Remaining parity boundary

Checkpoint 164 closes the compaction and tree extension interception points, replacement/cancellation behavior, durable hook metadata, awaited side effects, and core tree navigation semantics. Complete Pi 0.84.1 monorepo equivalence is still not claimed.

The highest-value remaining areas are:

1. Original token-budget cut-point selection, split-turn prefix handling, and reserve-token settings instead of the current message-count retention control.
2. Complete compaction and branch-summary prompts, file-operation extraction, prior-summary merge policy, and branch-summary reserve-token behavior.
3. Full compaction/tree progress events, cancellation controls, selectors, and fullscreen tree workflow.
4. Retry-policy propagation through OAuth, cloud credential, catalog-refresh, and update-check bootstrap requests.
5. Complete package, model, login, settings, session, and tree fullscreen managers.
6. Complete npm, pnpm, and Bun workspace, lockfile, lifecycle-script, and platform behavior.
7. Arbitrary extension-owned retained component trees with asynchronous invalidation.
8. Function-valued provider transports and extension-owned OAuth/login callbacks.
9. Native server TLS and mutual TLS.
10. Automatic image resizing, EXIF-orientation normalization, and transcoding.
11. Remaining enterprise credential, telemetry, retry, and cross-language interoperability breadth.
