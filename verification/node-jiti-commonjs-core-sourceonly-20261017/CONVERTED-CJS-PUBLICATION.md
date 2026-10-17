# Native-converted CJS publication over the actual Module

This is an explicit host admission seam for an already converted native body;
it is not Node's filesystem extension dispatch, wrapSafe, or a substitute
createRequire. Its supplied exports value must be the exact completed native
implementation from its actual owner. It does not turn an unimplemented or
missing package into a dummy module. No default bootstrap is selected.

API: native_node_commonjs_converted_module.publish(engine, Inputs) returns an
owned real Module. Inputs are borrowed for the call: authenticated canonical
module_constructor, exact physical filename JS string, parent (or undefined),
and exact completed exports. For the jiti profile pass Prepared.module_constructor,
Prepared.babel_filename and Prepared.native_babel_exports unchanged, with its
real loader parent when available. Then pass the returned Module to the actual
profile.complete. This unit does not construct a fake profile or namespace.

Authentication uses the constructor's existing private callback roots. It
requires constructor._cache === engine.commonjs_cache and rejects records not
in that exact constructor's private first-parent relation. A matching already
loaded record is reused only with the exact filename and exports identity;
children are deduplicated and its last parent is updated without changing the
first parent. Conflicting records and incomplete reentrant admissions fail.

For a new admission, actual new Module(filename,parent) performs its normal
path, exports, private first/last-parent and children initialization. The real
record is cached before the converted body assigns exports. Genuine cyclic
cache readers can therefore observe the initial Module/exports with loaded
false. Source loader symbols use the same constructor-owned exact identities
as later prototype bootstrap. The load step preserves filename/paths nullish
checks, captures live _nodeModulePaths before invoking dirname, assigns actual
exports, marks loaded and records the same private export snapshot consumed by
later Module/ESM composition. No generated wrapper, public fake .load method,
Module alias registry or Engine module registration is used by this publisher.

Initialization errors follow the actual load boundary policy: fresh private
allocation recognition is checked from an operation-owned generation snapshot
before guest cleanup. Actual current fatal and host allocation failures skip
guest cleanup. Ordinary errors remove the live cache entry and the genuine
parent child; cleanup failures retain ordinary finally precedence. Constructor,
cache-publication and pre-load symbol failures occur before this initialization
boundary, matching their placement before the actual Source load try/finally.
No new C, Engine, async helper, fatal tag or rejection policy is introduced.

The constructor's GC-owned private state now owns canonical lazy loader symbols
and the export WeakMap. Prototype bootstrap consumes those same values instead
of creating a second relation. Captured primordial WeakMap/Array operations are
rooted in the canonical constructor's owner. WeakMap keys do not acquire native
strong-reference cycles and no native side table is introduced. Root's two
pi_js_null() constructor fixes remain intact.

Six prepared native controls exercise actual constructor/cache identity,
first/last-parent reuse, GC, shared private keys/export snapshot, publication
before body through an actual parent children Proxy, live paths callee order,
ordinary cleanup, fresh fatal bypass, and forged/conflicting-record refusal.
They use real existing path and existing createRequire implementations; the
latter is retained as a constructor input but never invoked. A controlled
warning-free process object is explicitly fixture-only, not node:process.
These controls do not establish the older createRequire's Node24 completeness,
full Module prototype/compiler, genuine default profile bootstrap or jiti.

No compiler, metadata, native runtime, Node reference or generator job has run
for this successor. The six named declarations are not a compiled metadata
count. Earlier source units, original Node captures, negatives and proofs are
unchanged. A separately granted qualification must use the real profile's
completed capabilities and canonical cache; full unpatched CJS compilation and
sync ESM linking remain required genuine dependencies.

The host entry itself now suppresses diagnostic coercion in a balanced local
scope and applies exact fresh-allocation classification across the entire
entry, including live cache/getter and existing-record operations. Controls
call without external suppression; ordinary raw-reason toString must not run
and the fresh cache-getter reason must already be uncatchable on return.

Integration note: this helper is not an instruction to publish Babel eagerly.
Actual public jiti lazily loads Babel. A separate private provider-registration
and genuine first-resolved-load dispatch is being prepared; profile readiness
must not expose a preloaded cache record or invent its first parent.
