# Checkpoint 186 — provider lifecycle closure and 1.0.0 release

- Added explicit per-worker callback generations to every provider method
  descriptor and native callback owner.
- Added committed callback-set acknowledgement and retirement; unchanged
  callback sets avoid re-entrant worker exchanges.
- Added active stream generation/invocation tracking, unregister/reload/shutdown
  cancellation, bounded drain, stale-generation rejection, and hostile iterator
  worker isolation.
- Added object-form credential-aware `filterModels` and provider deferred
  fetch/cancel through the native `ModelClient`.
- Closed final Zig 0.16.0 Windows build/test gaps: portable permissions, short
  Node bridge launch, explicit SQLite library discovery, Windows-readable
  package operation metadata, native path assertions, and SQLite CLI version
  and help output.
- Promoted the rewrite to version 1.0.0 under the MIT License.
- The checkpoint-185 continuation slice is complete. Future parity work begins
  from a newer upstream source comparison rather than an inherited known gap.

# V8 checkpoint 176 — native clipboard output and bounded OSC 52 parity

- Added bounded native clipboard writes for Wayland, X11, Termux, macOS, Windows and WSL.
- Made `/copy` copy the newest assistant response instead of printing it into the transcript.
- Added the original 100,000-byte encoded OSC 52 ceiling and reused it for tree/application selection copying.
- Preserved remote native writes while also copying to the local SSH/Mosh terminal through OSC 52.
- Added timeout-safe writer subprocesses with forced termination of hung process groups.
- Routed fullscreen tree selection and JavaScript/TypeScript `copyToClipboard` through the same implementation.
- Added the Windows right-click, non-submitting paste event boundary.
- Corrected malformed duplicate extension-command RPC JSON serialization.
- Validation: 692/692 changed/imported tests; 964 pass, 7 intentional isolates, 0 fail in the all-package module process; 13/13 build steps; all three Debug binaries; zero synthetic files; real local/remote/extension clipboard E2E with zero stderr.
- Remaining clipboard work: live Windows desktop validation and additional native image formats. Broader priorities remain embedded image transformation, fullscreen package/account managers, package-manager platform breadth, async extension components, function-valued providers/OAuth, TLS/mTLS and enterprise interoperability.

## Checkpoint 166 — branch-summary settings and interactive policy parity

- Added native `branchSummary.reserveTokens` and `branchSummary.skipPrompt` parsing, independent global/project merge, settings display, startup propagation, project-environment propagation, and transactional live reload.
- Removed the fixed 96 KiB/8 KiB branch-summary truncation path in favor of newest-first token budgeting from the active model context window minus the configured reserve.
- Retained original summary prioritization: compaction and branch-summary context can cross the limit while less than 90% of the budget is used.
- Added cumulative read/write/edit tracking across all visited assistant tool calls and Pi-generated nested branch-summary details, including metadata outside the selected text budget.
- Added canonical branch-summary system/structured prompts, explicit role serialization, custom focus handling, sorted durable read/modified metadata, and original-style file-list sections.
- Plain interactive `/tree` now offers no summary, summary, custom prompt, or cancel; `branchSummary.skipPrompt=true` suppresses the dialog and defaults to no summary. Explicit `--summary` remains deterministic.
- Real executable validation combines a persistent RPC process with two pseudo-terminal sessions, custom focus `focus-166`, durable extension usage/label/details, live skip-prompt suppression, clean exits, and zero stderr.
- Complete validation: **894/894 direct root tests passed**; the normal module process passed 887 cases with seven linked SQLite isolates validated in dedicated processes; all three Debug binaries built.
- Remaining priorities: exact tokenizer/output-cap nuances; full tree progress/search/visualization UI; bootstrap retry propagation; remaining fullscreen managers; function-valued extension providers/OAuth; TLS/mTLS; image transforms; and enterprise breadth.

## Checkpoint 165 — token-budget compaction parity

- Automatic compaction now compares estimated active-context tokens with the active model context window minus `reserveTokens`, using the original defaults of 16,384 reserved and 20,000 retained tokens.
- Retained history is selected by backward token accumulation at valid turn boundaries rather than by an entry count; a tool result is never retained without its turn context.
- Oversized turns use explicit split-turn preparation: the user/tool prefix is summarized while the assistant/tool suffix remains in live context.
- Latest previous summaries and deterministic read/write/edit operation sets are carried into native model prompts and the `session_before_compact` payload.
- Startup, model switching, project loading, server turns, `/compact`, RPC compaction, and live reload all use the same token settings and current model context window.
- Stale assistant usage from before the newest compaction boundary is rejected by durable sequence order even when JSONL timestamps share the same second.
- RPC `set_auto_compaction` atomically persists the toggle while preserving token budgets and unrelated settings.
- Real executable coverage validates exact hook preparation, a split-turn assistant cut, immediate ordered actions, six-entry append-only history, compaction-aware active context, and zero stderr.
- Complete validation: **894/894 direct root tests passed**; the normal build graph completed **13/13 steps**, with 888 active module cases and all six SQLite repository isolates validated in the linked repository process.
- Remaining priorities: exact prompt clamping/token-estimation nuances; branch-summary token settings; compaction/tree fullscreen UI; bootstrap retry propagation; function-valued extension providers/OAuth; TLS/mTLS; image transforms; and enterprise breadth.

## Checkpoint 164 — compaction and session-tree extension lifecycle parity

- Native `session_before_compact`, `session_compact`, `session_before_tree`, and `session_tree` contracts now bridge original JavaScript/TypeScript extensions to live Zig sessions.
- Before-hooks receive branch/preparation projections and a live abort signal; they can cancel work, supply complete summaries, override tree instructions, and provide labels.
- Extension-provided compaction and branch-summary details, usage/cost data, labels, and `fromHook` markers persist through JSONL save/load and RPC projection.
- Hooks are wired into threshold/overflow compaction, manual `/compact`, `/tree`, and RPC `compact`, rather than existing as unused adapters.
- Actions emitted during before/after hooks are drained at the awaited lifecycle boundary. Session names, custom entries, model/tool changes, steering, follow-ups, aborts, and shutdown requests do not wait for a later agent turn.
- Selecting a user/custom entry through `/tree` now branches from its parent and returns its text for editor prefill, matching the original navigation contract.
- RPC compaction cancellation returns a typed failure without terminating the persistent process, while still applying and saving cancellation-hook actions.
- Real executable coverage validates replacement, cancellation, immediate action visibility, durable details/usage, labeled tree summaries, two clean process exits, and zero child-process stderr.
- Complete validation: **889/889 direct root tests passed**; the normal build graph completed **13/13 steps**, with 882 active module cases and all seven intentional SQLite isolates validated in their linked processes.
- Remaining priorities: original token-budget cut points and full file-operation extraction/prompt policy; branch-summary reserve-token settings; compaction/tree fullscreen UI; bootstrap retry propagation; function-valued extension providers/OAuth; TLS/mTLS; image transforms; and enterprise breadth.

## Checkpoint 163 — provider-internal request retry parity

- Native nested `retry.provider.timeoutMs`, `maxRetries`, and `maxRetryDelayMs` parsing, merge, display, runtime inheritance, transactional reload, and rollback.
- Shared response policy for `x-should-retry`, `retry-after-ms`, `retry-after` seconds/dates, bounded server delays, jittered backoff, cooperative cancellation, and whole-request timeouts.
- Fixed retry loops replaced across OpenAI Chat, Responses/Codex, Anthropic, Google, Mistral, Bedrock, Pi Messages, and OpenRouter image generation.
- Streaming transports refuse request replay after model output begins.
- Real loopback executable gates cover delay, forced/denied retry, cap failure, explicit/inherited timeout, and persistent RPC reload.
- Complete validation: **884/884 direct root tests passed**; the normal module process passed 877 cases and all seven intentional SQLite isolates passed in dedicated linked processes.
- Remaining priorities: bootstrap/OAuth/cloud retry propagation, compaction/tree hooks and policy, fullscreen managers, async extension components, TLS/mTLS, image transforms, and enterprise breadth.

## Checkpoint 159 — transactional live runtime reload

- `/reload` now stages and validates replacement extension workers, prompt templates, themes, declarative extension providers, commands, completion inventories, tool schemas, settings text, active-tool state, and keybindings before touching the active runtime.
- Invalid replacement resources retain the old workers and live client; successful swaps emit `session_shutdown:reload`, rebind the active provider/client snapshot, then emit `session_start:reload`.
- JavaScript and TypeScript extension commands and shortcuts expose asynchronous `ctx.reload()` through the ordered native action queue.
- Extension-owned UI surfaces are cleared without losing the terminal/editor binding; prompt/template and RPC command inventories switch immediately.
- Strict JSONL RPC accepts `reload`; a following `get_commands` sees only the replacement command and prompt inventories.
- Real persistent-process gates cover malformed-TypeScript rollback, old-worker retention, command-requested reload, direct RPC reload, replacement prompt/tool execution, and active-provider credential replacement across two local SSE requests.
- Complete direct closure: **841/841 tests passed**. The normal build-test graph also completed **13/13 steps**, with its seven C-linked SQLite isolates passing in dedicated processes. All three Debug executables build successfully.
- Remaining priorities: stale old-worker action rejection after `ctx.reload`, full mutable settings/model/auth-source reload, package source-manager UI, arbitrary async extension components, function-valued providers/OAuth, TLS/mTLS, image transforms, and enterprise parity breadth.

# V8 checkpoint 158 — top-level resource parity

- Package and top-level extension, skill, prompt and theme origins now share one deterministic config inventory.
- Automatic user/project resources and explicit settings files, directories and globs remain configurable even while disabled.
- Global exact load/unload and trusted project inherit/load/unload decisions persist atomically under the shared package-operation lock.
- Startup, RPC command discovery, project-environment construction and skill reload consume exact filtered resources instead of unconditional default scans.
- Malformed settings are rejected without replacement; only a missing file is treated as empty configuration.
- Complete root graph: 830 passed, 7 deliberate SQLite isolates, 0 failed.
- Real E2E: all four resource classes, extension enable/disable, prompt enable/disable, project tri-state, and 12/12 two-process rounds with zero lost updates.
- Remaining: full live reconstruction of extension/prompt/theme subsystems during `/reload`, package source manager UI, function-valued providers/OAuth, TLS/mTLS, image transformations, and enterprise parity breadth.

# Checkpoint 71 — Responses tool-result image replay

- Tool-result images are durable session metadata (`image` content blocks in v3 JSONL), survive load/fork, and replay into `ChatMessage`.
- OpenAI Responses emits tool-result text/images inside `function_call_output` / `custom_tool_call_output` as `input_text` / `input_image` content arrays for image-capable models.
- Text-only models preserve text; image-only results degrade to `(see attached image)` instead of being silently dropped.
- Runtime model `input_image` capability is threaded into Responses clients.
- Focused touched-module harness: 235/235 passing under Zig 0.16.0; no full project build was run.

## V8 checkpoint 70

- OpenAI Responses/Codex service-tier pricing now matches upstream flex/priority multipliers, including GPT-5.5 priority at 2.5x.
- Codex resolves a response tier of `default` back to requested flex/priority where appropriate.
- xAI Responses requests encrypted reasoning continuity even when reasoning is off.
- Focused Responses harness: 118/118 tests passing under Zig 0.16.0.

## V8 checkpoint 69

- OpenAI Responses/Codex now carry model reasoning capability and `thinkingLevelMap` into request construction.
- Standard Responses maps requested effort, emits model-specific `off` effort (default `none`), respects explicit unsupported holes, and skips the off control for GitHub Copilot.
- Codex Responses maps requested non-off effort but omits reasoning when off, matching upstream's distinct request contract.
- Focused Responses/runtime harness: 197/197 tests passing under Zig 0.16.0.

# pi-zig rewrite audit — checkpoint V7

## Integrity rule

The former repository contained a generated source surface designed to inflate the tree beyond 200k lines. That material remains deleted. V7 measures progress only through native behavior, observable upstream compatibility, tests, and real implementation code.

Still absent:

- `scripts/gen_surface.py`
- all `*_shard_*.zig` / `generated_root.zig` files
- synthetic model/tool/route/MCP/TUI/skill/eval/extension/local-model catalogs
- LOC-target generation machinery

V7 source audit before packaging:

```text
Zig files under src/: 77
Zig lines under src/: 25,089
Synthetic files: 0
Tests: 229/229 passing with Zig 0.16.0
```

## Implemented native areas

### Agent/core

- native multi-turn agent loop
- `read`, `write`, `edit`, `bash`, `grep`, `find`, `ls` tools
- tool filtering and schemas
- durable JSONL branch history and continuation/forking primitives
- compaction/truncation
- atomic cancellation
- POSIX process-group termination for aborted shell trees
- steering queue drained into model history between tool/model turns
- assistant thinking text/signature, tool opaque signatures, usage and cost retained in native history

### API protocol identity and transports

Provider identity, API protocol and native transport are independent. One custom provider can therefore contain models using different APIs without losing its public provider ID.

V7 has executable native paths for:

- `openai-completions`
- `openai-responses`
- `openai-codex-responses`
- `azure-openai-responses`
- `anthropic-messages`
- `google-generative-ai`
- `google-vertex`
- `mistral-conversations`
- `pi-messages`
- `bedrock-converse-stream`
- deterministic mock transport

#### Amazon Bedrock Converse Stream

V7 adds a native Bedrock transport with no AWS SDK dependency:

- Bedrock `ConverseStream` system/user/assistant/tool-result conversion
- text/image content, signed reasoning replay and tool-use/result conversion
- consecutive tool results combined into Bedrock-required user turns
- explicit cache points only for supported Claude families and long-retention TTL
- adaptive Claude thinking/effort where supported; fixed-budget fallback and GovCloud compatibility
- incremental binary AWS EventStream decoder with prelude/message CRC32 validation
- text/reasoning/signature/tool-input streaming deltas
- stop-reason and Bedrock exception mapping
- input/output/cache-read/cache-write token accounting and model-cost calculation
- `AWS_BEARER_TOKEN_BEDROCK` bearer authentication
- native SigV4 for ambient `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`, including `AWS_SESSION_TOKEN`
- inference-profile ARN / configured env / endpoint region precedence
- standard regional endpoint retargeting with custom endpoint preservation
- `AWS_BEDROCK_SKIP_AUTH=1` custom-proxy path
- upstream-compatible `amazon-bedrock` public provider identity
- `models.json` API inheritance and runtime hot switching

Not claimed yet: AWS profile/config-file loading, role assumption, ECS/IMDS, web identity, SSO/provider-owned login flows, HTTP proxy-agent parity, model-name hints for opaque application-profile ARNs, or complete AWS SDK request-id/diagnostic callback parity.

#### Pi Messages / Radius

The native gateway protocol used by Radius and custom `pi-messages` providers:

- Pi `{model, context, options}` request serialization
- bearer-authenticated `/messages` endpoint
- user text/image, assistant text/thinking/tool-call and tool-result history conversion
- historical assistant usage/cost and stop reason replay from native session metadata
- native tool-schema conversion into Pi `Context.tools`
- SSE text/thinking/tool-call event accumulation
- terminal done/error reasons and backend usage/cost
- thinking signatures and tool-result failure status
- stable session id and cache-retention forwarding
- missing-terminal, HTTP failure and cooperative abort behavior
- arbitrary `models.json` provider identities with `api: "pi-messages"`
- built-in Radius API inheritance and `radius/auto` runtime selection

Not claimed yet: Radius OAuth/login/refresh, dynamic `/v1/config` catalog discovery, gateway rewrite diagnostics, response-header callbacks, debug-query plumbing or durable `responseId` history.

#### OpenAI Chat Completions

- streaming/non-stream response parsing
- tool calls and replay
- cache/reasoning token accounting and model-cost calculation
- custom headers/base URL/provider identity
- developer-role, stream-usage and max-token compatibility
- OpenAI/OpenRouter/Together/DeepSeek/ZAI/Qwen/chat-template/string/Ant-Ling thinking forms implemented where represented by the native abstraction
- `requiresAssistantAfterToolResult`
- required `reasoning_content` replay
- ZAI `tool_stream`
- strict-tool stripping when unsupported
- explicit finish-reason enforcement
- encrypted `reasoning_details` retained against tool-call IDs and replayed durably
- cross-API tool-call ID normalization

#### OpenAI Responses

A distinct Responses transport, not a Chat-Completions alias:

- `/responses` request path
- Responses `input` history format
- `function_call` / `function_call_output` replay
- Responses tool schema conversion
- `store:false`
- 16-token minimum `max_output_tokens`
- reasoning effort/summary configuration
- output text/refusal/function-call SSE events
- completed/incomplete/failed status handling
- max-output incomplete mapped to length stop
- cached/reasoning usage and model pricing
- reasoning summary text retained as thinking

#### OpenAI Codex Responses

V5 added an explicit Codex request mode using the already-native Responses stream/event engine:

- `openai-codex-responses` API identity
- `/codex/responses` endpoint normalization
- JWT ChatGPT account-id extraction
- Codex bearer/account/originator/beta/session headers with mandatory-header precedence
- `instructions` separated from Responses `input`
- encrypted reasoning include, automatic tool choice and parallel tool calls
- Pi session id used for cache affinity

Not claimed yet: Codex WebSocket mode, zstd compression, automatic OAuth acquisition, previous-response chaining and the complete official retry/service-tier behavior.

#### Azure OpenAI Responses

- distinct API identity
- shared real Responses message/event engine
- Azure `api-key` authentication (no Bearer leakage)
- `api-version=v1`
- explicit configured Azure-compatible base endpoint
- custom headers/model/deployment identity

Current scope is explicit configured endpoints/keys. Automatic Azure resource/deployment discovery is not claimed.

#### Anthropic Messages

- streaming/non-stream messages
- tools/tool results
- configured headers/token limits/costs
- cache read/write and 1-hour cache-write accounting
- request-wide tier pricing with 1-hour writes priced at 2x base input
- thinking text and opaque `signature` / `signature_delta` durability
- same-model signed-thinking replay
- `allowEmptySignature` behavior; invalid unsigned thinking falls back to visible text

#### Google Generative AI

- native `streamGenerateContent?alt=sse`
- live text/thinking/tool deltas and cancellation
- `generationConfig` max output/thinking/sampling
- cached/thought token accounting and pricing
- opaque `thoughtSignature` retention for thinking and function calls
- signatures replay only to the same provider + exact model
- malformed/non-base64 signatures are not replayed
- Gemini 3+/Gemini Live 3+, Claude-on-Google and GPT-OSS-on-Google function-call ID requirements
- function-call IDs normalized consistently in requests/results

#### Google Vertex

- distinct API identity
- explicit Vertex-compatible base endpoint
- bearer access-token authentication
- Google streaming/request/signature engine reused natively
- custom headers and model request metadata

Current scope intentionally requires an explicit endpoint/access token. ADC, service-account loading and `gcloud` credential acquisition remain unimplemented and are not claimed.

#### Mistral Conversations

- distinct `mistral-conversations` API selection
- streaming HTTP/SSE path
- Mistral typed thinking/text replay
- deterministic collision-safe 9-character alphanumeric tool-call IDs
- consistent tool result ID replay
- Mistral reasoning `prompt_mode` / `reasoning_effort` behavior represented by current model rules
- cached prompt usage/cost
- custom endpoint/key/headers/provider identity

### Usage/cost fidelity

V4 carries these values through provider parsing → model response → native JSONL history → framed transcript:

- uncached input tokens
- output tokens
- cache-read tokens
- cache-write tokens
- Anthropic 1-hour cache writes
- reasoning/thinking tokens where reported
- total tokens
- input/output/cache-read/cache-write/total dollar cost

Pricing includes request-wide tier selection based on model cost metadata.

### Prompt cache and session affinity

V7 threads the durable Pi session id through CLI/server model clients and hot switches. Implemented compatibility includes:

- `CacheRetention`: `none`, `short`, `long`
- `supportsLongCacheRetention`
- `supportsExplicitPromptCacheMode`
- `sendSessionAffinityHeaders`
- `sessionAffinityFormat`: `openai`, `openai-nosession`, `openrouter`
- `cacheControlFormat: anthropic`
- OpenAI Chat/Responses prompt cache keys clamped to 64 bytes
- optional 24h OpenAI retention
- Anthropic-style system / last conversation / last tool cache markers and optional 1h TTL
- real Pi session ids used by CLI and framed-server turns; `/new` / RPC `new_session` rotate the id

### Model/runtime configuration

- upstream-style `provider/model` resolver and thinking suffixes
- arbitrary custom provider IDs
- API inheritance plus per-model API override
- model-level base URL overrides
- custom models merged/upserted into provider catalogs
- `modelOverrides`
- custom model defaults (`text`, 128k context, 16,384 output tokens, zero cost when omitted)
- canonical `auth.json`, API-key/OAuth records, legacy read fallback
- `$ENV`, `${ENV}`, `$$`, `$!` and `!command` config values
- shared CLI/server runtime resolver
- provider+model hot switching, including multiple endpoints under one provider
- owned runtime key/base/header metadata (no transient parser-slice borrowing)
- provider/model/override headers
- arbitrary JSON `samplingParams`
- input capabilities, context/output limits and tiered pricing metadata
- thinking level maps with omitted-vs-explicit-null semantics
- compatibility fields consumed by native request builders rather than merely parsed

### Protocol/server

The former fake route catalog remains replaced by a stateful service:

- four-byte big-endian length-prefixed CBOR
- strict hello-first persistent connections
- multi-frame peers and asynchronous post-hello request dispatch
- strict command/envelope validation for implemented commands
- inbound/outbound frame ceilings
- handshake deadline
- concurrent peers
- TCP and Unix-domain listeners
- Unix socket 0600 permissions, advisory ownership lock, stale recovery and ordinary-file safety
- connection-relative attachment state and global runtime locking
- disconnect unlock lifecycle including active-turn retention until idle
- server-assigned session UUIDs
- create/list/attach/detach/prompt/steer/abort/set_model/set_thinking
- thinking capability/clamping
- unsolicited session/server snapshots with connection-relative state/revisions
- atomic 0600 durable session files and restart recovery
- durable native agent history beside protocol session metadata
- real agent execution from framed `prompt`
- user/assistant/tool transcript projection including thinking/usage/cost
- same-connection steer/abort during active tools
- same project environment/runtime resolver as CLI
- effective executable model metadata in hello snapshot
- create/set-model validation against the same catalog

### TUI/editor — materially expanded in V4

V4 begins the real interactive editor port rather than relying only on `readLine()`:

- owned native editor buffer and byte cursor
- UTF-8 scalar-safe left/right insertion and deletion
- word navigation with whitespace/word/punctuation classes
- line start/end and multi-line vertical movement
- delete word / delete-to-line-start / delete-to-line-end
- Emacs-style kill ring with directional accumulation
- yank and yank-pop
- deep owned undo snapshots
- command history with draft restoration
- Linux TTY raw-mode adapter with non-TTY fallback preserved
- stateful multiline redraw/cursor positioning
- Ctrl-C line cancel and contextual Ctrl-D delete/exit
- xterm arrows/home/end/delete and modifier forms
- Kitty CSI-u printable/named/modifier/release parsing for the implemented editor keys
- upstream-style configurable editor/input keybindings
- `$PI_AGENT_DIR/keybindings.json` loading
- canonical + legacy keybinding IDs
- modifier-order normalization
- user overrides replace defaults
- conflict detection

Live PTY tests exercised typo repair with cursor motion, history recall/clear, custom `alt+h` cursor binding, multiline Ctrl-J submission and clean terminal teardown.

### Skills/project environment

- project context discovery
- YAML skill frontmatter (`name`, required `description`, `disable-model-invocation`)
- upstream `<available_skills>` XML prompt representation
- owned project environment so settings/tool-filter strings cannot dangle
- server and CLI use the same project context/settings/skills/tool filters

### MCP/storage/extensions/evals

Retained real implementations include MCP initialize/tools-list/tools-call, session index/storage helpers, extension host/manifest primitives, themes and deterministic mock eval harness.

## Major work still missing

V7 is still **not** a complete behavioral rewrite of upstream Pi. High-value remaining work includes:

1. **Remaining API families** — Cloudflare provider-specific auth/routing, OpenRouter Images and constrained-sampling/image-specific APIs remain. Bedrock now has a native request/event/auth path; its explicitly listed advanced AWS credential-chain gaps remain. Codex Responses and Pi Messages now have native request/event paths; their explicitly listed advanced gaps remain. Vertex automatic ADC/service-account orchestration and Azure resource discovery also remain.
2. **Provider OAuth breadth** — most provider-specific interactive login, token refresh and account-selection flows remain.
3. **Authoritative built-in model catalog breadth** — the upstream source references generated provider JSON not present in the supplied/source checkout. V7 keeps a curated executable catalog plus exact `models.json` metadata rather than fabricating missing generated data. A complete catalog import needs authoritative generated payloads/provenance.
4. **Remaining compatibility controls** — prompt-cache retention/session affinity, routing payloads, grammar/constrained tools, deferred tools, full strict-mode variants and provider-specific cache controls still need deeper model/session abstractions.
5. **Full TUI parity** — visual grapheme clustering/UAX #29, terminal-width wrapping, autocomplete, fuzzy/select/settings lists, scroll views, Markdown, image rendering, alternate-screen viewport, external editor and the coding-agent's many selectors/dialogs remain.
6. **Extension/package parity** — complete extension hook/event lifecycle, refresh behavior, filesystem watchers, clipboard/image processing, syntax highlighting, package-manager edge cases and telemetry remain.
7. **Protocol exhaustive parity** — additional byte-for-byte fixtures and cross-implementation scenario tests against the TypeScript server/client remain valuable.

## Rule for future work

Every added feature must correspond to an upstream behavior, observable compatibility requirement, or necessary native platform abstraction. Generated size is not evidence of progress.

## Checkpoint 88 additions

- Codex SSE requests now use a dependency-free pure-Zig Zstandard frame encoder (raw/RLE blocks) and `Content-Encoding: zstd`; WebSocket frames remain uncompressed.
- Codex retry handling now observes `retry-after-ms`, numeric `Retry-After`, and IMF-fixdate `Retry-After`, with 1s exponential fallback and a 60s maximum accepted server delay.
- Terminal Codex quota/billing errors are no longer treated as transient 429s.
- Focused OpenAI Responses/Codex harness: 138/138 tests passing under Zig 0.16.0.

## Checkpoint 89 additions

- Codex cache/session affinity is clamped to the 64-character OpenAI limit across request bodies, SSE headers, and WebSocket request IDs.
- `cacheRetention: none` suppresses Codex cache-affinity IDs consistently.
- Codex sampling `tool_choice` / `parallel_tool_calls` now replace defaults without duplicate JSON keys.
- Focused Responses/Codex harness: 140/140 passing under Zig 0.16.0.

## V8 checkpoint 91 targeted transport additions
- Codex SSE HTTP idle timeout: separate response-header and per-body-read deadlines, default 300000ms, `0`/`disabled` disables.
- Timeout/abort is cooperative via Zig `Io.Select`; active body reads reset the idle deadline.
- Retries are suppressed once a response has started to avoid replaying emitted deltas.
- Codex SSE body consumption returns immediately after parsed terminal events (`response.completed`, `response.done`, `response.incomplete`, `response.failed`, or API `error`) rather than waiting for TCP EOF.
- Validation used only the targeted Responses/settings/live-state harness; no full project build was run.

## V8 checkpoint 92 — Codex transport diagnostics
- Added owned assistant `diagnostics` metadata as raw JSON through ModelResponse, session JSONL, replay/RPC surfaces.
- Codex WebSocket -> SSE fallback records a redacted `provider_transport_failure` diagnostic without secrets.
- Diagnostics survive retry reset and are freed exactly once at live response teardown.
- Focused diagnostics/import harness: 291/291 tests passed under Zig 0.16.0.
- No full-project build/test was run.

## V8 checkpoint 93 — Codex partial transport failure preservation
- Post-start Codex WebSocket transport failures now produce a durable partial assistant error response instead of throwing away streamed output.
- Partial text/thinking/tool calls are retained; tool arguments are normalized before persistence.
- Transport diagnostics mark `eventsEmitted:true` / `after_message_stream_start` with no SSE fallback, preventing duplicate output.
- Connection-scoped continuation/socket state is invalidated on the failed stream.
- Focused diagnostics/Codex harness: 292/292 tests passed under Zig 0.16.0.
- No full-project build/test was run.

## V8 checkpoint 94 — Codex configurable WebSocket deadlines
- Added `websocketConnectTimeoutMs` / snake-case setting with 15s upstream default and `0`/`disabled` opt-out.
- Threaded connect timeout through settings -> ClientPool -> ResponsesClient -> WebSocket connector.
- Codex WebSocket stream idle now reuses configurable `httpIdleTimeoutMs` instead of a separate hard-coded timeout.
- Focused/imported harness: 293/293 tests passed under Zig 0.16.0.
- No full-project build/test was run.

## V8 checkpoint 95 — Codex API error fidelity
- Added owned `errorMessage` metadata through ModelResponse, session JSONL, agent persistence and RPC output.
- Codex WebSocket `error` and `response.failed` events now preserve partial assistant content plus provider code/message.
- API errors do not emit transport diagnostics and do not fall back to SSE.
- Focused/imported harness: 295/295 tests passed under Zig 0.16.0.
- No full-project build/test was run.

## V8 checkpoint 96 — Codex protocol-error fidelity
- Malformed Codex WebSocket/SSE event JSON is now a durable protocol error instead of being silently ignored.
- Partial assistant content is retained with `errorMessage` / raw protocol reason and no transport diagnostic/retry.
- Generic non-Codex Responses parsing remains tolerant of malformed extension events.
- Focused/imported harness: 297/297 tests passed under Zig 0.16.0.
- No full-project build/test was run.

## V8 checkpoint 97 — GitHub Copilot dynamic headers
- Added shared Copilot transcript-derived request headers across OpenAI Chat, OpenAI Responses and Anthropic Messages.
- `X-Initiator` follows the final message role; `Openai-Intent: conversation-edits` is always set; image-bearing user/tool history adds `Copilot-Vision-Request:true`.
- Provider/model custom headers remain last and can explicitly override Copilot defaults.
- Focused/imported harness: 298/298 tests passed under Zig 0.16.0.
- No full-project build/test was run.

## Checkpoint 98 — model-capability image downgrade

- Added shared transcript preparation that downgrades unsupported user/tool images to explicit text placeholders instead of sending invalid media or silently dropping it.
- Threaded `input_image` model capability through OpenAI Chat, Anthropic, Google/Vertex, Mistral, Bedrock, and Pi Messages clients/runtime.
- Context estimation and payload serialization now use the capability-adjusted transcript; Copilot dynamic-header inference still sees the original transcript.
- Targeted/imported Zig 0.16 harness: 300/300 passed. No full-project build/test was run.

## Checkpoint 99 — native Anthropic and Google image serialization

- Anthropic user/tool-result images now serialize as native base64 image blocks with image-only placeholders and cache-control-safe user media blocks.
- Google/Vertex user images now serialize as `inlineData` parts.
- Google tool-result images use Gemini 3+ multimodal `functionResponse.parts`; Gemini <3 gets the upstream-style separate `Tool result image:` user turn.
- Tool results now use Google `output` / `error` response keys.
- Targeted/imported Zig 0.16 harness: 303/303 passed. No full-project build/test was run.

## Checkpoint 100 — grouped Google function responses

- Consecutive Google/Vertex tool results now serialize as one user turn containing multiple `functionResponse` parts, matching Cloud Code Assist requirements.
- Gemini <3 legacy tool-image follow-ups close the function-response group before emitting the separate image user turn; Gemini 3+ keeps nested multimodal function responses grouped.
- Targeted/imported Zig 0.16 harness: 304/304 passed. No full-project build/test was run.

## Checkpoint 101 — cross-model opaque replay normalization

- Shared transcript preparation now gates opaque reasoning/tool-signature replay on exact provider + API + model identity.
- Cross-model/provider/API assistant thinking becomes ordinary visible text; empty signed thinking is dropped.
- Cross-model tool-call `thoughtSignature` metadata is removed before serialization.
- Targeted/imported Zig 0.16 harness: 305/305 passed. No full-project build/test was run.

## Checkpoint 102 — Anthropic cross-model tool ID normalization

- Shared transcript preparation now supports target-specific cross-model tool ID normalization.
- Anthropic uses the upstream `[A-Za-z0-9_-]` / 64-character rule only for foreign assistant turns.
- Historical tool results are remapped through the same original→normalized ID map so `tool_use_id` remains matched.
- Targeted/imported Zig 0.16 harness: 306/306 passed. No full-project build/test was run.

## V8 checkpoint 103 — Radius discovery/OAuth protocol core

Implemented native Radius gateway discovery/config and OAuth protocol helpers:
- gateway URL normalization and root-relative `/v1/config` / OAuth endpoint resolution;
- owned `/v1/config` parser mirroring upstream top-level validation while filtering malformed model rows;
- Radius model input capabilities, cost buckets, context/max-token metadata, and `thinkingLevelMap` parsing;
- OAuth discovery parser (`authorizationEndpoint`), device-authorization parser, token parser with 60s expiry skew;
- percent-safe refresh/device form builders and native refresh/discovery HTTP helpers.

Focused Zig 0.16 harness: 16/16 passing. Full-project build/test intentionally not run per user request.

## V8 checkpoint 104 — Radius OAuth refresh runtime

Implemented live Radius OAuth credential retention/refresh:
- stored auth.json OAuth credentials retain access, refresh, and absolute expiry through runtime resolution;
- environment/CLI API keys still override stored OAuth and do not inherit refresh metadata;
- PiMessagesClient has a lazy request-time token refresh hook and does not refresh valid tokens;
- ClientPool owns initial refresh material, derives custom Radius gateway roots from `/v1` API bases, and owns refreshed tokens;
- refreshed OAuth tokens are persisted back to auth.json best-effort while remaining usable in-memory if persistence is unavailable;
- CLI and HTTP RPC pools receive agent auth directory and primary OAuth metadata.

Focused runtime/client harness: 290/290 passing. Full-project build/test intentionally not run.

## Checkpoint 105 — Radius dynamic catalog cache
- Custom `oauth:"radius"` providers may omit static models and use gateway-owned catalogs.
- Radius `/v1/config` catalogs convert to owned native ModelInfo entries without collapsing custom provider identity.
- `models-store.json` read/write is lock-aware, preserves unrelated providers, and stores upstream-compatible full model entries.
- Legacy OAuth `auth.json.gatewayConfig` is importable offline when no model store is available.
- Focused Radius store/catalog harness: 17/17 passing under Zig 0.16.0.

## Checkpoint 106 — Offline Radius dynamic catalog integration
- Startup restores built-in/custom Radius catalogs from models-store.json without network access.
- Legacy OAuth gatewayConfig is imported as offline fallback and promoted to models-store best-effort.
- Dynamic Radius ModelInfo entries upsert built-ins, coexist with static models.json models, and receive modelOverrides.
- Runtime resolution prefers the cached model-specific API base over the OAuth gateway root.
- CLI and server effective catalogs include cached Radius models; custom Radius providers with no static models select their restored first model.
- Focused harnesses: cached catalog 35/35, effective composition 31/31, runtime resolution 72/72. main.zig AST check passes.

## Checkpoint 107 — Explicit Radius network refresh
- Added opt-in Radius `/v1/config` network refresh primitive; startup remains cache-only.
- `PI_OFFLINE` blocks refresh before any HTTP/URL work.
- Successful refresh converts to owned dynamic ModelInfo entries and persists upstream-compatible models-store metadata with checkedAt.
- Focused refresh/store harness: 19/19 passing under Zig 0.16.0.

## Checkpoint 108 — Radius OAuth device-code protocol
- Radius device authorization POST and device-token polling are implemented natively.
- RFC 8628 states are classified explicitly: authorization_pending, slow_down (+5s), expired_token, access_denied.
- Polling enforces >=1s cadence, device expiry, cancellation flag, and distinct slow-down timeout diagnostics.
- OAuth tokens preserve optional scope in auth.json and have a direct persistence helper.
- Focused Radius OAuth/auth-storage harness: 22/22 passing under Zig 0.16.0.

## Checkpoint 109 — Interactive Radius device-code login
- `/login <radius-provider> device-code` supports built-in Radius and custom models.json `oauth:"radius"` providers.
- Custom gateway roots are derived safely from provider baseUrl; built-in Radius defaults to radius.pi.dev.
- PI_OFFLINE blocks login before device authorization HTTP.
- Verification URI/user code are surfaced, device flow polls and persists OAuth, and optional scope is retained.
- Interactive OAuth credentials override the startup credential snapshot immediately and rebuild the active Radius client.
- Successful login refreshes the provider models-store cache best-effort; refresh failure leaves cached models usable.
- Focused LiveState and slash-command harnesses pass under Zig 0.16.0.

## Checkpoint 110 — live Radius catalog reload

- Radius `/login <provider> device-code` now reloads the current process model catalog after a successful `/v1/config` refresh.
- Dynamic Radius/pi-messages runtimes are rebuilt from the refreshed cache while long-lived non-Radius runtime configs are preserved.
- Newly discovered gateway model IDs become selectable without restarting the process.
- Dynamic snapshots own their models file, Radius cached catalogs, effective model catalog, Radius resolved runtimes, and merged runtime-config slice; `LiveState` tears them down at shutdown.
- Startup remains cache-only/offline; no automatic Radius network refresh was added.
- Targeted validation only: dynamic reload test, slash Radius login test, and `zig ast-check src/main.zig`; no project-wide build/test.

## Checkpoint 111 — Radius browser/PKCE OAuth

- Added native Radius browser OAuth protocol: secure PKCE verifier/challenge, UUIDv4 state, discovered authorization endpoint, upstream-compatible authorize query, and authorization-code token form.
- Added one-shot loopback callback server on `127.0.0.1:1456/oauth/callback` with route/state/code/error validation and cooperative abort while waiting for a browser callback.
- Added cross-platform browser launch (`cmd start`, `open`, `xdg-open`) with manual-URL fallback.
- `/login <provider> browser` is available for built-in and custom `oauth:"radius"` providers and reuses the same persistence/live credential/catalog-refresh path as device code.
- Targeted validation only: Radius PKCE/callback tests and slash declaration/login-gateway harness; no project-wide build/test.

## Checkpoint 112 — Radius recommended login method

- `/login <radius-provider>` now defaults to browser OAuth, matching upstream's recommended Radius sign-in method.
- Explicit `/login <provider> device-code` remains available for sign-in from another device.
- Non-Radius providers still require an explicit API key and are never silently routed into OAuth.
- Targeted slash declaration/login-gateway harness only; no project-wide build/test.

## V8 checkpoint 138 — current catalogs, auth, RPC/session and shell parity

Checkpoint 138 was developed against the supplied checkpoint 137 and Zig 0.16.0 compiler.
The referenced original source archive was absent from the container; current behavior was
therefore checked against canonical upstream v0.84.1 source/protocol documentation.

Implemented:

- directory-local `AGENTS.override.md` replacement semantics;
- live subprocess session/provider/model/thinking environment identity;
- 55 current Baseten/Qwen generated catalog entries with endpoints, capabilities, limits,
  costs, thinking maps and request dialects;
- native `pi auth` list/check/print behavior with JSON, exit codes, refresh and offline mode;
- widened RPC parsing, full model objects, supported thinking levels, queue modes, current
  state, session entries/tree/stats/commands/fork selectors and richer compaction data;
- active-stream `streamingBehavior`, mutex-protected steering/follow-up FIFOs and deferred
  command ordering without requeue spin;
- direct streaming/cancellable RPC bash and exact durable `bashExecution` session messages;
- append-only model/thinking session entries, active-branch message filtering, and corrected
  ISO timestamps.

Validation at freeze point: 487/487 tests pass; full Debug build and RPC smoke pass;
112 Zig files / 47,389 Zig LOC / zero synthetic files.

See `CHECKPOINT-138.md` for the detailed change and remaining-gap inventory.

## V8 checkpoint 142 — native SQLite backend and retained application shell

- Added a real optional SQLite backend through the stable platform ABI, with the original sessions, entries, sequences, stats, branch cache/tips, lanes/moves, records, facts and writer-lease schema.
- Added transactions, durable reopen, branch-aware querying, cache repair, facts/names/labels, merged logs, FTS5 search, writer fencing and branch/tree forks.
- Kept the normal Linux executable self-contained; only SQLite package consumers and its dedicated integration suite link `sqlite3` and libc.
- Added the retained alternate-screen shell with synchronized painting, modal overlays, focus restoration, SGR/X10 mouse routing, selection/OSC52, search and atomic IME composition.
- Added native box, input, select-list, settings-list, cancellable-loader and generic undo-stack components.
- Worktree validation covers all 670 unique declared tests; six C-backed repository cases are executed in the dedicated 11/11 SQLite process rather than silently skipped.
- Still missing: arbitrary upstream JS/TS extension execution, wiring every original interactive coding-agent screen, remote session adapters, and the complete provider enterprise-auth/proxy/retry matrix.


## V8 checkpoint 145 — migration, proxy, secure-remote and live-SQLite parity

- Added upstream JSONL v1/v2→v3 migration, atomic saves, stable creation timestamps and durable fork provenance.
- Added complete-tree session discovery plus native stats, tree, rename, guarded delete and migration administration commands.
- Switched to original cwd session-directory encoding and recover pre-145 hashes/misplaced sessions at startup.
- Ported one-time credential, settings, keybinding, commands/prompts and managed-binary migrations with atomic/no-clobber behavior.
- Added target-aware HTTP(S) proxy policy to primary provider/image transports and persistent Codex WebSockets, including NO_PROXY and global httpProxy semantics.
- Added certificate-verified remote target TLS and authenticated HTTP/HTTPS CONNECT tunnelling.
- Added the optional complete pi-sqlite-live server with canonical snapshot persistence, writer leases and restart recovery.
- Corrected open-stream reads that could wait for a large scratch buffer to fill.
- Complete test graph passed: all 740 unique declarations executed; root 723 pass/7 SQLite-isolated/0 fail; dedicated SQLite repository 11/11 and live persistence 5/5.
- Remaining priorities: arbitrary JS/TS extensions, complete native screen wiring, server TLS/mTLS, proxying every OAuth/cloud bootstrap request, automatic image transcoding, and broader enterprise/interoperability coverage.

## V8 checkpoint 146 — persistent original JavaScript/TypeScript extension compatibility

- Added direct `.ts`, `.js`, `.mts`, `.cts`, `.mjs` and `.cjs` extension loading while retaining the native `extension.json` ABI.
- Added `package.json` `pi.extensions`, `index.ts`/`index.js`, explicit-path and trusted one-level-directory discovery with native-manifest precedence.
- Added an embedded persistent Node protocol bridge with real dependency resolution first, Pi/TypeBox compatibility shims, retained closure state, record-separated output, bounded responses, serialized calls and hard invocation deadlines.
- Added native registration and execution for extension hooks, tools, commands, flags and keyboard shortcuts.
- Wired canonical agent/turn/message/tool lifecycle events, legacy input/tool aliases, `before_agent_start`, per-provider `context` projection and extension shortcuts into the live coding-agent paths.
- `before_agent_start` can replace the assembled system prompt and append durable hidden custom context; `context` can filter/reorder/inject request-only messages without mutating the session tree.
- Command and shortcut actions now persist `setSessionName` and `appendEntry` mutations through CLI, interactive and RPC paths.
- The original supplied extension corpus registration probe loaded 74/78 entries. The four qualified failures require npm packages absent from the source snapshot (`@anthropic-ai/sdk`, `@earendil-works/gondolin`, `@anthropic-ai/sandbox-runtime`, and `ms`).
- Fresh-cache validation passed with all 754 unique declarations executed: all-package root 737 pass/7 SQLite isolates/0 fail, dedicated SQLite repository 11/11, live SQLite persistence 5/5, SQLite CLI 8 active/6 isolated/0 fail, executable suite 4/4, all three Debug builds, formatting and real-source audit.
- Remaining priorities: interactive extension-owned UI parity, provider registration/OAuth APIs, complete dynamic module/runtime semantics beyond the validated Node 22 bridge, server TLS/mTLS, image normalization, and the remaining enterprise/provider interoperability matrix.

## Checkpoint 147 — bidirectional extension UI and live context

- Added correlated worker-to-native UI request/response framing that can suspend
  and resume the same asynchronous TypeScript extension handler.
- Added native select, confirm, input, prefilled editor and bounded custom
  request paths with noninteractive fallbacks.
- Added retained notifications, status, widgets, custom header/footer, terminal
  title, working indicator, hidden-thinking label and editor mutations.
- Added full session header/entry/active-branch/leaf snapshots and compatibility
  session-manager read APIs.
- Applied command/shortcut labels, model changes, thinking levels and exact
  active-tool selections to the live native runtime and durable session tree.
- Fixed cross-allocator ownership for parallel extension-tool results; the
  execution-time tool-filter E2E now exits cleanly under DebugAllocator.
- Validation: 741 pass/7 isolated/0 fail in the 748-case all-package root,
  all 758 unique declarations executed through dedicated linked processes,
  three Debug builds, and three real extension end-to-end gates.
- Remaining priorities: arbitrary extension components/renderers, an ordered
  side-effect queue for every hook path, provider/OAuth/reload semantics,
  dependency installation, complete original screen wiring, server TLS/mTLS,
  image normalization and enterprise interoperability breadth.

## Checkpoint 148 — ordered extension actions and declarative providers

- Added allocator-owned, canonical extension action records and a mutex-protected FIFO with monotonic sequence numbers.
- Lifecycle hooks and extension tool callbacks now capture side effects on any worker thread and apply them only at deterministic agent-thread safe points.
- Ordered actions cover custom messages, steering/follow-ups, session names, custom entries, labels, active tools, model/thinking changes, provider registration/removal, abort and shutdown.
- `agent_end` handlers can queue a durable continuation over the same session, while an authoritative `shouldStopAfterTurn` decision remains final and does not consume queued messages.
- `session_shutdown` actions are drained and saved after the last agent turn, including runs that never initialize a model pool.
- Added declarative `registerProvider`/`unregisterProvider` with transactional replacement, shallow re-registration merge, baseline restoration, custom model injection and runtime hot switching.
- Extension provider definitions reuse the native `models.json` validator, environment/key resolver, transport/API metadata and live model catalog rather than introducing a parallel parser.
- Real E2E gates validate lifecycle ordering, extension-tool callback ordering, `agent_end` continuation, shutdown persistence, and an in-hook provider registration/model switch against a live OpenAI-compatible SSE endpoint.
- Complete validation: all-package root 748 pass/7 SQLite-isolated/0 fail; all 765 unique declarations executed; three Debug builds and the extension E2E suite pass.
- Remaining priorities: arbitrary extension components/renderers, fully ordered command/shortcut return semantics, executable provider callbacks and extension OAuth, dependency installation, complete original screen wiring, server TLS/mTLS, image normalization and enterprise interoperability breadth.

## Checkpoint 150 — executable extension tools and rich progress

- Original JavaScript/TypeScript extensions can now replace same-name built-in tool execution rather than only changing presentation.
- Model-visible schemas and dispatch both honor extension ownership while active-tool filtering remains authoritative.
- Compatibility `create*Tool()` helpers explicitly delegate to the native Zig implementations, preserving renderer-only extensions.
- Original `prepareArguments()` handlers run before schema validation and execution, with isolated failure handling.
- Extension tools and rich `tool_result` hooks now retain ordered partial text, image MIME/base64 data, structured details and error state across allocator, terminal, JSON, session and protocol boundaries.
- Protocol v1 now emits and strictly decodes rich running `item_updated` and terminal `item_finished` tool items.
- Script-worker shutdown force-reaps POSIX children that ignore `SIGTERM`, avoiding an unbounded Zig 0.16 child wait.
- Remaining priorities: true live cross-process updates before the tool promise resolves, multiple-image fidelity, arbitrary retained component trees and invalidation, function-valued providers/OAuth, dependency installation, complete original screen wiring, server TLS/mTLS, image normalization and the enterprise interoperability matrix.

## V8 checkpoint 152

- Exact provider tool-call IDs now reach original JavaScript/TypeScript `tool.execute()` callbacks.
- One live AbortSignal is shared through the execute argument and `ctx.signal`; correlated worker control frames cancel pending promises without requiring a renderer, suppress late updates, and preserve worker reuse.
- Tool-local usage/cost and `addedToolNames` survive live/final results, hooks, JSON output, JSONL persistence, reload, fork and statistics.
- Installed packages now resolve authoritative `package.json` `pi.extensions`, `pi.skills`, `pi.prompts` and `pi.themes` exact paths, with conventional-directory fallback when no Pi manifest exists.
- Package resources are wired into startup, reload, RPC command discovery and standalone project environments; exact `SKILL.md` manifest paths are supported.
- Validation before freezing: 775 pass/7 intentional SQLite isolates/0 fail in the 782-case root graph; all 793 source-level declarations execute through the complete topology.
- Remaining priorities: package glob/filter and npm/git lifecycle, multiple images, arbitrary async component invalidation, function-valued providers/OAuth, complete fullscreen screens, server TLS/mTLS, image normalization and enterprise interoperability.

## V8 checkpoint 153 — ordered multi-image parity

- Replaced the single-image internal boundary with allocator-owned ordered image arrays while retaining the legacy first-image fields for source and JSONL compatibility.
- User prompts now persist one canonical message containing every ordered image rather than synthesizing one user entry per attachment.
- Tool updates and final results retain all images across sequential and parallel execution, extension `onUpdate`, `tool_result`/`after_tool` replacement, lifecycle replay, renderer input, JSON mode, protocol-v1 events, session save/load/fork and statistics.
- Added all-image request serialization for OpenAI Chat, OpenAI Responses, Anthropic, Google, Mistral, Bedrock and Pi Messages; context estimation, vision capability detection and transcript repair now account for the complete image set.
- Preserved backward compatibility: old singular fields remain the canonical first image and old session files load unchanged; new JSONL emits the original ordered content-array shape.
- A whole-tree audit caught and fixed a production-only parallel progress omission plus a standalone-build-only allocator initialization that the test-only compile graph did not instantiate.
- Real executable E2E validation streamed two images, returned three images, emitted them in JSON events, persisted all three in JSONL, completed the assistant turn and produced zero stderr.
- Complete worktree topology passed: 782/789 root cases passed with seven intentional SQLite isolates and zero failures; the dedicated SQLite repository, persistence, CLI/schema and executable suites all passed; all three Debug executables built.
- Remaining priorities: package manifest glob/filter and managed npm/git lifecycle; arbitrary async extension component trees; function-valued provider transports and extension OAuth; complete fullscreen screen wiring; native server TLS/mTLS; automatic image resizing/transcoding; and the remaining enterprise credential/retry/interoperability matrix.

## V8 checkpoint 156 — package transaction recovery and verified migration

- Added atomic target-derived journals for managed Git checkout replacement, recording canonical target, prepared sibling and previous backup before destructive renames.
- Added bounded, deterministic, path-confined recovery that commits a prepared checkout, restores a backup, or cleans stale siblings according to actual filesystem state.
- Git install/update/remove resolve an existing target journal before another mutation, preventing overlapping unresolved swaps.
- Added `pi repair` for user and trusted project scopes with machine-readable recovery counters.
- Added verified migration from historical `settings.json.packages`: native `packages.json` is atomically written, re-read and validated before only the legacy field is atomically removed; unrelated settings are preserved.
- Real executable recovery E2E commits a prepared checkout, removes its backup/journal, migrates a legacy npm package, and leaves no temporary artifacts.
- Complete build-test graph finished: 815 passed, 7 deliberate SQLite isolates skipped, 0 failed; all skipped behavior passes in dedicated linked SQLite suites; 13/13 build steps succeeded.
- Remaining priorities: package configuration TUI/resource origins, richer cross-process owner diagnostics and startup repair presentation, complete npm/pnpm/Bun platform parity, arbitrary async extension components, function-valued providers/OAuth, full screen wiring, server TLS/mTLS, image normalization, and enterprise interoperability breadth.

## V8 checkpoint 157 — native package selector and observable coordination

- Added allocator-owned package-resource inventories that retain disabled extension, skill, prompt and theme candidates rather than projecting only enabled paths.
- Added global package-resource toggles and trusted project-local inherit/load/unload deltas using the original ordered `+`/`-` selector semantics.
- Added `pi config` in fullscreen, plain and JSON forms, plus deterministic `--set PACKAGE TYPE PATH STATE` automation.
- Added a retained alternate-screen selector with search, width-aware rendering, navigation, page movement, mode switching and project tri-state cycling.
- Added package-operation metadata containing PID, operation, start time and registry root, plus nonblocking active/stale-owner inspection.
- Added `pi repair --check` and interactive startup warnings for active owners, stale metadata, interrupted Git journals and pending legacy migration.
- Moved package configuration to a single locked read-modify-write transaction, eliminating a real concurrent lost-update race.
- Real executable gates cover CLI configuration, pseudo-terminal rendering and persistence, active/stale lock inspection, and twelve simultaneous two-process configuration rounds with zero lost edits.
- Complete build-test graph finished with 823 passed, 7 deliberate SQLite isolates skipped and 0 failed; all skipped behavior passes in dedicated linked SQLite processes.
- Remaining priorities: top-level auto/explicit resource-origin editing in the selector, complete package/settings screens, fuller npm/pnpm/Bun platform behavior, arbitrary async extension component trees, function-valued providers/OAuth, server TLS/mTLS, image normalization, and enterprise interoperability breadth.

## V8 checkpoint 161 — settings-driven assistant retry parity

- Added the original nested `retry.enabled`, `retry.maxRetries`, and `retry.baseDelayMs` settings with field-preserving global/trusted-project merge and live reload.
- Added original `compaction.enabled` startup/reload behavior without conflating context-overflow recovery with transient retry.
- Added a shared allocation-free transient provider/transport classifier with quota, budget, subscription, and billing fail-fast exclusions.
- Added bounded saturating exponential backoff, whole-run cancellation, and retry-only cancellation.
- Added normalization of retryable thrown Zig transport errors into the same assistant retry path.
- Added original `auto_retry_start` and `auto_retry_end` JSON/RPC events plus print and interactive status.
- Made RPC `set_auto_retry`, `abort_retry`, and state/reload synchronization affect actual execution, including cancellation while the agent thread is busy.
- Real RPC gates validate success, concurrent cancellation without consuming the next response, runtime enablement, settings-file reload disablement, state synchronization, clean exit, and zero stderr.
- Complete validation: direct root **855/855**; build graph **13/13** steps with module **849 pass/6 SQLite isolates/0 fail**; isolated repository **11/11**; all three Debug builds.
- Remaining retry-specific gaps: summarization retry/events, durable persistence of RPC retry toggles, provider-level retry subsettings, and durable intermediate failed-attempt history excluded from active model context.

## V8 checkpoint 162 — summarization retry, append-only compaction, branch navigation, and durable retry history

- Compaction and branch-summary model calls share one settings-driven retry boundary with exponential abortable backoff, quota/billing fail-fast classification, and the original `summarization_retry_scheduled`, `summarization_retry_attempt_start`, and `summarization_retry_finished` event sequence.
- Requested model-assisted compaction no longer silently substitutes an extractive fallback after a model or stream failure. Terminal failures and cancellation leave the original session untouched.
- Replaced destructive compaction with an append-only `compaction` entry retaining raw summary, `firstKeptEntryId`, `tokensBefore`, details, `fromHook`, model metadata, usage, and cost while preserving all original ancestry.
- Added compaction-aware active-context reconstruction: latest summary, retained pre-boundary tail, and post-boundary entries. Provider requests, auto-compaction estimation, token estimation, and RPC `get_messages` use this projection, while `get_entries` keeps complete history.
- Raw summaries stay canonical in JSONL; provider context synthesizes the original user-message wrappers with allocator-safe ownership.
- Repeated compaction preserves earlier boundaries and original messages; unchanged compaction at the active tip is a no-op; malformed boundaries safely fall back to the full path.
- Failed assistant attempts remain durable append-only history while a live-only exclusion set omits them from the immediate retry request. Successful attempts append separately.
- RPC `set_auto_retry` performs an advisory-lock-protected atomic global settings update, preserves nested provider retry values, removes conflicting aliases, verifies persistence, and refuses malformed objects without clobbering the file.
- Native summarized tree navigation finds the common ancestor, summarizes only the abandoned branch, persists `branch_summary`, and supports editor-prefill positioning.
- Direct complete root closure: **877/877 passed**. The normal module process completed with **871 passed, six intentional SQLite isolates, and zero failures**; isolated behavior passes in dedicated linked processes.
- Real RPC processes validate persisted retry configuration, durable failed/successful assistant attempts, canonical compaction retry events, append-only history, compacted `get_messages`, process exit 0, and zero stderr.
- Remaining priorities include provider-internal timeout/retry/max-delay settings, token-budget and split-turn compaction, compaction/tree extension hooks, full retained package/model/login/settings/session screens, arbitrary async extension components, function-valued providers/OAuth, server TLS/mTLS, image transforms, and enterprise interoperability breadth.

## V8 checkpoint 167 — request-local summary budgets and fullscreen searchable tree selector

- Added request-local completion options to the native model-client ABI without mutating provider configuration.
- Added the original independent 2,048-token branch-summary output ceiling.
- Added original compaction output budgets: 80% of reserve tokens for ordinary summaries and 50% for split-turn prefixes.
- Added isolated summary requests that disable reusable prompt-cache retention and live session-affinity identifiers across implemented providers.
- Wired the request-local cap/isolation boundary through OpenAI Chat, OpenAI Responses/Codex, Anthropic, Google, Mistral, Bedrock, Pi Messages, and the deterministic mock client.
- Added a retained fullscreen bare-`/tree` selector with incremental search, labels, depth, active branch/tip markers, five filter modes, folding, paging, Unicode-safe rendering, and terminal lifecycle restoration.
- Preserved explicit-ID tree navigation, summary choice, `skipPrompt`, editor prefill, labels, append-only history, and tree extension hooks.
- Real provider/PTTY validation observed a 2,048-token summary cap, no summary affinity/cache fields, successful historical-entry search selection, durable summary persistence, exit 0, and zero stderr.
- Complete exact-source closure: 904/904 direct root tests; normal graph 897 pass/7 intentional SQLite isolates/0 fail; 13/13 build steps; all dedicated SQLite and executable suites passed.
- Remaining priorities: exact token-estimation/prompt-clamping nuances, complete original tree visualization/actions/progress/cancellation UX, remaining fullscreen managers, function-valued providers/OAuth, full npm/pnpm/Bun behavior, async extension components, server TLS/mTLS, image normalization, bootstrap retry propagation, and enterprise interoperability breadth.

## V8 checkpoint 168 — shared bootstrap networking and richer tree interaction

- Added a shared bounded HTTP request path for OAuth, cloud credentials, management catalogs, and other bootstrap traffic.
- Reused the live provider retry budget, per-attempt deadline, server retry headers, retry-delay cap, cooperative cancellation, target-aware proxy policy, and `NO_PROXY` semantics instead of maintaining one-off fetch loops.
- Migrated OpenAI Codex, Anthropic, OpenRouter, Radius, xAI, Kimi Coding, and GitHub Copilot OAuth/token/catalog traffic.
- Migrated Radius `/v1/config`, Google authorized-user/service-account ADC, AWS web identity and AssumeRole, ECS/container credentials, and IMDSv2 credentials.
- Explicitly removed application proxy settings from ECS/IMDS metadata requests to avoid credential leakage through a general proxy.
- Wired the same network policy into the live client pool, hot reload, interactive login, device login, pending-flow completion, and noninteractive `pi auth check`.
- Improved compact-context estimation with canonical compact JSON and shared tool-call accounting that excludes transport-only wrapper fields.
- Expanded the fullscreen session tree with wrapped movement, search-clearing Escape, direct and backward filter controls, label editing, label timestamps, OSC 52 copy, mouse selection/scrolling, and hit-component wheel dispatch.
- Real executable bootstrap validation covers retry and durable token replacement, `X-Should-Retry:false`, timeout pre-emption, settings-proxy absolute-form routing, and `NO_PROXY` bypass.
- Direct root closure: **913/913 passed**. Normal graph: **906 passed, 7 intentional SQLite isolates, 0 failed**, with all isolated behavior passing in dedicated linked processes.
- Remaining priorities: update/install reporting through the shared management client, every external OAuth/cloud/catalog bootstrap edge case, complete tree visual grammar and mouse actions, remaining fullscreen managers, function-valued providers and extension-owned OAuth, server TLS/mTLS, image normalization/transcoding, and enterprise telemetry/interoperability breadth.

## V8 checkpoint 169 — fullscreen model selector, release lifecycle, and managed search binaries

- Added a retained fullscreen `/model` selector with scoped/all catalog views, configured-provider filtering, canonical provider/id fuzzy search, current-model anchoring, model capability metadata, paging, mouse selection, bounded double-click confirmation, and deterministic terminal restoration.
- Wired selected identities through the native live-state boundary, durable `model_change`/`thinking_level_change` entries, model-specific thinking clamping, and no-client/mock configurations that previously changed only the model string while retaining a stale provider.
- Added exact bundled upstream Pi 0.84.1 changelog projection, atomic `lastChangelogVersion` acknowledgement, condensed changelog settings, `/changelog`, bounded proxy-aware latest-version checks, and the original anonymous install report with telemetry/offline environment controls.
- Added agent-private and system discovery plus on-demand native acquisition for `fd` and `ripgrep`, using the shared management HTTP retry/timeout/proxy policy, platform-specific assets, bounded downloads, archive extraction, unique temporary paths, atomic executable installation, Termux/offline suppression, and native Zig fallbacks.
- Real E2E validation covers the retained model selector, canonical durable model identity, changelog acknowledgement, release notice, install report, managed ripgrep download/extraction/execution, and second-process cache reuse with no duplicate network request.
- Direct root closure: **926/926 passed**. Normal graph: **919 passed, 7 intentional SQLite isolates, 0 failed**, with all isolated behavior passing in dedicated linked processes; build graph **13/13**; all three Debug builds passed.
- Remaining priorities: complete fullscreen package/login/settings/session management, exact upstream model-selector visual/keybinding breadth and model-management actions, self-update/install commands and richer update UI, complete npm/pnpm/Bun behavior, arbitrary asynchronously invalidated extension component trees, function-valued providers/OAuth, server TLS/mTLS, image normalization/transcoding, and enterprise interoperability breadth.

## V8 checkpoint 172 — media privacy, terminal image policy, and skill-command controls

- Added original `terminal.showImages`, `terminal.imageWidthCells`, `images.blockImages`, and `enableSkillCommands` settings with global/project deep merge, legacy aliases, canonical nested persistence, retained settings-screen controls, and transactional live reload.
- Enforced `blockImages` at the final provider boundary after extension transforms, retaining exact append-only history while stripping legacy and ordered image payloads from request context.
- Added the original blocked-image placeholder and fail-closed allocation behavior.
- Applied image visibility and width to native terminal protocols, explicit fallbacks, and extension custom renderers.
- Applied skill-command disabling to slash execution, help, completion, and RPC discovery without disabling skill context resources.
- Real loopback-provider/RPC validation proves blocked images never leave the process, allowed images still work, durable images remain intact, and skill command inventories update immediately after reload.
- Completed changed-area closure: 333/333 agent/AI tests, 649/649 settings/slash/completion/project/TUI tests, 11/11 SQLite repository tests, 10/10 ordinary executable tests, and zero E2E stderr.
- Remaining priorities: the rest of the settings surface and project override editor, image resize/EXIF/transcoding, fullscreen package/account management, complete package-manager behavior, async extension component invalidation, function-valued providers/OAuth, server TLS/mTLS, and enterprise interoperability breadth.
