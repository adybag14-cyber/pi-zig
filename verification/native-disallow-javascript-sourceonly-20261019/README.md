# Actual VM JavaScript execution scope

This unit adds the linked-C execution guard needed by Node's `DisallowJavascriptExecutionScope(THROW_ON_FAILURE)` during native handle cleanup. The production delta, all 22 authored controls and the build registration have independent source-review closure. No native compilation, test metadata discovery, Node execution, or runtime acceptance is claimed by this source unit.

## Original authority

The authority is the unchanged Node v24.13 V8 source at commit `def0bdf8abee441cfcbf793a8dc24a6f3b899573`. Complete source files and their original HTTP records are retained under `authority/`; `authority/source-acquisition.json` records full-body hashes. The V8 license is retained unchanged. The full original `api.cc` and `objects.cc` used by this proof are already retained in the preceding existing-Promise settlement unit, with exact paths and hashes in the acquisition record. Node's genuine CleanupHandles source excerpt is also retained in that record.

`source-design.json` preserves the actual V8 scope, Invoke, accessor/proxy and microtask code together with the original QuickJS entry bodies. It is a pre-implementation design record: its approval prerequisite was subsequently satisfied by Root's explicit source-only grant. `production-delta.json` records all 17 exact C replacements and the header addition, with complete old/new hashes. Reversing those replacements recreates the parent source byte for byte.

## Implemented boundary

A runtime Boolean starts enabled. `JS_PiExchangeJavascriptExecutionAllowed` stores a new value and returns the previous value without allocation or pending-state changes. The caller must restore that exact saved value on every scope exit. The ordinary `illegal access` string is allocated once during runtime construction and is reused by blocked entry; its allocation failure follows the existing runtime-construction unwind.

The linked raw call and constructor paths check the scope before actual body entry, constructor prototype work or a callable proxy's trap selection. Generator continuations and genuine native AsyncFunction initial/step entry are covered. Source compilation and native data-property operations remain available. An attempted JavaScript getter, setter or proxy trap reaches the same actual call guard. Existing pending reasons take precedence over a new scope failure, and the scope failure is an ordinary string throw rather than a native allocation or cancellation event.

The direct host API exemption is explicit. `JS_PiMarkNativeApiFunction` accepts only an actual direct native callable representation and marks that one object. It rejects bytecode, native AsyncFunction, bound and proxy representations before any guest property access. A caller using this operation asserts the original V8 **JSFunction/FunctionTemplate API-function provenance**; a custom QuickJS callable class can represent such a function. Generic ObjectTemplate callable-instance delegates do not use V8's direct InvokeApiFunction fast path and are outside this admission. C implementation alone, prototype inheritance, wrapping, or a native namespace never establishes this provenance. Source NodeFunction algorithms must remain unmarked.

An empty job queue returns the existing zero result. A disabled nonempty queue returns zero with a null context before dequeue, hooks, callback, or root retirement; with an existing pending reason it returns minus one and the first queued context without consuming the job. This matches the selected V8 release behavior: the ordinary disallow exception in TryRunMicrotasks is swallowed by its local nonverbose TryCatch, so no task is processed and the queue remains. The original debug assertion on an unexpectedly retained queue is not presented as release behavior. A caller must interpret zero as no progress and must not spin merely because the queue is still nonempty.

## Controls and ownership

`src/native_vm_disallow_javascript_test.zig` declares 22 actual linked-VM controls. The full names and exact hashes are in `status.json`. They use genuine raw contexts, calls, constructors, native callables, Promise reactions, native jobs, generator objects and native AsyncFunctions. They distinguish selected native accessors from JavaScript accessors, and use permitted native prototype/trap getters to prove that an outer blocked call stops before those lookups.

The controls also preserve supplied argument/receiver identity, ordinary versus actual flagged pending reasons, scope restoration, and real queued root liveness through GC. Post-fatal assertions inspect pre-retained own-data records directly; they do not run an additional guest program. Native probe storage outlives runtime teardown. Allocation-fast-path checks use a positive memory limit of one, because zero means unlimited in the linked allocator.

The independent production reviews are split between SDK (runtime/provenance/dispatch/constructor/native-AF) and Modules (exchange/job/ABI). The controls are split SDK 1–13 and Modules Fixture/14–22. Both slices are closed on the exact E38B689F test root; Modules also closed the 4A5F4C12 six-line build patch. The production pins remain C40F8A35C and H28C8E558. Neither a static review nor an authored declaration is counted as an executed test.

## Build and remaining integration

`build-intake.patch` adds exactly six install-only lines for `build-native-vm-disallow-javascript`, using the existing shared QuickJS library and the `VM DisallowJS` filter. It adds no run step or second native library. Root owns the later exact-source build and exact-artifact runtime grants.

The actual Node Environment/CleanupHandles composition is a separate caller unit. A distinct continuation-preserved embedder-data slot is the next VM dependency. This unit does not change `JS_SetExecutionContext`, its captured job/reaction capability roots, its hook, or the application `native_async_scope` owner.
