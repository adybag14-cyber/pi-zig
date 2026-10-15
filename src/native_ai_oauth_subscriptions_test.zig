const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn install(engine: *em.Engine) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    try s.put(global, "githubCopilotOAuth", try s.own(try @import("extensions/native_ai_oauth_copilot.zig").create(engine)));
    try s.put(global, "kimiCodingOAuth", try s.own(try @import("extensions/native_ai_oauth_kimi.zig").create(engine)));
    try s.put(global, "xaiOAuth", try s.own(try @import("extensions/native_ai_oauth_xai.zig").create(engine)));
}
test "native subscription OAuth actual Source84 public flows request bodies metadata and errors" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 15000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/ai-oauth-subscriptions-ae7.json");
    try sdk.put(engine, global, "oauthSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "ai-oauth-subscriptions-ae7.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-oauth-subscriptions-ae7.input.txt") ++
        "\nif(subscriptionOAuthRows.length!==84||oauthSource.rows.length!==84||oauthSource.sourceHead!=='ae7b16d43b7c78c5b6fa3213fdd1215bb339729d')throw Error('Source84 required');for(let i=0;i<84;i++)if(JSON.stringify(subscriptionOAuthRows[i])!==JSON.stringify(oauthSource.rows[i]))throw Error(JSON.stringify({case:i,actual:subscriptionOAuthRows[i],expected:oauthSource.rows[i]}));", "native-subscription-oauth-original.mjs") catch |err| {
        std.debug.print("Subscription OAuth Source84: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native subscription OAuth captured public functions survive caller graph collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule("globalThis.keptOAuth=[githubCopilotOAuth,kimiCodingOAuth,xaiOAuth];delete globalThis.githubCopilotOAuth;delete globalThis.kimiCodingOAuth;delete globalThis.xaiOAuth;export const prepared=true;", "native-subscription-oauth-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const result = try engine.evalModule(
        \\const access={marker:1};if((await keptOAuth[2].toAuth({access})).apiKey!==access)throw Error('xAI access identity');if((await keptOAuth[1].toAuth({access:'token'})).headers.Authorization!=='Bearer token')throw Error('Kimi retained body');const copilot=await keptOAuth[0].toAuth({access:'proxy-ep=proxy.individual.githubcopilot.com;',enterpriseUrl:'other.example'});if(copilot.baseUrl!=='https://api.individual.githubcopilot.com')throw Error('Copilot retained body');delete globalThis.keptOAuth;export const done=true;
    , "native-subscription-oauth-gc-complete.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native subscription OAuth shared Copilot catalog remains live through lexical roots" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    const catalog = try s.object();
    try s.put(global, "copilotLiveCatalog", catalog);
    try s.put(global, "copilotShared", try s.own(try @import("extensions/native_ai_oauth_copilot.zig").createWithCatalog(engine, catalog)));
    const result = try engine.evalModule(
        \\if(copilotShared.name!=='GitHub Copilot'||Object.hasOwn(copilotShared,'loginLabel'))throw Error('actual Copilot metadata');const marker={};let threw=false;try{copilotShared.refresh({get refresh(){throw marker;}},new AbortController().signal);}catch(e){threw=e===marker;}if(!threw)throw Error('normal arrow synchronous getter');copilotLiveCatalog.custom={id:'custom'};delete globalThis.copilotLiveCatalog;const out=await copilotShared.toAuth({access:'plain',enterpriseUrl:'https://ENTERPRISE.example/path'});if(out.baseUrl!=='https://copilot-api.enterprise.example')throw Error('enterprise URL');export const proof=true;
    , "native-subscription-oauth-shared-catalog.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
