//! Prepared native controls. Actual composed namespaces/runtime/physical fixtures
//! are inputs; no fake jiti, registry, resource loader or runtime is assembled.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const cache = @import("extensions/native_sdk_extension_cache.zig");
const c = em.c;
fn install(engine: *em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, name, c.JS_DupValue(engine.context, value));
}
pub fn verifyBrands(engine: *em.Engine, actual_loader: c.JSValue) !void {
    inline for (.{ "loadExtensions", "loadExtensionsCached", "loadExtensionFromFactory" }) |name| {
        const function = try js.get(engine, actual_loader, name); defer engine.freeValue(function);
        try std.testing.expect(c.JS_IsAsyncFunction(function) != 0);
        try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
        const length = try js.get(engine, function, "length"); defer engine.freeValue(length);
        var count: i32 = 0;
        if (c.JS_ToInt32(engine.context, &count, length) < 0) return js.capture(engine);
        try std.testing.expectEqual(@as(i32, 4), count);
    }
}
pub fn verifyRealEmptyInitialization(engine: *em.Engine, actual_loader: c.JSValue, actual_cwd: c.JSValue, actual_mcp_constructor: c.JSValue) !void {
    try install(engine, "ActualExtensionLoader", actual_loader);
    try install(engine, "ActualExtensionCwd", actual_cwd);
    try install(engine, "ActualMcpRegistry", actual_mcp_constructor);
    const result = try engine.evalModule(
        \\const first=await ActualExtensionLoader.loadExtensionsCached([],ActualExtensionCwd);
        \\const second=await ActualExtensionLoader.loadExtensionsCached([],ActualExtensionCwd);
        \\if(Object.keys(first).join()!=='extensions,errors,warnings,runtime')throw Error('result key order');
        \\if(first.extensions.length||first.errors.length||first.warnings.length)throw Error('empty lists');
        \\if(first.runtime===second.runtime||!(first.runtime.flagValues instanceof Map)||!(first.runtime.mcpServers instanceof ActualMcpRegistry))throw Error('actual runtime initialization');
        \\let message;try{first.runtime.sendMessage({})}catch(error){message=error.message}
        \\if(message!=='Extension runtime not initialized. Action methods cannot be called during extension loading.')throw Error('original pre-bind runtime');
        \\const explicit=await ActualExtensionLoader.loadExtensions([],ActualExtensionCwd,undefined,first.runtime);
        \\if(explicit.runtime!==first.runtime)throw Error('explicit runtime identity');
        \\export const passed=true;
    , "extension-loader-real-empty-initialization.mjs");
    defer engine.freeValue(result);
}
pub fn verifyPathAndIteratorReasons(engine: *em.Engine, actual_loader: c.JSValue, actual_cwd: c.JSValue, actual_bus: c.JSValue, actual_runtime: c.JSValue) !void {
    try install(engine, "ActualExtensionLoader", actual_loader);
    try install(engine, "ActualExtensionCwd", actual_cwd);
    try install(engine, "ActualExtensionBus", actual_bus);
    try install(engine, "ActualExtensionRuntime", actual_runtime);
    const result = try engine.evalModule(
        \\const reason={iterator:true};let closes=0,escaped=false,pending;
        \\const paths={[Symbol.iterator](){return{next(){throw reason},return(){closes++;return{done:true}}}}};
        \\try{pending=ActualExtensionLoader.loadExtensionsCached(paths,ActualExtensionCwd,ActualExtensionBus,ActualExtensionRuntime)}catch{escaped=true}
        \\let caught;try{await pending}catch(error){caught=error}
        \\if(escaped||caught!==reason||closes!==0)throw Error('IteratorStep raw identity/close boundary');
        \\const pathReason={path:true};const path={replace(){throw pathReason}};
        \\caught=undefined;try{await ActualExtensionLoader.loadExtensions([path],ActualExtensionCwd,ActualExtensionBus,ActualExtensionRuntime)}catch(error){caught=error}
        \\if(caught!==pathReason)throw Error('resolvePath outside per-extension catch');
        \\export const passed=true;
    , "extension-loader-iterator-path-reasons.mjs");
    defer engine.freeValue(result);
}
fn emptyCapture(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    if (engine.captured_exception != null) return error.ExtensionHandledReasonStillCaptured;
    return c.pi_js_undefined();
}
/// Observer wraps the real runtime subscription method; the actual event bus,
/// tracking closure, transactional API and discard implementation all run.
pub fn verifyDiscardOwnership(engine: *em.Engine, actual_loader: c.JSValue, actual_cwd: c.JSValue, actual_bus: c.JSValue, actual_runtime: c.JSValue) !void {
    try install(engine, "ActualExtensionLoader", actual_loader);
    try install(engine, "ActualExtensionCwd", actual_cwd);
    try install(engine, "ActualExtensionBus", actual_bus);
    try install(engine, "ActualExtensionRuntime", actual_runtime);
    const observer = try @import("extensions/native_node_function.zig").create(engine, "assertExtensionCaptureEmpty", 0, emptyCapture, &.{}); defer engine.freeValue(observer);
    try install(engine, "assertExtensionCaptureEmpty", observer);
    const result = try engine.evalModule(
        \\const runtime=ActualExtensionRuntime,original=runtime.trackEventBusSubscription;
        \\const reason={factory:true},discardReason={discard:true};let cleanups=0,override=false;
        \\runtime.trackEventBusSubscription=function(unsubscribe){return original.call(this,()=>{assertExtensionCaptureEmpty();cleanups++;unsubscribe();if(override)throw discardReason})};
        \\try{
        \\ for(const resumed of[false,true]){
        \\  const factory=pi=>{pi.events.on('loader-ownership',()=>{});if(resumed)return Promise.reject(reason);throw reason};
        \\  let caught;try{await ActualExtensionLoader.loadExtensionFromFactory(factory,ActualExtensionCwd,ActualExtensionBus,runtime)}catch(error){caught=error}
        \\  if(caught!==reason)throw Error('factory ordinary reason identity');assertExtensionCaptureEmpty();
        \\ }
        \\ override=true;let caught;try{await ActualExtensionLoader.loadExtensionFromFactory(pi=>{pi.events.on('loader-ownership',()=>{});throw reason},ActualExtensionCwd,ActualExtensionBus,runtime)}catch(error){caught=error}
        \\ if(caught!==discardReason||cleanups!==3)throw Error('discard ordinary override/cleanup');assertExtensionCaptureEmpty();
        \\}finally{runtime.trackEventBusSubscription=original}
        \\export const passed=true;
    , "extension-loader-discard-original-ownership.mjs");
    defer engine.freeValue(result);
}
fn freshAllocation(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try js.define(engine, roots[0], "original", c.JS_DupValue(engine.context, reason));
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
}
pub fn verifyDiscardNativeFailure(engine: *em.Engine, actual_loader: c.JSValue, actual_cwd: c.JSValue, actual_bus: c.JSValue, actual_runtime: c.JSValue) !void {
    try install(engine, "ActualExtensionLoader", actual_loader);
    try install(engine, "ActualExtensionCwd", actual_cwd);
    try install(engine, "ActualExtensionBus", actual_bus);
    try install(engine, "ActualExtensionRuntime", actual_runtime);
    const record = try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)); defer engine.freeValue(record);
    const hook = try @import("extensions/native_node_function.zig").create(engine, "raiseExtensionNativeAllocation", 0, freshAllocation, &.{record}); defer engine.freeValue(hook);
    try install(engine, "raiseExtensionNativeAllocation", hook);
    try install(engine, "extensionGuestCaught", c.pi_js_bool(engine.context, 0));
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\const runtime=ActualExtensionRuntime,original=runtime.trackEventBusSubscription;
        \\runtime.trackEventBusSubscription=function(unsubscribe){return original.call(this,()=>{unsubscribe();raiseExtensionNativeAllocation()})};
        \\try{await ActualExtensionLoader.loadExtensionFromFactory(pi=>{pi.events.on('loader-native-ownership',()=>{});throw{ordinary:true}},ActualExtensionCwd,ActualExtensionBus,runtime)}catch{extensionGuestCaught=true}
        \\throw Error('discard native allocation became ordinary');
    , "extension-loader-discard-native-allocation.mjs"));
    const original = try js.get(engine, record, "original"); defer engine.freeValue(original);
    const captured = engine.captured_exception orelse return error.MissingExtensionFatalReason;
    try std.testing.expect(c.pi_js_native_allocation_error_generation(original) != 0);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, captured));
    try std.testing.expect(c.JS_IsUncatchableError(captured));
    const caught = try js.global(engine, "extensionGuestCaught"); defer engine.freeValue(caught);
    try std.testing.expect(c.JS_ToBool(engine.context, caught) == 0);
    c.JS_ClearUncatchableError(engine.context, captured);
    engine.captured_exception = null;
    engine.freeValue(captured);
    // Run this fatal case in its own owned Engine; guest finally/restoration is
    // intentionally bypassed by a fatal failure. Teardown remains a gate.
}
pub fn verifyCacheInvalidation(engine: *em.Engine, actual_cwd: c.JSValue, actual_path: c.JSValue, actual_factory: c.JSValue) !void {
    if (!c.JS_IsFunction(engine.context, actual_factory)) return error.RequiredActualExtensionFactory;
    const clear = try cache.createClear(engine); defer engine.freeValue(clear);
    const ignored = try js.call(engine, clear, c.pi_js_undefined(), &.{}); engine.freeValue(ignored);
    const token = try cache.useCwd(engine, actual_cwd); defer engine.freeValue(token);
    try cache.remember(engine, actual_path, actual_factory, token);
    const cached = try cache.lookup(engine, actual_path, token); defer engine.freeValue(cached);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, cached, actual_factory));
    const cleared = try js.call(engine, clear, c.pi_js_undefined(), &.{}); engine.freeValue(cleared);
    // An earlier import completing after clear must not repopulate the cache.
    try cache.remember(engine, actual_path, actual_factory, token);
    const fresh = try cache.useCwd(engine, actual_cwd); defer engine.freeValue(fresh);
    const missing = try cache.lookup(engine, actual_path, fresh); defer engine.freeValue(missing);
    try std.testing.expect(c.JS_IsUndefined(missing));
}
pub fn verifyLazyVirtualPromiseIdentity(engine: *em.Engine, real_virtual_module_import: c.JSValue) !void {
    const getter = try @import("extensions/native_sdk_extension_virtual_modules.zig").createLazy(engine, real_virtual_module_import); defer engine.freeValue(getter);
    const first = try js.call(engine, getter, c.pi_js_undefined(), &.{}); defer engine.freeValue(first);
    const second = try js.call(engine, getter, c.pi_js_undefined(), &.{}); defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    const modules = try engine.awaitValue(first); defer engine.freeValue(modules);
    const third = try js.call(engine, getter, c.pi_js_undefined(), &.{}); defer engine.freeValue(third);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, third));
    const again = try engine.awaitValue(third); defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, modules, again));
}
pub fn verifyActualVirtualNamespace(engine: *em.Engine, names: @import("extensions/native_sdk_extension_virtual_modules.zig").Names) !void {
    const namespace = try @import("extensions/native_sdk_extension_virtual_modules.zig").evaluate(engine, names); defer engine.freeValue(namespace);
    const modules = try js.get(engine, namespace, "VIRTUAL_MODULES"); defer engine.freeValue(modules);
    try install(engine, "ActualVirtualModules", modules);
    const result = try engine.evalModule(
        \\const modules=ActualVirtualModules;
        \\const keys=['typebox','typebox/compile','typebox/value','@sinclair/typebox','@sinclair/typebox/compile','@sinclair/typebox/value','@earendil-works/pi-agent-core','@earendil-works/pi-tui','@earendil-works/pi-ai','@earendil-works/pi-ai/compat','@earendil-works/pi-ai/oauth','@earendil-works/pi-ai/providers/all','@earendil-works/pi-coding-agent','@mariozechner/pi-agent-core','@mariozechner/pi-tui','@mariozechner/pi-ai','@mariozechner/pi-ai/compat','@mariozechner/pi-ai/oauth','@mariozechner/pi-ai/providers/all','@mariozechner/pi-coding-agent'];
        \\if(Object.keys(modules).join()!==keys.join())throw Error('virtual module declaration order');
        \\for(const key of keys){const alias=key.replace('@earendil-works/','@mariozechner/').replace(/^typebox/,'@sinclair/typebox');if(alias in modules&&modules[alias]!==modules[key])throw Error('virtual module alias identity')}
        \\if(modules['@earendil-works/pi-ai']!==modules['@earendil-works/pi-ai/compat'])throw Error('compat root identity');
        \\export const passed=true;
    , "extension-loader-actual-virtual-namespace.mjs");
    defer engine.freeValue(result);
}
/// Two real controlled physical extension modules are required: the first
/// exports an ordinary factory that registers a tool; the second has no callable
/// default. The eventual runner retains their physical bytes and importer graph.
pub fn verifyActualImports(engine: *em.Engine, actual_loader: c.JSValue, actual_cwd: c.JSValue, valid_path: c.JSValue, invalid_path: c.JSValue, actual_bus: c.JSValue, actual_runtime: c.JSValue) !void {
    try install(engine, "ActualExtensionLoader", actual_loader);
    try install(engine, "ActualExtensionCwd", actual_cwd);
    try install(engine, "ActualValidExtensionPath", valid_path);
    try install(engine, "ActualInvalidExtensionPath", invalid_path);
    try install(engine, "ActualExtensionBus", actual_bus);
    try install(engine, "ActualExtensionRuntime", actual_runtime);
    const result = try engine.evalModule(
        \\const paths=[ActualValidExtensionPath,ActualInvalidExtensionPath];
        \\const first=await ActualExtensionLoader.loadExtensionsCached(paths,ActualExtensionCwd,ActualExtensionBus,ActualExtensionRuntime);
        \\const second=await ActualExtensionLoader.loadExtensionsCached(paths,ActualExtensionCwd,ActualExtensionBus,ActualExtensionRuntime);
        \\for(const result of[first,second]){
        \\ if(result.runtime!==ActualExtensionRuntime||result.extensions.length!==1||result.errors.length!==1||result.warnings.length)throw Error('real import result');
        \\ if(result.errors[0].path!==ActualInvalidExtensionPath||result.errors[0].error!==`Extension does not export a valid factory function: ${ActualInvalidExtensionPath}`)throw Error('invalid factory diagnostic');
        \\ if(result.extensions[0].tools.size!==1)throw Error('actual transactional factory');
        \\}
        \\if(first.extensions[0]===second.extensions[0]||first.extensions[0].tools===second.extensions[0].tools)throw Error('cached factory must reinitialize actual extension');
        \\export const passed=true;
    , "extension-loader-real-physical-imports.mjs");
    defer engine.freeValue(result);
}
