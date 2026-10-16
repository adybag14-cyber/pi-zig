# Resumed TLA source candidate after reviewed design

This prospective record is authored in the relocated worktree
`C:\Users\adyba\pi-zig\worktrees\runtime-tla`, starting from clean
`b9701e111cdecc2e4da3f0457e24066bbcd6a208`. Historical design/manifest/negative
bytes retain their original paths and meaning. The container's explicit
`path-relocations.json` resolves old paths; relocation is not a new execution.
Runtime recovery is pending. No Node, Zig, C compiler, formatter, generator,
Source observer or native runtime job ran for this candidate.

## Actual delta

`vendor/quickjs/quickjs.c` is the only product edit. Header, Engine, native-body
resume semantics, Promise reaction job implementation and module namespace
assembly are unchanged. No public ABI, module serialization format, GC owner
or new context reference is introduced.

JSAsyncFunctionData gains an initially NULL borrowed module pointer and a
module-execution flag. The latter survives termination so a queued callback
can recognize an inactive module state after its pointer/frame were cleared.
Native states are allocated with js_mallocz and keep both additions zero;
ordinary bytecode calls explicitly receive NULL through their unchanged class
callback wrapper. Only js_execute_async_module calls the internal helper with
its exact ModuleDef. Synchronous module calls use the ordinary wrapper.

The actual module pointer binds only after initial bytecode resume succeeds,
has no pending reason and leaves the state active. A pending initial module
failure terminates the active state before freeing its local reference and
holds the raw reason outside current_exception through cleanup. Initial fatal
START remains in the existing DFS executor's failure bookkeeping.

On later fatal bytecode completion, the state records its associated module's
terminal outcome through the reviewed linear, allocation-free parent worklist
before frame release. The same owned pending reason is restored after state
termination and returned to the existing job queue boundary. No error name,
tag, filename, ambient module or Promise identity is used to find the owner.

The borrowed pointer's lifetime is the reviewed active frame.cur_func ->
function bytecode -> duplicated/GC-marked realm -> context.loaded_modules
chain. Termination clears the pointer before freeing any frame root, including
GC finalization. No finalizer dereferences it and no new GC edge is needed.

Before a module continuation writes throw_flag or cur_sp, it now no-ops if the
state is inactive. If an outer attachment already recorded any module failure,
ordinary or fatal, it terminates the still-active state and no-ops before any
guest instruction executes. The original executor/cached module owns delivery
of that stored outcome: late callbacks do not throw it again, reset its
uncatchable flag or retag it. This clarifies the earlier design's tentative
proposal to return the stored reason again from a late callback.

Module-only await guards stop at a pending reason after PromiseResolve,
continuation creation or perform_promise_then, including its zero-plus-pending
case. Pending reasons are retained before owned continuation cleanup. Ordinary
rejections still reject the existing body/module Promises. Nonmodule callbacks
take their existing null-owner path; native-body resume code is unchanged.

## Prepared controls, all unexecuted

The seven existing START/attachment controls remain unchanged. The historical
prepared known-gap control remains unchanged. A new separate
`src/native_tla_resumed_fatal_delivery_test.zig` has six declarations:

1. Resumed direct body fatal with a waiting parent; exact reason survives host
   classification, cached child/parent entry and a fresh importer.
2. Ordinary and fatal outer attachment failure while the body awaits an actual
   thenable. After restoring the real Promise constructor, actual late jobs
   must retire without executing the body's counter increment. GC runs before
   late callback delivery, and cached reason/Promise identity remains exact.
3. The public host rejection tracker leaves a raw pending reason during
   perform_promise_then, before a successful enqueue. A queued module callback
   then outlives the terminated initial frame and must no-op safely. Its counter
   remains zero and the host sees the exact pending reason.
4. Two actual ModuleDefs compiled with the same physical filename. Only the
   failing definition becomes terminal; the other remains pending, then
   completes when its real gate resolves, including a GC checkpoint.
5. Ordinary nested nonmodule async return/rejection identity remains unchanged.
6. A genuine public Promise hook leaves a fresh native uncatchable reason
   while a resumed module's intrinsic resolving callback returns undefined.
   The module must deliver that exact reason terminally, retain cached failure
   after classification, and safely ignore any already queued fulfillment.

Independent review of the first resumed candidate found the sixth path:
resolving callbacks can return undefined despite a pending fatal exception.
Module-only checks now retain that reason immediately after both resolving
calls, before returned/thrown value cleanup, and mark fatal state at the common
termination point. This is confined to uncatchable reasons; catchable enqueue
pressure at the resolving-call boundary remains a separate explicit scope and
does not acquire fatal classification. The ordinary null-owner path is unchanged.

The sibling new build snippet prepares a separate resumed gate. Shared
build.zig is unchanged. No test has been syntax-checked or executed. These
controls establish no resource, allocation-position or lifetime success yet.

## Remaining scope

This associates only the actual top-level module bytecode coroutine. It does
not attribute an independently scheduled nested ordinary async function's
fatal failure to a waiting module, or alter that null-owner behavior. Existing
gather_available_ancestors allocation failure and broader recursive rejection
handling remain separate controls. Full module-failure/core qualification is
not claimed. Root and independent C-owner review of the complete delta must
precede any execution grant.
