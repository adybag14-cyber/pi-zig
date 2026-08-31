# Checkpoint 188 — Pi 0.84.4 / upstream-main Zig parity release

Checkpoint 188 advances the independent Zig rewrite from the retired Pi 0.84.1
reference to authoritative upstream main commit
`853a80d26c90a14c1886f0ebb8ffaae133ca2185` (Pi AI and coding-agent release
0.84.4). The comparison source remains in an isolated checkout outside this
repository; no TypeScript/JavaScript reference tree was restored.

## Source authority and reproducibility

- Authoritative repository: `https://github.com/earendil-works/pi.git`.
- Baseline embedded reference was proven byte-identical (apart from executable
  mode bits) to upstream commit
  `2e4d23959485279aa2da1a45103de2ea22d46395`.
- Audited delta: 174 upstream commits, 291 changed files, 11,685 insertions and
  2,577 deletions through `853a80d…`.
- Verified v0.84.4 release archive SHA-256:
  `ca3958559b60f87ee44c84d94df8c3ee0b7eda575370402abb2d0ad9155cde4a`.
- Exact catalog: 1,290 models across 39 providers; retained source SHA-256
  `cbb8df101cdeb3751d3a094a64c9214a4a7a72175bf187a039a02ee9724cb6af`.
- Exact bundled coding-agent changelog SHA-256:
  `469ee5caa136ec101a560ea5b61e42195a1a7265e18b561cb1f03d20d9e6b418`.
- Both projections are reproducible through commit/archive-pinned import
  scripts and the catalog generator's `--check` mode.

## Native parity delta

The native provider layer now includes Pi user-agent headers, provider-neutral
tool choice, compaction routing identities, all three compatible thinking-token
budget fields, Google thinking maps and stop-reason handling, Mistral fragmented
tool calls/top-level cache accounting, ordered OpenAI reasoning details,
Anthropic refusal fallbacks with returned-model pricing, Bedrock redacted
reasoning and raw response-header callbacks, Codex `end_turn`, current xAI
Responses routing, and the complete generated 0.84.4 compatibility metadata.

The coding-agent/runtime delta includes:

- current Copilot account-catalog policy selection, bounded 429 discovery and
  policy retries, sequential known-model enablement, and no-retry refresh;
- configurable default built-ins without dropping extension tools, optional
  native PowerShell, and `PI_EXPERIMENTAL=1` strict default-tool schemas;
- session-scoped searchable model and thinking selectors with explicit Ctrl+S
  persistence and non-empty `enabledModels` scope retention;
- `/share` active-branch JSONL export with `pi.share` prompt/tool metadata,
  organization-visible Radius artifacts, and private-gist fallback;
- `expandPromptTemplates` extension-command dispatch plus skill/template
  expansion, transactional failed factories, and immediate flag-default type
  validation;
- `ui_prompt_start`/`ui_prompt_end`, `session_compact_failed`, RPC
  `clear_queue`, terminal capability overrides, and fullscreen copy policy;
- malformed-line-tolerant and unterminated-tail-safe JSONL loading, post-tool
  extension message ordering, pre-provider post-tool compaction, and suppression
  of prepare-next-turn after final turns;
- UTF-8 BOM support, exact settings diagnostics, nested skill discovery,
  recursive shallower-first `@file` completion, semantic-version downgrade
  prevention, file-magic image MIME detection, fullscreen path/kebab selection,
  generic SGR release handling, and VS Code right-click paste suppression;
- durable cache-miss and compaction/branch-summary billing notices when
  `showCacheMissNotices` is enabled.

Cloudflare Worker binding injection and V8 string-length chunking are
JavaScript-runtime-specific mechanisms. Their native equivalents are direct
configured HTTP transport and Zig byte-slice terminal output; there is no V8
string ceiling or Worker binding object in the Zig runtime.

## Validation

Using stable Zig 0.16.0 on Windows with the official SQLite 3.53.4 x64 DLL and
import library, the final graph passed:

- aggregate build: 13/13 steps;
- module process: 1,035 passed, 27 intentional platform/isolation skips, zero
  failures;
- SQLite repository: 11/11;
- SQLite CLI: 11 passed, six intentional repository isolates;
- SQLite live persistence: 5/5;
- ordinary and SQLite-enabled executable roots: 12/12 each.

An isolated WSL Ubuntu build using the verified Linux Zig 0.16.0 archive passed
the real PTY/loopback lifecycle, summary-request, session-update,
project-settings, and fullscreen-settings gates with zero stderr. These gates
cover canonical model selection in the expanded catalog, lifecycle reporting,
managed ripgrep acquisition/cache reuse, routing/cache isolation for summaries,
session resume/update safety, settings persistence, and terminal restoration.

Final Windows ReleaseSafe artifacts:

- `pi.exe` — 9,042,944 bytes — SHA-256
  `fc73f94c1555de4d70aa72ba1664a9f05ec99a8bdcfd613d9771933f06af4cb4`;
- `pi-sqlite.exe` — 809,472 bytes — SHA-256
  `3026d87872e4446c63e0fc1e30c84fab54370cba1f03c6e7d569225a5da8bb82`;
- `pi-sqlite-live.exe` — 9,168,384 bytes — SHA-256
  `4004867186e5fe575682800fa4249c4e3156b3abea718aad852258b1eba96caf`.

All three report version 1.1.0. The real-source audit reports 201 Zig files,
127,642 Zig lines, and zero synthetic files.

## OpenRouter free-model gate

The stored OpenRouter OAuth credential is ready, and both completion-only and
tool-enabled ReleaseSafe requests reached `openrouter/free`. The external
account had exhausted its 50-request daily free allowance: OpenRouter returned
the real `openrouter_free_tier_daily` 429 with zero remaining and reset time
2026-09-01 00:00 UTC. Pi-Zig emitted zero automatic retry-start/end events and
one terminal agent-end event; no paid model or credits were used. Therefore
reachability and fail-fast behavior are proven, while a successful live
completion/tool invocation is explicitly not claimed for this run.

## Reference retirement

The historical 1,366-file TypeScript/JavaScript reference and its archive stay
deleted. Git history and `INPUT-PROVENANCE.json` retain their forensic hashes;
the new comparison checkout is deliberately outside the repository and is not
part of the release artifact.
