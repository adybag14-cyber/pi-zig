# Native async iterator intrinsic access

The pinned QuickJS-NG v0.17.0 source exposes function and class prototypes to
native hosts, but does not expose the context's intrinsic async iterator
prototype. Native `node:events.on()` iterators need the genuine prototype so
borrowed methods, async iteration and prototype identity behave consistently
with actual guest async generators. Evaluating a JavaScript host shim to obtain
that prototype would introduce a second implementation path.

The local C change adds `JS_GetAsyncIteratorPrototype(JSContext *)`. It returns
`JS_DupValue(ctx, ctx->async_iterator_proto)`. The caller owns that reference and
must release it with `JS_FreeValue` before freeing its context/runtime. The
accessor does not create a prototype, alter its properties, mutate the context,
execute guest code, or allocate additional host state. The duplicated reference
participates in the existing QuickJS reference counting and garbage collection.

The change is additive over Root composition `07376ae85dc0627c963e01f8ca85cf0aaa594567`.
It preserves the allocator ABI adapters, WeakRef kept-object checkpoint changes,
and private async-context/late-hook pair implementation. Focused tests compare
the returned object against the actual async-generator prototype chain, retain
and release references across explicit garbage collection, distinguish two
contexts in one runtime, and repeat native allocator-failure cleanup/reuse.
