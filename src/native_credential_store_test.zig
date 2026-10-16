const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;

test "native actual credential store replays genuine Source20 ordinary class queue and cancellation observations" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const constructor = try s.own(try @import("extensions/native_credentials_store.zig").constructor(engine));
    const second = try s.own(try @import("extensions/native_credentials_store.zig").constructor(engine));
    try std.testing.expect(s.equal(constructor, second));
    const prototype = try s.get(constructor, "prototype");
    inline for (.{ "enqueue", "read", "list", "modify", "delete" }) |name| {
        const method = try s.get(prototype, name);
        try std.testing.expect(!c.JS_IsConstructor(engine.context, method));
        try std.testing.expectEqual(std.mem.eql(u8, name, "read") or std.mem.eql(u8, name, "list"), c.JS_IsAsyncFunction(method));
    }
    const exports = try s.object();
    try s.put(exports, "InMemoryCredentialStore", constructor);
    try engine.registerValueModule("native:credential-store-source20", exports);
    const global = try s.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));
    const source = @embedFile("extensions/fixtures/credential-store-4954-source.json");
    try s.put(global, "__credentialStoreExpected", try s.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-credential-store-source20.json"))));
    const result = engine.evalModule(@embedFile("extensions/fixtures/credential-store-4954-cases.input.txt") ++
        \\import * as actual from 'native:credential-store-source20';
        \\const rawErrors=[],{rows}=await runCredentialStoreCases(actual,{rawError(id,error){rawErrors.push({id,error})}});
        \\if(rows.length!==20||__credentialStoreExpected.length!==20||rawErrors.length!==6)throw Error('Complete genuine Source20 observations required');
        \\for(let index=0;index<20;index++)if(JSON.stringify(rows[index])!==JSON.stringify(__credentialStoreExpected[index]))throw Error(JSON.stringify({id:rows[index].id,native:rows[index],source:__credentialStoreExpected[index]}));
        \\globalThis.__retainedCredentialStore=new actual.InMemoryCredentialStore();
        \\globalThis.__retainedCredentialConstructor=actual.InMemoryCredentialStore;
        \\globalThis.__retainedCredentialValue={type:'api_key',key:'retained',unknown:{identity:true}};
        \\await __retainedCredentialStore.modify('p',async()=>__retainedCredentialValue);
        \\delete globalThis.__credentialStoreExpected;
    , "native-actual-credential-store-source20.mjs") catch |err| {
        std.debug.print("Actual credential store Source20: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const retained = try engine.evalModule(
        \\if(!(__retainedCredentialStore instanceof __retainedCredentialConstructor)||await __retainedCredentialStore.read('p')!==__retainedCredentialValue)throw Error('Credential constructor and values lost through real GC');
        \\await __retainedCredentialStore.delete('p');if(await __retainedCredentialStore.read('p')!==undefined)throw Error('Credential prototype method lost after GC');
        \\delete globalThis.__retainedCredentialStore;delete globalThis.__retainedCredentialConstructor;delete globalThis.__retainedCredentialValue;
    , "native-actual-credential-store-after-gc.mjs");
    engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
