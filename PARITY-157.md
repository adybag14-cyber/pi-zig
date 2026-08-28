# Pi Zig parity audit — checkpoint 157

Reference: newly supplied original Pi 0.84.1 source tree. Baseline: uploaded native Zig checkpoint 156.

## Newly closed in checkpoint 157

| Area | Checkpoint 156 boundary | Checkpoint 157 behavior |
|---|---|---|
| Package configuration screen | No native equivalent of the original `pi config` selector. | Native fullscreen, plain and JSON package-resource inventories retain enabled and disabled candidates. |
| Global package-resource editing | Package filters were understood by the loader but had no editing surface. | Space/Enter or `--set` persists exact `+`/`-` selectors for extensions, skills, prompts and themes. |
| Project resource overrides | Trusted project package deltas loaded correctly but could not be interactively edited. | Project mode exposes inherited state and original-style inherit/load/unload cycling, pruning empty deltas. |
| Selector automation | No deterministic machine interface for resource decisions. | `pi config --json` and `--set PACKAGE TYPE PATH STATE` share the fullscreen model. |
| Concurrent configuration | Registry save was atomic, but a selector could read before acquiring the operation lock. | One lock now covers the complete registry read/modify/write/verify transaction; simultaneous selectors preserve both edits. |
| Operation ownership | Advisory locking existed without user-visible owner identity. | Lock payload records PID, operation, start time and registry root while the advisory lock is held. |
| Stale-owner diagnosis | A leftover lock payload could not be distinguished administratively. | Nonblocking inspection treats the advisory lock as authoritative and reports unlocked non-empty metadata as stale evidence. |
| Recovery inspection | `pi repair` was mutating only. | `pi repair --check` reports owner, marker, legacy-migration and registry state without mutation. |
| Startup presentation | Interrupted package state required manual discovery. | Interactive startup prints scoped, actionable warnings while JSON/RPC surfaces remain clean. |
| Executable validation | Recovery E2E only. | CLI, PTY, lock-owner and twelve-round concurrent configuration gates all pass. |

## Retained native coverage

Checkpoint 157 retains the broad native implementation accumulated through checkpoint 156, including provider transports, append-only sessions and migrations, RPC and remote clients, SQLite storage/server companions, retained terminal UI primitives, original JavaScript/TypeScript extension compatibility, live tool progress and cancellation, ordered multi-image propagation, package manifests/globs/filters, managed local/npm/Git lifecycles, trusted package scopes, configurable npm/pnpm/Bun wrappers, durable Git update journals and verified legacy package migration.

## Remaining high-value gaps

1. Top-level auto-discovered and explicit resource-origin editing alongside package resources.
2. The complete original package source manager screen and finer origin/group presentation.
3. Full npm/pnpm/Bun lockfile, workspace, lifecycle-script and platform-specific update parity.
4. Arbitrary extension-owned retained component trees with asynchronous invalidation.
5. Function-valued provider streaming transports, extension-owned OAuth/login and complete reload semantics.
6. Remaining original fullscreen model, login, settings and session screen wiring.
7. Native server TLS/mTLS and remaining proxy/bootstrap coverage.
8. Automatic image resizing, EXIF-orientation normalization and transcoding.
9. Remaining enterprise credential-chain, retry, telemetry and cross-language fixture breadth.

## Claim boundary

Checkpoint 157 is a tested, reproducible continuation of the native rewrite. It is not labelled complete Pi monorepo equivalence. Claims in this audit are limited to implemented source paths and observed validation gates.
