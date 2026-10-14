//! Actual b45 replicatedState factory; callers supply the real context-module
//! background value, preserving its identity across publication hydration.
const r = @import("native_chord_replicated_values.zig");
const h = r.h;
const c = r.c;
fn create(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: r.Scope = .{ .engine = engine };
    defer s.deinit();
    const initial = h.arg(args, 0);
    if (c.JS_IsFunction(engine.context, try s.get(initial, "attach"))) return @import("native_chord_replicated_attached.zig").attach(engine, captures[0], initial, h.arg(args, 1));
    return s.result(try h.construct(&s, captures[0], "MutableReplicatedStateImpl", &.{initial}));
}
pub fn install(engine: *h.Engine, api: c.JSValue, background: c.JSValue) !void {
    var s: r.Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = try s.record();
    try h.field(&s, bindings, "classes", try s.record());
    try h.field(&s, bindings, "objectPrototype", try s.get(try s.keep(try r.js.global(engine, "Object")), "prototype"));
    try h.field(&s, bindings, "background", background);
    try @import("native_chord_replicated_subscriber.zig").install(engine, bindings);
    try @import("native_chord_replicated_publisher.zig").install(engine, bindings);
    try @import("native_chord_replicated_mutable.zig").install(engine, bindings);
    try @import("native_chord_replicated_attached.zig").install(engine, bindings);
    try r.js.define(engine, api, "replicatedState", try @import("native_node_function.zig").create(engine, "replicatedState", 2, create, &.{bindings}));
}
