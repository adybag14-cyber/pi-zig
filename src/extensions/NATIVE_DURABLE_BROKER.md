# Durable owner request broker

This is the native thread/lifetime foundation for the still ongoing public task
facade. It does not itself certify Source task phase dispatch or recovery.

`Broker.call` is a worker-only boundary taking an owner generation, task ID,
invocation generation and native JSON value. It clones the payload into a
request-owned arena before admission to a bounded 64-request FIFO. A callback
is never carried to the worker. `Broker.drain` checks owner-thread affinity and
owner generation; the task/invocation identity reaches the owner's dispatcher
for its additional native runtime-lease validation.

Requests own their reply, event, cancellation flag and two references: one for
the caller and one for the queue or active callback. Cancellation and close can
settle a caller before an active callback returns without freeing that callback's
request. Owner allocation failure settles all waiting requests; a later healthy
drain remains usable. The owner must close, join its leased workers, then deinit.

The Engine pump has separate durable context/pump/deinit slots, so transport
control callbacks and durable callbacks retain their own contexts. A pending
VM promise can wait on this pump even when no transport control pump is set.
The callback and every QuickJS operation still run on the engine owner.

The reusable synchronization-only notifier lease is:

```
host_owner_notify_context: ?*anyopaque
host_owner_notify: ?*const fn (?*anyopaque) void
```

A worker copies this pair while on the owner and calls it only to signal the
transport's native event. It must not read Engine or CVM values on a worker.
The transport keeps the notifier context alive until durable cleanup has closed
and joined workers. Cleanup runs before dropping transport control callbacks.
The idle wire loop drains after resetting the wire event before waiting, so a
background notification arriving between the first pump and reset is retained.

Actual worker tests prove owned UTF-8 JSON replies, stale generation rejection,
owner-only asynchronous C VM callback delivery through Engine.awaitValue,
queued cancellation, close before joins, close inside a callback, and allocator
failure followed by healthy reuse. A native transport test forces the notifier
to arrive precisely between the initial pump check and wire-event reset; its
second owner drain observes that reset and delivers the request before sleep.

The initial unfrozen prototype's stale-generation test exposed an error-path
double free because constructor errdefers remained active after publication.
The corrected staged cleanup runs only before admission; the negative crash
receipt remains in evidence. This does not modify any earlier frozen donor.

The public scheduler adapter, runtime-value roots, full task/invocation ledger,
registry update handling, and native Session lifetime lease across scheduler
finalization are subsequent required work. Broker primitives and a notifier
lease are not complete public Harness parity or a switch-off gate for the
existing extension bridge.
