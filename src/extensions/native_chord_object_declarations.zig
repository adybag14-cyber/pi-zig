//! Actual Source1692 declaration maps; no old named-wrapper declaration API.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const prototype = try s.get(target, "prototype");
    const result = try s.keep(try engine.checked(c.JS_NewObjectProto(engine.context, if (c.JS_IsObject(prototype)) prototype else try s.get(captures[0], "objectPrototype"))));
    if (c.JS_ToBool(engine.context, captures[1]) != 0) {
        try h.field(&s, result, "resource", h.arg(args, 0));
    } else {
        inline for (.{ "cells", "cellSchemas", "cellVersions", "cellMigrations", "refs", "resources", "adopted", "listeners", "tasks", "derives", "registrations" }) |name| try h.field(&s, result, name, try h.map(&s));
    }
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    inline for (.{ "Decls", "ExposedImpl" }, 0..) |name, index| {
        const prototype = try s.record();
        try js.define(engine, bindings, name, try @import("native_class.zig").constructor(engine, name, @intCast(index), prototype, construct, &.{ bindings, c.pi_js_bool(engine.context, @intCast(index)) }));
    }
}
