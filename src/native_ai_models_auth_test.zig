const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;

test "native actual Models auth replays genuine Source69 with real defaults and shared imports" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"models-auth-source69"});
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    const Fixture = struct {
        fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            c.JS_RunGC(v.em.Engine.fromContext(context.?).runtime);
            return c.pi_js_undefined();
        }
    };
    try engine.bindFunction("__modelsAuthGC", Fixture.collect, 0);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const models = try s.own(try @import("extensions/native_ai_models_namespace.zig").create(engine));
    const core = try s.object();
    try @import("extensions/native_models.zig").populateExports(engine, core);
    const actual = try s.object();
    inline for (.{ "createModels", "ModelsError" }) |name| try s.put(actual, name, try s.get(models, name));
    try s.put(actual, "InMemoryCredentialStore", try s.get(core, "InMemoryCredentialStore"));
    const credential_constructor = try s.own(try @import("extensions/native_credentials_store.zig").constructor(engine));
    try std.testing.expect(s.equal(credential_constructor, try s.get(core, "InMemoryCredentialStore")));
    const imports = try s.own(try @import("extensions/native_ai_auth_abort.zig").create(engine));
    try s.put(imports, "ModelsError", try s.get(models, "ModelsError"));
    const resolver = try s.own(try @import("extensions/native_ai_auth_resolve.zig").create(engine, imports));
    const resolver_again = try s.own(try @import("extensions/native_ai_auth_resolve.zig").create(engine, imports));
    try std.testing.expect(s.equal(resolver, resolver_again));
    inline for (.{ "resolveProviderAuth", "refreshStoredOAuthCredential" }) |name| try s.put(actual, name, try s.get(resolver, name));
    const helpers = try s.own(try @import("extensions/native_ai_auth_helpers.zig").create(engine));
    try s.put(actual, "envApiKeyAuth", try s.get(helpers, "envApiKeyAuth"));
    try s.put(actual, "anthropicOAuth", try s.own(try @import("extensions/native_ai_oauth_anthropic.zig").create(engine)));
    const api_constructors = try s.own(try @import("extensions/native_ai_builtin_apis.zig").create(engine));
    const factories = try s.own(try @import("extensions/native_ai_provider_factories.zig").create(engine, api_constructors));
    try s.put(actual, "anthropicProvider", try s.get(factories, "anthropicProvider"));
    try engine.registerValueModule("native:actual-models-auth69", actual);
    const global = try s.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));
    const source = @embedFile("extensions/fixtures/models-auth-4954-source.json");
    try s.put(global, "__modelsAuthExpected", try s.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-models-auth-source69.json"))));
    const result = engine.evalModule(@embedFile("extensions/fixtures/models-auth-4954-cases.input.txt") ++
        \\import * as actual from 'native:actual-models-auth69';
        \\const rawErrors=[],key='PI_MODELS_AUTH_4954_KEY',prior=process.env[key],had=Object.hasOwn(process.env,key);
        \\try{
        \\ const fixture={rawError(id,error){rawErrors.push({id,error})},setEnv(name,value){if(name!==key)throw Error('Fixture environment escaped scope');process.env[name]=value},forceGC:__modelsAuthGC};
        \\ const {rows}=await runModelsAuthCases(actual,fixture);
        \\ if(rows.length!==69||__modelsAuthExpected.length!==69||rawErrors.length<10)throw Error('Complete Source69 observations required');
        \\ for(let index=0;index<69;index++)if(JSON.stringify(rows[index])!==JSON.stringify(__modelsAuthExpected[index]))throw Error(JSON.stringify({id:rows[index].id,native:rows[index],source:__modelsAuthExpected[index]}));
        \\ const store=new actual.InMemoryCredentialStore(),other=new actual.InMemoryCredentialStore();
        \\ if(Object.keys(store).join(',')!=='credentials,chains'||Object.getPrototypeOf(store)!==Object.getPrototypeOf(other)||store.read!==other.read||Object.hasOwn(store,'read'))throw Error('Actual ordinary credential class required');
        \\ const value={type:'api_key',key:'borrowed'};other.credentials.set('owned',value);
        \\ if(await store.read.call(other,'owned')!==value)throw Error('Credential read retained hidden bound receiver');
        \\ const m=actual.createModels();if(!(m.credentials instanceof actual.InMemoryCredentialStore))throw Error('Default credential constructor diverged');
        \\ globalThis.__retainedModelsAuth={m,store,other,value,actual};
        \\}finally{if(had)process.env[key]=prior;else delete process.env[key];delete globalThis.__modelsAuthExpected}
    , "native-actual-models-auth-source69.mjs") catch |err| {
        std.debug.print("Actual Models auth Source69: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const retained = try engine.evalModule(
        \\const {m,store,other,value,actual}=__retainedModelsAuth;
        \\if(await store.read.call(other,'owned')!==value||!(m.credentials instanceof actual.InMemoryCredentialStore))throw Error('Credential class roots lost across real GC');
        \\delete globalThis.__retainedModelsAuth;
    , "native-actual-models-auth-after-gc.mjs");
    engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
