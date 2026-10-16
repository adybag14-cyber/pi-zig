# Shared settlement callback fatal: separate successor over frozen 90cb

Root explicitly authorized three already traced operations in the same two
shared helpers. The frozen 90cb/38F implementation and prior design remain
review baselines, not rewritten proof. This source-only successor adds 17 C
lines; no jobs, compiler, formatter, Node or Source generator ran.

## Exact additional product scope

1. In getter ordinary-error conversion, immediately after the void
   fulfill_or_reject_promise(..., true), capture only an actually pending
   uncatchable reason before freeing the original owned ordinary getter error.
   Free that ordinary error once and return JS_Throw of the exact new fatal.
2. In deferred then ordinary-error conversion, immediately after intrinsic
   reject JS_Call, capture only an actually pending uncatchable reason before
   ordinary-error cleanup. Free the ordinary error once, then reuse the existing
   fatal_cleanup for its owned result and two resolving functions. Restore and
   throw the exact captured reason, without another rejection attempt.
3. In the shared resolver's existing done settlement branch, immediately after
   fulfill_or_reject_promise, return the exact actually pending uncatchable
   reason through an owned Get/Throw transfer. The resolution and Promise are
   borrowed, so no output/value ownership is released by this new branch.

These operations can invoke a real public RESOLVE hook or unhandled rejection
tracker while returning success/void. The checks occur at the actual operation
boundaries, never by inspecting a supplied rejection's name, tag or flag.
Earlier BEFORE, then-call or AFTER fatal paths have already branched away from
ordinary conversion, so conversion callbacks cannot replace a retained first
fatal. With no active uncatchable pending reason, the original ordinary
conversion and resolve/reject behavior remains unchanged, including catchable
pending callback behavior. No tag, module, context/GC ownership, ABI or broader
Promise-helper change is added.

The actual Promise may already be settled when its host callback reports a
fatal. This successor does not roll that state back or reject it a second time.
The callback-observed original data remains exact while the operation reports
the new fatal to the host boundary.

## New desired-terminal controls, all unexecuted

Three declarations extend the existing shared-thenable test file to eleven:

- Plain public Promise.resolve with an ordinary throwing getter and a real
  rejection tracker reporting a fresh native fatal. It checks raw JS_EXCEPTION,
  exact fatal identity, and exact original ordinary rejection data retained in
  the callback-observed Promise. No native AF call wrapper can mask this defect.
- A normal native return schedules adoption; the actual then method throws
  ordinary data. Before any handler/host await is attached, its real unhandled
  rejection tracker reports a fresh fatal. The raw adoption job must fail while
  the originally rejected data remains exact. GC runs before actual job delivery.
- Direct plain scalar Promise.resolve RESOLVE-hook and Promise.reject tracker
  cases. Fatal callbacks require exact raw failure; ordinary raw, cleared
  historical native and named lookalike callback reasons preserve the ordinary
  Promise return and do not acquire fresh fatal classification. Both cases
  verify the already settled original data, one callback and no repeated job.

All raw result/reason and callback-observed Promise values are owned before
assertions. The existing first-fatal-versus-second-fatal, normal hook replacement
and removal, flagged rejected-data/no-pending, and ordinary getter/then controls
remain in the same file. Actual metadata must select every declared/imported
test; eleven declarations do not replace a metadata capture or establish a
runtime result. The existing prospective build snippet remains applicable.

## Scope stop and remaining policy

Source expansion stops after these three explicit operation boundaries. INIT
hook behavior during Promise construction, other Promise/adoption helpers,
catchable enqueue/allocation recovery, or first-error policy inside generic
settlement/reaction machinery are not silently claimed covered. This does not
change fulfill_or_reject_promise itself or JS_ExecutePendingJob, nor attribute
nested ordinary async work to a module. Additional policy/control work requires
separate direction; no whole-Promise/core/application qualification is claimed.

Independent C review of the exact combined 90cb-plus-successor delta is required
before Root composition or an explicit execution grant.
