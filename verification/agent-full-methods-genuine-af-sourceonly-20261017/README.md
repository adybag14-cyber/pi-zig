# Actual Agent class AF methods and lexical arrows — SOURCE successor

Baseline482ddd9c63b49b6fce7bafbbdd29b8b73671441f preserves the independently
reviewed prompt/continue bodies and their two corrections. Original e3 and its
prepared observer remain unchanged. This successor implements the other five
actual Pi1.3 Agent async methods: runPromptMessages, runContinuation,
runWithLifecycle, handleRunFailure and processEvents. It also implements the two
lexical executor AF arrows and all three createLoopConfig async arrows. The
complete Agent installer now maps all seven async methods directly to native AF
bodies and contains no prototype-branding path for these entries. Unused legacy
config callback flows are removed from the migrated config leaf.

Authority is actual packages/agent/src/agent.ts at
8efd314fa3d3232ce197d8d7a6a5660530b9d83e, version1.3.0. No Source fixture, expected
file, compiled capture or original behavior corpus is changed. Each new function
uses the existing native_async_function primitive directly; it does not
adopt an old flow.create outer Promise. Ordinary emitter/idle-Promise callbacks
remain ordinary actual native arrows, as Source declares them.

Body boundaries:

- runPromptMessages/default options and runContinuation await actual
  runWithLifecycle. Their genuine lexical executors preserve argument evaluation,
  this capture, actual imported loop function identity, live processEvents emitter
  calls, context/config/signal/stream order and the executor's own real Await.
- runWithLifecycle constructs its actual global AbortController and global idle
  Promise, including the mutable resolvePromise binding. That idle Promise is a
  Source local, not an invented async-method outer Promise. Setup/state writes
  precede the Source try. Executor call/await failures enter the actual handler;
  handler failures propagate after the actual synchronous finally finishRun call.
  A finishRun throw overrides ordinary earlier completion. Trusted host fatal
  escapes bypass guest recovery/finally according to the existing Root policy.
- handleRunFailure builds the actual shared-usage failure message, preserving
  live model/Error/String/Date reads, then performs four distinct processEvents
  Awaits in order. A rejected step stops later events and preserves the raw reason.
- processEvents reduces state first, captures the actual signal and sync iterator,
  captures next once, then awaits each listener. Step/result/done/value failures
  precede body entry and do not close. Listener call/Await failure performs one
  synchronous IteratorClose; ordinary return getter/call failure preserves the
  original throw. A returned Promise is not awaited. Fresh trusted fatal escapes
  rather than being discarded with an ordinary close error. Existing native
  cancellation/iteration-budget checks are retained.
- createLoopConfig queue arrows use genuine async return/adoption without an
  invented Await; prepareNextTurn uses Source return-await, including Await of
  undefined after an optional nullish call and skipping the signal getter there.
  Queue skip state is a private null-prototype lexical cell. Live prepare
  condition/callee rereads and lexical receiver capture remain observable.

native_agent_af_values guards each fallible getter/call/set/constructor at its
own generation. It does not reclassify ordinary reasons against the start of an
entire method. Selected Await generations are stored after callee/argument work.
Actual pending exceptions take precedence over stale captured slots. Ordinary
caught reason ownership transfers exactly; fresh private reasons are rethrown
unchanged through the existing wrapping-generation classifier. Ordinary Source
Promise-executor/emitter callbacks additionally mark direct trusted GPA failure
before the generic callback can let a global Promise constructor swallow it.
No Engine/C/helper-wide failure policy changes are introduced.

The prepared observer has32 complete rows: all seven method descriptors; eight
lifecycle variants (sync/await catch, handler/finally precedence, setup outside
try, actual global idle Promise); two four-event failure cases; eight reducers;
seven iterator/listener/close phases; absent signal; two real executor prework
failures; three config/adoption/optional/capture cases. Owned borrowed receivers,
getters, queues and thenables are legitimate caller controls over the actual Agent
prototype, not a production Agent implementation. Executor controls intentionally
fail in genuine prework before the imported loop; they do not qualify that loop.
Date.now and global Promise mutations are owned/restored in finally. No host
credentials/environment/network or implementation substitute is used.

reference-input.mjs imports actual original Agent. The native comparison helper
runs the identical guest observer on the actual native constructor and compares
the full JSON object without row dropping/projection; it owns a dupeZ reference
buffer for QuickJS. All seven callbacks must satisfy native JS_IsAsyncFunction
and nonconstructibility, beyond superficial prototype equality. The32-row Source
capture and native execution have not occurred; expected data remains absent.

Additional native control specifications (not executable/passing targets):

- Pin pending receiver/arguments/lexical locals, iterator/listener/signal, controller,
  idle promise/resolve cell and failure message across each Await+GC. Compare
  actual Source lifetime; verify release after settlement and retained callbacks.
- Induce each GPA failure including Promise executor and emitter callbacks;
  preserve exact private reason identity, pending-first priority, u64 wrapping,
  old private tags/lookalikes and flagged rejected data with no actual pending
  fatal. Root's accepted primitive/C policy must qualify these, not a data-bit
  inference in new bodies.
- Fresh fatal during listener close must win while ordinary close errors retain
  the body reason. Global Promise execution must not swallow a trusted callback
  OOM. Handler/finally/continuation and pending-success fatal hooks need the actual
  Root primitive controls, not guessed new C behavior.
- Preserve full original Agent behavior/class/loop/events/tool/queue/GC/allocation
  gates and full SDK Source27/Original64/descriptors. Do not replace these with
  only metadata or the new32-row observer.

Remaining whole-Agent gap: native_agent_loop.loopFunction and its response/tool/
continuation pipelines still use older flow/prototype mechanisms. They remain
unchanged real collaborators, not certified genuine AF by this unit. The older
foundations installer/legacy helper component entrypoints are also unchanged.
All seven migrated complete-class methods and their arrows are Source-only until
review/compilation/runtime gates. Full Agent/SDK/CLI parity, default activation and
Node bridge removal remain Root gates. No public partial factory or backend is
published. No Main/C/H/Engine/default/golden edits, AST/compiler/Node/native/
generator jobs, capture result or runtime/CI pass occurred.
