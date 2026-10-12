//! Native sandbox public method bodies. Qualification installs this namespace
//! explicitly; package-wide activation waits for the remaining export gates.
const std = @import("std");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const classes = @import("native_class.zig");
const controlled = @import("native_codemode_controlled.zig");
const abort_signal = @import("abort_signal.zig");
const Box = struct {
    engine: *Engine,
    tools: c.JSValue,
    globals: c.JSValue,
    running: c.JSValue,
    timeout: c.JSValue,
    memory: usize,
    closed: bool = false,
};
const Method = enum(c_int) { start, execute, close, registerTool, unregisterTool, tools, globals };
fn state(engine: *Engine, value: c.JSValue, class: c.JSClassID) !*Box {
    if (!c.JS_IsObject(value)) return error.InvalidSandboxReceiver;
    const self: *Box = @ptrCast(@alignCast(c.JS_GetOpaque(value, class) orelse return error.InvalidSandboxReceiver));
    if (self.engine != engine) return error.InvalidSandboxReceiver;
    return self;
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *Box = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ "tools", "globals", "running", "timeout" }) |name| c.JS_FreeValueRT(runtime, @field(self, name));
    self.engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Box = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ "tools", "globals", "running", "timeout" }) |name| c.JS_MarkValue(runtime, @field(self, name), visit);
}
fn throwError(engine: *Engine, message: []const u8) anyerror {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const text = scope.text(message) catch |err| return err;
    const reason = js.builtin(engine, "Error", &.{text}) catch |err| return err;
    _ = engine.checked(c.JS_Throw(engine.context, reason)) catch |err| return err;
    unreachable;
}
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowTypeError(engine.context, "%s", @as([*:0]const u8, @errorName(err)));
}
fn values(scope: *Scope, map: c.JSValue) !c.JSValue {
    const iterator = try scope.invoke(map, "values", &.{});
    const symbol = try scope.get(try scope.global("Symbol"), "iterator");
    return scope.own(try js.collect(scope.engine, iterator, symbol));
}
fn classId(engine: *Engine, value: c.JSValue) !c.JSClassID {
    var id: u32 = 0;
    if (c.JS_ToUint32(engine.context, &id, value) < 0) return js.capture(engine);
    return id;
}
fn identifier(bytes: []const u8) bool {
    if (bytes.len == 0) return false;
    for (bytes, 0..) |byte, index| if (!(std.ascii.isAlphabetic(byte) or byte == '_' or byte == '$' or (index > 0 and std.ascii.isDigit(byte)))) return false;
    return true;
}
fn globalError(engine: *Engine, prefix: []const u8, name: c.JSValue, suffix: []const u8) anyerror {
    const text = engine.toString(name) catch |err| return err;
    defer engine.gpa.free(text);
    const message = std.fmt.allocPrint(engine.gpa, "{s}{s}{s}", .{ prefix, text, suffix }) catch |err| return err;
    defer engine.gpa.free(message);
    return throwError(engine, message);
}
pub fn checkGlobals(engine: *Engine, declared: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (c.JS_IsUndefined(declared) or c.JS_IsNull(declared)) return;
    const names = try scope.own(try js.builtin(engine, "Set", &.{}));
    const namespaces = try scope.own(try js.builtin(engine, "Set", &.{}));
    const symbol = try scope.get(try scope.global("Symbol"), "iterator");
    var iterator = try js.Iterator.init(engine, declared, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |global| {
        defer engine.freeValue(global);
        const parts = try scope.invoke(try scope.get(global, "name"), "split", &.{try scope.text(".")});
        var count: u32 = 0;
        if (c.JS_ToUint32(engine.context, &count, try scope.get(parts, "length")) < 0) return js.capture(engine);
        var valid = count <= 2;
        var first: c.JSValue = c.pi_js_undefined();
        for (0..count) |index| {
            const part = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, parts, @intCast(index))));
            const text = try engine.toString(part);
            defer engine.gpa.free(text);
            valid = valid and identifier(text);
            if (index == 0) {
                first = part;
                inline for (.{ "tools", "ALL_TOOLS", "console", "text", "image", "exit", "globalThis", "store", "load" }) |reserved| if (std.mem.eql(u8, text, reserved)) {
                    valid = false;
                };
            }
        }
        if (!valid) return globalError(engine, "Invalid global name \"", try scope.get(global, "name"), "\"");
        if (scope.truthy(try scope.invoke(names, "has", &.{try scope.get(global, "name")}))) return globalError(engine, "Global \"", try scope.get(global, "name"), "\" is already registered");
        if (count == 2) _ = try scope.invoke(namespaces, "add", &.{first});
        _ = try scope.invoke(names, "add", &.{try scope.get(global, "name")});
    }
    var namespace_iterator = try js.Iterator.init(engine, namespaces, symbol);
    defer namespace_iterator.deinit();
    errdefer namespace_iterator.closePreserving();
    while (try namespace_iterator.next()) |name| {
        defer engine.freeValue(name);
        if (scope.truthy(try scope.invoke(names, "has", &.{name}))) {
            const text = try engine.toString(name);
            defer engine.gpa.free(text);
            const message = try std.fmt.allocPrint(engine.gpa, "Global \"{s}\" conflicts with the namespace \"{s}\"", .{ text, text });
            defer engine.gpa.free(message);
            return throwError(engine, message);
        }
    }
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = if (args.len > 0 and !c.JS_IsUndefined(args[0])) args[0] else try scope.object();
    const tools = try scope.own(try js.builtin(engine, "Map", &.{}));
    const globals = try scope.own(try js.builtin(engine, "Map", &.{}));
    const running = try scope.own(try js.builtin(engine, "Set", &.{}));
    const timeout_value = try scope.get(options, "timeoutMs");
    const timeout = if (c.JS_IsNull(timeout_value) or c.JS_IsUndefined(timeout_value)) c.JS_NewInt32(engine.context, 300000) else timeout_value;
    const memory = try scope.get(options, "memoryLimitBytes");
    var limit: u64 = std.math.maxInt(usize);
    if (!c.JS_IsUndefined(memory) and !c.JS_IsNull(memory)) if (c.JS_ToIndex(engine.context, &limit, memory) < 0) return js.capture(engine);
    const prototype = try scope.get(target, "prototype");
    const object = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, try classId(engine, roots[0]))));
    const self = try engine.gpa.create(Box);
    self.* = .{ .engine = engine, .tools = c.JS_DupValue(engine.context, tools), .globals = c.JS_DupValue(engine.context, globals), .running = c.JS_DupValue(engine.context, running), .timeout = c.JS_DupValue(engine.context, timeout), .memory = @intCast(@min(limit, std.math.maxInt(usize))) };
    _ = c.JS_SetOpaque(object, self);
    const symbol = try scope.get(try scope.global("Symbol"), "iterator");
    const declared = try scope.get(options, "tools");
    if (!c.JS_IsUndefined(declared) and !c.JS_IsNull(declared)) {
        var iterator = try js.Iterator.init(engine, declared, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |tool| {
            defer engine.freeValue(tool);
            _ = try scope.invoke(object, "registerTool", &.{tool});
        }
    }
    try checkGlobals(engine, try scope.get(options, "globals"));
    const declared_globals = try scope.get(options, "globals");
    if (!c.JS_IsUndefined(declared_globals) and !c.JS_IsNull(declared_globals)) {
        var iterator = try js.Iterator.init(engine, declared_globals, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |global| {
            defer engine.freeValue(global);
            const name = try scope.get(global, "name");
            _ = try scope.invoke(globals, "set", &.{ name, global });
        }
    }
    return c.JS_DupValue(engine.context, object);
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return operate(engine, receiver, if (argc == 0) &.{} else argv[0..@intCast(argc)], @enumFromInt(magic), roots[0]) catch |err| fail(engine, err);
}
fn operate(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, operation: Method, class: c.JSValue) !c.JSValue {
    const self = try state(engine, receiver, try classId(engine, class));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else try scope.object();
    switch (operation) {
        .tools => return c.JS_DupValue(engine.context, try values(&scope, self.tools)),
        .globals => return c.JS_DupValue(engine.context, try values(&scope, self.globals)),
        .registerTool => {
            const name = try scope.get(first, "name");
            if (c.JS_ToBool(engine.context, try scope.invoke(self.tools, "has", &.{name})) != 0) {
                const text = try engine.toString(try scope.get(first, "name"));
                defer engine.gpa.free(text);
                const message = try std.fmt.allocPrint(engine.gpa, "Tool \"{s}\" is already registered", .{text});
                defer engine.gpa.free(message);
                return throwError(engine, message);
            }
            _ = try scope.invoke(self.tools, "set", &.{ try scope.get(first, "name"), first });
            return c.pi_js_undefined();
        },
        .unregisterTool => return c.JS_DupValue(engine.context, try scope.invoke(self.tools, "delete", &.{first})),
        .close => {
            self.closed = true;
            const handles = try values(&scope, self.running);
            const promises = try scope.array();
            var count: u32 = 0;
            if (c.JS_ToUint32(engine.context, &count, try scope.get(handles, "length")) < 0) return js.capture(engine);
            for (0..count) |index| {
                const handle = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, handles, @intCast(index))));
                try controlled.abort(engine, handle, "Sandbox closed");
                try scope.index(promises, @intCast(index), try scope.get(handle, "result"));
            }
            const all = try scope.invoke(try scope.global("Promise"), "all", &.{promises});
            const nothing = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, undefinedResult, "", 0)));
            return engine.checked(c.JS_PromiseThen(engine.context, all, nothing, c.pi_js_undefined()));
        },
        .start, .execute => {
            if (self.closed) {
                if (operation == .start) return throwError(engine, "Sandbox is closed");
                const error_value = try scope.own(try js.builtin(engine, "Error", &.{try scope.text("Sandbox is closed")}));
                return engine.checked(c.JS_NewSettledPromise(engine.context, true, error_value));
            }
            const holder = try scope.object();
            try scope.put(holder, "sandbox", receiver);
            try scope.put(holder, "pending", try scope.own(try js.builtin(engine, "Map", &.{})));
            try scope.put(holder, "seq", c.JS_NewInt32(engine.context, 0));
            const options = if (operation == .start) second else try scope.object();
            if (operation == .execute) {
                const snapshot = try scope.own(try js.builtin(engine, "Map", &.{self.tools}));
                try scope.put(holder, "tools", snapshot);
                try scope.put(holder, "globals", self.globals);
                try scope.put(options, "tools", try values(&scope, snapshot));
                try scope.put(options, "globals", try values(&scope, self.globals));
                const supplied_timeout = try scope.get(second, "timeoutMs");
                try scope.put(options, "timeoutMs", if (c.JS_IsUndefined(supplied_timeout) or c.JS_IsNull(supplied_timeout)) self.timeout else supplied_timeout);
                inline for (.{ "signal", "store" }) |name| try scope.put(options, name, try scope.get(second, name));
                var data = [_]c.JSValue{holder};
                const call = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, executeCall, "", 1, 0, data.len, &data)));
                try scope.put(options, "onCall", call);
            }
            var data = [_]c.JSValue{ holder, class };
            const on_finish = if (operation == .execute) try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, finishCalls, "", 0, 0, 1, &data))) else c.pi_js_undefined();
            const handle = try scope.own(try controlled.launch(engine, first, options, .{ .memory_limit = self.memory, .deterministic = operation == .start, .on_finish = if (operation == .execute) on_finish else null }));
            try scope.put(holder, "handle", handle);
            _ = try scope.invoke(self.running, "add", &.{handle});
            const completion = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, completed, "", 0, 0, data.len, &data)));
            const result = try scope.invoke(try scope.get(handle, "result"), "finally", &.{completion});
            try scope.set(handle, "result", result);
            return c.JS_DupValue(engine.context, if (operation == .start) handle else result);
        },
    }
}
fn undefinedResult(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn completed(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = blk: {
        const box = scope.get(roots[0], "sandbox") catch |err| break :blk fail(engine, err);
        const self = state(engine, box, classId(engine, roots[1]) catch |err| break :blk fail(engine, err)) catch |err| break :blk fail(engine, err);
        _ = scope.invoke(self.running, "delete", &.{scope.get(roots[0], "handle") catch |err| break :blk fail(engine, err)}) catch |err| break :blk fail(engine, err);
        break :blk c.pi_js_undefined();
    };
    return result;
}
fn finishCalls(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    abortCalls(engine, roots[0]) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn abortCalls(engine: *Engine, holder: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try scope.get(holder, "pending");
    const signals = try values(&scope, pending);
    var count: u32 = 0;
    if (c.JS_ToUint32(engine.context, &count, try scope.get(signals, "length")) < 0) return js.capture(engine);
    for (0..count) |index| {
        const signal = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, signals, @intCast(index))));
        try abort_signal.abort(engine, signal, c.pi_js_undefined());
    }
    _ = try scope.invoke(pending, "clear", &.{});
}
fn executeCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    startCall(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn startCall(engine: *Engine, holder: c.JSValue, call: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const name = try scope.get(call, "name");
    const target = try engine.toString(try scope.get(call, "target"));
    defer engine.gpa.free(target);
    const table = try scope.get(holder, if (std.mem.eql(u8, target, "tool")) "tools" else "globals");
    const tool = try scope.invoke(table, "get", &.{name});
    const signal = try scope.own(try abort_signal.create(engine));
    const id = try scope.get(call, "id");
    _ = try scope.invoke(try scope.get(holder, "pending"), "set", &.{ id, signal });
    const tool_context = try scope.object();
    try scope.put(tool_context, "signal", signal);
    const generation = engine.native_allocation_generation;
    const value = scope.invoke(tool, "execute", &.{ try scope.get(call, "args"), tool_context }) catch |err| {
        const restored = engine.nativeAllocationError(err, generation);
        if (restored != error.JavaScriptException) return restored;
        return settleCall(engine, holder, id, engine.captured_exception.?, true);
    };
    const awaited = try scope.own(try engine.checked(c.JS_PiPromiseResolve(engine.context, value)));
    var data = [_]c.JSValue{ holder, id };
    const fulfilled = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, toolComplete, "", 1, 0, data.len, &data)));
    const rejected = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, toolComplete, "", 1, 1, data.len, &data)));
    _ = try scope.own(try engine.checked(c.JS_PromiseThen(engine.context, awaited, fulfilled, rejected)));
}
fn toolComplete(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    settleCall(engine, roots[0], roots[1], if (argc > 0) argv[0] else c.pi_js_undefined(), magic != 0) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn settleCall(engine: *Engine, holder: c.JSValue, id: c.JSValue, settlement: c.JSValue, rejected: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = try scope.own(c.JS_DupValue(engine.context, settlement));
    const handle = try scope.get(holder, "handle");
    if (c.JS_ToBool(engine.context, try scope.get(handle, "finished")) != 0) return;
    _ = try scope.invoke(try scope.get(holder, "pending"), "delete", &.{id});
    const outcome = try scope.object();
    try scope.put(outcome, "ok", c.pi_js_bool(engine.context, @intFromBool(!rejected)));
    if (rejected) {
        const message = if (c.JS_IsError(value)) try scope.get(value, "message") else try scope.own(try engine.checked(c.JS_ToString(engine.context, value)));
        try scope.put(outcome, "message", message);
    } else try scope.put(outcome, "value", value);
    var seq: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &seq, try scope.get(holder, "seq")) < 0) return js.capture(engine);
    const next = c.JS_NewFloat64(engine.context, seq + 1);
    const generation = engine.native_allocation_generation;
    _ = scope.invoke(handle, "deliver", &.{ next, c.JS_NewFloat64(engine.context, @floatFromInt(std.Io.Clock.awake.now(engine.native_io.?).toMilliseconds())), id, outcome }) catch |err| {
        const restored = engine.nativeAllocationError(err, generation);
        if (restored != error.JavaScriptException or rejected) return restored;
        return settleCall(engine, holder, id, engine.captured_exception.?, true);
    };
    try scope.set(holder, "seq", next);
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    if (engine.abort_signal_class == 0) try abort_signal.install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native CodemodeSandbox", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const prototype = try scope.object();
    var data = [_]c.JSValue{c.JS_NewInt32(engine.context, @intCast(class))};
    inline for (std.meta.fields(Method)) |field| {
        const operation: Method = @enumFromInt(field.value);
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, method, field.name, if (operation == .start) 2 else if (operation == .execute or operation == .registerTool or operation == .unregisterTool) 1 else 0, @intFromEnum(operation), data.len, &data)));
        if (operation == .close) {
            const async_prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, function, async_prototype) < 0) return js.capture(engine);
        }
        if (operation == .tools or operation == .globals) {
            const atom = c.JS_NewAtom(engine.context, field.name);
            if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        } else if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const constructor = try scope.own(try classes.constructor(engine, "CodemodeSandbox", 0, prototype, construct, &data));
    try scope.put(exports, "CodemodeSandbox", constructor);
}
