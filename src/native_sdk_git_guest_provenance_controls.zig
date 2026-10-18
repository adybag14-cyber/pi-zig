//! Prepared genuine private SDK Git/PackageManager-input controls. UNRUN.
//! Requires a fresh actual Engine with its genuine node:url namespace installed.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const parser = @import("extensions/native_sdk_git_url.zig");
const c = v.c;

/// Successful C producer returns the newborn private allocation reason as DATA.
/// It deliberately publishes NO fatal event and leaves no pending exception.
fn makeData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(context);
    const global = c.JS_GetGlobalObject(context);
    if (c.JS_DefinePropertyValueStr(context, global, "actualGitOperationData", c.JS_DupValue(context, reason), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(global); engine.freeValue(reason);
        return c.JS_Throw(context, c.JS_GetException(context));
    }
    engine.freeValue(global);
    return reason;
}

/// The guest creates private DATA then throws THAT identity inside the same
/// URL constructor/getter callback. Source's actual forgiving Git catches must
/// run; a guest-call generation span must not manufacture a host fatal event.
pub fn verifySameGuestOperationDataThrowRemainsOrdinary(engine: *v.em.Engine, getter: bool) !void {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const node_url = engine.native_module_values.get("node:url") orelse return error.RequiredActualNodeUrlNamespace;
    const namespace = try s.own(try parser.create(engine, node_url));
    const parse = try s.get(namespace, "parseGitUrl");
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const maker = try s.own(try engine.checked(c.JS_NewCFunction(engine.context, makeData, "actualGitMakePrivateData", 0)));
    try s.put(global, "actualGitMakePrivateData", maker);
    const setup = try engine.evalModule(
        \\globalThis.actualGitOperationData=undefined;
        \\globalThis.actualGitOperationCalls=0;
        \\const RealURL=globalThis.URL;
        \\globalThis.actualGitInstallGuestBoundary=(getter)=>{
        \\  if(getter) Object.defineProperty(globalThis,'URL',{configurable:true,get(){actualGitOperationCalls++;const A=actualGitMakePrivateData();throw A}});
        \\  else globalThis.URL=new Proxy(RealURL,{construct(){actualGitOperationCalls++;const A=actualGitMakePrivateData();throw A}});
        \\};
    , "actual-git-same-operation-data.mjs"); engine.freeValue(setup);
    const install = try s.get(global, "actualGitInstallGuestBoundary");
    _ = try s.call(install, c.pi_js_undefined(), &.{c.pi_js_bool(engine.context, @intFromBool(getter))});
    const initial_generation = engine.native_allocation_generation;
    const input = try s.text("git:https://example.org/team/repo@next");
    var argv = [_]c.JSValue{input};
    var observed: v.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&observed);
    const raw = c.JS_Call(engine.context, parse, c.pi_js_undefined(), argv.len, &argv);
    const recorded_fatal = observed.first != null;
    const result = engine.leaveNativeInvocation(&observed, raw); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsNull(result));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!recorded_fatal);
    const reason = try s.get(global, "actualGitOperationData");
    try std.testing.expect(c.JS_IsObject(reason));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    const tag = c.pi_js_native_allocation_error_generation(reason);
    try std.testing.expect(tag != 0 and tag -% initial_generation != 0);
    const calls = try s.get(global, "actualGitOperationCalls");
    var count: i32 = 0;
    try std.testing.expect(c.JS_ToInt32(engine.context, &count, calls) == 0 and count > 0);
    try std.testing.expect(engine.native_fatal_invocation == null);
    // Fresh realm teardown only; no guest restoration following a failed assert.
}
