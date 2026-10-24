// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual loader.js watch-dependency reporters and their shared getLazy cell.
//! The canonical Module supplies the real process/path and captured ArrayMap.
//! No transport, public Module, or default application backend is installed.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const modules = @import("native_node_module_constructor.zig");
const functions = @import("native_node_module_callable.zig");
const publication = @import("native_node_fs_private_publication.zig");
const key = "pi-native:private/commonjs-watch-reporting";

/// Validate the actual shared Module even on an already-cached acquisition.
/// Both _load and _findPath retain the same completed private declarations.
pub fn acquire(engine: *a.v.em.Engine, module: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    const candidate = try a.expression(engine, createBody, .{module});
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, key, candidate);
}
fn createBody(s: *Scope, module: c.JSValue) !c.JSValue {
    const lexical = try s.own(try modules.loaderEnvironment(s.engine, module));
    if (s.engine.native_module_values.get(key)) |known| return a.duplicate(s.engine, known);
    const process = try s.get(lexical, "process");
    const paths = try s.get(lexical, "paths");
    const map = try s.get(lexical, "arrayMap");
    if (!c.JS_IsObject(process) or !c.JS_IsObject(paths) or
        !c.JS_IsFunction(s.engine.context, map)) return error.ActualCommonJSWatchInputsRequired;
    const state = try s.objectProto(c.pi_js_null());
    try s.put(state, "process", process);
    try s.put(state, "paths", paths);
    try s.put(state, "arrayMap", map);
    try s.put(state, "initialized", a.boolean(s, false));
    try s.put(state, "value", c.pi_js_undefined());
    const result = try s.objectProto(c.pi_js_null());
    try s.put(result, "reportModuleToWatchMode",
        try s.own(try functions.create(s.engine, "reportModuleToWatchMode", 1, true,
            reportRequired, &.{state})));
    try s.put(result, "reportModuleNotFoundToWatchMode",
        try s.own(try functions.create(s.engine, "reportModuleNotFoundToWatchMode", 2, true,
            reportMissing, &.{state})));
    return a.duplicate(s.engine, result);
}
fn environmentValue(s: *Scope, process: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.get(try s.get(process, "env"), "WATCH_REPORT_DEPENDENCIES"));
}
fn enabled(s: *Scope, state: c.JSValue) !c.JSValue {
    // internal/util.getLazy sets initialized only after the initializer returns.
    // An abrupt first read retries. Reentrant completion is not rolled back or
    // treated as a winner: a later successful outer assignment replaces it.
    if (s.equal(try s.get(state, "initialized"), a.boolean(s, false))) {
        const value = try s.own(try a.expression(s.engine, environmentValue,
            .{try s.get(state, "process")}));
        try s.put(state, "value", value);
        try s.put(state, "initialized", a.boolean(s, true));
    }
    return a.boolean(s, s.truthy(try s.get(state, "value")));
}
fn reportRequired(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, requiredBody, .{roots[0], a.arg(args, 0)});
}
fn requiredBody(s: *Scope, state: c.JSValue, filename: c.JSValue) !c.JSValue {
    if (!try a.condition(s.engine, enabled, .{state})) return c.pi_js_undefined();
    const process = try s.get(state, "process");
    if (!try a.condition(s.engine, a.fieldTruthy,
        .{process, @as([*:0]const u8, "send")})) return c.pi_js_undefined();
    // Source reads process.send again as the callee, before its object/array
    // argument. Object literal fields and array elements are definitions.
    const send = try s.get(process, "send");
    const record = try s.object();
    const files = try a.array(s);
    try a.index(s, files, 0, filename);
    try s.define(record, "watch:require", files, c.JS_PROP_C_W_E);
    _ = try s.call(send, process, &.{record});
    return c.pi_js_undefined();
}
fn reportMissing(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, missingBody, .{roots[0], a.arg(args, 0), a.arg(args, 1)});
}
fn missingBody(s: *Scope, state: c.JSValue, base_path: c.JSValue,
    extensions: c.JSValue) !c.JSValue
{
    if (!try a.condition(s.engine, enabled, .{state})) return c.pi_js_undefined();
    const process = try s.get(state, "process");
    if (!try a.condition(s.engine, a.fieldTruthy,
        .{process, @as([*:0]const u8, "send")})) return c.pi_js_undefined();
    const send = try s.get(process, "send");
    const record = try s.object();
    const paths = try s.get(state, "paths");
    // Use the actual captured ArrayPrototypeMap, including length/Has/Get,
    // holes, inherited elements, species construction, and abrupt completion.
    const mapper = try s.own(try functions.create(s.engine, "", 1, false,
        resolveExtension, &.{paths, base_path}));
    const mapped = try s.call(try s.get(state, "arrayMap"), extensions, &.{mapper});
    try s.define(record, "watch:require", mapped, c.JS_PROP_C_W_E);
    _ = try s.call(send, process, &.{record});
    return c.pi_js_undefined();
}
fn resolveExtension(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, resolveBody, .{roots[0], roots[1], a.arg(args, 0)});
}
fn resolveBody(s: *Scope, paths: c.JSValue, base_path: c.JSValue,
    extension: c.JSValue) !c.JSValue
{
    // Preserve path.resolve callee lookup before each template substitution,
    // and both independent ToString operations at every visited map element.
    const resolve = try s.get(paths, "resolve");
    const base = try s.toString(base_path);
    const suffix = try s.toString(extension);
    const filename = try a.add(s, base, suffix);
    return a.duplicate(s.engine, try s.call(resolve, paths, &.{filename}));
}
