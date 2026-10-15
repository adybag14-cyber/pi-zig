const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
fn install(engine: *v.em.Engine) !void {
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const helpers = try scope.own(try @import("extensions/native_ai_auth_helpers.zig").create(engine));
    const context = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return @import("extensions/native_ai_auth_helpers.zig").defaultProviderAuthContext(host);
        }
    };
    try scope.put(helpers, "defaultProviderAuthContext", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "defaultProviderAuthContext", 0, context.call, &.{})));
    const device = try scope.own(try @import("extensions/native_ai_oauth_device_code.zig").create(engine));
    inline for (.{ "abortableSleep", "pollOAuthDeviceCodeFlow" }) |name| try scope.put(helpers, name, try scope.get(device, name));
    try engine.registerValueModule("native:auth-helper-fixture", helpers);
}
test "native AI auth helpers preserve credential identity iterator close async loader and owned file behavior" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &path_buffer);
    const path = try std.fs.path.join(std.testing.allocator, &.{ path_buffer[0..length], "owned-auth-helper-input.txt" });
    defer std.testing.allocator.free(path);
    var source: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer source.deinit();
    try source.writer.writeAll(@embedFile("extensions/native_ai_auth_helpers_fixture.mjs"));
    try source.writer.writeAll("\nimport * as api from 'native:auth-helper-fixture';import fs from 'node:fs';const path=");
    try std.json.Stringify.value(path, .{}, &source.writer);
    try source.writer.writeAll(
        \\;fs.writeFileSync(path,'owned fixture only');export const rows=await run(api,path);
        \\const byCase=Object.fromEntries(rows.map(row=>[row.case,row]));
        \\if(rows.length!==16)throw Error('all helper cases required');
        \\if(!byCase['stored-getters'].sameEnv||byCase['stored-getters'].result.auth.apiKey!=='owned-stored-key')throw Error('stored identity');
        \\if(!byCase['abort-closes-preserving'].sameReason||byCase['abort-closes-preserving'].log.join(',')!=='return')throw Error('abort close identity');
        \\if(byCase['login-sync-failure-is-async'].syncThrow||!byCase['login-sync-failure-is-async'].sameReason)throw Error('async rejection');
        \\if(byCase['lazy-load-delegation'].loads!==1||!byCase['lazy-load-delegation'].identity)throw Error('lazy coalescing');
        \\if(byCase['lazy-rejection-cached'].loads!==1||byCase['lazy-sync-throw-retries'].loads!==2||byCase['lazy-nullish-retries'].loads!==2)throw Error('lazy promise semantics');
        \\if(!byCase['default-context-owned-file'].exists||byCase['default-context-owned-file'].missing||byCase['default-context-owned-file'].invalid)throw Error('owned file context');
        \\if(byCase['device-poll-intervals'].value!=='owned-device-result'||byCase['device-sleep-preabort'].message!=='Owned cancel')throw Error('device polling');
    );
    const namespace = engine.evalModule(source.written(), "native-auth-helpers-owned-fixture.mjs") catch |err| {
        std.debug.print("Auth helpers native: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(namespace);
    c.JS_RunGC(engine.runtime);
}
test "native AI auth helpers retain captured guest values and promises through real collection" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const first = try engine.evalModule(
        \\import * as api from 'native:auth-helper-fixture';
        \\globalThis.ownedAuth=api.envApiKeyAuth({toString(){return 'Owned retained'}},['OWNED_ONLY']);
        \\globalThis.ownedDeferred=api.lazyOAuth({name:'Owned retained OAuth',load(){return new Promise(resolve=>{globalThis.ownedRelease=resolve})}});
        \\globalThis.ownedPending=ownedDeferred.toAuth({access:'owned-retained-access'});
    , "native-auth-helpers-retain-before-gc.mjs");
    engine.freeValue(first);
    c.JS_RunGC(engine.runtime);
    const second = try engine.evalModule(
        \\const signal={throwIfAborted(){}};
        \\if((await ownedAuth.login({signal,async prompt(value){if(value.message!=='Enter Owned retained')throw Error('lost name');return 'owned-retained-key'}})).key!=='owned-retained-key')throw Error('lost login');
        \\ownedRelease({async toAuth(credential){return {apiKey:credential.access}}});
        \\if((await ownedPending).apiKey!=='owned-retained-access')throw Error('lost pending roots');
        \\delete globalThis.ownedAuth;delete globalThis.ownedDeferred;delete globalThis.ownedRelease;delete globalThis.ownedPending;
    , "native-auth-helpers-retain-after-gc.mjs");
    engine.freeValue(second);
    c.JS_RunGC(engine.runtime);
}
