//! Actual c268 utils/sleep ordinary producer, with genuine Source comparisons.
const std = @import("std");
const x = @import("extensions/native_ai_auth_helper_values.zig");
const c = x.c;
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
fn publish(engine: *x.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn prepare(engine: *x.em.Engine) !void {
    engine.native_io = std.testing.io;
    const native = try @import("extensions/native_ai_sleep.zig").create(engine);
    defer engine.freeValue(native);
    try publish(engine, "sleepNative", native);
    const source = try engine.evalModule(@embedFile("extensions/fixtures/ai-sleep-c268-source.mjs"), "actual-source-sleep-c268.mjs");
    defer engine.freeValue(source);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    try publish(engine, "sleepSource", try scope.get(source, "sleep"));
    const hooks = try retirement.createNativeRetirementHooks(engine);
    defer engine.freeValue(hooks);
    try publish(engine, "sleepHooks", hooks);
}
fn run(engine: *x.em.Engine, source: []const u8) !void {
    const namespace = try engine.evalModule(source, "actual-ai-sleep-caller.mjs");
    engine.freeValue(namespace);
}
fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
fn select(engine: *x.em.Engine, native: bool) !void {
    try run(engine, if (native) "globalThis.selectedSleep=sleepNative;" else "globalThis.selectedSleep=sleepSource;");
}
test "native AI sleep actual ordinary constructible declaration metadata" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "sleepSource", "sleepNative" }) |name| {
        const function = try scope.global(name);
        try std.testing.expect(!c.JS_IsAsyncFunction(function));
        try std.testing.expect(c.JS_IsConstructor(engine.context, function));
        try std.testing.expect(scope.equal(try scope.get(function, "length"), c.JS_NewInt32(engine.context, 2)));
        try std.testing.expect(scope.equal(try scope.get(function, "name"), try scope.text("sleep")));
    }
}
test "native AI sleep exact Source live Promise timer cancellation receiver and TDZ observations" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    const source = try std.mem.concat(engine.gpa, u8, &.{
        @embedFile("extensions/fixtures/ai-sleep-observer.mjs"),
        "\nexport const rows=await compareSleep(sleepNative,sleepSource);if(rows.length!==7)throw Error('All actual sleep routes required');",
    });
    defer engine.gpa.free(source);
    try run(engine, source);
}
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    _ = x.em.Engine.fromContext(context.?).throwNativeOutOfMemory();
    return c.JS_GetException(context);
}
fn actualFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?);
    _ = engine.checked(engine.throwNativeOutOfMemoryFatal()) catch {};
    const global = c.JS_GetGlobalObject(context);
    defer engine.freeValue(global);
    _ = c.JS_DefinePropertyValueStr(context, global, "sleepObservedB", c.JS_DupValue(context, engine.captured_exception.?), c.JS_PROP_C_W_E);
    return c.pi_js_undefined();
}
test "native AI sleep same-operation private DATA from throwIfAborted remains an ordinary rejection" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try engine.bindFunction("sleepPrivateData", privateData, 0);
    try run(engine,
        \\globalThis.sleepA=undefined;globalThis.sleepCaught=undefined;
        \\try{await sleepNative(1,{throwIfAborted(){sleepA=sleepPrivateData();throw sleepA}})}catch(error){sleepCaught=error}
        \\if(!sleepA||sleepCaught!==sleepA)throw Error("Actual sleep DATA identity");
    );
    const reason = try read(engine, "sleepA");
    defer engine.freeValue(reason);
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "native AI sleep actual B preempts later private DATA A inside the Promise executor" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try engine.bindFunction("sleepPrivateData", privateData, 0);
    try engine.bindFunction("sleepActualFatal", actualFatal, 0);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\globalThis.sleepA=undefined;globalThis.sleepCaught=false;
        \\try{await sleepNative(1,{throwIfAborted(){sleepA=sleepPrivateData();sleepActualFatal();throw sleepA}})}catch(error){sleepCaught=true}
    , "actual-sleep-fatal-priority.mjs"));
    const selected = engine.captured_exception orelse return error.RequiredSleepFatal;
    const reason = try read(engine, "sleepObservedB");
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, selected, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "native AI sleep throwIfAborted temporary retires before the setTimeout getter" {
    inline for (.{false, true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try select(engine, native);
        try run(engine,
            \\globalThis.sleepTemporary=sleepHooks.make(0);globalThis.sleepElapsed=undefined;
            \\globalThis.sleepSignal={throwIfAborted(){const value=sleepTemporary;sleepTemporary=undefined;return value},addEventListener(){},removeEventListener(){}};
            \\Object.defineProperty(globalThis,"setTimeout",{configurable:true,get(){if(sleepHooks.count(0)!==1)throw Error("throwIfAborted return retained");return callback=>{sleepElapsed=callback;return 1}}});
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        try run(engine,
            \\const pending=selectedSleep(1,sleepSignal);sleepElapsed();delete globalThis.sleepElapsed;await pending;
            \\if(sleepHooks.count(0)!==1)throw Error("Actual return-holder retirement required");
        );
    }
}
test "native AI sleep clearTimeout return retires before the actual signal reason getter" {
    inline for (.{false, true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try select(engine, native);
        try run(engine,
            \\globalThis.sleepTemporary=sleepHooks.make(0);globalThis.sleepAbort=undefined;globalThis.sleepElapsed=undefined;
            \\globalThis.setTimeout=callback=>{sleepElapsed=callback;return 9};
            \\globalThis.clearTimeout=()=>{const value=sleepTemporary;sleepTemporary=undefined;return value};
            \\globalThis.sleepReason={expected:true};
            \\globalThis.sleepSignal={throwIfAborted(){},addEventListener(name,callback){sleepAbort=callback},removeEventListener(){},get reason(){if(sleepHooks.count(0)!==1)throw Error("clear return retained");return sleepReason}};
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        try run(engine,
            \\const pending=selectedSleep(1,sleepSignal);sleepAbort();delete globalThis.sleepAbort;delete globalThis.sleepElapsed;
            \\let caught=false;try{await pending}catch(error){if(error!==sleepReason)throw error;caught=true}
            \\if(!caught||sleepHooks.count(0)!==1)throw Error("Actual abort reason and retirement required");
        );
    }
}
test "native AI sleep pending closure retains the real signal and releases it after callback disposal" {
    inline for (.{false, true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try select(engine, native);
        try run(engine,
            \\globalThis.sleepElapsed=undefined;globalThis.sleepWeak=undefined;
            \\globalThis.setTimeout=callback=>{sleepElapsed=callback;return 9};
            \\globalThis.sleepPending=(()=>{const signal={holder:sleepHooks.make(0),throwIfAborted(){},addEventListener(){},removeEventListener(){}};sleepWeak=new WeakRef(signal);return selectedSleep(1,signal)})();
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        c.JS_RunGC(engine.runtime);
        try run(engine,
            \\if(sleepHooks.count(0)!==0||sleepWeak.deref()===undefined)throw Error("Pending signal released");
            \\sleepElapsed();delete globalThis.sleepElapsed;await sleepPending;delete globalThis.sleepPending;
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        c.JS_RunGC(engine.runtime);
        try run(engine,
            \\if(sleepHooks.count(0)!==1||sleepWeak.deref()!==undefined)throw Error("Disposed signal retained");
        );
    }
}
