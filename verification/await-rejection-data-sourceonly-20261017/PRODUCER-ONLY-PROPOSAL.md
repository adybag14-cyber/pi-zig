# Separate shared direct-OOM callback producer proposal (inactive)

No implementation in this proposal is applied. The active packet changes no
native_node_function, native_class, native_sdk.fail, Engine, C or H bytes.

## Actual current producers

`native_node_function.fail` 18–21, `native_class.call` 30–32 and
`native_sdk.fail` 237–240 return Engine.throwNativeOutOfMemory() for a trusted
direct Zig `error.OutOfMemory`. Engine creates the actual native error, records
its private generation and returns JS_EXCEPTION, but does not mark that reason
uncatchable. A guest catch or intrinsic Promise executor can therefore consume
the producer error before an outer leaf guard sees it. This is an event at the
callback boundary, unlike a later fulfilled/rejected DATA value carrying its
tag. The native AF adapter already marks direct OOM locally; several leaves
duplicate variants of that producer policy and some capture independent fatal
holders for live global Promise constructors.

## Minimal proposed source unit for separate approval

Introduce one producer-only Zig callback-failure helper used by those three
actual C callback exits. Inputs are Engine and the *actual error union* returned
by the callback. Direct OutOfMemory is trusted host failure. Preserve an actual
current pending fatal before creating a new error. If no prior pending fatal,
create/retain the actual OOM reason, tag using the existing Engine generation
mechanism, mark that exact reason uncatchable and return JS_EXCEPTION with that
same owned reason pending. Keep chosen fatal owned outside pending while
retiring any displaced diagnostic/native-allocation tracking values and draining
finite native-finalizer exceptions; the final throw sees an empty pending slot.

For JavaScriptException, preserve actual pending-first C exception transport.
Do not mark a retained diagnostic slot or callback argument merely because it
has a private tag or flag. An explicit captured failed-operation boundary may
still use the existing exact freshness helper; a whole-callback starting
generation is not a substitute for the operation's boundary after guest getter
prework. Non-OOM native error mappings retain their existing Source error brands.
No changed success/constructor receiver semantics or namespace metadata.

Before authoring this helper, inspect Engine.throwNativeOutOfMemory's tracking
release: it takes the new exception, then frees the old tracked error before
putting the new reason back. A native finalizer on that old value can establish
a pending reason. The producer helper must own and drain these actual events
and maintain first-fatal identity; simply adding SetUncatchableError around the
existing call without an ownership proof is insufficient. If that requires an
Engine helper change, propose that exact change separately rather than silently
editing Engine or claiming three callsite additions close cleanup behavior.

## Required real controls before replacing per-leaf guards

- Genuine GPA failing allocation inside ordinary function callback, arrow
  callback and actual class constructor. Native guest catch/finally must not
  swallow the trusted event; raw reason identity/private tag retained.
- Actual live Promise constructor: intrinsic consumes executor exception;
  subclass then returns, throws ordinary value, invokes another native failure,
  or retains/reinvokes executor. A producer bit alone cannot retain a first
  consumed exception across later guest work. Existing per-invocation fatal
  holders remain necessary until the VM's consumed-event frontier is solved.
- Actual pending ordinary/fatal reasons plus finalizers on old captured/native
  tracking values; preserve first actual fatal while freeing all displaced
  owned values. Ordinary historical marked DATA is never a new producer event.
- Old tagged DATA and fresh-after-suspension tagged rejection DATA enter Source
  catch unchanged; same object actually thrown again uses actual pending-event
  policy. Old flags are neither universally cleared nor globally trusted.
- Unsigned generation wrap and exact raw identity; real cancellation/budget
  interruption remains on the actual C3 fatal event channel.

This proposal fixes a common *producer* policy. It does not authorize deleting
leaf handlers for captured failed operations, first-fatal executor retention,
or C3 error transport before independent review and actual runtime gates.
