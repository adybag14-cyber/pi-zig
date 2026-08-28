# Original Pi 0.84.1 versus native Zig checkpoint 141

## Reference

The parity reference is the uploaded `pi-main (3)(1).zip`, whose coding-agent and AI packages identify as Pi 0.84.1. Status is based on source behavior, public contracts and executable tests; names and source-line counts are not treated as proof of parity.

## Status by subsystem

| Subsystem | Checkpoint 141 status | Native evidence | Principal remaining work |
|---|---|---|---|
| Build/runtime | Substantial | Zig 0.16.0 executable, clean build/test, no Node runtime | Cross-platform release/package matrix |
| Agent loop/tools | Substantial | Multi-turn tool loop, cancellation, compaction, queues, built-in filesystem/shell/search tools | Specialized tool edge cases and exhaustive fixtures |
| Sessions/history | Substantial | Durable JSONL tree, media, fork/clone/import/export, exact IDs, resume, active model/thinking restore | Every custom-entry rendering rule and backend adapter |
| AI transports | Substantial but incomplete | Native OpenAI, Codex, Anthropic, Google/Vertex, Mistral, Bedrock, Pi Messages/Radius and mock paths | Complete provider/auth/proxy/retry/diagnostic matrix |
| Authentication | Substantial but incomplete | Credential storage plus multiple OAuth/device-code implementations | Enterprise/cloud credential chains and all provider UX |
| CLI/resources | Substantial | Ordered stdin/files/turns, contexts, skills, packages, templates, themes, extension flags/commands | Remaining conflict diagnostics and lesser subcommands |
| Multimodal | Substantial core | Magic-byte images, durable replay, provider conversion, terminal image protocols | Automatic resize and exhaustive provider limits |
| RPC/protocol | Substantial | Strict protocol-v1 server decoder, typed commands, sessions/models/tree/stats/bash and events | Complete optional-field and byte-level interoperability matrix |
| Native client | Substantial core | Framing/handshake, revision state, request correlation, leases and Unix transport | Full production reconnection policy and every original convenience API |
| Telemetry | Substantial core | Contexts, spans, attributes, events, status, schema and deterministic memory backend | Production exporters/integration breadth |
| TUI output | Substantial core | Markdown, LaTeX, Kitty/iTerm2 images, Unicode-cell behavior, themes and fullscreen output | Complete overlays/dialogs/application shell and all image resize paths |
| TUI input/layout | Substantial core | Kitty/xterm keys, fragmented stdin, paste, retained stacks, clipping, scrolling and scrollbars | Mouse interaction, IME lifecycle, selection/search and all widgets |
| Extensions | Partial/native alternative | Isolated native hooks/tools/flags/commands and scoped state | Drop-in arbitrary JS/TS extension compatibility and rich ExtensionContext |
| Server/MCP | Partial to substantial core | Native framing, server, sessions, MCP tools and transports | Remaining original package breadth/interoperability fixtures |
| Session backends | Partial | Native local durable storage | Original SQLite/remote repositories, queries, leases and migrations |
| Evals/auxiliary packages | Early to partial | Native evaluation scaffolding and selected behavior | Most original eval and auxiliary package functionality |

## Checkpoint 141 gains over checkpoint 140

1. A real native telemetry package with deterministic span semantics and validation.
2. Strict server-message decoding and corrected durable/live session metadata boundaries.
3. A reusable stateful native client with typed commands, correlation, leases and Unix transport.
4. Native Kitty/iTerm2 images with metadata parsing, cropping and placement reuse.
5. Width-aware Markdown and broad LaTeX-to-Unicode rendering integrated into interactive output.
6. Rich Kitty/xterm key parsing and incremental fragmented terminal-input processing.
7. Unicode 15.1 terminal-cell measurement, cluster-safe slicing/truncation and OSC-link hit testing.
8. Retained vertical/horizontal layout, flex-like allocation, clipping, scrolling and proportional scrollbars.

## Explicit non-claims

- Native extension isolation is not source/binary compatibility with arbitrary upstream JavaScript/TypeScript extensions.
- The retained TUI primitives do not yet equal the original complete alternate-screen application shell.
- Passing 644 native tests does not imply every original package has been ported.
- Generated Unicode property intervals are data tables, not evidence of feature parity by source volume.
