# Native AsyncFunction resolving-site audit: F06, source-only

Exact reviewed C:
`F06F1F2A23CB024FF381DB02CF43D1C249DE5848689D005918F7D1FB80BE9B5E`.
This audit changes no C, Engine, public ABI or module attribution. No test,
compiler, Node, generator or native job ran. Four standalone desired-terminal
controls are prepared in `src/native_async_resolving_pending_test.zig`; their
expected F06 failure is a static prediction, not an executed negative.

## RETURN: concrete public Promise-hook path

The native body returns a scalar (JS_PI_AF_RETURN). Native resume invokes its
intrinsic resolving_funcs[0]. js_promise_resolve_function_call goes directly to
fulfill_or_reject_promise for the scalar. That function first marks the outer
Promise fulfilled, then invokes the real public JS_PROMISE_HOOK_RESOLVE hook.
A hook can leave an exact uncatchable exception pending. The helper continues
with reaction enqueue and returns void; its resolving callback unconditionally
returns JS_UNDEFINED. JS_Call does not convert pending exception into an
exception return.

Native resume checks only JS_IsException(result), frees the successful result,
terminates the native state and returns true. The pending reason is not
necessarily destroyed, but the required failure is not delivered:

- At START, native_call returns the fulfilled Promise instead of JS_EXCEPTION.
  Engine.checked recognizes only exception returns, so a successful direct
  caller can bypass capture while current_exception remains pending.
- On a later resume, js_async_function_resolve_call's native branch returns
  JS_UNDEFINED. promise_reaction_job sees a successful handler, and the Await
  extension's undefined capability functions cause it to return undefined.
  JS_ExecutePendingJob tests only JS_IsException(res), returns +1, and never
  reports that pending uncatchable reason to the host capture boundary.

The standalone controls use the actual public Promise hook, actual genuine
native body factory and raw call/job APIs, with no top-level module wrapper
that could accidentally catch the pending reason via its own fixed guard.
The hook disarms before creating a fresh private native fatal reason. Each
control owns unexpected Promise results and raw exception values before
assertions, preserving clean teardown even for the predicted negative.

## REJECT: different concrete callback, not inferred symmetry

The public Promise RESOLVE hook is explicitly skipped for rejected Promises.
There is no direct RESOLVE-hook injection path through resolving_funcs[1].

The actual reject callback still calls fulfill_or_reject_promise, which marks
the outer Promise rejected, then invokes the public host rejection tracker
for a new unhandled rejection. That tracker can leave an uncatchable reason.
The intrinsic reject callback returns JS_UNDEFINED. Native resume frees its
original ordinary rejection reason, terminates, checks only exception return,
and returns true. START and resumed callers then miss delivery by the same
actual return/job checks described above.

The rejection controls therefore use JS_SetHostPromiseRejectionTracker and
filter the unhandled callback on the exact native outer Promise for resumed
execution. The native body throws an ordinary raw object first; only the host
tracker supplies the fresh fatal reason. A native body that itself throws an
uncatchable reason already takes the existing early fatal branch and is not
the missing case.

## Enqueue OOM is a distinct classification

fulfill_or_reject_promise ignores js_enqueue_job_context's integer result and
removes/frees each reaction anyway. js_promise_resolve_function_call also
ignores JS_EnqueueJob failure for adoption of a returned thenable. These paths
can leave a pending OOM despite a successful resolving callback. For reaction
enqueue failure, the outer Promise is already settled but a dependent Promise
can remain pending; for failed thenable-job enqueue, even the native outer
Promise can remain pending.

The ordinary C JS_ThrowOutOfMemory implementation does not set the uncatchable
bit or private Engine native-allocation generation. Its error must not be
relabeled a fresh native fatal merely because its name/message resembles OOM.
The four prepared controls address proven pending uncatchable host reasons;
catchable enqueue-pressure recovery needs an explicit policy/control of its
own. No global Promise-helper repair is proposed by this audit.

## Narrow direction for review

At each native resolving JS_Call, inspect pending uncatchable state immediately
before freeing output/result or native roots. Retain that exact raw value
outside current_exception over cleanup, terminate through the existing native
path, restore it and return false. This yields the already-supported START
JS_EXCEPTION or resumed reaction-job exception. Do not reject the fatal again,
retag it, add a module owner, or change ordinary rejection behavior. Any C
implementation still requires Root direction and independent review.

The existing native Await path already checks zero-plus-pending after
perform_promise_then. A separate ownership edge remains relevant to review:
a public handled-rejection tracker can leave an uncatchable reason while
that helper successfully enqueues a native continuation. The early fatal
branch terminates the state, but the native resolve callback has no inactive
guard before native_step reads native_function. This pre-existing queued-
callback safety path is not introduced by resolving-call guards (those sites
already terminate on successful completion); it needs its own focused control
before broader lifecycle qualification.
