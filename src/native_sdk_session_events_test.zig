const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const events = @import("extensions/native_sdk_session_events.zig");
const hooks = @import("extensions/native_sdk_session_hooks.zig");
const c = em.c;
fn attach(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    events.attachWithDependencies(engine, if (argc > 0) args[0] else c.pi_js_undefined(), roots[0]) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
// The 28 original event cases issue no tool result normalization. A dependency
// that rejects is explicit test input; it cannot conceal an invoked missing port.
fn unusedNormalizer(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_ThrowInternalError(context, "event fixture unexpectedly invoked image normalizer");
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-session-events"});
    const group = try @import("extensions/native_group.zig").Group.init(engine);
    defer group.deinit();
    const root_group = try group.add("session-events-root");
    try root_group.installSchemas();
    const namespace = try sdk.object(engine);
    defer engine.freeValue(namespace);
    try sdk.install(engine, namespace);
    try @import("extensions/native_agent_complete.zig").install(engine, namespace);
    const dependencies = try sdk.object(engine);
    defer engine.freeValue(dependencies);
    try @import("extensions/native_sdk_session_estimate.zig").install(engine, dependencies);
    try sdk.put(engine, dependencies, "convertToLlm", try @import("extensions/native_sdk_messages.zig").create(engine));
    try sdk.put(engine, dependencies, "normalizeToolResultImages", try engine.checked(c.JS_NewCFunction(engine.context, unusedNormalizer, "fixtureUnusedImageNormalizer", 2)));
    const constructor = try sdk.get(engine, namespace, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    try events.install(engine, prototype);
    try hooks.installWithDependencies(engine, prototype, dependencies);
    try @import("extensions/native_sdk_custom_message.zig").install(engine, prototype);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "sdkSessionEventsNative", c.JS_DupValue(engine.context, namespace));
    var roots = [_]c.JSValue{dependencies};
    try sdk.put(engine, global, "attachSessionEvents", try engine.checked(c.JS_NewCFunctionData2(engine.context, attach, "attachSessionEvents", 1, 0, roots.len, &roots)));
    const original = @embedFile("extensions/fixtures/sdk-session-events-19cb.json");
    try sdk.put(engine, global, "sessionEventsSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "sdk-session-events-19cb.json")));
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-events-19cb.input.txt") ++
        "\nif(sdkSessionEventsRows.length!==28)throw Error('28 Source scenarios required');for(let i=0;i<28;i++){const actual=sdkSessionEventsRows[i],expected=sessionEventsSource.rows[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({scenario:actual.scenario,actual,expected}));}", "sdk-session-events-native.mjs") catch |err| {
        std.debug.print("SDK session events Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    const clear = try engine.eval("delete globalThis.sdkSessionEventsNative;delete globalThis.attachSessionEvents;delete globalThis.sessionEventsSource;delete globalThis.sdkSessionEventsRows", "sdk-session-events-clear.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(clear);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session events match 28 genuine factory Source scenarios with actual native Agent runner and manager" {
    try exercise(std.testing.allocator);
}
test "native SDK session events compaction utilities match original Source values getters and failures" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const namespace = try sdk.object(engine);
    defer engine.freeValue(namespace);
    try @import("extensions/native_sdk_session_estimate.zig").install(engine, namespace);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "sdkSessionEstimateNative", c.JS_DupValue(engine.context, namespace));
    const original = @embedFile("extensions/fixtures/sdk-session-estimate-19cb.json");
    try sdk.put(engine, global, "sdkSessionEstimateSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "sdk-session-estimate-19cb.json")));
    const observed = engine.evalModule("const{estimateProjectedContextTokens,shouldCompact,getVirtualModelState}=sdkSessionEstimateNative;\n" ++
        @embedFile("extensions/fixtures/sdk-session-estimate-19cb.input.txt") ++
        "\nfor(const key of['estimateRows','compactRows','virtualRows','utilityMetadata'])if(JSON.stringify(sdkSessionEstimateRows[key])!==JSON.stringify(sdkSessionEstimateSource[key]))throw Error(JSON.stringify({key,actual:sdkSessionEstimateRows[key],expected:sdkSessionEstimateSource[key]}));", "sdk-session-estimate-native.mjs") catch |err| {
        std.debug.print("SDK session estimate Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
