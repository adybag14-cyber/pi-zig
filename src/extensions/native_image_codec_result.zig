//! Owner-VM image result construction shared by worker and inline strategies.
const std = @import("std");
const js = @import("native_js_values.zig");
const values = @import("native_select_list.zig");
const c = js.c;
pub fn create(engine: *js.Engine, bytes: []const u8, mime: c.JSValue, original_width: c.JSValue, original_height: c.JSValue, width: c.JSValue, height: c.JSValue, resized: bool) !c.JSValue {
    const encoded = try engine.gpa.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
    defer engine.gpa.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "data", try values.text(engine, encoded));
    try js.define(engine, result, "mimeType", c.JS_DupValue(engine.context, mime));
    try js.define(engine, result, "originalWidth", c.JS_DupValue(engine.context, original_width));
    try js.define(engine, result, "originalHeight", c.JS_DupValue(engine.context, original_height));
    try js.define(engine, result, "width", c.JS_DupValue(engine.context, width));
    try js.define(engine, result, "height", c.JS_DupValue(engine.context, height));
    try js.define(engine, result, "wasResized", c.pi_js_bool(engine.context, @intFromBool(resized)));
    return result;
}
