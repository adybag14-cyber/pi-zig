# Pi Zig checkpoint 177 — native account selector and transactional credential synchronization

Checkpoint 177 continues from checkpoint 176 and the supplied original Pi 0.84.1 source using Zig 0.16.0. It closes the principal interactive account-management gap around bare `/login` and `/logout`, immediate API-key activation, safe active-provider rebinding, and authoritative credential removal during live runtime reload.

## Retained fullscreen account selector

Bare interactive commands now open a native alternate-screen selector:

```text
/login
/logout
```

The selector provides:

- searchable provider and authentication-method rows;
- API-key, browser/subscription, and device-code methods;
- built-in and `models.json` provider identities;
- persisted credential status;
- logout rows limited to credentials actually stored by Pi;
- keyboard navigation, paging, mouse wheel, click, and bounded double-click confirmation;
- optional initial search text;
- deterministic raw-mode, mouse, paste, cursor, and alternate-screen restoration;
- safe cancellation without mutating auth storage.

Provider rows preserve public identities rather than collapsing custom OpenAI-compatible providers into the built-in `openai` identity. Local providers that do not require credentials are excluded from API-key selection.

## Masked API-key entry

API-key methods enter a separate retained secret-input phase. The key is represented only by mask characters and is never rendered back to the terminal.

The implementation:

- bounds secret input;
- zeroes secret buffers before freeing them;
- writes through the existing locked, atomic `auth.json` storage;
- preserves private file permissions;
- never includes the key in status output or E2E reports.

Explicit scriptable forms remain available:

```text
/login <provider> <api-key>
/login <provider> browser
/login <provider> device-code
/logout <provider>
```

## Immediate live API-key activation

A successfully stored API key is now installed into the live client pool with owned storage. When the selected provider is active, the client is rebuilt immediately, so the next model request uses the new credential without restarting Pi or manually issuing `/reload`.

The active model ID is copied before rebinding because `switchToIdentity()` replaces its owned model allocation. This fixes a lifetime defect exposed by the real provider test.

## Transactional logout and runtime reload

Deleting an active credential must make the newly loaded `auth.json` and `models.json` snapshot authoritative without leaving dangling pointers or stale process-local precedence.

Checkpoint 177 adds deep credential cloning for:

- API keys;
- OAuth refresh and access values;
- expiry, scope, account ID, and enterprise URL;
- available-model IDs and their presence marker.

Runtime reload now:

1. Deep-snapshots the process-local interactive credential.
2. Stages the replacement provider and model catalog.
3. Clears old interactive precedence before rebuilding clients.
4. Uses current persisted auth and provider configuration for the replacement.
5. Restores the old credential by ownership transfer if any rebind step fails.
6. Frees the old snapshot only after a successful commit.

This means `/logout` can remove a stored override and immediately fall back to a key from `models.json` or another authoritative current source while preserving rollback safety.

## Real executable validation

### Fullscreen login/logout workflow

```text
Login selector opened:                     passed
Search provider/method:                    passed
Masked key entry:                          passed
Private auth.json persistence:             passed
Logout selector stored status:             passed
Credential removal:                        passed
Secret absent from terminal:               passed
Terminal restoration:                      passed
Process exit:                              0
Stderr bytes:                              0
```

### Active-provider rebinding workflow

A custom provider used a real loopback OpenAI-compatible SSE endpoint.

```text
Initial configured key:                    models.json
Interactive login key persisted:           passed
First provider request:                    interactive key
Stored credential removed:                 passed
Live runtime reload:                       passed
Second provider request:                   models.json key
Provider request count:                    2
Secret absent from terminal:               passed
Process exit:                              0
Stderr bytes:                              0
```

## Validation qualification

Completed gates include:

```text
Auth selector/import graph:                107/107 passed
Credential-focused graph:                  29/29 passed
Login-focused graph:                       6/6 passed
Executable/main process:                  10/10 passed
SQLite repository process:                11/11 passed
SQLite CLI/schema process:                 8 passed, 6 isolated, 0 failed
Static Debug Pi build:                     passed
SQLite administration build:              passed
Whole-tree Zig formatting:                 passed
Python fixture compilation:                passed
Embedded Node bridge syntax:               passed
Real-source audit:                         passed
Synthetic source files:                    0
Fullscreen auth E2E:                       passed
Live provider rebinding E2E:               passed
Combined child stderr:                     0 bytes
```

The cold all-package module process and SQLite live-server build were attempted but exceeded their command deadlines without compiler diagnostics or failing tests. They are not mislabeled as passes. The ordinary static Pi executable and SQLite administration companion are complete checkpoint-177 builds.

## Remaining parity boundary

Checkpoint 177 materially closes the original bare login/logout selector and credential synchronization boundary. Complete Pi 0.84.1 equivalence is not claimed. Important remaining areas include:

- the original two-stage authentication-type selector and complete source/status wording;
- provider-owned asynchronous login dialog presentation, hyperlinks, progress, and cancellation for every OAuth flow;
- function-valued extension providers and extension-owned OAuth callbacks;
- the complete fullscreen package install/update/remove and account-administration managers;
- full npm, pnpm, Yarn, and Bun platform behavior;
- asynchronously invalidated extension-owned component trees;
- native server TLS and mutual TLS;
- an embedded image transformer rather than optional ImageMagick;
- remaining enterprise authentication, telemetry, update, retry, and interoperability breadth.
