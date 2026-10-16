Proposed Engine-owned fresh-root API, pending genuine jiti reload observations.

The current QuickJS source establishes these concrete lifecycle constraints:

- JS_EvalInternal with MODULE allocates a new JSModuleDef and appends it to the
  context loaded_modules list. COMPILE_ONLY still resolves dependencies before
  returning its owned module value. Alias/cycle routing must exist before this
  call, rather than being installed after compilation.
- JS_EvalFunction consumes that owned compiled value, then creates module
  functions, links and evaluates. It returns the actual evaluation promise.
  A native AsyncFunction Body must emit one Await action; nested awaitValue/job
  pumping would change execution ordering.
- JS_LoadModule creates a promise but finds the first matching loaded module.
  Compiling another root under the same physical name therefore cannot safely
  implement reload/self-import: normalized self references can bind an old root.
- Existing Engine.setImportMeta supplies physical file URL/path metadata. The
  native worker SourceLoader already resolves user modules, transforms actual
  TypeScript input in Zig/tree-sitter and handles CJS/JSON with native require.
  CJS loading has its own root cache and needs a separate exact-root policy.

The proposed API owns an immutable root identity for each import attempt, its
physical path, compiled-module value, evaluation promise and namespace. An
opaque GC-marked owner or an equivalently rooted Engine record retains the
compiled value through evaluation; callers never retain a naked ModuleDef
pointer across Await. Duplication and consumption are explicit: EvalFunction
consumes one reference; the owner retains another until namespace extraction.
Existing live namespaces and their module identities remain retained.

Use a distinct private root key per import and normalize that key through an
Engine-owned physical-path map. Set import.meta using the physical path, never
the private key. Relative imports resolve from the physical directory. Direct
self-import must resolve back to the same private root. This routing starts
before COMPILE_ONLY linking, not through a global module-cache clear.

Dependency policy is not chosen yet. Genuine pinned jiti controls will record
same-file root edits, same-file dependency edits, repeated side effects, old
namespace/closure stability, physical import.meta URL and direct/indirect
cycles. The observations must distinguish transformed TS dependencies, native
ESM dependencies and CJS require caching. Shared dependencies cannot be rebound
globally to a new root while old live graphs still reference them.

Failure/GC controls must cover compile/link/evaluation rejection, delayed TLA,
concurrent fresh roots, stale extension-cache tokens, allocation at each owner
boundary and exact metadata-map retirement. Only the attempt's private record
may be retired on failure; no other module or cache entry is cleared. This is
an API proposal, with no Engine/C edit or native execution in this lane.
