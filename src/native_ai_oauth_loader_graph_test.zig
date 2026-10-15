const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const loader = @import("extensions/native_ai_oauth_loader.zig");

fn setup() !*v.em.Engine {
    const engine = try @import("extensions/native_web_response_test.zig").setup(std.testing.allocator);
    errdefer engine.deinit();
    try @import("extensions/native_web_crypto.zig").install(engine);
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/node_buffer.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = try scope.own(try loader.namespace(engine));
    const second = try scope.own(try loader.namespace(engine));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    try engine.registerValueModule("native:oauth-load", first);
    try engine.registerValueModule("native:oauth-helpers", try scope.own(try @import("extensions/native_ai_auth_helpers.zig").create(engine)));
    return engine;
}

test "native OAuth loader graph actual nine modules singleton and bundled delegation" {
    const engine = try setup();
    defer engine.deinit();
    const result = engine.evalModule(@embedFile("extensions/native_ai_oauth_loader_fixture.mjs") ++
        \\import * as api from 'native:oauth-load';import {lazyOAuth} from 'native:oauth-helpers';
        \\export const rows=await run(api,lazyOAuth);
        \\if(rows.length!==18||new Set(rows.map(row=>row.case)).size!==18)throw Error('OAuth graph inventory');
        \\for(const row of rows.filter(row=>row.case.startsWith('load')))if(!row.same)throw Error('module singleton '+row.case);
        \\const byCase=Object.fromEntries(rows.map(row=>[row.case,row]));
        \\if(!byCase['radius-fresh-factory'].fresh||!byCase['radius-fresh-factory'].accessIdentity)throw Error('Radius factory identity');
        \\if(!byCase['lazy-loader-coalesces'].identity||byCase['lazy-loader-coalesces'].loads!==1)throw Error('lazy loader coalescing');
        \\if(byCase['bundled-getter-rejection'].sync||!byCase['bundled-getter-rejection'].sameReason)throw Error('bundled async error identity');
        \\if(!byCase['bundled-radius-options'].sameOptions||!byCase['bundled-radius-options'].sameReceiver)throw Error('raw options and receiver');
    , "native-oauth-nine-flow-graph.mjs") catch |err| {
        std.debug.print("OAuth loader graph: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native OAuth loader graph retained import cache survives actual GC" {
    const engine = try setup();
    defer engine.deinit();
    const pending = try engine.evalModule(
        \\import * as api from 'native:oauth-load';globalThis.heldOAuthNamespace=api;
        \\globalThis.heldMetaPromise=api.loadMetaOAuth();globalThis.heldRadiusPromise=api.loadRadiusOAuth({name:'Owned GC Radius',gateway:'owned.invalid'});
    , "native-oauth-graph-before-gc.mjs");
    engine.freeValue(pending);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const meta=await heldMetaPromise;if(meta!==await heldOAuthNamespace.loadMetaOAuth())throw Error('cached module roots');
        \\const radius=await heldRadiusPromise;const credential={owned:true};if((await radius.toAuth({access:credential})).apiKey!==credential)throw Error('factory roots');
        \\delete globalThis.heldMetaPromise;delete globalThis.heldRadiusPromise;delete globalThis.heldOAuthNamespace;
    , "native-oauth-graph-after-gc.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
