# Original Pi 0.84.1 versus native Zig checkpoint 142

## Reference

The parity reference is the uploaded `pi-main (3)(2).zip`, whose coding-agent and AI packages identify as Pi 0.84.1. Status is based on source behavior, public contracts and executable tests; source-file names or line counts alone are not treated as proof of parity.

## Status by subsystem

| Subsystem | Checkpoint 142 status | Native evidence | Principal remaining work |
|---|---|---|---|
| Build/runtime | Substantial | Zig 0.16.0 executable, clean build/test, no Node runtime, self-contained normal Linux binary | Cross-platform release/package matrix |
| Agent loop/tools | Substantial | Multi-turn tool loop, cancellation, compaction, queues, built-in filesystem/shell/search tools and native extension hooks | Specialized tool edge cases and exhaustive fixtures |
| Sessions/history | Substantial | Durable JSONL tree plus native SQLite repository, media, fork/clone/import/export, exact IDs, resume, branch/tree operations | Wire SQLite selection into every CLI/server path and complete every custom-entry rendering rule |
| SQLite backend | Substantial native port | Stable ABI wrapper, canonical schema/migrations, transactions, entries, branches, lanes, records, facts, stats, leases, FTS and forks | Remaining adapter/conformance conveniences and broader production migration fixtures |
| Remote session backends | Early/partial | Protocol and native client foundations | Original remote repository/search adapters, reconnection and lease policy breadth |
| AI transports | Substantial but incomplete | Native OpenAI, Codex, Anthropic, Google/Vertex, Mistral, Bedrock, Pi Messages/Radius and mock paths | Complete provider/auth/proxy/retry/diagnostic matrix |
| Authentication | Substantial but incomplete | Credential storage and multiple OAuth/device-code implementations | Enterprise/cloud credential chains and all provider UX |
| CLI/resources | Substantial | Ordered stdin/files/turns, contexts, skills, packages, templates, themes, extension flags/commands | Remaining conflict diagnostics, backend selection and lesser subcommands |
| Multimodal | Substantial core | Magic-byte images, durable replay, provider conversion, terminal image protocols | Automatic resize and exhaustive provider limits |
| RPC/protocol | Substantial | Strict protocol-v1 decoder, typed commands, sessions/models/tree/stats/bash and events | Complete optional-field and byte-level interoperability matrix |
| Native client | Substantial core | Framing/handshake, revision state, request correlation, leases and Unix transport | Full production reconnection policy and every original convenience API |
| Telemetry | Substantial core | Contexts, spans, attributes, events, status, schema and deterministic memory backend | Production exporters/integration breadth |
| TUI rendering | Substantial core | Markdown, LaTeX, Kitty/iTerm2 images, Unicode-cell behavior, themes and synchronized differential painting | Every original message/dialog renderer and image-resize path |
| TUI application/input | Substantial core | Retained layout, alternate-screen lifecycle, overlays, focus, mouse, selection, search, OSC52, IME and widgets | Wire all original coding-agent screens, external editor/platform details and extension-owned UI |
| Extensions | Partial/native alternative | Isolated native hooks/tools/flags/commands and scoped state | Drop-in arbitrary JS/TS extension compatibility and rich `ExtensionContext` |
| Server/MCP | Partial to substantial core | Native framing, server, sessions, MCP tools and transports | Remaining original package breadth/interoperability fixtures |
| Evals/auxiliary packages | Early to partial | Native evaluation harness and selected behavior | Most original eval and auxiliary package functionality |

## Checkpoint 142 gains over checkpoint 141

1. A real optional SQLite session backend using the platform ABI and the original canonical schema.
2. Transactional session/entry/branch/lane/record/fact/statistics operations with writer fencing.
3. FTS5 search, cache repair, durable reopen and branch/tree session forks.
4. A retained alternate-screen application shell with synchronized differential repainting.
5. Modal overlays, focus restoration, mouse hit testing, drag selection and OSC52 export.
6. Search/highlighting and atomic IME composition state.
7. Native box/input/select/settings/loader widgets and a generic undo stack.
8. A build split that preserves a self-contained normal executable while testing the optional SQLite package with explicit libc/SQLite linkage.

## Explicit non-claims

- The SQLite package exists and is fully exercised as an optional backend; the default CLI session manager has not been silently changed from its JSONL tree.
- The new application shell and widgets are not yet equivalent to every original coding-agent interactive screen.
- Native extension isolation is not source/binary compatibility with arbitrary upstream JavaScript/TypeScript extensions.
- Passing all native tests does not imply every original package and provider edge case has been ported.
