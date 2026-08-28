# Pi Zig parity audit — checkpoint 159

Reference: newly supplied original Pi 0.84.1 source tree. Baseline: uploaded native Zig checkpoint 158.

## Newly closed in checkpoint 159

| Area | Checkpoint 158 boundary | Checkpoint 159 behavior |
|---|---|---|
| Extension reload | `/reload` retained startup extension workers. | A validated replacement host swaps native and JS/TS workers at a lifecycle boundary. |
| Extension `ctx.reload()` | Script commands and shortcuts could not request native reload. | Both expose asynchronous `ctx.reload()`, represented as an ordered native action applied after worker return. |
| Reload rollback | Startup-owned resources could not be replaced transactionally. | Invalid replacements leave the complete old runtime usable and return the concrete failure. |
| Re-entry safety | Recursive reload had no dedicated guard. | A concurrent or recursive attempt returns `ReloadAlreadyInProgress`. |
| Extension lifecycle | Reload did not recreate the extension session boundary. | Old workers receive `session_shutdown:reload`; replacements receive `session_start:reload`; provider-rebind rollback restarts the old runner. |
| Prompt templates | Completion and expansion retained startup slices. | Templates are rebuilt and current completion/expansion use the replacement inventory immediately. |
| Extension commands | Interactive and RPC metadata was startup-owned. | Command names and full RPC metadata are rebuilt and atomically exposed. |
| Themes | Theme files were startup-owned. | The registry is rebuilt and the freshly selected theme is reapplied. |
| Extension UI | Worker-owned surfaces could outlive their worker. | Reload clears extension UI state while preserving terminal/editor ownership. |
| Extension tools | Schemas and dispatch stayed bound to startup workers. | Replacement schemas, bridge, active-tool state, and dispatch pointers move together. |
| Declarative providers | Runtime provider registrations were not reconstructed. | Provider/catalog state is rebuilt, active-model availability is checked, and the live client pool is rebound before old memory is released. |
| Settings display | `/settings` text stayed startup-owned. | Fresh merged settings text is swapped with the runtime. |
| Keybindings | Native keybindings were not rebuilt. | Interactive reload installs a new manager transactionally and retains the old manager on load failure. |
| RPC reload | Strict JSONL RPC lacked reload. | `{"type":"reload"}` executes the same transaction and returns a structured summary. |
| Validation | No complete replacement gate existed. | Malformed rollback, command-requested reload, RPC reload, tool dispatch, prompt replacement, and live provider credential replacement are exercised end to end. |

## Retained native coverage

Checkpoint 159 retains the complete checkpoint-158 surface: native provider transports, append-only sessions and migrations, strict RPC and remote clients, SQLite repository and live-server companions, retained Unicode TUI primitives, broad JavaScript/TypeScript extension compatibility, live tool progress and cancellation, ordered multi-image propagation, package manifests and filters, managed local/npm/Git lifecycles, trust-scoped resources, durable package repair, package/resource configuration, and exact top-level resource filtering.

## Validation

```text
Native Zig files:                          175
Native Zig lines:                          95,532
JavaScript bridge lines:                   941
Source test declarations:                  835
Synthetic/generated source shards:         0

Direct complete root closure:              841/841 passed
Build-test module graph:                   834 passed, 7 isolated, 0 failed
Build-test graph:                          13/13 steps succeeded
All three Debug builds:                    passed
Replacement/rollback/RPC E2E:              passed
Active-provider credential reload E2E:     passed
```

## Remaining high-value gaps

1. Reject or quarantine stale old-worker actions ordered after `ctx.reload()` in the same invocation.
2. Reload every mutable scalar/network/retry setting and externally changed model/auth source.
3. Complete package install/update/remove fullscreen management and richer origin diagnostics.
4. Complete npm/pnpm/Bun workspace, lockfile, lifecycle-script, and platform parity.
5. Arbitrary extension-owned retained component trees with asynchronous invalidation.
6. Function-valued provider transports and extension-owned OAuth/login flows.
7. Remaining fullscreen model, login, settings, and session screens.
8. Native server TLS and mutual TLS.
9. Automatic image resize, EXIF orientation normalization, and transcoding.
10. Remaining enterprise credential, retry, telemetry, and cross-language interoperability breadth.

## Qualification

Checkpoint 159 is a tested, reproducible continuation of the native rewrite. It is not labelled complete Pi monorepo equivalence. Claims are limited to implemented paths and observed gates.
