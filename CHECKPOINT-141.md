# Pi Zig V8 checkpoint 141

Checkpoint 141 continues the native Zig 0.16.0 rewrite against the uploaded original Pi 0.84.1 monorepo. It contains executable behavior and tests rather than generated feature-name shards.

## Measured state

- 139 Zig source files under `src/`
- 63,091 lines of native Zig under `src/`
- 644/644 integrated tests passing
- native Debug executable build passing
- no Node or TypeScript runtime dependency

## Native telemetry package

The rewrite now has a deterministic telemetry core rather than telemetry-shaped placeholders:

- no-op and in-memory context implementations
- parent/child spans and stable trace/span identities
- attributes, events, status and end semantics
- schema validation and thread-safe collection
- deterministic conformance tests

## Protocol and native client

Protocol-v1 support was extended from encoding/server use into a strict, reusable client surface:

- durable `SessionMetadata` for list and server snapshots, keeping attached live state in session snapshots
- closed-object decoding for all server message variants and nested model/session/transcript/error/progress payloads
- incremental handshake and fragmented frame processing
- reconnect-safe decoder reset and terminal truncation detection
- revision-aware authoritative state reduction and isolated subscribers
- typed encoding for all protocol commands
- pending-request correlation and command validation
- shared/exclusive lease ownership with disconnect invalidation
- Unix transport/socket-pair integration tests

## Terminal images, Markdown and LaTeX

The TUI now has native rich-output paths:

- Kitty direct/chunked uploads, placement-only redraw, deletion, source cropping and bounded metadata caching
- iTerm2 image transport
- PNG, JPEG, GIF and WebP metadata parsing without an image decoder
- protocol capability detection, cell sizing, hyperlinks and text fallback
- width-aware Markdown headings, emphasis, links, lists, tasks, quotes, rules, fenced code, tables and streaming-safe partial fences
- inline/display LaTeX with symbols, scripts, roots, fractions, operators, accents, matrices, cases, aligned/gathered environments and malformed-input fallback
- interactive final responses wired to active theme, terminal columns and hyperlink capability; print/JSON modes remain raw

## Input fidelity

The native input layer now covers:

- Kitty CSI-u identities, shifted/base-layout keys and press/repeat/release events
- xterm modifyOtherKeys, legacy arrows/functions, keypad normalization and control symbols
- fragmented CSI, OSC, DCS, APC, SGR mouse and old mouse framing
- atomic bracketed paste, CR normalization, control filtering and duplicate printable suppression
- SSH-aware Escape timing and fragmented WezTerm Escape handling
- line-editor dispatch for rich keys, release filtering and bracketed-paste lifecycle

## Unicode terminal text and retained layout

Checkpoint 141 centralizes terminal-cell semantics using native Unicode 15.1 property intervals:

- zero-width/default-ignorable and terminal-spacing mark behavior
- East Asian wide/fullwidth cells
- emoji presentation, modifiers, flags, keycaps and ZWJ sequences
- grapheme-cell hit testing and OSC 8 link lookup
- ANSI/OSC/DCS/APC stripping, Thai/Lao output normalization and fixed-width visible tabs
- cluster-safe slicing and truncation
- shared width behavior across terminal, Markdown and LaTeX code

A retained native layout tree now provides:

- component vtables with owned rendered frames
- vertical and horizontal stacks
- basis, grow, shrink, minimum, maximum and viewport visibility rules
- clipping, horizontal composition and Unicode-safe painting
- follow-end scrolling, explicit scrolling and overscroll chaining
- hidden/automatic/always scrollbars with proportional thumb geometry
- native text, truncated-text, spacer and static-line components

## Validation policy

The final source archive is created without `.zig-cache` or `zig-out`, extracted into a separate directory, tested and rebuilt with the supplied Zig 0.16.0 toolchain. The checkpoint patch is applied to a fresh extraction of checkpoint 140 and the reconstructed source tree is compared byte-for-byte. Artifact hashes and completed-file stability checks are recorded separately in `VALIDATION-141.txt` and the SHA-256 manifest.

## Remaining parity boundary

Checkpoint 141 does not claim complete feature equivalence. The largest remaining areas are arbitrary JavaScript/TypeScript extension execution, the complete application TUI shell and overlay/dialog/mouse/IME behavior, all original SQLite/remote session backends, the complete provider enterprise-auth/proxy/retry matrix, auxiliary eval/client/server package breadth, and exhaustive byte-for-byte interoperability fixtures.
