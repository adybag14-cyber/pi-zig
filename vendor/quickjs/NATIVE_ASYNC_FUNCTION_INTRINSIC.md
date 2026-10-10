# Native AsyncFunction intrinsic access

The pinned QuickJS-NG v0.17.0 source exposes the ordinary Function prototype
and the local async iterator intrinsic accessor. Native asynchronous functions
such as `node:events.once()` also need the context's genuine AsyncFunction
prototype, including inherited constructor and `Symbol.toStringTag` identity.

The additive C/header API `JS_GetAsyncFunctionPrototype(JSContext *)` returns
`JS_DupValue(ctx, ctx->class_proto[JS_CLASS_ASYNC_FUNCTION])`. The host owns the
returned reference and must release it before its context/runtime. The accessor
does not execute guest code, allocate another prototype, mutate the intrinsic,
change any function's execution semantics, or retain additional host state.

This patch builds on the qualified async iterator accessor
`8861e452d91c105bd02e49c47901efde0ab5aca4` and retains the existing allocator,
WeakRef checkpoint and private async-context patches. Focused native tests
compare actual guest async-function prototype identity, retain references
across GC, distinguish two contexts, and exercise allocator cleanup/reuse.
