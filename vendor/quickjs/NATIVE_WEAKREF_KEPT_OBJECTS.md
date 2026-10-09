# WeakRef kept objects and native host checkpoints

The pinned upstream is QuickJS-NG v0.17.0, commit
`6d46d07d04041b40f4f49eaa7fdebe44c314c699`. The original upstream `quickjs.c`
SHA256 is `9fd0e0e68856d165e2872140ac38889845b53eb1bc55150f8598a53eb86948f5`.
The original upstream `quickjs.h` SHA256 is
`747a77444ff04a910b57ca51dd998d7ee46895b1b9592d7d6051fd180317c44d`.
The existing correctly typed normalize and localeCompare allocator adapters
documented in `NATIVE_ABI_FIXES.md` are preserved.

Upstream creates a weak record without performing ECMAScript
`AddToKeptObjects`. A temporary target can therefore disappear immediately
after construction or a successful deref, even before the current JavaScript
job and its promise microtasks finish. The local C patch retains one duplicate
of each distinct object or nonregistered-symbol target in a runtime-owned
list. These references are external GC roots, using the same reference-count
root accounting as queued job arguments, so cyclic targets also survive GC.
Construction and successful deref both add the target; every allocation-error
path releases its unpublished weak records.

`JS_ClearKeptObjects` releases the list contents, retaining reusable empty
capacity. It refuses to clear while a JavaScript caller frame is active: a
nested C callback that pumps promises cannot end its caller's execution job.
Runtime destruction releases all kept roots and the backing allocation.

The Zig owner calls the API only when no promise jobs remain, after draining
ready jobs, after a completed await, before an await moves to another timer or
I/O turn, and at admission of the next outer invocation. It never clears
between queued promise microtasks. No stronger cache is added to Markdown or
any SDK lease, and no GC, sanitizer, or safety option is weakened.

`src/native_weakref_test.zig` compares constructor, deref and symbol behavior
against a fresh actual V8 observation from Node 24.14.0/V8 13.6.233.17,
retained at `src/extensions/fixtures/weakref-kept-objects-v8-20261009.json`.
Additional tests prove cyclic root retention through nested C callbacks,
collection after the host checkpoint, partial C-heap allocation cleanup,
and reuse after heap exhaustion. The checked-in vendor manifest records the
actual final C, header and provenance-document hashes.
