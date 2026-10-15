//! Native local Bash operations shared by the ordinary session executor.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
pub fn create(engine: *em.Engine) !c.JSValue {
    const bindings = try @import("native_env_values.zig").exports(engine);
    defer engine.freeValue(bindings);
    var roots = [_]c.JSValue{bindings};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, factory, "createLocalBashOperations", 1, 0, roots.len, &roots));
}
fn factory(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return factoryValue(&scope, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn factoryValue(scope: *Scope, options: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const result = try scope.object();
    var roots = [_]c.JSValue{ options, bindings };
    try scope.put(result, "exec", try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, exec, "exec", 3, 0, roots.len, &roots))));
    return c.JS_DupValue(scope.engine.context, result);
}
fn arg(args: []const c.JSValue, i: usize) c.JSValue {
    return if (i < args.len) args[i] else c.pi_js_undefined();
}
fn raise(scope: *Scope, message: c.JSValue) anyerror {
    const reason = scope.own(js.builtin(scope.engine, "Error", &.{message}) catch |err| return err) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason))) catch |err| return err;
    unreachable;
}
fn shellEnv(scope: *Scope) !c.JSValue {
    const environment = try scope.get(try scope.global("process"), "env");
    const keys = try scope.invoke(try scope.global("Object"), "keys", &.{environment});
    var path_key = try scope.text("PATH");
    for (0..try sdk.length(scope.engine, keys)) |i| {
        const key = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, keys, @intCast(i))));
        if (scope.equal(try scope.invoke(key, "toLowerCase", &.{}), try scope.text("path"))) {
            path_key = key;
            break;
        }
    }
    const current = try scope.own(try js.getKey(scope.engine, environment, path_key));
    const current_path = if (temp.nullish(current)) try scope.text("") else current;
    const agent_directory = try sdk.agentDir(scope.engine);
    defer scope.engine.gpa.free(agent_directory);
    const paths = @import("node_path.zig");
    const flavor: paths.Flavor = if (builtin.os.tag == .windows) .win32 else .posix;
    const bin = try paths.join(scope.engine.gpa, &.{ agent_directory, "bin" }, flavor);
    defer scope.engine.gpa.free(bin);
    const bin_value = try scope.text(bin);
    const delimiter = try scope.text(if (builtin.os.tag == .windows) ";" else ":");
    const entries = try scope.invoke(try scope.invoke(current_path, "split", &.{delimiter}), "filter", &.{try scope.global("Boolean")});
    const has_bin = scope.truthy(try scope.invoke(entries, "includes", &.{bin_value}));
    const values = try scope.array();
    try scope.index(values, 0, bin_value);
    try scope.index(values, 1, current_path);
    const updated = if (has_bin) current_path else try scope.invoke(try scope.invoke(values, "filter", &.{try scope.global("Boolean")}), "join", &.{delimiter});
    const result = try scope.own(try js.spread(scope.engine, environment));
    try js.setKey(scope.engine, result, path_key, updated);
    return result;
}
fn exec(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0], roots[1]) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, args: []const c.JSValue, factory_options: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, args, factory_options, bindings) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, args: []const c.JSValue, factory_options: c.JSValue, bindings: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const original_options = arg(args, 2);
    const on_data = try scope.get(original_options, "onData");
    const signal = try scope.get(original_options, "signal");
    const timeout = try scope.get(original_options, "timeout");
    const environment = try scope.get(original_options, "env");
    if (!c.JS_IsUndefined(timeout)) {
        if (!scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{timeout})) or !try scope.positive(timeout)) return raise(&scope, try scope.text("Invalid timeout: must be a finite number of seconds"));
        if (try @import("native_color.zig").number(engine, timeout) * 1000 > 2147483647) return raise(&scope, try scope.text("Invalid timeout: maximum is 2147483.647 seconds"));
    }
    if (!temp.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) return raise(&scope, try scope.text("aborted"));
    const shell_path = if (temp.nullish(factory_options)) c.pi_js_undefined() else try scope.get(factory_options, "shellPath");
    if (scope.truthy(shell_path)) {
        const text = try engine.toString(shell_path);
        defer engine.gpa.free(text);
        std.Io.Dir.cwd().access(engine.native_io orelse return error.NativeIoUnavailable, text, .{}) catch return raise(&scope, try scope.concat(try scope.text("Custom shell path not found: "), try scope.stringify(shell_path)));
    }
    const cwd = arg(args, 1);
    const cwd_text = try engine.toString(cwd);
    defer engine.gpa.free(cwd_text);
    std.Io.Dir.cwd().access(engine.native_io orelse return error.NativeIoUnavailable, cwd_text, .{}) catch return raise(&scope, try scope.concat(try scope.concat(try scope.text("Working directory does not exist: "), try scope.stringify(cwd)), try scope.text("\nCannot execute bash commands.")));
    try scope.put(owner, "onData", on_data);
    try scope.put(owner, "options", original_options);
    try scope.put(owner, "signal", signal);
    const receiver = try scope.object();
    try scope.put(receiver, "cwd", cwd);
    try scope.put(receiver, "shellPath", if (scope.truthy(shell_path)) shell_path else c.pi_js_undefined());
    const options = try scope.object();
    var roots = [_]c.JSValue{owner};
    try scope.put(options, "onData", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, output, "onData", 1, 0, roots.len, &roots))));
    try scope.put(options, "signal", signal);
    try scope.put(options, "timeout", timeout);
    try scope.put(options, "env", if (temp.nullish(environment)) try shellEnv(&scope) else environment);
    // The Env merge must not reintroduce variables omitted by the caller.
    try scope.put(options, "inheritEnv", c.pi_js_bool(engine.context, 0));
    const result = try scope.own(try @import("native_env_node_exec.zig").execWithMode(engine, receiver, &.{ arg(args, 0), options, c.pi_js_undefined() }, bindings, .raw));
    try flow.wait(done, engine, owner, result, 0);
}
fn output(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const callback = scope.get(roots[0], "onData") catch |err| return sdk.fail(engine, err);
    return js.call(engine, callback, c.pi_js_undefined(), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| {
        scope.put(roots[0], "callbackFailed", c.pi_js_bool(engine.context, 1)) catch |failure| return sdk.fail(engine, failure);
        return sdk.fail(engine, err);
    };
}
fn done(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected and !scope.truthy(try scope.get(owner, "callbackFailed"))) {
        const signal = try scope.get(owner, "signal");
        if (!temp.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) return raise(&scope, try scope.text("aborted"));
        // Internal native errors carry Source's timeout message. Expose ordinary
        // Error for the local Source adapter, preserving guest callback throws.
        const name = try scope.get(value, "name");
        if (scope.equal(name, try scope.text("ExecutionError"))) return raise(&scope, try scope.get(value, "message"));
    }
    try flow.settle(engine, owner, rejected, value);
}
