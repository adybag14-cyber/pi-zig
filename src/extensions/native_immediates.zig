//! Native Node check-phase queue. This queue is independent of timer deadlines.
//! Its linked handles, callback receiver and live fields follow Node24 timers.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const async_scope = @import("native_async_scope.zig");
const c = em.c;
const Handle = struct { gpa: std.mem.Allocator, scope: c.JSValue, active: bool = false, refed: bool = false };
const State = struct { engine: *em.Engine, owner: c.JSValue, class: c.JSClassID, count: usize = 0, refs: usize = 0, pumping: bool = false, timer_phase: bool = false };
const Method = enum(c_int) { set, clear, ref, unref, hasRef, dispose };
fn state(engine: *em.Engine) !*State {
    return @ptrCast(@alignCast(engine.native_immediate_state orelse return error.NativeImmediatesUnavailable));
}
fn handle(s: *State, value: c.JSValue) ?*Handle {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, s.class)));
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const retained: *Handle = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, retained.scope);
    retained.gpa.destroy(retained);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const retained: *Handle = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, retained.scope, visit);
}
fn cleanup(engine: *em.Engine) void {
    const s = state(engine) catch return;
    engine.native_immediate_state = null;
    engine.native_immediate_pump = null;
    engine.native_immediate_pending = null;
    engine.native_immediate_referenced = null;
    engine.native_immediate_cleanup = null;
    inline for (.{ "head", "tail", "current", "previous" }) |name| _ = c.JS_SetPropertyStr(engine.context, s.owner, name, c.pi_js_null());
    engine.freeValue(s.owner);
    engine.gpa.destroy(s);
}
pub fn pending(engine: *em.Engine) bool {
    return if (state(engine)) |s| s.count != 0 else |_| false;
}
pub fn referenced(engine: *em.Engine) bool {
    return if (state(engine)) |s| s.refs != 0 else |_| false;
}
fn function(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, length: c_int, operation: Method) !c.JSValue {
    var roots = [_]c.JSValue{owner};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, @intFromEnum(operation), 1, &roots)));
}
fn setFunction(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const supplied = if (args.len != 0) args[0] else c.pi_js_undefined();
    if (!c.JS_IsFunction(engine.context, supplied)) {
        const description = try @import("node_events.zig").description(engine, supplied);
        defer engine.gpa.free(description);
        const message = try std.fmt.allocPrint(engine.gpa, "The \"callback\" argument must be of type function. Received {s}", .{description});
        defer engine.gpa.free(message);
        return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
    }
    const argv = if (args.len > 1) try scope.array() else c.pi_js_undefined();
    if (args.len > 1) for (args[1..], 0..) |argument, index| try scope.index(argv, @intCast(index), argument);
    return construct(engine, try scope.get(roots[0], "constructor"), &.{ supplied, argv }, roots);
}
fn clearFunction(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try clear(&scope, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined());
    return c.pi_js_undefined();
}
fn disposeFunction(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try clear(&scope, roots[0], receiver);
    return c.pi_js_undefined();
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const s = try state(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const retained = try engine.gpa.create(Handle);
    retained.* = .{ .gpa = engine.gpa, .scope = async_scope.capture(engine) };
    var attached = false;
    errdefer if (!attached) {
        engine.freeValue(retained.scope);
        engine.gpa.destroy(retained);
    };
    const supplied_prototype = try scope.get(target, "prototype");
    const prototype = if (c.JS_IsObject(supplied_prototype)) supplied_prototype else try scope.get(roots[0], "objectPrototype");
    const object = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, s.class)));
    _ = c.JS_SetOpaque(object, retained);
    attached = true;
    try scope.set(object, "_idleNext", c.pi_js_null());
    try scope.set(object, "_idlePrev", c.pi_js_null());
    try scope.set(object, "_onImmediate", if (args.len > 0) args[0] else c.pi_js_undefined());
    try scope.set(object, "_argv", if (args.len > 1) args[1] else c.pi_js_undefined());
    try scope.set(object, "_destroyed", c.pi_js_bool(engine.context, 0));
    try js.setKey(engine, object, try scope.get(roots[0], "refed"), c.pi_js_bool(engine.context, 0));
    _ = try scope.invoke(object, "ref", &.{});
    const tail = try scope.get(roots[0], "tail");
    if (!c.JS_IsNull(tail)) {
        try scope.set(tail, "_idleNext", object);
        try scope.set(object, "_idlePrev", tail);
    } else try scope.set(roots[0], "head", object);
    try scope.set(roots[0], "tail", object);
    retained.active = true;
    s.count += 1;
    if (retained.refed) s.refs += 1;
    em.Engine.notifyOwner(engine);
    return c.JS_DupValue(engine.context, object);
}
fn deactivate(s: *State, value: c.JSValue) void {
    if (handle(s, value)) |retained| if (retained.active) {
        retained.active = false;
        s.count -= 1;
        if (retained.refed) s.refs -= 1;
        retained.refed = false;
    };
}
fn clear(scope: *Scope, owner: c.JSValue, object: c.JSValue) !void {
    const engine = scope.engine;
    if (c.JS_IsUndefined(object) or c.JS_IsNull(object)) return;
    if (!scope.truthy(try scope.get(object, "_onImmediate")) or scope.truthy(try scope.get(object, "_destroyed"))) return;
    try scope.set(object, "_destroyed", c.pi_js_bool(engine.context, 1));
    _ = try scope.own(try js.getKey(engine, object, try scope.get(owner, "refed")));
    deactivate(try state(engine), object);
    try js.setKey(engine, object, try scope.get(owner, "refed"), c.pi_js_null());
    try scope.set(object, "_onImmediate", c.pi_js_null());
    // The same live linked-list operations as Node's ImmediateList.remove.
    if (scope.truthy(try scope.get(object, "_idleNext"))) try scope.set(try scope.get(object, "_idleNext"), "_idlePrev", try scope.get(object, "_idlePrev"));
    if (scope.truthy(try scope.get(object, "_idlePrev"))) try scope.set(try scope.get(object, "_idlePrev"), "_idleNext", try scope.get(object, "_idleNext"));
    if (scope.equal(object, try scope.get(owner, "head"))) try scope.set(owner, "head", try scope.get(object, "_idleNext"));
    if (scope.equal(object, try scope.get(owner, "tail"))) try scope.set(owner, "tail", try scope.get(object, "_idlePrev"));
    try scope.set(object, "_idleNext", c.pi_js_null());
    try scope.set(object, "_idlePrev", c.pi_js_null());
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, roots[0], receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *em.Engine, owner: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, operation: Method) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (operation) {
        .set => return setFunction(engine, receiver, args, &.{owner}),
        .clear => return clearFunction(engine, receiver, args, &.{owner}),
        .dispose => {
            try clear(&scope, owner, receiver);
            return c.pi_js_undefined();
        },
        .ref, .unref, .hasRef => {
            const symbol = try scope.get(owner, "refed");
            const refed = try scope.own(try js.getKey(engine, receiver, symbol));
            if (operation == .hasRef) return c.pi_js_bool(engine.context, @intFromBool(scope.truthy(refed)));
            if (scope.equal(refed, c.pi_js_bool(engine.context, @intFromBool(operation == .unref)))) {
                const new_ref = operation == .ref;
                try js.setKey(engine, receiver, symbol, c.pi_js_bool(engine.context, @intFromBool(new_ref)));
                const s = try state(engine);
                if (handle(s, receiver)) |retained| {
                    if (retained.active) {
                        if (new_ref) s.refs += 1 else s.refs -= 1;
                    }
                    retained.refed = new_ref;
                }
            }
            return c.JS_DupValue(engine.context, receiver);
        },
    }
}
fn invokeCallback(scope: *Scope, immediate: c.JSValue) !void {
    const engine = scope.engine;
    const argv = try scope.get(immediate, "_argv");
    const function_value = try scope.get(immediate, "_onImmediate");
    var arguments: std.ArrayList(c.JSValue) = .empty;
    defer arguments.deinit(engine.gpa);
    if (scope.truthy(argv)) {
        const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
        var iterator = try js.Iterator.init(engine, argv, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |argument| {
            const rooted = try scope.own(argument);
            try arguments.append(engine.gpa, rooted);
        }
    }
    _ = try scope.call(function_value, immediate, arguments.items);
}
fn finishImmediate(scope: *Scope, owner: c.JSValue, immediate: c.JSValue) !void {
    try scope.set(immediate, "_onImmediate", c.pi_js_null());
    try scope.set(owner, "current", try scope.get(immediate, "_idleNext"));
}
pub fn pump(engine: *em.Engine) !bool {
    const s = try state(engine);
    if (s.pumping or c.JS_IsJobPending(engine.runtime)) return false;
    if (s.timer_phase) {
        s.timer_phase = false;
        return false;
    }
    s.pumping = true;
    defer s.pumping = false;
    var worked = false;
    var callbacks: usize = 0;
    {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        if (c.JS_IsNull(try scope.get(s.owner, "current"))) {
            try scope.set(s.owner, "current", try scope.get(s.owner, "head"));
            try scope.set(s.owner, "head", c.pi_js_null());
            try scope.set(s.owner, "tail", c.pi_js_null());
            try scope.set(s.owner, "previous", c.pi_js_null());
        }
    }
    while (true) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const immediate = try scope.get(s.owner, "current");
        if (c.JS_IsNull(immediate)) break;
        if (callbacks != 0) {
            try @import("node_events.zig").drainHostTicks(engine);
            _ = try engine.runReadyJobs(engine.options.job_budget);
            if (c.JS_IsJobPending(engine.runtime)) return error.JavaScriptJobLimit;
            engine.finishJob();
        }
        if (scope.truthy(try scope.get(immediate, "_destroyed"))) {
            const previous = try scope.get(s.owner, "previous");
            try scope.set(s.owner, "current", if (c.JS_IsNull(previous)) try scope.get(immediate, "_idleNext") else try scope.get(previous, "_idleNext"));
            continue;
        }
        if (engine.cancelled.load(.acquire)) return error.JavaScriptInterrupted;
        if (callbacks >= engine.options.job_budget) return error.JavaScriptJobLimit;
        try scope.set(immediate, "_destroyed", c.pi_js_bool(engine.context, 1));
        _ = try scope.own(try js.getKey(engine, immediate, try scope.get(s.owner, "refed")));
        deactivate(s, immediate);
        try js.setKey(engine, immediate, try scope.get(s.owner, "refed"), c.pi_js_null());
        try scope.set(s.owner, "previous", immediate);
        const token = if (handle(s, immediate)) |retained| retained.scope else c.pi_js_undefined();
        const entered = async_scope.enter(engine, token);
        defer entered.restore();
        invokeCallback(&scope, immediate) catch |err| {
            const original = if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else null;
            defer if (original) |value| engine.freeValue(value);
            finishImmediate(&scope, s.owner, immediate) catch {};
            if (original) |value| {
                if (engine.captured_exception) |previous| engine.freeValue(previous);
                engine.captured_exception = c.JS_DupValue(engine.context, value);
            }
            return err;
        };
        try finishImmediate(&scope, s.owner, immediate);
        worked = true;
        callbacks += 1;
    }
    s.timer_phase = worked;
    return worked;
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_immediate_state != null) return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    const ordinary = try scope.object();
    try scope.put(owner, "objectPrototype", try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, ordinary))));
    inline for (.{ "head", "tail", "current", "previous" }) |name| try scope.put(owner, name, c.pi_js_null());
    try scope.put(owner, "refed", try scope.call(try scope.global("Symbol"), c.pi_js_undefined(), &.{try scope.text("refed")}));
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Object", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const prototype = try scope.object();
    const constructor = try scope.own(try @import("native_class.zig").constructor(engine, "Immediate", 2, prototype, construct, &.{owner}));
    try scope.put(owner, "constructor", constructor);
    inline for (.{ .{ "ref", Method.ref }, .{ "unref", Method.unref }, .{ "hasRef", Method.hasRef } }) |entry| {
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, entry[0], c.JS_DupValue(engine.context, try function(&scope, owner, entry[0], 0, entry[1])), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const dispose_atom = try js.atom(engine, try scope.get(try scope.global("Symbol"), "dispose"));
    defer c.JS_FreeAtom(engine.context, dispose_atom);
    const nf = @import("native_node_function.zig");
    const dispose_function = try scope.own(try nf.create(engine, "", 0, disposeFunction, &.{owner}));
    if (c.JS_DefinePropertyValue(engine.context, prototype, dispose_atom, c.JS_DupValue(engine.context, dispose_function), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    const set = try scope.own(try nf.create(engine, "setImmediate", 1, setFunction, &.{owner}));
    const clear_function = try scope.own(try nf.create(engine, "clearImmediate", 1, clearFunction, &.{owner}));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const s = try engine.gpa.create(State);
    s.* = .{ .engine = engine, .owner = c.JS_DupValue(engine.context, owner), .class = class };
    engine.native_immediate_state = s;
    engine.native_immediate_pump = pump;
    engine.native_immediate_pending = pending;
    engine.native_immediate_referenced = referenced;
    engine.native_immediate_cleanup = cleanup;
    errdefer cleanup(engine);
    try scope.put(global, "setImmediate", set);
    try scope.put(global, "clearImmediate", clear_function);
}
