//! Concrete canonical/identity/compatibility functions for private Host ownership.
const js = @import("native_js_values.zig");
const c = js.c;
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn invoke(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var operation: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &operation, values[0]) < 0) return js.capture(engine);
    return switch (operation) {
        0 => @import("native_chord_canonical.zig").canonicalJson(engine, arg(args, 0)),
        1 => @import("native_chord_canonical.zig").hash64(engine, arg(args, 0)),
        2 => c.pi_js_bool(engine.context, @intFromBool(try @import("native_chord_canonical.zig").deepEqual(engine, arg(args, 0), arg(args, 1)))),
        3 => c.pi_js_bool(engine.context, @intFromBool(try @import("native_chord_fits.zig").fits(engine, arg(args, 0), arg(args, 1)))),
        else => @import("native_chord_identity.zig").canonicalIdentity(engine, arg(args, 0), arg(args, 1)),
    };
}
pub fn exports(engine: *js.Engine) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ .{ "canonicalJson", 1 }, .{ "hash64", 1 }, .{ "deepEqual", 2 }, .{ "fits", 2 }, .{ "canonicalIdentity", 2 } }, 0..) |entry, operation| {
        try js.define(engine, result, entry[0], try @import("native_node_function.zig").create(engine, entry[0], entry[1], invoke, &.{c.JS_NewInt32(engine.context, @intCast(operation))}));
    }
    return result;
}
