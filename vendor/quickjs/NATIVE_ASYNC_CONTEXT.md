# Native execution scopes for asynchronous provider callbacks

The pinned upstream is QuickJS-NG v0.17.0, commit
`6d46d07d04041b40f4f49eaa7fdebe44c314c699`. Original upstream hashes are
`9fd0e0e68856d165e2872140ac38889845b53eb1bc55150f8598a53eb86948f5` for
`quickjs.c` and
`747a77444ff04a910b57ca51dd998d7ee46895b1b9592d7d6051fd180317c44d` for
`quickjs.h`. The normalize/localeCompare allocator corrections in
`NATIVE_ABI_FIXES.md` and the kept-object behavior in
`NATIVE_WEAKREF_KEPT_OBJECTS.md` remain present. No sanitizer or safety option
is disabled.

Upstream's Promise hook does not bracket ordinary reaction jobs or intrinsic
async/await continuations. A Promise hook alone therefore cannot preserve an
invocation scope. The local embedder API `JS_SetExecutionContext` stores one
opaque JS value rooted on Runtime. `JS_SetExecutionContextHook` invokes a native
callback before and after each queued job, including error returns.

Ordinary jobs capture the current execution context when enqueued. Promise
reaction records instead capture it when `.then` or intrinsic `await` registers
the reaction; that retained value is passed to the eventual job even if another
scope resolves the promise. Each reaction marks its retained value for cycle GC
and releases it on disposal. Queued jobs duplicate the value, and release it
after execution or runtime cancellation/destruction. Runtime initialization and
destruction initialize/release the current value. Setting a context and invoking
the hook do not call any JavaScript property or mutable prototype method.

The Zig scope token is a private native class. It contains an owner-only context
pointer and activation/deactivation callbacks, and is never published to user
JavaScript. Native timers capture and trace the token at registration. Entering
a callback exchanges its binding snapshot, action queue, signal, SDK context and
UI dialog/component state; leaving restores the previous scope. Retiring the
token detaches its native context pointer before ticket storage is freed.
Ordinary JavaScript bookkeeping can still run in retained jobs/timers, while
native action/context/UI capabilities reject the retired token. A retired scope
cannot borrow a later ticket's mutable binding or a later owner's context.

WeakRef kept objects are cleared only after the outer scope and its ready jobs
have ended; an internal getter await cannot turn into an accidental checkpoint.
The existing native memory-owner C ABI and captured pristine WeakRef intrinsics
are preserved.

Real CLI and worker tests exercise a four-callback admission barrier, exact
Source ModelRuntime results, distinct A/B snapshots and UI bridges, immutable
begin snapshots despite later view changes, one AbortSignal, task cancellation
without retiring siblings, owner retirement, late timer bookkeeping with blocked
actions/UI, and allocation ownership. JSON contains no native scope token or
pointer. Provider ticket messages are bounded, owner/generation checked, and
single-use operations are never replayed after an uncertain response.
