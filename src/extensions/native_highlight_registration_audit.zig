//! Private native evidence for actual full-index registration, never a Source API.
//! Hooks perform no allocation, guest property read or guest callback.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = em.c;
const key = "pi-native:highlight/full191-registration-audit";
pub const count = 191;
const State = struct {
    engine: *em.Engine,
    core: c.JSValue,
    names: [count]c.JSValue,
    factories: [count]c.JSValue,
    successful: [count]bool = @splat(false),
    active: bool = false,
    completed: bool = false,
};
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.core);
    for (state.names) |item| c.JS_FreeValueRT(runtime, item);
    for (state.factories) |item| c.JS_FreeValueRT(runtime, item);
    state.engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.core, marker);
    for (state.names) |item| c.JS_MarkValue(runtime, item, marker);
    for (state.factories) |item| c.JS_MarkValue(runtime, item, marker);
}
fn get(engine: *em.Engine) ?*State {
    const value = engine.native_module_values.get(key) orelse return null;
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return null));
}
pub fn install(engine: *em.Engine, core: c.JSValue, names: [count][]const u8) !void {
    if (get(engine)) |state| {
        if (!c.JS_IsStrictEqual(engine.context, state.core, core)) return error.NativeHighlightCoreIdentityConflict;
        return;
    }
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native highlight registration audit", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const value = try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.pi_js_null(), class));
    defer engine.freeValue(value);
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .core = c.JS_DupValue(engine.context, core), .names = @splat(c.pi_js_undefined()), .factories = @splat(c.pi_js_undefined()) };
    _ = c.JS_SetOpaque(value, state);
    for (names, 0..) |name, index| state.names[index] = try sdk.text(engine, name);
    // The opaque value has no properties or exports. Only Engine-owned roots
    // retain it; importing this private namespace exposes no audit state.
    try engine.registerValueModule(key, value);
}
pub fn cachedFactory(engine: *em.Engine, index: usize) c.JSValue {
    return get(engine).?.factories[index];
}
pub fn cacheFactory(engine: *em.Engine, index: usize, factory: c.JSValue) void {
    const state = get(engine).?;
    c.JS_FreeValue(engine.context, state.factories[index]);
    state.factories[index] = c.JS_DupValue(engine.context, factory);
}
pub fn begin(engine: *em.Engine) void {
    const state = get(engine).?;
    state.successful = @splat(false);
    state.active = true;
}
pub fn finish(engine: *em.Engine) bool {
    const state = get(engine).?;
    state.active = false;
    for (state.successful) |successful| if (!successful) return false;
    state.completed = true;
    return true;
}
pub fn stop(engine: *em.Engine) void {
    if (get(engine)) |state| state.active = false;
}
pub fn complete(engine: *em.Engine, core: c.JSValue) bool {
    const state = get(engine) orelse return false;
    return state.completed and c.JS_IsStrictEqual(engine.context, state.core, core);
}
pub fn recordRegistered(engine: *em.Engine, core: c.JSValue, name: c.JSValue, factory: c.JSValue, body_succeeded: bool) void {
    const state = get(engine) orelse return;
    if (!state.active or !c.JS_IsStrictEqual(engine.context, state.core, core)) return;
    for (state.names, 0..) |expected, index| {
        if (!c.JS_IsStrictEqual(engine.context, name, expected)) continue;
        state.successful[index] = body_succeeded and !c.JS_IsUndefined(state.factories[index]) and
            c.JS_IsStrictEqual(engine.context, factory, state.factories[index]);
        return;
    }
}
