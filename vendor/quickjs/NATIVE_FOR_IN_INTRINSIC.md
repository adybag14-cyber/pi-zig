# Native for-in iterator boundary

`JS_PiForInStart` duplicates a borrowed source value and transfers that copy to
the existing `build_for_in_iterator` implementation. Success returns an owned
VM iterator whose existing class marker traces the source/prototype graph.
Failure leaves the original context exception and returns `JS_EXCEPTION`;
the existing builder consumes its source copy on every path. The caller keeps
its original source ownership and must free the returned iterator.

`JS_PiForInNext` borrows that iterator and supplies three local stack slots to
the existing `js_for_in_next` helper. The helper borrows slot zero, writes an
owned key or `undefined` to slot one and a Boolean completion value to slot
two. Success transfers slot one to the caller and writes `0` or `1` through
the required non-null `done` pointer. Failure preserves the original context
exception, returns `JS_EXCEPTION`, and leaves `done` set to `1`. The Boolean
slot has no heap ownership. Neither the wrapper nor the original next helper
consumes the borrowed iterator.

The Zig owner holds the iterator across each source getter and destination
assignment, frees each returned key, and releases the iterator on every exit.
It uses the existing host cancellation/interrupt budget during native loops.
The wrappers add no source evaluation, property reconstruction, key sorting,
alternate prototype walk, or modification to public interpreter opcodes.

This is a Source-only unqualified additive ABI draft. Its focused qualifier
must compare real guest for-in, inherited/numeric ordering, non-enumerable
shadows, deletion, proxies, original exception identity, GC and owned cleanup.
Original Node `highlight.js` inherit comparison is a separate requirement;
agreement with the guest VM alone does not prove Node proxy-trap ordering.
