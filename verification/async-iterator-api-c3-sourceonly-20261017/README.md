# Genuine VM GetAsyncIterator C API — SOURCE-only candidate

Base d19e0d206a05be23e37a1c53c8c9a503491d0d23, actual C3 C=DA14DFBB7E73DED032E9FCD742FD2E49FDAF45273F48D24D6089018539601614 /
H=A79E75A40D34C9E7CAFB9AB31359B7EE925FE205636603F2022CF764CFC18346.
Root explicitly authorized this narrow C/H export and actual VM tests. No Main,
Engine, qualified C3/C4 proof tree, other intrinsic or old observer is edited.
This candidate does not include separate C4 readonly-query/CallSite deltas.

JS_PiGetAsyncIterator(ctx,obj) is an executing acquisition operation, not a readonly
query. ctx must be a valid live owner-thread context; obj is borrowed and belongs
to its runtime. Same-runtime cross-context values are supported. Foreign-runtime
objects/invalid C pointers violate the existing QuickJS C API precondition and
are not passed to the VM to provoke undefined behavior. The owned iterator or
JS_EXCEPTION result follows normal C API ownership.

The only acquisition algorithm is the existing static JS_GetIterator(ctx,obj,true).
Its actual C3 implementation reads the well-known asyncIterator property first;
nullish selects sync iterator acquisition and JS_CreateAsyncFromSyncIterator.
Native async override is returned by identity. Sync fallback captures sync next
once and the real VM retains its sync iterator/next references. The returned value
is an iterator object, not a complete iterator record: the native consumer must
capture its async next method once, exactly where the Source algorithm does.
No hand-built adapter, Promise implementation, branding or guest JS code is added.

Pending-entry policy is explicit: ANY already pending exception returns JS_EXCEPTION
before getter/call work, leaving the exact pending reason/flag owned by the VM.
After delegation, any pending result is normalized. The original reason is taken
into an owned local before freeing the owned returned value. An already fatal
reason remains first; a new fatal cleanup reason wins over an ordinary original.
Otherwise JS_Throw restores the same owned original reason. A flagged returned
DATA value with no actual pending exception is returned normally, without flag
inference or mutation.

Native callbacks must obey the real C API exception-return convention. The API
cannot undo internal guest work already performed when a native callback violates
that contract by returning a value with a newly pending exception. The genuine
VM control includes a proper exception-return getter and a deliberate violation.
It records the violation's actual getter/method/finalizer counts and checks only
post-call ownership/pending-reason guarantees, not an invented no-work guarantee.
Our actual native producer/callback exit guards remain a separate responsibility.
This wrapper does not broaden or patch JS_GetIterator or every C3 intrinsic.

src/extensions/native_async_iterator_api.zig is the direct owned-return Zig binding.
Its caller owns/stores/frees the iterator and propagates Engine.checked failure.
Source-only Agent response consumers may use it once Root selects the exact C/H
composition. It must not be emulated on older C or silently fall back to old
manual adapters.

Twelve actual VM test definitions are prepared in native_async_iterator_api_test:
async override/identity/receiver/lazy-next; array+string actual language for-await
vs acquired iteration; immutable well-known identities under mutable global Symbol;
captured sync next; raw getter/next/thenable rejections; return/throw/for-await break;
bad values/results; ordinary+fatal pending entry/no-getter; same-runtime cross-
context realm; borrowed input/adapter GC lifetime; flagged nonpending returned data;
new pending result cleanup and native callback convention violation observations.
These use the actual linked VM and native C factory, not an adapter in fixture JS.
The isolated build/test steps are added but not attached to default tests. They
have not been compiled, parsed or run. There is no new expected/observed/golden data.

The earlier archived pure-language Source56 for-await/yield* proposal/controller
remains unchanged and separate. Its source callers are not executed here and no
Node24 semantic pass is claimed. These VM controls validate the new API boundary;
they do not turn same-VM language comparison into independent Node24 authority.
The existing VM's AsyncFromSync value-rejection/close behavior remains exactly its
original implementation and still needs the full genuine Source56 qualification.

Required next gates are independent Min SOURCE review, Root intake of exact narrow
delta, then a separately admitted native job. Root must compose with accepted C4
and any CallSite changes and rerun the actual original C3 controls/full JSON plus
all new API controls; no C3/C4 wholefile rollback or proof reuse is allowed. All
runtime, pending-hook, allocator/resource and full-Agent claims remain false here.
No Node, compiler, parser/AST, native, generator, benchmark or capture job ran.
