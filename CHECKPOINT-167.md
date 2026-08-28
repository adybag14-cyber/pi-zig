# Pi Zig checkpoint 167

Evidence base: the uploaded Pi coding-agent **0.84.1** source, uploaded Zig checkpoint 166, and the supplied native Zig **0.16.0** toolchain.

Checkpoint 167 closes two concrete original-source parity gaps: request-local completion controls for model-assisted summaries, and a retained fullscreen searchable session-tree selector for bare interactive `/tree`.

## Request-local completion options

The native model-client ABI now supports allocator-free per-request options without mutating the configured provider object:

```zig
pub const CompletionOptions = struct {
    max_tokens: u64 = 0,
    isolate_cache: bool = false,
};
```

Ordinary agent calls remain unchanged. A summarization call can now request a lower output ceiling and an isolated cache/session-affinity policy for that one request.

The model-level configured maximum remains authoritative. The effective limit is:

```text
min(configured model maximum, request-local maximum)
```

where an unspecified side does not constrain the other.

## Exact summary output budgets

The native summarization paths now match the supplied original source:

- branch summaries request at most **2,048 output tokens**;
- ordinary compaction summaries request `floor(reserveTokens × 0.8)`;
- split-turn prefix summaries request `floor(reserveTokens × 0.5)`;
- each request is still clamped by the selected model's lower configured maximum and context budget.

The branch-summary cap is independent of the model's ordinary output allowance. A model configured for 4,096 or 8,192 output tokens therefore receives a 2,048-token branch-summary request, while a model configured below 2,048 keeps its lower limit.

## Isolated summary cache and affinity

Standalone compaction and branch-summary requests now use an isolated request mode equivalent to the original `cacheRetention: "none"` behavior.

For implemented transports this suppresses reusable conversation affinity and prompt-cache state, including where applicable:

- `session_id`;
- `x-client-request-id`;
- OpenRouter-style session affinity;
- `prompt_cache_key`;
- explicit prompt-cache retention;
- Anthropic-compatible cache-control markers;
- Bedrock prompt-cache blocks;
- Mistral and Pi Messages session affinity.

The live conversation's configured cache policy remains unchanged for normal assistant turns.

## Provider coverage

Request-local output and isolation options are wired through the native transports for:

- OpenAI-compatible Chat Completions;
- OpenAI Responses and Codex-compatible Responses;
- Anthropic Messages;
- Google Generative AI and Vertex-compatible requests;
- Mistral Conversations;
- Amazon Bedrock Converse;
- Pi Messages.

The mock client records the exact options for deterministic regression tests.

## Fullscreen searchable `/tree`

Bare interactive `/tree` now opens a retained alternate-screen selector rather than requiring an entry ID to be typed manually.

The selector includes:

- append-only parent/child topology;
- indentation by branch depth;
- active-branch and active-tip markers;
- labels and compact content previews;
- case-insensitive incremental search across IDs, roles, entry types, content, tools, custom types, and labels;
- filter modes for default entries, no-tools, user-only, labeled-only, and all entries;
- branch folding and unfolding;
- Up/Down, Home/End, Page Up/Page Down navigation;
- Enter selection and Escape/Ctrl-C/Ctrl-D cancellation;
- Unicode-cell-safe clipping;
- deterministic alternate-screen, cursor, bracketed-paste, and mouse restoration;
- buffered line-editor input handoff when the enclosing interactive shell already owns stdin;
- preservation of malformed or orphaned durable entries as selectable roots instead of silently dropping them.

Explicit `/tree <entryId>` remains available and bypasses the selector. After selection, the existing checkpoint-166 summary choice, `branchSummary.skipPrompt`, extension hooks, labels, and editor-prefill behavior remain authoritative.

## Real provider and pseudo-terminal validation

A local OpenAI-compatible server recorded three ordinary requests and one branch-summary request from the exact checkpoint executable.

The ordinary requests carried live session affinity. The summary request carried none and used the original independent output cap:

```text
Normal requests:                           3
Summary requests:                          1
Summary max_tokens:                        2048
Normal affinity headers:                   session_id, x-client-request-id
Summary affinity headers:                  none
Summary prompt_cache_key:                  absent
Summary prompt_cache_retention:            absent
```

The same persistent session was reopened through a real pseudo-terminal. Bare `/tree` opened the fullscreen selector, incremental search selected the historical `assistant-167-1` entry, and the resulting branch summary persisted successfully.

```text
Fullscreen selector:                       passed
Search-selected entry:                     assistant-167-1
Summary persisted:                         passed
RPC exit:                                  0
PTY exit:                                  0
Combined stderr:                           0 bytes
```

## Complete validation

```text
Direct exact-source root tests:            904/904 passed
Direct skips/failures:                     0 / 0
Normal module process:                     897 passed, 7 isolated, 0 failed
SQLite repository process:                11/11 passed
SQLite CLI/schema process:                 8 passed, 6 isolated, 0 failed
Ordinary executable process:               9/9 passed
SQLite live-persistence process:           5/5 passed
SQLite-enabled executable process:         9/9 passed
Normal build-test graph:                   13/13 steps succeeded

Whole-tree Zig formatting:                 passed
Embedded Node bridge syntax:               passed
Python E2E fixture compilation:            passed
Git diff validation:                       passed
Real-source audit:                         passed
Synthetic source files:                    0

Static pi Debug build:                     passed
pi-sqlite Debug build:                     passed
pi-sqlite-live Debug non-LLVM build:       passed
```

The seven normal module-process isolates are intentional C-linked SQLite cases. Six execute in the dedicated SQLite repository process, while the SQLite CLI integration case executes in its dedicated linked process. The direct root command explicitly links SQLite and libc and executes all 904 cases without skips.

## Archive and patch reproducibility

The frozen source tree contains **328 files**. The source ZIP has one `pi-zig-v8-checkpoint-167/` root and excludes `.git`, Zig caches, `zig-out`, `__pycache__`, and compiled Python bytecode.

The exact archive extraction independently passed:

```text
Frozen/extracted file equivalence:         328/328 byte-for-byte
Direct root tests:                         904/904 passed
Normal build-test graph:                   13/13 steps succeeded
Static pi Debug rebuild:                   passed
pi-sqlite Debug non-LLVM rebuild:          passed
pi-sqlite-live Debug non-LLVM rebuild:     passed
Summary-request/fullscreen-tree E2E:       passed
Child-process stderr:                      0 bytes
```

The binary-safe patch was applied to a pristine checkpoint-166 extraction:

```text
git apply --check:                         passed
Patch application:                        passed
Reconstructed/source equivalence:          328/328 byte-for-byte
Direct root tests:                         904/904 passed
Normal build-test graph:                   13/13 steps succeeded
```

## Remaining parity boundary

Checkpoint 167 closes the independent branch-summary response cap, request-local cache isolation, and the core fullscreen searchable session-tree selection workflow. Complete Pi 0.84.1 monorepo equivalence is still not asserted.

The highest-value remaining areas are:

1. Exact upstream token-estimation and prompt-length clamping nuances beyond the now-correct output budgets.
2. Full tree visualization details, progress indicators, model-summary cancellation controls, mouse interaction, and every original selector action.
3. Retry-policy propagation through OAuth, cloud-credential, catalog-refresh, and update-check bootstrap requests.
4. The complete package, model, login, settings, and session fullscreen managers.
5. Complete npm, pnpm, and Bun workspace, lockfile, lifecycle-script, and platform behavior.
6. Arbitrary extension-owned retained component trees with asynchronous invalidation.
7. Function-valued provider transports and extension-owned OAuth/login callbacks.
8. Native server TLS and mutual TLS.
9. Automatic image resizing, EXIF-orientation normalization, and transcoding.
10. Remaining enterprise credential, telemetry, retry, and cross-language interoperability coverage.
