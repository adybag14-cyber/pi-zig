//! Shared private runtime for actual public emit and eight typed reducers.
//! Shares intrinsic await ownership while preserving eight real reducer bodies.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
const reducers = @import("native_sdk_public_runner_reducers.zig");
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
pub const Kind = enum { generic, cache, message, tool_result, tool_call, request, headers, resources, input, user_bash, boundary, context, agent_start };
const Phase = enum { handler, boundary_initial, boundary_rebuild };
pub const Root = enum { runner, event, context, extension, result, resolve, reject, parameter0, parameter1, parameter2, parameter3, current, aux, aux2 };
pub const State = struct {
    allocator: std.mem.Allocator,
    values: [std.meta.fields(Root).len]c.JSValue,
    kind: Kind,
    phase: Phase = .handler,
    boundary_valid: bool = true,
    context_system: bool = false,
    context_had_leading: bool = false,
    modified: bool = false,
    early_return: bool = false,
    outer: ?js.Iterator = null,
    inner: ?js.Iterator = null,
    finished: bool = false,
    pub fn get(self: *State, root: Root) c.JSValue {
        return self.values[@intFromEnum(root)];
    }
    pub fn replace(self: *State, engine: *em.Engine, root: Root, owned: c.JSValue) void {
        engine.freeValue(self.get(root));
        self.values[@intFromEnum(root)] = owned;
    }
};
fn state(owner: c.JSValue) *State {
    return @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
}
fn finalize(runtime: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const retained: *State = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for (retained.values) |value| c.JS_FreeValueRT(runtime, value);
    if (retained.inner) |iterator| {
        c.JS_FreeValueRT(runtime, iterator.iterator);
        c.JS_FreeValueRT(runtime, iterator.next_function);
    }
    if (retained.outer) |iterator| {
        c.JS_FreeValueRT(runtime, iterator.iterator);
        c.JS_FreeValueRT(runtime, iterator.next_function);
    }
    retained.allocator.destroy(retained);
}
fn mark(runtime: ?*c.JSRuntime, owner: c.JSValue, callback: ?*const c.JS_MarkFunc) callconv(.c) void {
    const retained = state(owner);
    for (retained.values) |value| c.JS_MarkValue(runtime, value, callback);
    if (retained.inner) |iterator| {
        c.JS_MarkValue(runtime, iterator.iterator, callback);
        c.JS_MarkValue(runtime, iterator.next_function, callback);
    }
    if (retained.outer) |iterator| {
        c.JS_MarkValue(runtime, iterator.iterator, callback);
        c.JS_MarkValue(runtime, iterator.next_function, callback);
    }
}
fn create(engine: *em.Engine, runner: c.JSValue, args: []const c.JSValue, kind: Kind, functions: [2]c.JSValue) !c.JSValue {
    if (engine.native_sdk_public_emit_class == 0) {
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Native public emit continuation", .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        engine.native_sdk_public_emit_class = class;
    }
    const owner = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(engine.native_sdk_public_emit_class)));
    errdefer engine.freeValue(owner);
    const retained = try engine.gpa.create(State);
    errdefer engine.gpa.destroy(retained);
    var values: [std.meta.fields(Root).len]c.JSValue = undefined;
    for (&values) |*value| value.* = c.pi_js_undefined();
    values[@intFromEnum(Root.runner)] = c.JS_DupValue(engine.context, runner);
    values[@intFromEnum(Root.event)] = if (args.len > 0) c.JS_DupValue(engine.context, args[0]) else c.pi_js_undefined();
    values[@intFromEnum(Root.resolve)] = c.JS_DupValue(engine.context, functions[0]);
    values[@intFromEnum(Root.reject)] = c.JS_DupValue(engine.context, functions[1]);
    for (args[0..@min(args.len, 4)], 0..) |argument, index| values[@intFromEnum(Root.parameter0) + index] = c.JS_DupValue(engine.context, argument);
    retained.* = .{ .allocator = engine.gpa, .values = values, .kind = kind };
    if (c.JS_SetOpaque(owner, retained) < 0) {
        for (retained.values) |value| engine.freeValue(value);
        return error.OutOfMemory;
    }
    return owner;
}
pub fn before(engine: *em.Engine, event: c.JSValue) !c.JSValue {
    inline for (.{ "session_before_switch", "session_before_fork", "session_before_compact", "session_before_tree" }) |name| {
        const current = try sdk.get(engine, event, "type");
        defer engine.freeValue(current);
        const expected = try sdk.text(engine, name);
        defer engine.freeValue(expected);
        if (c.JS_IsStrictEqual(engine.context, current, expected)) return c.pi_js_bool(engine.context, 1);
    }
    return c.pi_js_bool(engine.context, 0);
}
pub fn emit(engine: *em.Engine, runner: c.JSValue, event: c.JSValue) !c.JSValue {
    return run(engine, runner, &.{event}, .generic);
}
pub fn run(engine: *em.Engine, runner: c.JSValue, args: []const c.JSValue, kind: Kind) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(promise);
    defer for (functions) |function| engine.freeValue(function);
    const owner = create(engine, runner, args, kind, functions) catch |err| {
        const reason = captureReason(engine, err);
        defer engine.freeValue(reason);
        const ignored = try js.call(engine, functions[1], c.pi_js_undefined(), &.{reason});
        engine.freeValue(ignored);
        return promise;
    };
    defer engine.freeValue(owner);
    start(engine, owner) catch |err| try reject(engine, owner, err);
    return promise;
}
fn start(engine: *em.Engine, owner: c.JSValue) !void {
    const retained = state(owner);
    if (retained.kind == .agent_start) {
        try @import("native_sdk_public_runner_agent_start.zig").initialize(engine, retained);
    } else {
        retained.replace(engine, .context, try js.invoke(engine, retained.get(.runner), "createContext", &.{}));
        if (retained.kind != .generic) try reducers.initialize(engine, retained);
    }
    if (retained.kind == .boundary) {
        retained.phase = .boundary_initial;
        return buildBoundary(engine, owner);
    }
    return snapshotHandlers(engine, owner);
}
fn snapshotHandlers(engine: *em.Engine, owner: c.JSValue) !void {
    const retained = state(owner);
    const extensions = try sdk.get(engine, retained.get(.runner), "extensions");
    defer engine.freeValue(extensions);
    const event_type = if (retained.kind == .generic) try sdk.get(engine, retained.get(.event), "type") else try reducers.eventType(engine, retained);
    defer engine.freeValue(event_type);
    const method = try sdk.get(engine, extensions, "map");
    defer engine.freeValue(method);
    var roots = [_]c.JSValue{event_type};
    const mapper = try engine.checked(c.JS_NewCFunctionData2(engine.context, snapshotCall, "", 1, 0, roots.len, &roots));
    defer engine.freeValue(mapper);
    const snapshot = try js.call(engine, method, extensions, &.{mapper});
    defer engine.freeValue(snapshot);
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    retained.outer = try js.Iterator.init(engine, snapshot, symbol);
    try advance(engine, owner);
}
fn snapshotCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return snapshotRow(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn snapshotRow(engine: *em.Engine, extension: c.JSValue, event_type: c.JSValue) !c.JSValue {
    const row = try sdk.object(engine);
    errdefer engine.freeValue(row);
    try sdk.put(engine, row, "ext", c.JS_DupValue(engine.context, extension));
    const registry = try sdk.get(engine, extension, "handlers");
    defer engine.freeValue(registry);
    const handlers = try js.invoke(engine, registry, "get", &.{event_type});
    defer engine.freeValue(handlers);
    const copied = if (c.JS_IsNull(handlers) or c.JS_IsUndefined(handlers)) try sdk.array(engine) else try js.invoke(engine, handlers, "slice", &.{});
    try sdk.put(engine, row, "handlers", if (c.JS_IsNull(copied) or c.JS_IsUndefined(copied)) blk: {
        engine.freeValue(copied);
        break :blk try sdk.array(engine);
    } else copied);
    return row;
}
fn advance(engine: *em.Engine, owner: c.JSValue) !void {
    const retained = state(owner);
    while (!retained.finished) {
        if (retained.inner) |*iterator| {
            if (try iterator.next()) |handler| {
                defer engine.freeValue(handler);
                // Source constructs this event outside the handler try block.
                if (retained.kind == .boundary) try reducers.prepare(engine, retained);
                const value = invokeHandler(engine, retained, handler) catch |err| {
                    if (retained.kind == .tool_call) return err;
                    const reason = captureReason(engine, err);
                    defer engine.freeValue(reason);
                    try report(engine, retained, reason);
                    if (retained.kind == .boundary and try rebuildBoundary(engine, owner)) return;
                    continue;
                };
                defer engine.freeValue(value);
                const promise = engine.checked(c.JS_PiPromiseResolve(engine.context, value)) catch |err| {
                    if (retained.kind == .tool_call) return err;
                    const reason = captureReason(engine, err);
                    defer engine.freeValue(reason);
                    try report(engine, retained, reason);
                    if (retained.kind == .boundary and try rebuildBoundary(engine, owner)) return;
                    continue;
                };
                defer engine.freeValue(promise);
                awaitHandler(engine, owner, promise) catch |err| {
                    if (retained.kind == .tool_call) return err;
                    const reason = captureReason(engine, err);
                    defer engine.freeValue(reason);
                    try report(engine, retained, reason);
                    if (retained.kind == .boundary and try rebuildBoundary(engine, owner)) return;
                    continue;
                };
                return;
            }
            iterator.deinit();
            retained.inner = null;
        }
        if (try retained.outer.?.next()) |row| {
            defer engine.freeValue(row);
            if (retained.kind != .tool_call) retained.replace(engine, .extension, try sdk.get(engine, row, "ext"));
            const handlers = try sdk.get(engine, row, "handlers");
            defer engine.freeValue(handlers);
            const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
            defer engine.freeValue(symbol);
            retained.inner = try js.Iterator.init(engine, handlers, symbol);
        } else {
            if (retained.kind == .context and !retained.context_system) {
                retained.context_system = true;
                retained.outer.?.deinit();
                retained.outer = null;
                return snapshotHandlers(engine, owner);
            }
            try finish(engine, owner);
        }
    }
}
fn invokeHandler(engine: *em.Engine, retained: *State, handler: c.JSValue) !c.JSValue {
    if (retained.kind != .generic and retained.kind != .boundary) try reducers.prepare(engine, retained);
    return js.call(engine, handler, c.pi_js_undefined(), &.{ retained.get(.event), retained.get(.context) });
}
fn awaitHandler(engine: *em.Engine, owner: c.JSValue, promise: c.JSValue) !void {
    var roots = [_]c.JSValue{owner};
    const fulfilled = try engine.checked(c.JS_NewCFunctionData2(engine.context, resumeCall, "", 1, 0, roots.len, &roots));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData2(engine.context, resumeCall, "", 1, 1, roots.len, &roots));
    defer engine.freeValue(rejected);
    const ignored = try engine.checked(c.JS_PromiseThen(engine.context, promise, fulfilled, rejected));
    engine.freeValue(ignored);
}
fn resumeCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, rejected: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    resumeValue(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), rejected != 0) catch |err| {
        reject(engine, roots[0], err) catch |failure| return sdk.fail(engine, failure);
    };
    return c.pi_js_undefined();
}
fn resumeValue(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool) !void {
    const retained = state(owner);
    if (retained.finished) return;
    if (retained.phase != .handler) {
        const initial = retained.phase == .boundary_initial;
        retained.phase = .handler;
        if (rejected) {
            if (initial) {
                _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
                return js.capture(engine);
            }
            retained.boundary_valid = false;
            try reportBoundaryBuild(engine, retained, value);
        } else {
            retained.replace(engine, .aux2, c.JS_DupValue(engine.context, value));
            retained.boundary_valid = true;
        }
        if (initial) return snapshotHandlers(engine, owner);
        return advance(engine, owner);
    }
    if (rejected) {
        if (retained.kind == .tool_call) {
            _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
            return js.capture(engine);
        }
        try report(engine, retained, value);
    } else {
        const cancel = accept(engine, retained, value) catch |err| blk: {
            if (retained.kind == .tool_call) return err;
            const reason = captureReason(engine, err);
            defer engine.freeValue(reason);
            try report(engine, retained, reason);
            break :blk false;
        };
        if (cancel) return finish(engine, owner);
    }
    if (retained.kind == .boundary and try rebuildBoundary(engine, owner)) return;
    try advance(engine, owner);
}
fn buildBoundary(engine: *em.Engine, owner: c.JSValue) !void {
    const retained = state(owner);
    const value = try js.call(engine, retained.get(.parameter1), c.pi_js_undefined(), &.{retained.get(.current)});
    defer engine.freeValue(value);
    const promise = try engine.checked(c.JS_PiPromiseResolve(engine.context, value));
    defer engine.freeValue(promise);
    try awaitHandler(engine, owner, promise);
}
fn rebuildBoundary(engine: *em.Engine, owner: c.JSValue) !bool {
    const retained = state(owner);
    retained.phase = .boundary_rebuild;
    buildBoundary(engine, owner) catch |err| {
        retained.phase = .handler;
        retained.boundary_valid = false;
        const reason = captureReason(engine, err);
        defer engine.freeValue(reason);
        try reportBoundaryBuild(engine, retained, reason);
        return false;
    };
    return true;
}
fn accept(engine: *em.Engine, retained: *State, value: c.JSValue) !bool {
    if (retained.kind != .generic) return reducers.accept(engine, retained, value);
    const before_event = try js.invoke(engine, retained.get(.runner), "isSessionBeforeEvent", &.{retained.get(.event)});
    defer engine.freeValue(before_event);
    if (c.JS_ToBool(engine.context, before_event) != 1 or c.JS_ToBool(engine.context, value) != 1) return false;
    retained.replace(engine, .result, c.JS_DupValue(engine.context, value));
    const cancel = try sdk.get(engine, value, "cancel");
    defer engine.freeValue(cancel);
    return c.JS_ToBool(engine.context, cancel) == 1;
}
fn instanceOfError(engine: *em.Engine, reason: c.JSValue) !bool {
    const constructor = try js.global(engine, "Error");
    defer engine.freeValue(constructor);
    const result = c.JS_IsInstanceOf(engine.context, reason, constructor);
    if (result < 0) return js.capture(engine);
    return result != 0;
}
fn report(engine: *em.Engine, retained: *State, reason: c.JSValue) !void {
    try reportValue(engine, retained, reason);
    // user_bash reports the exact failure and then rejects with that original
    // value. A throwing listener replaces it before this point is reached.
    if (retained.kind == .user_bash) {
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
        return js.capture(engine);
    }
}
fn reportValue(engine: *em.Engine, retained: *State, reason: c.JSValue) !void {
    if (retained.kind == .cache or retained.kind == .input or retained.kind == .boundary) return reportInline(engine, retained, reason);
    const message = try errorMessage(engine, reason);
    defer engine.freeValue(message);
    const stack = if (try instanceOfError(engine, reason)) try sdk.get(engine, reason, "stack") else c.pi_js_undefined();
    defer engine.freeValue(stack);
    const method = try sdk.get(engine, retained.get(.runner), "emitError");
    defer engine.freeValue(method);
    const error_value = try sdk.object(engine);
    defer engine.freeValue(error_value);
    try sdk.put(engine, error_value, "extensionPath", try sdk.get(engine, retained.get(.extension), "path"));
    try sdk.put(engine, error_value, "event", try reportEventType(engine, retained));
    try sdk.put(engine, error_value, "error", c.JS_DupValue(engine.context, message));
    try sdk.put(engine, error_value, "stack", c.JS_DupValue(engine.context, stack));
    const ignored = try js.call(engine, method, retained.get(.runner), &.{error_value});
    engine.freeValue(ignored);
}
fn errorMessage(engine: *em.Engine, reason: c.JSValue) !c.JSValue {
    return if (try instanceOfError(engine, reason)) sdk.get(engine, reason, "message") else blk: {
        const string = try js.global(engine, "String");
        defer engine.freeValue(string);
        break :blk try js.call(engine, string, c.pi_js_undefined(), &.{reason});
    };
}
fn reportEventType(engine: *em.Engine, retained: *State) !c.JSValue {
    return if (retained.kind == .generic) sdk.get(engine, retained.get(.event), "type") else reducers.eventType(engine, retained);
}
fn reportInline(engine: *em.Engine, retained: *State, reason: c.JSValue) !void {
    const method = try sdk.get(engine, retained.get(.runner), "emitError");
    defer engine.freeValue(method);
    const error_value = try sdk.object(engine);
    defer engine.freeValue(error_value);
    try sdk.put(engine, error_value, "extensionPath", try sdk.get(engine, retained.get(.extension), "path"));
    try sdk.put(engine, error_value, "event", try reportEventType(engine, retained));
    try sdk.put(engine, error_value, "error", try errorMessage(engine, reason));
    try sdk.put(engine, error_value, "stack", if (try instanceOfError(engine, reason)) try sdk.get(engine, reason, "stack") else c.pi_js_undefined());
    const ignored = try js.call(engine, method, retained.get(.runner), &.{error_value});
    engine.freeValue(ignored);
}
fn reportBoundaryBuild(engine: *em.Engine, retained: *State, reason: c.JSValue) !void {
    const method = try sdk.get(engine, retained.get(.runner), "emitError");
    defer engine.freeValue(method);
    const error_value = try sdk.object(engine);
    defer engine.freeValue(error_value);
    try sdk.put(engine, error_value, "extensionPath", try sdk.get(engine, retained.get(.extension), "path"));
    try sdk.put(engine, error_value, "event", try reducers.eventType(engine, retained));
    const message = try errorMessage(engine, reason);
    defer engine.freeValue(message);
    // Template substitution performs ToString, including string-hint hooks
    // and Symbol rejection, before concatenating the literal prefix.
    const converted = try engine.checked(c.JS_ToString(engine.context, message));
    defer engine.freeValue(converted);
    const prefix = try sdk.text(engine, "Invalid boundary entries: ");
    defer engine.freeValue(prefix);
    try sdk.put(engine, error_value, "error", try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, prefix, converted)));
    try sdk.put(engine, error_value, "stack", if (try instanceOfError(engine, reason)) try sdk.get(engine, reason, "stack") else c.pi_js_undefined());
    const ignored = try js.call(engine, method, retained.get(.runner), &.{error_value});
    engine.freeValue(ignored);
}
fn finish(engine: *em.Engine, owner: c.JSValue) !void {
    const retained = state(owner);
    const result = if (retained.kind == .generic) c.JS_DupValue(engine.context, retained.get(.result)) else try reducers.output(engine, retained);
    defer engine.freeValue(result);
    if (retained.inner) |*iterator| try iterator.close();
    if (retained.outer) |*iterator| try iterator.close();
    retained.finished = true;
    const ignored = try js.call(engine, retained.get(.resolve), c.pi_js_undefined(), &.{result});
    engine.freeValue(ignored);
}
fn captureReason(engine: *em.Engine, err: anyerror) c.JSValue {
    _ = sdk.fail(engine, err);
    return c.JS_GetException(engine.context);
}
fn reject(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const retained = state(owner);
    const reason = captureReason(engine, err);
    defer engine.freeValue(reason);
    // Throw completion wins over exceptions thrown while closing iterators.
    if (retained.inner) |*iterator| iterator.closePreserving();
    if (retained.outer) |*iterator| iterator.closePreserving();
    retained.finished = true;
    const ignored = try js.call(engine, retained.get(.reject), c.pi_js_undefined(), &.{reason});
    engine.freeValue(ignored);
}
