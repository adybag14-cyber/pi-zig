# Original Pi 0.84.1 versus native Zig checkpoint 143

## Reference

The parity reference is the uploaded `pi-main (3)(3).zip`, whose coding-agent and AI packages identify as Pi 0.84.1. Its SHA-256 matches the source archive used for checkpoint 142. Status is based on source behavior, public contracts and executable tests; matching file names or increasing line count alone are not treated as proof of parity.

## Status by subsystem

| Subsystem | Checkpoint 143 status | Native evidence | Principal remaining work |
|---|---|---|---|
| Build/runtime | Substantial | Zig 0.16.0 static Debug executable, clean build/test, no Node runtime | Cross-platform release/package matrix |
| Agent loop/tools | Substantial | Multi-turn tool loop, cancellation, compaction, queues, built-in filesystem/shell/search tools and native extension hooks | Specialized tool edge cases and exhaustive fixtures |
| Sessions/history | Substantial | Durable JSONL tree plus native SQLite repository, media, fork/clone/import/export, exact IDs, resume and branch/tree operations | Select SQLite through every production path and complete custom-entry rendering |
| SQLite backend | Substantial native port | Stable ABI wrapper, canonical schema/migrations, transactions, entries, branches, lanes, records, facts, stats, leases, FTS and forks | Production backend selection and broader migration/conformance fixtures |
| Remote live sessions | Substantial core | Owned snapshots, transcript reducer, exclusive lifecycle, replacement rollback, prompt/steer, abort, model/thinking, reconnect and disposal | Rich interactive remote UI and exhaustive race/interoperability fixtures |
| Remote repositories/search | Early/partial | Live protocol sessions can list, open and persist through the server | Original remote repository/search adapters and offline query conveniences |
| AI transports | Substantial but incomplete | Native OpenAI, Codex, Anthropic, Google/Vertex, Mistral, Bedrock, Pi Messages/Radius and mock paths | Complete provider/auth/proxy/retry/diagnostic matrix |
| Authentication | Substantial but incomplete | Credential storage and multiple OAuth/device-code implementations | Enterprise/cloud credential chains and all provider UX |
| CLI/resources | Substantial | Ordered stdin/files/turns, contexts, skills, packages, templates, themes, extensions and native `pi remote` | Backend selection, remaining conflict diagnostics and lesser subcommands |
| Multimodal | Substantial core | Magic-byte images, durable replay, provider conversion and terminal image protocols | Automatic resize and exhaustive provider limits |
| RPC/protocol | Substantial | Strict protocol-v1 decoder, typed commands, sessions/models/tree/stats/bash/events and complete owned cloning | Complete optional-field and byte-level cross-language fixture matrix |
| Native client | Substantial | Framing/handshake, revision state, request correlation, leases, owned handles, acquire/create and Unix/TCP transports | DNS/proxy/TLS transports and broader reconnection policy fixtures |
| Telemetry | Substantial core | Contexts, spans, attributes, events, status, schema and deterministic memory backend | Production exporters/integration breadth |
| TUI rendering | Substantial core | Markdown, LaTeX, Kitty/iTerm2 images, Unicode-cell behavior, themes and synchronized differential painting | Every original message/dialog renderer and image-resize path |
| TUI application/input | Substantial core | Retained layout, alternate-screen lifecycle, overlays, focus, mouse, selection, search, OSC52, IME and widgets | Wire all coding-agent screens, external editor/platform details and extension-owned UI |
| Extensions | Partial/native alternative | Isolated native hooks/tools/flags/commands and scoped state | Drop-in arbitrary JS/TS extension compatibility and rich `ExtensionContext` |
| Server/MCP | Partial to substantial core | Native protocol server, persistent sessions, HTTP RPC, Unix/TCP protocol streams and MCP tools/transports | Remaining original package breadth, authorization and interoperability fixtures |
| Evals/auxiliary packages | Early to partial | Native evaluation harness and selected behavior | Most original eval and auxiliary package functionality |

## Checkpoint 143 gains over checkpoint 142

1. Allocator-directed deep cloning for every retained protocol model, transcript object, result, error and event.
2. The original remote transcript projection model with stale-revision filtering, progress overlays, tool-input accumulation and bounded compaction.
3. A high-level native `RemoteSession` with exclusive leases, replacement rollback, submit/steer selection, abort preemption, model/thinking updates, reconnect and safe disposal.
4. Lease-safe session handles plus complete attach/acquire/create workflows and cleanup reconciliation.
5. A native `pi remote` command for list, open, create, prompt, abort, model and thinking operations in text or JSON form.
6. Unix-domain and literal IPv4/IPv6 TCP client transports with absolute receive deadlines.
7. Live Unix and TCP integration against the native server, including streamed mock output and durable reopening.
8. A socket-read correction that removes a short-frame blocking hazard in both transports.
9. Protection against Zig 0.16.0's unsupported TCP-connect-timeout panic.

## Explicit non-claims

- The native remote lifecycle is not yet every original remote repository/search adapter or a full-screen remote UI.
- TCP endpoints currently accept literal IPv4/IPv6 addresses; hostname resolution, TLS and proxy tunnelling are not represented as complete.
- The SQLite package is exercised as an optional backend; the default CLI session manager has not silently changed from its JSONL tree.
- Native extension isolation is not source or binary compatibility with arbitrary upstream JavaScript/TypeScript extensions.
- Passing all native tests does not imply every original provider, package or cross-language edge case has been ported.
