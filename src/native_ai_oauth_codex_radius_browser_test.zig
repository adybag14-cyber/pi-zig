//! Original browser OAuth Source7 over owned native callbacks and HTTP responses.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const v = @import("extensions/native_ai_provider_values.zig");
const durable = @import("extensions/native_durable.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;

test "native OAuth Codex Radius browser actual ae7 Source7 owned loopback callbacks" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try @import("native_ai_oauth_codex_radius_test.zig").install(engine);
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/native_web_crypto.zig").install(engine);
    try @import("extensions/native_web_response.zig").install(engine);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "ownedCallbackFetch", try @import("extensions/native_ai_oauth_http.zig").captureFetch(&scope));
    try engine.registerModule("oauth-codex-radius-browser-cases", @embedFile("extensions/fixtures/oauth-codex-radius-browser-ae7-cases.input.txt"));
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/oauth-codex-radius-browser-ae7-source.json"));
    defer fixture.deinit();
    try scope.put(global, "oauthBrowserExpected", try scope.own(try durable.jsValue(engine, fixture.value)));
    const module = engine.evalModule(
        \\import{openaiCodexOAuth,createRadiusOAuth}from'native-oauth-codex-radius';
        \\import{runOAuthBrowserCases}from'oauth-codex-radius-browser-cases';
        \\globalThis.oauthBrowserActual=await runOAuthBrowserCases(openaiCodexOAuth,createRadiusOAuth,globalThis.ownedCallbackFetch);
    , "native-oauth-codex-radius-browser-source7") catch |err| {
        std.debug.print("OAuth browser Source7 {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        return err;
    };
    defer engine.freeValue(module);
    const actual = try engine.stringify(try scope.get(global, "oauthBrowserActual"));
    defer engine.gpa.free(actual);
    const expected = try engine.stringify(try scope.get(global, "oauthBrowserExpected"));
    defer engine.gpa.free(expected);
    if (!std.mem.eql(u8, actual, expected)) {
        std.debug.print("OAuth browser actual={s}\nexpected={s}\n", .{ actual, expected });
        return error.OAuthBrowserSourceObservationMismatch;
    }
    c.JS_RunGC(engine.runtime);
}
