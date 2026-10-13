const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    try @import("native_sdk_session_constructor_phase_test.zig").setup(engine, environment);
    try @import("extensions/node_buffer.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const namespace = try sdk.get(engine, global, "constructorPhaseSDK");
    defer engine.freeValue(namespace);
    const constructor = try sdk.get(engine, namespace, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_session_public_values.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_prompt_images.zig").install(engine, prototype);
    const source = @embedFile("extensions/fixtures/sdk-prompt-images-e622.json");
    const parsed = try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-prompt-images-e622.json"));
    defer engine.freeValue(parsed);
    try sdk.put(engine, global, "promptImagesSource", c.JS_DupValue(engine.context, parsed));
    const png = @embedFile("ai/fixtures/photon-source-8x5.png");
    const encoded = try engine.gpa.alloc(u8, std.base64.standard.Encoder.calcSize(png.len));
    defer engine.gpa.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, png);
    try sdk.put(engine, global, "originalPngBase64", try sdk.text(engine, encoded));
    const adapter = try engine.evalModule(
        \\globalThis.createPromptImagesCase=async()=>createNativeConstructorPhase();
    , "native-sdk-prompt-images-adapter.mjs");
    engine.freeValue(adapter);
}
test "native SDK session prompt images match15 original Source normalization hints limits getters and iterator cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-prompt-images-e622.input.txt") ++
        "\nif(promptImageRows.length!==15||promptImagesSource.rows.length!==15)throw Error('15 original Source cases required');for(let i=0;i<15;i++)if(JSON.stringify(promptImageRows[i])!==JSON.stringify(promptImagesSource.rows[i]))throw Error(JSON.stringify({case:i,actual:promptImageRows[i],expected:promptImagesSource.rows[i]}));", "native-sdk-prompt-images-source.mjs") catch |err| {
        std.debug.print("Session prompt images Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session prompt images original receiver and image buffers remain rooted across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\const state=await createPromptImagesCase();state.settings.getImageAutoResize=()=>false;const work=state.session._normalizePromptImages([{data:originalPngBase64,mimeType:'image/bmp'}]);globalThis.retainedPromptImages={state,work};export const prepared=true;
    , "native-sdk-prompt-images-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const result=await retainedPromptImages.work;if(result.images.length!==1||result.images[0].mimeType!=='image/png'||!result.hints[0].includes('converted from image/bmp'))throw Error('image owner lost');retainedPromptImages.state.dispose();delete globalThis.retainedPromptImages;export const completed=true;
    , "native-sdk-prompt-images-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session prompt images all allocation failures release codec iterator and session owner graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const observed = engine.evalModule(
                \\const state=await createPromptImagesCase();state.settings.getImageAutoResize=()=>false;const result=await state.session._normalizePromptImages([{data:originalPngBase64,mimeType:'image/bmp'}]);if(result.images[0].mimeType!=='image/png'||result.hints.length!==1)throw Error('image result');state.dispose();export const proof=true;
            , "native-sdk-prompt-images-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(observed);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
