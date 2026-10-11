const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const strategy = @import("extensions/native_image_resize_strategy.zig");
const worker = @import("extensions/native_image_vm_worker.zig");
const option_graph = @import("extensions/native_image_resize_options.zig");
const promises = @import("extensions/native_image_worker_promise.zig");
const image_api = @import("extensions/native_image_resize_api.zig");
test "native image JavaScript-valued strategy closes an unawaited worker promise with its VM" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    errdefer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var encoded_mime = blk: {
        const mime = try engine.checked(c.JS_NewString(engine.context, "image/png"));
        defer engine.freeValue(mime);
        break :blk try option_graph.serializeForWorker(engine, mime);
    };
    defer encoded_mime.deinit(std.testing.allocator);
    var encoded_options = blk: {
        const options = try engine.eval("({maxWidth:4})", "unawaited-image-options", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(options);
        break :blk try option_graph.serializeForWorker(engine, options);
    };
    defer encoded_options.deinit(std.testing.allocator);
    const task = try worker.Worker.start(std.testing.allocator, @embedFile("ai/fixtures/photon-source-8x5.png"), encoded_mime, encoded_options);
    const promise = promises.create(engine, task) catch |err| {
        task.deinit();
        return err;
    };
    engine.freeValue(promise);
    // Scheduler destruction releases its native callback owner, which joins
    // the exact worker before allocator and runtime destruction complete.
    engine.deinit();
}
test "native image JavaScript-valued strategy public candidate keeps clone and fallback getter traces" {
    const engine = try js.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "candidateResizeImage", try image_api.create(engine));
    const input = @embedFile("ai/fixtures/photon-source-8x5.png");
    const buffer = try engine.checked(c.JS_NewArrayBufferCopy(engine.context, input.ptr, input.len));
    defer engine.freeValue(buffer);
    try js.define(engine, global, "imageInputBuffer", c.JS_DupValue(engine.context, buffer));
    const result = try engine.evalModule(
        \\const bytes=new Uint8Array(imageInputBuffer),before=[...bytes],calls=[];
        \\const options={get maxWidth(){calls.push('maxWidth');return 4},get maxHeight(){calls.push('maxHeight');return 3}};
        \\const result=await candidateResizeImage(bytes,'image/png',options);if(result.width!==4||result.height!==3||JSON.stringify(calls)!=='["maxWidth","maxHeight"]'||JSON.stringify([...bytes])!==JSON.stringify(before))throw Error('Source worker options/input mismatch');
        \\const marker={original:true},failed=[];const rejected={get maxWidth(){failed.push('maxWidth');throw marker}};let promise;try{promise=candidateResizeImage(bytes,'image/png',rejected)}catch(error){throw Error('async image threw synchronously')};try{await promise;throw Error('missing image rejection')}catch(error){if(error!==marker)throw error};if(JSON.stringify(failed)!=='["maxWidth","maxWidth"]')throw Error('fallback original getter trace');
    , "native-image-public-candidate");
    engine.freeValue(result);
}
test "native image JavaScript-valued strategy settles its worker promise on the owner VM" {
    const engine = try js.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const mime = try engine.checked(c.JS_NewString(engine.context, "image/png"));
    defer engine.freeValue(mime);
    const options = try engine.eval("({maxWidth:4,maxHeight:3})", "image-promise-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    var encoded_mime = try option_graph.serializeForWorker(engine, mime);
    defer encoded_mime.deinit(std.testing.allocator);
    var encoded_options = try option_graph.serializeForWorker(engine, options);
    defer encoded_options.deinit(std.testing.allocator);
    const task = try worker.Worker.start(std.testing.allocator, @embedFile("ai/fixtures/photon-source-8x5.png"), encoded_mime, encoded_options);
    const promise = promises.create(engine, task) catch |err| {
        task.deinit();
        return err;
    };
    defer engine.freeValue(promise);
    const result = try engine.awaitValue(promise);
    defer engine.freeValue(result);
    const width = try js.get(engine, result, "width");
    defer engine.freeValue(width);
    var numeric: i32 = 0;
    if (c.JS_ToInt32(engine.context, &numeric, width) < 0) return js.capture(engine);
    try std.testing.expectEqual(@as(i32, 4), numeric);
}
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
