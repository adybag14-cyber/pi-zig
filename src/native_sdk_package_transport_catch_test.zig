//! Prepared component controls over the actual five-method transport installer.
//! Controlled process/read/spawn callbacks exercise catch ownership only; they
//! do not qualify the real OS child transport or select a production default.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
fn observeEmptyCapture(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    if (engine.captured_exception != null) return error.SwallowedReasonStillCaptured;
    return c.pi_js_undefined();
}
fn freshAllocation(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    if (c.JS_SetPropertyStr(engine.context, roots[0], "original", c.JS_DupValue(engine.context, reason)) < 0) return v.js.capture(engine);
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
}
fn setup(engine: *v.em.Engine, source: []const u8) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    const record = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    const functions = @import("extensions/native_node_function.zig");
    try s.put(global, "observeEmptyCapture", try s.own(try functions.create(engine, "observeEmptyCapture", 0, observeEmptyCapture, &.{})));
    try s.put(global, "raiseFreshAllocation", try s.own(try functions.create(engine, "raiseFreshAllocation", 0, freshAllocation, &.{record})));
    const configured = try s.own(try engine.eval(source, "package-transport-catch-setup.js", c.JS_EVAL_TYPE_GLOBAL));
    const prototype = try s.object();
    try @import("extensions/native_sdk_package_transport.zig").install(engine, prototype, .{
        .process = try s.get(configured, "process"),
        .read_file_sync = try s.get(configured, "readFileSync"),
        .spawn_process = try s.get(configured, "spawn"),
        .spawn_process_sync = try s.get(configured, "spawn"),
        .is_stdout_taken_over = try s.get(configured, "taken"),
    });
    try s.put(global, "actualTransportMethods", prototype);
    return c.JS_DupValue(engine.context, record);
}
const fixture =
    \\globalThis.reason={raw:true};globalThis.envReads=0;globalThis.fallbackEnv={kept:true};
    \\({process:{platform:'linux',get env(){if(++envReads===1)return{};observeEmptyCapture();if(globalThis.rethrowSame)throw reason;return fallbackEnv}},
    \\readFileSync(){if(globalThis.nativeFailure)raiseFreshAllocation();throw reason},spawn(command,args,options){return options.env},taken(){return false}})
;
test "actual transport empty catch consumes before fallback and preserves same object thrown anew" {
    for ([_]bool{ false, true }) |rethrow| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const record = try setup(engine, fixture); defer engine.freeValue(record);
        const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
        try v.js.define(engine, global, "rethrowSame", c.pi_js_bool(engine.context, @intFromBool(rethrow)));
        if (rethrow) {
            try std.testing.expectError(error.JavaScriptException, engine.eval("actualTransportMethods.spawnCommand('owned',[])", "transport-fallback-new-throw.js", c.JS_EVAL_TYPE_GLOBAL));
            const reason = try v.js.global(engine, "reason"); defer engine.freeValue(reason);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
        } else {
            const result = try engine.eval("actualTransportMethods.spawnCommand('owned',[])", "transport-fallback-success.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(result);
            const expected = try v.js.global(engine, "fallbackEnv"); defer engine.freeValue(expected);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, expected));
            try std.testing.expect(engine.captured_exception == null);
        }
    }
}
test "actual transport catch preserves exact fresh native allocation before fallback getter" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const record = try setup(engine, fixture); defer engine.freeValue(record);
    const configured = try engine.eval("globalThis.nativeFailure=true", "transport-native-setup.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(configured);
    try std.testing.expectError(error.JavaScriptException, engine.eval("actualTransportMethods.spawnCommand('owned',[])", "transport-native-failure.js", c.JS_EVAL_TYPE_GLOBAL));
    const original = try v.js.get(engine, record, "original"); defer engine.freeValue(original);
    const actual = engine.captured_exception orelse return error.MissingNativeReason;
    try std.testing.expect(c.pi_js_native_allocation_error_generation(original) != 0);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, actual));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    const reads = try v.js.global(engine, "envReads"); defer engine.freeValue(reads);
    var count: i32 = 0;
    try std.testing.expect(c.JS_ToInt32(engine.context, &count, reads) == 0);
    try std.testing.expectEqual(@as(i32, 1), count);
}
