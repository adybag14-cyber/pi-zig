const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const js = @import("extensions/native_js_values.zig");
const compat = @import("extensions/native_ai_compat.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    const setup = try engine.evalModule(
        \\globalThis.compatDependencies={models:{getProvider(){return undefined}},streams:{stream(){throw Error('unqualified builtin stream')},streamSimple(){throw Error('unqualified builtin simple')}}};export const ready=true;
    , "compat-caller-dependencies.mjs");
    engine.freeValue(setup);
    const dependencies = try js.global(engine, "compatDependencies");
    defer engine.freeValue(dependencies);
    const streams = try js.get(engine, dependencies, "streams");
    defer engine.freeValue(streams);
    const models = try js.get(engine, dependencies, "models");
    defer engine.freeValue(models);
    const env_module = try @import("extensions/native_ai_env_keys.zig").create(engine, .{});
    defer engine.freeValue(env_module);
    const env = try js.get(engine, env_module, "getEnvApiKey");
    defer engine.freeValue(env);
    var builtins: [compat.builtin_api_ids.len]compat.BuiltinApi = undefined;
    for (compat.builtin_api_ids, &builtins) |id, *entry| entry.* = .{ .api = id, .streams = streams };
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "compatAPI", try compat.create(engine, .{ .builtin_apis = &builtins, .compat_models = models, .get_env_api_key = env }));
}
test "native AI compat matches original b45 registry custom dispatch normalization and async observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/ai-compat-b45.json");
    try sdk.put(engine, global, "compatSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "ai-compat-b45.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-compat-b45.input.txt") ++
        "\nif(compatSource.sourceHead!=='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb'||compatRows.length!==compatSource.rows.length)throw Error('all original observations required');for(let i=0;i<compatRows.length;i++)if(JSON.stringify(compatRows[i])!==JSON.stringify(compatSource.rows[i]))throw Error(JSON.stringify({case:i,actual:compatRows[i],expected:compatSource.rows[i]}));", "native-ai-compat-original.mjs") catch |err| {
        std.debug.print("Compat Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native AI compat controlled builtin dependency routing preserves identity auth and cloudflare fallback" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const result = engine.evalModule(
        \\const calls=[],model={id:'x',provider:'cloudflare-test',api:'openai-completions'},context={messages:[]},opts={env:{OPENAI_API_KEY:'x'}},result={result(){return Promise.resolve('completed')}};
        \\const p={getModels(){return[{api:model.api}]},stream(m,c,o){calls.push(['provider',o]);return result},streamSimple(m,c,o){calls.push(['providerSimple',o]);return result}};
        \\compatDependencies.models.getProvider=()=>p;compatDependencies.models.stream=(m,c,o)=>{calls.push(['models',o]);return result};compatDependencies.models.streamSimple=(m,c,o)=>{calls.push(['modelsSimple',o]);return result};
        \\compatAPI.stream(model,context,opts);if(calls.at(-1)[0]!=='models'||calls.at(-1)[1]!==opts)throw Error('cloudflare fallback');
        \\compatAPI.streamSimple(model,context,{headers:{'cf-aig-authorization':''}});if(calls.at(-1)[0]!=='providerSimple')throw Error('empty header resolves auth');
        \\compatAPI.stream(model,context,{apiKey:' key '});if(calls.at(-1)[0]!=='provider')throw Error('explicit key direct provider');
        \\compatAPI.streamSimple(model,context,{apiKey:'   '});if(calls.at(-1)[0]!=='modelsSimple')throw Error('blank key fallback');
        \\compatAPI.registerApiProvider({api:model.api,stream(){calls.push(['override']);return result},streamSimple(){calls.push(['overrideSimple']);return result}});compatAPI.stream(model,context);if(calls.at(-1)[0]!=='override')throw Error('override disables builtin');
        \\compatAPI.registerBuiltInApiProviders();compatAPI.streamSimple(model,context,{apiKey:'key'});if(calls.at(-1)[0]!=='providerSimple')throw Error('original explicit builtin registration updates identity marker');
        \\if(await compatAPI.completeSimple(model,context,{apiKey:'key'})!=='completed')throw Error('completeSimple actual binding');export const proof=true;
    , "native-ai-compat-controlled-builtins.mjs") catch |err| {
        std.debug.print("Compat routing: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native AI compat retained registry wrappers survive garbage collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule(
        \\compatAPI.registerApiProvider({api:'kept',stream(){return{result(){return Promise.resolve('kept')}}},streamSimple(){return{result(){return Promise.resolve('simple')}}}},'kept-source');globalThis.keptCompat=compatAPI;globalThis.keptWrapper=compatAPI.getApiProvider('kept').stream;delete globalThis.compatAPI;delete globalThis.compatDependencies;export const ready=true;
    , "native-ai-compat-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const result = try engine.evalModule(
        \\if(await keptCompat.completeSimple({api:'kept',provider:'custom'},{messages:[]})!=='simple'||await keptWrapper({api:'kept'},{messages:[]}).result()!=='kept')throw Error('retained native graph');keptCompat.unregisterApiProviders('kept-source');if(keptCompat.getApiProvider('kept')!==undefined)throw Error('retained removal');delete globalThis.keptCompat;delete globalThis.keptWrapper;export const done=true;
    , "native-ai-compat-gc-complete.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native AI compat UUID uses actual secure native Crypto byte views and retained host roots" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/dom_exception.zig").install(engine);
    try @import("extensions/native_crypto_random.zig").install(engine);
    try @import("extensions/native_bigint_host.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "secureUUID", try @import("extensions/native_ai_uuid.zig").create(engine));
    const result = engine.evalModule(
        \\const buffer=new Uint8Array(96).fill(165),view=new Uint32Array(buffer.buffer,16,16);if(crypto.getRandomValues(view)!==view||buffer.slice(0,16).some(x=>x!==165)||buffer.slice(80).some(x=>x!==165)||buffer.slice(16,80).every(x=>x===165))throw Error('secure view identity or bounds');
        \\for(const Type of [Int8Array,Uint8Array,Uint8ClampedArray,Int16Array,Uint16Array,Int32Array,Uint32Array,BigInt64Array,BigUint64Array]){const a=new Type(3);if(crypto.getRandomValues(a)!==a)throw Error('integer view');}if(crypto.getRandomValues(new Uint8Array(0)).length!==0)throw Error('empty view');
        \\for(const a of [new Float32Array(1),new Float64Array(1),new DataView(new ArrayBuffer(8)),[],{},null])try{crypto.getRandomValues(a);throw Error('invalid accepted')}catch(e){if(e.name!=='TypeMismatchError'||e.code!==17)throw e;}
        \\try{crypto.getRandomValues(new Uint8Array(65537));throw Error('quota accepted')}catch(e){if(e.name!=='QuotaExceededError'||e.code!==22)throw e;}
        \\const a=secureUUID(100),b=secureUUID(100);if(!(a<b)||a.slice(0,13)!=='00000000-0064'||a.length!==36||a[14]!=='7'||!['8','9','a','b'].includes(a[19]))throw Error('native secure UUID');globalThis.keptCrypto=crypto;delete globalThis.crypto;export const proof=true;
    , "native-ai-compat-secure-uuid.mjs") catch |err| {
        std.debug.print("Secure crypto: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const retained = try engine.evalModule("if(keptCrypto.getRandomValues(new Uint8Array(16)).length!==16)throw Error('retained CSPRNG');delete globalThis.keptCrypto;delete globalThis.secureUUID;export const done=true;", "native-ai-compat-secure-gc.mjs");
    engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
test "native AI compat every host allocation releases registry wrappers env dispatch async completion and secure host roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            engine.native_io = std.testing.io;
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            @import("extensions/dom_exception.zig").install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            @import("extensions/native_crypto_random.zig").install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const shared={},model={api:'owned',provider:'openai'},messages=[{role:'user',content:'hello'}],options={env:{OPENAI_API_KEY:'caller-key'}};
                \\compatAPI.registerApiProvider({api:'owned',stream(m,c,o){if(c.messages[0]!==messages[0]||o.apiKey!=='caller-key')throw Error('dispatch');return{result(){return Promise.resolve(shared)}}},streamSimple(){return{result(){return Promise.resolve(shared)}}}},'owned-source');
                \\if(await compatAPI.complete(model,{messages},options)!==shared||await compatAPI.completeSimple(model,{messages})!==shared||compatAPI.getApiProviders().at(-1).api!=='owned')throw Error('owned graph');
                \\const wrapper=compatAPI.getApiProvider('owned').stream;compatAPI.unregisterApiProviders('owned-source');if(compatAPI.getApiProvider('owned')!==undefined||await wrapper(model,{messages},{apiKey:'caller-key'}).result()!==shared)throw Error('retained wrapper');
                \\compatAPI.resetApiProviders();if(compatAPI.getApiProviders().length!==10)throw Error('reset');const bytes=new Uint8Array(32);if(crypto.getRandomValues(bytes)!==bytes)throw Error('secure graph');export const proof=true;
            , "native-ai-compat-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
test "native AI compat emitted test inventory is explicit" {
    for (@import("builtin").test_functions) |entry| std.debug.print("AI_COMPAT_TEST={s}\n", .{entry.name});
}
