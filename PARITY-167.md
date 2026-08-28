# Pi 0.84.1 → native Zig parity audit — checkpoint 167

Checkpoint 167 was compared directly with the uploaded Pi 0.84.1 source, especially:

- `packages/coding-agent/src/core/compaction/branch-summarization.ts`;
- `packages/coding-agent/src/core/compaction/compaction.ts`;
- `packages/coding-agent/src/modes/interactive/components/tree-selector.ts`;
- `packages/coding-agent/src/modes/interactive/interactive-mode.ts`;
- provider request implementations under `packages/ai/src/api`.

## Closed in checkpoint 167

### Branch-summary output ceiling

The native branch-summary request now has the original independent 2,048-token output limit. The cap is request-local and remains bounded by a lower model-level maximum.

### Compaction output budgets

Ordinary compaction summaries use 80% of `reserveTokens`; split-turn prefix summaries use 50%. These values are carried through the same request-local model-client boundary.

### Non-reusable summary requests

Standalone summaries no longer inherit live conversation prompt-cache retention or session-affinity identifiers. This matches the original no-cache summary policy and avoids polluting or reusing the primary conversation cache lineage.

### Cross-provider option propagation

The implemented OpenAI, Responses/Codex, Anthropic, Google, Mistral, Bedrock, and Pi Messages transports all consume request-local output/isolation options.

### Fullscreen tree target selection

Bare interactive `/tree` now opens a retained searchable, filterable, foldable tree selector with labels, active-branch/tip state, Unicode-cell-safe rendering, and terminal lifecycle restoration. Explicit entry-ID navigation remains supported.

### Real request evidence

A loopback provider observed `max_tokens=2048` on the branch-summary request, no summary affinity headers, and no prompt-cache fields. A real PTY selected a historical entry through incremental search and persisted the resulting branch summary.

## Retained parity from earlier checkpoints

Checkpoint 167 preserves:

- append-only JSONL sessions, branches, compaction boundaries, branch summaries, labels, usage, and costs;
- token-budget branch preparation and `branchSummary.reserveTokens`/`skipPrompt`;
- `session_before_tree` and `session_tree` extension interception;
- `session_before_compact` and `session_compact` interception;
- native assistant/provider/summarization retry layers;
- original JavaScript/TypeScript extension compatibility and ordered actions;
- package and top-level resource management;
- native remote protocol, SQLite companions, rich TUI primitives, images, Markdown, terminal input, and provider transports.

## Remaining highest-value gaps

1. Exact original token estimator and every prompt-clamping corner case.
2. The complete original tree selector's visual grammar, mouse behavior, action set, summary progress, and cancellation UX.
3. Function-valued extension providers and extension-owned OAuth/login implementations.
4. Complete package, model, login, settings, and session fullscreen managers.
5. Full npm/pnpm/Bun workspace, lifecycle, lockfile, and platform behavior.
6. Arbitrary asynchronously invalidated extension-owned component trees.
7. Server-side TLS and mutual TLS.
8. Automatic image resizing, EXIF orientation normalization, and transcoding.
9. Retry propagation through every OAuth/cloud/catalog/bootstrap request.
10. Remaining enterprise credential, telemetry, and cross-language interoperability fixtures.

## Validation summary

```text
Direct exact-source root:                  904/904 passed
Normal module process:                     897 pass / 7 isolated / 0 fail
Build graph:                               13/13 succeeded
SQLite repository:                        11/11 passed
SQLite CLI/schema:                         8 pass / 6 isolated / 0 fail
Ordinary executable:                       9/9 passed
SQLite persistence:                        5/5 passed
SQLite-enabled executable:                 9/9 passed
Real summary-request/PTY E2E:              passed
Synthetic source files:                    0
```
