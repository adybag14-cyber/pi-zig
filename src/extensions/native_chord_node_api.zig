//! Actual Node-only Chord facade, available only to the opt-in private guest.
const h = @import("native_chord_host_values.zig");
pub fn exports(engine: *h.Engine, bindings: h.c.JSValue) !h.c.JSValue {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const api = try s.keep(try @import("native_chord_manager_api.zig").exports(engine, bindings));
    try h.js.define(engine, api, "nodeLoader", try @import("native_chord_node_loader.zig").create(engine));
    try h.js.define(engine, api, "forkDriver", try @import("native_node_function.zig").create(engine, "forkDriver", 1, @import("native_chord_process_runtime.zig").forkDriver, &.{bindings}));
    return s.result(api);
}
