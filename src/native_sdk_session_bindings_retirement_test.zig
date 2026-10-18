//! Native sole-holder expression witnesses. Authored/unrun; no JS proxy object
//! or wrapper retains the transferred holder after the actual return/getter.
const std = @import("std");
const em = @import("extensions/engine.zig");
const bindings = @import("extensions/native_sdk_session_bindings.zig");
const actual = @import("native_sdk_session_bindings_actual_controls.zig");
const c = em.c;
const Probe = struct { engine: *em.Engine, count: *usize };
fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    probe.count.* += 1;
    const global = c.JS_GetGlobalObject(probe.engine.context);
    _ = c.JS_SetPropertyStr(probe.engine.context, global, "bindingRetired", c.JS_NewInt32(probe.engine.context, @intCast(probe.count.*)));
    probe.engine.freeValue(global);
    probe.engine.gpa.destroy(probe);
}
fn holder(engine: *em.Engine, count: *usize) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "BindingExpressionHolder", .finalizer = finalize };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const state = try engine.gpa.create(Probe);
    errdefer engine.gpa.destroy(state);
    const value = try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.pi_js_null(), class));
    state.* = .{ .engine = engine, .count = count };
    _ = c.JS_SetOpaque(value, state);
    return value;
}
fn put(engine: *em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}
fn take(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const global = c.JS_GetGlobalObject(context);
    defer c.JS_FreeValue(context, global);
    const value = c.JS_GetPropertyStr(context, global, "bindingSeed");
    const key = c.JS_NewAtom(context, "bindingSeed");
    defer c.JS_FreeAtom(context, key);
    _ = c.JS_DeleteProperty(context, global, key, 0);
    return value;
}
fn firstGetter(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const global = c.JS_GetGlobalObject(context);
    defer c.JS_FreeValue(context, global);
    const previous = c.JS_GetPropertyStr(context, global, "bindingReadCount");
    defer c.JS_FreeValue(context, previous);
    var count: i32 = 0;
    if (!c.JS_IsUndefined(previous) and c.JS_ToInt32(context, &count, previous) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    if (c.JS_SetPropertyStr(context, global, "bindingReadCount", c.JS_NewInt32(context, count + 1)) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    if (count == 0) return take(context, receiver, argc, argv);
    const retired = c.JS_GetPropertyStr(context, global, "bindingRetired");
    defer c.JS_FreeValue(context, retired);
    if (!c.JS_IsStrictEqual(context, retired, c.JS_NewInt32(context, 1))) return c.JS_ThrowTypeError(context, "First native getter result remains alive at second native getter");
    return c.pi_js_undefined();
}
fn prepare(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    const prototype = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(prototype);
    try bindings.install(engine, prototype);
    try put(engine, "bindingsAF", prototype);
    try put(engine, "takeBindingHolder", try engine.checked(c.JS_NewCFunction(engine.context, take, "takeBindingHolder", 0)));
    try put(engine, "bindingFirstGetter", try engine.checked(c.JS_NewCFunction(engine.context, firstGetter, "bindingFirstGetter", 0)));
}
test "native session binding expression sole holder retires before next Source getter without Await" {
    const cases = [_][]const u8{
        // First condition result must die before the independent second read.
        \\const input={};Object.defineProperty(input,'uiContext',{get:bindingFirstGetter});await bindingsAF.bindExtensions.call(base,input);if(bindingReadCount!==2)throw Error('double read lost');
        ,
        // Assignment completion is a separate expression statement.
        \\let reads=0;const input={get uiContext(){return ++reads===1?1:takeBindingHolder()}};Object.defineProperty(base,'_extensionUIContext',{set(value){}});Object.defineProperty(base,'_applyExtensionBindings',{get(){if(bindingRetired!==1)throw Error('assignment result still alive');return ()=>{}}});await bindingsAF.bindExtensions.call(base,input);
        ,
        \\let reads=0;base._applyExtensionBindings=()=>takeBindingHolder();Object.defineProperty(base,'_extensionRunner',{get(){if(++reads===2&&bindingRetired!==1)throw Error('apply result still alive');return runner}});await bindingsAF.bindExtensions.call(base,{});
        ,
        \\runner.reportUnhandledMcpServers=()=>takeBindingHolder();Object.defineProperty(base,'extendResourcesFromExtensions',{get(){if(bindingRetired!==1)throw Error('report result still alive');return ()=>{}}});await bindingsAF.bindExtensions.call(base,{});
        ,
        \\base._sessionStartEvent={get reason(){return takeBindingHolder()}};base.extendResourcesFromExtensions=reason=>{if(bindingRetired!==1||reason!=='startup')throw Error('reason comparison result still alive')};await bindingsAF.bindExtensions.call(base,{});
        ,
        \\let reads=0;runner.hasHandlers=()=>takeBindingHolder();runner.emitResourcesDiscover=()=>({skillPaths:[],promptPaths:[],themePaths:[]});Object.defineProperty(base,'_extensionRunner',{get(){if(++reads===2&&bindingRetired!==1)throw Error('hasHandlers result still alive');return runner}});await bindingsAF.extendResourcesFromExtensions.call(base,'startup');
        ,
        \\runner.hasHandlers=()=>true;runner.emitResourcesDiscover=()=>({skillPaths:{get length(){return takeBindingHolder()}},promptPaths:[],themePaths:[]});Object.defineProperty(base,'buildExtensionResourcePaths',{get(){if(bindingRetired!==1)throw Error('length comparison result still alive');return paths=>paths}});base._resourceLoader={extendResources(){}};base.getActiveToolNames=()=>[];base._rebuildSystemPrompt=()=>{};await bindingsAF.extendResourcesFromExtensions.call(base,'startup');
        ,
        \\runner.hasHandlers=()=>true;runner.emitResourcesDiscover=()=>({skillPaths:[1],promptPaths:[],themePaths:[]});base.buildExtensionResourcePaths=paths=>paths;base._resourceLoader={extendResources(){return takeBindingHolder()}};Object.defineProperty(base,'_rebuildSystemPrompt',{get(){if(bindingRetired!==1)throw Error('extendResources result still alive');return ()=>{}}});base.getActiveToolNames=()=>[];await bindingsAF.extendResourcesFromExtensions.call(base,'startup');
        ,
    };
    for (cases) |source| {
        const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
        var count: usize = 0;
        // Count outlives the engine even on an early failed assertion.
        defer engine.deinit();
        try prepare(engine);
        try put(engine, "bindingRetired", c.JS_NewInt32(engine.context, 0));
        try put(engine, "bindingSeed", try holder(engine, &count));
        const text = try std.mem.concat(std.testing.allocator, u8, &.{
            "const runner={emit(){},reportUnhandledMcpServers(){}};const base={_applyExtensionBindings(){},_extensionRunner:runner,_sessionStartEvent:{reason:'startup'},extendResourcesFromExtensions(){}};\n",
            source,
            "\nif(bindingRetired!==1)throw Error('sole native holder not retired');export const complete=true;",
        });
        defer std.testing.allocator.free(text);
        const result = try engine.evalModule(text, "session-binding-expression-retirement.mjs");
        engine.freeValue(result);
        try std.testing.expectEqual(@as(usize, 1), count);
    }
}
test "native actual session binding control entry rejects active event before factory getter" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const factory = try engine.eval("({get createAgentSession(){globalThis.bindingFactoryGetterRan=true;throw Error('getter must not run')}})", "binding-entry-control.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(factory);
    const no_value = c.pi_js_undefined();
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    _ = engine.throwNativeOutOfMemoryFatal();
    const original = c.JS_GetException(engine.context);
    defer engine.freeValue(original);
    // The invocation owns the active event even when the VM pending slot is empty.
    if (actual.createAndBind(engine, factory, no_value, no_value)) |unexpected| {
        engine.freeValue(unexpected);
        _ = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
        return error.ActiveBindingEntryEventWasIgnored;
    } else |_| {}
    _ = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
    if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const ran = c.JS_GetPropertyStr(engine.context, global, "bindingFactoryGetterRan");
    defer engine.freeValue(ran);
    try std.testing.expect(c.JS_IsUndefined(ran));
}
