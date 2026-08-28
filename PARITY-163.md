# Pi Zig parity audit — checkpoint 163

Evidence base: uploaded original Pi coding-agent **0.84.1**, uploaded Zig checkpoint 162, and supplied Zig **0.16.0** toolchain.

## Newly closed in checkpoint 163

| Area | Checkpoint 162 boundary | Checkpoint 163 behavior |
|---|---|---|
| Provider retry settings | Nested `retry.provider` data could survive unrelated persistence, but it did not drive native transports | Parsed, deep-merged, formatted, inherited, hot-reloaded, rollback-safe `timeoutMs`, `maxRetries`, and `maxRetryDelayMs` |
| Retry attempt counts | Several transports used fixed three-attempt loops | Shared configured retry budget across eight model/image transport modules |
| Provider header overrides | HTTP status/body heuristics only | `x-should-retry` true/false overrides captured before response header storage expires |
| Server-directed delay | Codex had a local partial implementation | Shared decimal-ms, decimal-seconds, and HTTP-date parsing with malformed fallback and overflow safety |
| Delay safety | No common cap across transports | Original-style 60-second default cap; zero disables; cap failure is explicit |
| Request timeout | Mostly Codex idle timeout only | Whole-request timeout and abort race for std.http transports; inherited general HTTP timeout when provider override is absent |
| Streaming replay safety | Fixed loops could retry transport errors without one common output-start rule | Integrated transports refuse to replay after partial model output/tool deltas |
| Live reload | Provider retry values were not part of client reload state | Policy captured, applied to live/future clients, and restored on reload rollback |
| Executable evidence | No cross-transport provider retry E2E | Loopback delay, force/deny, cap, timeout, inherited-timeout, and persistent reload gates |

## Retained native surface

Checkpoint 163 retains checkpoint 162's outer assistant and summarization retry policy, append-only compaction/session-tree behavior, native model transports, JSONL RPC, framed remote protocol, SQLite repository/live-server source, retained Unicode TUI infrastructure, JavaScript/TypeScript extension compatibility, transactional runtime reload, package/resource management, live tool updates/cancellation, and ordered multi-image propagation.

## Validation evidence

```text
Direct complete root closure:              884/884 passed
Normal all-package module process:          877 passed, 7 isolated, 0 failed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                   8 passed, 6 isolated
Ordinary executable process:                 9/9 passed
SQLite live-persistence process:             5/5 passed
SQLite-enabled executable process:           9/9 passed
AI provider import graph:                  189/189 passed
Settings/live client import graph:         524/524 passed
Shared retry focused suite:                  7/7 passed
Controlled HTTP focused suite:               7/7 passed
Provider retry executable scenarios:        7/7 passed
All three executable builds:               passed
Formatting/source audits:                  passed
Synthetic source files:                    0
```

The direct root process linked SQLite and libc and ran all 884 cases. The normal
build graph separately validates its seven intentional SQLite isolates in the
linked repository and CLI processes; no declared behavior is omitted.

## Explicitly remaining

- Provider policy propagation through OAuth, cloud metadata/credential, catalog refresh, and updater requests.
- Complete per-provider HTTP/2 dispatcher and idle-timeout equivalence.
- Complete compaction prompt/token/file-operation policy and compaction extension overrides.
- Tree-summary settings, hooks, labels, file-change extraction, and fullscreen tree workflow.
- Full package/model/login/settings/session fullscreen managers.
- Complete npm/pnpm/Bun platform behavior.
- Arbitrary asynchronously invalidated extension component trees.
- Function-valued provider transports and extension-owned OAuth.
- Server TLS/mTLS.
- Automatic image transformation pipeline.
- Remaining enterprise credential, telemetry, retry, and interoperability breadth.

Checkpoint 163 is a tested continuation of the native rewrite. It is not labelled complete monorepo equivalence; claims are limited to implemented code paths and observed gates.
