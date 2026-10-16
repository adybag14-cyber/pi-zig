# Native AF resolving pending fatal: separate source successor over F06

Root approved source-only implementation after the concrete F06 audit. This
candidate has no execution grant and no runtime qualification. The accepted
focused TLA packet and Root's concurrent F06 core regression retain their
original source/artifact identity; this successor is a different C candidate.

The only product file is vendor/quickjs/quickjs.c. Both native-body resolving
JS_Call sites now check for an actually pending uncatchable reason immediately
before freeing output/result. They move that reason into an owned local,
free both local values, retire the native state, restore the same reason and
return false. The direct START caller then returns JS_EXCEPTION, while the
existing resumed callback/reaction job returns failure to the host boundary.

The START caller's failed cleanup also holds an existing pending fatal reason
over Promise and state release. This matters when the resolving call already
settled that Promise with a returned/rejected object whose last owner may be
released by the failed caller. The reason is transferred between owned local
and runtime exception slot without duplication, replacement or retagging.

The guard does not classify ordinary C enqueue OOM as uncatchable, infer error
identity from a name, alter native error generation, reject the fatal again,
add module attribution, add state/GC fields, change Promise helpers, or change
the public ABI. Native resolving paths with no pending fatal take the existing
ordinary return/rejection/catchable-failure code. The bytecode TLA code is
unchanged from F06.

Four desired-terminal controls were prepared in the separate audit checkpoint
486b45cbce912396892924cb16d392fb826f47d1. They use genuine native AF factories
and the actual public Promise RESOLVE hook for RETURN, and actual public host
rejection tracker for REJECT (the RESOLVE hook does not run on rejection).
Each has a direct START and a resumed raw-job variant. The resumed hook filters
the exact owned native outer Promise, avoiding an unrelated Promise failure.
Each verifies one callback, exact fresh private fatal identity/classification,
and raw JS_EXCEPTION or negative JS_ExecutePendingJob status. Unexpected
Promise results and raw reasons are owned before assertions so the predicted
old-code failure does not leak and mask the primary outcome.

No tests have been syntax-checked or executed for this new successor. The
prepared build snippet is separate from the shared build.zig. Actual metadata
must include every selected/imported mandatory test; no hand-assumed count
substitutes for a metadata capture.

Catchable resolving/enqueue pressure, thenable-job adoption failure and the
pre-existing native Await queued-callback/inactive-state safety edge identified
in the audit remain separate controls. This fix introduces no new early
termination for these two completion sites: they already retired native state
when their intrinsic callback returned success. No broader AF lifecycle/core
qualification is claimed. Root and independent C-owner review precede any
composition or native execution.
