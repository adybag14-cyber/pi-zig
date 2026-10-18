//! The actual utils/child-process.ts spawn wrappers over shared native Node and
//! Windows cross-spawn namespaces, plus the actual Source idle-grace consumer
//! over supplied genuine child events/streams.
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
pub fn create(engine: *js.Engine) !c.JSValue {
    const name = "pi-native:source-child-process-utils-bootstrap";
    if (engine.native_module_values.get(name)) |value| return c.JS_DupValue(engine.context, value);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const node = try scope.own(try @import("native_node_child_process.zig").create(engine, false));
    const cross = try scope.own(try @import("native_node_child_process.zig").create(engine, true));
    const namespace = try scope.object();
    inline for (.{ .{ "spawnProcess", "spawn" }, .{ "spawnProcessSync", "spawnSync" } }) |entry| {
        try scope.put(namespace, entry[0], try scope.own(try @import("native_node_function.zig").create(engine, entry[0], 3, called, &.{ try scope.get(node, entry[1]), try scope.get(cross, entry[1]) })));
    }
    try scope.put(namespace, "waitForChildProcess", try scope.own(try @import("native_wait_for_child_process.zig").create(engine)));
    try engine.registerValueModule(name, namespace);
    return c.JS_DupValue(engine.context, namespace);
}
/// Actual Source wrappers over the canonical public namespaces. Selection stays
/// with the caller; do not silently reuse the old bootstrap's captured functions.
pub fn createWithNamespaces(engine: *js.Engine, node: c.JSValue, cross: c.JSValue, actual_process: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: js.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const generation = engine.native_allocation_generation;
    const result = createPublicInner(engine, node, cross, actual_process) catch |err| {
        const failure = @import("native_child_process_function.zig").directFailure(engine, err, generation);
        _ = engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())) catch |actual| return actual;
        return @as(anyerror!c.JSValue, failure);
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn createPublicInner(engine: *js.Engine, node: c.JSValue, cross: c.JSValue, actual_process: c.JSValue) !c.JSValue {
    _ = actual_process; // Source intentionally reads live global process below.
    const PublicScope = @import("native_node_socket_scope.zig").Scope;
    const functions = @import("native_child_process_function.zig");
    const key = "\x00native.sdk.child-process-utils.public";
    try engine.checkNativeEntry();
    var scope: PublicScope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    if (engine.native_module_values.get(key)) |select| {
        const old_node = try scope.call(select, c.pi_js_undefined(), &.{c.JS_NewInt32(engine.context, 1)});
        const old_cross = try scope.call(select, c.pi_js_undefined(), &.{c.JS_NewInt32(engine.context, 2)});
        if (!scope.equal(old_node, node) or !scope.equal(old_cross, cross)) return error.NativeChildUtilitiesNamespaceMismatch;
        return c.JS_DupValue(engine.context, try scope.call(select, c.pi_js_undefined(), &.{c.JS_NewInt32(engine.context, 0)}));
    }
    const namespace = try scope.object();
    inline for (.{ .{ "spawnProcess", "spawn", "spawn" }, .{ "spawnProcessSync", "spawnSync", "sync" } }) |entry| {
        const synchronous = @import("std").mem.eql(u8, entry[0], "spawnProcessSync");
        try scope.put(namespace, entry[0], try scope.own(try functions.create(engine, entry[0], 3, calledActual, &.{ try scope.get(node, entry[1]), cross, c.pi_js_bool(engine.context, @intFromBool(synchronous)) })));
    }
    try scope.put(namespace, "waitForChildProcess", try scope.own(try @import("native_wait_for_child_process.zig").create(engine)));
    const select = try scope.own(try functions.createArrow(engine, "", 1, selectPublic, &.{namespace, node, cross}));
    try engine.checkNativeEntry();
    const retained = c.JS_DupValue(engine.context, select);
    engine.native_module_values.put(engine.gpa, key, retained) catch |err| {
        var failed = @import("native_sdk_owned_completion.zig").Completion.initVoid(engine, err);
        failed.release(retained); try failed.finishVoid(); unreachable;
    };
    return c.JS_DupValue(engine.context, namespace);
}
fn selectPublic(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var index: u32 = 0;
    if (c.JS_ToUint32(engine.context, &index, if (args.len == 0) c.pi_js_undefined() else args[0]) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    if (index >= roots.len) return error.NativeChildUtilitiesSelection;
    return c.JS_DupValue(engine.context, roots[index]);
}
fn calledActual(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: @import("native_node_socket_scope.zig").Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const windows = try actualWindows(engine);
    if (windows and scope.truthy(roots[2])) return c.JS_DupValue(engine.context, try scope.call(try scope.get(roots[1], "sync"), roots[1], args));
    return c.JS_DupValue(engine.context, try scope.call(roots[@intFromBool(windows)], c.pi_js_undefined(), args));
}fn called(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const windows = scope.equal(try scope.get(try scope.global("process"), "platform"), try scope.text("win32"));
    return js.call(engine, roots[@intFromBool(windows)], c.pi_js_undefined(), args);
}

fn actualWindows(engine: *js.Engine) !bool {
    var scope: @import("native_node_socket_scope.zig").Scope = .{ .engine = engine };
    const value = try @import("native_sdk_owned_completion.zig").finishValue(&scope, actualWindowsBody(&scope));
    return c.JS_ToBool(engine.context, value) == 1;
}
fn actualWindowsBody(scope: *@import("native_node_socket_scope.zig").Scope) !c.JSValue {
    const platform = try scope.get(try scope.global("process"), "platform");
    return c.pi_js_bool(scope.engine.context, @intFromBool(scope.equal(platform, try scope.text("win32"))));
}
