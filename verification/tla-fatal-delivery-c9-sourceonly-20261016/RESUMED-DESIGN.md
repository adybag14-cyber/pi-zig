# Resumed TLA fatal bookkeeping: design for review, not implemented

This design follows Root's request after the explicit resumed-body negative
control. It proposes no execution and no change to Engine/private error tags,
native AsyncFunction semantics, promise reactions or ambient runtime state.
The current C remains `333ABF5DC0CD17259C77B7A578D321C9836EC92199DAB413DD30EBCB29554F1A`.
Root and independent C-owner review must precede authoring the additional C
surface described here.

## Concrete path

At current 6b94, `js_async_function_call` allocates a JSAsyncFunctionData and
runs the module's bytecode body through its first await. `js_execute_async_module`
gets only its intrinsic Promise, then attaches module fulfilled/rejected
handlers. Later, an existing async resolve/reject object invokes
`js_async_function_resolve_call`, which resumes the same JSAsyncFunctionData.

If that resumed body throws an uncatchable reason,
`js_async_function_resume` returns false and terminates its state without
rejecting its Promise. The reaction job correctly delivers the raw exception
to the host. But no module handler runs, so the exact module remains
EVALUATING_ASYNC with a pending Promise and no stored fatal outcome. A cached
entry or fresh importer can hang after the host handles the first exception.

The new prepared negative control records this exact distinction: first host
delivery remains correct, while cached module and reimport must also terminate.
No execution has established the prepared control's result yet.

## Minimal association

Add a private, initially NULL `JSModuleDef *module` to JSAsyncFunctionData.
Do not bind ordinary async functions, native-body async functions, generators,
or synchronous module execution to a module.

Extract the current bytecode async-call body into an internal helper that
accepts an optional exact ModuleDef argument. Keep the existing
`js_async_function_call` callback signature as a wrapper passing NULL, preserving
the class-array call function ABI. Only `js_execute_async_module` passes its
actual `m`. The synchronous module body's call remains the NULL wrapper.

Bind `s->module = m` only after initial `js_async_function_resume` succeeds,
has no pending exception, and leaves `s->is_active` true. This is the point
after successful START and before dropping the call's local state reference.
An already completed or ordinarily rejected initial body needs no association.
Initial fatal START remains unassociated and uses the existing initial DFS
failure bookkeeping. No output-state handle, Promise inspection, filename
lookup, import.meta lookup or ambient current-module heuristic is needed.

## Ownership evidence and required ordering

The module pointer is a borrowed identity, not an independent GC owner. Its
lifetime is dominated by the active bytecode coroutine's existing function
root, with these concrete C9 ownership paths:

- `async_func_init` duplicates `func_obj` into `frame.cur_func`.
- `async_func_mark` marks that function while the bytecode state is active.
- `mark_children` for FUNCTION_BYTECODE marks `b->realm`.
- Bytecode construction/read duplicates its actual creating context into
  `b->realm`; the module's runtime function retains that same bytecode through
  `js_create_module_bytecode_function`.
- `JS_MarkContext` directly marks each context-loaded ModuleDef's owned values.
  The module definitions themselves are context-owned and not standalone GC
  objects. `JS_TAG_MODULE` is not an independent lifetime root.
- A module reaches evaluation only after resolution/linking; the legacy
  unresolved-module sweep does not free a resolved, active module.
- Final context teardown frees the loaded ModuleDefs. While an active async
  continuation is reachable, its rooted bytecode realm retains that owning
  context. During unreachable-cycle collection there is no resume callback;
  terminating/freeing the coroutine must not dereference its borrowed module.

Accordingly, fatal bookkeeping must occur while `s->is_active` and before
`js_async_function_terminate` frees `frame.cur_func`. Termination clears the
borrowed association before freeing any frame roots, for ordinary completion,
ordinary rejection, fatal completion and GC finalization alike. The general
free path never dereferences the pointer. This needs no new context refcount
or GC edge, avoiding an additional retained-context cycle. If independent
review cannot establish the existing active-frame ownership chain, the fallback
would be an explicit duplicated/GC-marked module owner context with balanced
free0 release; that larger lifetime change is not the recommended first patch.

Cross-context callbacks must not substitute their invocation context for the
module's owner. The module identity comes only from the module executor; its
actual runtime function/bytecode realm supplies the ownership chain. No context
membership conclusion is inferred from a pathname or the current stack frame.

## Fatal completion hook

At the common bytecode async-resume termination point, when `is_success` is
false because the current reason is uncatchable and `s->module` is non-NULL:

1. Call the existing allocation-free fatal worklist with the exact associated
   module and current pending raw reason, before releasing any frame roots.
2. Retain the reason via existing ModuleDef.eval_exception; mark the module and
   waiting async parents terminal. Preserve existing terminal ordinary errors.
3. Clear the borrowed association and terminate the bytecode state normally.
4. Return false with the original pending reason still present, so the same
   resolve callback and promise reaction job deliver it unchanged to the host.

The common point covers body failure and uncatchable resolving-call failure.
Ordinary rejection must keep its existing Promise rejection behavior and clear
the association on termination without marking fatal state. Cached retries use
the already reviewed fatal outcome bit, without retagging or resetting the
Error's uncatchable flag after host classification.

The existing bytecode await path checks `perform_promise_then`'s integer return
but can miss a pending exception on a zero return. The module-associated path
should additionally check pending exception immediately and enter the same
failure path; leave unassociated ordinary async behavior unchanged. Successful
initial START has no association yet, so its executor's existing pending-reason
guard continues to own that initial boundary.

If a module was already terminalized by a failed outer module attachment while
its body remained suspended, a later continuation must not execute that body's
guest instructions. A module-associated resume guard should terminate that
state, clear its association and return its stored reason without recreating
it. This guard needs focused review because the host may have cleared the
reason's uncatchable flag; it must not turn an old reason into a newly tagged
OOM. The existing module outcome remains terminal regardless of later queue
delivery details.

## Controls before any broader claim

The existing separate resumed negative control should become a positive
terminal cached/reimport control only after the hook is implemented and passes.
Add a waiting parent and cycle/shared-parent cases; resumed ordinary raw,
lookalike and historical errors must remain exact rejected Promises. Include
two module instances with the same physical name to prove explicit identity,
reachable continuation across GC, cancellation/context teardown, and host
classification followed by cached entry/new import. Preserve the immediate
START and deferred-ancestor controls and the original Models05f negative.

No source/native/core qualification follows from this design. Full allocation
positions, context lifetime and leak accounting remain execution gates.
