# Pi 0.84.1 → native Zig parity audit — checkpoint 171

Checkpoint 171 was compared directly with the supplied original Pi 0.84.1 source, especially:

- `modes/interactive/components/settings-selector.ts`;
- the upstream `SettingsManager` mutation and deep-merge behavior;
- interactive `/settings` handling in `interactive-mode.ts`;
- steering and follow-up queue settings;
- quiet startup and tree-filter policy;
- startup changelog/install-report ownership.

## Closed in checkpoint 171

### Retained fullscreen settings selector

Interactive `/settings` now opens a native alternate-screen settings editor with fuzzy search, keyboard paging, value cycling, mouse wheel/click support, Unicode-safe clipping, nested fullscreen operation, buffered-input handoff, and deterministic terminal restoration.

The screen exposes 24 native settings across compaction, summaries, retries, networking, transport, reasoning, themes, delivery queues, startup policy, tree filtering, telemetry, and project trust.

### Atomic interoperable persistence

Each setting change is written under the shared configuration lock through an atomic synchronized replacement. Existing JSON and unrelated nested fields are preserved, malformed shapes are rejected without clobbering the file, legacy aliases are removed only when superseded, and the persisted result is reloaded and verified.

Canonical Pi field names are used, including nested `compaction`, `branchSummary`, and `retry.provider` objects.

### Transactional live application

Closing the selector after one or more edits performs one existing rollback-capable runtime reload. Retry, compaction, transport, timeout, theme, thinking, turn-limit, steering, follow-up, and tree-filter behavior therefore changes without restarting the process.

### Additional original settings

`steeringMode`, `followUpMode`, `quietStartup`, and `treeFilterMode` now parse, deep-merge, format, persist, apply at startup, and reload live. Bare `/tree` uses the mutable configured initial filter.

### Startup lifecycle safety

Explicit `--offline` now suppresses startup version and install-report network work. Anonymous install-report work is joinable rather than detached, preventing process teardown from racing a still-running helper.

### Real-process evidence

The final Debug binary completed the fullscreen settings PTY workflow, changed six settings, preserved unrelated and nested provider configuration, applied one live reload, proved the new tree filter through bare `/tree`, proved quiet startup after restart, restored the terminal, exited successfully, and emitted zero stderr bytes.

The same binary retained checkpoint 168 tree controls, checkpoint 169 model/update/managed-tool behavior, and checkpoint 170 startup/live session resume.

## Retained parity from earlier checkpoints

Checkpoint 171 preserves:

- native model-provider transports, request and bootstrap retry, proxying, credentials, OAuth, catalogs, and transactional reload;
- append-only sessions, compaction, branch summaries, tree navigation, labels, usage, cost, failed-attempt history, and remote projection;
- JavaScript/TypeScript extension execution, lifecycle events, ordered actions, live updates, rich tools/renderers, UI requests, packages, dynamic providers, and reload;
- package and top-level resource discovery, trust, filtering, installation, repair, and configuration;
- protocol-v1 server/client, remote sessions, SQLite administration, and live SQLite persistence;
- retained TUI, Markdown/LaTeX, terminal images, Unicode cells, mouse, IME, model/tree/config/session selectors, and modern terminal input;
- ordered multimodal content through sessions, extensions, providers, JSON, RPC, and terminal output;
- changelog/version lifecycle, native self-update planning, and managed `rg`/`fd` acquisition.

## Remaining highest-value gaps

1. Remaining original settings controls: image presentation and resizing, thinking visibility, Mermaid rendering, cache notices, editor/output layout, hardware cursor, warnings, fullscreen mode/output/scrollbar, terminal progress, and automatic light/dark theme selection.
2. Project-scope settings edits and explicit visualization of project overrides.
3. Fullscreen package source manager and login/account workflows.
4. Complete npm/pnpm/Yarn/Bun workspace, lockfile, lifecycle-script, store, and platform behavior.
5. Arbitrary asynchronously invalidated extension-owned retained component trees.
6. Function-valued extension providers and extension-owned OAuth/login callbacks.
7. Native server TLS/mTLS.
8. Automatic image normalization, resizing, orientation correction, and transcoding.
9. Remaining enterprise credential, telemetry, update, retry, and interoperability breadth.

## Validation summary

```text
Direct exact-source root:                  935/935 passed
Normal module process:                     928 pass / 7 isolated / 0 fail
SQLite repository:                         11/11 passed
SQLite CLI/schema:                         8 pass / 6 isolated / 0 fail
Ordinary executable:                       10/10 passed
SQLite persistence:                        5/5 passed
SQLite-enabled executable:                 10/10 passed
Build-test graph:                          13/13 passed
Settings PTY E2E:                          passed
Tree/model/session regression E2Es:        passed
Synthetic source files:                    0
```
