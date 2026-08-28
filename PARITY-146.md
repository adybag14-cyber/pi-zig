# Pi 0.84.1 → Zig checkpoint 146 parity audit

Checkpoint 146 is measured against the supplied original Pi 0.84.1 tree and exact uploaded checkpoint-145 archive. “Implemented” means executable behavior exists and was tested; it does not imply every original JavaScript, terminal or provider edge case is equivalent.

| Original capability family | Checkpoint 146 status | Evidence / boundary |
|---|---|---|
| Core agent loop, tools, sessions and providers | Substantially implemented | Native loop/tool dispatch, streaming, durable session trees, provider transports and full root graph. |
| Native extension manifests | Implemented | Typed flags, hooks, tools, commands, shortcuts, isolated executable ABI and trust-gated discovery. |
| Original `.ts`/`.js` extension loading | Implemented broadly | Persistent Node 22 worker, direct/package/index entries, current/legacy Pi import shims, TypeScript transformation and retained closure state. |
| Script hooks and lifecycle | Implemented broadly | Canonical agent/turn/message/tool events plus input/tool aliases, serialized invocation, limits and error isolation. |
| `before_agent_start` | Implemented | Full assembled-system-prompt replacement, images/cwd/prompt payload and durable hidden custom context messages. |
| Per-request `context` hook | Implemented | Filter/reorder/inject without durable-history mutation; native assistant/tool/thinking/image metadata preserved for projected messages. |
| Script tools/commands/flags/shortcuts | Implemented broadly | Registration, schema conversion, execution modes, raw arguments, defaults/overrides, persistent state and editor-first shortcut dispatch. |
| Script extension action context | Partial to substantial | Notifications/messages, prompt handoff, session naming and termination work; interactive dialog/UI/provider methods remain partial or inert. |
| Original extension corpus registration | Substantial | 74/78 supplied entries register. Four require external npm packages absent from the supplied snapshot; no bridge/import-parser failures remain. |
| Extension-owned TUI/rendering APIs | Partial | Compatibility exports permit module registration; full interactive overlays/editors/widgets/renderers are not yet wired to the native shell. |
| Provider registration/OAuth from extensions | Partial | API shapes exist for import compatibility, but dynamic provider lifecycle and interactive auth are not complete. |
| JSONL/session compatibility and administration | Implemented broadly | v1/v2/v3 migration, atomic saves, discovery, search/show/doctor/stats/tree/rename/delete/migrate and fork provenance. |
| HTTP(S) proxy and secure remote transport | Implemented for primary paths | Target-aware provider proxying, NO_PROXY, verified remote TLS and CONNECT; server TLS/mTLS and every bootstrap helper remain. |
| Canonical/live SQLite persistence | Implemented | Repository, FTS, writer leases, administration companion and optional live protocol server with restart recovery. |
| Retained native TUI primitives | Substantially implemented | Alternate screen, layout, overlays, mouse, IME, Unicode cells, Markdown/LaTeX/images/widgets. Full original screen wiring remains. |
| Multimodal input/rendering | Partial to substantial | Binary-safe attachments, provider conversion, image dimensions and terminal protocols; automatic resizing/transcoding remains. |
| Enterprise auth/retry matrix | Partial | Many native credential paths exist; complete bootstrap proxying, sources, diagnostics and retries remain. |
| Auxiliary client/server/eval packages | Partial | Major protocol/client/server/eval behavior is native; broader cross-language and byte-exact coverage remains. |

## Validation closure

```text
Native Zig files:                       167
Native Zig logical lines:               79,230
Embedded JS bridge lines:               358
Zig test declarations:                    754
Synthetic feature files:                0
All-package root:                       737 pass / 7 isolated / 0 fail
Dedicated SQLite repository:            11/11
Dedicated SQLite live adapter:          5/5
SQLite CLI process:                     8 active / 6 isolated / 0 fail
Executable/main suite:                  4/4
Debug builds:                           pi, pi-sqlite, pi-sqlite-live PASS
Original extension corpus registration: 74/78; 4 absent npm dependencies
```

## Remaining highest-value gaps

1. Connect extension-owned overlays, dialogs, custom editors, renderers, headers, footers and widgets to the retained native application shell.
2. Implement complete script-side provider registration, dynamic models, OAuth/login and reload semantics.
3. Expand compatibility beyond the validated Node 22/TypeScript boundary and support extension-managed dependency installation workflows.
4. Wire every original coding-agent selector, model/login/session/tree and configuration screen.
5. Add native server-side TLS/mTLS.
6. Add automatic image normalization and complete provider-specific multimodal validation.
7. Route every OAuth/cloud bootstrap request through proxy policy and complete enterprise credential/retry behavior.
8. Expand remote repository adapters and cross-language interoperability fixtures.
