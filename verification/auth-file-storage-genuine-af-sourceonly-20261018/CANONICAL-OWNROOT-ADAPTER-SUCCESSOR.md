# Canonical root admission and final adapter successor

Root authorized the one SDK-owned ownRoot addition. This candidate copies only
`native_sdk_owned_completion.zig` from immutable source-closed
`62ded415ce3ebdeb99fb17b6a1ccf1b48b9dd54b`, SHA256
`C4354FAE45DB2C30E64EC8161C3F9E5EE7C27D73C3DB53F8ED4E79515368E04F`.
Its original 11357-byte 41AA prefix is unchanged. Independent core Source
review CD583672 is retained beside this document. No adapter/runtime closure
is inferred from the helper's review.

The actual File/lock get, call, global, text, object, constructor and function
results now normalize the checked raw result at their exact operation boundary
**before** canonical ownRoot admission. They do not invoke convenience
Scope.get/call/own first. Direct spread arguments, iterator roots and new AF
arithmetic/callback roots use that same admitted path. A local StateWriter
facade supplies own/get as well as put to private body.init/stage/action and
recorded-action snapshots, avoiding hidden raw Scope.own calls. It contains no
escaping pointer; Completion is returned inactive and entered only at its
actual caller address. Shared Scope, Engine, Body and C remain unchanged.

Independent review also found the adapter's callback argument was allocated
before its live push getter. The callee is now captured first, then the real
arrow is created, then push is called. The completed expression's short Scope
still retires before iterable callbacks. A new actual getter arms a real GPA
failure; the callable it returns delegates the genuine original push. The
failure must occur during callback creation after one getter and before any
push call. No constant-success substitute or invented result is used.

The historical b953 overflow control incorrectly expected the guarded Engine
OOM API to create fresh B under an already-retained fatal A. That API actually
returns A without advancing its generation. The historical test is preserved
in that commit and is now corrected: the ordinary-B profile still checks exact
first A; the guarded-producer profile checks exact A, already-marked status and
no new birth. It does not claim a fresh low-level B or a second allocator fault.
The previously unmarked retirement profile *without* held A remains a distinct
existing control and retains its original fresh-birth assertions.

There are fourteen authored native controls, all uncompiled/unqueried/unrun.
No original output or expected fixture was authored. Every original assertion
except the explicitly documented invalid guarded-producer expectation is
retained. Older candidates/manifests remain intact. The latest
`canonical-ownroot-adapter-prepared.json` is the cumulative current seal.
Actual DATA-safe AF1116/Bfb composition, Root grant, metadata and runtime
verification remain mandatory. Inherited synchronous constructors/functions,
full custom-fs/heartbeat behavior and whole SDK/application qualification remain
outside this finite adapter claim.
