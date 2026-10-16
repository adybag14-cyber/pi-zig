//! Actual loader factory-cache state and cwd/generation token rules. Native
//! opaque ownership hides the cache Map and marks every retained JS value.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const module_name = "pi-native:extension-cache-owner";
const State = struct { engine: *em.Engine, entries: c.JSValue, cwd: c.JSValue, generation: c.JSValue, clear_function: c.JSValue };
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ state.entries, state.cwd, state.generation, state.clear_function }) |item| c.JS_FreeValueRT(runtime, item);
    state.engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ state.entries, state.cwd, state.generation, state.clear_function }) |item| c.JS_MarkValue(runtime, item, marker);
}
fn stateValue(engine: *em.Engine) !c.JSValue {
    if (engine.native_module_values.get(module_name)) |value| return c.JS_DupValue(engine.context, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // Source constructs the shared Map once at module evaluation.
    const entries = try scope.own(try js.builtin(engine, "Map", &.{}));
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native Extension Cache Owner", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const state = try engine.gpa.create(State);
    var attached = false;
    errdefer if (!attached) engine.gpa.destroy(state);
    const value = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.JS_NULL, class)));
    state.* = .{ .engine = engine, .entries = c.JS_DupValue(engine.context, entries), .cwd = c.pi_js_undefined(), .generation = c.JS_NewInt32(engine.context, 0), .clear_function = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(value, state);
    attached = true;
    try engine.registerValueModule(module_name, value);
    return c.JS_DupValue(engine.context, value);
}
fn owned(engine: *em.Engine, value: c.JSValue) !*State {
    // This value only comes from the private registered module or function data;
    // no user argument is cast to the native ownership record.
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return error.InvalidNativeExtensionCacheOwner));
    if (state.engine != engine) return error.InvalidNativeExtensionCacheOwner;
    return state;
}
/// Owned genuine ordinary Source clearExtensionCache function, length0.
pub fn createClear(engine: *em.Engine) !c.JSValue {
    const value = try stateValue(engine);
    defer engine.freeValue(value);
    const state = try owned(engine, value);
    if (!c.JS_IsUndefined(state.clear_function)) return c.JS_DupValue(engine.context, state.clear_function);
    const function = try @import("native_node_function.zig").create(engine, "clearExtensionCache", 0, clearCall, &.{value});
    state.clear_function = c.JS_DupValue(engine.context, function);
    return function;
}
fn clearCall(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try clearBody(&scope, try owned(engine, roots[0]));
    return c.pi_js_undefined();
}
fn replace(scope: *Scope, target: *c.JSValue, value: c.JSValue) void {
    const retained = c.JS_DupValue(scope.engine.context, value);
    scope.engine.freeValue(target.*);
    target.* = retained;
}
fn clearBody(scope: *Scope, state: *State) !void {
    _ = try scope.invoke(state.entries, "clear", &.{});
    replace(scope, &state.cwd, c.pi_js_undefined());
    const generation = try scope.own(try scope.engine.checked(c.JS_PiIncrement(scope.engine.context, state.generation)));
    replace(scope, &state.generation, generation);
}
/// Owned actual useExtensionCacheCwd token. Source path normalization and cache
/// invalidation execute before capturing the current numeric generation.
pub fn useCwd(engine: *em.Engine, cwd: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.own(try stateValue(engine));
    const state = try owned(engine, owner);
    const resolved = try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, cwd, c.pi_js_undefined(), c.pi_js_undefined()));
    if (!c.JS_IsUndefined(state.cwd) and !scope.equal(state.cwd, resolved)) try clearBody(&scope, state);
    replace(&scope, &state.cwd, resolved);
    const token = try scope.object();
    try js.define(engine, token, "cwd", c.JS_DupValue(engine.context, resolved));
    try js.define(engine, token, "generation", c.JS_DupValue(engine.context, state.generation));
    return c.JS_DupValue(engine.context, token);
}
fn current(scope: *Scope, state: *State, token: c.JSValue) !bool {
    if (c.JS_IsUndefined(token)) return false;
    // Preserve LHS values across a getter that can recursively clear the cache.
    const cwd = try scope.own(c.JS_DupValue(scope.engine.context, state.cwd));
    if (!scope.equal(cwd, try scope.get(token, "cwd"))) return false;
    const generation = try scope.own(c.JS_DupValue(scope.engine.context, state.generation));
    return scope.equal(generation, try scope.get(token, "generation"));
}
/// Owned cached factory or undefined, using the genuine truthiness rule.
pub fn lookup(engine: *em.Engine, path: c.JSValue, token: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try owned(engine, try scope.own(try stateValue(engine)));
    if (!try current(&scope, state, token)) return c.pi_js_undefined();
    const factory = try scope.invoke(state.entries, "get", &.{path});
    return if (scope.truthy(factory)) c.JS_DupValue(engine.context, factory) else c.pi_js_undefined();
}
/// Only an import whose original token is still current can populate the cache.
pub fn remember(engine: *em.Engine, path: c.JSValue, factory: c.JSValue, token: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try owned(engine, try scope.own(try stateValue(engine)));
    if (try current(&scope, state, token)) _ = try scope.invoke(state.entries, "set", &.{ path, factory });
}
