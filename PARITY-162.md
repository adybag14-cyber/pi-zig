# Pi Zig parity audit — checkpoint 162

Evidence base: uploaded original Pi coding-agent **0.84.1**, uploaded Zig checkpoint 161, and supplied Zig **0.16.0** toolchain.

## Newly closed in checkpoint 162

| Area | Checkpoint 161 boundary | Checkpoint 162 behavior |
|---|---|---|
| Summarization retries | Assistant turns retried, but compaction and branch summaries did not share the original retry boundary | Shared classifier, exponential abortable backoff, quota fail-fast behavior, cancellation, and canonical retry events |
| Model compaction failure | A requested model summary could silently degrade into heuristic output | Model errors, cancellation, and empty output fail transactionally without mutating the session |
| Compaction history | Older session entries were rewritten/deleted and recent entries reparented | Append-only `compaction` entry with `firstKeptEntryId`, `tokensBefore`, details, usage, and unchanged durable ancestry |
| Compaction context | Provider requests walked the physical branch directly | Latest boundary projects summary plus retained tail and post-boundary entries |
| Repeated compaction | Earlier boundary/history fidelity was not preserved | New boundaries append without deleting prior summaries or original messages; unchanged tip is a no-op |
| Summary wire form | Summary text could mix persistence and presentation | Raw JSONL summary plus canonical user-message wrapper only in provider context |
| Failed retry attempts | Only the final assistant result remained in durable history | Failed attempts persist while immediate retry context excludes them through a live-only set |
| RPC retry toggle | `set_auto_retry` changed only live state | Global atomic `settings.json` persistence with lock, verification, alias cleanup, and no-clobber failure handling |
| RPC context projection | `get_messages` returned physical branch messages only | Compaction-aware AgentMessage projection while `get_entries` retains full durable history |
| Branch summaries | Session tree could switch tips but lacked native abandoned-branch summarization | Common-ancestor collection, structured model summary, retry events, target-aware branching, editor prefill, and durable `branch_summary` JSONL |

## Retained native surface

Checkpoint 162 retains checkpoint 161’s native provider transports, append-only session trees and migrations, strict JSONL RPC, framed remote protocol, SQLite repository/live-server companions, Unicode retained TUI infrastructure, broad JavaScript/TypeScript extension compatibility, transactional resource/provider reload, live extension tool progress and cancellation, ordered multi-image propagation, trust-scoped package/resource management, and deterministic package repair/configuration.

## Validation evidence

```text
Direct root closure:                       877/877 passed
Normal module process:                     871 passed
Intentional SQLite isolates:               6
Dedicated SQLite repository:               11/11 passed
Ordinary executable tests:                 7/7 passed
SQLite live persistence:                   5/5 passed
SQLite-enabled executable tests:           7/7 passed
All three Debug builds:                    passed
Whole-tree formatting/source audit:        passed
Synthetic source files:                    0
```

Real executable evidence:

```text
RPC_RETRY_PERSISTENCE=PASS
DURABLE_RETRY_HISTORY=PASS
RPC_COMPACTION_RETRY=PASS
CANONICAL_SUMMARY_RETRY_EVENTS=PASS
APPEND_ONLY_HISTORY=PASS
COMPACTION_AWARE_GET_MESSAGES=PASS
COMBINED_STDERR_BYTES=0
```

## Explicitly remaining

- Provider-internal timeout/retry configuration and bounded `Retry-After` policy across all transports.
- Token-budget cut points, split-turn prefix summaries, file-operation extraction, full compaction prompts, and compaction extension overrides.
- Full branch-summary settings, extension hooks, labels, file-change extraction, and retained fullscreen navigation UI.
- Full package/model/login/settings/session fullscreen managers.
- Complete npm/pnpm/Bun workspace and lifecycle parity.
- Arbitrary asynchronously invalidated extension component trees.
- Function-valued provider transports and extension-owned OAuth.
- Server TLS/mTLS.
- Automatic image transform pipeline.
- Remaining enterprise credential, telemetry, retry, and interoperability breadth.

Checkpoint 162 is a tested continuation of the native rewrite. It is not labelled complete monorepo equivalence; claims are limited to implemented code paths and observed gates.
