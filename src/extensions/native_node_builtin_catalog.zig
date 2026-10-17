// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node24 builtin identity policy over its exact original ordered id table.
//! ids is authority data from pinned Node, never engine.native_module_names.
//! Original Node24 data is admitted separately; generic create still accepts
//! explicit authority data and never reads the registry of implemented modules.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub const Catalog = struct {
    /// Actual frozen public builtinModules array, owned by caller.
    builtin_modules: c.JSValue,
    /// Predicate using the captured authority list. Generic create uses a
    /// private anonymous declaration; createOriginalNode24 supplies the
    /// observed public Module.isBuiltin name/length/nonconstructor shape.
    is_builtin: c.JSValue,
};
pub fn create(engine: *v.em.Engine, ids: []const []const u8) !Catalog {
    return createNamed(engine, ids, "");
}
/// Exact original v24.14.0 data, retaining its 72-item order. The genuine
/// nonconstructible public isBuiltin shape was observed in the same capture.
pub fn createOriginalNode24(engine: *v.em.Engine) !Catalog {
    return createNamed(engine, &@import("native_node_builtin_node24_data.zig").ids, "isBuiltin");
}
/// Future authority refreshes must present the exact version before reusing
/// this data. This does not add or spoof process.version/versions.node.
pub fn requireOriginalNodeVersion(actual: []const u8) !void {
    if (!std.mem.eql(u8, actual, @import("native_node_builtin_node24_data.zig").node_version)) return error.OriginalNodeBuiltinVersionMismatch;
}
fn createNamed(engine: *v.em.Engine, ids: []const []const u8, name: [*:0]const u8) !Catalog {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const list = try s.array();
    for (ids, 0..) |id, index| {
        if (index > std.math.maxInt(u32)) return error.NodeBuiltinCatalogTooLarge;
        try s.index(list, @intCast(index), try s.text(id));
    }
    if (c.JS_FreezeObject(engine.context, list) < 0) return v.js.capture(engine);
    const predicate = try s.own(try @import("native_node_module_callable.zig").create(engine, name, 1, false, classify, &.{list}));
    return .{ .builtin_modules = c.JS_DupValue(engine.context, list), .is_builtin = c.JS_DupValue(engine.context, predicate) };
}
fn classify(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (args.len == 0 or !c.JS_IsString(args[0])) return c.pi_js_bool(engine.context, 0);
    const requested = try engine.toString(args[0]); defer engine.gpa.free(requested);
    const prefixed = std.mem.startsWith(u8, requested, "node:");
    const raw = if (prefixed) requested[5..] else requested;
    // Remove exactly one prefix. Prefix-only ids in builtinModules still have
    // their node: spelling and must never become an unprefixed alias.
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var length: u32 = 0;
    if (c.JS_ToUint32(engine.context, &length, try s.get(roots[0], "length")) < 0) return v.js.capture(engine);
    for (0..length) |index| {
        const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, roots[0], @intCast(index)));
        defer engine.freeValue(item);
        const id = try engine.toString(item); defer engine.gpa.free(id);
        const match = if (std.mem.startsWith(u8, id, "node:"))
            prefixed and std.mem.eql(u8, requested, id)
        else std.mem.eql(u8, raw, id);
        if (match) return c.pi_js_bool(engine.context, 1);
    }
    return c.pi_js_bool(engine.context, 0);
}
