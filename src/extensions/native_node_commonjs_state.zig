//! Actual CommonJS lexical cells, retained only by the known Module owner.
//! Native depth updates never allocate while implementing require's finally.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub const State = struct {
    engine: *v.em.Engine,
    roots: c.JSValue,
    stat_cache: c.JSValue,
    require_depth: u64 = 0,
    wrapper_patched: bool = false,
    wrapper_initialized: bool = false,
};
fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = state.engine;
    c.JS_FreeValueRT(engine.runtime, state.roots);
    c.JS_FreeValueRT(engine.runtime, state.stat_cache);
    engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.roots, marker);
    c.JS_MarkValue(runtime, state.stat_cache, marker);
}
pub fn create(engine: *v.em.Engine, roots: c.JSValue) !c.JSValue {
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
    const state = try engine.gpa.create(State);
    errdefer if (!attached) engine.gpa.destroy(state);
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native CommonJS Lexical Owner", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const owner = try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.pi_js_null(), id));
    state.* = .{ .engine = engine, .roots = c.JS_DupValue(engine.context, roots), .stat_cache = c.pi_js_null() };
    _ = c.JS_SetOpaque(owner, state);
    attached = true;
    return owner;
}
/// Only a root made by create and retained inside a known Module callable is
/// passed here. This is not a guest token or an importable storage namespace.
pub fn known(engine: *v.em.Engine, owner: c.JSValue) !*State {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return error.InvalidKnownCommonJSLexicalOwner));
    if (state.engine != engine) return error.InvalidKnownCommonJSLexicalOwner;
    return state;
}
pub fn clearStatCache(state: *State) void {
    const previous = state.stat_cache;
    state.stat_cache = c.pi_js_null();
    state.engine.freeValue(previous);
}
