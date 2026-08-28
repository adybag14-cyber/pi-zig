# Pi Zig parity audit — checkpoint 156

Reference: supplied original Pi 0.84.1 source tree. Baseline: uploaded native Zig checkpoint 155.

## Newly closed in checkpoint 156

| Area | Checkpoint 155 boundary | Checkpoint 156 behavior |
|---|---|---|
| Interrupted Git update | Locking and atomic registry writes existed, but a process stop during checkout replacement had no durable transaction record. | A target-derived atomic journal records target/prepared/backup paths before the rename sequence and supports deterministic commit, restore, or cleanup. |
| Recovery confinement | Managed removal was root-confined, but no journal parser existed. | Journal names, normalized target identity, sibling directory, and target-derived `tmp`/`old` prefixes are all validated before filesystem mutation. |
| Subsequent package mutation | A later update could encounter unresolved swap artifacts. | Git install/update/remove first resolve a valid target-specific journal. |
| Administrative recovery | No native package-repair command. | `pi repair`, including trusted project-local and JSON modes, scans bounded managed roots and reports exact recovery counters. |
| Legacy package migration | Historical `settings.json.packages` remained loadable but was not automatically removed after native persistence. | Repair atomically writes and re-reads `packages.json`, validates it, then atomically removes only the legacy field while preserving unrelated settings. |
| Migration data safety | Cleanup sequencing was unspecified. | The old package array remains authoritative until the new registry has been persisted and verified. |
| Aggregate validation | Checkpoint 155's monolithic graph did not finish within its command deadline. | The checkpoint 156 complete graph finished: 815 passed, 7 deliberate isolates skipped, 0 failed; every skipped SQLite path executes in a dedicated linked process. |

## Retained native coverage

Checkpoint 156 retains the broad native implementation accumulated through checkpoint 155, including provider transports, append-only sessions and migrations, RPC and remote clients, SQLite storage/server companions, retained terminal UI primitives, original JavaScript/TypeScript extension compatibility, live tool progress and cancellation, multi-image propagation, package manifests/globs/filters, managed local/npm/Git lifecycles, trusted package scopes, and configurable npm/pnpm/Bun wrappers.

## Remaining high-value gaps

1. Complete package selector/configuration screens and resource-origin editing.
2. Richer cross-process owner metadata, stale-owner inspection, and user-facing startup repair diagnostics.
3. Full npm/pnpm/Bun lockfile, workspace, lifecycle-script, and platform-specific update parity.
4. Arbitrary extension-owned retained component trees with asynchronous invalidation.
5. Function-valued provider streaming transports, extension-owned OAuth/login, and complete reload semantics.
6. Full original fullscreen model/login/settings/session/package UI wiring.
7. Native server TLS/mTLS and remaining proxy/bootstrap coverage.
8. Automatic image resizing, EXIF-orientation normalization, and transcoding.
9. Remaining enterprise credential-chain, retry, telemetry, and cross-language fixture breadth.

## Claim boundary

Checkpoint 156 is a tested, reproducible continuation of the native rewrite. It is not labelled complete Pi monorepo equivalence. Claims in this audit are limited to implemented source paths and observed validation gates.
