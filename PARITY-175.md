# Pi 0.84.1 → Zig checkpoint 175 parity audit

## Closed in checkpoint 175

| Original behavior | Zig checkpoint 175 status |
|---|---|
| Configurable `app.clipboard.pasteImage` action | Native typed keybinding with legacy `pasteImage` compatibility |
| Ctrl+V image paste on Linux/macOS | Implemented; Windows default remains Alt+V as upstream |
| Clipboard text fallback when no image exists | Implemented in the same running editor |
| Wayland image MIME discovery | Implemented through bounded `wl-paste --list-types` and selected reads |
| X11 image and text clipboard | Implemented through `xclip`, with `xsel` text fallback |
| WSL image clipboard | Implemented through PowerShell PNG save and `wslpath` |
| macOS image clipboard | Implemented through `pngpaste` with AppleScript PNG fallback |
| macOS text clipboard | Implemented through `pbpaste` |
| Windows image/text clipboard | Implemented through PowerShell clipboard APIs |
| Termux graceful fallback | Image probing skipped; `termux-clipboard-get` text fallback retained |
| Clipboard image enters normal image pipeline | Implemented through a private temporary `@file` attachment |
| Durable image session history | Exact base64 and MIME survive JSONL persistence |
| Temporary attachment cleanup | Deterministic on normal interactive shutdown |
| Extension shortcut precedence | Retained before the built-in clipboard action |
| Clipboard text hygiene | Shares bracketed-paste CRLF/tab/control normalization |
| Real interactive verification | PTY image then text workflow passes with zero stderr |

## Qualified differences

- Platform image reads use available command-line or PowerShell/AppleScript adapters rather than the original native clipboard addon.
- Clipboard image commands are bounded and fail softly, but live native GUI clipboard APIs are not exercised on every target OS inside this Linux validation container.
- Temporary files are removed on normal shutdown; an uncatchable process termination may leave a private temporary file for ordinary system cleanup.
- `/copy` still lacks the original complete native write plus OSC 52 fallback and remains a separate parity gap.
- Right-click text paste and native fullscreen mouse paste are not yet implemented.

## Validation evidence

```text
Zig:                                      0.16.0
Native Zig files under src/:              188
Native Zig logical lines:                 112,569
Named Zig test declarations:              961
Synthetic source files:                   0
Clipboard/import filter:                  22/22 passed
Line-editor/import filter:                 23/23 passed
Keybinding/import filter:                  18/18 passed
Self-hosted Debug executable:              built and PTY-tested
LLVM static Debug executable:              built and PTY-tested
SQLite administration executable:         built and integrity-tested
Cold direct aggregate compilation:         deadline exceeded, no diagnostic
```
