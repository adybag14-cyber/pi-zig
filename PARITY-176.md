# Pi 0.84.1 → Zig checkpoint 176 parity audit

## Closed in checkpoint 176

| Original behavior | Zig checkpoint 176 status |
|---|---|
| `/copy` copies the last assistant response | Implemented through the shared native clipboard writer |
| `/copy` does not reprint the assistant response | Implemented and verified in a real PTY process |
| Wayland clipboard output | Implemented through bounded `wl-copy` execution |
| X11 clipboard output | Implemented through `xclip`, then `xsel` fallback |
| Termux clipboard output | Implemented through `termux-clipboard-set` |
| macOS clipboard output | Implemented through `pbcopy` |
| Windows clipboard output | Implemented through `clip`, then PowerShell fallback |
| WSL clipboard output | Implemented through Windows clipboard commands |
| Remote SSH/Mosh copy | Native write plus OSC 52 terminal copy |
| OSC 52 payload ceiling | Shared 100,000-byte encoded limit |
| Hung clipboard command handling | Deadline plus forced process termination |
| Tree-selector copy | Uses the same native/OSC 52 clipboard route |
| Extension `copyToClipboard` export | Implemented for original JS/TS compatibility imports |
| Machine-readable safety | Noninteractive extension requests suppress OSC 52 |
| Windows right-click paste boundary | Implemented as a non-submitting editor callback |
| Real process verification | Local, remote, and extension copy workflow passes with zero stderr |

## Qualified differences

- The port uses available platform commands and PowerShell rather than the original native clipboard addon.
- Native clipboard tools are simulated in the Linux process-level fixture; live GUI clipboard integration is not exercised on every supported operating system.
- The Windows right-click branch is covered through the native event/parser tests, not a real Windows desktop session.
- OSC 52 copies text only and deliberately rejects payloads whose base64 body exceeds 100,000 bytes.

## Validation evidence

```text
Zig compiler:                              0.16.0
Native Zig files under src/:               189
Native Zig logical lines:                  113,190
Named Zig test declarations:               970
Synthetic source files:                    0
Changed/imported module graph:             692/692 passed
All-package module process:                964 passed, 7 isolated, 0 failed
Build-test graph:                          13/13 steps succeeded
Static Debug Pi executable:                built and E2E-tested
SQLite administration executable:          built and integrity-tested
SQLite live companion:                     built and help-smoked
Local native clipboard E2E:                passed
Remote native + OSC 52 E2E:                passed
Extension copyToClipboard E2E:             passed
Combined child-process stderr:              0 bytes
```
