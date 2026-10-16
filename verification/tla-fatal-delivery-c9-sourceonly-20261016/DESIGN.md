# Fatal TLA delivery: source-only C9 successor

This is an authored source candidate, not a compiled or executed repair. No
Zig, C compiler, formatter/AST gate, Node, Source observer or native runtime job
was launched for this candidate. Root and independent C-owner review are
required before any qualification grant. Existing Source inputs and expected
observations are unchanged.

## Authority and isolation

- Isolated worktree: `C:\Users\adyba\pi-zig-tla-fatal-delivery-c9-20261016`.
- Base: `7bf652e57c2bd5928e1ab2e357a8dc868ddc8c51`.
- Base `vendor/quickjs/quickjs.c` SHA256:
  `E2F988956B452EBACDDC1B24AB45E5F70F7AFB4777F7452EDF1457649B2D1D3B`.
- Unchanged `vendor/quickjs/quickjs.h` SHA256:
  `341CF06F8041B8311D49767026C85C7B859BCFEE3088380F3FFE6D77527052AB`.
- Failure authority: exact Models candidate
  `05f1e971566da1c22f2895cc1f0fd37ee89d6775`, evidence
  `C:\Users\adyba\pi-zig-update-evidence-20261003\actual-models-root642-first05f-20261016-runtime.stderr.log`.
- Product edit: `vendor/quickjs/quickjs.c` only. Header ABI, Engine, native
  AsyncFunction implementation/adapter, Graph2 and Root worktrees are untouched.

## Concrete failure

The real refresh GPA probe completed its 300-allocation baseline. At failing
allocation 160, `native_sdk_prompt_scope.Scope.own` failed while retaining a new
object in `native_ai_models_refresh_publication.initialize`, called by
`refreshBody`. Scope frees its unretained value. The genuine native async START
adapter correctly throws a new, privately tagged, uncatchable native allocation
reason. The enclosing compiled asynchronous module returns `JS_EXCEPTION`.

`js_execute_async_module` returned -1, but the has-TLA branch of
`js_inner_module_evaluation` ignored that return, left the module asynchronous,
and returned its pending module capability. Engine.checked saw a non-exception
Promise, and the empty job queue produced `JavaScriptPromiseUnsettled`.
The observed boundary/current/captured-tag/retained-tag was 0/1/0/1, with one
job attempt and one empty poll. This demonstrates absent delivery to Engine's
capture boundary; it does not establish destruction of the raw reason.

The same ignored return occurs when a fulfilled dependency starts a TLA
ancestor in `js_async_module_execution_fulfilled`. That function also needs to
return fatal synchronous-ancestor failure to the actual promise reaction job.
Finally, `js_execute_async_module` previously ignored failure while constructing
either continuation function and while attaching `js_promise_then`.

## Changed behavior and ownership

1. Async module start and each continuation/attachment operation are checked
   immediately for both exception return and pending exception. No subsequent
   attachment is attempted after failure. The first pending reason is retained
   outside runtime current_exception during cleanup and then rethrown unchanged.
   Promise, module token, two functions and attachment result each have one
   cleanup path, initialized with undefined before partial construction.
2. Immediate failure enters the existing evaluation-stack failure bookkeeping.
   An uncatchable result is returned as `JS_EXCEPTION`, without calling the
   module Promise rejection function. Ordinary failure uses the previous
   rejection path.
3. Deferred ancestor failure records the fatal outcome in the failed module
   and its waiting async parents and returns the exact reason to the existing
   promise reaction job. The latter already returns uncatchable failure to
   `JS_ExecutePendingJob`. Propagation uses an allocation-free, failure-only
   fixed point over the context's loaded modules. It neither recurses nor frees
   ModuleDefs. Already evaluated modules are skipped. The execution-list
   allocation is freed before returning.
4. A private ModuleDef boolean records fatal evaluation separately from the
   retained reason's mutable uncatchable flag. Engine.nativeAllocationError
   clears that flag when it classifies a fresh native OOM. Cached module entry
   must still rethrow the stored outcome rather than return its pending
   capability. Cached retries duplicate the same reason, without resetting the
   flag, allocating a replacement error, increasing native generation, or
   interpreting error names/tags. Recursive evaluation carries the fatal
   outcome separately when a new importer depends on a cached failed module.
5. Each retained reason remains in existing `eval_exception`, already marked
   and freed by ModuleDef ownership. The new boolean owns no value and is
   initialized in `js_new_module_def`. JS_TAG_MODULE tokens still provide no
   independent GC ownership; context loaded_modules retains the definitions.

Ordinary guest errors, InternalError lookalikes, and previously classified
native reasons remain ordinary rejection values. The product change makes no
generation-based classification decision; that remains at the existing Engine
boundary. The previous module Promise can remain pending after a host-fatal
abort: the fatal operation terminates via exception, and subsequent module
entry rethrows. This patch does not convert a host abort into guest rejection.

## Prepared controls (all unexecuted)

`src/native_tla_fatal_delivery_test.zig` contains seven test declarations:

- Immediate genuine native START OOM: raw exception, exact identity, host
  classification, cached retry after clearing the uncatchable flag, healthy
  module reuse, then another exact cached retry.
- Engine.evalModule immediate delivery and fresh allocation classification.
- Deferred TLA ancestor START after a real TLA dependency, including a waiting
  parent and a fresh importer of the cached failed module.
- Deferred synchronous ancestor with the same dependency/parent controls.
- Raw object, InternalError lookalike, and historical native reason: exact
  rejected Promise and exact cached Promise identity, without fresh-OOM
  classification.
- std.testing.checkAllAllocationFailures of an actual native body using
  Scope.object, including failure while growing Scope.own and owned teardown.
- 65 bounded C memory quotas armed at the end of a syntactically asynchronous
  module, before module continuation attachment. Every observed outcome must
  terminate and retain its cached reason, and a healthy module must still run.

The quota control targets completion/handler0/handler1/then allocations. No
claim is made that a particular quota reaches a particular site, nor that the
allocation positions are exhaustive: an authorized instrumented run must
establish that. The tests have not been syntax-checked or executed. The sibling
build snippet is prepared for integration into the existing build scope; the
shared build.zig is unchanged.

## Explicit limits and next review

This is confined to fatal/start/attachment delivery. Existing module graph
allocation failure while gathering ancestors, ordinary recursive rejection
callback handling, dynamic import's separate rejection bridge, interruption
and full-context teardown still require their own controls if broader claims
are desired. Existing stale generation and guest-lookalike behavior must pass
unchanged. No core qualification or Models300 allocation success is claimed.

The failure-only scan is intentionally simple and allocation-free; large
module-graph resource limits and worst-case propagation cost remain a separate
gate. Independent review should check cycle-root bookkeeping, parent ordering,
partial attachments, reason ownership and default ordinary rejection behavior.
