// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node v24.14 Module._initPaths. Its four Source locals outlive all
//! expressions; the private lexical assignment precedes the public clone.
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const Frame = a.frames.Frame(enum { home_dir, node_path, prefix_dir, paths });
pub const Inputs = struct {
    module_constructor: c.JSValue,
    path: c.JSValue,
    process: c.JSValue,
    state: c.JSValue,
    /// Genuine internal credentials.safeGetenv; the Windows branch never calls it.
    safe_getenv: c.JSValue,
    array_unshift: c.JSValue,
    array_slice: c.JSValue,
    array_filter: c.JSValue,
    string_split: c.JSValue,
    boolean: c.JSValue,
    reflect_apply: c.JSValue,
    windows: bool,
};
fn roots(engine: *v.em.Engine, inputs: Inputs) [12]c.JSValue {
    return .{ inputs.module_constructor, inputs.path, inputs.process, inputs.state, inputs.safe_getenv,
        inputs.array_unshift, inputs.array_slice, inputs.array_filter, inputs.string_split,
        inputs.boolean, inputs.reflect_apply, c.pi_js_bool(engine.context, @intFromBool(inputs.windows)) };
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    const values = roots(engine, inputs);
    return @import("native_node_module_callable.zig").create(engine, "", 0, true, callback, &values);
}
fn callback(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    try initialize(engine, .{ .module_constructor = values[0], .path = values[1], .process = values[2],
        .state = values[3], .safe_getenv = values[4], .array_unshift = values[5], .array_slice = values[6],
        .array_filter = values[7], .string_split = values[8], .boolean = values[9], .reflect_apply = values[10],
        .windows = c.JS_ToBool(engine.context, values[11]) == 1 });
    return c.pi_js_undefined();
}
fn statement(engine: *v.em.Engine, comptime body: anytype, args: anytype) !void {
    var s = Scope.init(engine);
    var failure: ?anyerror = null;
    @call(.auto, body, .{&s} ++ args) catch |err| { failure = err; };
    _ = try s.finish(if (failure) |err| @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
}
fn environment(s: *Scope, inputs: Inputs, home: bool) !c.JSValue {
    if (inputs.windows) {
        const env = try s.get(inputs.process, "env");
        return a.duplicate(s.engine, try s.get(env, if (home) "USERPROFILE" else "NODE_PATH"));
    }
    return a.duplicate(s.engine, try s.call(inputs.safe_getenv, c.pi_js_undefined(),
        &.{try s.text(if (home) "HOME" else "NODE_PATH")}));
}
fn prefix(s: *Scope, inputs: Inputs) !c.JSValue {
    const resolve = try s.get(inputs.path, "resolve");
    const executable = try s.get(inputs.process, "execPath");
    return a.duplicate(s.engine, if (inputs.windows)
        try s.call(resolve, inputs.path, &.{executable, try s.text("..")}) else
        try s.call(resolve, inputs.path, &.{executable, try s.text(".."), try s.text("..")}));
}
fn initialPath(s: *Scope, inputs: Inputs, prefix_dir: c.JSValue) !c.JSValue {
    const resolve = try s.get(inputs.path, "resolve");
    return a.duplicate(s.engine, try s.call(resolve, inputs.path, &.{prefix_dir, try s.text("lib"), try s.text("node")}));
}
fn initialPaths(s: *Scope, inputs: Inputs, prefix_dir: c.JSValue) !c.JSValue {
    const paths = try a.array(s);
    const value = try s.own(try a.expression(s.engine, initialPath, .{inputs, prefix_dir}));
    try a.index(s, paths, 0, value);
    return a.duplicate(s.engine, paths);
}
fn homePath(s: *Scope, inputs: Inputs, home: c.JSValue, suffix: []const u8) !c.JSValue {
    const resolve = try s.get(inputs.path, "resolve");
    return a.duplicate(s.engine, try s.call(resolve, inputs.path, &.{home, try s.text(suffix)}));
}
fn prependHome(s: *Scope, inputs: Inputs, paths: c.JSValue, home: c.JSValue, suffix: []const u8) !void {
    const path = try s.own(try a.expression(s.engine, homePath, .{inputs, home, suffix}));
    _ = try s.call(inputs.array_unshift, paths, &.{path});
}
fn splitNodePath(s: *Scope, inputs: Inputs, node_path: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(inputs.string_split, node_path, &.{try s.get(inputs.path, "delimiter")}));
}
fn filteredNodePaths(s: *Scope, inputs: Inputs, node_path: c.JSValue) !c.JSValue {
    const split = try s.own(try a.expression(s.engine, splitNodePath, .{inputs, node_path}));
    return a.duplicate(s.engine, try s.call(inputs.array_filter, split, &.{inputs.boolean}));
}
fn prependNodePath(s: *Scope, inputs: Inputs, paths: c.JSValue, node_path: c.JSValue) !void {
    const filtered = try s.own(try a.expression(s.engine, filteredNodePaths, .{inputs, node_path}));
    _ = try s.call(inputs.reflect_apply, c.pi_js_undefined(), &.{inputs.array_unshift, paths, filtered});
}
fn assignPrivate(s: *Scope, inputs: Inputs, paths: c.JSValue) !void {
    // state is the inaccessible genuine Module owner with an own data slot.
    // JS_SetProperty publishes before releasing the displaced lexical root.
    try s.put(inputs.state, "modulePaths", paths);
}
fn publicClone(s: *Scope, inputs: Inputs) !c.JSValue {
    return a.duplicate(s.engine, try s.call(inputs.array_slice, try s.get(inputs.state, "modulePaths"), &.{}));
}
fn assignPublic(s: *Scope, inputs: Inputs) !void {
    const copy = try s.own(try a.expression(s.engine, publicClone, .{inputs}));
    try s.put(inputs.module_constructor, "globalPaths", copy);
}
pub fn initialize(engine: *v.em.Engine, inputs: Inputs) !void {
    var s = Scope.init(engine);
    const frame = Frame.create(&s.values) catch |err| {
        _ = try s.finish(@as(anyerror!c.JSValue, err));
        unreachable;
    };
    _ = try a.finishFrame(&s, frame, body(&s, frame, inputs));
}
fn body(s: *Scope, frame: *Frame, inputs: Inputs) !c.JSValue {
    try frame.take(.home_dir, a.expression(s.engine, environment, .{inputs, true}));
    try frame.take(.node_path, a.expression(s.engine, environment, .{inputs, false}));
    try frame.take(.prefix_dir, a.expression(s.engine, prefix, .{inputs}));
    try frame.take(.paths, a.expression(s.engine, initialPaths, .{inputs, frame.get(.prefix_dir)}));
    if (s.truthy(frame.get(.home_dir))) {
        try statement(s.engine, prependHome, .{inputs, frame.get(.paths), frame.get(.home_dir), @as([]const u8, ".node_libraries")});
        try statement(s.engine, prependHome, .{inputs, frame.get(.paths), frame.get(.home_dir), @as([]const u8, ".node_modules")});
    }
    if (s.truthy(frame.get(.node_path)))
        try statement(s.engine, prependNodePath, .{inputs, frame.get(.paths), frame.get(.node_path)});
    try statement(s.engine, assignPrivate, .{inputs, frame.get(.paths)});
    try statement(s.engine, assignPublic, .{inputs});
    return c.pi_js_undefined();
}
