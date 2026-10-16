This is the precise proposed phase1 C capability, awaiting Root's review of the
planned surface before C authoring. It is an unqualified, context-lifetime
prototype. It neither selects SDK defaults nor claims graph garbage collection.
No Engine classification/cache implementation belongs in this C patch.

Callback code and opaque host storage must outlive the owner context and every
old graph. The capability borrows that storage and owns no opaque destructor.
It must never point into a temporary import attempt, retired per-factory SDK
owner or cleared extension-cache token. Any JS values in host opaque storage
need separate context-lifetime GC roots; a raw host pointer does not mark them.

The isolated base is 8855fe109f5e4d71a01b80cc8faee9f35d354cd8. The existing C33+9h
vendor bytes are quickjs.c E2F988956B452EBACDDC1B24AB45E5F70F7AFB4777F7452EDF1457649B2D1D3B
and quickjs.h 341CF06F8041B8311D49767026C85C7B859BCFEE3088380F3FFE6D77527052AB.
Only vendor/quickjs/quickjs.c and vendor/quickjs/quickjs.h are planned existing
source edits. New prepared tests belong in src/native_private_module_graph_test.zig
and provenance/review material in this verification directory. No engine.zig,
native_worker.zig, build.zig, allocator/quota/async ABI, or old vendor copy is
part of this phase. No C/Zig compiler or runtime execution is authorized here.

The accepted authorities are Source48 proof76025577 and Source39 proofa44aee97.
Their exact raw expected hashes are14EEBD914A04DCBCBCEF24CD8D4509CB22A61FC2C18FB305B81ADE0E25C5DA00
and0DDCAB7DC649CBA5AC7147C722CE0AB98C9465E9B74290F57CD92C1A1FE89F27.
They establish the following observed policy, rather than an extension-only
classification rule:

| Observed execution | Cache lifetime |
| --- | --- |
| New transformed .ts factory and static .ts dependencies | Fresh parent cache for that import |
| Repeated dynamic .ts import from that live factory | Same first-loaded dependency |
| Reloaded transformed factory | New parent cache, reading current TS bytes |
| Old factory with its TS dependency already loaded | Keeps that earlier dependency |
| Old factory's first late dynamic TS import | Reads current bytes on that first call, then caches |
| Direct .mjs/.cjs/.js and native CJS/JSON/ESM dependencies | Shared cached identity in the measured cases |

Source39 also observes one evaluation and two completed results for parallel
dynamic TS TLA. Source48 observes fresh static cycles, physical import.meta URL,
stable old closures and protection against stale in-flight extension cache
tokens. Actual stack strings retain jiti's transformed columns and receiver
names. Physical filenames alone do not prove full native stack parity.

The proposed public C additions are opaque trusted-host capabilities, not guest
objects, properties or forgeable string tokens. Names below are the intended
header surface; exact C declarations will be reviewed with the patch:

```c
typedef struct JSPiPrivateModuleGraph JSPiPrivateModuleGraph;
typedef struct JSPiModuleOrigin JSPiModuleOrigin;
/* -1: exception, 0: existing shared domain, 1: importer's private graph. */
typedef int JSPiModuleGraphSelectFunc(JSContext *ctx,
    const JSPiModuleOrigin *importer, const char *canonical_physical_name,
    JSValueConst attributes, void *opaque);
typedef JSModuleDef *JSPiModuleGraphLoadFunc(JSContext *ctx,
    JSPiPrivateModuleGraph *graph, const char *canonical_physical_name,
    JSValueConst attributes, void *opaque);
JSPiPrivateModuleGraph *JS_PiNewPrivateModuleGraph(JSContext *ctx,
    JSPiModuleGraphSelectFunc *selector, JSPiModuleGraphLoadFunc *loader,
    void *opaque);
JSValue JS_PiCompilePrivateModule(JSContext *ctx,
    JSPiPrivateModuleGraph *graph, const char *source, size_t source_length,
    const char *physical_filename, JSValueConst attributes);
/* Borrowed until owner context teardown; NULL origin returns NULL. */
const char *JS_PiModuleOriginFilename(const JSPiModuleOrigin *origin);
const JSValue *JS_PiModuleOriginAttributes(const JSPiModuleOrigin *origin);
JSPiPrivateModuleGraph *JS_PiModuleOriginGraph(const JSPiModuleOrigin *origin);
typedef struct JSPiModuleGraphStats {
    uint64_t created, linked, evaluated, failed, quarantined;
} JSPiModuleGraphStats;
int JS_PiGetPrivateModuleGraphStats(JSContext *ctx,
    const JSPiPrivateModuleGraph *graph, JSPiModuleGraphStats *stats);
```

This list is exhaustive for the planned new header surface. Existing public
evaluation/loader signatures and JSEvalOptions version are unchanged. A caller
must supply an accessible NUL terminator at source[source_length], matching
JS_Eval's parser input contract; physical_filename must be NUL terminated too.
The source length excludes that terminator. This is a trusted host contract,
not an attempted out-of-bounds probe by the VM.
A caller
must duplicate an attribute value if retaining it outside the borrowed access;
no accessor supplies an independent ModuleDef reference or graph ID. Stats
access validates context membership before reading a capability. Normalization
uses the existing physical resolver before the selector. A selector cannot
return an arbitrary capability, and the graph loader never handles shared0.

1. Opaque JSPiPrivateModuleGraph and JSPiModuleOrigin types. A graph belongs to
   one JSContext and captures immutable selector/loader callbacks plus their
   opaque host context at creation. A NULL graph is the existing shared domain0.
2. JS_PiNewPrivateModuleGraph(ctx, selector, loader, opaque) allocates a private
   context-owned capability. Both callbacks are mandatory. No graph-free API is
   offered in phase1; default code has no graph capability.
3. The selector runs synchronously AFTER physical normalization but BEFORE any
   loaded-module lookup. It receives the exact importer origin, canonical target
   physical name and original import attributes. It returns current private
   graph, shared0, or an exception for an unobserved/unsupported policy. It cannot
   select a different private graph. This is an explicit kind/policy decision,
   not a guess from a filename suffix or lookup result.
4. The graph loader receives selected capability, canonical physical name and
   original attributes only for a private miss. Shared0 uses the existing
   loader/cache and never manufactures a second alias of a native namespace.
5. JS_PiCompilePrivateModule(ctx, graph, source, length, physical_filename,
   attributes) compiles one module in that capability. The graph and exact
   origin must exist BEFORE COMPILE_ONLY resolves child modules. The result is
   the ordinary compiled module value consumed by JS_EvalFunction; it is not
   advertised as independent ModuleDef ownership.
6. Read-only origin accessors provide borrowed physical filename, attributes
   and owning graph to trusted host callbacks. Context/graph accounting reports
   created/linked/evaluated/failed modules for tests. No accessor returns a
   guest-visible generation nonce. Callback output is validated against owner
   context, selected graph, physical name and attributes before use.

Graph-aware lookup is by canonical physical name, original attribute equality
and graph capability. Graph0 through existing APIs remains the old path. A
private ModuleOrigin additionally points to the exact ModuleDef and records its
   physical filename and capability; that exact descriptor, rather than a fresh
by-name search or scalar ID, follows all nested bytecodes. An origin is created
once per definition and is immutable after the definition is admitted. A
descriptor can be tombstoned when its unevaluated definition is freed on an
existing compile-failure path, without changing its retained physical diagnostic
name. It must never contain a dangling ModuleDef pointer.

The immutable attribute snapshot is an owned JSValue in the context-owned
Origin itself, separately marked from JS_MarkContext and freed with the late
origin record. ModuleDef holds a duplicate of that same immutable snapshot.
It is not a pointer into ModuleDef storage. An earlier borrowed attribute
pointer therefore remains valid even if the definition is tombstoned before
context teardown. Normalization copies own enumerable string keys, reads each
value once, requires strings and preserves existing absent/empty attribute
equality; private callbacks cannot mutate the retained cache key. This corrects
the first metadata draft's ModuleDef-storage accessor lifetime hazard.

Legacy shared-domain lookup and legacy by-name import.meta fallback must skip
private definitions that retain the same physical name. Otherwise merely
loading a private graph could poison a later default/shared lookup. Private
lookup uses exact origin plus its capability/attribute identity. These filters
remain a no-op in contexts where the new capability has never been used.

Physical filename, parser line information and bytecode debug filename remain
unchanged. There is no private generation suffix in module names, URLs, stack
filenames, resolution bases or diagnostics. Existing JS_GetScriptOrModuleName
continues returning the physical name. Private import.meta uses the current
bytecode's exact origin/definition, including attribute identity, instead of
js_find_loaded_module_by_name. Native/frame/syntax/link/load diagnostics must
use physical names. Full Source39 stack comparison is a later native gate; this
phase does not claim that native transpiler columns already equal jiti columns.

Private dynamic import captures the current exact origin before enqueuing its
job. The job retains that context-owned descriptor through evaluation/Await,
including calls from an old live factory after a newer graph is created. It
resolves relative names from the physical source and asks the selector before
lookup. There is no process/runtime-global active-graph switch spanning Await.
Nested synchronous graph creation cannot change the outer origin. Cross-context
use must honor the bytecode's existing realm ownership and reject a capability
from another owner context. Non-module/eval/generated-function origin behavior
is not guessed; the default path stays unchanged and unobserved private routes
remain outside the admitted policy.

Every origin field is explicitly NULL/zero for ordinary compilation, native
functions, synthetic native AsyncFunction bytecode and bytecode deserialization.
Nested user functions inherit only their lexical module's origin. All bytecode
allocation/copy/read paths must be enumerated, not inferred from mallocz. The
reviewed async/C allocation machinery is otherwise untouched.

The lifetime contract deliberately follows existing loaded_modules context
ownership. JS_DupValue on a JS_TAG_MODULE is NOT an independent lifetime proof;
JS_MarkValue does not mark ModuleDefs as ordinary GC objects, and their terminal
tagged free path is not a module reclamation API. Module namespaces/reexport
autoinit, TLA callbacks and escaped closures also depend on definitions. Phase1
keeps graph/origin records until owner-context teardown, with charged allocation
and explicit accounting. Context teardown frees definitions before descriptors.
No arbitrary reload-count limit is invented. Existing C/host memory quota must
charge this retention and preserve the reviewed trusted allocation failure path.
Graph GC or a separately reviewed resource/lifecycle policy remains a production
gate. A refcount on the capability does not solve module/bytecode cycles.

Compile/link creation is recorded per private attempt. Shared0 modules and
older private graphs are excluded from its accounting/cleanup. The existing
resolved flag is insufficient: it is set before recursive child resolution.
No context-wide unresolved-module sweep is used as a private rollback. Existing
global error sweeps must not reap context-pinned private definitions. Phase1
quarantines failed private attempts under their owner context; any scoped early
free must prove that no linked namespace, evaluation callback or escaped closure
can reference the definition. Once execution begins, an error cannot authorize
tearing down the whole graph: guest code may already have escaped a closure.
Default graph0 cleanup remains unchanged when the new capability is unused.

Graph0 bytecode serialization format and existing read APIs remain unchanged.
Private origins/capabilities are context-local and are not serialized as
pointers, IDs or physical-name guesses. Writing private graph module/bytecode
through a bytecode writer explicitly rejects before publication of an output
buffer. Deserialization always starts with NULL origin and cannot revive a
private capability. Structured-clone behavior for ordinary values/functions
must retain its existing errors. Private serialization is an explicit phase1
unsupported operation, pending separate design and review.

The prepared tests must cover graph0 baseline serialization and behavior;
distinct private TS graphs with self/indirect cycles; exact origin import.meta
for nested functions and attributes; static and live/late dynamic cache policy;
parallel TLA and old namespaces; physical URL and full stack names; concurrent
fresh attempts; partial compile/link failures without shared/old-graph cleanup;
escaped closures after evaluated failure; all allocation boundaries and final
context teardown accounting; and the explicit private serialization rejection.
They require reviewed Root native admission before execution. These are new
capability tests, not inherited qualification from Source or the async primitive.

The Source policy is still incomplete for .mts/.cts/.tsx, native JS/MJS to TS
edges, native-import failure followed by transform fallback, failed late-import
retries/error identity, direct/indirect eval/new Function import(), symlink/case
canonicalization and attribute/relative-alias combinations. Engine classification
and cache integration must remain a separate proposal and fail closed for
unobserved private routes. This C prototype is not default-loader completion.
