# Actual jiti interop/cache/import and safe frontend retirement

This source-only unit implements concrete missing jiti2.7.0 algorithms. It does
not register createJiti, compose the incomplete private importer as a facade,
select the default SDK, or claim whole-graph parity.

Authority was freshly obtained from the primary npm registry and official jiti
repository, independently of the recovery-pending runtime. The official npm
archive passes its SHA512 integrity and contains exactly the retained Source48/39
dist SHA A0B3B8D5E06A0519C66B62179E29200533057920F6F11370546E979DACD24C49.
The package gitHead is fd3bb289b75ed207edfb686d671ed50144f7e90f; official tag and
immutable-commit copies of all four source files plus LICENSE match bytewise.
The primary archive, exact dist/source bytes, license and authority receipt are
retained under authority/. They are reference input, not a production JS bridge.
No downloaded module was executed. This does not revalidate the old dependency
runtime or transfer any of its process/native qualification.

native_jiti_interop.zig implements utils.ts93–153: primitive identity, the
captured default value, Promise checks in Source order, actual Proxy traps and
per-proxy Map cache, synthetic __esModule reads, original-module self-default,
nested-default double getter, inherited target reads and bound default-method
fallback. Source quirks are preserved: typeof null is object for fallback; a
null-default missing read throws; an apply trap does not make an object target
callable; callable module targets continue to call the original function.
Private closure state has null prototype, while the public handler and actual
module/export objects retain their Source prototypes and identities.
Trap captures use the existing VM-owned CFunctionData roots, traced/charged/freed
by the runtime; they add no untraced native record or context-pinned Proxy owner.

The JSON branch follows require.ts98–108. It returns the actual JSON export and
uses the live Object.defineProperty operation for a permanent, nonenumerable
self-default only when no own/inherited default exists. Falsy primitives pass
through; truthy primitives fail at the real in-operation boundary. The separate
importDefault helper performs the synchronous nullish-default expression after
the caller's genuine Await, creating no Promise or thenable driver.

native_jiti_module_cache.zig supplies actual parentCache || {}, two parent-cache
reads on a hit, loaded native-cache lookup, real Module publication before eval,
native-cache-only compile/eval failure cleanup and strict ===false tryNative
success cleanup. Parent partial records are not globally cleared. Cache deletion
does not retire native ESM namespaces, old closures or private C graphs. The
retained actual distribution places these functions inside a strict IIFE, so
failed deletes throw. loadedExports is only the next() tail after the real caller
has handled any Babel __JITI_ERROR__ marker; marker handling is not fabricated.

native_jiti_import.zig supplies the actual async import method, genuine AF name
import/length2/nonconstructor, over a required actual ordinary jitiRequire
binding. It spreads original options, overwrites async:true, performs one raw
primitive Await and reads original opts.default only after resumption. Borrowed
arguments/results are duplicated where retained or returned; ordinary reasons
transfer out of the captured slot and trusted host failures retain their fatal
identity. A namespace-only importer is not substituted for jitiRequire.

The existing adapter now releases frontend resources only when a terminal
session never acquired a private C graph. Such sessions have no private C
callbacks/origins capturing their binding arrays. Copied names, retained JS
authority roots, private kind entries and the handle are released; a small
retired SessionRecord tombstone remains until context teardown. Membership
rejects retired records, and their addresses are never reused, avoiding public
opaque-handle ABA. Sessions with a non-NULL graph remain untouched and pinned.
Shared kind policy remains owned by the hub across sessions. Host-only counters
distinguish released bindings from retained tombstones; they are not guest fields.

Adapter callback exits also preserve any preexisting/fresh fatal reason before
normalizing an actually pending VM exception. Owned current captured reasons
transfer back to the VM at C callback boundaries, or into the AF thrown action,
before terminal frontend cleanup. This addresses the existing metadata setter
which can return JavaScriptException with a pending reason without a native
capture; no Engine/shared Scope flow is modified.

Full createJiti remains explicitly missing. The existing native TypeScript
transform preserves ESM syntax. jiti's real evalModule instead lowers through
Babel to a CommonJS wrapper, constructs actual node:module.Module, publishes
partial exports and binds nested require/import/esmResolve to that parent cache.
Current commonjs exposes createRequire but no actual Module constructor or
_nodeModulePaths; proxying an ESM namespace cannot claim those identities/live
export semantics. Option normalization, tsconfig paths, transform/native retry,
parse-marker stacks and complete physical alias/diagnostic parity also remain.
The genuine queued import ABI is under separate Root/models_auth review. This
unit does not compose synchronous JS_LoadModule as guest dynamic import.

Private graph GC/reclamation is still unavailable in the reviewed C surface.
Even minimal tombstones remain context-pinned; an explicit reviewed production
resource policy or real graph/closure/job-aware reclamation is a remaining gate.
No ModuleDef/capability/context-wide sweep or C rollback occurs here. The vendor,
Engine and async primitives remain unchanged; integration must retain Root's
current vendor/primitive baseline rather than copy this older isolated tree.

Six prepared entry points cover Source Proxy getter/cache/receiver quirks, raw
trap reason and JSON behavior, actual context/Module cache lifecycle, actual
jitiRequire import method, no-graph binding retirement/old-handle rejection and
fresh trap native allocation identity. Three JS programs are retained as source;
integration controls require actual composed subjects and owned physical paths.
No fake Node.Module, jitiRequire, provider registry or SDK bootstrap is supplied.
These are not a Source reference capture or accepted native expected output.

No formatter/AST, compiler, native runtime, Node capture or generator was run.
All controls remain uncompiled/unrun, as does this adapter unit. Original
Source53/44/15/48/39 packets, expected files, physical fixtures and historical
relocation records remain unchanged. New Source capture and native allocation,
cancellation, context teardown and complete graph replay gates are still needed.
