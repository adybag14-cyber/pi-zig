# Pi Zig checkpoint 175 — native clipboard image and text paste

Checkpoint 175 continues from checkpoint 174 and the supplied original Pi 0.84.1 source using Zig 0.16.0. It closes the missing interactive clipboard-paste path across the native line editor, image attachment pipeline, platform clipboard adapters, configurable keybindings, durable sessions, and clean shutdown.

## Native clipboard subsystem

The new `src/coding_agent/clipboard.zig` provides bounded, allocator-owned clipboard acquisition for:

- Linux Wayland through `wl-paste` MIME discovery and reads;
- Linux X11 through `xclip`, with `xsel` text fallback;
- WSL image extraction through PowerShell and `wslpath`;
- macOS image extraction through `pngpaste` or AppleScript and text through `pbpaste`;
- Windows image and text reads through PowerShell;
- Termux text fallback through `termux-clipboard-get`, while deliberately skipping unsupported image probing.

Clipboard image bytes are validated by the existing magic-byte image inspector rather than trusting the MIME advertised by a desktop clipboard. Command stdout, stderr, and execution duration are bounded. Missing tools, empty clipboards, invalid images, invalid UTF-8, and unsupported platform paths fail softly without terminating the editor.

## Interactive editor integration

The upstream keybinding is now part of the typed native registry:

```text
app.clipboard.pasteImage
legacy name: pasteImage
Linux/macOS default: Ctrl+V
Windows default: Alt+V
```

User keybinding configuration can replace the default. Original JavaScript/TypeScript extension shortcuts retain first refusal over the built-in clipboard action.

The shortcut callback contract now distinguishes:

```text
not handled
handled and continue editing
handled and interrupt the editor
```

This allows clipboard input to mutate the current draft without submitting it or forcing the interactive loop to restart, while preserving the prior extension-command interruption behavior.

## Image attachments

When the clipboard contains an image, Pi:

1. selects the best supported advertised MIME;
2. reads and validates the bytes;
3. writes a private `0600` temporary attachment;
4. inserts a correctly quoted `@"path"` reference at the cursor;
5. passes the file through the existing auto-resize, conversion, EXIF, privacy, provider, and multi-image pipeline on submission;
6. persists canonical image bytes and MIME metadata in append-only JSONL;
7. deletes the temporary clipboard file at normal process shutdown.

Spacing around the inserted reference is handled so existing or subsequent draft text does not merge into the attachment token.

## Text fallback and paste hygiene

If no image is available, the same shortcut reads text from the platform clipboard. Clipboard-command text now uses the same normalizer as bracketed terminal paste:

- CRLF and CR become canonical LF;
- tabs become four spaces;
- NUL and unsafe C0 control bytes are discarded;
- valid UTF-8 and permitted escape examples are retained.

This avoids a security and consistency split between terminal paste and direct clipboard paste.

## Real executable validation

A real pseudo-terminal fixture supplied a structurally valid PNG through a fake Wayland clipboard provider, then changed the same running clipboard to text.

Observed results:

```text
Ctrl+V image paste:                        passed
Persisted image MIME:                     image/png
Persisted image bytes:                    exact, 92 bytes
Second Ctrl+V text fallback:               passed
CRLF/tab/control normalization:            passed
Durable user messages:                     2
Temporary files after shutdown:            0
Process exit:                              0
Process stderr:                            0 bytes
```

The fixture passed independently with both the self-hosted non-LLVM Debug executable and the final LLVM Debug executable.

## Validation qualification

Completed gates:

```text
Clipboard/import filter:                  22/22 passed
Line-editor/import filter:                 23/23 passed
Keybinding/import filter:                  18/18 passed
Modified and whole-tree formatting:        passed, 188 Zig files
Python fixture compilation:                passed
Embedded Node bridge syntax:               unchanged and previously validated
Real-source audit:                         passed
Synthetic source files:                    0
Self-hosted Debug build:                   passed
LLVM static Debug build:                   passed
LLVM clipboard PTY E2E:                    passed
SQLite administration Debug build:        passed
SQLite init/integrity smoke:               passed
```

A cold direct all-package test artifact was attempted with SQLite and libc linked. Zig 0.16.0 exceeded the 30-minute compilation deadline before producing the test executable and emitted no compiler diagnostic or failing test output. No aggregate pass or aggregate failure is claimed.

## Remaining parity boundary

Checkpoint 175 materially closes clipboard image ingestion and text fallback, but complete Pi 0.84.1 equivalence is not claimed. Important remaining areas include:

- native clipboard writing for `/copy`, including Wayland/X11/system and bounded OSC 52 fallback;
- right-click clipboard-text paste behavior in the fullscreen shell, especially Windows;
- platform-native clipboard image formats beyond the supported PNG/JPEG/WebP/GIF/BMP path;
- an embedded image decoder/encoder instead of optional ImageMagick for transformations;
- the complete fullscreen package, login, and account managers;
- full npm, pnpm, Yarn, and Bun platform behavior;
- asynchronously invalidated extension-owned retained component trees;
- function-valued extension providers and extension-owned OAuth;
- native server TLS and mutual TLS;
- remaining enterprise credential, telemetry, update, retry, and interoperability breadth.
