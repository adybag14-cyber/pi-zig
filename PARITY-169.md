# Pi 0.84.1 → native Zig parity audit — checkpoint 169

Checkpoint 169 was compared directly with the uploaded Pi 0.84.1 source, especially:

- `packages/coding-agent/src/modes/interactive/components/model-selector.ts`;
- `packages/coding-agent/src/modes/interactive/model-search.ts`;
- model-selection paths in `interactive-mode.ts`;
- `packages/coding-agent/src/utils/version-check.ts`;
- install reporting and changelog handling in `interactive-mode.ts`;
- lifecycle fields in `core/settings-manager.ts`;
- `packages/coding-agent/src/utils/tools-manager.ts`;
- `packages/coding-agent/src/core/tools/grep.ts` and the original find/tool startup paths.

## Closed in checkpoint 169

### Fullscreen model selection

Bare interactive `/model` now opens a native retained selector over the effective live catalog. It provides scoped/all views, configured-provider availability, current-model retention, provider/model fuzzy search, metadata, keyboard and mouse navigation, and deterministic terminal restoration.

The selected canonical identity is applied to the live runtime and append-only session tree. Model-specific thinking is clamped or taken from explicit scope metadata. The no-client/mock path now changes provider and model together instead of persisting a stale provider.

### Changelog and release lifecycle

The exact uploaded upstream changelog is bundled and projected by semantic version. Startup acknowledgement is persisted atomically through the existing settings-operation lock. Condensed notices, `/changelog`, bounded latest-version discovery, update notes, offline/version-check gates, and anonymous install reporting are native.

### Managed search binaries

The agent now resolves `fd` and `ripgrep` from its private bin directory, then the system path, then a bounded on-demand release download. Platform asset names, proxy/retry/timeout policy, offline and Termux behavior, archive extraction, atomic executable installation, and native Zig fallbacks are implemented.

### Canonical model switching without a client pool

Deterministic mock runs and embedders can omit the provider client pool. Canonical `provider/model` references are nevertheless resolved through the catalog, update the provider/model/context-window state, and produce the same durable model identity as network-backed runs.

## Real executable evidence

A real PTY run demonstrated:

- condensed upstream 0.84.1 changelog notice;
- one bounded latest-version request;
- one anonymous install report;
- an update note for a synthetic 0.85.0 release;
- the fullscreen `/model gpt-4.1-mini` selector;
- durable `openai/gpt-4.1-mini` persistence;
- process exit 0 and zero stderr.

A separate one-shot tool phase demonstrated:

- one synthetic ripgrep release metadata request;
- one archive download;
- official-layout tar extraction;
- atomic executable installation to `agent/bin/rg`;
- execution through the native `grep` tool;
- second-process reuse with no repeated network operation;
- process exit 0 and zero stderr.

## Retained parity from earlier checkpoints

Checkpoint 169 preserves:

- native model/provider transports, proxying, provider and summarization retry;
- append-only sessions, compaction, branch summaries, labels, usage, cost, and retry history;
- JavaScript/TypeScript extensions, ordered actions, live updates, UI requests, custom renderers, packages, dynamic providers, and transactional reload;
- top-level and package resource management with trusted project scopes;
- protocol-v1 server/client, remote sessions, SQLite administration and live persistence;
- retained TUI primitives, fullscreen tree/config selectors, rich Markdown/LaTeX, terminal images, Unicode cells, mouse, IME, and modern terminal input;
- ordered multimodal content across sessions, extensions, providers, JSON, RPC, and terminal rendering.

## Remaining highest-value gaps

1. Complete original model-selector keybinding/action/OAuth/model-management breadth and exact visual behavior.
2. Complete fullscreen package, login, settings, and session managers.
3. Native Zig self-update/install workflow and richer update-notice management.
4. Complete npm/pnpm/Bun workspace, lockfile, lifecycle-script, and platform behavior.
5. Arbitrary asynchronously invalidated extension component trees.
6. Function-valued extension providers and extension-owned OAuth/login callbacks.
7. Native server TLS and mutual TLS.
8. Automatic image normalization, resizing, orientation correction, and transcoding.
9. Remaining enterprise credential, telemetry, update, retry, and cross-language interoperability breadth.

## Validation summary

```text
Direct exact-source root:                  926/926 passed
Normal module process:                     919 pass / 7 isolated / 0 fail
Build graph:                               13/13 succeeded
SQLite repository:                         11/11 passed
SQLite CLI/schema:                         8 pass / 6 isolated / 0 fail
Ordinary executable:                       9/9 passed
SQLite persistence:                        5/5 passed
SQLite-enabled executable:                 9/9 passed
Model/update/tool executable E2E:          passed
Synthetic source files:                    0
```
