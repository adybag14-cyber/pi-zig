//! Source-derived public OAuth façade observations; no real provider traffic.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const functions = @import("extensions/native_node_function.zig");
const durable = @import("extensions/native_durable.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;

test "native OAuth Codex Radius actual ae7 Source35 owned fake HTTP" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 20000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/node_url.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/node_base64.zig").install(engine, global);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.put(engine, exports, "openaiCodexOAuth", try @import("extensions/native_ai_oauth_codex.zig").create(engine));
    const Adapter = struct {
        fn create(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return @import("extensions/native_ai_oauth_radius.zig").create(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    try sdk.put(engine, exports, "createRadiusOAuth", try functions.create(engine, "createRadiusOAuth", 1, Adapter.create, &.{}));
    try engine.registerValueModule("native-oauth-codex-radius", exports);
    try engine.registerModule("oauth-codex-radius-cases", @embedFile("extensions/fixtures/oauth-codex-radius-ae7-cases.input.txt"));
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/oauth-codex-radius-ae7-source.json"));
    defer fixture.deinit();
    try sdk.put(engine, global, "oauthCodexRadiusExpected", try durable.jsValue(engine, fixture.value));
    const module = engine.evalModule(@embedFile("extensions/fixtures/oauth-codex-radius-ae7-native.input.txt"), "native-oauth-codex-radius-source35") catch |err| {
        std.debug.print("OAuth Codex Radius evaluation {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        return err;
    };
    defer engine.freeValue(module);
    const actual = try sdk.get(engine, global, "oauthCodexRadiusActual");
    defer engine.freeValue(actual);
    const raw = try engine.stringify(actual);
    defer engine.gpa.free(raw);
    const expected_value = try sdk.get(engine, global, "oauthCodexRadiusExpected");
    defer engine.freeValue(expected_value);
    const expected = try engine.stringify(expected_value);
    defer engine.gpa.free(expected);
    if (!std.mem.eql(u8, raw, expected)) {
        std.debug.print("OAuth Codex Radius actual={s}\nexpected={s}\n", .{ raw, expected });
        return error.OAuthSourceObservationMismatch;
    }
    c.JS_RunGC(engine.runtime);
}
