# Checkpoint 182 — live extension OAuth login and credential lifecycle

Checkpoint 182 connects extension-defined OAuth providers to the real `/login` command, canonical credential storage, model projection, and every native request transport that consumes provider credentials. It builds on checkpoint 181's persistent callback ownership and does not serialize JavaScript function source.

This checkpoint deliberately does **not** claim complete TypeScript provider parity. Dynamic `refreshModels(context)` publication/persistence and the `streamSimple` event-stream bridge remain subsequent lanes.

## Implemented

### Production OAuth interaction protocol

`src/extensions/js_bridge.mjs` and `src/extensions/js_runtime.zig` now execute `oauth.login(callbacks)` on the provider callback's owning persistent extension worker.

The worker exposes the upstream interaction surface through native UI records:

- `onAuth` → `oauth_auth` action with URL and optional instructions;
- `onDeviceCode` → `oauth_device_code` action with verification URI, user code, timing metadata, and instructions;
- `onProgress` → `oauth_progress` action;
- `onPrompt` → signal-aware `oauth_prompt` request, including secret input support;
- `onManualCodeInput` → signal-aware `oauth_manual_code` request;
- `onSelect` → signal-aware `oauth_select` request with normalized choices;
- `signal` → the live invocation `AbortSignal` controlled by native cancellation.

Pending host requests install invocation-scoped abort listeners, remove their pending promise on abort, and remove the listener on success or failure. JavaScript exceptions and rejected promises retain their stack text in the native provider-method error channel.

Human OAuth interaction uses a dedicated 15-minute default deadline rather than the ordinary 15-second extension callback timeout. The ordinary timeout is restored after every login attempt. Tests also cover overriding both deadlines independently.

### Canonical JSON-preserving credential transactions

`src/auth/storage.zig` now provides complete JSON OAuth operations:

- `readOAuthJson`;
- `setOAuthJson` and `setOAuthJsonAbortable`;
- `modifyOAuthJson` and `modifyOAuthJsonAbortable`.

These operations preserve provider-specific and future credential fields instead of reducing credentials to the native fixed-field struct. They retain the existing advisory-lock discipline, validate replacements before mutation, and check cancellation immediately before durable writes. Invalid, rejected, or late-cancelled replacements leave the previous credential unchanged.

`src/extensions/provider_oauth.zig` centralizes the extension OAuth lifecycle:

1. invoke `oauth.login` on the owning worker;
2. validate the returned OAuth object;
3. persist the complete object through the canonical auth store;
4. resolve stored credentials for requests;
5. refresh credentials under the exclusive auth transaction when they are inside the one-minute early-refresh window;
6. persist the replacement atomically;
7. derive the request key through `oauth.getApiKey`;
8. apply credential-dependent models through `oauth.modifyModels`.

Concurrent refresh callers re-check expiry while holding the auth lock, preventing duplicate refresh writes. Login cancellation maps to `LoginCancelled`; request-resolution cancellation maps to `Canceled`. A callback that ignores its `AbortSignal` cannot commit a late credential after native cancellation.

### Real `/login` and authentication UI integration

The interactive and headless login paths now recognize extension OAuth providers:

- bare `/login` receives extension OAuth provider IDs even when the provider has no currently published catalog models;
- `/login <extension-provider>` selects the extension browser flow by default;
- the full-screen dialog renders authorization URLs, device codes, progress, secret and non-secret prompts, manual-code entry, and provider selection lists;
- Escape and Ctrl-C drive the native abort flag;
- non-interactive execution rejects requests requiring human input rather than waiting indefinitely;
- successful login persists the complete credential and rebuilds the active provider client.

A provider is offered as a usable extension OAuth login target only when it defines both `oauth.login` and `oauth.getApiKey`. This prevents a login-only provider from accepting credentials that the request path can never consume.

### Request transport and model integration

`src/coding_agent/live_state.zig` exposes a cycle-free `ExtensionOAuthBridge` consumed by `ClientPool`. The bridge resolves and owns extension-derived request keys and expiry metadata, and credential-aware model projection happens after credentials resolve.

Refresh callbacks are wired into the native clients used by extension providers:

- OpenAI-compatible chat completions;
- OpenAI Responses;
- Anthropic-compatible requests;
- Pi Messages;
- Google;
- Mistral;
- Bedrock bearer credentials.

Provider and model identifiers used during projected-catalog replacement are owned rather than borrowed from a snapshot that may be invalidated by publication.

### Reload, unregister, and rollback safety

Before a provider registry is replaced or removed, `ClientPool.invalidateExtensionOAuth()` detaches extension-derived keys, expiry pointers, and refresh callbacks from every concrete client. Only then are the owned key and callback runtime released.

During transactional extension reload, OAuth resolution is temporarily routed through the candidate provider registry. A failed reload restores the original registry and live snapshots; a successful reload rebinds the stable registry. Explicit unregister removes callback ownership and invalidates any active transport state before the worker or provider snapshot disappears.

### Verification hardening

The production bridge E2E launches the actual `src/extensions/js_bridge.mjs` and covers the full login interaction surface, complete credential return, rejection stacks, cancellation, pending-request cleanup, and worker reuse. The structural production checker spans the JavaScript bridge, runtime, registry, lifecycle, storage, slash path, TUI selector, live clients, three additional AI transports, and main reload wiring.

Focused Zig regressions cover login/persistence, serialized refresh, request-key derivation, `modifyModels`, cooperative and non-cooperative cancellation, reload/unregister ownership, transport invalidation, `/login`, selector visibility, arbitrary credential fields, abort-aware storage, the human login deadline, callback ownership, and callback-ID collisions.

## Source delta from checkpoint 181

The production/test patch changes 16 files:

- 2,150 inserted lines and 34 deleted lines;
- new `src/extensions/provider_oauth.zig` lifecycle module;
- new production OAuth bridge E2E and integration checker;
- storage, login UI, slash command, client pool, provider registry, JavaScript runtime, main lifecycle, and transport updates.

The exact patch is `CHECKPOINT-181-to-182.patch`; machine-readable per-file statistics are in `checkpoint-182-patch-report.json`.

## Verification

Using the uploaded Zig 0.16.0 toolchain, the working tree passed:

- JavaScript and Python syntax checks;
- checkpoint-181 provider-method production bridge E2E;
- checkpoint-181 provider-method structural integration checker: 13/13;
- checkpoint-182 provider OAuth login production bridge E2E;
- checkpoint-182 provider OAuth structural integration checker: 22/22;
- 12 focused production-path filters, each completing 17/17 test-root checks;
- Zig formatting checks;
- source audit: 193 Zig files, 118,181 Zig LOC, zero synthetic source files;
- default `zig build -Duse-llvm=false --summary all`: 3/3 steps;
- complete `zig build test -Duse-llvm=false --summary all`: 992 passed, 7 intentional skips, 0 failed; 13/13 build steps.

All required gates are repeated from a fresh extraction of the exact final ZIP. The external `pi-zig-v8-checkpoint-182-FINAL.verification.json` and transfer-verification sidecar are the final archive evidence.

## Remaining parity work

Checkpoint 182 completes the live extension OAuth login and credential lifecycle slice, but the provider rewrite still has these material gaps:

1. bridge `refreshModels(context)` with effective refreshed credentials, immutable stored state, offline/online policy, force, a live abort signal, generation-checked `publish`, provider-owned persistence, and transactional catalog updates;
2. persist and reload extension-owned dynamic model catalogs with the same semantics as upstream `ModelsStoreEntry`;
3. bridge `streamSimple(model, context, options)` as a native event stream, including payload/response hooks, partial events, usage, tool calls, cancellation, and terminal errors;
4. complete remaining object-form native `Provider` auth/filter/stream semantics;
5. retire obsolete JavaScript callback generations after native acknowledgement instead of retaining them until unregister or worker shutdown.
