# Pi Zig checkpoint 176 — native clipboard output and bounded OSC 52

Checkpoint 176 continues from checkpoint 175 and the supplied original Pi 0.84.1 source using Zig 0.16.0. It closes the principal clipboard-output gap across `/copy`, the fullscreen session-tree selector, JavaScript/TypeScript extensions, remote terminals, and the Windows right-click paste event boundary.

## Shared clipboard output subsystem

The existing native clipboard module now supports bounded text writes as well as reads. The writer implements:

- Wayland through `wl-copy`;
- X11 through `xclip`, with `xsel` fallback;
- Termux through `termux-clipboard-set`;
- macOS through `pbcopy`;
- Windows through `clip`, with PowerShell `Set-Clipboard` fallback;
- WSL through the Windows clipboard commands;
- OSC 52 when native writing is unavailable or when the session is remote.

Native commands are invoked directly rather than through a shell. Input is supplied through a private temporary file, subprocesses have a 5-second deadline, nonresponsive process groups are force-terminated on POSIX, and temporary input is removed deterministically.

Remote sessions deliberately perform both operations when possible: the remote host receives its native clipboard write and the local terminal receives OSC 52. Remote detection covers SSH and Mosh environment identities.

## Bounded OSC 52

A shared `src/tui/osc52.zig` implementation now owns OSC 52 framing. It applies the original Pi ceiling:

```text
Maximum encoded payload: 100,000 bytes
```

Oversized terminal payloads are rejected rather than emitted. This removes the former unbounded behavior from both the retained application-selection helper and the fullscreen tree selector.

## Functional `/copy`

The native `/copy` command now copies the last assistant text instead of printing it back into the transcript.

Behavior now matches the original contract:

```text
No assistant response -> clear command error
Successful copy       -> status confirmation
Native failure        -> bounded OSC 52 fallback
Total failure         -> explicit clipboard error
```

The assistant response is not duplicated in print output or durable history.

## Fullscreen tree and extension integration

The session-tree selector now routes selected-entry copy through the same native writer. This provides platform writes, remote OSC 52, the common payload ceiling, and consistent error handling.

The JavaScript/TypeScript compatibility layer now exports:

```typescript
copyToClipboard(text: string): Promise<void>
```

Extension requests reach the same Zig writer. In noninteractive JSON/RPC contexts, terminal control-sequence fallback is suppressed so machine-readable output cannot be polluted; native clipboard writes remain available.

## Windows right-click paste boundary

The retained line-editor input contract now recognizes an unmodified secondary-button press as a non-submitting clipboard-paste request when Windows behavior is enabled. The callback mutates the current draft and keeps the editor active.

The event boundary and editor behavior are covered by native tests. A real Windows GUI clipboard session was not available in the Linux validation container, so this is source/test coverage rather than a claim of end-to-end Windows runtime validation.

## Additional correction

While exercising the extension command route, checkpoint 176 removed a duplicate JSON string write in the extension-command RPC response. The malformed response could previously serialize the command name twice.

## Real executable validation

A real PTY fixture used a fake Wayland clipboard writer and the final static executable.

```text
Local /copy native writes:                 1
Local OSC 52:                              absent
Remote /copy native writes:                1
Remote OSC 52:                             present
Assistant response reprints:               0
Extension copyToClipboard native write:    passed
All process exits:                         0
Combined child stderr:                     0 bytes
```

## Validation qualification

Completed gates:

```text
Changed/imported module graph:             692/692 passed
All-package module process:                964 passed, 7 isolated, 0 failed
SQLite repository process:                11/11 passed
SQLite CLI/schema process:                 8 passed, 6 isolated, 0 failed
Ordinary executable process:              10/10 passed
SQLite live-persistence process:           5/5 passed
SQLite-enabled executable process:        10/10 passed
Build-test graph:                          13/13 steps succeeded
Whole-tree Zig formatting:                 passed
Embedded Node bridge syntax:               passed
Python E2E fixture compilation:             passed
Git diff validation:                       passed
Static LLVM Debug Pi build:                passed
SQLite administration executable:          built and integrity-tested
SQLite live companion:                     built and help-smoked
Real `/copy` and extension E2E:            passed
```

The seven module-process isolates are deliberate C-linked SQLite cases. Six execute in the dedicated repository process, and the SQLite CLI integration case executes in its separately linked process.

## Remaining parity boundary

Checkpoint 176 materially closes native clipboard writing, `/copy`, bounded OSC 52, tree-copy reuse, extension copy export, and the Windows right-click event boundary. Complete Pi 0.84.1 equivalence is not claimed. Important remaining areas include:

- real Windows fullscreen right-click validation and platform-native GUI clipboard APIs;
- additional platform-native clipboard image formats;
- an embedded image decoder/encoder instead of optional ImageMagick;
- the complete fullscreen package, login, and account managers;
- complete npm, pnpm, Yarn, and Bun platform behavior;
- asynchronously invalidated extension-owned component trees;
- function-valued extension providers and extension-owned OAuth;
- native server TLS and mutual TLS;
- remaining enterprise credential, telemetry, update, retry, and interoperability breadth.
