# Pi Zig parity audit — checkpoint 166

Evidence base: uploaded original Pi coding-agent **0.84.1**, uploaded Zig checkpoint 165, and supplied Zig **0.16.0** toolchain.

## Newly closed in checkpoint 166

| Area | Checkpoint 165 boundary | Checkpoint 166 behavior |
|---|---|---|
| Branch-summary settings | Native path ignored `branchSummary` settings | Nested `reserveTokens` and `skipPrompt` parse, merge, display, project-load, and reload natively |
| Request budget | Fixed 96 KiB total and 8 KiB per-entry byte caps | Newest-first token budget from active model context window minus reserved tokens |
| Model awareness | Branch summary used a fixed approximation | Startup, model switch, project environment, reload, and `/tree` use the active model context window |
| Summary retention | No original 90% summary exception | Important compaction/branch summaries may cross the limit while under 90% usage |
| File continuity | Partial nested-summary/tool-call handling | All Pi-generated nested summary details and visited assistant read/write/edit calls are accumulated |
| Request shape | Ad-hoc XML-like role serialization | Original system prompt, structured prompt, chronological explicit role serialization, and custom focus handling |
| Durable metadata | Basic details support | Sorted read/modified lists persist and append to the generated summary for later branch continuity |
| Interactive navigation | Summary required explicit command syntax | Plain `/tree` offers no summary, summary, custom focus, or cancel in a real terminal |
| Prompt suppression | Not implemented | `branchSummary.skipPrompt=true` suppresses the dialog and defaults to no summary |
| Automation | Interactive and scripted behavior could conflict | Explicit `--summary` remains noninteractive and deterministic |
| Executable evidence | Unit and lifecycle coverage | Persistent RPC plus two real pseudo-terminal sessions, settings reload, durable hook metadata, and zero stderr |

## Retained native surface

Checkpoint 166 retains checkpoint 165's token-budget compaction, append-only session tree, compaction/tree extension lifecycle, assistant and provider retry policies, native model transports, JSONL RPC, framed remote protocol, SQLite repository/live server, retained Unicode TUI, JavaScript/TypeScript extension compatibility, transactional runtime reload, package/resource management, live tool updates/cancellation, rich renderer support, and ordered multi-image propagation.

## Validation evidence

```text
Direct complete root closure:              894/894 passed
Normal module process:                     887 passed, 7 isolated, 0 failed
SQLite repository process:                 11/11 passed
SQLite CLI/schema process:                   8 passed, 6 isolated
Ordinary executable process:                 9/9 passed
SQLite live-persistence process:             5/5 passed
SQLite-enabled executable process:           9/9 passed
Normal build-test graph:                   passed
Branch-summary RPC/PTY E2E:                passed
Interactive custom focus:                 passed
skipPrompt dialog suppression:            passed
Durable details/usage/label:              passed
Child-process stderr:                     0 bytes
All three executable builds:              passed
Formatting/source audits:                 passed
Synthetic source files:                   0
```

The direct root process links SQLite and libc and executes all 894 cases. The normal module process intentionally isolates seven linked SQLite cases, all validated in their dedicated processes.

## Explicitly remaining

- Exact original token estimator and prompt-length clamping details, including an independent 2,048-token branch-summary output cap.
- Complete tree progress, cancellation, searchable selector, visualization, and fullscreen workflow.
- OAuth/cloud/catalog/update bootstrap retry propagation.
- Remaining package/model/login/settings/session/tree fullscreen managers.
- Complete npm/pnpm/Bun platform behavior.
- Arbitrary asynchronously invalidated extension component trees.
- Function-valued providers and extension-owned OAuth.
- Server TLS/mTLS.
- Automatic image transformation pipeline.
- Remaining enterprise credential, telemetry, retry, and interoperability breadth.

Checkpoint 166 is a tested continuation of the native rewrite. Claims are limited to implemented code paths and observed gates; complete monorepo equivalence is not asserted.
