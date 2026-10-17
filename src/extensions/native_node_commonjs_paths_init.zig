// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node24.14.0 Module._initPaths body. Private paths and public clone
//! intentionally have distinct identities. No environment value is logged.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
pub const Inputs = struct {
    module_constructor: c.JSValue,
    path: c.JSValue,
    process: c.JSValue,
    state: c.JSValue,
    /// Genuine native safeGetenv on POSIX; never needed on Windows.
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
pub fn initialize(engine: *v.em.Engine, inputs: Inputs) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const home = if (inputs.windows) try s.get(try s.get(inputs.process, "env"), "USERPROFILE") else
        try s.call(inputs.safe_getenv, c.pi_js_undefined(), &.{try s.text("HOME")});
    const node_path = if (inputs.windows) try s.get(try s.get(inputs.process, "env"), "NODE_PATH") else
        try s.call(inputs.safe_getenv, c.pi_js_undefined(), &.{try s.text("NODE_PATH")});
    const resolve = try s.get(inputs.path, "resolve");
    const executable = try s.get(inputs.process, "execPath");
    const prefix = if (inputs.windows) try s.call(resolve, inputs.path, &.{ executable, try s.text("..") }) else
        try s.call(resolve, inputs.path, &.{ executable, try s.text(".."), try s.text("..") });
    const initial_resolve = try s.get(inputs.path, "resolve");
    const paths = try s.array();
    try s.index(paths, 0, try s.call(initial_resolve, inputs.path, &.{ prefix, try s.text("lib"), try s.text("node") }));
    if (s.truthy(home)) {
        const libraries_resolve = try s.get(inputs.path, "resolve");
        _ = try s.call(inputs.array_unshift, paths, &.{try s.call(libraries_resolve, inputs.path, &.{ home, try s.text(".node_libraries") })});
        const modules_resolve = try s.get(inputs.path, "resolve");
        _ = try s.call(inputs.array_unshift, paths, &.{try s.call(modules_resolve, inputs.path, &.{ home, try s.text(".node_modules") })});
    }
    if (s.truthy(node_path)) {
        const split = try s.call(inputs.string_split, node_path, &.{try s.get(inputs.path, "delimiter")});
        const filtered = try s.call(inputs.array_filter, split, &.{inputs.boolean});
        _ = try s.call(inputs.reflect_apply, c.pi_js_undefined(), &.{ inputs.array_unshift, paths, filtered });
    }
    try s.set(inputs.state, "modulePaths", paths);
    // Assignment order matters if a guest later installs a setter here:
    // replacing the private lexical paths precedes assigning its public copy.
    try s.set(inputs.module_constructor, "globalPaths", try s.call(inputs.array_slice, paths, &.{}));
}
