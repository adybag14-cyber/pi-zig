# Private native async-generator review candidate

This isolated candidate starts at reviewed foundation `3f0cce9ad90ee9618d4216d9889f088f6a28f6de`. It adds a native resume callback to the existing QuickJS AsyncGenerator implementation. It does not yet change `native_stream.zig`, OpenAI production scheduling, the private JSON hook, the configured 1 MiB stack guard, or another worktree. Source-only review is complete; compilation and runtime qualification are separate evidence.

## Private C API and ownership

`JS_PiNewNativeAsyncGenerator(ctx, owner, resume, prototype)` returns an owned real `JS_CLASS_ASYNC_GENERATOR` instance, or `JS_EXCEPTION`. The owner and prototype arguments are borrowed. Undefined prototype selects the creation context's intrinsic AsyncGenerator prototype; callers may supply the provider method's own prototype object. The callback pointer is compiled native code and must outlive the instance. The API is private to this runtime; callers supply an object/null/undefined prototype.

`JS_PiGetAsyncGeneratorPrototype(ctx)` and `JS_PiGetAsyncGeneratorFunctionPrototype(ctx)` each return an owned reference to that context's intrinsic prototype. They do not compile guest source or depend on mutable globals.

The resume callback receives the retained creation context, borrowed owner, borrowed input, and a completion discriminator. It returns an owned JSValue and writes an action, or returns `JS_EXCEPTION` with the original pending exception. It must not retain borrowed inputs without duplicating them. All guest state crossing a suspension belongs in the GC-visible owner graph. Native state machines, rather than guest JavaScript fragments, implement body control flow.

Completion discriminators are START, NEXT, RETURN_INPUT, THROW_INPUT, AWAIT_FULFILLED, and AWAIT_REJECTED. Actions are:

- AWAIT: suspend through QuickJS's existing PromiseResolve and promise reaction path, then resume with fulfillment or raw rejection.
- YIELD: perform mandatory Await of the yielded value before resolving the current request and suspending at yield. Rejection enters the body as THROW_INPUT.
- RETURN: perform mandatory Await of the return expression. Rejection enters the body as THROW_INPUT; fulfillment completes the body.
- COMPLETE: finish a bare/implicit return, or finish an expression the body already awaited explicitly. A native implementation with a `finally` clause must explicitly AWAIT its return expression before running that clause; it must not run finally before choosing RETURN.
- THROW: complete abruptly with the raw value, without error-message coercion.

The minimal Zig wrapper translates these actions, preserves raw guest exceptions, and retains existing tagged native allocation failures. It has no promise scheduler of its own.

## Data lifecycle and modified branches

`JSAsyncGeneratorData` gains the callback, retained context, retained owner, and native suspension phase. `native_resume == NULL` selects the existing bytecode implementation, including its existing frame lifetime and allocation behavior. Existing bytecode state allocation is zero initialized.

The complete lifecycle touchpoints are:

1. `JS_PiNewNativeAsyncGenerator`: allocates zeroed data, initializes the request queue and suspended-start state, duplicates context/owner, creates the actual branded object, attaches data, and cleans up if object creation fails.
2. `js_async_generator_mark`: marks native owner and creation context instead of the absent bytecode frame. Existing request result, promise, and resolving functions remain marked.
3. `js_native_async_generator_retire`: clears context/owner/phase before releasing them. It is safe when called again by finalization after completion.
4. `js_async_generator_free` and the existing finalizer: free all pending request roots, retire a native body without touching `func_state`, and free the data. Bytecode frame cleanup keeps its original branch.
5. `js_async_generator_complete`: retires a native body instead of freeing a bytecode frame.
6. `js_native_async_generator_drive`: retains a local creation-context reference across retirement, observes existing interrupt/stack checks, invokes the callback, consumes each owned output, and delivers abrupt completion or a real Await phase. A synchronous poisoned Promise constructor exception resumes the body at the corresponding await/yield boundary.
7. `js_async_generator_resume_next`: native start/next/return/throw dispatch bypasses the absent frame. Suspended-start return/throw never enters the body. Suspended-yield return awaits its input before native body handling. Completed native requests drain in FIFO order.
8. `js_async_generator_resolve_function`: native await/yield/return reactions resume the proper phase in the creation realm. Repeated Await leaves execution suspended without reentering the bytecode-frame path. Completed-return reactions drain requests queued behind that return.
9. `js_native_async_generator_resolve`: checked iterator-result allocation rejects the current native request with the raw allocation exception and retires the body. The inherited unchecked bytecode helper remains unchanged.
10. Completed native return handles failure from `js_async_generator_completed_return`: captures the raw exception, restores completed state, rejects/removes the head, and continues draining. This is the independently reviewed correction for otherwise stranded requests on PromiseResolve/handler allocation failure.

Active body iterator results use the creation realm; promises and later completed-state results use the borrowed intrinsic method's realm. No owner/context reference is released while a native callback still needs it.

## Qualification plan and exact test scope

`build-native-async-generator` / `test-native-async-generator` compile and run eight new functional tests plus selected unchanged JSON and stream regressions. The new tests cover actual intrinsic brand/prototype/borrowed next, raw identity, explicit Await, queued next/return/throw, return-input thenables, draining behind a completed return, suspended-start abrupt completion, throwing then getters, poisoned Promise constructors, invalid receiver, pending owner GC, cross-realm promise/result ownership, targeted raw VM allocation failure, owner retirement, and unreachable owner-cycle finalization exactly once.

The completed-return handler-allocation test uses an actual Promise constructor getter to queue a trailing next request before arming the one-byte VM limit. Both request capabilities therefore exist, and PromiseResolve reuses the original input Promise before handler creation fails. It verifies the current and trailing requests reject, the VM exception is consumed, and later next succeeds after restoring the memory limit. This directly exercises the native completed-return negative-result correction identified during review.

The VM allocation test uses a valid compiled callback while memory limit is one byte for constructor data allocation, and sets that limit immediately before native COMPLETE to exercise checked iterator-result failure. One byte is below the initialized VM's usage; this pinned QuickJS interprets zero as unlimited. It restores the configured memory limit and verifies terminal next remains usable. It is targeted coverage, not an exhaustive C allocator sweep. The original zero-limit test negative is preserved separately: its unexpectedly successful constructor result was not released on the failed assertion, producing an external AsyncGenerator leak; the successor releases that owned return on every outcome.

`build-native-async-generator-gpa` / `test-native-async-generator-gpa` run the complete host allocator failure sweep separately. The body performs an actual host allocation so callback OOM traverses the C request queue with the original tagged failure. This target is measured separately under the same runtime deadline.

The selected old regressions cover genuine OpenAI HTTP20 request bodies and terminal decoder shapes, 33 JSON/partial observations, existing JSON hook/delegate/error roots, ordinary unhooked parsing, EventStream exports/queue/result/receiver cleanup, overflow, provider validation, and cancellation. The known full OpenAI intermediate-snapshot negative remains preserved and is not claimed fixed by this hook alone. Existing host allocator and all ordinary bytecode generator tests are not silently included in this selected run.

Fresh Node/Source async-generator observations, actual EventStream integration, nested SDK iterator layers, callback/drain/chunk timing, and the full OpenAI snapshot retry are still required. Inline ECMAScript checks in this candidate are native tests; they are not presented as a new captured Source differential.

## Reviewed limitations

Independent CI read-only review and Root reviewed C SHA256 `ED1F3A59AD13DE57B32CCA164FC42D347C463632F0B8A1921DC79621E79DE69E`. The only subsequent header change explicitly states getter ownership; the implementation is unchanged. Both reviewers accepted the completed-return negative-result correction for experimental qualification, with no remaining control-flow blocker identified.

The inherited general `js_promise_resolve_function_call` ignores `JS_EnqueueJob` failure. Targeted native allocation handling therefore does not establish exhaustive malloc/OOM behavior of all existing Promise machinery. The candidate remains private and unintegrated until its frozen native gates and subsequent actual Source parity gates pass.
