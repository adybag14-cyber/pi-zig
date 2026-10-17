# Serialized fixture correction after actual 09e negative

This successor changes the index-six fixture setup and its source hash pin.
The readonly query C/H, build target, fourteen named declarations and optional
storage-name policy are unchanged. No compiler, metadata or runtime job was
launched while authoring this correction. The historical prepared.json and
source-only README describe their original checkpoint, not new execution.

The retained 09e runtime stdout was independently decoded as fifteen result
records: index six flags=1, all other fourteen flags=0. Its stderr points to
JS_ReadObject at fixture line 133, before the first query. JS_ReadModule resolves
serialized request names during reading; that context lacked a matching module
cache or source loader until after the read. The setup therefore could not
return the intended unresolved token.

The corrected setup pre-creates two genuine JS_NewCModule definitions under the
exact requested names and installs a counted normalizer before JS_ReadObject.
The read resolves both names to cached native definitions without recursively
resolving them or calling their init callbacks. The first query still must fail
on the actual unresolved serialized root, leaving output 99 and normalization
counts unchanged.

Then the fixture makes the normalizer reject only the second request during
actual JS_ResolveModule. The actual resolver marks the root resolved, resolves
the first native child and fails before looking up the second. The existing
unresolved-module sweep frees that second definition; the parent remains owned
and retains a genuinely incomplete static edge. No child module-value token is
kept across the sweep. The second query must fail with output 99, even with root
TLA, without invoking normalization, loading or initialization. GC is run before
this query; the native init flag and pending-job check must stay clear. No fields
are fabricated, no ModuleDef casts/setters are used, and no ABI is added.

Original 09e files and runtime/build-query evidence remain immutable. This is a
source correction awaiting independent review and a separately granted fresh
build/query/runtime, not a passing successor or whole-graph qualification.
