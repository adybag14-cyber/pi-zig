# Native SourceMapCacheMap owner

This isolated source packet ports the complete private SourceMapCacheMap class from Node v24.14.0, commit f657bb8ed86365ff3fdbe32e27563e778b41486a, using the original file retained by the pinned supplier-gap assessment. The original MIT license is retained in Main's node-module-constructor authority directory and pinned by source-intake.json.

The selected owner is projected-v2/src/extensions/native_node_source_map_cache_map.zig. The first owner under projected is retained as an unselected draft; iterator-single-value-source-inverse.json records the only two refinements, preserving one result.value evaluation during destructuring. The selected test and pristine-capture successor remain under projected.

## Concrete entry and actual owners

create(engine, Inputs{ .debuglog = actual_debuglog_function }) returns one owned class constructor. The supplied function must be the genuine internal/util/debuglog.debuglog collaborator from the canonical Module graph. It is borrowed through the synchronous creation call. Its returned logger and assignment callback form the actual mutable lexical debug binding; the callback has the original initialization TDZ. Tests supply explicitly named observation fixtures; production has no test logger, disabled-policy default, JavaScript evaluation, shadow channel, or synthesized environmental policy.

The actual Engine already captures WeakRef constructor/deref before guest execution and owns their lifetime. Its existing clone-operation registry is extended with Map.get/delete/size, FinalizationRegistry constructor/register, Array.prototype.forEach, Object.freeze, Symbol.iterator and the one actual private source-map-data symbol shared across cache classes within that Engine. Engine.zig, QuickJS C/header and the native ABI remain unchanged.

Each instance owns an actual VM Map, cleanup function and FinalizationRegistry in private own slots. Native callable closures retain and mark their JavaScript roots. The cache holds keys and WeakRefs; source-map data is attached to the actual module's private slot. There is no strong host dictionary of module/data entries, surrogate weak pointer, manual cleanup queue, or manually invoked finalization callback.

## Preserved behavior and completion ownership

- set constructs WeakRef before inspecting keys. Captured Array.forEach preserves array-like length, holes, inherited indices and getter order. A partial key failure preserves previous insertions. Private module-data Set happens after key insertion and before FinalizationRegistry.register.
- Private class brands require each actual own slot and reject inherited/proxied/forged receivers. The shared module-data private property uses the existing genuine VM operation, including frozen ordinary objects and a Proxy wrapper's own storage.
- get returns the module's current shared private value after real deref. A successful deref participates in the Engine's actual end-of-job kept-target lifecycle. size remains the underlying Map estimate until cleanup.
- The actual FinalizationRegistry receives the original mutable keys object inside { keys }. Cleanup checks the currently mapped WeakRef, preserving a newer live replacement. It resolves the mutable debug callee before template-literal ToString of the key, invokes that exact callee, then unconditionally deletes. A thrown logger prevents deletion; logger/key-coercion reentry retains original ordering.
- Iteration uses the actual Map iterator and captured next. It produces the original ordinary iterator object with own enumerable/configurable/writable next and Symbol.iterator methods. Dead WeakRefs recurse through the captured original next even if the public next property is replaced. Result descriptors, insertion order and exhaustion remain those of the original algorithm.
- The class prototype is frozen. The native class/closure representation uses existing VM callable ownership; this packet does not assert V8 heap layout, debugger naming, native function source rendering or exact allocation-count equivalence.
- Existing Scope, synchronous argument frames and completion boundaries preserve assigned roots, actual pending native events and retirement ordering. Captured flagged Error values remain ordinary data; a fresh native producer during coercion or replacement retirement remains a pending event with first-fatal identity.

## Controls and verification limits

The test root declares twenty focused controls. They exercise real Engine/Map/WeakRef/FinalizationRegistry owners, actual native lifetime probes, actual end-of-job checkpoints, deferred jobs, stale aliases, mutable held keys, reentrant/throwing logging, original descriptors, forged receivers, pristine operations after prototype/global poisoning, and native fatal producers. The only JavaScript source evaluation is in these test controls.

Static verification replays four pristine-capture hunks, the two iterator refinements and the 722-byte additive build insertion with complete raw inverses. It resolves all literal imports, records all twenty direct declarations and scans the bounded source for concrete local/function-name shadow candidates. This is source inspection only. No Zig parser/compiler/formatter, native query/runtime, Node reference capture, source preparer or generator was run. No actual metadata count or execution success is asserted.

## Integration

The four target paths are new owner, new test, native_clone_intrinsics.zig and build.zig. Main is untouched by this packet. The baseline is clean 7947d3a0825a356dccc6aca7a327c92d7248b47f. If composed with another packet, insert only build-insertion.txt at its exact anchor; do not replace a separately composed build.zig with this standalone projection. All retained original authority and previous source packets remain byte-exact.

## Next production entry

The constructor is a real dependency for source_map_cache.js getLazy(() => new SourceMapCacheMap()), lines 33-35. It does not yet publish that module or supply maybeCacheSourceMap. production-entry-handoff.json identifies the exact inputs and unresolved production owners. In particular, a genuine JavaScript debuglog producer is still required; NODE_DEBUG_NATIVE EnabledDebugList is a different owner. A complete maybeCacheSourceMap must preserve actual coverage/support reads, URL normalization, data/file map loading, null-data coverage entries and generated-versus-module cache ownership. This packet does not flip the application backend or qualify print/RPC startup.
