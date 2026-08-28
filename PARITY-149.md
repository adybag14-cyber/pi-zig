# Pi 0.84.1 → Zig checkpoint 149 parity audit

Checkpoint 149 is measured against the supplied original Pi 0.84.1 tree and exact uploaded checkpoint-148 archive. “Implemented” means executable behavior exists and was exercised; it does not imply byte-for-byte equivalence for every JavaScript, terminal or provider edge case.

| Original capability family | Checkpoint 149 status | Evidence / boundary |
|---|---|---|
| Core agent loop, tools, sessions and providers | Substantially implemented | Native loop/tool dispatch, streaming, durable trees, provider transports and complete test graph. |
| Native extension manifests | Implemented | Typed flags, hooks, tools, commands, shortcuts, providers, executable ABI and trust-gated discovery. |
| Original `.ts`/`.js` extension loading | Implemented broadly | Persistent Node 22 worker, direct/package/index discovery, TypeScript transformation, compatibility imports and retained closure state. |
| Bidirectional script UI requests | Substantial | Native select, confirm, input, editor and bounded custom requests suspend/resume handlers. Arbitrary component UI remains partial. |
| Retained extension UI actions | Substantial | Notifications, status, widgets, header/footer, title, editor mutation, working indicator and thinking labels. |
| Script session manager/context | Substantial | Owned header/entry/branch/leaf snapshots, labels, tree, paths, cwd, model and tool registries. |
| Ordered lifecycle/tool side effects | Implemented broadly | Canonical records, monotonic FIFO, worker-safe ownership and safe-point application. |
| Ordered command/shortcut actions | Substantial | Canonical script API calls preserve order in startup, interactive, print and RPC paths; return-object-only legacy fields remain a fallback. |
| Startup command replay | Implemented | Side-effect-free preflight, one replay after live provider initialization, consumed-prompt removal and durable early-stop actions. |
| Agent-end/shutdown lifecycle | Implemented | `agent_end` continuation, final shutdown drain and authoritative stop policy. |
| Declarative provider registration | Substantial | Runtime register/unregister, custom models, live catalog/client replacement and same-batch model switching. Function callbacks/OAuth remain partial. |
| Script hooks and lifecycle | Implemented broadly | Canonical agent/turn/message/tool events, transformations, limits, ordered actions and error isolation. |
| Script tools/commands/flags/shortcuts | Implemented broadly | Registration, schemas, execution modes, persistent state, live filtering and editor-first shortcuts. |
| Custom message renderers | Implemented for terminal projection | Persistent renderer invocation, theme/component compatibility, immediate TUI output and durable JSONL persistence. Arbitrary components remain partial. |
| Durable entry renderers | Implemented for terminal projection | Canonical entry object, original custom type dispatch and immediate TUI rendering. Transcript replay screens remain partial. |
| Markdown transformers | Substantial | Ordered transformer chain before final native assistant Markdown render; streaming-delta transformation is not complete. |
| Extension tool renderers | Substantial | Stateful call/result renderer context, one canonical render per tool execution and native fallback. Complete details/images/partial updates remain. |
| Built-in tool renderer overrides | Implemented safely | Original renderer-only re-registration works while native Zig schemas/execution remain authoritative. Executable replacement remains partial. |
| Extension tool ownership | Implemented | Host output/actions cross allocator and thread boundaries safely. |
| Original extension corpus registration | Substantial, retained | Checkpoint-146 probe loaded 74/78 supplied entries; four require absent external npm dependencies. |
| JSONL/session compatibility and administration | Implemented broadly | Migration, atomic save, discovery, search/show/doctor/stats/tree/rename/delete/migrate and fork provenance. |
| HTTP(S) proxy and secure remote transport | Implemented for primary paths | Target-aware proxying, NO_PROXY, verified remote TLS and CONNECT; server TLS/mTLS and every bootstrap path remain. |
| Canonical/live SQLite persistence | Implemented | Repository, FTS, writer leases, administration companion and optional live protocol server. |
| Retained native TUI primitives | Substantially implemented | Alternate screen, layout, overlays, mouse, IME, Unicode cells, Markdown/LaTeX/images/widgets plus extension shell state. Full screen wiring remains. |
| Multimodal input/rendering | Partial to substantial | Binary-safe attachments, provider conversion, dimensions and terminal image protocols; automatic resizing/transcoding remains. |
| Enterprise auth/retry matrix | Partial | Many native paths exist; complete bootstrap proxying, credential sources, diagnostics and retries remain. |
| Auxiliary client/server/eval packages | Partial | Major protocol/client/server/eval behavior is native; broader cross-language and byte-exact coverage remains. |

## Validation closure

```text
Native Zig files:                         170
Native Zig logical lines:                 83,452
Embedded JS bridge lines:                    775
Synthetic feature files:                      0
All-package root:                         750 pass / 7 isolated / 0 fail
Dedicated SQLite repository:              11/11
Dedicated SQLite live adapter:             5/5
SQLite CLI process:                        8 active / 6 isolated / 0 fail
Executable suites:                         5/5 ordinary + 5/5 SQLite-enabled
Debug builds:                              pi, pi-sqlite, pi-sqlite-live PASS
Renderer/order/original-extension E2E:     PASS
```

## Remaining highest-value gaps

1. Fully arbitrary extension components, overlays, asynchronous invalidation and transcript replay renderers.
2. Complete renderer details/images/partial updates/expanded-state fidelity.
3. Executable built-in tool replacement, function-valued providers and extension-owned OAuth/login callbacks.
4. Extension dependency installation and compatibility beyond the validated Node 22 TypeScript/ESM boundary.
5. Complete original coding-agent selector, model, login, settings and session screens.
6. Native server TLS/mTLS, image normalization and complete provider-specific multimodal validation.
7. Complete enterprise credential/retry behavior and broader interoperability fixtures.
