# Pi Zig checkpoint 178 — staged authentication selection and source-aware credential status

Checkpoint 178 continues from checkpoint 177 and the supplied original Pi 0.84.1 source using Zig 0.16.0. It closes the previously documented mismatch between Pi's staged authentication workflow and checkpoint 177's combined provider/method list, while making credential-source reporting agree with the actual provider and noninteractive-auth resolution paths.

## Original two-stage login workflow

Bare interactive `/login` now follows the original selection order:

1. Choose an authentication type:
   - `Sign in with an account`
   - `Sign in with an API key`
2. Choose a provider supporting that type.
3. Continue into the existing browser, device-code, or masked API-key flow.

The selector remains fully native and retained. It preserves search, keyboard navigation, mouse input, bounded secret entry, alternate-screen ownership, and deterministic terminal restoration.

Explicit provider routing is also more faithful:

```text
/login anthropic
```

When a provider offers more than one authentication method, Pi opens an authentication-type stage scoped to that provider. A provider with only one available method proceeds directly. Unknown text remains an initial provider-search query rather than being silently interpreted as a credential.

Explicit automation forms remain unchanged:

```text
/login <provider> <api-key>
/login <provider> browser
/login <provider> device-code
/logout <provider>
```

## Source-aware provider status

Provider rows now identify the effective source that can satisfy authentication rather than reporting only durable `auth.json` entries.

Implemented status sources include:

- `stored credential` for Pi-managed `auth.json` entries;
- the exact environment variable name, such as `OPENAI_API_KEY`;
- `configured API key` for resolvable `models.json` keys;
- `AWS_PROFILE` and `AWS_DEFAULT_PROFILE`;
- `AWS access keys`;
- `ECS task role`;
- `web identity token`;
- `AWS_BEDROCK_SKIP_AUTH`.

A status can also show that the configured credential type differs from the currently viewed login method. This prevents a stored API key from making an account/subscription row appear as though browser login itself were already configured.

`models.json` environment templates are shown as configured only when the referenced value currently resolves. Literal and command-backed keys remain valid configured sources.

## Correct Anthropic environment classification

`ANTHROPIC_OAUTH_TOKEN` is accepted by the Anthropic API-key resolver. It is not a durable OAuth record with refresh metadata.

Checkpoint 178 makes the fullscreen selector, `pi auth check`, and `pi auth print-api-key` agree on this boundary:

```text
Auth type: api_key
Printable key source: ANTHROPIC_OAUTH_TOKEN
```

This removes a mismatch where noninteractive diagnostics could classify the same credential differently from the live provider client.

## Standalone Escape handling

Production PTY validation exposed a terminal-input defect hidden by unit tests: a lone Escape byte is deliberately incomplete to the generic CSI parser, so the authentication selector could ignore Escape indefinitely.

The selector now recognizes standalone Escape explicitly:

- active search is cleared first;
- provider selection returns to the authentication-type stage when appropriate;
- a provider-scoped type stage returns to the caller;
- the outer stage cancels cleanly.

This behavior is covered by a focused regression test and the real staged-login PTY fixture.

## Real executable validation

### Staged authentication and source labels

```text
Authentication-type stage:                 passed
Subscription provider stage:               passed
API-key provider stage:                    passed
Stored-type mismatch display:              passed
Environment source display:                OPENAI_API_KEY
models.json source display:                 configured API key
Explicit-provider scoped stage:            anthropic
Masked custom-provider key persistence:    passed
Anthropic stored credential replacement:   passed
Secrets absent from terminal:              passed
Terminal restoration:                      passed
Process exit:                              0
Stderr bytes:                              0
```

### Checkpoint-177 regressions retained

```text
Masked login/logout selector:              passed
Private auth.json permissions:             passed
Stored credential removal:                 passed
Active custom-provider key rebinding:      passed
Logout fallback to models.json:            passed
Provider requests:                         2
Combined process stderr:                   0 bytes
```

## Validation qualification

Completed gates:

```text
Auth-filtered source graph:                100/100 passed
Auth selector focused graph:               20/20 passed
Explicit-provider focused graph:           19/19 passed
Anthropic environment classification:      passed
Canonical executable process observed:     10/10 passed
Whole-tree Zig formatting:                 passed
Python fixture compilation:                passed
Embedded Node bridge syntax:               passed
Real-source audit:                         passed
Synthetic feature shards:                  0
Static self-hosted Debug Pi build:          passed
SQLite administration build:              passed
Fresh SQLite integrity check:              passed
Three authentication PTY workflows:        passed
Combined child-process stderr:             0 bytes
```

The canonical `zig build test` graph was attempted. Its ordinary executable process completed 10/10 tests, but compilation of the remaining cold aggregate artifacts exceeded the command deadline. No complete all-package result is claimed.

The optional SQLite live-server build was also attempted and exceeded its compile deadline before producing a complete executable. It is not published, and no older live-server binary is reused or relabeled.

## Remaining parity boundary

Checkpoint 178 closes the staged authentication-type/provider workflow, provider-scoped method selection, configuration-source status labels, standalone-Escape handling, and Anthropic environment classification.

Complete Pi 0.84.1 equivalence is not claimed. The largest remaining areas are:

- the original provider-owned asynchronous login dialog with hyperlinks, codes, progress, manual input, cancellation, and complete flow-specific status presentation;
- function-valued extension providers and extension-owned OAuth callbacks;
- the complete fullscreen package install/update/remove and broader account-administration managers;
- complete npm, pnpm, Yarn, and Bun workspace, lockfile, lifecycle-script, global-store, and platform behavior;
- asynchronously invalidated extension-owned retained component trees;
- native server TLS and mutual TLS;
- an embedded image transformation stack instead of optional ImageMagick;
- remaining enterprise authentication, telemetry, update, retry, and cross-language interoperability breadth.

## Exact archive and patch reconstruction

The frozen checkpoint was reproduced through two independent paths:

```text
Tracked final files:                       412
Exact source-ZIP files:                    412
Patch-reconstructed files:                 412

ZIP missing/extra/changed/mode-changed:    0 / 0 / 0 / 0
Patch missing/extra/changed/mode-changed:  0 / 0 / 0 / 0
Uploaded checkpoint-177 baseline match:    405/405 files
ZIP compressed-data integrity:             passed
git apply --check:                         passed
Patch application:                        passed
```

Both the exact ZIP extraction and independently patched source passed:

```text
Auth-filtered graph:                       100/100 passed
Self-hosted Debug Pi build:                passed
Staged authentication PTY E2E:             passed
Process exit:                              0
Process stderr:                            0 bytes
```
