# Actual legacy Windows TTY output continuation

This source-only continuation follows the frozen TTY/backend and utility
review packets. Nothing here was compiled, AST checked, executed or selected.
No Main/shared C/header/Engine or protected Source20/14 path changed. Earlier
receipts and manifests remain historical and were not rewritten.

`native_node_tty_windows_legacy.zig` ports the retained Node v24.14.0 libuv
`src/win/tty.c` parser and its native screen operations. Its four arguments and
field widths come from the separately retained original `include/uv/win.h`.
The Node license was already retained with the authority. The new leaf has no
VM, allocator, worker, callback, process or borrowed Engine pointer. It uses
real Windows console handles and module-local Zig Win32 extern declarations.

The native operations cover all commands that this Source parser supports:
relative/absolute movement, line/screen erase, initial state reset, SGR
foreground/background/brightness/inverse changes, saved position/intensity,
cursor visibility and cursor shape. Unsupported ANSI sequences are ignored by
the actual state machine, including its quoted string-control termination
rules. They are not replaced with an approximate modern ANSI implementation.
The Source 16-color implementation does not gain a fake 24-bit mode.

Parser and UTF8/EOL carry survive writes. The fourth argument limit, unsigned
short final-digit wrap, trailing-semicolon behavior, DECSCUSR invalid-byte
fallthrough, invalid erase argument's preceding text flush, two saved intensity
bits, and Source cursor size values are retained. Only parsed text reaches the
same 8192-WCHAR WriteConsoleW path. Controls first flush preceding text and
then make the real relevant console API calls, in Source order.

`native_node_tty_windows_output` now performs Source once-per-process VT
capability detection, initial style/cursor capture and virtual-window update
under the same global lock used for the entire synchronous write. The console
admission carries its actual queried initial screen/cursor data to that step;
no invented dimensions or new post-transfer fallible ownership operation is
added. A failed VT attempt selects the actual legacy translator, rather than
passthrough or a missing-output placeholder. The existing ownership selection
guard remains false.

The virtual window spans the actual screen-buffer width and visible-window
height; its offset follows the captured cursor, subsequent scrolling and
screen-buffer bottom bound. Initial style and cursor are captured once, as in
Source, with its black-on-black conversion. Real ERROR_INVALID_PARAMETER on
move/fill triggers Source's fresh-info resize retry. The retry is synchronous
under the console lock, as the original; no invented timer, extra tick or
asynchronous completion substitutes for it.

The original set-style/cursor-visibility/cursor-shape helpers lack the other
helpers' prior-error early guard. This implementation preserves those real
subsequent calls and their actual failure result instead of silently following
the broader comment's intended stop-all-IO rule. WriteConsoleW still stops
after its first failure while UTF8/parser state continues consuming the input.

One explicit native safety deviation requires review: original move_caret
records a failed GetConsoleScreenBufferInfo and then reads uninitialized info.
This implementation terminates with that actual query error. There is no
deterministic Source coordinate or success value to emulate from undefined
memory. Other Source retry/error behavior is preserved.

Primary Microsoft API contracts used for local ABI/ownership review:

- https://learn.microsoft.com/en-us/windows/console/console-screen-buffer-info-str
- https://learn.microsoft.com/en-us/windows/console/setconsolecursorposition
- https://learn.microsoft.com/en-us/windows/console/fillconsoleoutputcharacter
- https://learn.microsoft.com/en-us/windows/console/fillconsoleoutputattribute

`original-legacy-console-inputs.json` is an original input/control specification
with no expected output. A later Root-owned reference driver must use the
actual pinned libuv `uv_tty_set_vterm_state(UV_TTY_UNSUPPORTED)` and original
write algorithm against independently owned private console buffers. Observe
actual characters, attributes, cursor, write result and physical API failures.
This mode override is the original public native API, not a simulated failure
of SetConsoleMode. The driver/helper and exact original libuv source/build
closure still need Root review/grant; no reference driver or capture is claimed.
No ordinary user terminal, framed worker stdout or fake HANDLE is admitted.

Source review, exact ABI/linked-source checks, original controls, physical
private-console output and actual callback/backpressure qualification remain
separate required gates. Input cancellation and frontend remote-handle
authority retain their earlier ownership boundaries.
