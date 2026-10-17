//! Prepared real VM controls; no compiler, metadata or runtime execution claim.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
fn capture(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_CaptureCurrentStackFrames(context, 32, c.pi_js_undefined(), null, 0, 0, c.JS_ERROR_STACK_SKIP_FIRST);
}
fn clone(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_CloneCapturedStackFrame(context, if (argc > 0) args[0] else c.pi_js_undefined());
}
fn install(engine: *em.Engine) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
    defer engine.freeValue(global);
    const probe = try engine.checked(c.JS_NewCFunction(engine.context, capture, "ownedCapture", 0));
    if (c.JS_SetPropertyStr(engine.context, global, "ownedCapture", probe) < 0) return error.CaptureSetupFailure;
    const copier = try engine.checked(c.JS_NewCFunction(engine.context, clone, "ownedClone", 1));
    if (c.JS_SetPropertyStr(engine.context, global, "ownedClone", copier) < 0) return error.CaptureSetupFailure;
}
fn check(engine: *em.Engine, code: []const u8) !void {
    const result = try engine.eval(code, "C:/callsite/visibility-script.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_ToBool(engine.context, result) == 1);
}
test "CallSite visibility preserves sloppy function and actual object receiver after return and GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    try check(engine, "globalThis.receiver={marker:1};function sloppy(){return ownedCapture()}globalThis.frames=sloppy.call(receiver);frames[0].getFunction()===sloppy&&frames[0].getThis()===receiver");
    c.JS_RunGC(engine.runtime);
    try check(engine, "frames[0].getFunction()===sloppy&&frames[0].getThis()===receiver&&ownedClone(frames[0]).getThis()===receiver");
}
test "CallSite visibility poisons strict frame and older sloppy frames but preserves younger sloppy frame" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    try check(engine, "globalThis.youngerReceiver={};function younger(){return ownedCapture()}function strictMiddle(){'use strict';return younger.call(youngerReceiver)}function older(){return strictMiddle()}globalThis.frames=older();frames[0].getFunction()===younger&&frames[0].getThis()===youngerReceiver&&frames[1].getFunction()===undefined&&frames[1].getThis()===undefined&&frames[2].getFunction()===undefined&&frames[2].getThis()===undefined");
    c.JS_RunGC(engine.runtime);
    try check(engine, "ownedClone(frames[1]).getFunction()===undefined&&ownedClone(frames[2]).getThis()===undefined");
}
test "CallSite visibility uses actual top-level flag rather than eval spelling" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    try check(engine, "globalThis.named={'<eval>'(){return ownedCapture()}};globalThis.frames=named['<eval>']();frames[0].getFunction()===named['<eval>']&&frames[0].getThis()===named&&frames[1].getFunction()===undefined&&frames[1].getThis()===globalThis");
}
test "CallSite visibility applies strict poisoning to actual legacy Error prepareStackTrace capture" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try check(engine, "Error.prepareStackTrace=function(error,frames){return frames};function legacyStrict(){'use strict';return new Error('owned').stack}function legacyOlder(){return legacyStrict()}globalThis.legacyFrames=legacyOlder();const strictFrame=legacyFrames.find(f=>f.getFunctionName()==='legacyStrict'),olderFrame=legacyFrames.find(f=>f.getFunctionName()==='legacyOlder');strictFrame!==undefined&&olderFrame!==undefined&&strictFrame.getFunction()===undefined&&strictFrame.getThis()===undefined&&olderFrame.getFunction()===undefined&&olderFrame.getThis()===undefined");
    c.JS_RunGC(engine.runtime);
    try check(engine, "legacyFrames.find(f=>f.getFunctionName()==='legacyOlder').getThis()===undefined");
}
test "CallSite visibility retains one actual sloppy primitive box with and without this expression" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    try check(engine, "function usesThis(){return [ownedCapture(),ownedCapture(),this]}function unusedThis(){return [ownedCapture(),ownedCapture()]}globalThis.used=usesThis.call('boxed');globalThis.unused=unusedThis.call('unused');used[0][0].getThis()===used[2]&&used[1][0].getThis()===used[2]&&unused[0][0].getThis()===unused[1][0].getThis()&&unused[0][0].getThis().valueOf()==='unused'");
    c.JS_RunGC(engine.runtime);
    try check(engine, "ownedClone(unused[0][0]).getThis()===unused[1][0].getThis()");
}
test "CallSite visibility retains coroutine receiver through suspension resume and GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    const started = try engine.eval("globalThis.asyncReceiver={};async function ownedAsync(){await 0;globalThis.asyncFrames=ownedCapture()}ownedAsync.call(asyncReceiver)", "C:/callsite/async-script.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(started);
    c.JS_RunGC(engine.runtime);
    _ = try engine.drainReadyJobs();
    c.JS_RunGC(engine.runtime);
    try check(engine, "asyncFrames[0].getFunction()===ownedAsync&&asyncFrames[0].getThis()===asyncReceiver");
}
fn nativeBody(context: ?*c.JSContext, _: c.JSValue, _: c.JSValue, _: c_int, _: [*c]const c.JSValue, _: c_int, _: c.JSValue, _: [*c]c.JSValue, action: [*c]c_int) callconv(.c) c.JSValue {
    action[0] = c.JS_PI_AF_RETURN;
    return c.JS_CaptureCurrentStackFrames(context, 32, c.pi_js_undefined(), null, 0, 0, 0);
}
test "CallSite visibility native AsyncFunction frame initializes receiver and poisons older frames" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context)); defer engine.freeValue(global);
    const function = try engine.checked(c.JS_PiNewNativeAsyncFunction(engine.context, nativeBody, c.pi_js_undefined(), c.pi_js_undefined(), 0, "ownedNative", 0));
    if (c.JS_SetPropertyStr(engine.context, global, "ownedNative", function) < 0) return error.NativeSetupFailure;
    const started = try engine.eval("function nativeCaller(){return ownedNative.call({})}nativeCaller().then(frames=>{globalThis.nativeFrames=frames})", "C:/callsite/native-caller.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(started);
    _ = try engine.drainReadyJobs();
    c.JS_RunGC(engine.runtime);
    try check(engine, "nativeFrames[0].getFunction()===undefined&&nativeFrames[0].getThis()===undefined&&nativeFrames[1].getFunction()===undefined&&nativeFrames[1].getThis()===undefined");
}
const PrologueProbe = struct {
    context: ?*c.JSContext,
    warmed: bool = false,
    armed: bool = false,
    captured: c.JSValue,
    calls: usize = 0,
    fn poll(_: ?*c.JSRuntime, data: ?*anyopaque) callconv(.c) c_int {
        const self: *PrologueProbe = @ptrCast(@alignCast(data.?));
        self.warmed = true;
        if (!self.armed) return 0;
        self.calls += 1;
        self.armed = false;
        self.captured = c.JS_CaptureCurrentStackFrames(self.context, 8, c.pi_js_undefined(), null, 0, 0, 0);
        return 1; // Actual trusted VM interruption stops before body evaluation.
    }
};
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue { return c.pi_js_undefined(); }
fn prologueSubject(legacy: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    if (legacy) try check(engine, "Error.prepareStackTrace=function(error,frames){globalThis.legacyPrologueFrames=frames;return frames};true");
    const module = try engine.eval("export function declaration(){return 1}globalThis.prologueBodyRan=true", "C:/callsite/prologue.mjs", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer engine.freeValue(module);
    const warm = try engine.checked(c.JS_NewCFunction(engine.context, noop, "ownedNoop", 0)); defer engine.freeValue(warm);
    var probe: PrologueProbe = .{ .context = engine.context, .captured = c.pi_js_undefined() };
    defer engine.freeValue(probe.captured);
    c.JS_SetInterruptHandler(engine.runtime, PrologueProbe.poll, &probe);
    defer c.JS_SetInterruptHandler(engine.runtime, null, null);
    var warm_calls: usize = 0;
    while (!probe.warmed and warm_calls < 10000) : (warm_calls += 1) {
        const result = c.JS_Call(engine.context, warm, c.pi_js_undefined(), 0, null);
        defer engine.freeValue(result);
        try std.testing.expect(!c.JS_IsException(result));
    }
    try std.testing.expect(probe.warmed);
    // The actual pinned 10000-call cadence has just reset. One call-entry poll
    // and the module declaration-prologue if_false poll remain before capture.
    for (0..9998) |_| {
        const result = c.JS_Call(engine.context, warm, c.pi_js_undefined(), 0, null);
        defer engine.freeValue(result);
        try std.testing.expect(!c.JS_IsException(result));
    }
    probe.armed = true;
    const evaluated = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
    defer engine.freeValue(evaluated);
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    defer c.JS_ClearUncatchableError(engine.context, reason);
    c.JS_SetInterruptHandler(engine.runtime, null, null);
    try std.testing.expect(c.JS_IsException(evaluated));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expect(!c.JS_IsException(probe.captured));
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context)); defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "prologueFrames", c.JS_DupValue(engine.context, probe.captured)) < 0) return error.PrologueCaptureFailure;
    c.JS_RunGC(engine.runtime);
    try check(engine, "prologueFrames.length>0&&prologueFrames[0].getFileName()==='C:/callsite/prologue.mjs'&&prologueFrames[0].getFunction()===undefined&&prologueFrames[0].getThis()===undefined&&globalThis.prologueBodyRan===undefined");
    if (legacy) try check(engine, "globalThis.legacyPrologueFrame=legacyPrologueFrames.find(frame=>frame.getFileName()==='C:/callsite/prologue.mjs');legacyPrologueFrame!==undefined&&legacyPrologueFrame.getFunction()===undefined&&legacyPrologueFrame.getThis()===undefined&&legacyPrologueFrame.getLineNumber()===null&&legacyPrologueFrame.getColumnNumber()===null");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
test "CallSite visibility hides actual strict module prologue function before its body runs" { try prologueSubject(false); }
test "CallSite visibility legacy prepareStackTrace handles actual module prologue without current PC" { try prologueSubject(true); }
