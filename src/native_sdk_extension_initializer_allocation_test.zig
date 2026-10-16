//! Prepared integration checks over supplied actual loader/event-bus namespaces.
//! The only injected callback creates a private native allocation-error reason;
//! no initializer, runtime, registry or event-bus collaborator is substituted.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
fn freshAllocation(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    _ = engine.throwNativeOutOfMemory();
    const original = c.JS_GetException(engine.context);
    defer engine.freeValue(original);
    if (c.JS_SetPropertyStr(engine.context, roots[0], "original", c.JS_DupValue(engine.context, original)) < 0) return v.js.capture(engine);
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, original)));
}
fn scenario(engine: *v.em.Engine, actual_subjects: c.JSValue, source: []const u8, filename: [:0]const u8) !void {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const record = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(record, "original", c.pi_js_undefined());
    const hook = try scope.own(try @import("extensions/native_node_function.zig").create(engine, "raiseFreshNativeAllocation", 0, freshAllocation, &.{record}));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "ActualExtensionFailureSubjects", actual_subjects);
    try scope.put(global, "raiseFreshNativeAllocation", hook);
    try scope.put(global, "initializerGuestCaught", c.pi_js_bool(engine.context, 0));
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(source, filename));
    const original = try scope.get(record, "original");
    try std.testing.expect(c.pi_js_native_allocation_error_generation(original) != 0);
    const actual = engine.captured_exception orelse return error.MissingInitializerAllocationFailure;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, actual));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expect(c.JS_ToBool(engine.context, try scope.get(global, "initializerGuestCaught")) == 0);
    c.JS_ClearUncatchableError(engine.context, actual);
    engine.freeValue(actual);
    engine.captured_exception = null;
}
/// Invoke only after constructing the real loader and event-bus namespaces.
/// Actual subjects: { loader:{createExtensionRuntime,loadExtensionFromFactory},
/// eventBus:{createEventBus} }. Tests require the reviewed genuine async adapter.
pub fn verify(engine: *v.em.Engine, actual_subjects: c.JSValue) !void {
    try scenario(engine, actual_subjects,
        \\const {loader,eventBus}=ActualExtensionFailureSubjects;
        \\const runtime=loader.createExtensionRuntime(),bus=eventBus.createEventBus(),realOn=bus.on;
        \\bus.on=(...args)=>{const unsubscribe=realOn(...args);return()=>{unsubscribe();raiseFreshNativeAllocation()}};
        \\try{await loader.loadExtensionFromFactory(pi=>{pi.events.on('owned-start',()=>{});throw {ordinary:true}},'.',bus,runtime,'<inline:start-discard>')}catch{globalThis.initializerGuestCaught=true}
        \\throw Error('trusted allocation was converted into an ordinary rejection');
    , "initializer-start-discard-allocation.mjs");
    try scenario(engine, actual_subjects,
        \\const {loader,eventBus}=ActualExtensionFailureSubjects;
        \\const runtime=loader.createExtensionRuntime(),bus=eventBus.createEventBus(),realOn=bus.on;
        \\bus.on=(...args)=>{const unsubscribe=realOn(...args);return()=>{unsubscribe();raiseFreshNativeAllocation()}};
        \\const realRegister=runtime.registerProvider;runtime.registerProvider=(...args)=>{realRegister(...args);throw {ordinary:true}};
        \\try{await loader.loadExtensionFromFactory(pi=>{pi.events.on('owned-resume',()=>{});pi.registerProvider('owned',{baseUrl:'https://example.test'})},'.',bus,runtime,'<inline:resumed-discard>')}catch{globalThis.initializerGuestCaught=true}
        \\throw Error('trusted resumed allocation was converted into an ordinary rejection');
    , "initializer-resumed-discard-allocation.mjs");
}
