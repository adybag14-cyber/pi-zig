//! Genuine Source24 differential plus retained callback/Response ownership.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    // Shared Response's bootstrap installs the actual Body/ReadableStream graph.
    // Its absence remains a compile-time dependency, never a Response double.
    const engine = try @import("extensions/native_web_response_test.zig").setup(gpa);
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/node_buffer.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const api = try sdk.object(engine);
    defer engine.freeValue(api);
    try sdk.put(engine, api, "anthropic", try @import("extensions/native_ai_oauth_anthropic.zig").create(engine));
    try sdk.put(engine, api, "openrouter", try @import("extensions/native_ai_oauth_openrouter.zig").create(engine));
    try sdk.put(engine, global, "oauthAPI", c.JS_DupValue(engine.context, api));
    return engine;
}
test "native AI OAuth Anthropic OpenRouter genuine Source24 metadata requests callbacks signals and issued credentials" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    // Published only by the admitted original-source owner after successful
    // termination and full zero-drift Source/runtime/Node/control posthash.
    const expected = @embedFile("extensions/fixtures/ai-oauth-anthropic-openrouter-ae7.json");
    try sdk.put(engine, global, "oauthSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "actual-ae7-OAuth24.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-oauth-anthropic-openrouter-ae7.input.txt") ++
        \\if(oauthSource.sourceHead!=='ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'||oauthSource.count!==24||oauthObservedRows.length!==24||oauthSource.rawRows.length!==24)throw Error('actual Source24 inventory required');
        \\for(let index=0;index<24;index++)if(JSON.stringify(oauthObservedRows[index])!==JSON.stringify(oauthSource.rows[index]))throw Error(JSON.stringify({index,actual:oauthObservedRows[index],expected:oauthSource.rows[index]}));
    , "native-ai-oauth-anthropic-router-Source24.mjs") catch |err| {
        std.debug.print("OAuth Anthropic/OpenRouter Source24: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native AI OAuth Anthropic OpenRouter pending fetch and credential identities survive collection" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const prepared = try engine.evalModule(
        \\const refresh=oauthAPI.anthropic.refresh,toAuth=oauthAPI.openrouter.toAuth,routerRefresh=oauthAPI.openrouter.refresh;delete globalThis.oauthAPI;let release;globalThis.oauthPending={refresh,toAuth,routerRefresh,release:value=>release(value)};globalThis.fetch=()=>new Promise(resolve=>{release=resolve});const signal=new AbortController().signal;oauthPending.work=refresh({refresh:'retained-old'},signal);export const ready=true;
    , "native-ai-oauth-retained-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\oauthPending.release(new Response(JSON.stringify({access_token:'retained-access',refresh_token:'retained-refresh',expires_in:3600})));const credential=await oauthPending.work;if(credential.access!=='retained-access'||credential.refresh!=='retained-refresh')throw Error('retained request');credential.unknown={alive:true};if(await oauthPending.routerRefresh(credential)!==credential||(await oauthPending.toAuth(credential)).apiKey!==credential.access)throw Error('credential identity');delete globalThis.oauthPending;delete globalThis.fetch;export const done=true;
    , "native-ai-oauth-retained-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
