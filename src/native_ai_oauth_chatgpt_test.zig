const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const oauth = @import("extensions/native_ai_oauth_openai_chatgpt.zig");
const callback = @import("extensions/native_ai_oauth_chatgpt_callback.zig");
const c = em.c;
fn install(engine: *em.Engine, token_origin: ?[]const u8) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/native_url.zig").install(engine);
    try @import("extensions/abort_signal.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "openaiChatGPTOAuth", try oauth.createForTest(engine, .{ .token_origin = token_origin }));
}
test "native AI ChatGPT source input covers metadata live values error and getter order" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    try install(engine, null);
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-oauth-chatgpt-ae7.input.mjs"), "ai-oauth-chatgpt-ae7.input.mjs") catch |err| {
        std.debug.print("ChatGPT fixture failed: {s}\n", .{engine.last_error orelse "unknown"});
        return err;
    };
    engine.freeValue(result);
    const checked = try engine.evalModule(
        \\const {rows,wire}=chatGPTOAuthObservation;const success=rows.find(r=>r.name==='refresh-success').value;if(!success||success.clientId!==' issued client '||success.expires!==1700003420123||success.access!==' access '||success.scopes.join('|')!=='openid|chatgpt.tokens.use.direct|custom')throw Error('issued client credential');if(wire[0].url!=='https://auth.openai.com/api/accounts/oauth/token'||wire[0].method!=='POST'||wire[0].body!=='grant_type=refresh_token&client_id=+issued+client+&refresh_token=r+%2B%2F%3D&resource=https%3A%2F%2Fapi.openai.com%2Fv1'||!wire.every(x=>x.signal))throw Error('exact source form');if(JSON.stringify(rows.find(r=>r.name==='refresh-getter-order').value)!==JSON.stringify(['clientId','refresh','refresh.toString']))throw Error('live getter order');if(!rows.find(r=>r.name==='toAuth-live').value.same||!rows.find(r=>r.name==='toAuth-getter-error').value.same)throw Error('credential identity');if(rows.some(r=>r.name==='login-invalid-device'&&r.error.message!=='Sign in with ChatGPT requires a device ID (UUID) for this installation'))throw Error('device validation');export const pass=true;
    , "chatgpt-live-checks.mjs");
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(!callback.pending(engine));
}
test "native AI ChatGPT refresh real owned HTTP preserves path form status and issued ID" {
    const fixture = @import("ai/http_fixture.zig");
    const body = "{\"access_token\":\"fixture-access\",\"refresh_token\":\"fixture-refresh\",\"expires_in\":3600,\"scope\":\"chatgpt.tokens.use.direct\"}";
    const server = try fixture.PlanServer.init(std.testing.allocator, std.testing.io, &.{.{ .path = "/api/accounts/oauth/token", .body = body, .payload_contains = "grant_type=refresh_token&client_id=issued%2Bfixture&refresh_token=refresh+%2B%2F&resource=https%3A%2F%2Fapi.openai.com%2Fv1", .expected_request_headers = &.{ .{ .name = "accept", .value = "application/json" }, .{ .name = "content-type", .value = "application/x-www-form-urlencoded" } } }});
    defer server.deinit();
    const origin = try server.url(std.testing.allocator, "");
    defer std.testing.allocator.free(origin);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine, origin);
    const result = engine.evalModule("const credential=await openaiChatGPTOAuth.refresh({clientId:'issued+fixture',refresh:'refresh +/'},new AbortController().signal);if(credential.clientId!=='issued+fixture'||credential.access!=='fixture-access'||credential.refresh!=='fixture-refresh')throw Error('real native HTTP refresh');export const pass=true;", "chatgpt-owned-http.mjs") catch |err| {
        std.debug.print("ChatGPT HTTP failed: {s}\n", .{engine.last_error orelse "unknown"});
        return err;
    };
    engine.freeValue(result);
    try server.finish();
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(!@import("extensions/native_ai_http.zig").pending(engine));
}
test "native AI ChatGPT manual login owns callback cleanup and exact registration form" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine, null);
    const result = engine.evalModule(
        \\const notices=[],controller=new AbortController();let state,challenge,manualSignal;globalThis.fetch=async(url,init)=>{const form=init.body;if(form.get('client_id')!=='issued + client'||form.get('grant_type')!=='authorization_code'||form.get('redirect_uri')!=='http://127.0.0.1:1455/auth/callback'||form.get('resource')!=='https://api.openai.com/v1'||form.get('code')!=='code+/='||form.get('code_verifier').length!==43)throw Error('exchange dynamic registration contract');return {ok:true,json:async()=>({access_token:'access',refresh_token:'refresh',expires_in:600,id_token:'present',scope:'chatgpt.tokens.use.direct'})}};const interaction={signal:controller.signal,notify(value){notices.push(value.type);if(value.type==='auth_url'){const url=new URL(value.url);state=url.searchParams.get('state');challenge=url.searchParams.get('code_challenge');if(url.pathname!=='/api/accounts/authorize'||url.searchParams.get('client_id')!=='dynamic_agent_client'||url.searchParams.get('ext_agent_host_id')!=='urn:uuid:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'||url.searchParams.get('agent_name_hint')!=='Fixture Agent'||url.searchParams.get('nonce').length!==43||state.length!==43||challenge.length!==43)throw Error('authorization URL')}} ,prompt(value){manualSignal=value.signal;return Promise.resolve('http://127.0.0.1:1455/auth/callback?code=code%2B%2F%3D&state='+state+'&client_id=+issued+%2B+client+')}};const result=await openaiChatGPTOAuth.login(interaction,{getDeviceId(){return 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'},agentName:'Fixture Agent'});if(result.clientId!=='issued + client'||!manualSignal.aborted||notices.join('|')!=='auth_url|progress')throw Error('manual race or cleanup');delete globalThis.fetch;export const pass=true;
    , "chatgpt-native-login.mjs") catch |err| {
        std.debug.print("ChatGPT login failed: {s}\n", .{engine.last_error orelse "unknown"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(!callback.pending(engine));
}
test "native AI ChatGPT callback validates ordered fields preserves issued ID and closes spare sockets" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const server = try callback.open(engine, "expected-state", "127.0.0.1", 0);
    defer engine.freeValue(server);
    try sdk.put(engine, global, "callbackServer", c.JS_DupValue(engine.context, server));
    const port_value = try sdk.get(engine, server, "port");
    defer engine.freeValue(port_value);
    var port: u32 = 0;
    try std.testing.expect(c.JS_ToUint32(engine.context, &port, port_value) == 0);
    const address = try std.Io.net.IpAddress.parse("127.0.0.1", @intCast(port));
    const spare = try address.connect(std.testing.io, .{ .mode = .stream, .protocol = .tcp });
    defer spare.close(std.testing.io);
    const rows = [_]struct { target: []const u8, status: u16, message: []const u8 }{
        .{ .target = "/wrong?code=x&state=expected-state", .status = 404, .message = "Callback route not found." },
        .{ .target = "/auth/callback?state=expected-state", .status = 400, .message = "Missing authorization code" },
        .{ .target = "/auth/callback?code=x", .status = 400, .message = "Missing OAuth state" },
        .{ .target = "/auth/callback?code=x&state=wrong", .status = 400, .message = "OAuth state mismatch" },
        .{ .target = "/auth/callback?code=x&state=expected-state", .status = 400, .message = "OpenAI OAuth registration callback did not contain an issued client ID" },
        .{ .target = "/auth/callback?code=owned%2B%2F%3D&state=expected-state&client_id=%C2%A0issued%2Bclient%E3%80%80", .status = 200, .message = "ChatGPT authentication completed. You can close this window." },
    };
    for (rows) |row| {
        const url = try std.fmt.allocPrint(std.testing.allocator, "http://127.0.0.1:{d}{s}", .{ port, row.target });
        defer std.testing.allocator.free(url);
        var response = try @import("ai/bootstrap_http.zig").request(std.testing.allocator, std.testing.io, .{ .url = url, .options = .{ .policy = .{ .timeout_ms = 2000, .max_retries = 0 } } });
        defer response.deinit(std.testing.allocator);
        try std.testing.expectEqual(row.status, response.status);
        try std.testing.expect(std.mem.indexOf(u8, response.body, row.message) != null);
    }
    const result = try engine.evalModule("const result=await callbackServer.result;if(result.code!=='owned+/='||result.clientId!=='issued+client')throw Error('callback result');callbackServer.close();export const pass=true;", "chatgpt-callback-owned.mjs");
    engine.freeValue(result);
    try std.testing.expect(!callback.pending(engine));
    c.JS_RunGC(engine.runtime);
}
test "native AI ChatGPT VM teardown cancels abandoned callback and idle owned connection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    var engine_alive = true;
    defer if (engine_alive) engine.deinit();
    engine.native_io = std.testing.io;
    const server = try callback.open(engine, "abandoned-state", "127.0.0.1", 0);
    const port_value = try sdk.get(engine, server, "port");
    var port: u32 = 0;
    try std.testing.expect(c.JS_ToUint32(engine.context, &port, port_value) == 0);
    engine.freeValue(port_value);
    engine.freeValue(server);
    const address = try std.Io.net.IpAddress.parse("127.0.0.1", @intCast(port));
    const spare = try address.connect(std.testing.io, .{ .mode = .stream, .protocol = .tcp });
    defer spare.close(std.testing.io);
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(callback.pending(engine));
    engine.deinit();
    engine_alive = false;
    var replacement = try address.listen(std.testing.io, .{ .reuse_address = true });
    replacement.deinit(std.testing.io);
}
