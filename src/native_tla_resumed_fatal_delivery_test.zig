//! Prepared source-only resumed TLA and late-callback controls. No runtime
//! success follows from these assertions until the exact candidate is run.
const std = @import("std");
const em = @import("extensions/engine.zig");
const af = @import("extensions/native_async_function.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn fatalStart(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return error.OutOfMemory;
}
test "native TLA resumed fatal cached module and reimport terminate with exact reason" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "fatalStart", try scope.own(try af.create(engine, "fatalStart", 0, fatalStart, &.{})));
    const source = "await Promise.resolve(); await fatalStart();";
    try engine.registerModule("resumed-fatal", source);
    const module = try engine.eval(source, "resumed-fatal", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer engine.freeValue(module);
    const parent = try engine.eval("import 'resumed-fatal'; export const unreachable=true;", "resumed-fatal-parent.mjs", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer engine.freeValue(parent);
    const boundary = engine.native_allocation_generation;
    const first = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, parent));
    defer engine.freeValue(first);
    try std.testing.expect(!c.JS_IsException(first));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, first));
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(first));
    const reason = try scope.own(c.JS_DupValue(engine.context, engine.captured_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.OutOfMemory);
    const retry_boundary = engine.native_allocation_generation;
    const cached = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
    defer engine.freeValue(cached);
    const cached_failed = c.JS_IsException(cached);
    const cached_reason = if (cached_failed) c.JS_GetException(engine.context) else c.pi_js_undefined();
    defer engine.freeValue(cached_reason);
    const parent_cached = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, parent));
    defer engine.freeValue(parent_cached);
    const parent_failed = c.JS_IsException(parent_cached);
    const parent_reason = if (parent_failed) c.JS_GetException(engine.context) else c.pi_js_undefined();
    defer engine.freeValue(parent_reason);
    const importer = try engine.eval("import 'resumed-fatal'; export const unreachable=true;", "resumed-fatal-reimport.mjs", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer engine.freeValue(importer);
    const imported = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, importer));
    defer engine.freeValue(imported);
    const import_failed = c.JS_IsException(imported);
    const imported_reason = if (import_failed) c.JS_GetException(engine.context) else c.pi_js_undefined();
    defer engine.freeValue(imported_reason);
    if (!cached_failed or !import_failed) std.debug.print("Resumed TLA fatal: cached_exception={} cached_promise_state={d} reimport_exception={} reimport_promise_state={d} jobs_pending={}\n", .{
        cached_failed,
        c.JS_PromiseState(engine.context, cached),
        import_failed,
        c.JS_PromiseState(engine.context, imported),
        c.JS_IsJobPending(engine.runtime),
    });
    // Evaluate both entries before asserting, to expose both pending paths
    // without adding extra ticks or awaiting an already known pending result.
    try std.testing.expect(cached_failed);
    try std.testing.expect(import_failed);
    try std.testing.expect(parent_failed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, cached_reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, imported_reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, parent_reason));
    try std.testing.expect(!c.JS_IsUncatchableError(cached_reason));
    try std.testing.expectEqual(retry_boundary, engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(engine.context));
}

fn drain(engine: *em.Engine) !void {
    var jobs: usize = 0;
    while (c.JS_IsJobPending(engine.runtime)) {
        if (jobs == 32) return error.LateCallbackJobBudget;
        var context: ?*c.JSContext = null;
        const status = c.JS_ExecutePendingJob(engine.runtime, &context);
        if (status < 0) {
            const failure = c.JS_GetException(context orelse engine.context);
            _ = try engine.checked(c.JS_Throw(engine.context, failure));
        }
        try std.testing.expect(status > 0);
        jobs += 1;
    }
}

test "native TLA resumed fatal outer attachment failure prevents ordinary and fatal late body callbacks" {
    for ([_]bool{ false, true }) |fatal| {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        try scope.put(global, "fatalStart", try scope.own(try af.create(engine, "fatalStart", 0, fatalStart, &.{})));
        const source = try std.fmt.allocPrint(std.testing.allocator,
            "globalThis.lateSideEffects=0; globalThis.attachmentReason={{raw:true}};" ++
                "const original=Object.getOwnPropertyDescriptor(Promise.prototype,'constructor');" ++
                "globalThis.restoreCtor=()=>Object.defineProperty(Promise.prototype,'constructor',original);" ++
                "const gate={{then(resolve){{globalThis.releaseLate=resolve}}}};" ++
                "Object.defineProperty(Promise.prototype,'constructor',{{configurable:true,get(){{{s}}}}});" ++
                "await gate; lateSideEffects++;", .{if (fatal) "fatalStart();" else "throw attachmentReason;"});
        defer std.testing.allocator.free(source);
        const module = try engine.eval(source, "tla-suspended-outer-attachment.mjs", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
        defer engine.freeValue(module);
        const boundary = engine.native_allocation_generation;
        const evaluated = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
        defer engine.freeValue(evaluated);
        if (fatal) {
            try std.testing.expect(c.JS_IsException(evaluated));
            try std.testing.expectError(error.JavaScriptException, engine.checked(evaluated));
            try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.OutOfMemory);
        } else {
            try std.testing.expect(!c.JS_IsException(evaluated));
            try std.testing.expectError(error.JavaScriptException, engine.awaitValue(evaluated));
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, try scope.get(global, "attachmentReason")));
        }
        const expected = try scope.own(c.JS_DupValue(engine.context, engine.captured_exception.?));
        const after_failure = engine.native_allocation_generation;
        const restored = try engine.eval("restoreCtor();", "restore-tla-constructor.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(restored);
        try drain(engine); // Actual thenable job publishes its resolver.
        c.JS_RunGC(engine.runtime);
        const release = try scope.get(global, "releaseLate");
        try std.testing.expect(c.JS_IsFunction(engine.context, release));
        const released = try engine.checked(c.JS_Call(engine.context, release, c.pi_js_undefined(), 0, null));
        engine.freeValue(released);
        try drain(engine); // Actual continuation must retire without body code.
        const count = try scope.get(global, "lateSideEffects");
        var count_int: i32 = undefined;
        if (c.JS_ToInt32(engine.context, &count_int, count) < 0) return error.JavaScriptException;
        try std.testing.expectEqual(@as(i32, 0), count_int);
        const cached = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
        defer engine.freeValue(cached);
        if (fatal) {
            try std.testing.expect(c.JS_IsException(cached));
            const reason = c.JS_GetException(engine.context);
            defer engine.freeValue(reason);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, reason));
        } else {
            try std.testing.expect(!c.JS_IsException(cached));
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, evaluated, cached));
            const reason = c.JS_PromiseResult(engine.context, cached);
            defer engine.freeValue(reason);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, reason));
        }
        try std.testing.expectEqual(after_failure, engine.native_allocation_generation);
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}

fn pendingHandledTracker(context: ?*c.JSContext, _: c.JSValue, _: c.JSValue, handled: bool, _: ?*anyopaque) callconv(.c) void {
    if (!handled) return;
    const global = c.JS_GetGlobalObject(context);
    defer c.JS_FreeValue(context, global);
    const armed = c.JS_GetPropertyStr(context, global, "armPending");
    defer c.JS_FreeValue(context, armed);
    if (c.JS_ToBool(context, armed) != 1) return;
    // Existing data-property update and owned value dup do not allocate. The
    // public host tracker deliberately leaves a raw pending reason inside
    // perform_promise_then after continuation creation, before successful job
    // enqueue. Its queued callback therefore outlives terminated frame roots.
    if (c.JS_SetPropertyStr(context, global, "armPending", c.pi_js_bool(context, 0)) < 0) return;
    _ = c.JS_Throw(context, c.JS_GetPropertyStr(context, global, "partialReason"));
}
test "native TLA resumed fatal partial initial await setup retires queued inactive callback" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const reason = try scope.object();
    try scope.put(global, "partialReason", reason);
    try scope.put(global, "awaitedReason", try scope.object());
    try scope.put(global, "armPending", c.pi_js_bool(engine.context, 0));
    try scope.put(global, "afterPartial", c.JS_NewInt32(engine.context, 0));
    const module = try engine.eval("armPending=true; await Promise.reject(awaitedReason); afterPartial++;", "tla-partial-initial-await.mjs", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer engine.freeValue(module);
    c.JS_SetHostPromiseRejectionTracker(engine.runtime, pendingHandledTracker, null);
    defer c.JS_SetHostPromiseRejectionTracker(engine.runtime, null, null);
    const boundary = engine.native_allocation_generation;
    const evaluated = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
    defer engine.freeValue(evaluated);
    try std.testing.expect(!c.JS_IsException(evaluated));
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(evaluated));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
    var count: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &count, try scope.get(global, "afterPartial")) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 0), count);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expectEqual(boundary, engine.native_allocation_generation);
    c.JS_RunGC(engine.runtime);
}

test "native TLA resumed fatal exact module association distinguishes duplicate physical names" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "fatalStart", try scope.own(try af.create(engine, "fatalStart", 0, fatalStart, &.{})));
    const setup = try engine.eval("globalThis.secondDone=false; globalThis.secondGate=new Promise(r=>globalThis.releaseSecond=r);", "tla-identity-setup.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(setup);
    const failed_module = try engine.eval("await Promise.resolve(); await fatalStart();", "duplicate-physical.mjs", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer engine.freeValue(failed_module);
    const healthy_module = try engine.eval("await secondGate; secondDone=true;", "duplicate-physical.mjs", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer engine.freeValue(healthy_module);
    const boundary = engine.native_allocation_generation;
    const failed = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, failed_module));
    defer engine.freeValue(failed);
    const healthy = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, healthy_module));
    defer engine.freeValue(healthy);
    try std.testing.expect(!c.JS_IsException(failed));
    try std.testing.expect(!c.JS_IsException(healthy));
    c.JS_RunGC(engine.runtime);
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(failed));
    try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.OutOfMemory);
    const expected = try scope.own(c.JS_DupValue(engine.context, engine.captured_exception.?));
    const healthy_cached = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, healthy_module));
    defer engine.freeValue(healthy_cached);
    try std.testing.expect(!c.JS_IsException(healthy_cached));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, healthy, healthy_cached));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, healthy_cached));
    const released = try engine.eval("releaseSecond();", "release-second-module.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
    const settled = try engine.awaitValue(healthy);
    engine.freeValue(settled);
    try std.testing.expect(c.JS_ToBool(engine.context, try scope.get(global, "secondDone")) == 1);
    const retry = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, failed_module));
    defer engine.freeValue(retry);
    try std.testing.expect(c.JS_IsException(retry));
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, reason));
}

test "native TLA resumed fatal ordinary nonmodule async callbacks retain rejection and return behavior" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const result = try engine.evalModule(
        "const raw={};const f=async()=>{await 0;throw raw};let caught=false;try{await f()}catch(e){if(e!==raw)throw e;caught=true}" ++
            "const g=async(x)=>{await Promise.resolve();return x};if(!caught||await g(raw)!==raw)throw Error('ordinary async path changed');export const done=true;",
        "tla-ordinary-nonmodule.mjs",
    );
    engine.freeValue(result);
    try std.testing.expectEqual(@as(u64, 0), engine.native_allocation_generation);
}

fn fatalCompletionHook(context: ?*c.JSContext, kind: c.JSPromiseHookType, _: c.JSValue, _: c.JSValue, hook_data: ?*anyopaque) callconv(.c) void {
    if (kind != c.JS_PROMISE_HOOK_RESOLVE) return;
    const engine: *em.Engine = @ptrCast(@alignCast(hook_data.?));
    const global = c.JS_GetGlobalObject(context);
    defer c.JS_FreeValue(context, global);
    const armed = c.JS_GetPropertyStr(context, global, "armCompletion");
    defer c.JS_FreeValue(context, armed);
    if (c.JS_ToBool(context, armed) != 1) return;
    if (c.JS_SetPropertyStr(context, global, "armCompletion", c.pi_js_bool(context, 0)) < 0) return;
    // A genuine public host hook reports a native fatal allocation reason.
    // The intrinsic resolving callback still returns undefined after this.
    _ = engine.throwNativeOutOfMemory();
    c.JS_SetUncatchableError(context, engine.native_allocation_exception.?);
}
test "native TLA resumed fatal resolving callback pending host hook reason is terminal and exact" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const module = try engine.eval("await Promise.resolve(); globalThis.armCompletion=true;", "tla-resumed-resolving-hook.mjs", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer engine.freeValue(module);
    const boundary = engine.native_allocation_generation;
    const pending = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
    defer engine.freeValue(pending);
    try std.testing.expect(!c.JS_IsException(pending));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    c.JS_SetPromiseHook(engine.runtime, fatalCompletionHook, engine);
    defer c.JS_SetPromiseHook(engine.runtime, null, null);
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(pending));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, engine.native_allocation_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception.?));
    try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.OutOfMemory);
    const after_failure = engine.native_allocation_generation;
    const cached = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
    defer engine.freeValue(cached);
    try std.testing.expect(c.JS_IsException(cached));
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    // Completion may already have queued the module fulfillment handler.
    // It must observe the recorded terminal failure and no-op after delivery.
    try drain(engine);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expectEqual(after_failure, engine.native_allocation_generation);
    const healthy = try engine.evalModule("await 0; export const healthy=true;", "tla-after-resolving-hook.mjs");
    engine.freeValue(healthy);
}
