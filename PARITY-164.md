# Pi Zig parity audit — checkpoint 164

Evidence base: uploaded original Pi coding-agent **0.84.1**, uploaded Zig checkpoint 163, and supplied Zig **0.16.0** toolchain.

## Newly closed in checkpoint 164

| Area | Checkpoint 163 boundary | Checkpoint 164 behavior |
|---|---|---|
| Compaction extension interception | Compaction did not call original script lifecycle hooks | Native `session_before_compact` and `session_compact` across automatic, slash, and RPC paths |
| Compaction cancellation | No extension cancellation boundary | Cancellation leaves the tree unchanged, returns a typed RPC/slash result, and still applies queued hook actions |
| Compaction replacement | Only native/model/heuristic summary generation | Extensions can provide summary, retained entry, tokens, details, usage, and cost with validation |
| Durable hook identity | No compaction `fromHook` source | JSONL/RPC preserve `fromHook`, details, usage, and cost |
| Tree extension interception | Native branch summaries bypassed original hooks | Native `session_before_tree` and `session_tree` with cancellation and replacement |
| Tree labels and details | Native summary metadata was fixed and unlabeled by hooks | Extension label, details, usage/cost, and source survive persistence |
| User-message navigation | Selected messages behaved like direct leaf targets | User/custom targets branch from the parent and return text for editor prefill |
| Awaited hook actions | Hook-produced actions could remain queued until a later turn | Slash, RPC, and automatic paths drain ordered actions immediately after lifecycle completion |
| Persistent RPC failure handling | Hook cancellation/errors could escape command control | RPC compact reports failure without terminating the process and saves applied cancellation actions |
| Executable evidence | Unit-level compaction/tree behavior only | Persistent RPC plus real-PTY replacement/cancellation/tree gate with zero child stderr |

## Retained native surface

Checkpoint 164 retains checkpoint 163's provider-internal retry policy, outer assistant and summarization retry, append-only history, native model transports, JSONL RPC, framed remote protocol, SQLite repository/live server, retained Unicode TUI, JavaScript/TypeScript extension compatibility, transactional runtime reload, package/resource management, live tool updates/cancellation, rich renderer support, and ordered multi-image propagation.

## Validation evidence

```text
Direct complete root closure:              889/889 passed
Normal all-package module process:          882 passed, 7 isolated, 0 failed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                   8 passed, 6 isolated
Ordinary executable process:                 9/9 passed
SQLite live-persistence process:             5/5 passed
SQLite-enabled executable process:           9/9 passed
Build-test graph:                          13/13 steps succeeded
Session hook executable E2E:               passed
RPC prompt turns:                           4
Compaction replacement/cancellation:        passed
Immediate hook-action visibility:           passed
Tree replacement and label:                 passed
Child-process stderr:                       0 bytes
All three executable builds:               passed
Formatting/source audits:                  passed
Synthetic source files:                    0
```

The direct root process linked SQLite and libc and ran all 889 cases. The normal build graph separately validates its seven intentional SQLite isolates in linked repository and CLI processes; no declared behavior is omitted.

## Explicitly remaining

- Token-budget cut points, split-turn prefix handling, reserve-token settings, and exact compaction thresholds.
- Complete compaction/branch prompts, file-operation extraction, previous-summary integration, and branch-summary token budgeting.
- Full compaction/tree progress events and fullscreen navigation UI.
- OAuth/cloud/bootstrap retry propagation and provider-specific HTTP/2 behavior.
- Full package/model/login/settings/session fullscreen managers.
- Complete npm/pnpm/Bun platform behavior.
- Arbitrary asynchronously invalidated extension component trees.
- Function-valued provider transports and extension-owned OAuth.
- Server TLS/mTLS.
- Automatic image transformation pipeline.
- Remaining enterprise credential, telemetry, retry, and interoperability breadth.

Checkpoint 164 is a tested continuation of the native rewrite. It is not labelled complete monorepo equivalence; claims are limited to implemented code paths and observed gates.
