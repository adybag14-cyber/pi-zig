This source-only unit migrates the actual startup `findInitialModel` export from
an ordinary native method with an assigned AsyncFunction prototype and a manual
`native_agent_async` Promise into `native_async_function.createResumable`.

The exact Source is Pi 1.3.0 Git c268154ca1171c2f9eefe75d3d7372a68aada2d5,
`packages/coding-agent/src/core/model-resolver.ts` (retained unchanged in
`authority/model-resolver.ts`). `findInitialModel` has **zero Await expressions**.
All seven option destructuring reads happen in order. Scoped selection retains
optional-chain key short circuiting, separate template-substitution coercions,
the third live scopedModel.model read, and nullish thinking precedence. Saved
selection retains live getModel/hasConfiguredAuth receiver/callee/argument order
and truthy thinking precedence. Snapshot selection retains synchronous
getAvailableSnapshot, array spread, dynamic Object.keys and its iterator,
dynamic availableModels.find and a nonconstructible captured predicate per
iteration, default-provider/id strict comparisons, IteratorClose on return or
body throw, and no IteratorClose after next/done/value failure. Return records
the raw object for VM adoption, with no extra Await or sync-await substitute.

`authority/sdk.ts` preserves the genuine caller: sdk.ts236 awaits this function
only when no model was supplied/restored. That Await remains in the actual SDK
factory; this leaf does not add another one. Shared mutable defaults retain
their existing cached identity. Other exports and their bodies are unchanged.

Frozen predecessor f1eeb4606582cb443aa6ad5d297869a1dde2371d is preserved as
source-review negative, with prepared-manifest hash
9E6AF952874758404598CE87E3AEE1AC320B1C972663155CC77B43F38033F549. Body found
function-wide retention of iterator methods/results and discarded auth/find
temporaries, plus an ordinary manual cancellation exit. The successor uses
expression/block/step/iteration scopes: the iterator method, then temporary
iterable retire before cached-next lookup; done retires before value lookup;
step retires before body delivery; auth/callee/predicate/iteration temporaries
retire before later live Source operations; exhausted iterators retire before
fallback selection. The actual newly produced manual interruption is marked
terminal before checked/current-event recording. Source/C retirement order was
read directly from protected vendor/quickjs/quickjs.c JS_GetIterator,
js_for_of_start, JS_IteratorNext, and JS_IteratorClose, without parser or jobs.

The new resolver-local raw Ops use the unchanged canonical
`native_sdk_owned_completion.zig` ownRoot and Completion. Actual status/pending
events are normalized before incoming roots retire, and the real outcome is
recorded before native-owned scope retirement. IteratorClose remains a Source
operation with ordinary Throw precedence; it is not substituted by cleanup.
Actual NativeInvocation fatal events remain authoritative. No flag or private
generation on a borrowed argument, PromiseResult, or historical diagnostic is
used to manufacture an event. Engine, shared Scope, native AF ABI and C are
unchanged. Existing import-namespace assembly/ordinary helper dependencies are
not newly qualified by this source edit.

Prepared controls accept the real application owner's `graph.imports` and
`factoryExports()` plus real caller inputs. The current source-closed actual
owner route is donor 4514202eff19b8ec48815a3b2775f6e6ad063bee in
worktrees/sdk-unified-native-owner-20261018. It is a separate Root intake and
qualification prerequisite. The public SDK import is not assumed to expose
that completed new factory. No fake completed namespace, Models/runtime class,
loader, session constructor, or replacement successful auth graph is created.

The common Source/native caller labels its Proxy input cases explicitly as
borrowed options with actual modelRuntime. Root must provide four real cases:
`actual-scoped-model`, `actual-saved-default`, `actual-default-snapshot`, and
`actual-empty-snapshot`. Empty availability requires a genuinely configured
runtime with no available models; a synthetic empty object is not admissible.
The negative raw getter and constructibility controls, inherited-result-then
return-adoption control, C/AF actual pending-before-body control, and historical
flagged diagnostic DATA control are separate from those real positive cases.
Native metadata checks use JS_IsAsyncFunction, so prototype decoration alone
cannot pass. `startActualFactoryCaller` invokes real createAgentSession and
returns its actual Promise to Root; Root owns the real lifecycle/retirement.

`native_sdk_initial_model_retirement_controls.zig` creates actual native C
sole-holder finalizers and a heap-owned opaque counter record. The paired
borrowed-iterator fixture consumes a callable carrier at @@iterator lookup and
a step carrier at next(), then independently checks native finalizer counts and
WeakRef death at cached-next and default-provider property frontiers. It still
uses the genuine shared default binding and real nonempty ModelRuntime data.
The fixture never supplies replacement models/auth results. Preparation and
execution MUST be separated by Root's normal idle job/kept-object boundary;
the control does not manually clear WeakRefs or claim an Await in the resolver.
Optional fatal retirement uses an actual engine.throwNativeOutOfMemoryFatal
event and records its raw identity; cancellation sets real engine.cancelled at
method retirement. Separate host assertions require exact native fatal identity
or terminal interruption, with zero guest next body/IteratorClose on cancellation.
No guest restoration is attempted after an actual fatal exit. These controls
remain authored and unexecuted, including whether the intended manual poll
frontier is reached by Root's composed VM. Their patterns were read from the
frozen genuine session-binding/Agent-loop controls, without copying their files.

All controls are parameterized and **unexecuted**. The build fragment only
installs Root's already composed actual-owner profile; it does not run it.
No native/compiler/formatter/parser/AST/Node/test/CIM/process-probe job has run.
No original expected rows, native rows, pass counts, full SDK/full application
qualification, or public/default activation is claimed. C354/H0DBC, Promise
forwarding/G2 and the current real-input owner composition remain external
qualification prerequisites. The original31064 runtime has reference-byte
authority only, at acceptance EFEC9629751FA119BE0B311D206A7F8A10A5A9E31213482FBBF647C6B6C11CF0;
its historical lifecycle negative is preserved.
