//! Actual highlight.js10.7.3 inherit(original,...objects) body.
//! Private Source-order enumerator prototype; Original24 remains an exact gate.
//! Historical VM-backed negative and separate unchanged guest VM ABI are retained.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const ordinary = @import("native_node_function.zig");
const enumeration = @import("native_source_for_in.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const c = em.c;

pub fn create(engine: *em.Engine) !c.JSValue {
    return ordinary.create(engine, "inherit", 1, call, &.{});
}
/// Isolated genuine-Original legacy-function diagnostic. Never selected by the
/// production compiler or ordinary helper until dedicated native qualification.
pub fn createLegacyPrototype(engine: *em.Engine) !c.JSValue {
    return @import("native_legacy_function.zig").create(engine, "inherit", 1, call, &.{});
}
fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.invoke(try scope.global("Object"), "create", &.{c.pi_js_null()});
    try copy(engine, result, if (args.len > 0) args[0] else c.pi_js_undefined());
    const objects = try scope.array();
    for (if (args.len > 1) args[1..] else &.{}, 0..) |value, index| try scope.index(objects, @intCast(index), value);
    const for_each = try scope.get(objects, "forEach");
    const callback = try scope.own(try ordinary.create(engine, "", 1, copyEach, &.{result}));
    _ = try scope.call(for_each, objects, &.{callback});
    return c.JS_DupValue(engine.context, result);
}
fn copy(engine: *em.Engine, target: c.JSValue, source: c.JSValue) !void {
    var iterator = try enumeration.Iterator.init(engine, source);
    defer iterator.deinit();
    while (try iterator.next()) |key| {
        defer engine.freeValue(key);
        const value = try js.getKey(engine, source, key);
        defer engine.freeValue(value);
        try js.setKey(engine, target, key, value);
    }
}
fn copyEach(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    try copy(engine, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined());
    return c.pi_js_undefined();
}
