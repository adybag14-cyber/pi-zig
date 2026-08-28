# Pi 0.84.1 → Zig checkpoint 177 parity audit

## Closed in checkpoint 177

| Original behavior | Zig checkpoint 177 status |
|---|---|
| Bare `/login` opens a provider selector | Implemented with a retained fullscreen native selector |
| Bare `/logout` lists removable stored credentials | Implemented; environment and `models.json` credentials are not presented as deletable stored entries |
| Search provider/authentication methods | Implemented with case-insensitive multi-token fuzzy matching |
| API-key and subscription/device-code choices | Implemented across built-in and custom provider identities |
| Masked API-key entry | Implemented without rendering secret bytes |
| Private credential persistence | Uses locked, atomic `auth.json` with private permissions |
| Immediate login activation | Active provider client is rebound to the new owned key |
| Custom provider identity preservation | Custom IDs remain distinct from built-in transport identities |
| Immediate logout synchronization | Runtime reload uses current persisted auth/provider state |
| Configured fallback after logout | Verified by falling back from an interactive key to `models.json` |
| Reload rollback safety | Deep snapshot and ownership-transfer restore for API-key and OAuth credentials |
| Secret lifecycle | Secret buffers are zeroed before deallocation and excluded from terminal/report output |
| Terminal lifecycle | Raw mode, mouse, paste, cursor, and alternate screen restore cleanly |
| Real process verification | Fullscreen auth and live provider requests pass with zero stderr |

## Qualified differences

- The original presents authentication type and provider in separate selector stages; checkpoint 177 presents provider/method combinations in one searchable list.
- The selector reports stored credential state but does not yet reproduce every environment/configuration-source label from the original UI.
- Existing browser and device-code flows are selected from the fullscreen list, but their subsequent progress presentation still uses the port's current flow-specific command UI rather than the complete original login-dialog component.
- Logout reload failure remains surfaced as a command error after persistent deletion; the old process-local credential is retained through rollback so the running client is not left with invalid memory.

## Validation evidence

```text
Original Pi source:                        0.84.1
Zig compiler:                              0.16.0
Native Zig files under src/:               190
Native Zig logical lines:                  114,308
Named Zig test declarations:               994
Synthetic source files:                    0
Auth selector/import graph:                107/107 passed
Credential-focused graph:                  29/29 passed
Login-focused graph:                       6/6 passed
Executable/main process:                  10/10 passed
SQLite repository process:                11/11 passed
SQLite CLI/schema process:                 8 passed, 6 isolated, 0 failed
Static Pi build:                           passed
SQLite administration build:              passed
Fullscreen auth PTY E2E:                   passed
Live provider credential E2E:              passed
Combined child-process stderr:             0 bytes
```
