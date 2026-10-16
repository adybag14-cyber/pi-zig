# Shared thenable fatal conversion: design only, before independent C review

Root approved a separate source proposal for the two traced conversions and
explicit public BEFORE/AFTER hook boundaries. No shared Promise C implementation
is changed here. Current product C is E334 (native resolving guards plus native
Await inactive guard); old C409/F06 proofs retain their exact identities. No
compiler, formatter, Node, Source generator or native runtime job ran.

## Two concrete conversions that a native-only fix cannot cover

1. js_promise_resolve_function_call reads resolution.then. If its getter
   actually throws with current_exception uncatchable, the current code
   unconditionally gets/clears that exception and calls
   fulfill_or_reject_promise(..., true). It returns undefined with an ordinary
   rejected Promise and no active pending exception. C409's later native guard
   cannot recover a consumed fatal reason, nor should it infer one from a
   rejected value.
2. js_promise_resolve_thenable_job calls the actual then function. If that call
   actually throws an uncatchable reason, the current code gets/clears it and
   calls args[1] to reject. The job returns undefined/success. For a native AF
   return, the native state already retired after scheduling this adoption job;
   no native resume guard can repair the later conversion.

Public Promise BEFORE/AFTER hooks in the second helper can also leave a pending
fatal reason while returning void. A BEFORE fatal currently does not stop the
then call, and an AFTER fatal with a normal then result is not inspected. These
are current-exception boundaries, not rejected-Promise/value classification.

## Proposed minimal product surface

Limit edits to js_promise_resolve_function_call and
js_promise_resolve_thenable_job. No change to fulfilled/rejected value semantics,
module attribution, private generation tagging, JS_EnqueueJob, general Promise
reaction handling, public ABI, context fields or serialization is proposed.

At every proposed boundary, a fatal exists only when JS_HasException(ctx) is
true and the actual current exception is uncatchable. Never inspect the bit,
name or tag of a supplied resolution/rejection value to classify an operation.
Do not reset the bit, retag, replace the error, or reject it again.

For the resolution.then getter, check that condition immediately after
JS_GetProperty, before testing the returned sentinel/value. Capture the exact
pending reason outside current_exception, free the owned then result (which
can be JS_EXCEPTION or a successful value with a pending host reason), and
return JS_Throw of that same owned reason. Caller-owned resolution/Promise are
borrowed and must not be freed by this helper. Ordinary getter exceptions keep
their existing rejection conversion; no-active-fatal paths retain existing
behavior, including ordinary rejected values whose internal Error happens to
carry an uncatchable flag.

## Deferred job hook ordering and first-reason policy

Initialize the owned result and two resolving function values with undefined
before any early cleanup path. Preserve existing successful/catchable ordering.

- After BEFORE, an active fatal is retained immediately and stops the then
  invocation. No AFTER is emitted because then was not invoked; no further
  guest code executes. This is an explicit host-fatal abort rule, not an
  ordinary hook-order change.
- Once then was invoked, preserve the existing paired AFTER call, including
  when then threw. If then left an active fatal, retain an owned duplicate of
  that exact reason BEFORE invoking AFTER. Keep the original current exception
  visible to the hook, matching current behavior. This owned reference is
  allocation-free and survives a hook consuming or replacing current_exception.
- Re-read the currently configured hook/opaque for AFTER as existing code does;
  do not change normal hook replacement/removal semantics in this repair.
- After AFTER, if no earlier fatal was captured, capture its actually pending
  uncatchable reason. If a first fatal already exists, a later hook failure
  cannot replace it. Do not create or infer a fatal from a successful hook
  return or from a rejected argument.
- With a captured fatal, free the owned then-call result and both resolving
  functions once, then JS_Throw the retained first reason and return
  JS_EXCEPTION. Cleanup/replacement exceptions are superseded by that first
  owned reason. Do not invoke args[1] in this path.
- With no captured fatal, keep the previous ordinary JS_EXCEPTION-to-rejection
  conversion and successful return path. Ordinary/catchable BEFORE/AFTER
  behavior is deliberately unchanged, including any existing replacement of
  an ordinary thrown reason by another ordinary host hook reason.

The paired AFTER recommendation is a review decision: it preserves the hook's
existing completion notification when then was actually invoked while retaining
the first fatal before any downstream callback. Independent review should
confirm this policy before C authoring; do not silently switch to skipping
AFTER for a thrown then call.

## Ownership and context evidence

In the getter helper, resolution and s->promise are borrowed from the actual
resolving function/caller. The returned then value is owned. The synchronous
caller must keep its context valid through JS_Call, as before; native AF also
owns native_ctx during this call. No lifetime is inferred from a filename,
ambient module or Promise result.

The deferred job's argv retain the actual Promise, thenable and then callable.
The locally created args[0]/args[1] own resolving functions and are released
once on every post-creation exit. The then-call result is independently owned.
A captured raw fatal reference remains rooted by normal C API ownership over
all local cleanup and is consumed once by JS_Throw.

JSJobEntry.ctx is a raw context pointer: JS_EnqueueJob does not duplicate it.
This design does NOT claim that the then function's realm necessarily owns the
job context (a callable can be from another realm). The existing host must keep
that job context valid through JS_ExecutePendingJob and its argv cleanup. The
Engine owns its context throughout its job pump; cancellation/runtime teardown
already free job argv through the runtime. No new context ownership mechanism
or GC edge is introduced here. Cross-realm/job-lifetime controls remain required
for any wider host lifecycle claim.

## Prepared control plan before execution (not authored/run yet)

1. Actual native AF RETURN with a then getter that invokes a genuine fatalStart:
   raw START returns JS_EXCEPTION with exact fresh reason, not rejected Promise.
   Repeat getter path on a resumed native RETURN to require a negative job result.
2. Actual native AF RETURN schedules thenable adoption normally; actual then()
   later invokes fatalStart. The native AF has already retired. Running that
   adoption job must return a negative status with the exact pending reason.
3. BEFORE public hook reports fatal: then-side-effect counter stays zero,
   observed hook sequence contains BEFORE only, and raw job fails exactly.
4. AFTER hook reports fatal after normal then(): observed order remains
   BEFORE/then/AFTER, raw job fails exactly, cleanup is complete.
5. then() reports first fatal and AFTER reports a second distinct fatal. The
   observed order stays paired; the first reason survives. A later generation
   must not erase earlier fresh identity at the same host boundary.
6. Ordinary raw getter/then throws, cleared historical native reasons and named
   lookalikes keep exact ordinary Promise rejection behavior. Normal resolution,
   Promise adoption and hook order remain unchanged.
7. An already rejected value carrying an uncatchable Error flag but with no
   pending exception stays an ordinary rejected value. Test both reject(value)
   and adoption of an already rejected Promise. This specifically rejects the
   invalid inference from a value's bit/tag alone.
8. GC between scheduling and adoption, ordinary cross-realm callable ownership,
   multiple callback attempts, and owned teardown are separate required controls
   before broad lifecycle/resource claims. Do not weaken context/job admission.

Catchable enqueue/allocation pressure remains separate: plain C
JS_ThrowOutOfMemory does not mark a private native fatal. This proposal does not
alter its classification or claim recovery of every failed adoption allocation.
Root and independent async C review must approve scope, ordering and cleanup
before implementation/composition. No new C behavior is qualified by this design.
