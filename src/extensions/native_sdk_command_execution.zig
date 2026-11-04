//! Commands execute against fresh resolved rows before prompt admission.
//! Promise continuations root the actual session and captured preflight callback.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;

// A direct native allocator outcome is a producer before deferred JS roots
// can publish a later cleanup event. Other typed failures retain their class.
fn nativeAllocation(engine: anytype, result: anytype) @TypeOf(result) {
    return result catch |err| {
        if (@as(anyerror, err) == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal();
        return err;
    };
}
fn nativeText(engine: anytype, value: c.JSValue) anyerror![]u8 {
    try engine.checkNativeEntry();
    return nativeAllocation(engine, engine.toString(value));
}

pub fn start(owner: *sdk.State, session: c.JSValue, args: []const c.JSValue) !?c.JSValue {
    const engine = owner.engine;
    const options = if (args.len > 1) args[1] else c.pi_js_undefined();
    const expand = if (c.JS_IsNull(options) or c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "expandPromptTemplates");
    defer engine.releaseNativeValue(expand);
    const preflight = if (c.JS_IsNull(options) or c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "preflightResult");
    defer engine.releaseNativeValue(preflight);
    if (!c.JS_IsNull(expand) and !c.JS_IsUndefined(expand) and c.JS_ToBool(engine.context, expand) != 1) return null;
    const source = try nativeText(engine, args[0]);
    defer engine.gpa.free(source);
    if (source.len == 0 or source[0] != '/') return null;
    const split = @import("std").mem.indexOfScalar(u8, source, ' ') orelse source.len;
    const command_name = try sdk.text(engine, source[1..split]);
    defer engine.releaseNativeValue(command_name);
    const command = try @import("native_sdk_commands.zig").getCommand(owner, command_name);
    defer engine.releaseNativeValue(command);
    if (c.JS_ToBool(engine.context, command) != 1) return null;
    const lease = try sdk.sessionModelLease(owner);
    const generation = try engine.checked(c.JS_NewBigUint64(engine.context, lease.generation));
    defer engine.releaseNativeValue(generation);
    const runtime = try engine.checked(c.JS_NewBigUint64(engine.context, lease.runtime_id));
    defer engine.releaseNativeValue(runtime);
    const context = try @import("native_sdk_tool_context.zig").createCommand(engine, session, generation, runtime);
    defer engine.releaseNativeValue(context);
    const raw = try sdk.text(engine, if (split == source.len) "" else source[split + 1 ..]);
    defer engine.releaseNativeValue(raw);
    var roots = [_]c.JSValue{ session, command_name, preflight };
    const rejected = try engine.checked(c.JS_NewCFunctionData2(engine.context, failed, "", 1, 0, roots.len, &roots));
    defer engine.releaseNativeValue(rejected);
    const handler = sdk.get(engine, command, "handler") catch |err| return syncFailure(engine, err, rejected);
    defer engine.releaseNativeValue(handler);
    const pending = js.call(engine, handler, command, &.{ raw, context }) catch |err| return syncFailure(engine, err, rejected);
    defer engine.releaseNativeValue(pending);
    const promise = try sdk.promise(engine, pending);
    defer engine.releaseNativeValue(promise);
    const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, handled, "", 0, 0, roots.len, &roots));
    defer engine.releaseNativeValue(done);
    return try sdk.invoke(engine, promise, "then", &.{ done, rejected });
}
fn syncFailure(engine: *em.Engine, err: anyerror, rejected: c.JSValue) !?c.JSValue {
    const reason = try @import("native_agent_async.zig").reason(engine, err);
    defer engine.releaseNativeValue(reason);
    const promise = try sdk.promise(engine, reason);
    defer engine.releaseNativeValue(promise);
    // Synchronous handler failures pass through the same await boundary.
    return try sdk.invoke(engine, promise, "then", &.{rejected});
}
fn handled(context: ?*c.JSContext, ignored0: c.JSValue, ignored1: c_int, ignored2: [*c]c.JSValue, ignored3: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(handledOwnedBody(context, ignored0, ignored1, ignored2, ignored3, roots));
}
fn handledOwnedBody(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return complete(engine, roots[2]) catch |err| sdk.fail(engine, err);
}
fn complete(engine: *em.Engine, callback: c.JSValue) !c.JSValue {
    if (!c.JS_IsNull(callback) and !c.JS_IsUndefined(callback)) {
        const disposition = try sdk.text(engine, "handled");
        defer engine.releaseNativeValue(disposition);
        const ignored = try js.call(engine, callback, c.pi_js_undefined(), &.{disposition});
        engine.releaseNativeValue(ignored);
    }
    return c.pi_js_undefined();
}
fn failed(context: ?*c.JSContext, ignored0: c.JSValue, argc: c_int, argv: [*c]c.JSValue, ignored1: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(failedOwnedBody(context, ignored0, argc, argv, ignored1, roots));
}
fn failedOwnedBody(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return report(engine, roots, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn report(engine: *em.Engine, roots: [*c]c.JSValue, reason: c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, roots[0]);
    const report_value = try sdk.object(engine);
    defer engine.releaseNativeValue(report_value);
    const prefix = try sdk.text(engine, "command:");
    defer engine.releaseNativeValue(prefix);
    try sdk.put(engine, report_value, "extensionPath", try @import("native_select_list.zig").concat(engine, &.{ prefix, roots[1] }));
    try sdk.put(engine, report_value, "event", try sdk.text(engine, "command"));
    try sdk.put(engine, report_value, "error", if (c.JS_IsError(reason)) try sdk.get(engine, reason, "message") else converted: {
        const message = try nativeText(engine, reason);
        defer engine.gpa.free(message);
        break :converted try sdk.text(engine, message);
    });
    const callback = try sdk.get(engine, owner.data, "extension_onError");
    defer engine.releaseNativeValue(callback);
    if (c.JS_ToBool(engine.context, callback) == 1) {
        const ignored = try js.call(engine, callback, c.pi_js_undefined(), &.{report_value});
        engine.releaseNativeValue(ignored);
    }
    return complete(engine, roots[2]);
}
