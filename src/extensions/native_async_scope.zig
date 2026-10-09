//! Private owner-thread execution scopes propagated through promises and timers.
//! No scope authority, native pointer or lookup key is exposed to JavaScript.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Callback = *const fn (?*anyopaque) void;
const Token = struct {
    gpa: std.mem.Allocator,
    context: ?*anyopaque,
    activate: Callback,
    deactivate: Callback,
    live: bool = true,
};
const State = struct {
    engine: *engine_mod.Engine,
    class: c.JSClassID,
    current: c.JSValue,
    stack: [128]c.JSValue = undefined,
    depth: usize = 0,
    suppressed: usize = 0,
    failed: bool = false,
};
fn state(engine: *engine_mod.Engine) ?*State {
    return @ptrCast(@alignCast(engine.native_async_scope));
}
fn record(engine: *engine_mod.Engine, value: c.JSValue) ?*Token {
    const s = state(engine) orelse return null;
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, s.class)));
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    _ = runtime;
    const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    token.gpa.destroy(token);
}
pub fn install(engine: *engine_mod.Engine) !void {
    if (state(engine) != null) return;
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native private async scope", .finalizer = finalize };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const s = try engine.gpa.create(State);
    s.* = .{ .engine = engine, .class = class, .current = c.pi_js_undefined() };
    engine.native_async_scope = s;
    c.JS_SetExecutionContextHook(engine.runtime, hook, s);
}
pub fn deinit(engine: *engine_mod.Engine) void {
    const s = state(engine) orelse return;
    c.JS_SetExecutionContextHook(engine.runtime, null, null);
    c.JS_SetExecutionContext(engine.runtime, c.pi_js_undefined());
    engine.freeValue(s.current);
    for (s.stack[0..s.depth]) |value| engine.freeValue(value);
    engine.native_async_scope = null;
    engine.gpa.destroy(s);
}
pub fn create(engine: *engine_mod.Engine, context: ?*anyopaque, activate: Callback, deactivate: Callback) !c.JSValue {
    try install(engine);
    const s = state(engine).?;
    const token = try engine.gpa.create(Token);
    errdefer engine.gpa.destroy(token);
    token.* = .{ .gpa = engine.gpa, .context = context, .activate = activate, .deactivate = deactivate };
    const value = try engine.checked(c.JS_NewObjectClass(engine.context, s.class));
    _ = c.JS_SetOpaque(value, token);
    return value;
}
pub fn retire(engine: *engine_mod.Engine, value: c.JSValue) void {
    const token = record(engine, value) orelse return;
    if (token.live) if (state(engine)) |s| if (c.JS_IsStrictEqual(engine.context, s.current, value)) token.deactivate(token.context);
    token.live = false;
    token.context = null;
}
pub fn capture(engine: *engine_mod.Engine) c.JSValue {
    return if (state(engine)) |s| c.JS_DupValue(engine.context, s.current) else c.pi_js_undefined();
}
pub fn requireLive(engine: *engine_mod.Engine) !void {
    const s = state(engine) orelse return;
    if (s.failed) return error.OutOfMemory;
    if (record(engine, s.current)) |token| if (!token.live) return error.RetiredNativeAsyncScope;
}
fn switchTo(s: *State, value: c.JSValue) void {
    if (c.JS_IsStrictEqual(s.engine.context, s.current, value)) return;
    if (record(s.engine, s.current)) |token| if (token.live) token.deactivate(token.context);
    s.engine.freeValue(s.current);
    s.current = c.JS_DupValue(s.engine.context, value);
    c.JS_SetExecutionContext(s.engine.runtime, value);
    if (record(s.engine, s.current)) |token| if (token.live) token.activate(token.context);
}
pub const Guard = struct {
    engine: *engine_mod.Engine,
    previous: c.JSValue,
    pub fn restore(self: Guard) void {
        const s = state(self.engine) orelse return;
        switchTo(s, self.previous);
        self.engine.freeValue(self.previous);
    }
};
pub fn enter(engine: *engine_mod.Engine, value: c.JSValue) Guard {
    const previous = capture(engine);
    if (state(engine)) |s| switchTo(s, value);
    return .{ .engine = engine, .previous = previous };
}
fn hook(_: ?*c.JSContext, before: bool, inherited: c.JSValue, raw: ?*anyopaque) callconv(.c) void {
    const s: *State = @ptrCast(@alignCast(raw.?));
    if (before) {
        if (s.depth == s.stack.len) {
            s.failed = true;
            s.suppressed += 1;
            return;
        }
        s.stack[s.depth] = capture(s.engine);
        s.depth += 1;
        switchTo(s, inherited);
    } else {
        if (s.suppressed != 0) {
            s.suppressed -= 1;
            return;
        }
        if (s.depth == 0) {
            s.failed = true;
            return;
        }
        s.depth -= 1;
        const previous = s.stack[s.depth];
        switchTo(s, previous);
        s.engine.freeValue(previous);
    }
}
