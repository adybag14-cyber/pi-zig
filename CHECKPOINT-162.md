# Pi Zig checkpoint 162

Checkpoint 162 continues from the uploaded native checkpoint 161 against the newly supplied original Pi coding-agent **0.84.1** source tree, using the supplied Zig **0.16.0** compiler. This pass concentrates on retry, summarization, compaction, and session-tree fidelity rather than generated surface area.

## Major native port additions

### Shared summarization retry boundary

Model-assisted compaction and branch-summary generation now use one native retry implementation with:

- `retry.enabled`, `retry.maxRetries`, and `retry.baseDelayMs`;
- exponential, saturating, cancellation-aware backoff;
- shared transient provider and Zig transport classification;
- quota, billing, subscription, and budget fail-fast behavior;
- whole-operation and retry-only cancellation;
- exact scheduling, attempt-start, and completion callbacks.

The native event surfaces expose the upstream sequence:

```text
summarization_retry_scheduled
summarization_retry_attempt_start
summarization_retry_finished
```

Attempt-start identifies `source: "compaction"` plus `reason: manual|threshold|overflow`, or `source: "branchSummary"` for summarized tree navigation.

### Transactional model-assisted compaction

When a model client is requested, a model error, dropped stream, cancellation, or empty response no longer silently degrades into a heuristic summary. A terminal summarization failure leaves the session tree and active tip unchanged.

Heuristic compaction remains available only when no model client was requested.

### Upstream-style append-only compaction

The former rewrite-and-delete compactor has been replaced with a durable compaction boundary. Older entries remain in JSONL and retain their original identifiers, parent links, timestamps, tools, images, usage, costs, diagnostics, and auxiliary fields.

Each native compaction entry now persists:

```text
summary
firstKeptEntryId
tokensBefore
details
fromHook
provider/API/model/response metadata
usage and cost
```

`Session.contextEntries()` reconstructs the provider-facing context as:

```text
latest compaction summary
retained pre-boundary tail beginning at firstKeptEntryId
entries appended after the compaction boundary
```

This projection is used by normal provider requests, automatic-compaction size estimation, RPC context-token estimation, and RPC `get_messages`. A malformed hand-edited boundary falls back to the complete active path rather than silently dropping history.

Repeated compactions remain append-only. An unchanged compaction at the active tip is a no-op, while later conversation can append a new boundary without deleting the earlier boundary or any original messages.

### Canonical summary projection

Raw compaction and branch summaries are stored without display wrappers. Provider context synthesizes the original user-message wrappers around the raw summary while retaining timestamp and ownership safety. This keeps JSONL canonical and avoids contaminating persisted summaries with presentation text.

### Durable failed assistant attempts

Transient assistant failures now remain in append-only session history before retry begins. Retry request construction excludes those failed attempts only from the live provider-facing context and retains the original user and tool context.

A successful retry is appended as a distinct assistant entry. The exclusion set is intentionally process-local: saving and reopening a session preserves the failed attempt for forensics without permanently rewriting historical context policy.

### Persistent RPC retry configuration

RPC `set_auto_retry` now updates global `settings.json` instead of changing only the current process:

- the read/modify/write transaction uses the package/resource advisory lock;
- unrelated settings and nested `retry.provider` fields survive;
- conflicting legacy top-level retry aliases are removed;
- the file is written atomically and synchronized;
- the persisted result is reloaded and verified;
- malformed scalar retry configuration is rejected without replacing the original file.

### Native summarized tree navigation

The native session tree now supports model-backed branch summaries through:

```text
/tree <entryId> --summary [additional focus]
/tree --summary <entryId> [additional focus]
```

The implementation:

- finds the deepest common ancestor of active and selected branches;
- collects only the abandoned side of the current path;
- applies a bounded, UTF-8-safe newest-first summary budget;
- retains nested compaction and branch summaries as source context;
- uses the shared summarization retry boundary;
- selects the correct target position for assistant/tool versus user/custom entries;
- returns selected user/custom text for editor prefill;
- persists a canonical `branch_summary` entry with details, model metadata, usage, and cost;
- survives JSONL serialization, reload, and active-tip reconstruction.

### Compaction-aware RPC projection

RPC now distinguishes durable history from live agent context:

- `get_entries` retains the complete append-only session tree, including pre-compaction entries;
- `get_messages` returns the compaction-aware AgentMessage projection;
- compaction and branch summaries are represented explicitly;
- custom messages remain available with display metadata;
- live-only retry exclusions are omitted from the active projection;
- RPC `compact` reports the persisted boundary’s `summary`, `firstKeptEntryId`, `tokensBefore`, `details`, and estimated post-compaction context.

## Validation completed in the development tree

```text
Supplied Zig compiler:                     0.16.0
Direct complete root graph:                877/877 passed
Direct root skips/failures:                0 / 0

Normal module process:                     871 passed
Intentional SQLite isolates:               6
Module-process failures:                   0
Dedicated SQLite repository process:       11/11 passed
SQLite CLI/schema process:                 8 passed, 6 isolated, 0 failed
Ordinary executable process:               7/7 passed
SQLite live-persistence process:           5/5 passed
SQLite-enabled executable process:         7/7 passed

Whole-tree Zig formatting:                 passed
Node bridge syntax validation:             passed
Git diff validation:                       passed
Real-source audit:                         passed
Synthetic source files:                    0
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug build:                passed
```

The six normal-module isolates are not omitted behavior. Their C-linked SQLite paths execute successfully in the separately linked repository and SQLite CLI processes.

Changed-area coverage includes summarization retry, quota fail-fast classification, cancellation, branch summaries, terminal compaction rollback, append-only compaction, repeated compaction, malformed-boundary fallback, canonical summary wrappers, rich entry preservation, live-only retry exclusions, atomic retry-setting persistence, and compaction-aware RPC messages.

## Real executable gates

Persistent JSONL RPC processes validate:

- `set_auto_retry` persistence and immediate `get_state` synchronization;
- failed and successful assistant attempts as separate durable JSONL entries;
- omission of the failed attempt from the immediate retry request;
- one scheduled, one attempt-start, and one finished summarization retry event;
- `source: "compaction"` and `reason: "manual"` on attempt start;
- successful second-attempt model summary;
- nine durable session entries after compacting an eight-message conversation;
- a compaction boundary parented to the original tip;
- retained `firstKeptEntryId` and nonzero `tokensBefore`;
- `get_messages` returning the summary plus retained tail while `get_entries` retains the older messages;
- process exit 0 and zero stderr.

See [`RETRY-SUMMARY-E2E-162.txt`](./RETRY-SUMMARY-E2E-162.txt).

## Remaining parity boundary

Checkpoint 162 materially closes summarization retry, durable retry history, retry-setting persistence, append-only compaction, compaction-aware context reconstruction, and basic model-backed tree-summary navigation. Complete Pi 0.84.1 monorepo equivalence is not claimed.

The largest remaining areas are:

1. `retry.provider.timeoutMs`, `maxRetries`, and `maxRetryDelayMs` across every provider transport, including bounded server-directed retry delays.
2. Token-budget cut points, turn-prefix summaries, file-operation extraction, complete compaction prompt policy, and extension `session_before_compact` overrides.
3. Full branch-summary configuration, extension `session_before_tree`/`session_tree` hooks, labels, file-change extraction, and the original fullscreen tree workflow.
4. The complete package install/update/remove, model, login, settings, and session fullscreen screens.
5. Complete npm, pnpm, and Bun workspace, lockfile, lifecycle-script, and platform behavior.
6. Arbitrary extension-owned retained component trees with asynchronous invalidation.
7. Function-valued provider transports and extension-owned OAuth/login callbacks.
8. Native server TLS and mutual TLS.
9. Automatic image resizing, EXIF-orientation normalization, and transcoding.
10. Remaining enterprise credential, telemetry, retry, and cross-language interoperability coverage.
