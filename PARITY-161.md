# Pi Zig parity audit — checkpoint 161

Reference: supplied original Pi coding-agent 0.84.1 source tree. Baseline: uploaded native Zig checkpoint 160.

## Newly closed in checkpoint 161

| Area | Checkpoint 160 boundary | Checkpoint 161 behavior |
|---|---|---|
| Agent-level retry | Provider transports had isolated retry behavior, but the native agent loop did not implement original `settings.retry`. | The outer assistant-producing call has a bounded settings-driven retry policy. |
| Settings | Retry values were not retained as a nested, field-preserving policy. | `retry.enabled`, `retry.maxRetries`, and `retry.baseDelayMs` parse, merge, format, and live-reload independently. |
| Compaction toggle | The current compactor had a threshold but did not honor original `compaction.enabled`. | Initial startup and live reload enable or disable automatic compaction explicitly. |
| Classification | No reusable original-style agent retry classifier existed. | Transient provider/transport text, Zig transport error names, and quota/billing exclusions share one allocation-free classifier. |
| Backoff | No outer retry sleep or retry-only cancellation existed. | Saturating exponential backoff is interruptible by whole-run abort or RPC `abort_retry`. |
| Context overflow | Transient retry could have conflicted with context recovery if added naively. | Context overflow remains a distinct compact-once path and runs before transient classification. |
| Events | RPC documented retry events but the native run path did not emit them. | JSON/RPC output emits original `auto_retry_start` and `auto_retry_end` objects; print/TUI surfaces render the same state. |
| RPC control | `set_auto_retry` and `abort_retry` were effectively bookkeeping. | They now change live execution, including concurrent cancellation while an agent request is busy. |
| Reload | Changed retry settings were not applied to the running agent. | Transactional reload updates enabled state, attempt budget, delay, and the RPC state projection. |
| Transport failures | Thrown Zig I/O errors bypassed assistant-message retry logic. | Retryable thrown transport errors are normalized into a terminal-safe assistant error and enter the same policy. |
| Validation | No end-to-end retry wire test existed. | Real RPC processes cover success, cancellation, runtime enablement, settings reload disablement, state sync, and clean shutdown. |

## Retained native coverage

Checkpoint 161 retains the checkpoint-160 surface: native provider transports, strict JSONL RPC and framed remote protocol, append-only sessions and migrations, SQLite repository/live-server companions, Unicode retained TUI infrastructure, broad JavaScript/TypeScript extension compatibility, transactional extension/provider reload, live tool progress and cancellation, ordered multi-image propagation, package manifests and filters, managed local/npm/Git lifecycles, trust-scoped resources, durable package repair, package/resource configuration, and exact top-level runtime filtering.

## Validation

```text
Native Zig files:                          176
Native Zig lines:                          96,798
JavaScript bridge lines:                   984
Named source test declarations:            850
Synthetic/generated source shards:         0

Direct complete root closure:              855/855 passed
Build-test module graph:                   849 passed, 6 isolated, 0 failed
Build-test graph:                          13/13 steps succeeded
All three Debug builds:                    passed
Retry RPC success/abort/toggle/reload E2E: passed
RPC stderr bytes:                          0
```

## Remaining high-value gaps

1. Summarization retry scheduling/events for compaction and branch summaries.
2. Durable persistence of RPC retry toggles into global settings.
3. `retry.provider` timeout/retry/delay propagation through every transport.
4. Durable history of intermediate failed attempts while excluding them from active retry context.
5. Complete package and remaining model/login/settings/session fullscreen screens.
6. Complete npm/pnpm/Bun workspace, lockfile, lifecycle-script, and platform parity.
7. Arbitrary asynchronously invalidated extension component trees.
8. Function-valued providers and extension-owned OAuth/login flows.
9. Native server TLS and mutual TLS.
10. Automatic image resize, EXIF orientation normalization, and transcoding.
11. Remaining enterprise credential, telemetry, retry, and cross-language interoperability breadth.

## Qualification

Checkpoint 161 is a tested, reproducible continuation of the native rewrite. It is not labelled complete Pi monorepo equivalence. Claims are limited to implemented paths and observed validation gates.
