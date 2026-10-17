# Link-only ownership and rollback design after actual V8 inspection

This is a concrete source design, not C implementation permission. It supplements
111ed2f7/124f2eae; their earlier unspecified fatal-latch/undo alternatives are
not implementation authority. The proposed public signature remains:

    int JS_PiLinkModuleGraph(JSContext *ctx, JSValueConst compiled_module);

Zero means actual declarations/bindings prepared without module body execution.
Minus one leaves the exact actual VM reason pending. No Promise, loader,
normalizer, evaluation, namespace-as-answer or job pumping substitutes for this.

## Primary decision: restore failed environments, retain completed SCCs

Pinned Node f657bb8ed86365ff3fdbe32e27563e778b41486a V8 objects/module.cc
Instantiate calls ResetGraph after PrepareInstantiate/FinishInstantiate failure.
ResetGraph only resets pre-linking/linking nodes; completed linked dependencies
remain intact. Reset recreates the failed environment/export state as unlinked.
The same pinned Node ModuleJobSync.runSync calls instantiate before testing TLA.
Thus a permanent ordinary failure latch would not be a faithful substitute for
linking rollback. This design chooses explicit rollback, not that latch.

The initial proposed escaped-prologue getFunction route was a compatibility bug:
V8 builtins-callsite withholds strict/top-level functions; isolate's CallSite
builder poisons strict and older frames. C3 directly exposed its stored func.
The separately source-reviewed CallSite correction 328eab6e fixes that route.
No shared/nested-bytecode guard architecture is justified by this incorrect
exposure. No such guard or failure-holder field is proposed here.

## Admission and effects

Require owner-thread live context/root, no context disposal/concurrency, no
module graph mutation or guest reentry through host callbacks during the call.
The interrupt callback is the existing trusted Engine cancellation/budget
callback. Error capture must be the genuine capture-only native Node Error
stack owner (or an equivalently nonreentrant native capture-only owner); no
legacy eager guest prepareStackTrace invocation is admitted during preparation.
The actual native_error_stack.capture uses data-only stackTraceLimit, captured
private WeakMap operations and actual CallSite capture; it does not format the
error or read guest stack/message/toString. The host adapter must retain its
balanced diagnostic suppression and must not format until C returns. This
callback contract is a real prerequisite, not inferred from a non-NULL pointer.

Use qualified C4 graph validation (never early-return just because TLA is found)
for actual root/edge context membership, resolved flags and cycle safety before
mutation. TLA is metadata only at this stage, not a reason to skip binding errors.
The transaction then builds an iterative charged ledger in static-request DFS
preorder. Existing healthy LINKED/EVALUATING_ASYNC/EVALUATED nodes are accepted
and preserved, including their owned cells and namespaces. Reject LINKING or
synchronous EVALUATING roots/edges, corrupted/partial edges and inconsistent
healthy-to-fresh dependency states before touching them.

Fresh nodes must be UNLINKED, func_created=false, namespace undefined, no
existing export var_ref, no evaluation promise/outcome, with raw function
bytecode for script modules or a genuine native init function. Do not silently
adopt old legacy partial-create state. Already healthy linked roots can be a
validated no-op; ordinary cached/evaluation errors stay actual caller policy.
No creation-time global unresolved/unevaluated-module sweep is permitted.

One checked VM-charged native block contains membership table, DFS work/iterator
frames and per-node snapshots. Capacity is a power of two >=2*M, load <=1/2,
lookup probes <=capacity; counts, byte sizes and growth are checked. Work and
ledger entries are bounded by M context modules. Poll actual js_poll_interrupts
and actual pending state through count/populate/probe/edge/snapshot/creation
loops, not fabricated counters or clocks. Owned snapshot values use JS_DupValue
(no allocation). No ModuleDef/entry array is freed or relocated by rollback.

A private context boolean rejects nested use of this API and selects its
strict pending-result checks; it has no Engine/public ABI field or serialized
representation. It starts false and is reset on every exit. It is not a claim
that arbitrary hostile C callbacks can be made safe; the above contract remains.

## Creation order and partial-create hazards

Extract the existing one-module creation work into a private local helper.
The old default recursive helper can continue using that local helper. The new
API invokes it in the ledger's real request-order preorder, avoiding unbounded
C recursion before the linker's own stack checks. Mark a ledger node touched
BEFORE calling local creation, since native export creation can fail halfway.

Two real baseline hazards must be closed by the transaction: native export
cells are stored before func_created=true; and a parent's func_created becomes
true before a recursively created child can fail. Retrying those partial fields
would leak/overwrite cells or skip the child. The snapshots/rollback below
restore both; merely resetting status or adding a root latch would not.

After local creation succeeds for all fresh nodes, call the real linker, whose
existing DFS/SCC behavior and stack check remain. Its module-prologue JS_Call
is actual declaration initialization with this=true. The emitter returns before
the body label; it does not call native module init functions or run any module
body. During this opt-in transaction only, check actual pending state immediately
after the prologue call even if it returns undefined, own that reason before
result cleanup, and fail BEFORE marking its SCC linked. No rejection-data bit,
private error tag, name, message or prototype is used to classify this result.

## Namespace construction must stop its real producer failures

Two inspected legacy producers are prerequisites inside this same opt-in scope:
exported_names_cmp currently converts two atoms to strings and returns equality
on allocation failure, letting later comparison replace the pending reason;
js_build_module_ns ignores the final Symbol.toStringTag string/property errors.
A wrapper around the old linker cannot promise first-reason safety while those
are unchecked. Default inactive behavior is not silently broadened by this API.

For the transaction's namespace construction, materialize every export atom's
actual JS string once, checking exception AND pending immediately after each
conversion. Use one checked VM-charged workspace with owned key values (tracked
initialized count) plus two index vectors. Bottom-up stable mergesort of indices
compares actual UTF-16 units with bounded actual interrupt/pending polls through
comparison, merge and copy loops. It makes no allocations or coercions after
key materialization. Property insertion follows sorted indices into the actual
export records; the original record array is not overwritten through pointers.
Keys are freed exactly once from their ownership array, not duplicate index
copies. An interruption stops immediately, not after an uninterruptible qsort.

Check the actual Symbol.toStringTag atom-string result, then its actual property
definition result/pending state before admitting the namespace. On namespace
failure hold the actual first pending reason outside the pending slot over
owned object/key/workspace cleanup, then restore it. This is concrete opt-in
producer work, not a blanket shared Promise/namespace error-policy rewrite.

## Snapshot and reference accounting

For every fresh node retain its original raw func_obj as one owned snapshot;
record func_created, status, DFS indices/ancestor, stack_prev and original
namespace/export-reference invariants. Static atoms, requests, export indices
and resolved pointers are never modified by this API. Script creation adds a
bytecode reference for the new callable then releases the module's old raw
bytecode reference; the snapshot keeps that bytecode alive. Native local cells
are detached JSVarRefs whose value is heap-owned, not a pointer into a ledger.

Linking adds actual per-import var_ref references, per-export references and
namespace property references. They are independent counts: a namespace property
increments its cell reference; imported aliases increment it; a module export
entry increments it separately. Failure cleanup releases only the reference
owned by the field being removed. It never forcibly destroys a var_ref merely
because another module is rolling back.

On failure first move the actual pending reason to an owned local. The actual
linker resets remaining LINKING nodes to UNLINKED. A fresh SCC already LINKED
has completed its declaration preparation; keep its function, export cells,
namespace and DFS state, and just release its unused snapshot. Existing healthy
shared dependencies were never snapshotted for restoration and stay untouched.
If creation failed before linking, all touched fresh nodes remain UNLINKED.

For a touched failed UNLINKED node, clear its current namespace field before
releasing that one namespace root; clear each non-NULL local export reference
and free precisely that reference; transfer the owned original raw func_obj
snapshot back into the module and release its replaced callable reference.
Restore func_created=false and original status/DFS/stack fields. Untouched
snapshots are released. No native allocation, atom/string conversion, property
lookup, formatter, user callback or module-definition free occurs in rollback.
Keep the original reason owned throughout all value/ref cleanup and restore it
with JS_Throw exactly once after cleanup. Do not retag it or manufacture a new
OOM reason. Snapshot/free work is bounded by admitted nodes/exports, with no
quadratic whole-context fixed point and no recursive graph cleanup.

## Nonescape and retained error stacks

Admission rejects already exposed fresh namespaces. During preparation no
body/native init is executed, no resolver callback runs and the admitted error
hook captures but does not format or call guest code. Prologue-created function
and namespace objects therefore have no Source-valid publication route before
success. Newly completed SCCs are deliberately retained instead of rolled back.
A completed dependency cannot statically depend on a failed ancestor outside
its SCC; otherwise it would not have completed. Dynamic import is not executed.

An error can retain the old module callable through its private captured frame;
this is not a guest getFunction escape once strict/top-level visibility is
correct. Do not force-free that callable. JS_FreeValue of the module's reference
leaves the captured-frame reference alive. Its own detached cells, import alias
references and bytecode remain independently retained until the error/frame is
released. Existing namespace normal properties retain cell references; namespace
autoinit entries may retain ModuleDef pointers, but definitions/arrays are never
freed by rollback and their context is still owned. No pointer is rebound to
freed native ledger memory. Old raw function/data remains internal; strict
caller/arguments access cannot expose it. A host that deliberately unwraps
opaque internals or disposes/mutates the context violates admission, not Source.

## Default entries, retries and honest remaining scope

There is no persistent ordinary prepare-error latch. After failure, unlinked
nodes again contain original bytecode/empty native cells and can be retried by
this API or ordinary EvalFunction without the two partial-create hazards.
After success the ordinary evaluator sees real linked functions and does not
repeat creation/prologue. Fatal interruption/OOM still returns the actual same
pending failure; undo is safe here because no module body ran. This is not
rollback of an evaluated module or alteration of C2's recorded terminal module
fatal/evaluation outcome. No new tag, module-evaluation promise or cached-fatal
replay policy is introduced. Generic legacy callers that never use this
transaction retain their old behavior; their separate existing retry safety is
not claimed by this API. Serialization sees ordinary restored/linked values,
not a private guard/latch that can be bypassed by writing bytecode.

Required future causal controls: native-cell and bytecode creation failures at
actual allocation positions, late child failure, missing/ambiguous bindings,
namespace numeric/empty/Unicode ordering and key/property OOM, cycles/diamonds,
completed fresh SCC preservation, existing evaluated dependency preservation,
prologue success/pending and actual interruption before body, retained error
frames across GC/rollback/retry, exact first reason, no body/native-init/jobs,
repeated ordinary failure and successful retry via both API and default entry.
They must use actual APIs/allocator events and ownership, not ModuleDef setters.
The bounded original Node retry/SCC caller inputs have no expected or observed
output until a separately granted original capture. Neither this design nor
CallSite source closure qualifies implementation, Node require(esm), or a full
CommonJS/jiti bootstrap. Independent C design review precedes any authoring grant.

## Finite review clarification: pending entry and complete poll frontier

ANY actual pending VM reason at entry is refused before tag/member inspection,
allocation, polling, snapshots or transaction-flag mutation. Return -1 with that
same pending value unchanged. No historical captured slot or data flag is used.
If membership/ledger allocation, population, snapshot polling or any other
pre-mutation preparation fails, move the actual pending reason into an owned
local BEFORE releasing any initialized snapshot roots/native buffers. Release
only initialized ownership; no module field rollback is needed before mutation.
Restore the same reason exactly once and clear the private active flag on every
exit. This includes a successful native operation that nevertheless leaves an
actual pending reason. Cleanup does not poll or invoke new abort callbacks over
an owned first failure; it is bounded linear native/ref-count retirement.

The opt-in normal-operation polling scope is specifically:

- One-module creation: each native local export-cell creation and each bytecode
  closure/global-slot creation loop, plus post-helper pending checks.
- js_inner_module_linking: actual entry stack check plus budget/pending poll;
  every request/dependency, indirect-export, imported-binding, local-export
  reference capture and SCC-pop iteration; immediate actual pending checks after
  namespace/local-reference/prologue producers before new diagnostics/work.
- js_resolve_export1: actual stack-limit check and poll at every recursive entry,
  indirect hop and star-export iteration. Its visited-set find/add scans and
  actual find_export_entry scans also poll; their private lookup status must
  distinguish interrupted failure from ordinary not-found. An interrupted
  lookup propagates JS_RESOLVE_RES_EXCEPTION, not a new missing-export error.
- js_get_local_export_var_ref1: actual stack-limit check/poll on recursive entry,
  import-alias scans, visited lookups/additions and recursive resolution. A NULL
  with actual pending state is propagated before a generic circular-binding
  diagnostic; NULL without pending retains its real ordinary resolution policy.
- get_exported_names: actual stack-limit check/poll on recursion, visited-module
  scans, each direct export, duplicate-name scan and star-export edge. Private
  find_exported_name receives context and has a distinct failed status so an
  interrupt cannot be confused with absence and followed by allocation.
- Namespace building: exported-name resolution, key materialization, UTF-16 key
  comparison/merge/copy, property insertion and actual final tag property; each
  loop polls through the opt-in context flag and stops before downstream work.

The existing recursive export helpers currently lack the required stack/budget
checks in these paths; the proposal does not treat their legacy implementation
as already bounded. These additions use actual js_check_stack_overflow /
js_poll_interrupts and preserve their actual reason, with inactive behavior
unchanged. This is neither an injected clock nor a claim that recursive export
resolution is linear time. Metadata-only preflight/rollback storage and cleanup
are bounded by admitted modules/exports; the real resolution algorithm has its
own potentially larger work cost and must remain interruptible throughout.
