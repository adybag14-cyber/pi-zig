# Pi 0.84.1 → native Zig parity audit — checkpoint 173

## Closed in checkpoint 173

| Original surface | Native Zig checkpoint 173 |
|---|---|
| Main `/settings` inventory | Native typed representation and retained selector entries for the original compaction, retry, provider, transport, display, media, editor, Markdown, warning, TUI, lifecycle and trust controls. |
| Global/project scopes | Tab switches between global and trusted-project configuration; project scope excludes global-only telemetry and trust policy. |
| Effective-value visualization | Project rows distinguish explicit values from `inherit → effective value`. |
| Project override removal | Backspace/Delete atomically removes the selected project value and prunes empty nested objects. |
| Atomic persistence | Global and project edits share the advisory configuration lock, atomic replacement, fsync and parse/read-back verification. |
| Legacy compatibility | Camel-case and snake-case settings are accepted; canonical original forms are written. |
| Explicit default override | Project `maxTurns:16` correctly overrides a global non-default value. |
| Selector identity | Search clearing and reload preserve the selected setting by enum identity, preventing row-index mutation errors. |
| Terminal progress | Live OSC 9;4 start/clear sequences follow the merged setting. |
| Editor/output padding | Live reload updates prompt indentation and native assistant Markdown padding. |
| Settings-driven TUI startup | Trusted project `tuiMode` selects fullscreen on a fresh process when no CLI override exists. |

## Parsed, editable, and reloadable in checkpoint 173

The native model now includes:

```text
hideThinkingBlock
showCacheMissNotices
doubleEscapeAction
terminal.clearOnShrink
terminal.showTerminalProgress
images.autoResize
editorPaddingX
outputPad
autocompleteMaxVisible
showHardwareCursor
markdown.mermaid
warnings.anthropicExtraUsage
tuiMode
fullscreenExitOutput
fullscreenScrollbar
```

These settings merge independently between global and trusted project files and persist in canonical nested form. Controls whose complete behavior depends on the original retained transcript/editor implementation remain explicitly listed below rather than being overstated as complete.

## Validation status

```text
Focused settings/TUI/import graph:          165/165 passed
Global settings real PTY:                   passed, zero stderr
Project/global settings real PTY:           passed, zero stderr
Ordinary executable tests observed:         10/10 passed
SQLite repository:                          11/11 passed
SQLite CLI/schema:                           8 passed, 6 intentional isolates
Static pi Debug build:                      passed
pi-sqlite Debug build:                      passed
SQLite integrity:                           ok
```

The aggregate root/module artifacts and SQLite-live companion exceeded cold Zig 0.16.0 compile deadlines. No failure was emitted, but no pass or binary is claimed.

## Largest remaining gaps

1. Complete retained-shell behavior for clear-on-shrink, autocomplete rows, scrollbar, dynamic TUI switching, exit transcript/hint, cache notices, Mermaid, and thinking presentation.
2. Automatic light/dark theme selection and preview.
3. Image resize/orientation/transcoding.
4. Fullscreen package and account/login administration.
5. Complete package-manager behavior on all supported platforms.
6. Asynchronously invalidated extension component trees.
7. Function-valued providers and extension-owned OAuth.
8. Native server TLS/mTLS.
9. Enterprise credential, telemetry, update, retry and interoperability breadth.
