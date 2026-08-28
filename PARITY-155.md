# Pi Zig checkpoint 155 parity audit

Reference: supplied original Pi 0.84.1 source tree.

## Closed or materially advanced

| Area | Checkpoint 155 status | Evidence |
|---|---|---|
| Package scopes | User, trusted project, and nonpersistent temporary scopes are native | Unit tests plus real user/project/temporary executable gates |
| Project trust | Project package storage is inaccessible until trust is resolved | Trust tests and `--local --approve` lifecycle gate |
| Package precedence | Project records win identity collisions; project `autoload:false` records act as deltas | Package scope/delta/tombstone tests |
| Legacy settings packages | Original string/object package arrays load when native registry is absent | User/project legacy tests |
| Package mutation locking | Bounded advisory lock guards install/update/remove | Lock contention/recovery test |
| Package-manager command | Argv-style `npmCommand` with npm/pnpm/bun-specific arguments | Settings tests, manager detection tests, fake-pnpm E2E |
| Explicit extensions | Path, local package, npm, and Git inputs resolve through temporary scope | Local and npm temporary extension E2Es |
| Installed TypeScript | `.ts`/`.mts`/`.cts` below `node_modules` transform through an explicit load hook | Runtime regression test and npm TypeScript E2E |
| Registry pollution | Temporary sources never create user/project package records | E2E filesystem assertions |
| Startup/reload/RPC | Trusted merged package resources flow through all three paths | Compiled integration changes and executable build |

## Retained prior parity

Checkpoint 155 retains the prior native provider transports, session tree and JSONL persistence, RPC/client/server surfaces, SQLite repositories and live server, Markdown/LaTeX/TUI primitives, multi-image propagation, live tool updates, script-extension hooks/tools/commands/UI/renderers, package resource glob/filter behavior, and managed npm/Git lifecycle from checkpoints 138–154.

## Known incomplete areas

| Area | Remaining work |
|---|---|
| Package UI | Original interactive config selector, resource-origin display, scope switching, and enable/disable editing |
| Concurrent package repair | Cross-process progress, durable repair markers, interrupted Git dependency recovery, richer diagnostics |
| Legacy migration cleanup | Verified migration and removal of old settings package entries rather than precedence-only compatibility |
| Extension UI | Fully arbitrary retained component trees, async invalidation, overlays, editors, and custom screen ownership |
| Dynamic providers | Function-valued transports, extension streaming implementations, OAuth/login callbacks, complete reload semantics |
| Fullscreen application | Remaining original model/login/settings/session/package selectors wired into the native shell |
| Server security | Native server TLS and mTLS |
| Image preprocessing | Resize, EXIF orientation normalization, transcoding, and remaining provider-specific limits |
| Enterprise integrations | Complete credential chains, proxy propagation, retry policy, and cross-language byte fixtures |

## Validation qualification

The focused affected suites, all three Debug executable builds, and the package/extension E2Es pass. The monolithic root test artifact exceeded the command deadline while compiling and produced no failed test output. No aggregate root-pass claim is made for checkpoint 155.
