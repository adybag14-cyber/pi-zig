const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    c.JS_RunGC(engine.runtime);
    return c.pi_js_undefined();
}
fn setup(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/node_buffer.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "processImage", try @import("extensions/native_sdk_image_process.zig").create(engine));
    try sdk.put(engine, global, "normalizeToolResultImages", try @import("extensions/native_sdk_tool_result_images.zig").create(engine));
    try sdk.put(engine, global, "collectNow", try engine.checked(c.JS_NewCFunction(engine.context, collect, "collectNow", 0)));
    const source = @embedFile("extensions/fixtures/sdk-image-process-e622.json");
    const parsed = try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-image-process-e622.json"));
    defer engine.freeValue(parsed);
    try sdk.put(engine, global, "originalPngBase64", try sdk.get(engine, parsed, "pngBase64"));
    try sdk.put(engine, global, "imageProcessSource", c.JS_DupValue(engine.context, parsed));
}
test "native SDK image processing selected inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("SDK_IMAGE_PROCESS_TEST_INVENTORY={s}\n", .{encoded});
}
test "native SDK image processing matches36 genuine latest Source MIME conversion resizing getter iterator and promise cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-image-process-e622.input.txt") ++
        "\nif(imageProcessRows.length!==36||imageProcessSource.rows.length!==36)throw Error('36 genuine original Source cases required');for(let i=0;i<36;i++)if(JSON.stringify(imageProcessRows[i])!==JSON.stringify(imageProcessSource.rows[i]))throw Error(JSON.stringify({case:i,actual:imageProcessRows[i],expected:imageProcessSource.rows[i]}));", "native-sdk-image-process-source.mjs") catch |err| {
        std.debug.print("SDK image processing Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK image processing retained iterator and native byte owners survive collection during worker option getters" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const observed = try engine.evalModule(
        \\let collections=0;const content=[{type:'image',data:originalPngBase64,mimeType:'image/png'}];const result=await normalizeToolResultImages(content,{resizeOptions:{get maxWidth(){collections++;collectNow();return 2},maxHeight:2}});if(collections<1||result===content||result[0].mimeType!=='image/png'||result[1].type!=='text')throw Error('live owner graph lost during collection');const marker={owned:true};let closed=false;const throwing={some:()=>true,[Symbol.iterator](){return{next(){return{done:false,value:{type:'image',get data(){throw marker}}}},return(){closed=true;collectNow();throw Error('secondary close error')}}}};try{await normalizeToolResultImages(throwing);throw Error('missing original rejection')}catch(reason){if(reason!==marker||!closed)throw Error('iterator did not preserve thrown completion')}export const proof=true;
    , "native-sdk-image-process-gc.mjs");
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK image processing all native allocation failures release codec byte and asynchronous iterator owners" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            try setup(engine);
            const generation = engine.native_allocation_generation;
            const observed = engine.evalModule(
                \\const content=[{type:'text',text:'first'},{type:'image',data:originalPngBase64,mimeType:'image/bmp'}];const result=await normalizeToolResultImages(content,{autoResizeImages:false});if(result===content||result[1].mimeType!=='image/png'||result[2].type!=='text')throw Error('conversion not composed');export const proof=true;
            , "native-sdk-image-process-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(observed);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
