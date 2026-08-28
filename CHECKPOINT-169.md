# Pi Zig checkpoint 169

Checkpoint 169 continues the native Zig 0.16.0 rewrite against the uploaded Pi 0.84.1 source. This pass closes the interactive model-selection boundary, ports the original release/changelog lifecycle, and replaces hard-coded external search-tool assumptions with managed native acquisition plus safe fallbacks.

## Fullscreen native model selector

Interactive `/model` now opens a retained alternate-screen selector backed by the live model catalog.

Implemented behavior includes:

- defaulting to the configured `--models` scope when one exists;
- switching between scoped and all-model views;
- filtering the all-model view to providers with usable runtime configuration while retaining the current model;
- current-model-first sorting followed by stable provider/model ordering;
- fuzzy matching across canonical `provider/model`, provider, model ID, and display name;
- an optional `/model <query>` initial filter;
- context-window, output-limit, reasoning, image-input, and API metadata;
- Up/Down wrapping, Home/End, Page Up/Page Down, Tab scope changes, Enter selection, and search-first Escape behavior;
- mouse-wheel navigation, row selection, and bounded double-click confirmation;
- Unicode-cell-safe clipping and deterministic raw-mode, mouse, bracketed-paste, cursor, and alternate-screen restoration;
- buffered-input handoff from the parent interactive editor.

Selection returns a canonical provider/model identity to the existing live-state layer. A successful switch now:

- rebuilds the live client when a client pool exists;
- updates provider and model identity even in deterministic mock/embedder runs without a client pool;
- appends a durable `model_change` entry;
- applies scoped or model-capability-clamped thinking;
- appends `thinking_level_change` when the effective level changes;
- updates the active context-window threshold used by compaction.

A new regression test covers the formerly broken no-client-pool `openai/gpt-4.1-mini` path.

## Original release and changelog lifecycle

The native interactive startup now ports the relevant upstream lifecycle rather than displaying a Pi-Zig-only summary.

Implemented behavior includes:

- bundling the exact uploaded Pi 0.84.1 `CHANGELOG.md` bytes;
- parsing semantic versions, including prerelease precedence;
- selecting only released changelog sections newer than the acknowledged version and no newer than the targeted upstream version;
- first-start and upgrade lifecycle decisions;
- skipping lifecycle notices when resuming an existing session;
- atomic, advisory-lock-protected persistence of `lastChangelogVersion` without replacing unrelated settings;
- `collapseChangelog` condensed startup notices;
- `/changelog` rendering the bundled upstream changelog;
- a bounded 1.5-second latest-version request through the shared bootstrap HTTP client;
- proxy, `NO_PROXY`, timeout, response-bound, and offline behavior inherited from the shared management transport;
- `PI_SKIP_VERSION_CHECK` and `PI_OFFLINE` gates;
- the original anonymous install report when enabled;
- `enableInstallTelemetry` and authoritative `PI_TELEMETRY` control;
- owned detached report state, avoiding dependence on temporary command buffers.

The user-facing update notice deliberately reports that this Zig port targets Pi 0.84.1; it does not pretend that an upstream JavaScript package can replace the native executable automatically.

## Managed `fd` and `ripgrep`

The native `find` and `grep` tools now use a shared managed-tool implementation derived from the original `tools-manager.ts` behavior.

Resolution order is:

1. the agent-private `bin` directory;
2. matching commands on `PATH` (`fd`/`fdfind` or `rg`);
3. on-demand managed acquisition;
4. the existing native Zig filesystem/search fallback.

Managed acquisition includes:

- GitHub latest-release discovery;
- original platform asset naming for Linux, macOS, and Windows x86-64/aarch64 targets represented by the Zig build;
- environment/private-mirror endpoint overrides;
- the shared bounded management HTTP retry, timeout, proxy, and `NO_PROXY` policy;
- `PI_OFFLINE` and `PI_SKIP_TOOL_DOWNLOADS` gates;
- nonfatal Termux behavior so package-manager-provided tools or native Zig fallbacks remain authoritative;
- bounded release metadata and 128 MiB archive responses;
- unique temporary archive/extraction paths;
- `.tar.gz` and `.zip` extraction;
- recursive binary discovery inside release archives;
- executable permission installation;
- atomic replacement into the agent-private `bin` directory;
- no implicit network operation in unit-test/embedding contexts that provide no environment.

`grep` now invokes the resolved managed ripgrep path with the complete child environment. `find` prefers managed `fd` with hidden-file, exclusion, glob, full-path, and result-limit behavior, then retains the native walker if fd is unavailable or fails.

## Real executable validation

The final model/update/tool E2E uses one real pseudo-terminal and one loopback management server.

Observed model/update behavior:

```text
Latest-version requests:                   1
Anonymous install reports:                 1
Persisted lifecycle version:               0.84.1
Fullscreen model selector:                 passed
Selected model:                            openai/gpt-4.1-mini
Durable model-change entries:              1
Interactive stderr:                        0 bytes
```

The same gate serves a synthetic official-layout ripgrep tarball. A real one-shot agent turn causes the native `grep` tool to:

1. request release metadata once;
2. download the archive once;
3. extract and atomically install `agent/bin/rg`;
4. execute the installed binary;
5. complete the mock agent turn;
6. reuse the same binary in a second process without another release or download request.

```text
Managed ripgrep install:                   passed
Release metadata requests:                 1
Archive download requests:                 1
Second-process cache reuse:                passed
Tool-process stderr:                       0 bytes
```

## Validation closure

```text
Supplied Zig compiler:                     0.16.0
Native Zig source files:                   184
Native Zig logical lines:                  106,213
Named Zig test declarations:               924
Synthetic/generated feature shards:        0

Direct all-package root suite:             926/926 passed
Direct skipped/failed:                     0 / 0

Normal module process:                     919 passed
Intentional linked SQLite isolates:         7
Module-process failures:                    0
SQLite repository process:                11/11 passed
SQLite CLI/schema process:                 8 passed, 6 isolated, 0 failed
Ordinary executable process:               9/9 passed
SQLite live-persistence process:           5/5 passed
SQLite-enabled executable process:         9/9 passed
Build-test graph:                          13/13 steps succeeded

Whole-tree Zig formatting:                 passed
Embedded Node bridge syntax:               passed
Python E2E fixture compilation:            passed
Git diff validation:                       passed
Real-source audit:                         passed
Bundled changelog byte equivalence:        passed
Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug build:                passed
```

## Remaining parity boundary

Checkpoint 169 materially closes the original model selector and update/install-report/tool-acquisition boundaries, but complete Pi 0.84.1 monorepo equivalence is not claimed.

The largest remaining areas are:

1. The original model selector’s complete configurable keybinding/action vocabulary, model-management shortcuts, OAuth entry actions, and exact visual grammar.
2. The complete fullscreen package install/update/remove, login, settings, and session managers.
3. Native self-update/install commands and richer asynchronous update-notice UI for the Zig distribution.
4. Exact npm, pnpm, and Bun workspace, lockfile, lifecycle-script, and platform behavior.
5. Arbitrary extension-owned retained component trees with asynchronous invalidation.
6. Function-valued extension providers and extension-owned OAuth/login callbacks.
7. Native server TLS and mutual TLS.
8. Automatic image resizing, EXIF-orientation normalization, and transcoding.
9. Remaining enterprise credential, telemetry, update, retry, and cross-language interoperability breadth.
