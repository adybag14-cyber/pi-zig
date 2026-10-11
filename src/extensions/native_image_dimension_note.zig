//! Source dimension notes keep ordinary getters and VM numeric/string coercion.
const js = @import("native_js_values.zig");
const c = js.c;
const frames = @import("native_tui_alt_frame.zig");
const utf16 = @import("native_utf16.zig");
const arithmetic = @import("native_image_arithmetic.zig");
fn append(frame: *frames.Frame, current: c.JSValue, next: c.JSValue) !c.JSValue {
    return frame.own(try utf16.concat(frame.engine, &.{ current, next }));
}
fn run(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var frame: frames.Frame = .{ .engine = engine, .object = if (args.len > 0) args[0] else c.pi_js_undefined(), .bindings = c.pi_js_undefined() };
    defer frame.deinit();
    const resized = try frame.get(frame.object, "wasResized");
    if (!frames.v.truthy(engine, resized)) return c.pi_js_undefined();
    const original = try frame.get(frame.object, "originalWidth");
    const width = try frame.get(frame.object, "width");
    const scale = try frame.own(try arithmetic.binary(engine, .divide, original, width));
    var text = try frame.text("[Image: original ");
    text = try append(&frame, text, try frame.get(frame.object, "originalWidth"));
    text = try append(&frame, text, try frame.text("x"));
    text = try append(&frame, text, try frame.get(frame.object, "originalHeight"));
    text = try append(&frame, text, try frame.text(", displayed at "));
    text = try append(&frame, text, try frame.get(frame.object, "width"));
    text = try append(&frame, text, try frame.text("x"));
    text = try append(&frame, text, try frame.get(frame.object, "height"));
    text = try append(&frame, text, try frame.text(". Multiply coordinates by "));
    const fixed = try frame.own(try js.invoke(engine, scale, "toFixed", &.{c.JS_NewInt32(engine.context, 2)}));
    text = try append(&frame, text, fixed);
    text = try append(&frame, text, try frame.text(" to map to original image.]"));
    return frame.result(text);
}
pub fn create(engine: *js.Engine) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "formatDimensionNote", 1, run, &.{});
}
