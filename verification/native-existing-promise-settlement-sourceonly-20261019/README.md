# Existing intrinsic Promise settlement

This source-only unit exposes `JS_PiSettlePromise(ctx, promise, value, is_reject)` for a native caller that must settle an existing genuine Promise. Both operands are borrowed. The result is an owned `undefined` or the exception sentinel with an actual pending reason. Callers continue to use their existing guest-operation completion boundary.

The original Node v24.13 V8 API identifies `Promise::Resolver` with the same Promise object: `GetPromise` casts that object, and `Resolve` / `Reject` skip work only when the Promise is no longer pending. They otherwise call the genuine `JSPromise` resolution or rejection machinery. This differs from the per-pair one-shot latch of ordinary ECMAScript resolving functions.

The implementation extracts the linked VM's existing resolution tail without changing its operation order, Promise hooks, ordinary rejection handling, current uncatchable handling, then lookup, or queued thenable work. The only four substitutions in that tail replace `s->promise` with its borrowed Promise argument. The original resolving-function entry retains its original latch, argument choice and debug selection. The new native entry checks an actual pending exception before brand access, rejects non-Promise receivers, and skips a settled genuine Promise before observing the supplied value or allocating any resolver wrapper. If a tail operation publishes an actual current exception, the native entry returns the exception sentinel for its normal caller boundary to handle.

Repeated native calls during thenable adoption are permitted while the target remains pending. A later direct fulfillment or rejection can settle the target before earlier queued thenable work runs. That queued work still invokes its originally selected then function through the unchanged VM job, and later settlement attempts cannot replace the already published result.

## Authority and exact change

The complete original public files are retained without rewriting:

- `authority/v8-api.v24.13.cc`: 489,340 bytes, SHA-256 `573F6F992A93EB59751953A372F9071E32AEB36D9B6F5328BD50967D3008F201`.
- `authority/v8-objects.v24.13.cc`: 272,859 bytes, SHA-256 `81E1D4EDFCE90BC1409DDF1B16966F2931E8DC947BF7429DFED6959708211BFC`.

They come from Node v24.13.0, commit `def0bdf8abee441cfcbf793a8dc24a6f3b899573`, under `deps/v8/src/api/api.cc` and `deps/v8/src/objects/objects.cc`. The separate explicitly authorized downloads only acquired and verified source bytes; no fetched source was executed. Original notices in those files and the unchanged 3,093-byte `authority/V8-LICENSE` (SHA-256 `6AB33AF8774A0F396EE3AEEB761E3229057682D6F9FA7F572E390C2CB3A6E509`) are preserved.

`source-design.json` holds the bounded actual V8/QuickJS excerpts and API policy. `production-delta.json` holds the complete old resolving-function body and exact replacement, plus the new declaration; reversing its two edits reproduces the original C/H files. `control-observation-successor.json` preserves the one peer-requested post-failure observation correction. `build-intake.patch` adds six install-only lines using the existing shared QuickJS build.

## Authored controls and limits

The root declares 17 controls over real linked-VM objects and jobs. They cover:

- Same-object settlement, intrinsic creation and borrowed result identity.
- Settled and primitive fast paths under an actual failing positive-allocation limit.
- Synchronous live then lookup, queued call receiver and genuine Promise then override.
- Repeated direct settlement during adoption and the unchanged ordinary resolver latch.
- Self-resolution, ordinary getter throw, noncallable then, flagged returned DATA, foreign realm Promise and proxy rejection.
- Actual entry-pending identity and a published uncatchable getter failure with only retained own-data progress observations.
- Actual thenable-job and reaction-job allocation failures, including already published state and retry behavior.
- Native-finalizable operand markers showing caller ownership and actual job retention through live GC.

QuickJS limit zero is unlimited. The allocation controls use limit one, which makes every positive VM allocation fail against a zero effective ceiling, and restore zero afterward. Ordinary VM allocation failure is checked as the actual pending null fallback. It is kept distinct from a real flagged Error published by `JS_Throw`.

These are authored source controls, not execution results. The controls use real QuickJS programs and native APIs; the original V8 evidence is source evidence. This unit does not claim a completed FSReqPromise/AsyncWrap owner, a public Node filesystem graph, an Engine cancellation contract, or new behavior for arbitrary raw Promise callers that omit their normal completion boundary. Existing linked-VM promise hook and reaction behavior is preserved, rather than independently expanded here. Root owns all subsequent build, metadata, process-closure and runtime qualification.
