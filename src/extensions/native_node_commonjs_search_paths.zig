//! Genuine linkage of Module's search-path declarations. The completed private
//! record uses the existing Module, its original primordials and its one lexical
//! modulePaths cell. Full node:module publication belongs to the loader graph.
const builtin = @import("builtin");
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const core = @import("native_node_commonjs_module_core.zig");
const constructor = @import("native_node_module_constructor.zig");
const lookup = @import("native_node_commonjs_lookup.zig");
const initialize = @import("native_node_commonjs_paths_init.zig");
const functions = @import("native_node_module_callable.zig");
const publication = @import("native_node_fs_private_publication.zig");
const errors = @import("native_node_argument_errors.zig");
const key = "pi-native:private/commonjs-search-paths";
pub const Inputs = struct {
    /// Real internal credentials binding on POSIX. The actual Windows Source
    /// branch uses process.env and has no safeGetenv call.
    safe_getenv: ?c.JSValue = null,
};
pub fn acquire(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |cached| return a.duplicate(engine, cached);
    const candidate = try a.expression(engine, createBody, .{inputs});
    if (engine.native_module_values.get(key)) |cached| {
        var selected = a.owned.Completion.initValue(engine, a.duplicate(engine, cached));
        selected.release(candidate);
        return selected.finishValue();
    }
    return publication.publish(engine, key, candidate);
}
fn define(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    return s.define(target, name, value, c.JS_PROP_C_W_E);
}
fn adoptErrors(s: *Scope, input: errors.Exports) !void {
    var values: [std.meta.fields(errors.Exports).len]c.JSValue = undefined;
    inline for (std.meta.fields(errors.Exports), 0..) |field, position| values[position] = @field(input, field.name);
    for (&values, 0..) |*slot, position| {
        const incoming = slot.*; slot.* = c.pi_js_undefined();
        _ = s.own(incoming) catch |err| {
            for (values[position + 1 ..]) |*remaining| s.boundary.release(remaining);
            return err;
        };
    }
}
fn assign(s: *Scope, module: c.JSValue, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    try s.put(module, name, value);
    return c.pi_js_undefined();
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    const windows = builtin.os.tag == .windows;
    if (!windows and inputs.safe_getenv == null) return error.ActualCredentialSafeGetenvRequired;
    const module = try s.own(try core.create(s.engine));
    const owner = try s.own(try constructor.loaderEnvironment(s.engine, module));
    const argument = (try errors.acquire(s.engine)) orelse return error.ActualModuleArgumentOwnerRequired;
    try adoptErrors(s, argument);
    const path = try s.get(owner, "paths");
    const process = try s.get(owner, "process");
    const normalize = try s.own(try @import("native_node_builtin_normalize.zig").create(s.engine, .{
        .string_starts_with = try s.get(owner, "stringStartsWith"),
        .string_slice = try s.get(owner, "stringSlice"),
    }));
    const lookup_function = try s.own(try lookup.createLookupPaths(s.engine, .{
        .module_constructor = module, .path = path, .state = owner, .is_builtin = normalize,
        .array_slice = try s.get(owner, "arraySlice"), .array_unshift = try s.get(owner, "arrayUnshift"),
        .array_push = try s.get(owner, "arrayPush"), .array_includes = try s.get(owner, "arrayIncludes"),
        .array_is_array = try s.get(owner, "arrayIsArray"), .reflect_apply = try s.get(owner, "reflectApply"),
        .invalid_arg_value = argument.invalid_arg_value, .string_char_at = try s.get(owner, "stringCharAt"),
        .string_starts_with = try s.get(owner, "stringStartsWith"), .string_char_code_at = try s.get(owner, "charCodeAt"),
        .windows = windows,
    }));
    const init_function = try s.own(try initialize.create(s.engine, .{
        .module_constructor = module, .path = path, .process = process, .state = owner,
        .safe_getenv = inputs.safe_getenv orelse c.pi_js_undefined(),
        .array_unshift = try s.get(owner, "arrayUnshift"), .array_slice = try s.get(owner, "arraySlice"),
        .array_filter = try s.get(owner, "arrayFilter"), .string_split = try s.get(owner, "stringSplit"),
        .boolean = try s.get(owner, "boolean"), .reflect_apply = try s.get(owner, "reflectApply"), .windows = windows,
    }));
    const record = try s.objectProto(c.pi_js_null());
    try define(s, record, "Module", module);
    try define(s, record, "owner", owner);
    try define(s, record, "normalizeRequirableId", normalize);
    try define(s, record, "_resolveLookupPaths", lookup_function);
    try define(s, record, "_initPaths", init_function);

    // Every Source assignment finishes before the next one. These fields are
    // linked only to the known private Module; no public ESM/CJS facade is made.
    _ = try a.expression(s.engine, assign, .{module, @as([*:0]const u8, "_resolveLookupPaths"), lookup_function});
    _ = try a.expression(s.engine, assign, .{module, @as([*:0]const u8, "_initPaths"), init_function});
    var ignored = try a.call(s.engine, init_function, module, &.{});
    s.boundary.release(&ignored);
    try s.pending();
    return a.duplicate(s.engine, record);
}
fn known(s: *Scope, record: c.JSValue) !void {
    const actual = s.engine.native_module_values.get(key) orelse return error.ActualSearchPathOwnerNotReady;
    if (!s.equal(actual, record)) return error.DifferentActualSearchPathOwner;
    const module = try s.get(record, "Module");
    const expected = try s.own(try constructor.actualConstructor(s.engine));
    if (!s.equal(module, expected)) return error.DifferentActualSearchPathModule;
}
/// Borrowed values are retained by the completed private record until Engine
/// teardown. A new callable adopts them through its normal copied-root API.
pub fn lookupInputs(engine: *a.v.em.Engine, record: c.JSValue) !lookup.Inputs {
    var s = Scope.init(engine);
    var result: lookup.Inputs = undefined;
    const outcome: anyerror!c.JSValue = body: {
        known(&s, record) catch |err| break :body err;
        const function = s.get(record, "_resolveLookupPaths") catch |err| break :body err;
        const captured = functions.capturedRoots(engine, function) catch |err| break :body err;
        if (captured.len != lookup.captured_root_count) break :body error.ActualLookupRootShapeRequired;
        result = lookup.restoreRoots(engine, captured);
        break :body c.pi_js_undefined();
    };
    _ = try s.finish(outcome);
    return result;
}
