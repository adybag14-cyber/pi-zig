# Pi Zig parity audit — checkpoint 165

Evidence base: uploaded original Pi coding-agent **0.84.1**, uploaded Zig checkpoint 164, and supplied Zig **0.16.0** toolchain.

## Newly closed in checkpoint 165

| Area | Checkpoint 164 boundary | Checkpoint 165 behavior |
|---|---|---|
| Automatic compaction threshold | Fixed character approximation | Active-context token estimate compared with active model context window minus `reserveTokens` |
| Retained history policy | `keep N entries` | Backward token accumulation using `keepRecentTokens` |
| Cut-point safety | Entry-count cut could ignore turn shape | Valid boundaries never retain a tool result without its turn context |
| Oversized turns | No explicit split-turn preparation | User/tool prefix summarized separately while assistant/tool suffix is retained |
| Iterative compaction | Previous summary only partially represented | Latest active summary integrated into preparation and model prompt |
| File operation continuity | Read/write/edit paths not extracted for compaction | Deterministic file-operation sets carried through previous summaries, tool calls, prompts, and hooks |
| Extension preparation | Shallow branch projection | Real summarized messages, prefix messages, split flag, file operations, and token settings |
| Model context awareness | Compaction controls independent of selected model | Context window follows startup, switch, reload, project, server, slash, and RPC paths |
| Usage estimation after compact | Timestamp-only validity could retain stale usage | Durable sequence order rejects pre-boundary usage even with second-resolution timestamps |
| RPC auto-compaction toggle | Runtime-only mutation | Atomic verified persistence preserving budgets and unrelated settings |
| Durable history | Retained append-only boundary behavior | Preserved; six messages remain durable while active context begins at summary |
| Executable evidence | Hook lifecycle E2E | Persistent RPC token-policy and settings-persistence E2E with zero stderr |

## Retained native surface

Checkpoint 165 retains checkpoint 164's compaction/tree extension lifecycle, provider-internal and assistant retry policies, append-only session tree, native model transports, JSONL RPC, framed remote protocol, SQLite repository/live server, retained Unicode TUI, JavaScript/TypeScript extension compatibility, transactional runtime reload, package/resource management, live tool updates/cancellation, rich renderer support, and ordered multi-image propagation.

## Validation evidence

```text
Direct complete root closure:              894/894 passed
Normal module process:                     888 passed, 6 isolated, 0 failed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                   8 passed, 6 isolated
Ordinary executable process:                 9/9 passed
SQLite live-persistence process:             5/5 passed
SQLite-enabled executable process:           9/9 passed
Build-test graph:                          13/13 steps succeeded
Compaction-policy executable E2E:          passed
Settings persistence:                     passed
Split-turn assistant cut:                 passed
Append-only history:                      passed
Compaction-aware active projection:       passed
Child-process stderr:                     0 bytes
All three executable builds:              passed
Formatting/source audits:                 passed
Synthetic source files:                   0
```

The direct root process links SQLite and libc and executes all 894 cases. The normal module process intentionally isolates six SQLite repository cases, all of which pass in its separately linked 11-test process.

## Explicitly remaining

- Exact original prompt length clamping and every token-estimation nuance.
- Branch-summary reserve-token and skip-prompt settings.
- Complete compaction/tree progress, cancellation, selector, and fullscreen UI.
- OAuth/cloud/catalog/update retry propagation.
- Remaining package/model/login/settings/session/tree fullscreen managers.
- Complete npm/pnpm/Bun platform behavior.
- Arbitrary asynchronously invalidated extension component trees.
- Function-valued providers and extension-owned OAuth.
- Server TLS/mTLS.
- Automatic image transformation pipeline.
- Remaining enterprise credential, telemetry, retry, and interoperability breadth.

Checkpoint 165 is a tested continuation of the native rewrite. Claims are limited to implemented code paths and observed gates; complete monorepo equivalence is not asserted.
