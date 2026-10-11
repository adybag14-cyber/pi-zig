# Private native allocation error identity

Native Zig callbacks can fail their host allocator while QuickJS still has
memory to construct an Error. The embedding must distinguish the actual native
error object from a user lookalike, a proxy, or a previously caught error
rethrown in a later operation. Error text and guest properties are insufficient.

The local Error-only union member retains the existing first JSValue used for
stack data, followed by a uint64_t host generation tag. JS_NewObjectFromShape
initializes the tag to zero for every actual Error. The existing Error GC mark
and finalizer continue to process only the first JSValue; the integer is not a
GC root or a pointer. No history list or map retains old exceptions.

The private embedding ABI pi_js_mark_native_allocation_error and
pi_js_native_allocation_error_generation checks the actual internal Error class
before accessing this member. These functions allocate nothing, call no guest
code, and access no properties. Proxy traps, modified WeakMap intrinsics,
frozen Error objects, altered messages and forged properties cannot affect the
tag. The declarations belong to the embedding's engine_abi.h, not the public
QuickJS JavaScript surface.

Engine.throwNativeOutOfMemory tags each genuine native failure with the next
u64 generation. Zero is reserved for unmarked values. Host boundaries retain
their existing generation checkpoint and compare wrapping u64 distances. A
second OOM during cleanup does not erase the first object's identity. Errors
created before the checkpoint and later rethrows remain JavaScriptException.
No JSNumber conversion or precision limit is involved.

Actual source-extracted C layout proofs for Windows x64, Linux x64 and Linux
AArch64 show unchanged JSObject size72 and union size24. Linux x86 uses the
32-bit NaN-boxed JSValue: the union grows12 to16 and JSObject grows36 to40
bytes. This four-byte cost preserves natural alignment. Allocation and memory
accounting use sizeof(JSObject). The private object layout is not a serialized
or public embedding ABI.

True QuickJS heap exhaustion can make JS_ThrowError2 fall back to null when an
Error itself cannot be allocated. Primitives remain unmarked and are not
classified by this mechanism; accepting an arbitrary user null would erase the
identity guarantee. This pre-existing fallback is intentionally conservative.

Focused Windows Debug tests preserve the original genuine error across two
native OOMs and reject user, proxy, stale and pre-scope objects. They cover u64
wrap, WeakMap tampering, frozen/altered Error objects, allocation-free tag
operations under exhausted VM memory, bootstrap failure and WeakRef GC release.
A separate unchanged full public-open failing-allocator sweep checks cleanup,
original raw causes, three actual closes and one report. These private-source
results require fresh Root composition and hosted OS/mode qualification after
integration; the cross-target layout proof alone is not runtime evidence.

This patch is additive to the existing native ABI, WeakRef, async-context,
iterator, binary-operator, PromiseResolve and ToNumeric changes. Their public
headers, behavior and provenance entries are preserved.
