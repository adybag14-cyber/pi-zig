# Diagnostics channel registry and Channel core

This source-only packet ports the complete retained `Channel` and `ActiveChannel` declarations, their activation/deactivation helpers, store wrappers, and the public `channel`, `subscribe`, `unsubscribe`, and `hasSubscribers` functions. It is based on the retained Node `diagnostics_channel.js` authority and current Main `c248553d15282e1e8ad896382c78132b6a501dd9`.

The owner retains one canonical weak registry per Engine. It creates the registry through the existing complete `WeakRefMap` owner and the supplied genuine internal/util `WeakReference` class. Store maps use the existing `SafeMap` owner. Both SafeMap and SafeFinalizationRegistry must already be bootstrapped; there is no late replacement of public constructors. Cached acquisitions preserve identity and reject conflicting process, error-binding, or WeakReference inputs. A linked assembly stack rejects same-engine reentry even across a nested second Engine.

## Actual dependency boundaries

`Inputs.process` must be the installed native process default. The original live `process.nextTick` method schedules subscriber/transform failures and captures the existing native async scope. `Inputs.trigger_uncaught_exception` is the required actual internalBinding('errors') function and receives the original reason and `false`; the core never replaces it with JS_Throw or a fabricated Error. The production uncaught report/exit adapter is still unadmitted. The control driver supplies a native observation binding that records these exact calls and their captured scope; it does not certify production reporting or process exit.

The complete public diagnostics_channel namespace remains pending. TracingChannel and its adapters are not implemented or published by this packet. The exported private core object exists for composition with the future complete owner, so all eventual tracing/public channels can share this registry. There is no private module.require-only registry and no partial public builtin admission.

## Shared projected changes

Six original primordials are captured during the existing pristine Engine initialization: Array slice/indexOf/push, Object getPrototypeOf/setPrototypeOf, and Symbol.hasInstance. The additions preserve every preceding byte outside the exact insertion spans.

The actual existing internal/errors argument owner now creates and caches the complete original validateFunction, using its canonical hidden ERR_INVALID_ARG_TYPE and unchanged hideStackFrames wrapper. The raw anonymous nonconstructible function has arity two. Existing Inputs, Exports, and all prior definitions remain intact. The two validator projections were prepared by validation_controls and independently reconstructed from their five finite additions before incorporation here.

## Behavior and controls

The source preserves typed errors, direct constructor registry replacement, symbol/string key identity, prototype transitions, shallow Symbol.hasInstance, subscriber snapshots with live length reads, duplicate subscription counts, store replacement counts, reverse store nesting, and actual ReflectApply rest-array behavior. Store iteration uses the retained original indexed entry reads and genuine for-of/IteratorClose behavior.

Lexical frame ownership follows the linked VM: the final entry and store/transform locals survive through the later run call; the onMessage local survives the following length check and resets at the next try-block entry; a catch reason remains live even if a nextTick override immediately executes and discards its callback. The nested slice call retires its argument before an assignment setter. Native fatal/cancellation provenance remains outside ordinary source catches.

There are 47 named source controls. Forty compare the native owner against an exact retained original function/class body in separate fresh instances of the actual linked VM, with the same real dependencies. Seven native controls cover canonical cache/conflict and missing-input gates, genuine weak collection, nextTick async-scope capture, two fatal paths, and A-to-B-to-A owner acquisition. Causal finalizer controls cover the reviewed lexical retirement cases. The original fixture contains only a dependency-capture wrapper and exact original core body; its inverse is recorded.

## Validation status

Only source writing and bounded static inspection have been performed. No native compiler, linked runtime, Node process, original fixture, formatter, or production source generator ran for this packet. The compiled metadata count and runtime result are null. Root must review the exact patch, compose shared changes, then obtain fresh exact-head compilation and runtime evidence. Source acceptance is not runtime or whole-application qualification.
