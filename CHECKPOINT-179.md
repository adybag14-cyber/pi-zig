# Pi Zig checkpoint 179 — retained provider-owned OAuth and device login dialog

Checkpoint 179 continues from checkpoint 178 and the supplied original Pi 0.84.1 source with Zig 0.16.0. It closes the highest-value authentication gap left by checkpoint 178: provider-owned browser and device-code operations no longer drop out of the fullscreen workflow into plain printed instructions and an opaque blocking wait.

## Retained asynchronous login dialog

The new native `auth_flow_tui` controller owns the provider flow after authentication type and provider selection. It provides:

- alternate-screen and raw-terminal lifecycle;
- buffered stdin hand-off from the parent interactive editor;
- OSC 8 authorization hyperlinks;
- browser-open instructions and callback-listener status;
- device verification URLs and user codes;
- elapsed-time and bounded progress history;
- manual redirect/code input with optional secret masking;
- Escape, Ctrl-C, Ctrl-D, EOF, and transport cancellation;
- provider-facing abort flags while callback or device polling is active;
- bounded control-character sanitization;
- success/failure presentation and deterministic terminal restoration.

The input and ticker tasks are grouped and synchronously cancelled before state is destroyed. A provider request aborted because the dialog was cancelled is normalized to `Login cancelled.` instead of exposing an internal transport error.

## Provider integration

The retained dialog is wired into:

- OpenAI Codex browser callback and device-code flows;
- Anthropic browser callback flow;
- OpenRouter browser callback flow;
- GitHub Copilot device-code flow and model discovery;
- Kimi Coding device-code flow;
- xAI device-code flow;
- Radius browser callback and device-code flows, including custom `models.json` providers.

Browser flows display the authorization URL before waiting, retain callback-listener details, and show token-exchange progress. Device flows retain the verification code on screen while polling. Provider token persistence and live client rebinding continue through the existing native completion functions.

When a Codex or Anthropic callback listener cannot bind but a live pending-flow store is available, the dialog keeps the PKCE flow alive and accepts the final redirect URL or code directly. Noninteractive/manual command forms remain compatible.

## Real executable validation

A loopback Radius provider and real pseudo-terminal exercised the final executable:

```text
Browser dialog entered:                    passed
OSC 8 authorization hyperlink:             passed
Real callback on 127.0.0.1:1456:           passed
Authorization-code exchange:               passed
OAuth credential persistence:              passed
Device-code dialog:                        passed
Visible verification code:                 CODE-179
Escape cancellation:                       passed
Cancellation returned to editor:           passed
Terminal restoration:                      passed
Process exit:                              0
Process stderr:                            0 bytes
```

Checkpoint-178 staged-selector and checkpoint-177 live-credential E2Es also pass unchanged.

## Source and validation measurements

```text
Original Pi source:                        0.84.1
Supplied Zig compiler:                     0.16.0
Native Zig files under src/:               191
Native Zig logical lines:                  115,569
Named Zig test declarations:               983
Synthetic/generated feature shards:        0

Authentication/import graph:               102/102 passed
Login-filtered graph:                      19/19 passed
Executable process:                       10/10 passed
SQLite repository process:                11/11 passed
SQLite CLI/schema process:                 8 passed, 6 intentional isolates
Auth dialog PTY E2E:                       passed
Checkpoint-178 auth selector regression:   passed
Checkpoint-177 live rebind regression:     passed
Whole-tree Zig formatting:                 passed
Python fixture compilation:                passed
Embedded Node bridge syntax:               passed
Real-source audit:                         passed
Static Pi Debug build:                     passed
SQLite administration Debug build:         passed
SQLite live-server Debug build:            passed
```

The complete multi-process `zig build test` topology was attempted. The executable, SQLite repository, and SQLite CLI processes completed without failures before the cold aggregate module compilation exceeded the command deadline. No unsupported aggregate pass is claimed.

## Remaining parity boundary

Checkpoint 179 materially closes the original provider-owned login-dialog boundary. Complete Pi 0.84.1 monorepo equivalence is not yet claimed. The largest remaining areas are:

1. Function-valued extension providers and extension-owned OAuth callbacks.
2. Every provider-specific prompt/select/manual-code event shape and flow-specific help link exposed by the original generic auth interaction protocol.
3. Fullscreen package install/update/remove and broader account-administration managers.
4. Complete npm, pnpm, Yarn, and Bun workspace, lockfile, lifecycle-script, global-store, and platform behavior.
5. Arbitrarily invalidated extension-owned retained component trees.
6. Native server TLS and mutual TLS.
7. An embedded image-transformation stack rather than optional ImageMagick.
8. Remaining enterprise authentication, telemetry, update, retry, and cross-language interoperability breadth.
