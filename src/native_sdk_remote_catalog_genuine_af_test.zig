//! Authored controls over actual RemoteCatalog, model, management HTTP, and
//! native platform/configuration owners. Runtime qualification is separate.
const std = @import("std");
const x = @import("extensions/native_sdk_catalog_values.zig");
const c = x.c;
const catalog = @import("extensions/native_sdk_remote_catalog_provider.zig");
const bootstrap = @import("extensions/native_sdk_application_bootstrap.zig");
const config_module_url = "file:///C:/Users/adyba/pi-zig/upstream/pi/packages/coding-agent/src/config.ts";
fn publish(o: *x.Ops, name: [*:0]const u8, value: c.JSValue) !void {
    const root = try o.own(c.JS_GetGlobalObject(o.s.engine.context));
    try o.put(root, name, value);
}
fn prepare(engine: *x.em.Engine, environment: *const std.process.Environ.Map) !void {
    try bootstrap.installPlatform(engine, std.testing.io, environment, &.{"actual-remote-catalog-controls"});
    var storage: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &storage };
    return x.owned.finishVoid(&storage, prepareBody(&o));
}
fn prepareBody(o: *x.Ops) !void {
    const engine = o.s.engine;
    const platform = try o.own(try @import("extensions/native_sdk_filesystem_namespaces.zig").createPlatform(engine));
    const os = engine.native_module_values.get("node:os") orelse return error.RequiredActualOsNamespace;
    const url = engine.native_module_values.get("node:url") orelse return error.RequiredActualUrlNamespace;
    const configuration = try o.own(try @import("extensions/native_sdk_configuration_production.zig").create(engine, .{
        .process = try o.global("process"),
        .paths = try o.get(platform, "paths"),
        .filesystem = try o.get(platform, "filesystem"),
        .os = os,
        .url = url,
        .path_utilities = try o.get(platform, "pathUtilities"),
        .module_url = try o.text(config_module_url),
        .user_agent_runtime = .native_zig,
    }));
    const models = try o.own(try @import("extensions/native_ai_models_namespace.zig").create(engine));
    const http = try o.own(try @import("extensions/native_sdk_management_http.zig").create(engine));
    const namespace = try o.own(try catalog.create(engine, .{
        .get_model_type = try o.get(models, "getModelType"),
        .is_model_type = try o.get(models, "isModelType"),
        .fetch_with_retry = try o.get(http, "fetchWithRetry"),
        .get_pi_user_agent = try o.get(configuration, "getPiUserAgent"),
        .version = try o.get(configuration, "VERSION"),
    }));
    try publish(o, "actualRemoteCatalog", namespace);
    try publish(o, "actualRemoteConfiguration", configuration);
    try publish(o, "actualRemoteModels", models);
    try publish(o, "actualRemoteHttp", http);
}
fn run(engine: *x.em.Engine, tail: []const u8) !void {
    const source = try std.mem.concat(engine.gpa, u8, &.{@embedFile("extensions/fixtures/sdk-remote-catalog-genuine-af-observer.mjs"), "\n", tail});
    defer engine.gpa.free(source);
    const namespace = try engine.evalModule(source, "actual-remote-catalog-caller.mjs");
    engine.freeValue(namespace);
}
fn eval(engine: *x.em.Engine, source: []const u8, name: [:0]const u8) !void {
    const namespace = try engine.evalModule(source, name); engine.freeValue(namespace);
}
test "SDK RemoteCatalog actual AF metadata and genuine imported owners" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try prepare(engine, &environment);
    var storage: x.Scope = .{ .engine = engine }; defer storage.deinit(); var o: x.Ops = .{ .s = &storage };
    const wrapped = try o.own(try engine.eval("actualRemoteCatalog.withRemoteCatalog({id:'actual',getModels(){return[]}})", "actual-remote-metadata.js", c.JS_EVAL_TYPE_GLOBAL));
    const function = try o.get(wrapped, "refreshModels");
    try std.testing.expect(c.JS_IsAsyncFunction(function));
    try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
    try std.testing.expect(o.equal(try o.get(function, "name"), try o.text("refreshModels")));
    try std.testing.expect(o.equal(try o.get(function, "length"), c.JS_NewInt32(engine.context, 1)));
    const imports = try o.global("actualRemoteModels");
    try std.testing.expect(o.equal(try o.get(imports, "getModelType"), try o.get(engine.native_ai_model_operations_namespace.?, "getModelType")));
    const http = try o.global("actualRemoteHttp");
    try std.testing.expect(c.JS_IsAsyncFunction(try o.get(http, "fetchWithRetry")));
    const actual_http = try o.own(try @import("extensions/native_sdk_management_http.zig").create(engine));
    try std.testing.expect(o.equal(http, actual_http));
    try eval(engine,
        \\import fs from'node:fs';const config=actualRemoteConfiguration;
        \\const pkg=JSON.parse(fs.readFileSync(config.getPackageJsonPath(),'utf8'));
        \\if(config.VERSION!==pkg.version||config.PACKAGE_NAME!==pkg.name)throw Error('real package configuration required');
        \\if(!config.getPiUserAgent(config.VERSION).startsWith('pi/'+pkg.version+' ('))throw Error('real native user agent');
        \\if(actualRemoteCatalog.REMOTE_CATALOG_REFRESH_INTERVAL_MS!==14400000||actualRemoteCatalog.REMOTE_CATALOG_MODEL_TYPES.join(',')!=='chat,image,classifier')throw Error('actual catalog constants');
    , "actual-remote-import-identities.mjs");
}
test "SDK RemoteCatalog actual restore publication Await offline and freshness gates" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try prepare(engine, &environment);
    try run(engine, "export const rows=await observeRemoteOffline(actualRemoteCatalog);");
}
test "SDK RemoteCatalog actual request retry parse status and post-publication error order" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try prepare(engine, &environment);
    try run(engine, "export const rows=await observeRemoteNetwork(actualRemoteCatalog,actualRemoteConfiguration.getPiUserAgent(actualRemoteConfiguration.VERSION));");
}
test "SDK RemoteCatalog actual personalized replacement empty fallback and abort gates" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try prepare(engine, &environment);
    try run(engine, "export const rows=await observePersonalizedCatalog(actualRemoteCatalog);");
}
test "SDK RemoteCatalog actual independent async continuations and thenable rejection identity" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try prepare(engine, &environment);
    try run(engine, "export const rows=await observeRemoteConcurrent(actualRemoteCatalog);");
}
test "SDK RemoteCatalog actual spread and live iterator close precedence" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try prepare(engine, &environment);
    try run(engine, "export const rows=await observeRemoteSpreadAndIteration(actualRemoteCatalog);");
}
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?); _ = engine.throwNativeOutOfMemory(); return c.JS_GetException(context);
}
fn actualB(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?); _ = engine.checked(engine.throwNativeOutOfMemoryFatal()) catch {};
    const root = c.JS_GetGlobalObject(context); defer engine.freeValue(root);
    _ = c.JS_DefinePropertyValueStr(context, root, "observedRemoteB", c.JS_DupValue(context, engine.captured_exception.?), c.JS_PROP_C_W_E);
    return c.pi_js_undefined();
}
fn rawRead(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const root = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(root);
    return engine.checked(c.JS_GetPropertyStr(engine.context, root, name));
}
test "SDK RemoteCatalog SAME publish callback DATA A remains ordinary and actual B1 wins" {
    inline for (.{false, true}) |fatal| {
        var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
        const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine, &environment);
        try engine.bindFunction("remotePrivateData", privateData, 0); try engine.bindFunction("remoteActualB", actualB, 0);
        const prefix = "globalThis.remoteA=undefined;globalThis.remoteCaught=undefined;const wrapper=actualRemoteCatalog.withRemoteCatalog({id:'actual',getModels(){return[]}});try{await wrapper.refreshModels({publish(){remoteA=remotePrivateData();";
        const source = try std.mem.concat(engine.gpa, u8, &.{prefix, if (fatal) "remoteActualB();" else "", "throw remoteA}})}catch(error){remoteCaught=error}export const completed=true;"}); defer engine.gpa.free(source);
        const outcome = engine.evalModule(source, "actual-remote-publish-current-vs-data.mjs");
        if (fatal) {
            if (outcome) |value| {engine.freeValue(value);return error.ActualRemoteFatalWasSwallowed;} else |err| try std.testing.expect(err == error.JavaScriptException);
            const chosen = engine.captured_exception orelse return error.RequiredActualRemoteFatal;
            const b = try rawRead(engine, "observedRemoteB"); defer engine.freeValue(b);
            const a = try rawRead(engine, "remoteA"); defer engine.freeValue(a);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, chosen, b));
            try std.testing.expect(!c.JS_IsStrictEqual(engine.context, a, b));
        } else {
            const value = try outcome; engine.freeValue(value);
            const a = try rawRead(engine, "remoteA"); defer engine.freeValue(a);
            const caught = try rawRead(engine, "remoteCaught"); defer engine.freeValue(caught);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, caught)); try std.testing.expect(!c.JS_IsUncatchableError(a));
        }
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
fn gc(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(x.em.Engine.fromContext(context.?).runtime); return c.pi_js_undefined();
}
test "SDK RemoteCatalog prior job condition and method temporaries retire before downstream getters" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try prepare(engine, &environment);
    try engine.bindFunction("actualRemoteGc", gc, 0);
    try eval(engine,
        \\let condition={owned:'first type'},parse=function(){return 1000},isNan=function(){return false};
        \\globalThis.remoteConditionWeak=new WeakRef(condition);globalThis.remoteParseWeak=new WeakRef(parse);globalThis.remoteIsNanWeak=new WeakRef(isNan);
        \\globalThis.takeRemoteCondition=()=>{const value=condition;condition=undefined;return value};
        \\globalThis.takeRemoteParse=()=>{const value=parse;parse=undefined;return value};
        \\globalThis.takeRemoteIsNan=()=>{const value=isNan;isNan=undefined;return value};
    , "actual-remote-prior-job.mjs");
    // evalModule already drained this preparation job through Engine.awaitValue.
    // Keep Engine.finishJob's actual async/job ownership gate authoritative.
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try run(engine,
        \\const parseDescriptor=Object.getOwnPropertyDescriptor(Date,'parse'),nanDescriptor=Object.getOwnPropertyDescriptor(Number,'isNaN');let reads=0;
        \\const model={id:'lifetime',get type(){if(reads++===0)return takeRemoteCondition();actualRemoteGc();if(remoteConditionWeak.deref()!==undefined)throw Error('condition value retained');return'chat'}};
        \\try{Object.defineProperty(Date,'parse',{configurable:true,get(){return takeRemoteParse()}});
        \\Object.defineProperty(Number,'isNaN',{configurable:true,get(){return takeRemoteIsNan()}});
        \\await withFetch(()=>({status:200,ok:true,get headers(){return{get(name){if(name==='etag'){actualRemoteGc();if(remoteIsNanWeak.deref()!==undefined)throw Error('Number predicate retained')}return null}}},json(){actualRemoteGc();if(remoteParseWeak.deref()!==undefined)throw Error('Date.parse retained');return[model]}}),async()=>{
        \\const wrapped=actualRemoteCatalog.withRemoteCatalog({id:'actual',getModels(){return[]}});
        \\await wrapped.refreshModels({force:true,allowNetwork:true,signal:new AbortController().signal,publish(record){record.update?.();return true}});
        \\});}finally{Object.defineProperty(Date,'parse',parseDescriptor);Object.defineProperty(Number,'isNaN',nanDescriptor)}
        \\if(reads<3)throw Error('all Source type condition reads required');
    );
}

fn flaggedData(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const value = privateData(context, receiver, argc, args);
    c.JS_SetUncatchableError(context, value);
    return value;
}
test "SDK RemoteCatalog successful flagged Error constructor value rejects as DATA" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try prepare(engine, &environment);
    try engine.bindFunction("remoteFlaggedData", flaggedData, 0);
    try run(engine,
        \\const descriptor=Object.getOwnPropertyDescriptor(globalThis,'Error'),OriginalError=Error;
        \\globalThis.remoteErrorData=remoteFlaggedData();globalThis.remoteErrorCaught=undefined;let constructors=0,publishes=0;
        \\try{Object.defineProperty(globalThis,'Error',{configurable:true,writable:true,value:function Error(){constructors++;return remoteErrorData}});
        \\await withFetch(()=>({status:200,ok:true,headers:{get(){return null}},json(){return 17}}),async()=>{
        \\const wrapped=actualRemoteCatalog.withRemoteCatalog({id:'actual',getModels(){return[]}});
        \\try{await wrapped.refreshModels({force:true,allowNetwork:true,signal:new AbortController().signal,publish(record){publishes++;record.update?.();return true}})}
        \\catch(error){remoteErrorCaught=error}
        \\});}finally{Object.defineProperty(globalThis,'Error',descriptor)}
        \\if(constructors!==1||publishes!==1||remoteErrorCaught!==remoteErrorData)throw new OriginalError('Source Error-constructor DATA completion');
    );
    const data = try rawRead(engine, "remoteErrorData"); defer engine.freeValue(data);
    const caught = try rawRead(engine, "remoteErrorCaught"); defer engine.freeValue(caught);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, data, caught));
    try std.testing.expect(c.JS_IsUncatchableError(data));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(data) != 0);
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
