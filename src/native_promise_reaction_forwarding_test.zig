//! Source-only genuine VM controls for absent Promise rejection handlers.
//! These definitions have not been compiled or executed by their author.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;

fn script(engine: *em.Engine, source: []const u8) !void {
    engine.freeValue(try engine.eval(source, "promise-reaction-forwarding.js", c.JS_EVAL_TYPE_GLOBAL));
}
fn field(engine: *em.Engine, key: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, key));
}
fn publish(engine: *em.Engine, key: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, key, c.JS_DupValue(engine.context, value)) < 0)
        return error.JavaScriptException;
}
fn oneJob(engine: *em.Engine) !void {
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(engine.runtime, &context) > 0);
    try std.testing.expect(!c.JS_HasException(engine.context));
}
fn drain(engine: *em.Engine) !void {
    var count: usize = 0;
    while (c.JS_IsJobPending(engine.runtime) and count < 16) : (count += 1) try oneJob(engine);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn privateReason(engine: *em.Engine) c.JSValue {
    // A real private native tag, retained later as rejection DATA. This fixture
    // does not claim to have exhausted an allocator.
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(engine.context);
}
fn expectData(engine: *em.Engine, actual: c.JSValue, reason: c.JSValue, flagged: bool, tag: u64) !void {
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, reason));
    try std.testing.expectEqual(flagged, c.JS_IsUncatchableError(actual));
    try std.testing.expectEqual(tag, c.pi_js_native_allocation_error_generation(actual));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
const shapes = [_][]const u8{
    "globalThis.forwarded=input.then();globalThis.output=forwarded.catch(reason=>{globalThis.caught=reason;return 37});",
    "globalThis.forwarded=input.then(undefined);globalThis.output=forwarded.catch(reason=>{globalThis.caught=reason;return 37});",
    // Matches the genuine exec.ts waitForChildProcess(...).then(success).catch(failure) shape.
    "globalThis.forwarded=input.then(()=>{throw Error('rejected input reached fulfillment handler')});globalThis.output=forwarded.catch(reason=>{globalThis.caught=reason;return 37});",
};
fn verifyForwarded(engine: *em.Engine, reason: c.JSValue, flagged: bool, tag: u64) !void {
    // Inspect the actual intermediate rejected Promise before its attached
    // catch runs; this also rules out a synthetic fulfilled success shortcut.
    try oneJob(engine);
    const forwarded = try field(engine, "forwarded");
    defer engine.freeValue(forwarded);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, forwarded));
    const rejected = c.JS_PromiseResult(engine.context, forwarded);
    defer engine.freeValue(rejected);
    try expectData(engine, rejected, reason, flagged, tag);
    c.JS_RunGC(engine.runtime);
    try drain(engine);
    const caught = try field(engine, "caught");
    defer engine.freeValue(caught);
    try expectData(engine, caught, reason, flagged, tag);
    const output = try field(engine, "output");
    defer engine.freeValue(output);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, output));
    const result = c.JS_PromiseResult(engine.context, output);
    defer engine.freeValue(result);
    var number: i32 = 0;
    try std.testing.expect(c.JS_ToInt32(engine.context, &number, result) == 0);
    try std.testing.expectEqual(@as(i32, 37), number);
    try expectData(engine, reason, reason, flagged, tag);
}

test "native Promise forwarding settled Error DATA preserves identity flags and private tags" {
    for (shapes) |source| {
        for ([_]bool{ false, true }) |private| {
            for ([_]bool{ false, true }) |flagged| {
                const engine = try em.Engine.init(std.testing.allocator, .{});
                defer engine.deinit();
                const reason = if (private) privateReason(engine) else try engine.checked(c.JS_NewError(engine.context));
                defer engine.freeValue(reason);
                if (flagged) c.JS_SetUncatchableError(engine.context, reason);
                const tag = c.pi_js_native_allocation_error_generation(reason);
                try std.testing.expectEqual(private, tag != 0);
                const input = try engine.checked(c.JS_NewSettledPromise(engine.context, true, reason));
                defer engine.freeValue(input);
                try publish(engine, "input", input);
                // An old captured diagnostic and old native tag do not create
                // a new failed handler operation or a pending VM exception.
                engine.captured_exception = c.JS_DupValue(engine.context, reason);
                try script(engine, source);
                try verifyForwarded(engine, reason, flagged, tag);
            }
        }
    }
}

test "native Promise forwarding fresh private DATA after reaction registration preserves unsigned wrap" {
    for (shapes) |source| {
        for ([_]u64{ 0, std.math.maxInt(u64) }) |generation| {
            for ([_]bool{ false, true }) |flagged| {
                const engine = try em.Engine.init(std.testing.allocator, .{});
                defer engine.deinit();
                engine.native_allocation_generation = generation;
                var resolving: [2]c.JSValue = undefined;
                const input = try engine.checked(c.JS_NewPromiseCapability(engine.context, &resolving));
                defer engine.freeValue(input);
                defer for (resolving) |value| engine.freeValue(value);
                try publish(engine, "input", input);
                try script(engine, source);
                try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
                const reason = privateReason(engine);
                defer engine.freeValue(reason);
                if (flagged) c.JS_SetUncatchableError(engine.context, reason);
                const tag = c.pi_js_native_allocation_error_generation(reason);
                try std.testing.expectEqual(@as(u64, 1), tag);
                var args = [_]c.JSValue{reason};
                engine.freeValue(try engine.checked(c.JS_Call(engine.context, resolving[1], c.pi_js_undefined(), args.len, &args)));
                try verifyForwarded(engine, reason, flagged, tag);
            }
        }
    }
}

test "native Promise forwarding primitive rejection and ordinary fulfillment and actual handler throws" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try script(engine,
        \\globalThis.results=[];globalThis.primitives=[undefined,null,0,19,'raw',false,Symbol('reason'),7n];
        \\for(const reason of primitives)for(const select of [p=>p.then(),p=>p.then(undefined),p=>p.then(v=>v)])results.push(select(Promise.reject(reason)).catch(value=>{if(value!==reason)throw Error('primitive identity');return true}));
        \\globalThis.fulfilled=Promise.resolve(23).then().then(undefined).then(value=>value+1);
        \\globalThis.ordinaryThrown={};globalThis.ordinaryCaught=Promise.resolve(1).then(()=>{throw ordinaryThrown}).catch(value=>{if(value!==ordinaryThrown)throw Error('ordinary throw changed');return true});
        \\globalThis.rejectedHandlerReturn=Promise.reject('ordinary').then(undefined,reason=>{if(reason!=='ordinary')throw Error('wrong reject argument');return 41});
        \\globalThis.rejectedHandlerThrow=Promise.reject('ordinary').then(undefined,()=>{throw ordinaryThrown}).catch(value=>{if(value!==ordinaryThrown)throw Error('reject handler throw changed');return true});
        \\globalThis.complete=Promise.all([...results,fulfilled,ordinaryCaught,rejectedHandlerReturn,rejectedHandlerThrow]).then(values=>{if(values.length!==28||values.slice(0,24).some(v=>v!==true)||values[24]!==24||values[25]!==true||values[26]!==41||values[27]!==true)throw Error('ordinary Promise semantics');return true});
    );
    // This cohort intentionally has more than sixteen jobs.
    var count: usize = 0;
    while (c.JS_IsJobPending(engine.runtime) and count < 256) : (count += 1) try oneJob(engine);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    const complete = try field(engine, "complete");
    defer engine.freeValue(complete);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, complete));
    const result = c.JS_PromiseResult(engine.context, complete);
    defer engine.freeValue(result);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, result));
}

fn freshFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(context);
    c.JS_SetUncatchableError(context, reason);
    return c.JS_Throw(context, reason);
}

test "native Promise forwarding actual fresh native fatal handlers retain hard stop and raw reason" {
    for ([_][]const u8{
        "globalThis.handled=Promise.resolve(1).then(freshFatal);globalThis.output=handled.catch(()=>{globalThis.caught=true;return 37});",
        "globalThis.handled=Promise.reject('ordinary').then(undefined,freshFatal);globalThis.output=handled.catch(()=>{globalThis.caught=true;return 37});",
    }) |source| {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try engine.bindFunction("freshFatal", freshFatal, 1);
        try script(engine, source);
        try std.testing.expectEqual(@as(u64, 0), engine.native_allocation_generation);
        var context: ?*c.JSContext = null;
        try std.testing.expect(c.JS_ExecutePendingJob(engine.runtime, &context) < 0);
        const escaped = c.JS_GetException(context orelse engine.context);
        defer engine.freeValue(escaped);
        try std.testing.expect(c.JS_IsUncatchableError(escaped));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, escaped, engine.native_allocation_exception.?));
        try std.testing.expectEqual(@as(u64, 1), c.pi_js_native_allocation_error_generation(escaped));
        try std.testing.expectEqual(@as(u64, 1), engine.native_allocation_generation);
        for ([_][*:0]const u8{ "handled", "output" }) |key| {
            const promise = try field(engine, key);
            defer engine.freeValue(promise);
            try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, promise));
        }
        const caught = try field(engine, "caught");
        defer engine.freeValue(caught);
        try std.testing.expect(c.JS_IsUndefined(caught));
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    }
}
