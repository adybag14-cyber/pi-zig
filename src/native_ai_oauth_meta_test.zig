const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    try @import("extensions/native_url.zig").install(engine);
    try @import("extensions/abort_signal.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "metaOAuth", try @import("extensions/native_ai_oauth_meta.zig").create(engine));
}
test "native AI Meta OAuth matches original ae7 controlled authorization polling mint and credential observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/ai-oauth-meta-ae7.json");
    try sdk.put(engine, global, "metaOAuthSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "ai-oauth-meta-ae7.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-oauth-meta-ae7.input.txt") ++
        "\nif(metaOAuthSource.sourceHead!=='ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'||metaOAuthRows.length!==metaOAuthSource.rows.length)throw Error('original Meta Source authority');for(let i=0;i<metaOAuthRows.length;i++)if(JSON.stringify(metaOAuthRows[i])!==JSON.stringify(metaOAuthSource.rows[i]))throw Error(JSON.stringify({case:i,actual:metaOAuthRows[i],expected:metaOAuthSource.rows[i]}));", "native-ai-oauth-meta-source.mjs") catch |err| {
        std.debug.print("Meta OAuth Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native AI Meta OAuth asynchronous credential roots survive collection and preserve access identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepare = try engine.evalModule(
        \\globalThis.metaHeld=metaOAuth;delete globalThis.metaOAuth;globalThis.metaAccess={tag:'held'};globalThis.metaAuthPending=metaHeld.toAuth({access:metaAccess});globalThis.metaFetchResolve=undefined;globalThis.fetch=()=>new Promise(resolve=>{metaFetchResolve=resolve;});globalThis.metaRefreshPending=metaHeld.refresh({refresh:'controlled-gc-identity'},new AbortController().signal);export const prepared=true;
    , "native-ai-meta-gc-prepare.mjs");
    engine.freeValue(prepare);
    c.JS_RunGC(engine.runtime);
    const complete = try engine.evalModule(
        \\metaFetchResolve({status:200,ok:true,json:async()=>({api_key:'controlled-gc-key'})});if((await metaAuthPending).apiKey!==metaAccess)throw Error('access identity lost');const credential=await metaRefreshPending;if(credential.refresh!=='controlled-gc-identity'||credential.access!=='controlled-gc-key'||credential.type!=='oauth')throw Error('refresh roots lost');delete globalThis.fetch;delete globalThis.metaHeld;delete globalThis.metaAccess;delete globalThis.metaAuthPending;delete globalThis.metaRefreshPending;delete globalThis.metaFetchResolve;export const complete=true;
    , "native-ai-meta-gc-complete.mjs");
    engine.freeValue(complete);
    c.JS_RunGC(engine.runtime);
}
