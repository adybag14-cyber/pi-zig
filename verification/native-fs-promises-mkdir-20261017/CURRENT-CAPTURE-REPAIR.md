# Preserve captures produced after boundary entry

Source-only successor to the independent finite finding at immutable5122dfdf.
Only native_node_fs_mkdir_exit changes in product code. Original6ac7/5122 packets,
manifests, filesystem controls and primary authorities remain unchanged.

Pre-entry captured history remains separately owned and released as DATA exactly
once by Frame.enter. From that point the captured slot is empty and isolated:
new captured completions have current-producer provenance. check, release,
record and adoptFailureValue now take/drain that current slot alongside actual
pending completion before any destructor; no repeated historical-DATA clearing
is performed. Both current values are selected/owned before displaced roots are
freed. First actual fatal identity and C5 cleanup priority remain intact.

The new contrasting native callback control performs a real failing-allocator
allocation, routes the actual host OOM through Engine.throwNativeOutOfMemory and
Engine.checked into the freshly isolated captured slot, then returns a normal
opaque object whose real destructor publishes an ordinary VM reason. The guard
must preserve that new actual fatal B before releasing the returned object and
must expose the same private native allocation Error identity. A pre-entry
flagged history object is supplied in the same control and must not win. Existing
old-history success, first/later-fatal cleanup and actual resolver/completion-entry
controls are retained. All controls are UNRUN, with no fake Engine/process or
fabricated original/native result.

The mkdir worker, Hub cancellation/join, task completion entry guard, protected
resolver cleanup/native-only later destroy, AF body and installation API remain
unchanged from5122. The peer found no additional finite blocker in those portions
on the5122 read; this statement is review context only, not a receipt or runtime
claim. Genuine C3 ordinary THROW/DATA/prebody prerequisites remain separately
owned by Root's API lane. No C/H, Engine, Hub, Main, compiler/formatter/AST/Node/
native/helper/generator execution or public activation occurs here.
