# Lazy actual native-converted CJS provider

This supersedes the eager publication assumption for the public jiti profile.
Register the actual native backend before exposing jiti; do not create a Babel
Module, change require.cache, or guess the future parent at readiness time.

Host API native_node_commonjs_converted_provider.register(engine, Inputs)
takes the exact canonical Module constructor, absolute physical filename JS
string, and actual native backend exports function. The canonical constructor
owns a private VM Map of filename to ordinary five-argument native CJS body.
Repeated registration of the same three identities is idempotent and preserves
the body function identity. A conflicting backend is refused. ready(engine,
Inputs) authenticates those three identities without reading guest cache state.
Neither the Map nor the readiness record is exposed as an import namespace.

The body is an actual native implementation of the converted module's CJS
assignment: module.exports = the exact real backend. It has normal CJS arguments
(exports, require, module, filename, dirname), returns undefined, and makes no
Promise, fake parse result, canParseAsESM field, fake compile metadata, extension
handler or filesystem result. It is not the transform function passed off as a
Node wrapper; the transform function is its actual exported value.

Dispatch is deliberately inside the real Module.prototype._compile after the
public _load/module.load/extension-handler/_compile calls have already occurred.
Only explicit commonjs format plus the canonical initialized, unpatched
Module.wrap/wrapper can select the exact registered filename. Other files,
module/unknown formats, an uninitialized wrapper and any patched wrapper fall
through to the required genuine wrapSafe compiler/script path. This preserves
public method/registry patches; intercepting before module.load would not.
The shared compiledBody selector is used by the actual _compile body and by the
prepared selector controls. No new replacement require is introduced.

The existing actual _load path resolves first, checks cache/circular records,
constructs the real Module with its first actual require parent, publishes its
cache record before load, and owns relative-cache/children failure cleanup. The
actual load body sets physical filename and live paths before its handler. The
actual _compile retains require-depth/stat-cache, require function construction,
executing flag and raw body completion order. The actual load then sets loaded
and its canonical private export snapshot. Ordinary failure keeps Source
finally precedence; fresh/current fatal bypass is the closed 138ecd boundary.
An initializer does not mark its Module loaded or bypass these surrounding
steps. Genuine cache cycles return through existing _load circular/cache logic;
readiness never claims that a Module has been initialized. Cache eviction is
not a request to manufacture a new native compiler implementation: the admitted
native backend identity is host-owned, while a new Module lifecycle still runs.

Map storage and constructor/class/property allocations are charged by the VM.
The existing aggregate-charged native ordinary callable owns duplicated roots
for the exact constructor, filename and backend exports; its gc_mark and final
release cover them. The constructor roots the private Map, so there is no raw
native pointer token, uncharged provider side table or unmarked native JS root.
The resulting constructor/Map/body root cycle uses existing GC-aware callable
ownership. Registration publishes a body only after its creation succeeds;
failure before Map insertion leaves no admitted provider. Partial empty private
Map allocation is harmless and reusable. Normal register/ready host entries use
local balanced diagnostic suppression and operation-owned generation guards.
The initializer captures an actual pending reason before/after assignment and
uses the existing ordinary callable's precise generation boundary.

Three additional actual-VM controls (nine named in the combined control root)
cover lazy cache/parent absence, idempotent body identity across GC, conflicting
registration, the actual-used format/wrapper/name selector and direct genuine
five-argument initializer behavior. They do not pretend to run a full _load.
The six earlier publisher controls remain separately reviewable at 0641c422.
Actual first-load-once, cached cycle/reentry, eviction/new-parent and failure
cleanup through the full public jiti/Module graph still need a genuine complete
bootstrap and original/native execution controls. No Source expected values or
fake actual dependency graph is supplied here.

The real generic compiler/wrapSafe, actual createRequire/resolver/FS/hooks,
namespace bootstrap and profile readiness integration remain separate required
capabilities. This source does not select a default registry, change Engine/C,
register an Engine value-module alias, load Babel eagerly, or assert Node24/jiti
runtime qualification. No Node, compiler, metadata, native or generator job has
run for this successor.
