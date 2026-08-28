# Pi Zig checkpoint 165

Evidence base: the uploaded Pi coding-agent **0.84.1** source, uploaded checkpoint 164, and the supplied native Zig **0.16.0** toolchain.

Checkpoint 165 continues the native rewrite by replacing the remaining message-count/character compaction approximation with Pi's token-budget, valid-boundary policy. The implementation remains append-only: old entries stay durable while the active provider projection starts at the newest compaction summary and its retained tail.

## Native token-budget compaction

The native compactor now uses the original settings shape and defaults:

```json
{
  "compaction": {
    "enabled": true,
    "reserveTokens": 16384,
    "keepRecentTokens": 20000
  }
}
```

Automatic compaction compares estimated active-context tokens against:

```text
contextWindow - reserveTokens
```

The context window follows the active model through startup, model switching, project construction, framed server turns, and transactional live reload. Saturating arithmetic avoids underflow when the reserve exceeds a small model context window.

## Turn-aware cut selection

The old `keep N entries` control is removed from production paths. The retained tail is chosen by walking backward over estimated token costs until `keepRecentTokens` is reached, then selecting a valid cut point.

The native policy now:

- never begins retained context at a tool-result entry;
- prefers complete user turns when they fit the retained budget;
- recognizes a split turn when a single turn exceeds the retained budget;
- retains the assistant/tool suffix of a split turn;
- summarizes the preceding user/tool prefix separately;
- preserves the exact first retained entry ID in the durable compaction boundary;
- rejects a zero retained-token budget rather than silently producing invalid context.

## Previous summaries and file operations

Preparation starts after the latest active compaction boundary and carries its previous summary forward. It extracts deterministic read, write, and edit path sets from prior compaction details and assistant tool calls. Those paths are included in the model prompt and extension preparation instead of being discarded.

Model-assisted compaction now builds separate original-style inputs for:

- first compaction;
- iterative compaction with a previous summary;
- split-turn prefix summarization.

The summary remains transactional: cancellation, empty output, invalid hook replacement, or provider failure leaves the append-only tree and active tip unchanged.

## Higher-fidelity extension preparation

`session_before_compact` now receives the actual preparation rather than a shallow branch approximation:

```text
branchEntries
messagesToSummarize
turnPrefixMessages
isSplitTurn
firstKeptEntryId
tokensBefore
previousSummary
fileOps.read / written / edited
settings.enabled / reserveTokens / keepRecentTokens
customInstructions
reason
willRetry
```

The existing cancellation and replacement contract is retained. `session_compact` still receives the exact persisted boundary, including `fromHook`, details, usage, cost, reason, and retry state. Ordered actions from both lifecycle stages are applied at the awaited boundary.

## Active-context token estimation

The estimator uses durable assistant usage when it belongs to the current active context and falls back to native message estimation otherwise. A correctness fix prevents usage snapshots from the pre-compaction tail from being reused merely because JSONL timestamps have one-second resolution. Session sequence order identifies whether a usage snapshot predates the newest active compaction boundary.

Repeated compactions continue to ignore older pre-boundary history while retaining every old entry for audit and branching.

## Settings, persistence, and RPC

Global and project settings deep-merge the three compaction fields independently. Camel-case and snake-case compatibility aliases are accepted.

`set_auto_compaction` now atomically persists the global `settings.json` value before changing live state. The write path:

1. acquires the shared package/settings operation lock;
2. parses and validates the current settings object;
3. preserves token budgets and unrelated fields;
4. removes deprecated flat aliases;
5. atomically replaces and synchronizes the file;
6. reloads it to verify the result;
7. updates the current RPC state only after persistence succeeds.

Malformed compaction settings are rejected without replacing the existing file.

## Runtime wiring

The token-budget policy is used consistently by:

- initial CLI and interactive startup;
- project-environment construction;
- model switching;
- live settings/model reload;
- threshold-triggered automatic compaction;
- context-overflow recovery compaction;
- manual `/compact`;
- JSONL RPC `compact`;
- framed HTTP/server turns.

`/settings` reports the effective enabled state, reserve-token budget, and retained-token budget.

## Real executable E2E

A persistent JSONL RPC process loaded a trusted TypeScript extension and validated:

```text
set_auto_compaction persistence:             passed
reserveTokens retained:                     123
keepRecentTokens retained:                  20
unrelated theme retained:                   night
durable messages before compaction:         6
durable messages after compaction:          6
messagesToSummarize received by hook:        4
turnPrefixMessages received by hook:         1
split-turn selection:                       true
first retained role:                        assistant
before-hook action immediately visible:     true
after-hook action immediately visible:      true
active context begins with summary:         true
old summarized history absent from context: true
process exit:                               0
process stderr:                             0 bytes
```

## Validation summary

```text
Direct all-package root tests:              894/894 passed
Normal module process:                     888 passed, 6 isolated, 0 failed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                  8 passed, 6 isolated, 0 failed
Ordinary executable process:                9/9 passed
SQLite live-persistence process:            5/5 passed
SQLite-enabled executable process:          9/9 passed
Build-test graph:                          13/13 steps succeeded
Whole-tree formatting:                     passed
Embedded Node bridge syntax:               passed
Python fixture compilation:                passed
Real-source audit:                         passed
Synthetic source files:                    0
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug build:                passed
Compaction policy E2E:                     passed
E2E stderr:                                0 bytes
```

The six normal module-process isolates are the C-linked SQLite repository cases. Every one passes in the separately linked 11-test repository process. The direct root process links SQLite and libc and executes all 894 cases without skips.

## Explicit remaining parity boundary

Checkpoint 165 materially closes token-budget cut selection, split-turn handling, active-model thresholds, previous-summary/file-operation preparation, and compaction-setting persistence. It does not claim complete Pi 0.84.1 monorepo equivalence.

The largest remaining areas are:

- exact original prompt length clamping and every token-estimation nuance;
- branch-summary reserve-token and skip-prompt settings;
- complete compaction/tree progress, cancellation, selector, and fullscreen workflow;
- retry propagation through OAuth, cloud credentials, catalog refresh, and update checks;
- remaining package, model, login, settings, session, and tree fullscreen managers;
- complete npm, pnpm, and Bun workspace, lockfile, lifecycle-script, and platform behavior;
- arbitrary extension-owned retained component trees with asynchronous invalidation;
- function-valued provider transports and extension-owned OAuth/login callbacks;
- native server TLS and mutual TLS;
- automatic image resizing, EXIF-orientation normalization, and transcoding;
- remaining enterprise credential, telemetry, retry, and cross-language interoperability coverage.
