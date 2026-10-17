# Raw owned result before local cleanup

Original negative: dc3861f98cf4430aa6bfcabc1b720e125d08c6be. Its ordinary-cleanup
manifest, source patch and complete-tree apply proof are retained unchanged.
Body accepted that candidate's ordinary unwind/provider cleanup improvement,
then found a narrower earlier boundary: Engine.checked(raw) can free an owned
successful getter result while a pending A exists, before the local reducer can
observe a finalizer's fresh private OOM B. A shared Engine edit is unnecessary.

Scope.ownSince now owns the ACTUAL pending event and diagnostic DATA separately
before releasing the raw returned owner. It retains the operation's pre-call
native allocation generation, drains actual events after raw retirement, ranks
first ordinary / first actual fatal, publishes the selected actual event, and
only delegates to checked when that raw-result boundary is clean. A raw exception
sentinel alone cannot classify historical captured DATA as a current producer.
Known callback error-union unwinds continue to use captureUnwind. No old flag is
admission authority. An initial fresh private A is classified before cleanup B.

Local get/global/call/construct/receiver/index/string/operator paths save their
generation BEFORE their actual VM operation. The ordinary callable constructor
no longer calls shared native_class.object: it performs the actual live
newTarget.prototype lookup through local Scope.get and creates the actual
JS_NewObjectProto receiver (or normal Object fallback) on that same local
owned-result path. Its callback result uses the saved pre-callback generation.
Socket Error/WeakMap constructors, callable re-entry, createOwned and live queued
index access no longer pre-check their raw result before local ownership.

A source call-site audit also found that Socket closeTick already required
createArrow while the new local helper only exposed ordinary/createMethod.
The actual additive arrow creator now retains callback roots/metadata, ignores
a call/apply receiver, and remains nonconstructible with no own prototype. This
matches the actual Root helper semantics; it is not a function prototype alias.

New causal controls are genuine native VM operations, all UNRUN:

* An unwrapped actual C getter returns its sole real opaque holder and leaves
  actual pending ordinary A, marked fatal A or fresh private nonfatal OOM A.
  Its finalizer raises ordinary B, marked fatal B, or fresh private nonfatal
  OOM B after a genuine failing GPA allocation. Pre-entry flagged captured
  history is present in every case and must remain DATA.
* Exercise that raw getter by actual property get, actual call, actual receiver
  prototype lookup, and actual construction with a Proxy newTarget through the
  same complete callable used by canonical Socket. The constructor body must
  not execute after failed prototype admission.
* Assert exact selected reason identity, expected real generation increments,
  no synthesized replacement C after Bfb retained the first fatal, exactly one
  getter/finalizer, zero constructor-body effects, real allocation failure and
  popped invocation ownership. No fake OS handle/provider/process is used.

The fifteen-product projection still retains RootBfb Engine, generic function,
shared Scope, native_class, Buffer/encoding and C/H exactly. Existing dependency
APIs, adopter receiver-first ABI, whole-call synchronous write metadata, same
Pool/Lease qualification defaults-off and standalone wake owner remain unchanged.
Older inherited-stdio/Socket/closepool receipts are not receipts for these bytes.
Independent finite source review is pending; physical IO, ABI/runtime, complete
child/public net/TCP and default activation are explicitly unqualified.
