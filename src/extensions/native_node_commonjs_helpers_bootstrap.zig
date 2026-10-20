//! Genuine selected CommonJS helper graph. The original Module bootstrap
//! retains the primordial imports before guest execution; this owner binds
//! those exact values to the real filesystem and options declarations.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const core = @import("native_node_commonjs_module_core.zig");
const modules = @import("native_node_module_constructor.zig");
const helpers = @import("native_node_commonjs_helpers.zig");
const publication = @import("native_node_fs_private_publication.zig");
const key = "pi-native:private/commonjs-helpers";

pub fn acquire(engine: *a.v.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |known| return a.duplicate(engine, known);
    const candidate = try a.expression(engine, createBody, .{});
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, key, candidate);
}
fn adopt(s: *a.Scope, values: []c.JSValue) !void {
    for (values, 0..) |*slot, position| {
        const incoming = slot.*;
        slot.* = c.pi_js_undefined();
        _ = s.own(incoming) catch |err| {
            // own records any typed allocation failure before later returned
            // roots are retired under the same first-failure boundary.
            for (values[position + 1 ..]) |*remaining| s.boundary.release(remaining);
            return err;
        };
    }
}
fn requiredFunction(s: *a.Scope, owner: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const value = try s.get(owner, name);
    if (!c.JS_IsFunction(s.engine.context, value)) return error.ActualCommonJSHelperImportRequired;
    return value;
}
fn createBody(s: *a.Scope) !c.JSValue {
    try s.pending();
    if (s.engine.native_module_values.get(key)) |known| return a.duplicate(s.engine, known);
    const constructor = try s.own(try core.create(s.engine));
    const lexical = try s.own(try modules.loaderEnvironment(s.engine, constructor));
    // helpers.js imports all of fs so its live realpathSync remains patchable.
    // The startup assembler must have installed the actual FS/Stream graph.
    const filesystem = try s.own((try s.engine.requireBuiltin("node:fs")) orelse return error.ActualCommonJSHelperFilesystemRequired);
    const internal_fs = try s.own(try @import("native_node_fs_path_bootstrap.zig").prepare(s.engine));
    const actual = try helpers.create(s.engine, .{
        .filesystem = filesystem,
        .internal_fs = internal_fs,
        .safe_map = try requiredFunction(s, lexical, "safeMap"),
        .safe_set = try requiredFunction(s, lexical, "safeSet"),
        .get_option_value = try requiredFunction(s, lexical, "getOptionValue"),
        .object_freeze = try requiredFunction(s, lexical, "objectFreeze"),
    });
    var outputs = [_]c.JSValue{
        actual.to_real_path, actual.initialize_conditions,
        actual.get_conditions, actual.get_conditions_array,
    };
    try adopt(s, &outputs);
    const exports = try s.objectProto(c.pi_js_null());
    try s.put(exports, "toRealPath", actual.to_real_path);
    try s.put(exports, "initializeCjsConditions", actual.initialize_conditions);
    try s.put(exports, "getCjsConditions", actual.get_conditions);
    try s.put(exports, "getCjsConditionsArray", actual.get_conditions_array);
    return a.duplicate(s.engine, exports);
}
