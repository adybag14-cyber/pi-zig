# Actual native Node microtask checkpoint

This unit ports the selected explicit Node 24.13 checkpoint onto the actual C VM job queue. The native Queue owns charged storage, suppression/scope counters and native completion callback pairs. It does not implement a guest queue.

The retained upstream revision is def0bdf8abee441cfcbf793a8dc24a6f3b899573. Full selected queue/header/task-queue files, the exact selected Runtime_ReportMessageFromMicrotask excerpt with acquisition offsets, and the V8 license are retained under authority.

The native drain preserves the failed job continuation for ordinary reporting and restores the caller continuation before termination cleanup, deferred native AFTER or completion callbacks. Active termination retires the old queue; a cancelled stopped round preserves later live work. Callback mutation uses the original vector for the current round and a copy for the next round. Kept WeakRef targets are cleared only after completion callbacks.

The terminal path reduces actual invocation owners. A successful empty checkpoint does not poll or service a request-only termination. Ordinary and generic actual exceptions use the existing Engine capture path; actual private termination remains a typed native event.

## Source review

The 20 declared controls use actual C jobs, native callback pairs, actual termination requests/cancellation and actual GC/WeakRef observations. Source peers cover all 20 controls and the production owner. The original predecessor bodies and the narrow terminal, failure-cleanup, WeakRef and distinct-FIFO corrections are retained.

The build proposal installs one test artifact with the existing callback Engine dependencies. It does not run it. The source manifest and peers are source evidence only.

## Integration requirements

The VM termination C/header foundation and the exact reviewed Engine/gateway intake must be installed with this unit. The embedding must provide the genuine native report_message_from_microtask operation. The observation callback in the tests qualifies queue ordering/ownership only and is not an implementation of MessageHandler or Node's fatal-exception listener.

No native build or runtime execution, public Node bootstrap installation, report operation implementation or application qualification is claimed by this packet.
