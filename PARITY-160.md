# Pi Zig parity audit — checkpoint 160

Reference: newly supplied original Pi 0.84.1 source tree. Baseline: uploaded native Zig checkpoint 159.

## Newly closed in checkpoint 160

| Area | Checkpoint 159 boundary | Checkpoint 160 behavior |
|---|---|---|
| Stale command context | Old script code could continue mutating state after `await ctx.reload()`. | The JavaScript bridge invalidates the old context and returns the already ordered reload plus a stale-context diagnostic. |
| Native action barrier | A nonconforming worker could place actions after reload in one batch. | Zig treats the first reload as terminal across preview, startup, commands, shortcuts, lifecycle queues, and compatibility replay. |
| External model changes | Reload rebuilt extension providers over the startup disk catalog. | `models.json`, Radius/Pi Messages state, and Copilot-filtered catalogs are reconstructed from disk before extension providers. |
| Removed providers | A removed `models.json` provider could remain in retained runtime state. | Disk-owned providers are replaced as a set; removed identities do not survive the new snapshot. |
| External credentials | Built-in and custom credentials generally remained startup-owned. | `auth.json`, environment-backed provider keys, legacy fallback, and matching explicit CLI keys are resolved again. |
| Borrowed reload values | Client keys/proxy could point into temporary reload storage. | Reload-installed built-in keys and proxy URLs are allocator-owned by `ClientPool`. |
| Network settings | Proxy, Codex transport, and request timeouts were startup values. | They are staged, installed, and rolled back with the active client transaction. |
| Agent settings | Tool allow-list, max turns, and compaction retention stayed stale. | Fresh merged trusted settings update the tool schema and live agent configuration. |
| Client rollback | Provider reconstruction rollback did not cover every mutable client scalar. | Runtime list, credentials, proxy, transport, timeouts, and active identity are restored together. |
| RPC teardown | Detached stdin context leaked and retained a potentially freed Inbox pointer. | Reader state is detached from DebugAllocator ownership through a guarded pointer and allocator-correct line lifecycle. |
| Validation | Existing reload E2Es focused on extension-owned providers. | A real disk-backed provider changes endpoint, Bearer token, model metadata, and tool schema in one persistent RPC process. |

## Retained native coverage

Checkpoint 160 retains the checkpoint-159 surface: native provider transports, strict JSONL RPC and framed remote protocol, append-only sessions and migrations, SQLite repository/live-server companions, Unicode retained TUI infrastructure, broad JavaScript/TypeScript extension compatibility, transactional extension/provider reload, live tool progress and cancellation, ordered multi-image propagation, package manifests and filters, managed local/npm/Git lifecycles, trust-scoped resources, durable package repair, package/resource configuration, and exact top-level runtime filtering.

## Validation

```text
Native Zig files:                          175
Native Zig lines:                          96,019
JavaScript bridge lines:                   984
Named source test declarations:            839
Synthetic/generated source shards:         0

Direct complete root closure:              844/844 passed
Build-test module graph:                   837 passed, 7 isolated, 0 failed
Build-test graph:                          13/13 steps succeeded
All three Debug builds:                    passed
Disk model/auth/settings reload E2E:        passed
RPC clean-shutdown allocator gate:          passed
```

## Remaining high-value gaps

1. Complete transactional reload for every remaining retry/compaction/UI scalar and externally refreshed OAuth/account source.
2. Complete package source install/update/remove fullscreen management.
3. Complete npm/pnpm/Bun workspace, lockfile, lifecycle-script, and platform parity.
4. Arbitrary asynchronously invalidated extension component trees.
5. Function-valued providers and extension-owned OAuth/login flows.
6. Remaining fullscreen model, login, settings, and session screens.
7. Native server TLS and mutual TLS.
8. Automatic image resize, EXIF orientation normalization, and transcoding.
9. Remaining enterprise credential, retry, telemetry, and cross-language interoperability breadth.

## Qualification

Checkpoint 160 is a tested, reproducible continuation of the native rewrite. It is not labelled complete Pi monorepo equivalence. Claims are limited to implemented paths and observed gates.
