//! Ownership and intrinsic await operations for the actual native Chord Host.
const std = @import("std");
const scoped = @import("native_chord_values.zig");
pub const Scope = scoped.Scope;
pub const js = scoped.js;
pub const c = js.c;
pub const Engine = js.Engine;
pub const Kind = enum(c_int) { HostImpl, CtxImpl, RecordImpl, HandleImpl, SelfImpl, MemberReadable, Cell, Derived, Source, Fanout, BaseLink, MemoryLink, IpcLink, WebSocketLink, RemoteHandle, RemoteReadable, RelayHold, RelayCall, Connection, Reload, ObjectSelf, ObjectCtx, ObjectImpl, RefImpl, RemoteRef, RelayRef, RemoteBinding, ViewReadable };
pub const Actor = struct { engine: *Engine, bindings: c.JSValue, data: c.JSValue };
pub const RawCallback = *const fn (?*c.JSContext, c.JSValue, c_int, [*c]c.JSValue, c_int, [*c]c.JSValue) callconv(.c) c.JSValue;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
pub fn iteratorSymbol(s: *Scope) !c.JSValue {
    return s.keep(try s.engine.checked(JS_GetIteratorSymbol(s.engine.context)));
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owned: *Actor = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, owned.bindings);
    c.JS_FreeValueRT(runtime, owned.data);
    owned.engine.gpa.destroy(owned);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owned: *Actor = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, owned.bindings, visit);
    c.JS_MarkValue(runtime, owned.data, visit);
}
pub fn identifier(s: *Scope, bindings: c.JSValue, kind: Kind) !u32 {
    const names = try s.get(bindings, "classes");
    const value = try s.get(names, @tagName(kind));
    var result: u32 = undefined;
    if (c.JS_ToUint32(s.engine.context, &result, value) < 0) return js.capture(s.engine);
    return result;
}
pub fn actor(s: *Scope, value: c.JSValue, bindings: c.JSValue, kind: Kind) !*Actor {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(s.engine.context, value, try identifier(s, bindings, kind)) orelse return js.capture(s.engine)));
}
pub fn allocate(engine: *Engine, target: c.JSValue, bindings: c.JSValue, kind: Kind) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const prototype = try s.get(target, "prototype");
    const fallback = if (c.JS_IsObject(prototype)) prototype else try s.get(bindings, "objectPrototype");
    const value = try s.keep(try engine.checked(c.JS_NewObjectProtoClass(engine.context, fallback, try identifier(&s, bindings, kind))));
    const data = try s.record();
    const owned = try engine.gpa.create(Actor);
    owned.* = .{ .engine = engine, .bindings = s.result(bindings), .data = s.result(data) };
    _ = c.JS_SetOpaque(value, owned);
    return s.result(value);
}
pub fn register(s: *Scope, bindings: c.JSValue, kind: Kind) !void {
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(s.engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = @tagName(kind), .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(s.engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    try js.define(s.engine, try s.get(bindings, "classes"), @tagName(kind), c.JS_NewUint32(s.engine.context, id));
}
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn construct(s: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const constructor = try s.get(bindings, name);
    return s.keep(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, @intCast(args.len), @constCast(args.ptr))));
}
pub fn field(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try js.define(s.engine, target, name, s.result(value));
}
pub fn map(s: *Scope) !c.JSValue {
    return s.keep(try js.builtin(s.engine, "Map", &.{}));
}
pub fn set(s: *Scope) !c.JSValue {
    return s.keep(try js.builtin(s.engine, "Set", &.{}));
}
pub fn invoke(s: *Scope, target: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.keep(try js.invoke(s.engine, target, name, args));
}
pub fn snapshot(s: *Scope, iterable: c.JSValue) !c.JSValue {
    return s.keep(try @import("native_iterator_spread.zig").snapshot(s.engine, iterable));
}
pub fn entries(s: *Scope, value: c.JSValue) !c.JSValue {
    return snapshot(s, try invoke(s, value, "entries", &.{}));
}
pub fn values(s: *Scope, value: c.JSValue) !c.JSValue {
    return snapshot(s, try invoke(s, value, "values", &.{}));
}
pub fn length(s: *Scope, value: c.JSValue) !u32 {
    var result: u32 = undefined;
    if (c.JS_ToUint32(s.engine.context, &result, try s.get(value, "length")) < 0) return js.capture(s.engine);
    return result;
}
pub fn flag(s: *Scope, value: c.JSValue, name: [*:0]const u8) !bool {
    return c.JS_ToBool(s.engine.context, try s.get(value, name)) != 0;
}
pub fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
pub fn errorValue(s: *Scope, bindings: c.JSValue, code: []const u8, parts: []const c.JSValue, options: c.JSValue) !c.JSValue {
    const message = try s.keep(try @import("native_utf16.zig").concat(s.engine, parts));
    const constructor = try s.get(try s.get(bindings, "errors"), "ChordError");
    var arguments = [_]c.JSValue{ try s.text(code), message, options };
    return s.keep(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 3, &arguments)));
}
pub fn throwValue(s: *Scope, value: c.JSValue) !c.JSValue {
    return s.engine.checked(c.JS_Throw(s.engine.context, s.result(value)));
}
pub fn invalid(s: *Scope, bindings: c.JSValue, reason: []const u8, parts: []const c.JSValue) !c.JSValue {
    const options = try s.record();
    try field(s, options, "reason", try s.text(reason));
    return throwValue(s, try errorValue(s, bindings, "invalid", parts, options));
}
pub fn ordinaryError(s: *Scope, parts: []const c.JSValue) !c.JSValue {
    const message = try s.keep(try @import("native_utf16.zig").concat(s.engine, parts));
    return throwValue(s, try s.keep(try js.builtin(s.engine, "Error", &.{message})));
}
pub fn typeError(s: *Scope, parts: []const c.JSValue) !c.JSValue {
    const message = try s.keep(try @import("native_utf16.zig").concat(s.engine, parts));
    return throwValue(s, try s.keep(try js.builtin(s.engine, "TypeError", &.{message})));
}
pub fn rejected(engine: *Engine, reason: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_NewSettledPromise(engine.context, true, reason));
}
pub fn resolved(engine: *Engine, value: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_PiPromiseResolve(engine.context, value));
}
pub fn ignore(engine: *Engine, promise: c.JSValue) void {
    c.JS_PromiseMarkAsHandled(engine.context, promise);
}
pub fn wait(comptime next: *const fn (*Engine, c.JSValue, c.JSValue, bool, c_int) anyerror!c.JSValue, engine: *Engine, work: c.JSValue, value: c.JSValue, stage: c_int) !c.JSValue {
    const Adapter = struct {
        fn fulfilled(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, phase: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = Engine.fromContext(context.?);
            const generation = owner.native_allocation_generation;
            return next(owner, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), false, phase) catch |err| {
                return @import("native_chord_native_failure.zig").escape(owner, err, generation) orelse @import("native_durable.zig").reject(owner, err);
            };
        }
        fn failed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, phase: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = Engine.fromContext(context.?);
            const generation = owner.native_allocation_generation;
            return next(owner, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), true, phase) catch |err| {
                return @import("native_chord_native_failure.zig").escape(owner, err, generation) orelse @import("native_durable.zig").reject(owner, err);
            };
        }
    };
    var data = [_]c.JSValue{work};
    const fulfilled = try engine.checked(c.JS_NewCFunctionData2(engine.context, Adapter.fulfilled, "", 1, stage, 1, &data));
    defer engine.freeValue(fulfilled);
    const failed = try engine.checked(c.JS_NewCFunctionData2(engine.context, Adapter.failed, "", 1, stage, 1, &data));
    defer engine.freeValue(failed);
    const awaited = try resolved(engine, value);
    defer engine.freeValue(awaited);
    return engine.checked(c.JS_PromiseThen(engine.context, awaited, fulfilled, failed));
}
pub fn define(s: *Scope, prototype: c.JSValue, bindings: c.JSValue, name: [*:0]const u8, callback: RawCallback, operation: c_int, arity: c_int, getter: bool, async_function: bool) !void {
    // JS_NewCFunctionData2 copies the supplied C string. Ordinary method names
    // already have their required sentinel and need no temporary heap copy.
    const getter_name = if (getter) try std.fmt.allocPrintSentinel(s.engine.gpa, "get {s}", .{name}, 0) else null;
    defer if (getter_name) |owned_name| s.engine.gpa.free(owned_name);
    const function_name: [*:0]const u8 = if (getter_name) |owned_name| owned_name.ptr else name;
    var data = [_]c.JSValue{bindings};
    const function = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, function_name, arity, operation, 1, &data)));
    if (async_function) {
        const async_prototype = try s.keep(try s.engine.checked(c.JS_GetAsyncFunctionPrototype(s.engine.context)));
        if (c.JS_SetPrototype(s.engine.context, function, async_prototype) < 0) return js.capture(s.engine);
    }
    if (getter) {
        const atom = c.JS_NewAtom(s.engine.context, name);
        defer c.JS_FreeAtom(s.engine.context, atom);
        if (c.JS_DefinePropertyGetSet(s.engine.context, prototype, atom, s.result(function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(s.engine);
    } else if (c.JS_DefinePropertyValueStr(s.engine.context, prototype, name, s.result(function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(s.engine);
}
