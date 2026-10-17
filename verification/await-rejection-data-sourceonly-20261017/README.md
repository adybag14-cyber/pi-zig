# Await rejection DATA correction (source only)

Base: `c720bdefde6a03b473b6c504bb90ffe2ddff7ec3`. This successor changes four
Zig product paths, adds nine actual VM test definitions and an independent build
target. It does not change C, H, Engine, the native AF adapter, an original
observer, reference result, expected file, qualification tree or Main. No jobs
or compiler/parser/AST commands have run in this lane.

`native_agent_af_values.rejected`, actual Agent prompt/continue, and actual
AgentSession abort/waitForIdle no longer classify the borrowed Await input by
private allocation generation. Old Await-generation record writes are removed;
synchronous selected-call guards still snapshot their own failed operation.
`native_async_body.enterRejectedContinuation` checks actual current pending
state first. Without a current pending exception it does not read the captured
diagnostic slot and does not inspect or mutate the input's bit, tag, identity or
properties. Its callers continue their actual Source catch/finally/throw flow.
The classifier's comment now explicitly restricts it to captured failed
operations; its algorithm is unchanged.

## Exact authority and finite contract

The inert retained Pi1.3 files are original 8efd314f snapshot bytes, alongside
their original license. `agent.ts` 373–410 has prompt/continue's direct Await;
507–530 has runWithLifecycle's ordinary catch and finally. Original
`agent-session.ts` 2464–2481 has abort/waitForIdle. Nothing in those Source bodies
classifies a rejection by hidden native history.

Pinned C3 `js_async_function_resolve_call`, quickjs.c 22212–22234, passes the
actual Promise rejection argument as `JS_PI_AF_AWAIT_REJECTED` input. In
`js_native_async_function_resume`, 22062–22078, a real current uncatchable Await
setup error bypasses the resumed Source body. Ordinary abrupt Await setup is
converted to a rejected completion after taking the pending exception. These
are distinct channels. A retained diagnostic reason, a private tag born since
suspension, and an old uncatchable bit on DATA establish no new producer event.

An actual *new* throw of the same marked object does create current pending
state, and this correction preserves that current event. It does not clear the
object's flag to make a test pass. Actual trusted direct allocator failure still
goes through the existing native AF `fail(OutOfMemory)` path; cancellation still
uses C3's actual interrupt path.

## Separate C3 frontier: not solved by this Zig patch

C3 quickjs.c 22013–22016 handles a normal `JS_PI_AF_THROW` completion by placing
its payload in pending state and entering `rejected`, whose bit check treats an
already-flagged DATA payload as a new fatal event. Thus this patch repairs entry
to Source catch/finally, but an uncaught flagged DATA rejection can still fail
at that primitive boundary. The ninth regression states the required ordinary
raw rejection and is deliberately expected to expose that current C3 defect.
There is no skipped test, removed assertion, synthetic passing result or new
golden. The target must not be called a passing gate until that separately
reviewed primitive correction and these tests actually execute.

The concrete future primitive distinction is: an owned Action.THROW payload is
an ordinary Source throw-completion, whereas `JS_EXCEPTION` plus a real current
pending error is a failed producer event. Reject the outer capability directly
with an ordinary completion's owned payload, without first promoting its data
bit via `JS_Throw`. Check real pending events before action dispatch and protect
the first actual fatal across owned result/input/state/capability cleanup.
Preserve direct OOM and cancellation escape, and do not globally clear flags.
This is a proposal, not a C change or an authorization to compose C.

## Prepared controls, not observations

`src/native_await_rejection_data_test.zig` contains nine actual test definitions:

1. Actual AF catch consumes old flagged Error and private-tagged Error DATA,
   including a retained captured diagnostic and GC, retaining identity and bit.
2. Real deferred rejection creates its private-tagged reason *after* suspension,
   at zero and unsigned-wrap generations; catch preserves its unmarked data.
3. Actual native runWithLifecycle invokes the failure handler then finishRun for
   flagged rejection DATA, retaining exact reason and `catch,finally` order.
4. Same marked object without pending is DATA; actual new JS_Throw of it is a
   current event that the pending-first entry guard preserves exactly.
5. An actual sole-owned old diagnostic native finalizer publishes a cleanup
   fatal; the entry guard promotes it over an ordinary current event while
   retaining the first current fatal when one already exists.
6. Actual prompt, continue, abort and waitForIdle preserve a fresh rejection born
   after suspension. Their collaborators are owned guest methods/Promises, not
   replacement implementations of the method under test.
7. Actual FailingAllocator failure of a resumed body allocation escapes the real
   native AF job as privately tagged host OOM; it is not injected error-union OOM.
8. Actual cancellation before a resumed job remains fatal and leaves its outer
   Promise pending.
9. An escaping flagged ordinary completion must reject the same raw value with
   no pending event and no flag clearing. Current C3 is a known negative here.

The build/test target names are `build-native-await-rejection-data` and
`test-native-await-rejection-data`. They have **not** run. The old
`native_async_rejected_allocation_test.zig` remains byte-identical, including its
previously incorrect expectation that fresh private rejection DATA must escape
as fatal. It is retained historical negative source, not authority overriding
the actual VM/Source contract. Its old target must not be described as proving
the corrected DATA rule. Original Agent32, routing15, SDK session35, HTTP20 and
OpenAI58 input/reference bytes remain unchanged.

The additive `source-observer.mjs` is a prepared genuine-original caller for
twenty ordinary DATA rows over the actual Pi8efd class methods. Native-only
flags/tags are deliberately tested through actual VM controls instead of fake
JavaScript properties. No source collector has run, no reference output exists,
and no grant for executing this new caller is implied.

`AUDIT.md` enumerates other concrete callers for separately owned corrections.
`PRODUCER-ONLY-PROPOSAL.md` addresses shared callback failures separately; no
shared callback implementation is changed in this packet.
