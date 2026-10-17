# SDK loader and initializer rejected-DATA correction — source only

This finite successor corrects actual loader_production + initializer callbacks.
It preserves originalf12/0a7607/Source48 observations/proofs; no Source expected
file is changed. Root baseline05260c391a81950fd56a0e904b16f1ad9c5f3af7 is C3
DA14/A79. No shared C/Engine/AF/helper, selector or Main edit and no Node,
generator, formatter, AST, compiler or native execution occurs.

## Actual boundaries

- Rejected Await input is DATA. The old JS_IsUncatchableError(input) test alone
  re-promoted historical flags, turning ordinary loader errors into a new fatal.
  reject() and initializeBody's rejected branch now preserve any actual pending
  VM event first, use the prior operation's saved private generation to recognize
  an exact fresh allocation reason, check pending again, and clear only a stale
  hidden bit before transferring the SAME data object. No name/message inference,
  wrapper Error, extra Promise, manual thenable or function retagging is added.
- Each actual module/extension/internal AF callback and initializer/fromFactory
  callback moves prior engine.captured_exception ownership to a private stack
  frame and clears the slot before Source operations. Prior ownership is restored
  only if no new capture remains; otherwise the prior root is freed. A same-object
  ordinary throw is a valid NEW event; pointer inequality is not the criterion.
- Actual JS_HasException entry events precede Scope/state/DATA touches. The
  qualified native AF trampoline already suppresses diagnostic formatting before
  these private callbacks. Callback catches normalize actual pending events and
  require a newly populated current slot, failing closed on missing capture.
  Actual current flag/fresh-private-cause checks remain in catch handling; only
  rejected DATA's historical flag is cleared. Fresh host OOM and genuine pending
  interrupt/fatal events bypass ordinary formatting, discard and aggregation.
- Source iterator closing, catch text, commit/discard ordering, ordinary discard
  overrides and original callback identity/argument/await structure are intact.
  Normal rejected data still performs real discard/unsubscribe; loader-level
  catch still formats its ordinary error. Three preexisting c.JS_NULL constants
  use Root's exact pi_js_null shim in separate7e8e84e8 lexical correction.

Source implementation commits96a5b8a9 (loader),7e8e84e8 (exact3nullshim),
3f76ac4b (initializer). These are source-only, not native qualification.

## Genuine causal controls — prepared/unrun, expected absent

The retained controller.input.mjs is an actual guest user module that creates
its own intrinsic Promise/gate/resolve/reject. extension.input.mjs is an actual
physical guest extension exporting a real ordinary factory that registers a
real ExtensionAPI event listener and returns that gate. The owner must import
the factory with the actual native jiti/Module pipeline and supply the actual
composed loader, real runtime and event bus. There are no fake successful
getCreateJiti, importer, API, registry, cache, constructor or runtime subjects.
Before rejection, controls drive genuine import/factory/adoption work to a
quiescent pending gate and assert that the actual factory ran exactly once.

Prepared contrasts:

1. Old flagged ordinary/native-tagged/lookalike reason, created BEFORE START,
   rejected through real initializeExtension. Exact rejection identity, no
   active event, ordinary flag and actual unsubscribe/diagnostic observations.
2. Same old DATA through loadExtensionsCached's real module import/factory /
   initializer / per-extension catch / result aggregation. It produces the
   original one-error result and actual cleanup. The controller.expectedError
   must be the Source result for the supplied reason's message; it is not a
   rewrite of historical expected observations or inferred from native output.
3. A message getter throws the SAME object as a preexisting diagnostic root.
   Only the fresh captured event is used, outer rejection preserves raw identity,
   prior root ownership is restored and no diagnostic ToString getter runs.
4. Real runtime subscription wrapper delegates actual unsubscribe, then invokes
   the exact native fresh-OOM fault probe during discard. The original fresh
   private reason is fatal, outer promise stays pending and formatting is bypassed.
5. An actual pending non-OOM host event before native Await resumption wins over
   flagged rejected data, preserving actual reason and leaving data untouched.
6. The installed real Engine interrupt handler creates a deferred non-OOM fatal
   from cancelled execution before resumption; private-OOM generation stays
   unchanged and the actual current event wins. Hook controls require their own
   fresh exclusive Engine; no application owner's hook is replaced.

The actual bootstrap inputs are still incomplete. No positive control is
claimed executed or runnable with stand-ins. Native whole-loader/factory,
allocation/teardown and full trace qualification remains a later owned gate.
This correction does not establish a general audit of every unrelated SDK
success-value+pending-event or retained discarded-return boundary.
