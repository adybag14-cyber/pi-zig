# Pi upstream `853a80d` to native Zig parity audit — checkpoint 188

The comparison target is authoritative upstream main commit
`853a80d26c90a14c1886f0ebb8ffaae133ca2185`, containing Pi 0.84.4. Status is
based on source-delta inspection and executable behavior, not filenames or
version strings.

| Upstream 0.84.2–0.84.4 area | Native result | Evidence |
| --- | --- | --- |
| Generated provider/model data | Implemented exactly | 1,290 models, 39 providers, pinned archive/structure/source hashes and generator check |
| User agent, tool choice, thinking budgets/maps | Implemented | Focused request-body tests across OpenAI, Responses, Anthropic, Google, Mistral, Bedrock and Pi Messages |
| Anthropic fallbacks/pricing | Implemented | Fallback beta/payload and returned-model cost regression |
| OpenAI reasoning details, xAI Responses, Codex `end_turn` | Implemented | Streaming/non-streaming ordered replay and session round-trip regressions |
| Bedrock redacted reasoning and response headers | Implemented | Split base64 reassembly/replay and raw gateway-header observer tests |
| Copilot login policy/rate limiting | Implemented | Account catalog, Individual fallback, known policy filter and bounded sequential enablement tests |
| Session/agent ordering and compaction | Implemented | Final-turn prepare suppression, post-tool custom ordering, pre-next-request compaction and failed-compaction event tests |
| Default tools, PowerShell, strict experimental tools | Implemented | Filter preservation, Windows UTF-8/bypass execution and constrained-schema tests |
| Model/thinking controls | Implemented | Searchable selectors, session-only Enter, Ctrl+S defaults, persistent scope tests |
| Session sharing | Implemented | Active-branch export, `pi.share` metadata, Radius upload and private-gist URL tests |
| Settings/BOM/diagnostics/nested skills | Implemented | Parser, scoped persistence, path diagnostic and recursive discovery tests |
| RPC queue and extension UI events | Implemented | `clear_queue`, prompt start/end and wire-format tests |
| TUI terminal/copy/completion regressions | Implemented | Capability overrides, host clipboard, recursive ranking, generic release, path double-click and VS Code paste tests |
| Npm downgrade prevention | Implemented | Strict semver-greater selection test plus complete package suite |
| Cloudflare Worker binding fetch | Native-equivalent boundary | Zig uses configured native HTTP transport; JavaScript Worker binding objects do not exist |
| V8 maximum-string render chunking | Not applicable | Native Zig output uses byte slices and has no V8 UTF-16 string ceiling |

The final Windows graph passed 1,035 module tests plus every dedicated SQLite
and executable process. Five real Linux PTY/loopback gates passed. The only
unmet external acceptance result is a successful OpenRouter free completion:
the authenticated account was at its published 50/50 daily limit. Reachability,
terminal classification, zero paid traffic, and zero automatic retries were
verified instead.
