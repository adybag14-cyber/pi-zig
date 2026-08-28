# Pi 0.84.1 → Zig checkpoint 145 parity audit

Checkpoint 145 is measured against the supplied original Pi 0.84.1 tree and the exact uploaded checkpoint-144 archive. “Implemented” means executable native behavior exists and is tested; it does not mean every original edge case is already equivalent.

| Original capability family | Checkpoint 145 status | Evidence / boundary |
|---|---|---|
| Core agent loop, tools, sessions and providers | Substantially implemented | Native loop/tool dispatch, streaming, durable JSONL trees, provider-specific transports and full root test graph. Remaining edge cases are listed below. |
| JSONL v1/v2/v3 compatibility | Implemented | Deterministic v1 tree migration, compaction index conversion, v2 role migration, atomic rewrite and live CLI migration. |
| Session discovery/administration | Implemented broadly | List/search/show/doctor plus stats/tree/rename/guarded delete/migrate; complete-tree names and billing-aware statistics. |
| Original session directory layout | Implemented | Human-readable cwd encoding plus automatic recovery of pre-145 hashed paths and misplaced root sessions. |
| Original one-time startup migrations | Implemented broadly | Auth/settings, keybindings, commands→prompts, managed binaries, sessions and deprecated-layout warnings; atomic/no-clobber behavior. |
| HTTP(S) proxy policy | Implemented for primary model/image transports | Protocol env precedence, ALL_PROXY, NO_PROXY, global `httpProxy`, auth, CONNECT/TLS; OAuth/cloud credential bootstrap remains incomplete. |
| Persistent Codex WebSocket proxying | Implemented | Proxy storage survives the cached socket lifetime and follows target-aware routing. |
| Remote client TCP/Unix/DNS/IPv6 | Implemented | Native framed protocol, leases, high-level sessions, search and remote CLI. |
| Remote target TLS and CONNECT proxying | Implemented client-side | Certificate-verified TLS, HTTP/HTTPS CONNECT, nested target TLS and deadlines. Native server TLS/mTLS remains. |
| Canonical SQLite repository | Implemented | Schema, branches, lanes, facts, records, FTS, stats, forks and writer leases. |
| Live SQLite protocol-server persistence | Implemented in optional companion | `pi-sqlite-live`, startup restore, snapshots, renewable leases, idempotent JSON import and restart transcript recovery. |
| Ordinary self-contained executable | Implemented | Static Linux x86-64 `pi`; SQLite remains optional in companion binaries. |
| Retained TUI primitives | Substantially implemented | Alternate screen, layout, overlays, mouse, IME, Unicode cells, Markdown/LaTeX/images/widgets. Full original screen wiring remains. |
| Extension manifests and native command surface | Partial | Typed manifests and native commands exist; arbitrary JS/TS extension execution is not implemented. |
| Multimodal input/rendering | Partial to substantial | Binary-safe attachments, image MIME/dimensions, terminal protocols and provider conversion. Automatic resizing/transcoding and all provider limits remain. |
| Enterprise auth/proxy/retry matrix | Partial | Many native OAuth/cloud chains exist; complete credential bootstrap proxying and every enterprise edge case remain. |
| Auxiliary client/server/eval packages | Partial | Major protocol/client/server/eval behavior is native; broader cross-language and byte-for-byte fixture coverage remains. |

## Validation closure

```text
Native Zig files:                       166
Native Zig lines:                       77,510
Unique declared tests:                  740
Synthetic feature files:                0
All unique declarations executed:       PASS
All-package root:                       723 pass / 7 isolated / 0 fail
Dedicated SQLite repository:            11/11
Dedicated SQLite live adapter:          5/5
SQLite CLI process:                     8 active / 6 isolated / 0 fail
Executable/main suite:                  4/4
Debug builds:                           pi, pi-sqlite, pi-sqlite-live PASS
Live proxy/CONNECT/migration/admin/DB:  PASS
Exact source-ZIP full validation:          PASS
Exact 144→145 patch reconstruction/tests: PASS
```

## Remaining highest-value gaps

1. Execute arbitrary upstream JavaScript/TypeScript extensions with compatible hooks, UI ownership and lifecycle semantics.
2. Wire every original coding-agent modal, selector, tree, model/login/session dialog and extension-owned UI onto the retained native shell.
3. Add native server-side TLS/mTLS configuration rather than relying on a trusted TLS terminator.
4. Route all OAuth, AWS/GCP metadata and management/bootstrap requests through the same target-aware proxy policy.
5. Add automatic image resizing/transcoding and complete provider-specific multimodal validation.
6. Complete enterprise credential sources, retry/error classification and provider diagnostics.
7. Expand remote repository adapters, auxiliary package breadth and cross-language byte-level fixtures.
