//! Native value operations shared by the actual batch3 factory bodies.
const em = @import("engine.zig");
const ordinary = @import("native_legacy_function.zig");
pub const Engine = em.Engine;
pub const Scope = @import("native_highlight_scope.zig").Scope;
pub const c = em.c;
pub fn factory(engine: *Engine, name: [*:0]const u8, comptime body: anytype) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return body(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, name, 1, Adapter.invoke, &.{});
}
pub fn rx(s: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(pattern)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
pub fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
pub fn mode(s: *Scope, class_name: []const u8) !c.JSValue {
    const result = try s.object();
    try s.put(result, "className", try s.text(class_name));
    return result;
}
pub fn boolean(s: *Scope, value: bool) c.JSValue {
    return c.pi_js_bool(s.engine.context, @intFromBool(value));
}
