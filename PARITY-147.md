# Pi 0.84.1 → Zig checkpoint 147 parity audit

Checkpoint 147 is measured against the supplied original Pi 0.84.1 tree and the
exact uploaded checkpoint-146 archive. “Implemented” means native executable
behavior exists and was exercised; it does not imply byte-for-byte equivalence
for every JavaScript, terminal or provider edge case.

| Original capability family | Checkpoint 147 status | Evidence / boundary |
|---|---|---|
| Core agent loop, tools, sessions and providers | Substantially implemented | Native loop/tool dispatch, streaming, durable trees, provider transports and the complete test graph. |
| Native extension manifests | Implemented | Typed flags, hooks, tools, commands, shortcuts, executable ABI and trust-gated discovery. |
| Original `.ts`/`.js` extension loading | Implemented broadly | Persistent Node 22 worker, direct/package/index discovery, TypeScript transformation, compatibility imports and retained closure state. |
| Bidirectional script UI requests | Substantial | Native select, confirm, input, multiline editor and bounded custom requests can suspend/resume async extension handlers. Arbitrary extension components remain partial. |
| Retained extension UI actions | Substantial | Notifications, status, widgets, header/footer, title, editor mutation, working indicator and thinking label are applied by the native shell. |
| Script session manager/context | Substantial | Owned header/entry/branch/leaf snapshots, labels, tree, paths, cwd, model registry and tool registry. Compaction-aware context projection remains less exact than upstream. |
| Script runtime actions | Substantial for commands/shortcuts | Names, entries, labels, model, thinking and active tools update native state and durable sessions. General ordered side effects from every hook path remain incomplete. |
| Script hooks and lifecycle | Implemented broadly | Canonical agent/turn/message/tool events, transformations, limits and error isolation. |
| Script tools/commands/flags/shortcuts | Implemented broadly | Registration, schemas, execution modes, persistent state, live tool filtering and editor-first shortcut dispatch. |
| Extension tool ownership | Implemented | Host output is cloned into caller ownership; parallel tool E2E terminates without DebugAllocator leaks. |
| Original extension corpus registration | Substantial, retained | Checkpoint-146 registration probe loaded 74/78 supplied entries; four require absent external npm dependencies. UI/action changes preserve this resolver but the full corpus was not used as a behavioral UI suite. |
| Extension custom renderers/components | Partial | Compatibility objects permit registration/import; arbitrary component rendering and custom message/tool renderers are not native-equivalent. |
| Provider registration/OAuth from extensions | Partial | Registry API shapes exist, but dynamic native provider lifecycle, auth and reload are incomplete. |
| JSONL/session compatibility and administration | Implemented broadly | Migration, atomic save, discovery, search/show/doctor/stats/tree/rename/delete/migrate and fork provenance. |
| HTTP(S) proxy and secure remote transport | Implemented for primary paths | Target-aware proxying, NO_PROXY, verified remote TLS and CONNECT; server TLS/mTLS and every bootstrap helper remain. |
| Canonical/live SQLite persistence | Implemented | Repository, FTS, writer leases, administration companion and optional live protocol server. |
| Retained native TUI primitives | Substantially implemented | Alternate screen, layout, overlays, mouse, IME, Unicode cells, Markdown/LaTeX/images/widgets plus extension-driven shell state. Full original screen wiring remains. |
| Multimodal input/rendering | Partial to substantial | Binary-safe attachments, provider conversion, image dimensions and terminal protocols; automatic resizing/transcoding remains. |
| Enterprise auth/retry matrix | Partial | Many native paths exist; complete bootstrap proxying, credential sources, diagnostics and retries remain. |
| Auxiliary client/server/eval packages | Partial | Major protocol/client/server/eval behavior is native; broader cross-language and byte-exact coverage remains. |

## Validation closure

```text
Native Zig files:                         168
Native Zig logical lines:                 81,047
Embedded JS bridge lines:                    602
Zig test declarations:                       758
Synthetic feature files:                      0
All-package root:                         741 pass / 7 isolated / 0 fail
Dedicated SQLite repository:              11/11
Dedicated SQLite live adapter:             5/5
SQLite CLI process:                        8 active / 6 isolated / 0 fail
Executable suites:                         4/4 ordinary + 4/4 SQLite-enabled
Debug builds:                              pi, pi-sqlite, pi-sqlite-live PASS
Extension UI/actions/tools E2E:            PASS
```

## Remaining highest-value gaps

1. Native-equivalent arbitrary extension components, overlays and custom
   renderers.
2. A general ordered action queue for side effects returned by every hook and
   tool lifecycle callback.
3. Complete extension provider registration, OAuth/login, dynamic models and
   reload semantics.
4. Extension dependency installation and compatibility beyond the validated
   Node 22 TypeScript/ESM boundary.
5. Complete original coding-agent selector, model, login, session and settings
   screens.
6. Native server TLS/mTLS, image normalization and complete provider-specific
   multimodal validation.
7. Complete enterprise credential/retry behavior and broader interoperability
   fixtures.
