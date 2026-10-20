//! Genuine bootstrap of the shared Module constructor and createRequire
//! declarations. Remaining loader members are linked by the full CommonJS
//! assembler before it publishes node:module.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const constructors = @import("native_node_module_constructor.zig");
const creation = @import("native_node_commonjs_create_require.zig");
const options = @import("native_node_options.zig");
const publication = @import("native_node_fs_private_publication.zig");
const key = "pi-native:private/commonjs-module-core";
pub fn create(engine: *a.v.em.Engine) !c.JSValue {
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
fn adopt(s: *Scope, values: []c.JSValue) !void {
    for (values, 0..) |*slot, position| {
        const incoming = slot.*;
        slot.* = c.pi_js_undefined();
        _ = s.own(incoming) catch |err| {
            // own() has already recorded typed producer failure. Remaining
            // incoming roots retire only after that current outcome exists.
            for (values[position + 1 ..]) |*remaining| s.boundary.release(remaining);
            return err;
        };
    }
}
fn createBody(s: *Scope) !c.JSValue {
    try s.pending();
    if (s.engine.native_module_values.get(key)) |known| return a.duplicate(s.engine, known);
    // Both default values come from the actual built-in registry, never its
    // ESM snapshot record. Process/Stream must be installed by host startup.
    const process = try s.own((try s.engine.requireBuiltin("node:process")) orelse return error.ActualModuleProcessRequired);
    if (!s.engine.native_module_values.contains("node:path"))
        try @import("node_path.zig").install(s.engine, s.engine.native_io orelse return error.ActualModuleIoRequired);
    const paths = try s.own((try s.engine.requireBuiltin("node:path")) orelse return error.ActualModulePathsRequired);
    const prepared = try @import("native_node_argument_bootstrap.zig").prepare(s.engine);
    var original_inputs = [_]c.JSValue{
        prepared.internal_inspect, prepared.assert_function,
        prepared.arguments.invalid_arg_type, prepared.arguments.hidden_invalid_arg_type,
        prepared.arguments.invalid_arg_value, prepared.arguments.internal_assertion,
        prepared.arguments.validate_string,
    };
    try adopt(s, &original_inputs);
    const url_owner = try s.own(try @import("native_node_file_url_paths.zig").acquire(s.engine));
    const ends_with = try s.own(try @import("native_node_argument_errors.zig").stringEndsWith(s.engine));
    const create_require = try s.own(try creation.create(s.engine, .{
        .paths = paths, .process = process, .url_owner = url_owner,
        .invalid_arg_type = prepared.arguments.invalid_arg_type,
        .invalid_arg_value = prepared.arguments.invalid_arg_value,
        .validate_string = prepared.arguments.validate_string,
        .string_ends_with = ends_with,
    }));
    // internal/util captures this real declaration from internal/options.
    // Its lazy dictionary stays in that completed owner; warning predicates
    // call it at their actual Source occurrence rather than freezing flags.
    const option_owner = try s.own(try options.acquire(s.engine));
    const get_option_value = try s.get(option_owner, "getOptionValue");
    const graph = try constructors.create(s.engine, .{
        .paths = paths, .create_require = create_require, .process = process,
        .get_option_value = get_option_value,
    });
    var graph_values = [_]c.JSValue{ graph.module_constructor, graph.namespace_exports };
    try adopt(s, &graph_values);
    // A nested completed bootstrap wins by exact identity. A separately
    // supplied historical constructor cannot silently become this owner.
    if (s.engine.native_module_values.get(key)) |known| return a.duplicate(s.engine, known);
    if (!s.equal(try s.get(graph.module_constructor, "createRequire"), create_require))
        return error.DifferentActualModuleCreateRequireOwner;
    return a.duplicate(s.engine, graph.module_constructor);
}
