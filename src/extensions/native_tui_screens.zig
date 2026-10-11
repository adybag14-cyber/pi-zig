//! Public renderer declarations share the genuine Source TuiBase identity.
//! This private candidate requires composed public and frontend gates.
const js = @import("native_js_values.zig");
const c = js.c;

pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    const base = try @import("native_tui_base.zig").create(engine, exports);
    defer engine.freeValue(base);
    try js.define(engine, exports, "TuiMainScreen", try @import("native_tui_main_screen.zig").create(engine, exports, base));
    try js.define(engine, exports, "TuiAltScreen", try @import("native_tui_alt_screen.zig").create(engine, exports, base));
}
