# Checkpoint 183 — generation-safe extension `refreshModels(context)` publication and persistence

Checkpoint 183 completes the dynamic model-refresh lane for extension-defined providers. It connects the production JavaScript worker to a native generation coordinator, canonical `models-store.json` persistence, OAuth credential resolution, live registry/client publication, startup cache restoration, selective online refresh, and transactional reload/unregister handling.

This checkpoint deliberately does **not** claim complete provider parity. The remaining major lane is `streamSimple(model, context, options)` as a real ordered event stream rather than a one-shot callback.

## Implemented

### Production refresh context and publication protocol

`src/extensions/js_bridge.mjs` now retains each provider's original live configuration object separately from the JSON-safe registration snapshot. This preserves object identity and private mutable state for object-form providers while keeping manifests serializable.

The production worker handles `provider_refresh_models` and invokes the registered `refreshModels` callback with:

- the effective credential, deep-cloned and deeply frozen;
- the provider-scoped stored catalog snapshot, deep-cloned and deeply frozen;
- `allowNetwork`;
- `force` only during an online phase;
- the invocation's live `AbortSignal`;
- `publish({ persist?, update? })` backed by native acknowledgement.

A publication receives a strictly increasing sequence number. JavaScript runs `publication.update` synchronously only after native persistence accepts the generation. It then reports the same live provider object's current catalog through `provider_models_catalog`. Config-form callbacks may return a replacement model array directly; object-form callbacks may update private state and expose the result through `getModels()`.

### Generation-safe native coordinator

The new `src/extensions/provider_models.zig` owns stable per-provider state:

- monotonic safe-integer generations;
- active invocation cancellation;
- registration state;
- serialized publication and catalog commitment;
- retained provider-specific error text and JavaScript stacks.

Starting a newer refresh supersedes and aborts the older generation before it can publish. Every persistence mutation and catalog replacement rechecks provider registration, generation identity, invocation identity, and cancellation while holding the provider lock. Duplicate or out-of-order publication sequence numbers are rejected.

Registry reads and snapshot replacements are globally serialized because separate extension workers may otherwise replace the shared registry concurrently. Provider names are owned throughout refresh execution, fixing a discovered use-after-replacement hazard when the first catalog commit rebuilt registration storage.

### Upstream-compatible two-phase refresh lifecycle

Each selected dynamic provider runs:

1. an offline/cache-only phase using the stored credential without OAuth network refresh;
2. an online phase only when permitted, after canonical credential resolution and OAuth refresh;
3. optional `force` propagation only to the online phase.

OAuth refresh remains serialized under the canonical auth-store transaction, so model refresh cannot reproduce the credential-refresh hang fixed upstream. API-key credentials are projected as complete JSON credentials. A missing usable online credential skips the network phase without discarding the restored cache.

Refresh results report cancellation and retain errors per provider instead of rejecting the entire provider set. Selective provider lists ignore unknown and static providers.

### Provider-owned persistence

The new `src/extensions/models_store.zig` implements the upstream `models-store.json` envelope:

- provider-keyed `ModelsStoreEntry` objects;
- `models`, optional `lastModified`, optional `checkedAt`, and optional verbatim `etag`;
- shared/exclusive advisory locking through a sidecar lock file;
- atomic 0600 replacement;
- preservation of unrelated provider entries;
- a 16 MiB safety bound;
- cancellation checks immediately before the authoritative atomic replace.

Publication semantics are exact:

- omitted `persist` leaves storage unchanged;
- an entry writes provider-scoped state;
- `persist: null` deletes provider-scoped state;
- `update` runs only after the selected storage operation commits and the generation is still current.

Both persisted model arrays and live catalog arrays are validated through the effective provider configuration before mutation. Invalid JSON, invalid envelopes, invalid model definitions, stale generations, and cancellation leave the committed catalog/store unchanged.

### Startup, registration, selector, reload, and unregister integration

`src/main.zig` now owns the model-refresh runtime alongside the provider registry and OAuth runtime.

- Startup restores cached extension catalogs before the final client pool is published.
- Dynamic provider registration performs an immediate offline restore.
- The interactive model selector performs the online refresh before presenting the catalog.
- Client runtime providers and the live model catalog are repointed after each accepted replacement.
- Reload supersedes active generations before worker shutdown, preallocates replacement provider state, commits the new registry without allocation after the ownership boundary, and preserves persisted catalogs.
- Explicit unregister aborts the active generation and deletes provider-owned persisted catalog state.

### Verification hardening

The production bridge E2E executes the actual `src/extensions/js_bridge.mjs` and covers config-form and object-form providers, immutable contexts, offline/online force policy, write/omit persistence, synchronous update ordering, catalog publication, stale generation rejection, abort, JavaScript rejection stacks, and worker reuse.

The structural checker spans the production JavaScript bridge, Zig worker protocol, provider registry, canonical credential storage, OAuth lifecycle, model-store implementation, generation coordinator, startup, dynamic registration, reload preparation/commit, unregister, and selector refresh wiring.

Native regressions cover cached startup, OAuth refresh before online discovery, force, persistence, reload preservation, rejection stacks, explicit deletion, invalid-persist rollback, stale generations, duplicate sequence rejection, cancellation, no partial catalog/store mutation, unregister cleanup, and post-abort worker reuse.

## Source delta from checkpoint 182

The production/test patch changes 11 files:

- 2,113 inserted lines and 7 deleted lines;
- new `src/extensions/models_store.zig`;
- new `src/extensions/provider_models.zig`;
- new production refresh bridge E2E and integration checker;
- JavaScript bridge/runtime, registry, OAuth/storage, root exports, and main lifecycle integration updates.

The exact patch is `CHECKPOINT-182-to-183.patch`; machine-readable statistics are in `checkpoint-183-patch-report.json`.

## Verification

Using the uploaded Zig 0.16.0 toolchain, the frozen working tree passed:

- JavaScript and Python syntax checks;
- checkpoint-181 provider-method production bridge E2E and 13/13 structural checks;
- checkpoint-182 provider OAuth production bridge E2E and 22/22 structural checks;
- checkpoint-183 provider refresh production bridge E2E and 32/32 structural checks;
- focused provider-refresh tests: 7/7;
- focused model-store tests: 6/6;
- Zig formatting across all production Zig sources;
- source audit: 195 Zig files, 119,746 Zig LOC, zero synthetic source files;
- default `zig build -Duse-llvm=false --summary all`: 3/3 steps;
- complete `zig build test -Duse-llvm=false --summary all`: 997 passed, 7 intentional skips, 0 failed; 13/13 build steps.

All required gates are repeated from a fresh extraction of the exact final ZIP. The external `pi-zig-v8-checkpoint-183-FINAL.verification.json` and transfer-verification sidecar are the final archive evidence.

## Remaining parity work

Checkpoint 183 completes extension dynamic model discovery/publication/persistence, but material provider gaps remain:

1. bridge `streamSimple(model, context, options)` as a native event stream with ordered partial events, usage, tool calls, terminal status, errors, and cancellation;
2. complete remaining object-form native `Provider` auth/filter/stream semantics where they are not represented by config-form callbacks;
3. support any remaining custom request/payload/response hooks required by streamed providers;
4. retire obsolete JavaScript callback generations after native acknowledgement instead of retaining them until unregister or worker shutdown.
