# Canonical Agent guest-operation provenance correction

This is source-only authoring from Main311a, not metadata or runtime qualification. Nine new named declarations are prepared. Existing 12 return-adapter, four parallel, ten loop, and prompt control bytes remain unchanged. Native/Node/compiler/parser jobs have not run.

`guard(engine, generation, result)` retains its interface. It is nonconsuming and checks actual pending/current NativeInvocation only; the generation argument is ignored. It cannot establish a boundary before an expression already evaluated by its caller. Callers keep ownership of any raw result when the guard rejects. It accepts Scope-borrowed results without passing them to consuming Engine APIs.

`GuestOperation` is initialized inactive at a stable caller-local address. `begin(engine)` enters the frame before effects and rejects existing pending/current producer events. Every successful begin requires exactly one finish on the same engine, before escape/Await. `finish(engine, result)` takes a borrowed Scope result or error, leaves using owned undefined, and preserves ordinary captured DATA on normal leave. Typed OutOfMemory publishes its actual fatal producer before cleanup. No throwCaptured/SDK fail transport republishes ordinary captured DATA into leave.

get/global/call/construct/set/getKey/instanceOf/binary use this frame before the real C operation. Owned results go through Engine.checked then unchanged C435 ownRoot while active. Scope outputs remain borrowed. Key coercion checks actual pending/B1 before its subsequent property read. No guest-span allocation generation or captured-only error flag is fatal authority.

caught/failure surface actual pending/current producer first, then transfer captured-only DATA without inspecting flags/tags. The private idle-Promise executor delegates constructor retention to its real enclosing stable frame rather than diagnosing a captured generation. Prompt/continue reuse the same selected guest helpers and catch transport; their original Source Await placement and direct adoption remain unchanged.

The eight original Agent bodies/fixtures and all existing test assertions stay at their real scope. Shared 8cf per-free completion policy, C435, Scope, Engine, NativeNode, C and ABI remain byte protected. The current checkout's old VM is not the intended VM dependency. The separately source-closed c252 union BCDF/0DBC/G2 and fresh composed qualification are required; no qualification transfers from its source receipt.

Prepared controls create unmarked private DATA using the actual raw native error producer, then throw it within the SAME getter/call/constructor/coercion/setter. They contrast actual producer B1, actual entry abortion, captured-only marked DATA, the production emitter, and real FailingAllocator root append failure before ordinary/fatal sole-output finalizers. These are authored controls, not captures, fixtures, expected Source rewrites, or executed results.
