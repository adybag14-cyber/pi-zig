//! Ordinary Source AgentSession user-bash methods. The executor and local
//! operations factory must be the shared native module bindings.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Method = enum(c_int) { executeBash, recordBashResult };

pub fn install(engine: *em.Engine, prototype: c.JSValue, executor: c.JSValue, local_operations: c.JSValue) !void {
    if (!c.JS_IsFunction(engine.context, executor) or !c.JS_IsFunction(engine.context, local_operations)) return error.RequiredSharedNativeUserBashBindings;
    try installMethod(engine, prototype, .executeBash, &.{ executor, local_operations });
    try installRecord(engine, prototype);
}
pub fn installRecord(engine: *em.Engine, prototype: c.JSValue) !void {
    try installMethod(engine, prototype, .recordBashResult, &.{});
}
fn installMethod(engine: *em.Engine, prototype: c.JSValue, comptime method: Method, roots: []const c.JSValue) !void {
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, @tagName(method), 3, @intFromEnum(method), @intCast(roots.len), @constCast(roots.ptr)));
    defer engine.freeValue(function);
    if (method == .executeBash) {
        const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
        defer engine.freeValue(parent);
        if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    }
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, @tagName(method), c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn optional(scope: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(value)) c.pi_js_undefined() else scope.get(value, name);
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return (switch (@as(Method, @enumFromInt(magic))) {
        .recordBashResult => record(engine, session, argument(args, 0), argument(args, 1), argument(args, 2)),
        .executeBash => execute(engine, session, args, roots[0], roots[1]),
    }) catch |err| sdk.fail(engine, err);
}
pub fn record(engine: *em.Engine, session: c.JSValue, command: c.JSValue, result: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const message = try scope.object();
    try scope.put(message, "role", try scope.text("bashExecution"));
    try scope.put(message, "command", command);
    inline for (.{ "output", "exitCode", "cancelled", "truncated", "fullOutputPath" }) |name| try scope.put(message, name, try scope.get(result, name));
    try scope.put(message, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    try scope.put(message, "excludeFromContext", try optional(&scope, options, "excludeFromContext"));
    if (scope.truthy(try scope.get(session, "isStreaming"))) {
        _ = try scope.invoke(try scope.get(session, "_pendingBashMessages"), "push", &.{message});
    } else {
        _ = try scope.invoke(try scope.get(session, "sessionManager"), "appendMessage", &.{message});
        _ = try scope.invoke(session, "_refreshFinalizedContext", &.{});
    }
    return c.pi_js_undefined();
}
fn execute(engine: *em.Engine, session: c.JSValue, args: []const c.JSValue, executor: c.JSValue, local_operations: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, args, executor, local_operations) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, args: []const c.JSValue, executor: c.JSValue, local_operations: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const controller = try scope.own(try js.builtin(engine, "AbortController", &.{}));
    _ = try scope.invoke(try scope.get(session, "_bashAbortControllers"), "add", &.{controller});
    try scope.put(owner, "controller", controller);
    try scope.put(owner, "command", argument(args, 0));
    try scope.put(owner, "onChunk", argument(args, 1));
    try scope.put(owner, "options", argument(args, 2));
    const prefix = try scope.invoke(try scope.get(session, "settingsManager"), "getShellCommandPrefix", &.{});
    const shell_path = try scope.invoke(try scope.get(session, "settingsManager"), "getShellPath", &.{});
    const command = if (scope.truthy(prefix)) try scope.concat(try scope.concat(try scope.stringify(prefix), try scope.text("\n")), try scope.stringify(argument(args, 0))) else argument(args, 0);
    beginTry(engine, owner, command, shell_path, executor, local_operations) catch |err| {
        const reason = flow.reason(engine, err);
        defer engine.freeValue(reason);
        return finish(engine, owner, reason, true, 0);
    };
}
fn beginTry(engine: *em.Engine, owner: c.JSValue, command: c.JSValue, shell_path: c.JSValue, executor: c.JSValue, local_operations: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const cwd = try scope.invoke(try scope.get(session, "sessionManager"), "getCwd", &.{});
    const supplied = try optional(&scope, try scope.get(owner, "options"), "operations");
    const operations = if (!temp.nullish(supplied)) supplied else local: {
        const config = try scope.object();
        try scope.put(config, "shellPath", shell_path);
        break :local try scope.call(local_operations, c.pi_js_undefined(), &.{config});
    };
    const execution_options = try scope.object();
    var roots = [_]c.JSValue{owner};
    try scope.put(execution_options, "onChunk", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, chunk, "onChunk", 1, 0, roots.len, &roots))));
    try scope.put(execution_options, "signal", try scope.get(try scope.get(owner, "controller"), "signal"));
    const result = try scope.call(executor, c.pi_js_undefined(), &.{ command, cwd, operations, execution_options });
    try flow.wait(finish, engine, owner, result, 0);
}
fn chunk(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return chunkValue(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn chunkValue(engine: *em.Engine, owner: c.JSValue, delta: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const callback = try scope.get(owner, "onChunk");
    if (!temp.nullish(callback)) _ = try scope.call(callback, c.pi_js_undefined(), &.{delta});
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("bash_execution_update"));
    try scope.put(event, "id", try optional(&scope, try scope.get(owner, "options"), "id"));
    try scope.put(event, "delta", delta);
    _ = try scope.invoke(try scope.get(owner, "agent"), "_emit", &.{event});
    return c.pi_js_undefined();
}
fn finish(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    var failure = rejected;
    var settled = try scope.own(c.JS_DupValue(engine.context, value));
    if (!failure) {
        _ = scope.invoke(session, "recordBashResult", &.{ try scope.get(owner, "command"), value, try scope.get(owner, "options") }) catch |err| failed_record: {
            failure = true;
            settled = try scope.own(flow.reason(engine, err));
            break :failed_record c.pi_js_undefined();
        };
    }
    // A throwing finally replaces the pending return or original rejection.
    _ = try scope.invoke(try scope.get(session, "_bashAbortControllers"), "delete", &.{try scope.get(owner, "controller")});
    try flow.settle(engine, owner, failure, settled);
}
