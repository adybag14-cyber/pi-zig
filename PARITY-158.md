# Pi Zig parity audit — checkpoint 158

Reference: newly supplied original Pi 0.84.1 source tree. Baseline: uploaded native Zig checkpoint 157.

## Newly closed in checkpoint 158

| Area | Checkpoint 157 boundary | Checkpoint 158 behavior |
|---|---|---|
| Top-level resource inventory | `pi config` exposed package resources only. | Package and top-level extension, skill, prompt, and theme origins share one deterministic inventory. |
| Auto-discovered resource editing | User/project `.pi` resources loaded implicitly and could not be disabled through the selector. | Disabled automatic candidates remain visible and persist exact `+`/`-` settings selectors. |
| Explicit settings resources | Explicit top-level paths/globs were runtime inputs without a native origin-editing model. | Files, directories and globs are resolved into configurable concrete resources while preserving source identity. |
| Project inheritance | Package deltas supported inherit/load/unload; inherited top-level resources did not. | Trusted project top-level resources and inherited user resources support the same tri-state and prune redundant overrides. |
| Runtime filtering | Configuration state could diverge from unconditional startup directory scans. | Extensions, skills, prompts and themes load from exact enabled paths resolved from settings and trust. |
| Project environment | Project-context skill discovery bypassed top-level filters. | Project-environment construction uses the exact merged top-level/package skill set. |
| Reloaded skills | `/reload` could rediscover a disabled skill through defaults. | Live and fallback reload paths re-resolve filtered top-level/package skills before rebuilding context. |
| Settings safety | Package registry changes were locked, but top-level settings had no shared transaction layer. | Top-level settings mutations share the package operation lock and atomically preserve unrelated fields. |
| Invalid configuration | A broad missing-file fallback risked treating unrelated settings read failures as empty. | Only `FileNotFound` means empty settings; malformed or inaccessible settings fail without replacement. |
| Concurrency validation | Package configuration had a two-process stress gate. | Twelve two-process top-level mutations preserve both settings decisions with zero lost updates. |

## Retained native coverage

Checkpoint 158 retains the broad native implementation accumulated through checkpoint 157: provider transports, append-only sessions and migrations, RPC and remote clients, SQLite storage/server companions, retained terminal UI primitives, JavaScript/TypeScript extension compatibility, live tool progress and cancellation, ordered multi-image propagation, package manifests/globs/filters, managed local/npm/Git lifecycles, trusted package scopes, durable update recovery, package health inspection, and the native package-resource fullscreen selector.

## Remaining high-value gaps

1. The complete package source install/update/remove fullscreen manager and richer source/resource grouping.
2. Full live `/reload` reconstruction of extension workers, prompt templates and active theme state; checkpoint 158 reapplies skill/context filters but does not rebuild every startup-owned subsystem.
3. Full npm/pnpm/Bun workspace, lockfile, lifecycle-script and platform-specific parity.
4. Arbitrary extension-owned retained component trees with asynchronous invalidation.
5. Function-valued provider streaming transports, extension-owned OAuth/login and complete provider reload semantics.
6. Remaining original fullscreen model, login, settings and session screen wiring.
7. Native server TLS/mTLS and remaining proxy/bootstrap coverage.
8. Automatic image resizing, EXIF-orientation normalization and transcoding.
9. Remaining enterprise credential-chain, retry, telemetry and cross-language fixture breadth.

## Claim boundary

Checkpoint 158 is a tested, reproducible continuation of the native rewrite. It is not labelled complete Pi monorepo equivalence. Claims in this audit are limited to implemented source paths and observed validation gates.
