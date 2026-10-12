const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

test "native SDK private session lifecycle matches actual Source custom run and settlement phases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    const constructor = try sdk.get(engine, exports, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    // Bind actual native component bodies only in this owned test context.
    // Production factory activation still requires all session dependencies.
    try @import("extensions/native_sdk_custom_message.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_run.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_settled.zig").install(engine, prototype);
    try engine.registerValueModule("sdk-private-session-lifecycle", exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/sdk-session-lifecycle-19cb.json");
    try sdk.put(engine, root, "lifecycleSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "sdk-session-lifecycle-19cb.json")));
    const observed = engine.evalModule("import{AgentSession,SessionManager}from'sdk-private-session-lifecycle';\n" ++
        @embedFile("extensions/fixtures/sdk-session-custom-19cb.input.txt") ++ "\n" ++
        @embedFile("extensions/fixtures/sdk-session-run-19cb.input.txt") ++ "\n" ++
        @embedFile("extensions/fixtures/sdk-session-settled-19cb.input.txt") ++ "\n" ++
        @embedFile("extensions/fixtures/sdk-session-transcript-19cb.input.txt") ++
        "\nfor(const [key,actual]of[['custom',sdkCustomRows],['run',sdkSessionRunRows],['settled',sdkSessionSettledRows],['transcript',sdkSessionTranscriptRows]])if(JSON.stringify(actual)!==JSON.stringify(lifecycleSource[key]))throw Error(JSON.stringify({key,actual,expected:lifecycleSource[key]}));", "sdk-session-lifecycle-source.mjs") catch |err| {
        std.debug.print("Session lifecycle Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
}
