# Canonical CommonJS watch-dependency reporting

This packet implements the original loader.js watch-dependency reporters and their one shared lazy environment value. Canonical _load and _findPath now acquire the actual private reporter from the genuine Module owner; neither public input record accepts a caller-supplied reporting policy.

Main base: 65fac9975b25e9a5e4c00d7d7bca499aae1275c0. This is a source-only successor to application-commonjs-circular-sourceonly-20261023. No Main file, sealed donor, compiler output, native evidence, or application default was changed.

## Exact source and integration

source-accounting.json records the selected five projected source files, their exact predecessors, retained authority, finite deltas, direct imports, and the separate build insertion. application-commonjs-watch-source.patch contains those five source changes and the additive build change.

The Module constructor and _load predecessors are the accepted circular packet's projected-v2 files. _findPath comes from frozen Main. The reviewable build diff uses the finite derived base Main build.zig plus the accepted circular insertion. Neither that derived full build nor an alternative merged build is copied into this packet.

Root must compose only build-addition.zig.txt into an already-combined Stream/Module/circular build. The new install-only step is build-native-node-commonjs-watch, filtered by native actual CommonJS watch. It introduces eleven named test declarations; actual compiled metadata remains unknown.

## Original behavior preserved

The authority is Node 24.14.0 commit f657bb8ed86365ff3fdbe32e27563e778b41486a: loader.js line 185 and lines 314-329, plus internal/util.js lines 813-823. Existing retained authority paths and digests are referenced in the accounting; no authority is recopied.

The flag process.env.WATCH_REPORT_DEPENDENCIES is read only on first use. Its original JS value is retained, including undefined or any other falsy value. Initialization is recorded only after the read succeeds. A throwing initializer retries; a reentrant successful outer initialization overwrites the inner value, while a throwing outer initialization leaves an inner completed value intact. This matches getLazy's assignment order.

Each enabled report reads process.send once for the condition and again as the actual callee. The second lookup precedes message construction or mapping. The call uses the actual process receiver. Required filenames retain their identity and are never coerced.

Missing-path reporting calls the Array.prototype.map retained by the canonical Module before guest execution. Native map supplies the original sparse/inherited-element, length, species, and abrupt-completion behavior. At each visited element, the callback reads live path.resolve before separately coercing the base path and extension, then calls that selected function with the actual path receiver.

The watch:require message and its literal array elements are own data-property definitions. Inherited setters do not intercept object or array literal construction.

The private reporter graph is cached per Engine after validating the genuine canonical Module, including cached acquisitions. It creates no substitute Module, public namespace, transport, or independent process owner.

## Focused controls

Eleven unexecuted controls cover:

1. One authenticated graph, declaration metadata, rejected foreign Module, and no public node:module publication.
2. Lazy initialization shared by both reporters over the actual process/path owners.
3. Cached undefined and complete disabled-path short circuit.
4. Throwing initializer retry and exception identity.
5. Successful outer reentrant initialization replacing the inner value.
6. Throwing outer initialization preserving a completed inner cache.
7. Two live send reads, original receiver, and uncoerced filename identity.
8. Message/array own data fields despite inherited setters.
9. Module-captured map after guest mutation, sparse/inherited elements, and real species construction.
10. Exact send/map/path/callee/template-coercion order at successive elements.
11. Map/send exception propagation with the initialized flag retained.

The controls initialize the real Engine, process/Stream graph, native path/URL/FS providers, and canonical Module core. Mutated guest properties observe the original JS semantics; they are not production adapters. No IPC channel or Node process is launched.

## Qualification boundary

Static inspection verifies the finite source inverses, unchanged helpers and find algorithm, actual caller binding, source import resolution, exact patch reconstruction, and additive build inverse. No Zig parser, formatter, compiler, native metadata query, runtime, Node reference capture, or source generator was run.

The complete Module hook/ESM/compile graph, native Jiti dependencies and physical identities, application namespace/lifetime assembly, and Main print/RPC integration remain separate work. This bounded collaborator does not claim production bridge removal or complete application qualification. The earlier two-root validation packet stays sealed and unchanged.
