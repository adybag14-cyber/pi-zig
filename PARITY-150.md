# Pi 0.84.1 → Zig checkpoint 150 parity audit

Checkpoint 150 is measured against the supplied original Pi 0.84.1 tree and exact uploaded checkpoint-149 archive. “Implemented” means executable behavior exists and was exercised; it does not imply byte-for-byte equivalence for every JavaScript, terminal or provider edge case.

| Original capability family | Checkpoint 150 status | Evidence / boundary |
|---|---|---|
| Core agent loop, tools, sessions and providers | Substantially implemented | Native loop/tool dispatch, streaming, durable trees, provider transports and complete test topology. |
| Native extension manifests | Implemented | Typed flags, hooks, tools, commands, shortcuts, providers, executable ABI and trust-gated discovery. |
| Original `.ts`/`.js` extension loading | Implemented broadly | Persistent Node 22 worker, direct/package/index discovery, TypeScript transformation, compatibility imports and retained closure state. |
| Bidirectional script UI requests | Substantial | Native select, confirm, input, editor and bounded custom requests suspend/resume handlers. Arbitrary component UI remains partial. |
| Retained extension UI actions | Substantial | Notifications, status, widgets, header/footer, title, editor mutation, working indicator and thinking labels. |
| Script session manager/context | Substantial | Owned header/entry/branch/leaf snapshots, labels, tree, paths, cwd, model and tool registries. |
| Ordered lifecycle/tool/command side effects | Implemented broadly | Canonical FIFO actions, worker-safe ownership and deterministic safe-point application. |
| Startup command replay | Implemented | Side-effect-free preflight, one replay after live provider initialization and consumed-prompt removal. |
| Agent-end/shutdown lifecycle | Implemented | `agent_end` continuation, final shutdown drain, authoritative stop policy and force-reaped script workers. |
| Declarative provider registration | Substantial | Runtime register/unregister, custom models, live catalog/client replacement and same-batch switching. Function callbacks/OAuth remain partial. |
| Script tools/commands/flags/shortcuts | Implemented broadly | Registration, schemas, execution modes, persistent state, live filtering and editor-first shortcuts. |
| Extension `prepareArguments()` | Implemented | Script preparation precedes schema validation/execution; transformed ownership and failure isolation are native. |
| Extension-owned built-in replacement | Implemented | Same-name schemas and execution replace built-ins, while explicit `create*Tool()` delegation safely returns to native Zig. |
| Custom message/entry/Markdown renderers | Substantial | Persistent renderer invocation and native terminal projection; arbitrary component trees and streaming transforms remain partial. |
| Extension tool renderers | Substantial | Stateful call/result context, canonical single rendering, partial state, images and details. Asynchronous invalidation remains partial. |
| Rich extension tool updates | Substantial | Ordered text/image/details/error updates reach JSON, print, TUI and protocol. Worker delivery is currently batched at promise completion. |
| Rich `tool_result` hooks | Implemented for current native model | Text, first image, details, error and termination replacement survive allocator boundaries and persistence. Multiple images remain partial. |
| Extension tool ownership | Implemented | Host outputs, updates and actions cross allocator/thread boundaries safely. |
| Original extension corpus registration | Substantial, retained | Checkpoint-146 probe loaded 74/78 supplied entries; four require absent external npm dependencies. |
| JSONL/session compatibility and administration | Implemented broadly | Migration, atomic save, discovery, search/show/doctor/stats/tree/rename/delete/migrate and fork provenance. |
| HTTP(S) proxy and secure remote transport | Implemented for primary paths | Target-aware proxying, NO_PROXY, verified remote TLS and CONNECT; server TLS/mTLS and every bootstrap path remain. |
| Canonical/live SQLite persistence | Implemented | Repository, FTS, writer leases, administration companion and optional live protocol server. |
| Retained native TUI primitives | Substantially implemented | Alternate screen, layout, overlays, mouse, IME, Unicode cells, Markdown/LaTeX/images/widgets and extension shell state. Full screen wiring remains. |
| Multimodal input/rendering | Partial to substantial | Binary-safe attachments, provider conversion, dimensions, terminal image protocols and rich tool images; resizing/transcoding remains. |
| Enterprise auth/retry matrix | Partial | Many native paths exist; complete bootstrap proxying, credential sources, diagnostics and retries remain. |
| Auxiliary client/server/eval packages | Partial | Major protocol/client/server/eval behavior is native; broader cross-language and byte-exact coverage remains. |

## Validation closure

```text
Native Zig files:                         170
Native Zig logical lines:                 84,735
Embedded JS bridge lines:                    865
Synthetic feature files:                      0
Source-level test declarations:              778
All-package root:                         760 pass / 7 isolated / 0 fail
Dedicated SQLite repository:              11/11
Dedicated SQLite live adapter:             5/5
SQLite CLI process:                        8 active / 6 isolated / 0 fail
Executable suites:                         5/5 ordinary + 5/5 SQLite-enabled
Debug builds:                              pi, pi-sqlite, pi-sqlite-live PASS
Original replacement/delegation E2E:       PASS
Rich preparation/update/hook E2E:          PASS
```

## Remaining highest-value gaps

1. True live cross-process extension updates and multiple-image result fidelity.
2. Fully arbitrary extension component trees, overlays and asynchronous invalidation.
3. Function-valued providers, custom streams and extension-owned OAuth/login callbacks.
4. Extension dependency installation beyond the validated Node 22 TypeScript/ESM boundary.
5. Complete original coding-agent selector, model, login, settings and session screens.
6. Native server TLS/mTLS, image normalization and complete provider-specific multimodal validation.
7. Complete enterprise credential/retry behavior and broader interoperability fixtures.
