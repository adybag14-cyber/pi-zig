# Native Await inactive callback: source-only successor over C409

Root approved the minimal native callback guard after the exact C409 trace.
Only two C lines are added in js_async_function_resolve_call's native_body
branch: an inactive state returns JS_UNDEFINED before native_resume/native_step.
No module owner, new field, tag, context reference, Promise helper or ABI is
added. Active native and ordinary bytecode paths retain their existing code.

A genuine handled-rejection tracker can leave an uncatchable reason inside
perform_promise_then after resolver creation. That helper still successfully
queues the chosen native continuation and returns zero. The native Await path
detects pending fatal state, terminates and returns failure. Its queued resolver
still retains JSAsyncFunctionData, so the state survives the failed caller.

Termination frees/clears native_function, native_state, native_this and argv,
and sets is_active=false. It does NOT retire native_ctx: the state owns that
duplicated context until free0, and the GC mark path marks native_ctx even
while inactive. Therefore the dangerous later read is the cleared
native_function slot, not a prematurely freed native_ctx. Without the guard,
the later resolver enters native_step, whose first bytecode lookup dereferences
JS_VALUE_GET_OBJ(native_function) before any stack/interrupt guard. The proposed
no-op avoids that invalid read and re-delivery of an already handled error.

The prepared standalone control creates a real rejected input before tracker
installation, filters that exact input on handled=true, reports one fresh native
fatal, and verifies raw START failure/exact host classification with a callback
still queued. It clears host delivery, runs actual GC, drains the actual queue,
and requires no body resume, no new generation and no pending exception. It
then invokes the same genuine native function with a healthy input and requires
one normal resume. All raw results/reasons are owned before assertions.

No syntax/compiler/runtime/Node jobs ran. The old C409 and F06 packets keep
their exact identity and do not qualify this successor. The standalone control
and snippet require future actual metadata capture and an explicit grant.
