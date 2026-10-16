This is a source-only integration proposal after independent static review of
24424bbf closed without another concrete blocker. No Engine or C implementation
is authorized by this document. The C prototype is uncompiled and unrun;
context-pinned retention is an explicit production resource/lifecycle gap.

The read-only inventory is pinned to Root 25427e035cbfe572892d641d09ca38bb1d43fe17.
The six inspected loader files have the same blobs as aef0bbe5. The external
inventory receipt is engine-private-module-design-20261016/existing-loader-seams-readonly.json.
Source authorities are accepted Source48 proof76025577 and Source39 proofa44aee97.
Their original packets, physical versions, negative wrapper and Root supplements
remain unchanged. This proposal creates no new expected output.

Existing seams and concrete gaps

| Existing seam | Current behavior | Proposed scoped use |
| --- | --- | --- |
| engine.zig SourceLoader, setSourceLoader, normalizeModule | One runtime loader; registered native modules except TypeBox bypass disk normalization | Keep ordinary path; capture a separate extension policy per import session |
| Engine.modules, registerModule, moduleLoader | Stores transformed dependency bytes globally under physical names | Private TS reads/compiles bypass this table; explicit registered user inputs remain ordinary |
| Engine.evalModule and private setImportMeta | Compiles a root directly, sets physical metadata, evaluates and pumps jobs | Factor metadata and compile/evaluate pieces; extension async caller owns Await |
| JS_LoadModule | Existing shared resolver/cache, evaluation Promise resolving to namespace | Shared ESM roots use this path rather than compiling another root definition |
| native_worker.Loader.normalizeMode | Resolver realpath, package exports/imports and import/require conditions | Reuse physical resolution only where observed; do not infer jiti tsconfig-path behavior |
| native_worker.Loader.source/input | Transforms .ts/.mts/.cts before classifying CJS/JSON; .js package-scope inspection | Factor raw read and classification; no blanket reuse of this suffix policy |
| commonjs.load/cache | Shared per-Engine platform-filename cache, CJS cycles and JSON values | Preserve shared CJS/JSON authority and identity across private graph reloads |
| Bindings.loadFactory / worker.loadSource | Loads a root through evalModule or a CJS export value | Separate future adapter; no worker/default switch in the proposed first patch |

Exact inspected Git blobs:

- engine.zig f00a5a3c6ac791a861ca899b83a93dad2daaef41
- native_worker.zig 7c05fe180bbcbe1df78f8651789af4a2e230b7fc
- commonjs.zig 8a317c650660be6ccd5d3cd5201404b678fd12b3
- module_resolver.zig c8078e130ea363c7e4db200750733f7ef1b12ca1
- typescript.zig 1b4bf193cdc597335086270a5e7013233a52ad1a
- native_bindings.zig is recorded in the external inventory, not proposed for edits.

Required normalization seam before Engine code

C phase1 currently invokes the runtime-global normalizer before its selector
receives exact importer origin. This is insufficient to distinguish an extension
private import from an ordinary import with the same physical base. In particular,
Source virtual-modules.ts resolves exact Pi/TypeBox virtual names before disk
lookup, while ordinary Engine resolution deliberately prefers an external
TypeBox package. A physical-name lookup cannot establish lexical graph identity.
Temporarily switching a runtime-global current graph is also unsuitable across
dynamic imports, guest re-entry and Await.

The recommended separate phase1.1 C proposal is one optional graph normalizer:

```c
typedef char *JSPiModuleGraphNormalizeFunc(JSContext *ctx,
    const JSPiModuleOrigin *importer, const char *physical_base,
    const char *specifier, JSValueConst captured_attributes, void *opaque);
JSPiPrivateModuleGraph *JS_PiNewPrivateModuleGraph2(JSContext *ctx,
    JSPiModuleGraphNormalizeFunc *normalizer,
    JSPiModuleGraphSelectFunc *selector, JSPiModuleGraphLoadFunc *loader,
    void *opaque);
```

The returned name has the existing js_malloc/free ownership contract. Exact
origin selects this callback before physical normalization; selector still runs
after normalization and before lookup. Old constructor remains a wrapper with
NULL normalizer; graph zero is unchanged. Callback success with a pending reason
must stop before selector re-entry. Graph captures callback/opaque immutably for
context lifetime, with no callback setter or process-global current graph.

This extra C surface requires Root and independent review, allocation/lifetime
controls and qualification separately. It is not implemented in 24424. Without
it, the first Engine prototype would have to reject virtual/private resolver
differences and loader replacement; it cannot claim complete Source39 inputs.

Proposed Zig API and ownership

Keep existing SourceLoader and ModuleInput signatures unchanged. Introduce a
separate extension-only policy in a new leaf, rather than replacing Engine:

```zig
pub const ExtensionModuleKind = enum {
    transformed_ts, shared_esm, shared_commonjs, shared_json, shared_value,
};
pub const ExtensionImportPolicy = struct {
    context: ?*anyopaque,
    normalize: *const fn (?*anyopaque, *Engine, []const u8, []const u8,
        c.JSValue) anyerror![]u8,
    classify: *const fn (?*anyopaque, *Engine, []const u8,
        c.JSValue) anyerror!ExtensionModuleKind,
    transformed_source: *const fn (?*anyopaque, *Engine,
        []const u8) anyerror![:0]u8,
};
pub fn createExtensionImportSession(self: *Engine,
    policy: ExtensionImportPolicy) !*ExtensionImportSession;
pub fn startExtensionImport(self: *Engine, session: *ExtensionImportSession,
    physical_base: []const u8, specifier: []const u8,
    attributes: c.JSValue) !c.JSValue;
```

The return is an owned native Promise for a namespace, not an internally pumped
result. Existing actual async caller awaits it at its Source boundary and applies
the measured default interop. Engine does not call awaitValue while creating this
Promise. Private root evaluation needs an explicit native resumable helper to
await JS_EvalFunction's result once, then obtain the exact module namespace. Its
state uses the reviewed private owner, never a public metadata object.

Session and callback records are Engine/context-owned stable allocations. They
capture immutable policy callbacks, host context and actual virtual namespace
roots. Those inputs must outlive Engine teardown; a stack attempt, extension
factory owner or cache token is not a valid callback opaque. One fresh private
capability is created for each actual transformed root import. A shared root
uses shared zero and does not need a private capability.

The Engine-owned record maps the trusted capability to its kind decisions and
captured resolver. It does not expose a graph ID or origin through JS module
exports, require/cache keys or diagnostic names. No ModuleDef lifetime is inferred
from JS_DupValue(module). Context ownership and the executing function's realm
anchor remain the C phase1 contract. Native quota charges retained host records.
Use the existing native_env_charged_allocator.zig allocator interface (Root blob
63d50d2aeb855d4ca953f52c501ebb4d5eb42a2b), subject to its own qualification,
or the existing native-memory reserve/release API. Ordinary engine.gpa allocation
does not establish aggregate VM quota accounting. The charged owner reference
can outlive runtime destruction while final host records retire. Release owned
JS roots while the context is valid; keep callback/opaque storage alive through
context/runtime teardown, then free all host allocations and assert charged use
zero before releasing the retained memory owner. Queue cancellation, finalizers
and teardown order need explicit terminal accounting controls.

Observed classification and cache policy

| Captured case | First admitted decision | Repeated/reloaded behavior |
| --- | --- | --- |
| Local transformed .ts root/static .ts dependencies | Private transformed TS in that new session | A new root gets a new graph and current source bytes |
| Live factory dynamic .ts dependency | Private in that exact lexical graph | First successful load cached; old seeded closure retains it |
| Old factory first late dynamic .ts import | Private miss in the old graph | Reads current bytes then caches; no global latest-graph switch |
| Direct .mjs, .cjs, .js type:module/commonjs/no-type-CJS roots | Shared ESM/CJS after the observed format decision | Same factory after edits and new importer; cached type transition retains first definition |
| Static JSON and dynamic CJS/native .mjs dependencies | Shared CJS/JSON/ESM | Same namespace/export value after file edits and private root reloads |
| Exact configured virtual names / Node builtins | Existing canonical shared value module | Same actual namespace, constructors, Memory/Settings and function identities |

This is a closed observed subset, not extension-only classification. The first
kind decision considers resolution mode, physical path, package scope and source
format where needed. The kind of a successfully shared-cached module is retained
with that shared record; rereading changed package.type must not reclassify its
cached identity. Classification runs before C lookup, but can use this retained
kind decision without rereading edited source. A private cache hit likewise
retains its first kind/source record while the selector still executes.

Cache keys are canonical physical names plus existing attribute equality and
capability. C owns private attribute snapshots; Engine must not stringify mutable
objects into an alternative cache key. Initial Source39 integration accepts the
observed absent/empty attributes only. C's raw attribute controls do not establish
Source policy for nonempty attributes. Windows case folding, relative aliases,
symlink changes and query/fragment identities remain unobserved and fail closed.

Virtual resolution must use actual VIRTUAL_MODULES authority before disk lookup.
The namespace table is a required real composition input, not an empty registry.
For a registered canonical name, private selector returns shared zero; it must
not create another C module wrapper or duplicate a builtin namespace. Pi and
TypeBox aliases reuse the existing real composed exports. Ordinary Engine imports
retain their current external-schema preference through the separate normalizer.

CommonJS/JSON interop is a separate observable seam. Existing createDefaultModule
wrapping alone does not establish jiti's complete default behavior. Primary jiti
JSON fallback adds a nonenumerable self default only when `default` is absent;
the current commonjs loader does not establish that extension-only behavior.
Preserve generic require and JSON cache behavior, and implement/capture the
extension interop at its own boundary before claiming parity. Proxy/default
getter ordering and mixed ESM/CJS cycles need genuine controls.

Physical resolution and async lifetime

Private normalizer uses its captured policy and exact origin, including for old
factory dynamic imports after a reload. Resolution bases, parser filenames,
import.meta URL/filename/dirname and stack filenames remain physical. The existing
setImportMeta body can be factored into a scoped Engine helper and reused after
private compile, before evaluation; no nonce may enter names or URLs. Actual
jiti transformed stack columns/receiver names remain a separate parity gate.

Current Resolver implements filesystem realpath, package exports/imports and
import/require conditions. It does not implement tsconfigPaths or import.meta.resolve.
The first proposal must reject their unobserved uses rather than treating the
ordinary resolver as a complete jiti replacement. A future import.meta.resolve
closure captures exact physical base and policy without reading a global graph.
TS transformation uses native typescript.transform on fresh physical bytes and
retains the source/source-map authority required for diagnostics.

Module-level Source extensionCache is separate from the graph cache. Keep its
resolved cwd and generation token, factory-type check and post-Await token check.
A stale in-flight import may return its factory to its caller but cannot repopulate
the current cache. Clearing that cache retires no old graph or escaped closure,
and does not clear native/shared or CommonJS/JSON caches. One actual live importer
session keeps its parent cache; a new transformed import gets a fresh session.

Unobserved .mts/.cts/.tsx, native JS/MJS-to-TS edges, fallback after native failure,
failed late-import retries/error identity, eval/new Function import(), concurrent
fresh roots/TLA and aliases/attributes remain explicit blocked policy cases. The
C raw VM helper supports primitives; it does not supply their missing Source truth.

Expected future files and gates

The smallest Engine implementation would add one policy/async leaf and scoped
engine.zig fields/methods/metadata factoring. A separate small worker adapter may
factor raw read/classify without switching loadSource. commonjs.zig and the normal
Resolver remain unchanged initially; any required extension interop or resolver
feature is reviewed separately. No whole Engine/worker copy is proposed.

Before authoring: review this API and the missing graph normalizer surface.
Before native integration: qualify C phase1 and any approved phase1.1 delta,
including exact allocation reasons, context/job lifetime, graph-zero serialization
and current C regression cohorts. Before activation: replay genuine Source48/39
physical effects and identities through the actual transformer/filesystem pipeline,
capture missing policy edges, prove callback/getter/Await order and full stacks,
and approve graph reclamation or another concrete long-lived resource policy.
Context pinning alone is not production completion. All default selection remains
uninvoked throughout this proposal.
