# Private live imports for actual jiti core/eval declarations — proposal only

Source-only proposal under Root's cycle-model approval. No C/Engine/shared
policy change, execution, placeholder factory or empty registry is authorized.
Actual core/eval callback bodies remain the product; the cells only hold their
real import bindings and keep declaration identity stable through bootstrap.

## Concrete Zig surface

New scoped `native_jiti_module_cells.zig`:

* `declare(engine, Bodies{core: NativeCallback, frontend: NativeCallback}) !Cells`
  creates actual ordinary constructible functions named createJiti(length1)
  and evalModule(length2), using the real native source body callback pointers.
  Both capture one private GC-owned record, initially unlinked. No functions
  are exported, registered, cached or exposed to Source by this operation.
* `link(engine, *Cells, Bindings{core: CoreImports, frontend: FrontendImports})
  !void` validates actual callable/static dependency values without invoking
  guest getters or callbacks, duplicates/stages all owned JS roots and commits
  exactly once. The record itself supplies the exact real core/frontend
  counterparts, so callers cannot substitute an unrelated factory/evaluator.
* `initialize(engine, *Cells) !void` runs the actual Source module-scoped
  platform capture after complete linking, computes isWindows exactly, then
  marks ready. Only after success can an assembler obtain or publish exports.
  It is not a public Source call or a partial-namespace cache operation.
* `exports(engine, *Cells) !Exports{createJiti,evalModule}` returns owned
  duplicates of the same actual functions only in ready phase. Repeated calls
  preserve their identities. This is a host record, not a fake ESM namespace.
* Body-only `requireCoreImports/requireFrontendImports(engine, private_owner)`
  checks Engine and phase and borrows the stable real bindings for the native
  callback. Any premature internal invocation throws an actual VM reference
  error instead of returning dummy data. Actual Source bodies keep their own
  name/arity/constructibility/receiver/raw-return/error semantics.
* `Cells.deinit()` releases host roots and invalidates this move-only owned
  handle. Source functions/namespace references retain the private record as
  long as they remain live; no stale raw opaque token is exposed to callers.

`Cells` contains only its owned private owner JSValue and private class ID.
The actual function references and typed import records are held inside that
record, not as Source object properties. Caller code never receives prelink
function references via this API. Native body callback pointers are static
real implementation declarations, not JS delegates or alternate fake subjects.

## Identity, lifetime and OOM boundaries

The private owner is a dedicated native JS class with null prototype, a charged
native record and exact Engine pointer. Its class ID/opaque membership and
Engine identity are checked before using it. The native finalizer and gc_mark
visit/free all owned function and binding JSValues. Ordinary function roots use
the already reviewed charged/marked callable implementation. Owner/function
cycles are ordinary VM-visible edges, with no global map or context-pinned
host registry. This is not a claim that C Graph2 reclamation is solved.

`link` receives typed host import structs containing actual already-created
JSValues and static data, not a JS object to enumerate. It must not invoke
Source getters, require(), proxy property reads, callbacks or module evaluation.
Required real callable values are checked without reading Source properties;
package JSON/iterator and namespace identities are retained as actual values.
Core's real eval import and frontend's real nested-core import are installed
from the declared functions themselves, never from a supplied surrogate.

Before commit, all native allocation bytes are reserved in aggregate and all
JS roots duplicated into staging. Every failure frees staging/roots/reservations
and leaves declared phase unchanged; no partially installed import record.
Commit is a nonfallible field transfer plus phase change. A second successful
link or foreign Engine/handle is rejected. No global ambient current module.

Module static initialization may execute the genuine platform function only
after all real bindings and counterparts are linked. On initialization error
the producer discards the unpublished graph and releases its roots, preserving
the exact ordinary/fatal error. It does not cache partial namespace/functions.
Any now-unreachable cycles are visible to the VM's normal collector; no hidden
never-freed native allocation is permitted. Memory remains charged until that
actual collection, rather than being falsely reported as immediately reclaimed.

No Source getters, public core/eval calls or export publication occur before
complete link. Export access additionally requires successful static init.
Ordinary Source error reasons retain ownership before fallible cleanup; fresh
trusted allocation failure bypasses Source catch, with current-boundary exact
tag checks and no name-based or historical classification.

## Required real inputs and controls

Core imports include actual options algorithm, require/resolve, transform,
debug/cache-dir utility, pathe/mlly URL+alias functions, library require,
escape-string-regexp, actual platform, package JSON and intrinsic iterator.
Frontend imports include actual resolver/path/syntax/package/transform policy,
Module8a and 4d body; its nested counterpart is the declared actual core.
Absent real dependencies prevent linking; they are not filled with no-ops,
empty modules, replacement caches, identity functions or fake getters.

Prepared controls must cover foreign Engine, duplicate link, prelink exports/
internal call, rollback at every staged allocation, stable exact callable
identity/metadata across cycle, real root release/GC, init failure without
publication, no getter/callback during link, and completed-real-input cycles.
Positive whole Source subjects remain pending while actual imports are missing.
No expected observations or runtime qualification are created by this proposal.
