// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node24 helpers.js makeRequireFunction. These are ordinary functions
//! over a genuine Module parent, never aliases to an unrelated hidden require.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const functions = @import("native_node_module_callable.zig");
pub const Inputs = struct {
    module_constructor: c.JSValue,
    process: c.JSValue,
    invalid_arg_type: c.JSValue,
};
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn invalidArgumentType(engine: *v.em.Engine, constructor: c.JSValue, name: []const u8, expected: []const u8, actual: c.JSValue) anyerror {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    var arguments = [_]c.JSValue{ s.text(name) catch |err| return err, s.text(expected) catch |err| return err, actual };
    const reason = s.own(engine.checked(c.JS_CallConstructor(engine.context, constructor, arguments.len, &arguments)) catch |err| return err) catch |err| return err;
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch |err| return err;
    unreachable;
}
pub fn create(engine: *v.em.Engine, inputs: Inputs, parent: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const instance = c.JS_IsInstanceOf(engine.context, parent, inputs.module_constructor);
    if (instance < 0) return v.js.capture(engine);
    if (instance != 1) return invalidArgumentType(engine, inputs.invalid_arg_type, "mod", "Module", parent);
    const values = [_]c.JSValue{ inputs.module_constructor, inputs.process, inputs.invalid_arg_type, parent };
    const require = try s.own(try functions.create(engine, "require", 1, true, requireCallback, &values));
    const resolve = try s.own(try functions.create(engine, "resolve", 2, true, resolveCallback, &values));
    try s.set(require, "resolve", resolve);
    const paths = try s.own(try functions.create(engine, "paths", 1, true, pathsCallback, &values));
    try s.set(resolve, "paths", paths);
    try s.put(require, "main", try s.get(inputs.process, "mainModule"));
    try s.set(require, "extensions", try s.get(inputs.module_constructor, "_extensions"));
    try s.set(require, "cache", try s.get(inputs.module_constructor, "_cache"));
    return c.JS_DupValue(engine.context, require);
}
fn requireCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const parent = values[3];
    const function = try s.get(parent, "require");
    return v.js.call(engine, function, parent, &.{arg(args, 0)});
}
fn resolveCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const request = arg(args, 0);
    if (!c.JS_IsString(request)) return invalidArgumentType(engine, values[2], "request", "string", request);
    const function = try s.get(values[0], "_resolveFilename");
    return v.js.call(engine, function, values[0], &.{ request, values[3], c.pi_js_bool(engine.context, 0), arg(args, 1) });
}
fn pathsCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const request = arg(args, 0);
    if (!c.JS_IsString(request)) return invalidArgumentType(engine, values[2], "request", "string", request);
    const function = try s.get(values[0], "_resolveLookupPaths");
    return v.js.call(engine, function, values[0], &.{ request, values[3] });
}
