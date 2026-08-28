# Checkpoint 185 — reconstructed full tree and production `streamSimple` bridge

Checkpoint 185 repairs the empty checkpoint-184 transfer and implements extension-defined `streamSimple(model, context, options)` from the intact checkpoint-183 base.

## Repository completeness repair

The checkpoint-184 ZIP supplied for continuation contained no source files. This checkpoint therefore reconstructs from checkpoint 183 and embeds the complete current upstream reference in two forms:

- **1,366 extracted files** at `upstream/pi-main/`;
- the untouched source ZIP at `upstream/source-archive/pi-main-20260823-194058.zip`.

Every extracted upstream file was compared byte-for-byte with its ZIP member. The resulting audit reported zero missing files, zero extras, and zero hash mismatches. `UPSTREAM-PI-MAIN-COMPLETENESS.json` and the two upstream SHA-256 manifests record that proof.

## Production JavaScript event stream

`src/extensions/js_bridge.mjs` now exposes a real `AssistantMessageEventStream` compatibility implementation rather than the former no-op shim. It provides:

- asynchronous iteration and terminal-result delivery;
- a **64-event** and **1 MiB** queued-buffer bound;
- a **512 KiB** per-event limit;
- a **16 MiB** cumulative invocation limit;
- one native acknowledgement per event before the iterator advances;
- cancellation-aware iterator reads;
- bounded `iterator.return()` retirement;
- shutdown rejection of every pending stream acknowledgement.

The dedicated `provider_stream_simple` protocol invokes the callback on its exact persistent owner worker with deeply frozen model, context, and option snapshots plus a live `AbortSignal`.

## Event protocol validation

Both sides enforce a strict stream state machine:

- `start` exactly once and before partial events;
- independently indexed text, thinking, and tool-call blocks;
- ordered, positive sequence numbers bound to one invocation ID;
- text/thinking start, delta, and end;
- tool-call start, argument deltas, and completion;
- exactly one `done` or `error` terminal event;
- rejection of open blocks at termination and of events after termination;
- validation of upstream stop-reason classes;
- JavaScript stack propagation for provider rejection.

UTF-16 high surrogates split across separate JavaScript delta events are held until a matching low surrogate arrives. Unpaired or incomplete surrogates are rejected. The native end-to-end regression verifies that `A` plus split rocket-surrogate halves plus `B` becomes `A🚀B`.

Tool-call argument deltas are retained as partial JSON. Final arguments are compared semantically, not by object-key order, on both the JavaScript and Zig sides.

## Native runtime and model-client integration

`src/extensions/js_runtime.zig` adds the event/ack transport and rejects wrong invocation IDs, duplicate/out-of-order sequences, malformed events, and native callback failures. Protocol failures close the worker rather than allowing a later request to consume stale records.

`src/extensions/provider_stream.zig` is the native adapter. It:

- projects native messages and tools into upstream context JSON;
- supplies provider/model identity, API, credential projection, base URL, headers, compatibility flags, sampling parameters, thinking settings, token/context limits, model cost, session affinity, and cache retention;
- accumulates text, reasoning, tool calls, usage, diagnostics, response IDs, response-model identity, and terminal metadata into an owned `ModelResponse`;
- emits live native deltas without borrowing worker-owned strings;
- converts cancellation and rejection into non-replayable `aborted`/`error` assistant responses;
- waits for JavaScript iterator completion before accepting the protocol summary.

`ClientPool` now selects this adapter as a real `ModelClient` whenever the active extension provider owns `streamSimple`. Extension OAuth is resolved immediately before every call, preventing a long-lived selection from handing an expired projection to the provider.

Startup and reload wire the stream runtime to the active provider registry. Registry replacement is rollback-safe and rebinds the stream runtime only when the new registry commits.

## Verification

The reconstructed source passed:

- JavaScript syntax validation;
- provider-method bridge E2E and **13/13** structural checks;
- provider-OAuth bridge E2E and **22/22** structural checks;
- provider-model-refresh bridge E2E and **32/32** structural checks;
- provider-stream bridge E2E and **18/18** structural checks;
- focused native stream integration, including real split-surrogate handling;
- Zig format validation;
- real-source audit: **196 Zig files**, **121,515 Zig lines**, zero synthetic source files;
- default Zig build: **3/3** steps;
- complete Zig test graph: **1,000 passed**, **7 intentional skips**, **0 failed**, **13/13** build steps.

The final release process repeats the required gates from a fresh extraction of the exact downloadable ZIP and records the result outside the ZIP as well.

## Deliberate remaining parity gaps

This checkpoint establishes the core custom-provider stream path but does not claim total provider parity. Remaining work includes:

1. generation-acknowledged retirement of obsolete callback IDs;
2. explicit active-stream cancellation on unregister/reload with forced worker recycling for an iterator that continues executing after abort;
3. complete object-form `filterModels` behavior;
4. custom request/payload/response transformation hooks;
5. deferred-response fetch/cancel callbacks where a provider exposes them;
6. broader adversarial reload/unregister/shutdown concurrency coverage.
