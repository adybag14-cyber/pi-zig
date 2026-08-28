# Pi 0.84.1 → native Zig parity audit — checkpoint 172

## Closed in checkpoint 172

| Original surface | Native Zig checkpoint 172 |
|---|---|
| `terminal.showImages` | Parsed, merged, atomically persisted, fullscreen-editable, live-reloadable, and applied to native plus extension rendering. |
| `terminal.imageWidthCells` | Parsed and persisted in canonical nested form; applied to native inline image sizing with original default 60. |
| `images.blockImages` | Enforced after extension context transforms at the final provider boundary; ordered and legacy images stripped while durable history remains intact. |
| Blocked-image placeholder | Original `Image reading is disabled.` marker inserted for user/tool image-only content. |
| `enableSkillCommands` | Controls slash execution, help, completion, RPC discovery, and live reload while leaving resource/context loading independent. |
| Original legacy settings compatibility | Snake-case forms and historical nested `skills.enableSkillCommands` accepted; canonical form written back. |
| Settings UI | Four new controls integrated into the retained `/settings` selector with atomic verified persistence. |
| Provider privacy E2E | Real provider request proves blocked images do not leave the process and allowed images still do. |
| Durable multimodal history | Exact image MIME/base64 retained in JSONL regardless of provider-blocking policy. |

## Important implementation boundaries

- `showImages` is a presentation policy; it does not remove images from provider context.
- `blockImages` is an outbound privacy policy; it does not destroy or rewrite append-only history.
- Privacy filtering occurs after extension transforms so script extensions cannot bypass it.
- Allocation failure during privacy projection is an error rather than a fallback to sending images.
- `enableSkillCommands` controls command registration only; skill files may still contribute project context when selected.

## Validation status

```text
Agent/AI tests:                            333/333 passed
Changed coding-agent/settings/TUI tests:   649/649 passed
SQLite repository:                         11/11 passed
SQLite CLI/schema:                          8 passed, 6 intentional isolates
Ordinary executable:                       10/10 passed
Real media/skill E2E:                      passed, zero stderr
Static pi build:                           passed
pi-sqlite build:                           passed
```

The aggregate root artifact and SQLite-live companion exceeded cold Zig 0.16.0 compile deadlines without emitting a source failure. They are recorded as unobserved for this checkpoint, not reported as passing or failing.

## Largest remaining gaps

1. Remaining original settings and project-scope override editing.
2. Automatic image resize, rotation normalization, transcoding, and provider-limit enforcement.
3. Fullscreen package/account/login administration.
4. Complete package-manager platform and lifecycle behavior.
5. Arbitrary asynchronously invalidated extension component trees.
6. Function-valued extension providers and extension-owned OAuth.
7. Native server TLS/mTLS.
8. Remaining enterprise credential, telemetry, update, retry, and interoperability breadth.
