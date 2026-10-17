# Actual nativeImportOrRequire declaration + private assembly — source only

This closes the concrete missing declaration in the source canonical bootstrap.
It does not rename an importer as jitiRequire, replace either real algorithm,
provide an empty namespace/registry, select defaults, or add a Promise/AF.
All Node/generator/formatter/AST/compiler/native jobs remain unrun. Main, C/H,
Engine, shared callable/AF helpers and historical proof/expected files are intact.

## Exact pinned Source contract

Original jiti2.7 fd3bb289b75ed207edfb686d671ed50144f7e90f require.ts exports
the ordinary declaration nativeImportOrRequire(ctx,id,async?), name unchanged,
length3, constructible. Its async truthiness short-circuits the first live
ctx.nativeImport read. A truthy result leads to a second live nativeImport
callee read, actual normalizeWindowsImportId(id), ctx method receiver, then
the returned value's live .then lookup/call with that value as receiver. The
actual interop arrow maps the real fulfilled module through jitiInteropDefault.
The declaration returns the exact RAW .then result. A falsy async/import selects
the live ctx.nativeRequire member call and actual interop; no Promise is added.
Getter, normalization, callee, invocation and .then failures remain synchronous
ordinary throws from this declaration. A genuine rejected import remains a
real returned Promise, not a synthesized wrapper or synchronous conversion.

The real normalization is the pinned utils.ts static std-env isWindows value,
actual pathe.isAbsolute and mlly.pathToFileURL. Required concrete capabilities
are these actual module imports plus the actual live context nativeRequire/
nativeImport/opts. They cannot be fake callbacks returning namespace substitutes.

## Source implementation / canonical transaction

`native_jiti_require.createNativeImportOrRequire(engine, Inputs)` constructs
the real ordinary declaration through the reviewed charged/marked callable,
using the SAME actual inputRoots/fromRoots and UNCHANGED nativeImportOrRequire
host algorithm already source-reviewed in ca974. Its interop callback is the
same real canonical callback implementation, not an identity replacement.

The new private entry suppresses formatting through its actual ModuleCallable
trampoline, isolates prior diagnostic capture ownership, preserves an actual
pending VM event before argument/context getters, and classifies only new
current capture/fresh private allocation causes. Missing actual JS failure
state fails closed. If an actual pending host event remains despite a success
value, the exact pending reason is retained BEFORE releasing that success value
and propagated instead of publishing a false success. This local entry guard
does not change a shared policy or infer anything from a rejected data flag.

Canonical link now constructs actual jitiRequire AND nativeImportOrRequire
privately from the same fully real Inputs with eval_module=record.frontend.
FrontendDependencies no longer has a caller-provided native_import_or_require
slot. Both constructors finish before fixed/precharged import-record commit;
the actual new declaration is installed in the frontend, and same actual
jitiRequire remains in core/frontend. Neither staged function is exposed before
linked initialization/ready exports. Failure creating the second declaration
releases its partial native storage and the first staged owned function root,
returns declared phase, and leaves imports uncommitted. Any function/prototype
cycles remain visible and charged until actual GC. Full context/class-registry
or Graph2 reclamation is not claimed.

## Primitive boundary

This declaration does NOT need a new Graph2 or queued-C3 adapter. It invokes
the actual live ctx.nativeImport exactly as Source does. The production parent
context must supply a genuine qualified queued import capability when that
branch is used. The separate DA14/A79 Graph0 binding and privateGraph/Source39
policy/reclamation gates are not copied, changed, selected or qualified here.
Reference/user controls may use genuine guest dynamic import through the linked
VM, with a real owned physical module; that is user input, not a production JS
host bridge. Missing parent capability cannot be filled with a dummy importer.

## Prepared genuine contrasts

Original user inputs take actual native require/import functions. Proxies only
observe/delegate the real receiver/arguments/results. The imported Promise is
real; its user-observed .then delegates the real then and can return a marker,
so raw identity is measurable without substituting an importer/namespace.
Native contexts/options are real direct caller data for the original export.

Eight native controls plus the explicit native probe installer are prepared:
canonical distinct declarations with identical17 actual captures/frontend;
real raw .then return; sync real require without any import getter; exact
synchronous actual getter/call throw; pending actual event before getters;
pending actual event over success value; fresh actual native OOM; second staged
declaration allocation failure/rollback and genuine retry. The last uses the
pinned0.16 FailingAllocator to fail the third GPA allocation after real bodies/
namespaces exist: first require state+17roots succeeded, then nativeImport state
fails. It requires an exclusive Engine with no tasks/jobs and restores the same
backing allocator before later GC/finalization. No fake Source callbacks run.

All controls/causal traces remain UNRUN, expected absent. Completed real Subjects,
independent source review and later owned native gates remain required. Public
package wrapper, reviewed default-transformer composition/full profile, remaining
namespace/resolver inputs and default SDK/runtime qualification remain separate.
