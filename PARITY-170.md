# Pi 0.84.1 → native Zig parity audit — checkpoint 170

Checkpoint 170 was compared directly with the supplied original Pi 0.84.1 source, especially:

- startup resume handling in `packages/coding-agent/src/main.ts`;
- the shared session selector and search components;
- interactive `/resume` handling in `interactive-mode.ts`;
- the runtime-host session replacement boundary;
- `packages/coding-agent/src/package-manager-cli.ts`;
- update target parsing and default-self behavior;
- release/version and package-manager integration paths.

## Closed in checkpoint 170

### Shared startup and live session selection

Startup `--resume` and interactive `/resume` now use one retained native selector rather than separate ad-hoc listings. It provides project/all scopes, recursive discovery, threaded/recent/relevance sorting, fuzzy and quoted search, names/path controls, rename, guarded delete, keyboard and mouse interaction, and deterministic terminal restoration.

### Real live session replacement

`/resume` now loads and installs the selected append-only session, updates the live session path and identity, rebinds provider-client affinity and extension context, restores model/thinking state, and brackets the operation with extension shutdown/start lifecycle events. Old-runtime and resumed-runtime actions are persisted on the correct side of the transaction.

### Native self-update target semantics

Bare `pi update` now defaults to Pi itself. `--self`, `--extensions`, `--models`, `--all`, `--extension`, positional sources, `--check`, `--force`, `--offline`, and `--json` are parsed through one conflict-checked plan.

Self-update planning recognizes npm, pnpm, Yarn, and Bun package-owned layouts from the executable path, preserves configured wrappers for command construction, supports package-name migration, enforces safe path/writeability constraints, and reports unsupported standalone/platform cases. The bounded release lookup continues to use the shared bootstrap retry, timeout, proxy, and `NO_PROXY` policy.

### Real-process evidence

The executable E2E proves:

- startup selector selection of a real JSONL target;
- durable rename of that selected target;
- no mutation of the unselected source;
- live `/resume` replacement;
- post-resume prompt and assistant history isolated to the target;
- a non-mutating managed-install check and unsafe standalone-install check;
- three bounded latest-release requests across the exercised check/safety/execution phases;
- ordered uninstall/install package-name migration;
- successful process exits and zero stderr.

## Retained parity from earlier checkpoints

Checkpoint 170 preserves:

- native provider transports, request/bootstrap retry, proxying, credentials, and transactional reload;
- append-only sessions, compaction, branch summaries, tree selection, labels, usage, cost, and failed-attempt history;
- original JavaScript/TypeScript extension execution, ordered actions, live updates, rich tools/renderers, UI requests, packages, dynamic providers, and reload;
- package and top-level resource discovery, trust, filtering, installation, repair, and configuration;
- protocol-v1 server/client, remote sessions, SQLite administration, and live SQLite persistence;
- retained TUI, Markdown/LaTeX, terminal images, Unicode cell handling, mouse, IME, model/tree/config selectors, and modern terminal input;
- ordered multimodal content through sessions, extensions, providers, JSON, RPC, and terminal output;
- changelog/version lifecycle and managed `rg`/`fd` acquisition.

## Remaining highest-value gaps

1. Complete upstream session-selector visual, regex, threaded-tree, loading, and cross-project workflow details.
2. Complete Windows and unmanaged-binary Zig self-update replacement/rollback semantics.
3. Fullscreen package source manager and remaining login/settings/session administration screens.
4. Complete npm/pnpm/Yarn/Bun workspace, lockfile, lifecycle-script, global-store, and platform behavior.
5. Arbitrary asynchronously invalidated extension component trees.
6. Function-valued extension providers and extension-owned OAuth/login callbacks.
7. Native server TLS/mTLS.
8. Automatic image normalization, resizing, orientation correction, and transcoding.
9. Remaining enterprise credential, telemetry, update, retry, and cross-language interoperability breadth.

## Validation summary

```text
Direct exact-source root:                  932/932 passed
Normal module process:                     925 pass / 7 isolated / 0 fail
SQLite repository:                         11/11 passed
SQLite CLI/schema:                         8 pass / 6 isolated / 0 fail
Ordinary executable:                       9/9 passed
SQLite persistence:                        5/5 passed
SQLite-enabled executable:                 9/9 passed
Focused session-related filter:            97/97 passed
Focused update-related filter:             35/35 passed
Session/resume/self-update E2E:             passed
Synthetic source files:                    0
```
