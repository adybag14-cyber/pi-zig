//! Source-derived public OAuth façade observations; no real provider traffic.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const functions = @import("extensions/native_node_function.zig");
const durable = @import("extensions/native_durable.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;

pub fn install(engine: *em.Engine) !void {
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
    try sdk.put(engine, exports, "createRadiusOAuth", try @import("extensions/native_ai_oauth_radius.zig").factory(engine));
    try engine.registerValueModule("native-oauth-codex-radius", exports);
}

test "native OAuth Codex Radius actual ae7 Source35 owned fake HTTP" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 20000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
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

test "native OAuth Codex Radius actual ae7 pending roots retain credential identity through GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 20000 });
    defer engine.deinit();
    try install(engine);
    const exports = engine.native_module_values.get("native-oauth-codex-radius").?;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "ownedCodex", try sdk.get(engine, exports, "openaiCodexOAuth"));
    try sdk.put(engine, global, "ownedRadiusFactory", try sdk.get(engine, exports, "createRadiusOAuth"));
    const started = try engine.eval(
        \\globalThis.ownedAccess={identity:'owned'};globalThis.ownedSignal=new AbortController().signal;
        \\globalThis.fetch=async(url,init)=>init.body.get('refresh_token')==='fail'?{ok:false,status:400,async text(){return'{"error":"invalid_client"}'}}:{ok:true,async json(){return{access_token:'e30.'+btoa(JSON.stringify({'https://api.openai.com/auth':{chatgpt_account_id:'owned-account'}}))+'.sig',refresh_token:'owned-refresh',expires_in:120,scope:ownedAccess}}};
        \\globalThis.ownedRadius=ownedRadiusFactory({name:'Owned',gateway:'owned.example'});
        \\globalThis.ownedPending=[ownedCodex.refresh({refresh:'owned'},ownedSignal),ownedRadius.refresh({refresh:'owned'},ownedSignal),ownedCodex.toAuth({access:ownedAccess}),ownedRadius.toAuth({access:ownedAccess}),ownedRadius.refresh({refresh:'fail'},ownedSignal).catch(e=>e),ownedRadiusFactory({name:'Second',gateway:'owned.example'}).refresh({refresh:'fail'},ownedSignal).catch(e=>e)];
        \\undefined;
    , "native-oauth-gc-start", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(started);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const values=await Promise.all(globalThis.ownedPending);if(values[0].accountId!=='owned-account'||values[1].scope!==ownedAccess||values[2].apiKey!==ownedAccess||values[3].apiKey!==ownedAccess||values[4].constructor!==values[5].constructor||values[4].constructor.name!=='OAuthResponseError'||values[4].constructor.length!==4||!(values[4] instanceof Error)||values[4].status!==400)throw Error('OAuth owned graph lost identity');
        \\delete globalThis.fetch;delete globalThis.ownedPending;export const proof=true;
    , "native-oauth-gc-complete");
    defer engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}

test "native OAuth Codex Radius actual ae7 Source wire only rebinds owned origin and consumes genuine Response" {
    const gpa = std.testing.allocator;
    var source = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/oauth-codex-radius-ae7-source.json"), .{});
    defer source.deinit();
    const codex_wire = source.value.array.items[7].object.get("requests").?.array.items[0];
    const radius_wire = source.value.array.items[16].object.get("requests").?.array.items[0];
    const codex_credential = source.value.array.items[7].object.get("value").?;
    const codex_body = try std.fmt.allocPrint(gpa, "{{\"access_token\":\"{s}\",\"refresh_token\":\"refresh-2\",\"expires_in\":120}}", .{codex_credential.object.get("access").?.string});
    defer gpa.free(codex_body);
    const fixture = @import("test_support/oauth_codex_radius_http_fixture.zig");
    const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{
        .{ .path = "/oauth/token", .body = codex_body, .payload_exact = codex_wire.object.get("body").?.string, .expected_request_headers = &.{.{ .name = "content-type", .value = "application/x-www-form-urlencoded" }} },
        .{ .path = "/v1/oauth/token", .body = "{\"access_token\":\"a\",\"refresh_token\":\"r\",\"expires_in\":120,\"scope\":\"gateway offline_access\"}", .payload_exact = radius_wire.object.get("body").?.string, .expected_request_headers = &.{ .{ .name = "accept", .value = "application/json" }, .{ .name = "content-type", .value = "application/x-www-form-urlencoded" } } },
    });
    defer server.deinit();
    const origin = try server.url(gpa, "");
    defer gpa.free(origin);
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 20000 });
    defer engine.deinit();
    try install(engine);
    try @import("extensions/native_web_response.zig").install(engine);
    const v = @import("extensions/native_ai_provider_values.zig");
    const http = @import("extensions/native_ai_oauth_http.zig");
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const native_fetch = try http.captureFetch(&scope);
    const Rebind = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: v.Scope = .{ .engine = host };
            defer local.deinit();
            const url = try local.own(try v.js.builtin(host, "URL", &.{args[0]}));
            const original = try local.invoke(url, "toString", &.{});
            if (!local.equal(original, roots[2]) and !local.equal(original, roots[3])) return error.UnexpectedOAuthOriginalFullUrl;
            const address = try local.concat(roots[1], try local.concat(try local.get(url, "pathname"), try local.get(url, "search")));
            return http.requestWithFetch(host, roots[0], address, if (args.len > 1) args[1] else c.pi_js_undefined());
        }
    };
    try scope.put(global, "fetch", try scope.own(try functions.createArrow(engine, "fetch", 1, Rebind.call, &.{ native_fetch, try scope.text(origin), try scope.text(codex_wire.object.get("url").?.string), try scope.text(radius_wire.object.get("url").?.string) })));
    try scope.put(global, "ownedWireCodexExpected", try scope.own(try durable.jsValue(engine, codex_credential)));
    const result = try engine.evalModule(
        \\import{openaiCodexOAuth,createRadiusOAuth}from'native-oauth-codex-radius';Date.now=()=>1700000000000;
        \\const originalJson=Response.prototype.json;let actualResponseCount=0;Response.prototype.json=function(){if(!(this instanceof Response))throw Error('non-native Response');actualResponseCount++;return originalJson.call(this)};
        \\const signal=new AbortController().signal,codex=await openaiCodexOAuth.refresh({refresh:'r +/=x'},signal),radius=await createRadiusOAuth({name:'Radius test',gateway:'gateway.example/base///'}).refresh({refresh:'r +/=x'},signal);
        \\if(JSON.stringify(codex)!==JSON.stringify(ownedWireCodexExpected)||radius.access!=='a'||radius.expires!==1700000060000||actualResponseCount!==2)throw Error('owned exact Source OAuth wire/Response mismatch');export const proof=true;
    , "native-oauth-source-wire-owned-origin");
    defer engine.freeValue(result);
    try server.finish();
    try std.testing.expectEqual(@as(usize, 2), server.captured.items.len);
    c.JS_RunGC(engine.runtime);
}
