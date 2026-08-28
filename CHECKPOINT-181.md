# Checkpoint 181 — production provider callback invocation and OAuth adapters

Checkpoint 181 repairs checkpoint 180's misplaced provider encoder and carries provider method descriptors through a real JavaScript-worker-to-Zig invocation path. The result is a tested callback transport with persistent worker ownership, asynchronous error propagation, cancellation, re-registration semantics, and native OAuth refresh/key/model-projection adapters.

## Implemented

### Production JavaScript bridge

`src/extensions/js_bridge.mjs` now:

- encodes function-valued provider members in the actual `pi.registerProvider(...)` path;
- recursively preserves nested object methods and callable array entries;
- binds each function to its original owning object so `this` semantics survive;
- keeps closures and function source inside the extension worker rather than serializing them;
- emits JSON descriptors with `__pi_callback_id`, `__pi_callback_kind`, and `__pi_callback_path`;
- rejects cyclic and non-JSON provider registrations before mutating the live provider snapshot;
- implements upstream-style named re-registration as a shallow, defined-value merge;
- keeps the previous registration callable across the deferred native-action handoff;
- removes all retained callbacks on explicit provider unregister;
- dispatches `provider_method` protocol requests and awaits synchronous or asynchronous callbacks;
- delivers a live `AbortSignal` where the native caller requests it;
- returns JavaScript exception stacks and promise-rejection stacks to Zig.

### Native runtime protocol

`src/extensions/js_runtime.zig` now exposes `Runtime.invokeProviderMethod(...)`. It validates JSON argument arrays, writes a provider-method request to the persistent worker, reuses the existing invocation/abort watcher, and returns an owned JSON value envelope.

The production-runtime regression exercises:

- closure retention;
- receiver binding;
- nested array methods;
- asynchronous success and rejection;
- JavaScript stack propagation;
- live native abort delivery;
- old/new callback generations during re-registration;
- transactional cyclic-registration rejection;
- unregister cleanup and subsequent worker reuse.

### Descriptor ownership in the provider registry

`src/extensions/provider_registry.zig` now:

- recursively validates every callback descriptor in incoming and effective provider JSON;
- rejects descriptor paths that do not match their actual configuration location;
- associates each descriptor with the persistent JavaScript runtime that registered it;
- preserves callback owners when a later data-only registration shallow-merges omitted methods;
- routes ownership by callback id **plus path**, avoiding misrouting when different workers independently generate the same callback id;
- performs replacement transactionally so a failed parse, ownership check, runtime resolution, or registry rebuild leaves the previous provider intact;
- fixes a replacement failure-path double-free inherited from the prior registry implementation;
- exposes generic `invokeProviderMethod(...)` and `hasProviderMethod(...)` operations;
- adds typed adapters for `oauth.refreshToken`, `oauth.getApiKey`, and `oauth.modifyModels` with JSON shape validation.

### Runtime-owner integration

`src/extensions/host.zig` and `src/main.zig` now preserve the worker owner at all existing provider registration entry points:

- startup manifest registrations;
- registrations emitted during a later extension action;
- full extension reload reconstruction.

Unregister and reload teardown continue to remove the native registrations before their owning workers are discarded.

### Verification hardening

The checkpoint-180 copied helper was replaced by a standalone Node E2E test that launches the **actual** `src/extensions/js_bridge.mjs`. The marker-only production check was replaced by 13 structural integration checks spanning the bridge, runtime, registry, host, and three live registration call sites.

## Descriptor and invocation contract

Manifest descriptor:

```json
{
  "__pi_callback_id": "provider:<encoded-provider-name>:<ordinal>",
  "__pi_callback_kind": "provider_method",
  "__pi_callback_path": "oauth.refreshToken"
}
```

Native request:

```json
{
  "kind": "provider_method",
  "callbackId": "provider:demo:1",
  "args": [{ "refresh": "..." }],
  "appendSignal": true,
  "abortable": true,
  "invocationId": "..."
}
```

Successful worker response:

```json
{
  "ok": true,
  "result": { "value": { "access": "..." } }
}
```

## Source delta from checkpoint 180

Seven production/test files changed before checkpoint metadata was added:

- 1,052 inserted lines and 97 deleted lines;
- `src/extensions/js_runtime.zig`: +266/-1;
- `src/extensions/provider_registry.zig`: +491/-4;
- `src/extensions/js_bridge.mjs`: +96/-10;
- `src/extensions/host.zig`: +9;
- `src/main.zig`: three registration call sites changed;
- production E2E/checker tests: +187/-79.

The final real-source audit reports 192 Zig files, 116,394 Zig LOC, and zero synthetic source files.

## Verification

Using the uploaded Zig 0.16.0 toolchain:

- JavaScript production bridge syntax: passed;
- production bridge E2E: passed;
- production integration checker: 13/13 passed;
- standalone `ProviderMethodRef` test: 1/1 passed;
- focused production runtime test root: 17/17 passed;
- focused OAuth owner test root: 17/17 passed;
- focused callback-id collision test root: 17/17 passed;
- Zig formatting checks: passed;
- default `zig build -Duse-llvm=false`: 3/3 build steps passed;
- complete `zig build test -Duse-llvm=false`: 982 passed, 7 intentional skips, 0 failed; 13/13 build steps passed.

The same required gates are repeated from a fresh extraction of the final ZIP. `CHECKPOINT-181-VERIFICATION.json`, the packaged logs, the SHA-256 file inventory, and the external transfer-verification record contain the machine-readable evidence.

## Remaining parity work

This checkpoint establishes the generic callback transport and three callable OAuth adapters, but it does **not** claim full TypeScript provider parity. The next work remains:

1. integrate extension OAuth `login(callbacks)` with the live `/login` UI interaction protocol and credential storage;
2. persist refreshed OAuth credentials and invoke the new refresh/key adapters from every live auth-resolution path;
3. bridge `refreshModels(context)` including credential, stored catalog, network policy, generation-checked `publish`, and cancellation;
4. bridge `streamSimple(model, context, options)` as an event stream rather than a one-shot JSON result;
5. support complete object-form native `Provider` registration semantics, including auth/filter/stream methods;
6. retire obsolete JavaScript callback generations after native acknowledgement instead of retaining them until unregister/process shutdown;
7. add end-to-end login, model refresh, streaming, reload, and unload tests at the actual CLI call sites.
