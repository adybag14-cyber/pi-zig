const std = @import("std");
const em = @import("extensions/engine.zig");
const v = @import("extensions/native_ai_provider_values.zig");
const callback = @import("extensions/native_ai_oauth_callback_server.zig");
const http = @import("extensions/native_ai_http.zig");
const c = em.c;
fn request(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const url = try engine.toString(args[0]);
    defer engine.gpa.free(url);
    const method = if (args.len > 1) try engine.toString(args[1]) else try engine.gpa.dupe(u8, "GET");
    defer engine.gpa.free(method);
    return http.open(engine, .{ .url = url, .method = if (std.mem.eql(u8, method, "POST")) .POST else .GET, .payload = "", .headers = &.{}, .timeout_ms = 2000, .framing = .body }, c.pi_js_undefined());
}
test "native OAuth callback replays exact original Source pages errors lifecycle and manual races" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_url.zig").install(engine);
    try @import("extensions/abort_signal.zig").install(engine);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "A", try scope.own(try callback.create(engine)));
    try scope.put(global, "rawRequest", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "rawRequest", 2, request, &.{})));
    const result = engine.evalModule(
        \\const request=async(url,method='GET')=>{const r=rawRequest(url,method),head=await r.ready;let body='';for await(const e of r.events)if(e.type==='body'||e.type==='error_body')body+=e.body;return{status:head.status,contentType:head.headers['content-type'],cacheControl:head.headers['cache-control'],body}};
    ++ @embedFile("extensions/fixtures/ai-oauth-callback-ae7.input.txt") ++
        \\if(callbackRows.length!==16)throw Error('all original cases required');globalThis.serializedCallbackRows=JSON.stringify(callbackRows);
    , "native-oauth-callback-controlled.mjs") catch |err| {
        std.debug.print("Callback fixture: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    // The expected fixture is populated only by the admitted original-source capture.
    const actual = try engine.toString(try scope.get(global, "serializedCallbackRows"));
    defer engine.gpa.free(actual);
    const expected = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("extensions/fixtures/ai-oauth-callback-ae7.json"), .{});
    defer expected.deinit();
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, expected.value.object.get("rows").?, .{});
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings(encoded, actual);
    try std.testing.expect(!callback.pending(engine));
}
