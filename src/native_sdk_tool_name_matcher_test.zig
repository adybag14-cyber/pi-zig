const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn setup(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "createToolNameMatcher", try @import("extensions/native_sdk_tool_name_matcher.zig").create(engine));
}
test "native SDK tool-name matcher matches27 original Source exact wildcard escaping live methods and callback metadata cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-tool-matcher-e622.json");
    try sdk.put(engine, global, "toolMatcherSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-tool-matcher-e622.json")));
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-tool-matcher-e622.input.txt") ++
        "\nif(toolMatcherRows.length!==27||toolMatcherSource.rows.length!==27)throw Error('27 original Source cases required');for(let i=0;i<27;i++)if(JSON.stringify(toolMatcherRows[i])!==JSON.stringify(toolMatcherSource.rows[i]))throw Error(JSON.stringify({case:i,actual:toolMatcherRows[i],expected:toolMatcherSource.rows[i]}));", "native-sdk-tool-name-matcher-source.mjs") catch |err| {
        std.debug.print("Tool-name matcher Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK tool-name matcher retained collection roots survive explicit collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try setup(engine);
    const prepared = try engine.evalModule(
        \\globalThis.retainedMatcher=createToolNameMatcher(['read','mcp__a__*','a[?*']);export const prepared=true;
    , "native-sdk-matcher-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\if(!retainedMatcher('read')||!retainedMatcher('mcp__a__tool')||!retainedMatcher('a[?value')||retainedMatcher('mcp__b__tool'))throw Error('captured matcher collections lost');delete globalThis.retainedMatcher;export const completed=true;
    , "native-sdk-matcher-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK tool-name matcher every allocation failure releases collection and callback graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{});
            defer engine.deinit();
            try setup(engine);
            const generation = engine.native_allocation_generation;
            const observed = engine.evalModule(
                \\const matcher=createToolNameMatcher(['read','mcp__a__*','a[?*']);if(!matcher('read')||!matcher('mcp__a__tool')||!matcher('a[?value')||matcher('mcp__b__tool'))throw Error('matcher values');export const proof=true;
            , "native-sdk-matcher-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(observed);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
