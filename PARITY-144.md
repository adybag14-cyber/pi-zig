# Original Pi 0.84.1 versus native Zig checkpoint 144

## Reference

The parity reference is the uploaded `pi-main (3)(4).zip`, SHA-256 `42162e1ea09cfaf78ec737862255b919789eef7defd73f413dbb58c8dee0aa1a`. The rewrite baseline is the uploaded checkpoint-143 archive, SHA-256 `b42337ef2cbc859de2f91683235a3fed0b560c7698f3d4c3f8b24cf274e363f3`. Status is based on implemented behavior and executable tests, not matching names or manufactured line count.

## Status by subsystem

| Subsystem | Checkpoint 144 status | Native evidence | Principal remaining work |
|---|---|---|---|
| Build/runtime | Substantial | Zig 0.16.0 Debug `pi`, optional separately linked `pi-sqlite`, no Node runtime | Cross-platform release/package matrix |
| Agent loop/tools | Substantial | Multi-turn tools, cancellation, queues, compaction, hooks and built-ins | Specialized edge cases and exhaustive fixtures |
| JSONL sessions/history | Substantial | Durable tree, exact resume/fork behavior, branch-aware list/search/show/doctor | Complete custom-entry rendering and migration tooling |
| SQLite backend | Substantial, production-accessible | Canonical schema, entries/branches/lanes/records/facts/stats/leases/FTS/forks plus `pi-sqlite` | Select as live agent/server store and broaden migrations |
| Remote live sessions | Substantial core | Owned snapshots, leases, lifecycle, reconnect, Unix/TCP commands | Rich fullscreen remote UI and exhaustive races |
| Remote repositories/search | Partial to substantial | Client-side protocol snapshot search with session/role/case filters | Original remote repository/offline adapters and server-side indexes |
| Network transports | Substantial core | Unix, literal IP and DNS-hostname TCP; IPv4/IPv6 server binds; deadlines | TLS, proxies, DNS policy and certificate controls |
| HTTP compatibility/security | Substantial diagnostic path | Strict bearer header, timing-safe comparison, exact routes, complete body framing | Full HTTP server semantics are intentionally out of scope |
| AI transports | Substantial but incomplete | Native OpenAI/Codex/Anthropic/Google/Vertex/Mistral/Bedrock/Pi Messages/mock | Complete provider/auth/proxy/retry matrix |
| Authentication | Substantial but incomplete | Credential storage and several OAuth/device-code paths | Enterprise/cloud credential chains and all login UX |
| CLI/resources | Substantial | Contexts, skills, packages, templates, themes, local/remote/SQLite session commands | Remaining conflict diagnostics and lesser original commands |
| Multimodal | Substantial core | Magic-byte images, durable replay, provider conversion, terminal protocols | Automatic resize and exhaustive provider limits |
| RPC/protocol | Substantial | Strict protocol v1, typed commands, complete owned cloning | Cross-language byte fixtures and remaining optional fields |
| Native client | Substantial | Framing, state reduction, correlation, leases, handles, Unix/TCP and snapshot search | TLS/proxy policy and broader reconnect fixtures |
| Telemetry | Substantial core | Contexts, spans, attributes/events/status and memory backend | Production exporters |
| TUI rendering/application | Substantial core | Markdown/LaTeX/images/Unicode/layout/overlays/mouse/search/IME/widgets | Wire every original coding-agent screen and extension UI |
| Extensions | Partial native alternative | Native hooks/tools/flags/commands and scoped state | Drop-in arbitrary JS/TS extension compatibility |
| Server/MCP | Partial to substantial | Protocol server, durable sessions, hardened HTTP diagnostic path and MCP | Remaining original package breadth and auth/interoperability |
| Evals/auxiliary packages | Early to partial | Native harness and selected behavior | Most original evaluation and auxiliary packages |

## Checkpoint 144 gains over checkpoint 143

1. Storage-neutral, branch-aware JSONL session search with owned ranked hits and malformed-file isolation.
2. Production `pi sessions list/search/show/doctor` commands in text and JSON modes.
3. Client-side protocol-snapshot search and `pi remote search` without changing protocol v1.
4. DNS hostname support for TCP clients and numeric IPv6 server binding.
5. Strict bearer-header authentication with duplicate/folding rejection and timing-safe comparison.
6. Complete and unambiguous HTTP Content-Length framing with bounded bodies and exact routes.
7. Optional production `pi-sqlite` build and administration command surface.
8. SQLite FTS snippets, metadata/stats/lane inspection and integrity/schema doctor checks.
9. UTF-8-safe local session compact rendering and search snippets.
10. Eighteen additional native test declarations across the new behavior.

## Explicit non-claims

- The SQLite repository is production-accessible but is not yet the selectable live store for every agent/server path.
- Snapshot search does not represent every original remote repository or offline indexing adapter.
- DNS TCP support is not TLS or proxy support.
- Diagnostic HTTP hardening does not turn the binary protocol into an authenticated/TLS protocol.
- Native extension isolation is not source or binary compatibility with arbitrary upstream JavaScript/TypeScript extensions.
- The cold aggregate root test compilation timed out; successful focused and executable gates are reported separately.
