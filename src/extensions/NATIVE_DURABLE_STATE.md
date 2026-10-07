# Native committed document state and adoption visibility

This additive slice follows frozen observer/context/invocation patch 8deabdcd.
Authority is durable and Chord at 7fb59f995b0a1db552001a8577b234e4105d7179,
captured through the original officially built packages. Production code is Zig
and the linked C VM, without host Node execution.

Public Session/Harness `documentState` attaches to one committed document
incarnation. Its readonly `value` is hydrated before acquisition resolves.
Subscriptions hydrate synchronously with BACKGROUND_CONTEXT and sequence zero;
each subscription independently serializes later asynchronous callbacks. At most
100 deliveries wait behind one callback. Overflow preserves the hydration and
the newest pending value/context/sequence according to Source. Unsubscription
discards pending work while leaving a running callback caller-owned.

Publication delivers complete committed values without applying or re-diffing
them. Definition-version changes publish a replacement; a migration with no
operations for an observer already on the new shape emits no delivery. Retirement
publishes null and binds the old state permanently to the retired incarnation.
Disposal and Session close detach the source, preserve the last published value,
and permit later hydration of that retained value. Listener errors are queued as
asynchronous VM jobs and subscriber delivery resumes independently.

The native Transaction now has an optional after-storage adoption callback. Only
the owner VM facade installs it, and the callback verifies the transaction owner
thread before touching VM roots. Generic native scheduler/worker transactions
retain the null default. Prepared cache adoption allocates before admission,
then transfers its prepared ownership before commit listeners run. Adoption is
idempotent, and no-op drafts preserve their original snapshot reference.
Publication uses the canonical committed cache value so snapshots, watches and
state observations share Source's object identity.

Ended task invocations now abort their owner signal with an Error bearing the
Source task-specific message. Escaped Runtime calls throw distinct Errors with
the same message. Source completion/idle waits can finish before the invocation
ends; the authentic fixture waits for the actual abort event.

Original captures cover adoption/listener visibility and reference identity,
synchronous hydration, slow versus fast subscriber progress, disposal/close,
retirement/recreation, 102 updates and exact overflow sequences, and ended error
type/message/identity. Exhaustive native allocation failures cover state
construction, subscription, queued publication, synchronous delivery, detach and
disposal, in addition to prior document and watch allocation gates.

Remaining work is explicit: full mutation-aware Chord normalization, final
validation before checkpoint predicates, complete Proxy/pending-acquisition and
task-document owner/fork contracts, generic Chord mutable/replica/source exports,
source-contract gap/error reporting across host policies, full registry/builtin/
context-range/agent/conversation APIs, arbitrary user Storage, and original
SQLite physical-format interoperability. Active Context-waiter allocation
failure coverage and every reflection/custom getter edge case remain separate.
Focused Windows/Linux tests do not certify macOS runtime or the full composed
distribution. Prior frozen donors are unchanged; Root owns those release gates.
