//! Commands execute against fresh resolved rows before prompt admission.
//! Promise continuations root the actual session and captured preflight callback.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;

pub fn start(owner: *sdk.State, session: c.JSValue, args: []const c.JSValue) !?c.JSValue {
    const engine = owner.engine;
    const options = if (args.len > 1) args[1] else c.pi_js_undefined();
    const expand = if (c.JS_IsNull(options) or c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "expandPromptTemplates");
    defer engine.freeValue(expand);
    const preflight = if (c.JS_IsNull(options) or c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "preflightResult");
    defer engine.freeValue(preflight);
    if (!c.JS_IsNull(expand) and !c.JS_IsUndefined(expand) and c.JS_ToBool(engine.context, expand) != 1) return null;
    const source = try engine.toString(args[0]);
    defer engine.gpa.free(source);
    if (source.len == 0 or source[0] != '/') return null;
    const split = @import("std").mem.indexOfScalar(u8, source, ' ') orelse source.len;
    const command_name = try sdk.text(engine, source[1..split]);
    defer engine.freeValue(command_name);
    const command = try @import("native_sdk_commands.zig").getCommand(owner, command_name);
    defer engine.freeValue(command);
    if (c.JS_ToBool(engine.context, command) != 1) return null;
    const lease = try sdk.sessionModelLease(owner);
    const generation = try engine.checked(c.JS_NewBigUint64(engine.context, lease.generation));
    defer engine.freeValue(generation);
    const runtime = try engine.checked(c.JS_NewBigUint64(engine.context, lease.runtime_id));
    defer engine.freeValue(runtime);
    const context = try @import("native_sdk_tool_context.zig").createCommand(engine, session, generation, runtime);
    defer engine.freeValue(context);
    const raw = try sdk.text(engine, if (split == source.len) "" else source[split + 1 ..]);
    defer engine.freeValue(raw);
    var roots = [_]c.JSValue{ session, command_name, preflight };
    const rejected = try engine.checked(c.JS_NewCFunctionData2(engine.context, failed, "", 1, 0, roots.len, &roots));
    defer engine.freeValue(rejected);
    const handler = sdk.get(engine, command, "handler") catch |err| return syncFailure(engine, err, rejected);
    defer engine.freeValue(handler);
    const pending = js.call(engine, handler, command, &.{ raw, context }) catch |err| return syncFailure(engine, err, rejected);
    defer engine.freeValue(pending);
    const promise = try sdk.promise(engine, pending);
    defer engine.freeValue(promise);
    const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, handled, "", 0, 0, roots.len, &roots));
    defer engine.freeValue(done);
    return try sdk.invoke(engine, promise, "then", &.{ done, rejected });
}
fn syncFailure(engine: *em.Engine, err: anyerror, rejected: c.JSValue) !?c.JSValue {
    _ = sdk.fail(engine, err);
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    const promise = try sdk.promise(engine, reason);
    defer engine.freeValue(promise);
    // Synchronous handler failures pass through the same await boundary.
    return try sdk.invoke(engine, promise, "then", &.{rejected});
}
fn handled(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return complete(engine, roots[2]) catch |err| sdk.fail(engine, err);
}
fn complete(engine: *em.Engine, callback: c.JSValue) !c.JSValue {
    if (!c.JS_IsNull(callback) and !c.JS_IsUndefined(callback)) {
        const disposition = try sdk.text(engine, "handled");
        defer engine.freeValue(disposition);
        const ignored = try js.call(engine, callback, c.pi_js_undefined(), &.{disposition});
        engine.freeValue(ignored);
    }
    return c.pi_js_undefined();
}
fn failed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return report(engine, roots, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn report(engine: *em.Engine, roots: [*c]c.JSValue, reason: c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, roots[0]);
    const report_value = try sdk.object(engine);
    defer engine.freeValue(report_value);
    const prefix = try sdk.text(engine, "command:");
    defer engine.freeValue(prefix);
    try sdk.put(engine, report_value, "extensionPath", try @import("native_select_list.zig").concat(engine, &.{ prefix, roots[1] }));
    try sdk.put(engine, report_value, "event", try sdk.text(engine, "command"));
    try sdk.put(engine, report_value, "error", if (c.JS_IsError(reason)) try sdk.get(engine, reason, "message") else converted: {
        const message = try engine.toString(reason);
        defer engine.gpa.free(message);
        break :converted try sdk.text(engine, message);
    });
    const callback = try sdk.get(engine, owner.data, "extension_onError");
    defer engine.freeValue(callback);
    if (c.JS_ToBool(engine.context, callback) == 1) {
        const ignored = try js.call(engine, callback, c.pi_js_undefined(), &.{report_value});
        engine.freeValue(ignored);
    }
    return complete(engine, roots[2]);
}
