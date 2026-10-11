const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const strategy = @import("extensions/native_image_resize_strategy.zig");
const worker = @import("extensions/native_image_vm_worker.zig");
const option_graph = @import("extensions/native_image_resize_options.zig");
test "native image JavaScript-valued strategy executes on an independent owned worker VM" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const mime = try engine.checked(c.JS_NewString(engine.context, "image/png"));
    defer engine.freeValue(mime);
    const options = try engine.eval("({maxWidth:4,maxHeight:3})", "image-worker-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    var encoded_mime = try option_graph.serializeForWorker(engine, mime);
    defer encoded_mime.deinit(std.testing.allocator);
    var encoded_options = try option_graph.serializeForWorker(engine, options);
    defer encoded_options.deinit(std.testing.allocator);
    const task = try worker.Worker.start(std.testing.allocator, @embedFile("ai/fixtures/photon-source-8x5.png"), encoded_mime, encoded_options);
    defer task.deinit();
    const result = try task.result(engine);
    defer engine.freeValue(result);
    try std.testing.expect(task.isDone());
    const width = try js.get(engine, result, "width");
    defer engine.freeValue(width);
    var value: i32 = 0;
    if (c.JS_ToInt32(engine.context, &value, width) < 0) return js.capture(engine);
    try std.testing.expectEqual(@as(i32, 4), value);
}
test "native image JavaScript-valued strategy matches actual original resized bytes and dimension types" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const mime = try engine.checked(c.JS_NewString(engine.context, "image/png"));
    defer engine.freeValue(mime);
    const options = try engine.eval("({maxWidth:4,maxHeight:3})", "image-js-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    const result = try strategy.resize(engine, @embedFile("ai/fixtures/photon-source-8x5.png"), mime, options);
    defer engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeImageResult", c.JS_DupValue(engine.context, result));
    const check = try engine.eval(
        \\if(nativeImageResult.data!=='iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAYAAAC09K7GAAAAPklEQVR4AQEzAMz/AG2IfvSNhGvRhneO33qLffEArF5i5mhkof9ohpvogZtY9wCHepPddJ180aFKePVNbJf/1A4coj83usMAAAAASUVORK5CYII='||nativeImageResult.width!==4||nativeImageResult.height!==3||nativeImageResult.originalWidth!==8||nativeImageResult.originalHeight!==5||nativeImageResult.mimeType!=='image/png'||nativeImageResult.wasResized!==true)throw Error('Source image result mismatch');
    , "image-js-source-result", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(check);
}
