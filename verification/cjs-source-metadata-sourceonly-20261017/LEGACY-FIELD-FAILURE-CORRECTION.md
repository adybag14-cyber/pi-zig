# Metadata legacy capture failure and raw logical locations

This additive source successor preserves the original 3a7c1c13 packet. Independent
review found that the new logical CallSite field correctly left an actual
allocation reason pending, but the legacy build_backtrace caller did not stop
before constructing an array/calling prepareStackTrace/restoring its saved slot.
In particular, a numeric logical URL uses a genuine allocating atom-to-string
conversion. The failure was not an invented rejected-data/fatal-bit case.

The legacy builder now returns a private status only on a metadata-affected
field/format failure, owns the actual current reason before releasing initialized
frame fields, and skips later guest preparation. Presence is recorded before
taking the slot. An earlier actually pending owner is retained; a later actually
pending uncatchable cause may supersede an ordinary earlier owner, while the
first fatal remains first. Absence sentinels and unrelated flagged values are
never admitted as failures. Both successful capture and all default metadata-NULL
paths retain their previous call ordering/ignored-error policy.

The private status passes through actual capture_error_stack callers. A local
tracked boolean in the error-production format chain prevents only this newly
reported failure from being overwritten by JS_ThrowError2's legacy JS_NULL
fallback. No Engine field, public ABI/tag, global Promise/error-policy change or
name-based fatal classification is introduced. Existing embedding callback
negative statuses are normalized to the old <0 contract so a host's integer -2
cannot fabricate the new internal metadata status. Other direct builder owners
release their object only after the exact reason is owned.

The C default logical-location append now uses the genuine atom string and
JS_ToCStringLen plus dbuf_put(length). It holds any actual entry reason while
converting/appending, restores that exact slot on success, and protects the
selected current reason over native/string cleanup on failure. This keeps NUL
and following characters as data; the physical/default filename formatter
retains its previous path. No logical name becomes an import referrer.

Two more prepared controls bring this source packet to fifteen named metadata
declarations, still uncompiled/unqueried/unrun. The real legacy allocator sweep
compiles a recursive function with numeric logical URL, removes the native
capture owner, configures an actual prepareStackTrace callable, and exercises
64 genuine captured frames. The actual JS_NewError callback records its pending
reason and preparation count before outer bytecode exception handling can
recapture an ordinary error. Every measured native backing event is failed once
in a fresh VM (limit512), retained causes must remain identical, a failed creation
must not have run preparation before returning, GC is exercised, and all native
backing blocks must retire. Old legacy array/prepare conversion behavior outside
the metadata-field failure remains explicit; this is not an exhaustive logical
allocator-position or whole legacy error-policy claim. The second real VM test
checks a default formatted Error.stack string contains the full NUL-bearing
logical name after actual function invocation. Original 3a source/proofs, the
original eighteen-row Node observer, old compiler controls and all primaries
remain intact. No jobs or source execution occurred.
