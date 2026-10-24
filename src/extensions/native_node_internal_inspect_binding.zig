//! One private binding record for the actual consumed internal/util/inspect
//! functions. It is not registered as the public node:util namespace. Public
//! exotic/layout profiles retain the explicit gates in the real formatter.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const inspect = @import("native_node_util_inspect.zig");
const publication = @import("native_node_fs_private_publication.zig");
const key = "pi-native:private/internal-inspect-binding";

fn adopt(s: *a.Scope, value: anytype) !void {
    const T = @TypeOf(value);
    var values: [std.meta.fields(T).len]c.JSValue = undefined;
    inline for (std.meta.fields(T), 0..) |field, position| values[position] = @field(value, field.name);
    for (&values, 0..) |*slot, position| {
        const moved = slot.*; slot.* = c.pi_js_undefined();
        _ = s.own(moved) catch |err| {
            for (values[position + 1 ..]) |*remaining| s.boundary.release(remaining);
            return err;
        };
    }
}
/// The genuine Node bootstrap calls this before guest extension execution.
/// Later consumers acquire this same record and the same live field identities.
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
fn createBody(s: *a.Scope) !c.JSValue {
    const inputs = try inspect.capturePrimordials(s.engine);
    try adopt(s, inputs);
    const functions = try inspect.create(s.engine, inputs);
    try adopt(s, functions);
    // This is the real receiver retained by lazyInternalUtilInspect().inspect.
    // Its function values come directly from the accepted native factory.
    const record = try s.object();
    try s.put(record, "inspect", functions.inspect);
    try s.put(record, "format", functions.format);
    try s.put(record, "formatWithOptions", functions.format_with_options);
    return a.duplicate(s.engine, record);
}
