//! Source default spread and worker-clone boundary. Keep own undefined values.
const js = @import("native_js_values.zig");
const c = js.c;
const values = @import("native_select_list.zig");
pub fn spreadDefaults(engine: *js.Engine, options: c.JSValue) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ .{ "maxWidth", 2000.0 }, .{ "maxHeight", 2000.0 }, .{ "maxBytes", 4718592.0 }, .{ "jpegQuality", 80.0 } }) |field|
        try js.define(engine, result, field[0], values.numeric(engine, field[1]));
    try js.spreadInto(engine, result, options);
    return result;
}
pub fn cloneForWorker(engine: *js.Engine, options: c.JSValue) !c.JSValue {
    return @import("native_structured_clone.zig").clone(engine, options);
}
