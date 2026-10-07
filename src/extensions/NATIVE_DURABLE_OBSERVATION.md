# Native document watches, Context and invocation lifetime

This additive slice follows the frozen documents patch. Source authority is the
official built durable/Chord implementation at 7fb59f995b0a1db552001a8577b234e4105d7179.
Production implementation is Zig and the linked C VM, with no host Node runtime.

Session/Harness `watchDoc` acquires on the mutation line. It owns one persisted
document incarnation, keeps the acquisition value until delivery, installs one
listener, and serializes asynchronous delivery as owner VM promise jobs. Pending
delivery retains at most 100 exact frames; overflow replaces the pending queue
with the newest value and a root replacement. Retirement delivers null and
`["r", null]` before terminating. Stop, cancellation and Session close detach
subscriptions and resolve `closed` immediately; a running callback remains owned
by its caller. Listener failures preserve Error identity or convert other values
to Error. Value/closed accessors are readonly and nonenumerable.

Preparation stages original document operations in the native transaction arena
independently of storage representation. Selecting a checkpoint base retains the
prepared operations for publication. Storage and publication are both assembled
before storage admission. Retirement publications use the canonical replacement.

Runtime `snapshot`, `snapshotAsOf` and `watchDoc` forward on the owner. Watches are
retained by the actual native invocation and stopped before aborting its signal
when that invocation ends. Source keeps a Runtime and watches alive across
running phases of one invocation. Per-phase broker ledger admission remains
fenced, while public Runtime operations now use the underlying retained native
Invocation lifetime. Context and cancellation signal identity are shared across
those phases. An ended invocation rejects escaped Runtime operations.

`@earendil-works/chord/context` exports BACKGROUND_CONTEXT, TODO_CONTEXT,
createContextKey, withContextValue, withAbortSignal, withoutAbortSignal,
withCancel and awaitWithContext. Keyed values and parent contexts are VM roots.
Cancellation rejects only the waiter and preserves the underlying promise.
Without cancellation the original promise identity is returned. Raw cancellation
reasons become AbortError DOMExceptions; Error reasons retain identity.

Actual original captures cover pending/start/stop ordering, checkpoint operations,
retirement, cancellation, listener failure, Session close, 102-frame overflow,
Runtime/context/signal identity across phases, ended-runtime fencing, keyed
Context forwarding, waiter-only cancellation and queued acquisition cancellation.
Exhaustive native allocation failures cover watch construction, subscription
admission, queued-frame ownership and detachment. The watch GPA test is explicitly
named to match the public VM build filter.

Remaining parity gaps are explicit:

- Replicated `documentState` and complete Chord replicated-state/root exports.
- Full mutation-aware Chord normalization and checkpoint-predicate ordering after
  native final validation, as listed in the prior document contract.
- Complete registry/builtin/context-range/agent/conversation runtime APIs and
  Source error/report fidelity; arbitrary user Storage and original SQLite format.
- All Context prototype/reflection edge cases, arbitrary malformed Context inputs,
  custom signal getter side effects and exhaustive allocator failures of active
  Context waiters are not certified by the constructor/watch allocation tests.
- No macOS runtime claim follows from Windows/Linux focused qualification. Root
  owns exact composed distribution and hosted macOS gates.

Prior frozen donors remain unchanged; this slice is qualified incrementally.
