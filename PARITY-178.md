# Pi 0.84.1 → Zig checkpoint 178 parity audit

## Closed in checkpoint 178

| Original behavior | Zig checkpoint 178 status |
|---|---|
| Authentication type selected before provider | Implemented as separate retained fullscreen stages |
| Account/subscription and API-key provider lists | Implemented and filtered by supported method |
| `/login <provider>` with multiple methods | Opens a provider-scoped authentication-type stage |
| `/login <provider>` with one method | Proceeds directly to the only supported method |
| Unknown login query | Preserved as an initial provider-search query |
| Stored credential source | Reported as `stored credential` |
| Environment credential source | Exact variable name shown where available |
| `models.json` key source | Reported as `configured API key` only when resolvable |
| AWS ambient credential sources | Profile, access-key, ECS, web-identity, and skip-auth statuses covered |
| Credential/method mismatch | Selector distinguishes configured credential type from viewed method |
| `ANTHROPIC_OAUTH_TOKEN` classification | Correctly treated as API-key authentication across UI and `pi auth` |
| Standalone Escape in fullscreen selector | Explicit search-clear, back, and cancel behavior implemented |
| Checkpoint-177 masked login/logout | Retained and revalidated |
| Live active-provider credential rebinding | Retained and revalidated |

## Qualified differences

- Browser and device-code selection now begins with the original staged selector, but the subsequent provider-owned flow still uses the port's existing flow-specific presentation rather than the complete original asynchronous login-dialog component.
- Environment and configuration status coverage is substantially broader, but provider-specific enterprise account-policy labels may still differ for edge-case credential chains.
- Logout remains intentionally limited to Pi-managed durable credentials; ambient environment and `models.json` sources are visible but not presented as deletable stored entries.

## Validation evidence

```text
Original Pi source:                        0.84.1
Zig compiler:                              0.16.0
Native Zig files under src/:               190
Native Zig logical lines:                  114,787
Tracked Zig files:                         191
Named Zig test declarations:               981
Synthetic feature shards:                  0

Auth-filtered source graph:                100/100 passed
Auth selector focused graph:               20/20 passed
Explicit-provider focused graph:           19/19 passed
Canonical executable process observed:     10/10 passed
Whole-tree formatting:                     passed
Static self-hosted Pi build:               passed
SQLite administration build:              passed
Staged authentication PTY E2E:             passed
Checkpoint-177 auth screen regression:     passed
Checkpoint-177 live rebind regression:     passed
Combined child-process stderr:             0 bytes
```

## Reproduction evidence

```text
Uploaded checkpoint-177 baseline:          405/405 files matched
Final source ZIP:                          412/412 files matched
Patch reconstruction:                     412/412 files matched
Content and executable modes:              byte-for-byte passed
Exact ZIP auth graph:                      100/100 passed
Patch reconstruction auth graph:           100/100 passed
Exact ZIP and patch static builds:          passed
Exact ZIP and patch staged PTY E2E:         passed
```

## Unclosed high-value areas

1. Complete asynchronous OAuth/device-flow dialog presentation, hyperlinks, progress, manual-code entry, and cancellation.
2. Function-valued extension providers and extension-owned OAuth callbacks.
3. Fullscreen package install/update/remove and broader account-administration managers.
4. Complete package-manager platform behavior.
5. Arbitrarily invalidated extension-owned component trees.
6. Native server TLS and mutual TLS.
7. Embedded image transformation.
8. Remaining enterprise authentication and interoperability edge cases.
