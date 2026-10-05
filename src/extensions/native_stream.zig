//! Native pi-ai event streams and acknowledged provider iteration. No host JS.
const std = @import("std");
const typebox = @import("typebox.zig");
const engine_mod = @import("engine.zig");
const providers_mod = @import("native_providers.zig");
const c = engine_mod.c;
pub const maximum_event_bytes = 512 * 1024;
pub const maximum_total_bytes = 16 * 1024 * 1024;

const Queued = struct { value: c.JSValue, bytes: usize };
const Waiter = struct { iterator: c.JSValue, resolve: c.JSValue, reject: c.JSValue };
const Stream = struct {
    engine: *engine_mod.Engine,
    assistant: bool,
    complete: c.JSValue,
    extract: c.JSValue,
    result: c.JSValue,
    result_resolve: c.JSValue,
    result_reject: c.JSValue,
    done: bool = false,
    queued_bytes: usize = 0,
    events: std.ArrayList(Queued) = .empty,
    waiting: std.ArrayList(Waiter) = .empty,
};
const Iterator = struct { engine: *engine_mod.Engine, stream: c.JSValue, closed: bool = false };

fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native provider stream: %s", @as([*:0]const u8, @errorName(err)));
}

fn property(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}

fn callOne(engine: *engine_mod.Engine, function: c.JSValue, value: c.JSValue) !void {
    var args = [_]c.JSValue{value};
    const result = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 1, &args));
    engine.freeValue(result);
}

fn iterationResult(engine: *engine_mod.Engine, value: c.JSValue, done: bool) !c.JSValue {
    const object = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    try property(engine, object, "value", c.JS_DupValue(engine.context, value));
    try property(engine, object, "done", c.pi_js_bool(engine.context, @intFromBool(done)));
    return object;
}

fn streamFinalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Stream = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.event_stream_class) orelse return));
    for ([_]c.JSValue{ self.complete, self.extract, self.result, self.result_resolve, self.result_reject }) |value| c.JS_FreeValueRT(runtime, value);
    for (self.events.items) |event| c.JS_FreeValueRT(runtime, event.value);
    for (self.waiting.items) |waiter| {
        for ([_]c.JSValue{ waiter.iterator, waiter.resolve, waiter.reject }) |value| c.JS_FreeValueRT(runtime, value);
    }
    self.events.deinit(engine.gpa);
    self.waiting.deinit(engine.gpa);
    engine.gpa.destroy(self);
}

fn streamMark(runtime: ?*c.JSRuntime, object: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Stream = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.event_stream_class) orelse return));
    for ([_]c.JSValue{ self.complete, self.extract, self.result, self.result_resolve, self.result_reject }) |value| c.JS_MarkValue(runtime, value, mark);
    for (self.events.items) |event| c.JS_MarkValue(runtime, event.value, mark);
    for (self.waiting.items) |waiter| for ([_]c.JSValue{ waiter.iterator, waiter.resolve, waiter.reject }) |value| c.JS_MarkValue(runtime, value, mark);
}

fn iteratorFinalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Iterator = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.event_stream_iterator_class) orelse return));
    c.JS_FreeValueRT(runtime, self.stream);
    engine.gpa.destroy(self);
}

fn iteratorMark(runtime: ?*c.JSRuntime, object: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Iterator = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.event_stream_iterator_class) orelse return));
    c.JS_MarkValue(runtime, self.stream, mark);
}

fn construct(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return constructValue(engine, target, false, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}

fn constructAssistant(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return constructValue(engine, target, true, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}

fn constructValue(engine: *engine_mod.Engine, target: c.JSValue, assistant: bool, args: []c.JSValue) !c.JSValue {
    var capabilities: [2]c.JSValue = undefined;
    const result = try engine.checked(c.JS_NewPromiseCapability(engine.context, &capabilities));
    errdefer engine.freeValue(result);
    errdefer for (capabilities) |value| engine.freeValue(value);
    const prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, target, "prototype"));
    defer engine.freeValue(prototype);
    const object = try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, engine.event_stream_class));
    errdefer engine.freeValue(object);
    const self = try engine.gpa.create(Stream);
    self.* = .{ .engine = engine, .assistant = assistant, .complete = c.JS_DupValue(engine.context, if (args.len > 0) args[0] else c.pi_js_undefined()), .extract = c.JS_DupValue(engine.context, if (args.len > 1) args[1] else c.pi_js_undefined()), .result = result, .result_resolve = capabilities[0], .result_reject = capabilities[1] };
    _ = c.JS_SetOpaque(object, self);
    return object;
}

fn streamCall(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const self: *Stream = @ptrCast(@alignCast(c.JS_GetOpaque(this, engine.event_stream_class) orelse return c.JS_ThrowTypeError(context, "Illegal EventStream receiver")));
    return streamOperation(self, this, magic, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}

fn streamOperation(self: *Stream, receiver: c.JSValue, method: c_int, value: c.JSValue) !c.JSValue {
    const engine = self.engine;
    if (method == 2) return c.JS_DupValue(engine.context, self.result);
    if (method == 3) {
        const iterator = try engine.checked(c.JS_NewObjectClass(engine.context, engine.event_stream_iterator_class));
        errdefer engine.freeValue(iterator);
        const state = try engine.gpa.create(Iterator);
        state.* = .{ .engine = engine, .stream = c.JS_DupValue(engine.context, value) };
        _ = c.JS_SetOpaque(iterator, state);
        return iterator;
    }
    if (method == 1) {
        self.done = true;
        if (!c.JS_IsUndefined(value)) try callOne(engine, self.result_resolve, value);
        while (self.waiting.items.len > 0) {
            const waiter = self.waiting.orderedRemove(0);
            defer for ([_]c.JSValue{ waiter.iterator, waiter.resolve, waiter.reject }) |item| engine.freeValue(item);
            const result = try iterationResult(engine, c.pi_js_undefined(), true);
            defer engine.freeValue(result);
            try callOne(engine, waiter.resolve, result);
        }
        return c.pi_js_undefined();
    }
    if (self.done) return c.pi_js_undefined();
    const encoded = try engine.stringify(value);
    defer engine.gpa.free(encoded);
    if (encoded.len > maximum_event_bytes) {
        _ = c.JS_ThrowRangeError(engine.context, "assistant stream event exceeds the native byte limit");
        _ = engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context))) catch {};
        return error.JavaScriptException;
    }
    if (self.waiting.items.len == 0 and (self.events.items.len >= 64 or encoded.len > 1024 * 1024 - self.queued_bytes)) {
        _ = c.JS_ThrowRangeError(engine.context, "assistant stream producer exceeded the bounded pending queue");
        const failure = c.JS_GetException(engine.context);
        defer engine.freeValue(failure);
        self.done = true;
        try callOne(engine, self.result_reject, failure);
        _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure))) catch {};
        return error.JavaScriptException;
    }
    const complete = if (self.assistant) blk: {
        const kind = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "type"));
        defer engine.freeValue(kind);
        const text = try engine.toString(kind);
        defer engine.gpa.free(text);
        break :blk std.mem.eql(u8, text, "done") or std.mem.eql(u8, text, "error");
    } else blk: {
        var args = [_]c.JSValue{value};
        const result = try engine.checked(c.JS_Call(engine.context, self.complete, receiver, 1, &args));
        defer engine.freeValue(result);
        break :blk c.JS_ToBool(engine.context, result) != 0;
    };
    if (complete) {
        self.done = true;
        const terminal = if (self.assistant) blk: {
            const kind = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "type"));
            defer engine.freeValue(kind);
            const text = try engine.toString(kind);
            defer engine.gpa.free(text);
            break :blk try engine.checked(c.JS_GetPropertyStr(engine.context, value, if (std.mem.eql(u8, text, "done")) "message" else "error"));
        } else blk: {
            var args = [_]c.JSValue{value};
            break :blk try engine.checked(c.JS_Call(engine.context, self.extract, receiver, 1, &args));
        };
        defer engine.freeValue(terminal);
        try callOne(engine, self.result_resolve, terminal);
    }
    if (self.waiting.items.len > 0) {
        const waiter = self.waiting.orderedRemove(0);
        defer for ([_]c.JSValue{ waiter.iterator, waiter.resolve, waiter.reject }) |item| engine.freeValue(item);
        const result = try iterationResult(engine, value, false);
        defer engine.freeValue(result);
        try callOne(engine, waiter.resolve, result);
    } else {
        const retained = c.JS_DupValue(engine.context, value);
        errdefer engine.freeValue(retained);
        try self.events.append(engine.gpa, .{ .value = retained, .bytes = encoded.len });
        self.queued_bytes += encoded.len;
    }
    return c.pi_js_undefined();
}

fn streamIterator(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const self: *Stream = @ptrCast(@alignCast(c.JS_GetOpaque(this, engine.event_stream_class) orelse return c.JS_ThrowTypeError(context, "Illegal EventStream receiver")));
    return streamOperation(self, this, 3, this) catch |err| fail(engine, err);
}

fn iteratorSelf(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_DupValue(context, this);
}

fn iteratorCall(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const self: *Iterator = @ptrCast(@alignCast(c.JS_GetOpaque(this, engine.event_stream_iterator_class) orelse return c.JS_ThrowTypeError(context, "Illegal EventStream iterator")));
    return nextIterator(self, this, magic != 0) catch |err| fail(engine, err);
}

fn nextIterator(self: *Iterator, this: c.JSValue, close: bool) !c.JSValue {
    const engine = self.engine;
    const stream: *Stream = @ptrCast(@alignCast(c.JS_GetOpaque(self.stream, engine.event_stream_class).?));
    var capabilities: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &capabilities));
    errdefer engine.freeValue(promise);
    var transferred = false;
    defer if (!transferred) for (capabilities) |value| engine.freeValue(value);
    if (close) {
        self.closed = true;
        var index: usize = 0;
        while (index < stream.waiting.items.len) {
            if (!c.JS_IsStrictEqual(engine.context, stream.waiting.items[index].iterator, this)) {
                index += 1;
                continue;
            }
            const waiter = stream.waiting.orderedRemove(index);
            defer for ([_]c.JSValue{ waiter.iterator, waiter.resolve, waiter.reject }) |value| engine.freeValue(value);
            const result = try iterationResult(engine, c.pi_js_undefined(), true);
            defer engine.freeValue(result);
            try callOne(engine, waiter.resolve, result);
        }
    }
    if (!self.closed and stream.events.items.len > 0) {
        const event = stream.events.orderedRemove(0);
        defer engine.freeValue(event.value);
        stream.queued_bytes -= event.bytes;
        const result = try iterationResult(engine, event.value, false);
        defer engine.freeValue(result);
        try callOne(engine, capabilities[0], result);
    } else if (self.closed or stream.done) {
        const result = try iterationResult(engine, c.pi_js_undefined(), true);
        defer engine.freeValue(result);
        try callOne(engine, capabilities[0], result);
    } else {
        if (stream.waiting.items.len >= 64) return error.NativeEventStreamWaiterLimit;
        const retained = c.JS_DupValue(engine.context, this);
        errdefer engine.freeValue(retained);
        try stream.waiting.append(engine.gpa, .{ .iterator = retained, .resolve = capabilities[0], .reject = capabilities[1] });
        transferred = true;
    }
    return promise;
}

fn assistantFactory(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_CallConstructor(context, data[0], 0, null);
}

pub fn install(engine: *engine_mod.Engine) !void {
    if (engine.event_stream_class != 0) return;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const symbol = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Symbol"));
    defer engine.freeValue(symbol);
    const async_symbol = try engine.checked(c.JS_GetPropertyStr(engine.context, symbol, "asyncIterator"));
    defer engine.freeValue(async_symbol);
    engine.event_stream_async_atom = c.JS_ValueToAtom(engine.context, async_symbol);
    if (engine.event_stream_async_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    _ = c.JS_NewClassID(engine.runtime, &engine.event_stream_class);
    _ = c.JS_NewClassID(engine.runtime, &engine.event_stream_iterator_class);
    const stream_definition: c.JSClassDef = .{ .class_name = "EventStream", .finalizer = streamFinalizer, .gc_mark = streamMark, .call = null, .exotic = null };
    const iterator_definition: c.JSClassDef = .{ .class_name = "EventStream Iterator", .finalizer = iteratorFinalizer, .gc_mark = iteratorMark, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, engine.event_stream_class, &stream_definition) < 0 or c.JS_NewClass(engine.runtime, engine.event_stream_iterator_class, &iterator_definition) < 0) return error.JavaScriptException;
    const prototype = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(prototype);
    inline for (.{ .{ "push", 0 }, .{ "end", 1 }, .{ "result", 2 } }) |operation| try property(engine, prototype, operation[0], try engine.checked(c.pi_js_function_magic(engine.context, streamCall, operation[0], if (operation[1] == 2) 0 else 1, operation[1])));
    if (c.JS_DefinePropertyValue(engine.context, prototype, engine.event_stream_async_atom, c.JS_NewCFunction(engine.context, streamIterator, "asyncIterator", 0), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    c.JS_SetClassProto(engine.context, engine.event_stream_class, c.JS_DupValue(engine.context, prototype));
    const iterator_prototype = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(iterator_prototype);
    try property(engine, iterator_prototype, "next", try engine.checked(c.pi_js_function_magic(engine.context, iteratorCall, "next", 0, 0)));
    try property(engine, iterator_prototype, "return", try engine.checked(c.pi_js_function_magic(engine.context, iteratorCall, "return", 0, 1)));
    if (c.JS_DefinePropertyValue(engine.context, iterator_prototype, engine.event_stream_async_atom, c.JS_NewCFunction(engine.context, iteratorSelf, "asyncIterator", 0), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    c.JS_SetClassProto(engine.context, engine.event_stream_iterator_class, c.JS_DupValue(engine.context, iterator_prototype));
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, construct, "EventStream", 2, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(constructor);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    const assistant_prototype = try engine.checked(c.JS_NewObjectProto(engine.context, prototype));
    defer engine.freeValue(assistant_prototype);
    const assistant = try engine.checked(c.JS_NewCFunction2(engine.context, constructAssistant, "AssistantMessageEventStream", 0, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(assistant);
    if (c.JS_SetConstructor(engine.context, assistant, assistant_prototype) < 0 or c.JS_SetPrototype(engine.context, assistant, constructor) < 0) return error.JavaScriptException;
    const module = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(module);
    // Register the shared schema object before immutable module export names
    // are declared. All pi-ai and Typebox aliases retain its exact identity.
    const schema_exports = if (engine.native_module_values.get("typebox")) |existing| c.JS_DupValue(engine.context, existing) else blk: {
        const created = try engine.checked(c.JS_NewObject(engine.context));
        errdefer engine.freeValue(created);
        try property(engine, created, "Type", try typebox.create(engine));
        try engine.registerValueModule("typebox", created);
        try engine.registerValueModule("@sinclair/typebox", created);
        break :blk created;
    };
    defer engine.freeValue(schema_exports);
    try property(engine, module, "Type", try engine.checked(c.JS_GetPropertyStr(engine.context, schema_exports, "Type")));
    try property(engine, module, "EventStream", c.JS_DupValue(engine.context, constructor));
    try property(engine, module, "AssistantMessageEventStream", c.JS_DupValue(engine.context, assistant));
    var factory_data = [_]c.JSValue{assistant};
    try property(engine, module, "createAssistantMessageEventStream", try engine.checked(c.JS_NewCFunctionData2(engine.context, assistantFactory, "createAssistantMessageEventStream", 0, 0, 1, &factory_data)));
    try engine.registerValueModule("@earendil-works/pi-ai", module);
    try engine.registerValueModule("@mariozechner/pi-ai", module);
    try engine.registerValueModule("pi-ai", module);
}

const BlockKind = enum { text, thinking, toolcall };
const Block = struct { kind: BlockKind, bytes: std.ArrayList(u8) = .empty, high: ?u16 = null, saw_delta: bool = false };
const Validator = struct {
    engine: *engine_mod.Engine,
    started: bool = false,
    terminal: ?enum { done, err } = null,
    reason: []u8 = &.{},
    blocks: std.AutoHashMapUnmanaged(u64, Block) = .empty,
    total_bytes: usize = 0,

    fn deinit(self: *@This()) void {
        var blocks = self.blocks.valueIterator();
        while (blocks.next()) |block| block.bytes.deinit(self.engine.gpa);
        self.blocks.deinit(self.engine.gpa);
        if (self.reason.len > 0) self.engine.gpa.free(self.reason);
    }

    fn text(self: *@This(), object: c.JSValue, key: [*:0]const u8) ![]u8 {
        const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, object, key));
        defer self.engine.freeValue(value);
        if (!c.JS_IsString(value)) return error.InvalidNativeProviderEvent;
        return self.engine.toString(value);
    }

    fn assistant(self: *@This(), value: c.JSValue) !void {
        if (!c.JS_IsObject(value) or c.JS_IsArray(value)) return error.InvalidNativeAssistantMessage;
        const role = try self.text(value, "role");
        defer self.engine.gpa.free(role);
        if (!std.mem.eql(u8, role, "assistant")) return error.InvalidNativeAssistantMessage;
        const content = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, "content"));
        defer self.engine.freeValue(content);
        if (!c.JS_IsArray(content)) return error.InvalidNativeAssistantMessage;
    }

    fn index(self: *@This(), value: c.JSValue) !u64 {
        const field = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, "contentIndex"));
        defer self.engine.freeValue(field);
        if (!c.JS_IsNumber(field)) return error.InvalidNativeProviderContentIndex;
        var number: f64 = 0;
        if (c.JS_ToFloat64(self.engine.context, &number, field) < 0) return error.JavaScriptException;
        if (!std.math.isFinite(number) or number < 0 or number > 9_007_199_254_740_991 or number != @trunc(number)) return error.InvalidNativeProviderContentIndex;
        return @intFromFloat(number);
    }

    fn appendFragment(self: *@This(), block: *Block, source: []const u8) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(self.engine.gpa);
        var iterator = (try std.unicode.Wtf8View.init(source)).iterator();
        var buffer: [4]u8 = undefined;
        while (iterator.nextCodepoint()) |point| {
            if (block.high) |high| {
                if (point < 0xdc00 or point > 0xdfff) return error.InvalidNativeProviderUnicode;
                const scalar: u21 = 0x10000 + (@as(u21, high - 0xd800) << 10) + point - 0xdc00;
                const length = try std.unicode.utf8Encode(scalar, &buffer);
                try output.appendSlice(self.engine.gpa, buffer[0..length]);
                block.high = null;
            } else if (point >= 0xd800 and point <= 0xdbff) {
                block.high = @intCast(point);
            } else if (point >= 0xdc00 and point <= 0xdfff) return error.InvalidNativeProviderUnicode else {
                const length = try std.unicode.utf8Encode(point, &buffer);
                try output.appendSlice(self.engine.gpa, buffer[0..length]);
            }
        }
        try block.bytes.appendSlice(self.engine.gpa, output.items);
        return output.toOwnedSlice(self.engine.gpa);
    }

    fn normalize(self: *@This(), raw: c.JSValue) ![]u8 {
        const encoded = try self.engine.stringify(raw);
        defer self.engine.gpa.free(encoded);
        const terminated = try self.engine.gpa.dupeZ(u8, encoded);
        defer self.engine.gpa.free(terminated);
        const event = try self.engine.checked(c.JS_ParseJSON(self.engine.context, terminated.ptr, encoded.len, "native-provider-event"));
        defer self.engine.freeValue(event);
        if (!c.JS_IsObject(event) or c.JS_IsArray(event)) return error.InvalidNativeProviderEvent;
        const kind = try self.text(event, "type");
        defer self.engine.gpa.free(kind);
        if (self.terminal != null) return error.NativeProviderEventAfterTerminal;
        if (std.mem.eql(u8, kind, "start")) {
            if (self.started) return error.DuplicateNativeProviderStart;
            const partial = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, event, "partial"));
            defer self.engine.freeValue(partial);
            try self.assistant(partial);
            self.started = true;
        } else {
            if (!self.started) return error.NativeProviderEventBeforeStart;
            const terminal = std.mem.eql(u8, kind, "done") or std.mem.eql(u8, kind, "error");
            if (terminal) {
                if (self.blocks.count() != 0) return error.NativeProviderUnclosedContent;
                const reason = try self.text(event, "reason");
                errdefer self.engine.gpa.free(reason);
                const success = std.mem.eql(u8, kind, "done");
                const allowed = if (success) std.mem.eql(u8, reason, "stop") or std.mem.eql(u8, reason, "length") or std.mem.eql(u8, reason, "toolUse") or std.mem.eql(u8, reason, "deferred") else std.mem.eql(u8, reason, "error") or std.mem.eql(u8, reason, "aborted");
                if (!allowed) return error.InvalidNativeProviderTerminalReason;
                const message = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, event, if (success) "message" else "error"));
                defer self.engine.freeValue(message);
                try self.assistant(message);
                self.terminal = if (success) .done else .err;
                self.reason = reason;
            } else {
                const partial = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, event, "partial"));
                defer self.engine.freeValue(partial);
                try self.assistant(partial);
                const block_kind: BlockKind = if (std.mem.eql(u8, kind, "text_start") or std.mem.eql(u8, kind, "text_delta") or std.mem.eql(u8, kind, "text_end")) .text else if (std.mem.eql(u8, kind, "thinking_start") or std.mem.eql(u8, kind, "thinking_delta") or std.mem.eql(u8, kind, "thinking_end")) .thinking else if (std.mem.eql(u8, kind, "toolcall_start") or std.mem.eql(u8, kind, "toolcall_delta") or std.mem.eql(u8, kind, "toolcall_end")) .toolcall else return error.InvalidNativeProviderEvent;
                const key = try self.index(event);
                if (std.mem.endsWith(u8, kind, "_start")) {
                    if (self.blocks.contains(key)) return error.DuplicateNativeProviderContent;
                    if (self.blocks.count() >= 4096) return error.NativeProviderContentLimit;
                    try self.blocks.put(self.engine.gpa, key, .{ .kind = block_kind });
                } else {
                    const block = self.blocks.getPtr(key) orelse return error.NativeProviderContentNotStarted;
                    if (block.kind != block_kind) return error.NativeProviderContentKindMismatch;
                    if (std.mem.endsWith(u8, kind, "_delta")) {
                        const delta = try self.text(event, "delta");
                        defer self.engine.gpa.free(delta);
                        const normalized = try self.appendFragment(block, delta);
                        defer self.engine.gpa.free(normalized);
                        block.saw_delta = true;
                        try property(self.engine, event, "delta", try self.engine.checked(c.JS_NewStringLen(self.engine.context, normalized.ptr, normalized.len)));
                    } else if (std.mem.endsWith(u8, kind, "_end")) {
                        if (block.high != null) return error.InvalidNativeProviderUnicode;
                        if (block_kind != .toolcall) {
                            const content = try self.text(event, "content");
                            defer self.engine.gpa.free(content);
                            if (block.saw_delta and !std.mem.eql(u8, content, block.bytes.items)) return error.NativeProviderContentMismatch;
                        } else {
                            const call = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, event, "toolCall"));
                            defer self.engine.freeValue(call);
                            if (!c.JS_IsObject(call) or c.JS_IsArray(call)) return error.InvalidNativeProviderToolCall;
                            const call_type = try self.text(call, "type");
                            defer self.engine.gpa.free(call_type);
                            const id = try self.text(call, "id");
                            defer self.engine.gpa.free(id);
                            const name = try self.text(call, "name");
                            defer self.engine.gpa.free(name);
                            if (!std.mem.eql(u8, call_type, "toolCall") or id.len == 0 or name.len == 0) return error.InvalidNativeProviderToolCall;
                            const arguments = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, call, "arguments"));
                            defer self.engine.freeValue(arguments);
                            if (!c.JS_IsObject(arguments) or c.JS_IsArray(arguments)) return error.InvalidNativeProviderToolCall;
                            if (block.saw_delta) {
                                var expected = try std.json.parseFromSlice(std.json.Value, self.engine.gpa, block.bytes.items, .{});
                                defer expected.deinit();
                                const source = try self.engine.stringify(arguments);
                                defer self.engine.gpa.free(source);
                                var actual = try std.json.parseFromSlice(std.json.Value, self.engine.gpa, source, .{});
                                defer actual.deinit();
                                if (!jsonEqual(expected.value, actual.value)) return error.NativeProviderToolArgumentsMismatch;
                            }
                        }
                        var removed = self.blocks.fetchRemove(key).?.value;
                        removed.bytes.deinit(self.engine.gpa);
                    } else return error.InvalidNativeProviderEvent;
                }
            }
        }
        const result = try self.engine.stringify(event);
        errdefer self.engine.gpa.free(result);
        if (result.len > maximum_event_bytes or result.len > maximum_total_bytes - self.total_bytes) return error.NativeProviderStreamSizeLimit;
        self.total_bytes += result.len;
        return result;
    }
};

fn jsonEqual(a: std.json.Value, b: std.json.Value) bool {
    if ((a == .integer or a == .float) and (b == .integer or b == .float)) {
        // JSON parsed by the extension follows ECMAScript Number semantics,
        // including equivalent 1/1.0 spellings and integer rounding above 2^53.
        const left: f64 = if (a == .integer) @floatFromInt(a.integer) else a.float;
        const right: f64 = if (b == .integer) @floatFromInt(b.integer) else b.float;
        return left == right;
    }
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null => true,
        .bool => a.bool == b.bool,
        .integer => a.integer == b.integer,
        .float => a.float == b.float,
        .number_string, .string => std.mem.eql(u8, if (a == .string) a.string else a.number_string, if (b == .string) b.string else b.number_string),
        .array => blk: {
            if (a.array.items.len != b.array.items.len) break :blk false;
            for (a.array.items, b.array.items) |left, right| if (!jsonEqual(left, right)) break :blk false;
            break :blk true;
        },
        .object => blk: {
            if (a.object.count() != b.object.count()) break :blk false;
            var entries = a.object.iterator();
            while (entries.next()) |entry| if (!jsonEqual(entry.value_ptr.*, b.object.get(entry.key_ptr.*) orelse break :blk false)) break :blk false;
            break :blk true;
        },
    };
}

pub const Bridge = struct { context: ?*anyopaque, event: *const fn (?*anyopaque, u64, []const u8) anyerror!void };

pub fn freezeJson(engine: *engine_mod.Engine, value: c.JSValue, depth: usize) !void {
    if (!c.JS_IsObject(value)) return;
    if (depth > 256) return error.NativeProviderInputDepth;
    var properties: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, value, c.JS_GPN_STRING_MASK) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, properties, count);
    for (properties[0..count]) |field| {
        const child = try engine.checked(c.JS_GetProperty(engine.context, value, field.atom));
        defer engine.freeValue(child);
        // Only the actual invocation signal is excluded; JSON input may not
        // carry runtime objects. Its mutable native abort state stays live.
        if (c.JS_GetOpaque(child, engine.abort_signal_class) == null) try freezeJson(engine, child, depth + 1);
        if (c.JS_DefineProperty(engine.context, value, field.atom, c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), c.JS_PROP_HAS_WRITABLE | c.JS_PROP_HAS_CONFIGURABLE) < 0) return error.JavaScriptException;
    }
    if (c.JS_PreventExtensions(engine.context, value) < 0) return error.JavaScriptException;
}

pub const Runner = struct {
    engine: *engine_mod.Engine,
    active: bool = false,
    cleaning: bool = false,
    providers: ?*providers_mod.Providers = null,
    provider: []const u8 = "",
    callback: []const u8 = "",
    generation: u64 = 0,
    signal: ?c.JSValue = null,
    ack: ?struct { sequence: u64, resolve: c.JSValue, reject: c.JSValue } = null,

    pub fn poll(self: *Runner) !void {
        if (!self.active or self.cleaning) return;
        const aborted = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, self.signal.?, "aborted"));
        defer self.engine.freeValue(aborted);
        if (c.JS_ToBool(self.engine.context, aborted) != 0) {
            const reason = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, self.signal.?, "reason"));
            defer self.engine.freeValue(reason);
            _ = try self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason)));
            return error.JavaScriptException;
        }
        if (!self.providers.?.live(self.callback, self.provider, self.generation)) return error.NativeProviderStreamRetired;
    }

    pub fn acknowledge(self: *Runner, sequence: u64, ok: bool, accepted: bool, message: c.JSValue) !void {
        const pending = self.ack orelse return;
        if (sequence != pending.sequence) return;
        self.ack = null;
        defer self.engine.freeValue(pending.resolve);
        defer self.engine.freeValue(pending.reject);
        if (ok and accepted) try callOne(self.engine, pending.resolve, c.pi_js_bool(self.engine.context, 1)) else {
            const failure = try self.engine.checked(c.JS_NewError(self.engine.context));
            defer self.engine.freeValue(failure);
            try property(self.engine, failure, "message", c.JS_DupValue(self.engine.context, message));
            try callOne(self.engine, pending.reject, failure);
        }
    }

    fn clearAck(self: *Runner) void {
        if (self.ack) |pending| {
            self.engine.freeValue(pending.resolve);
            self.engine.freeValue(pending.reject);
        }
        self.ack = null;
    }

    fn awaitAck(self: *Runner, bridge: Bridge, sequence: u64, event: []const u8) !void {
        var capabilities: [2]c.JSValue = undefined;
        const promise = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &capabilities));
        defer self.engine.freeValue(promise);
        self.ack = .{ .sequence = sequence, .resolve = capabilities[0], .reject = capabilities[1] };
        defer self.clearAck();
        try bridge.event(bridge.context, sequence, event);
        const result = try self.engine.awaitValue(promise);
        self.engine.freeValue(result);
    }

    fn retire(self: *Runner, iterator: c.JSValue) bool {
        self.cleaning = true;
        defer self.cleaning = false;
        const previous = self.engine.options.host_await_timeout_ms;
        self.engine.options.host_await_timeout_ms = 250;
        defer self.engine.options.host_await_timeout_ms = previous;
        const function = self.engine.checked(c.JS_GetPropertyStr(self.engine.context, iterator, "return")) catch return true;
        defer self.engine.freeValue(function);
        if (!c.JS_IsFunction(self.engine.context, function)) return true;
        const pending = self.engine.checked(c.JS_Call(self.engine.context, function, iterator, 0, null)) catch return true;
        defer self.engine.freeValue(pending);
        const result = self.engine.awaitValue(pending) catch |err| return err != error.NativeHostPromiseTimeout;
        self.engine.freeValue(result);
        return true;
    }

    pub fn consume(self: *Runner, providers: *providers_mod.Providers, callback: []const u8, provider: []const u8, generation: u64, args: c.JSValue, signal: c.JSValue, bridge: Bridge, invocation_id: []const u8, cancel_only: bool) !c.JSValue {
        if (self.active) return error.NativeProviderStreamBusy;
        try providers.validate(callback, provider, generation);
        self.active = true;
        self.providers = providers;
        self.callback = callback;
        self.provider = provider;
        self.generation = generation;
        self.signal = signal;
        defer {
            self.clearAck();
            self.active = false;
            self.signal = null;
            self.providers = null;
        }
        const previous_timeout = self.engine.options.host_await_timeout_ms;
        self.engine.options.host_await_timeout_ms = 0;
        defer self.engine.options.host_await_timeout_ms = previous_timeout;
        const returned = try providers.invokeUnsettled(callback, args);
        defer self.engine.freeValue(returned);
        const stream = try self.engine.awaitValue(returned);
        defer self.engine.freeValue(stream);
        if (cancel_only) return self.engine.checked(c.JS_NewObject(self.engine.context));
        const get_iterator = try self.engine.checked(c.JS_GetProperty(self.engine.context, stream, self.engine.event_stream_async_atom));
        defer self.engine.freeValue(get_iterator);
        if (!c.JS_IsFunction(self.engine.context, get_iterator)) return error.NativeProviderStreamNotAsyncIterable;
        const iterator = try self.engine.checked(c.JS_Call(self.engine.context, get_iterator, stream, 0, null));
        defer self.engine.freeValue(iterator);
        var validator: Validator = .{ .engine = self.engine };
        defer validator.deinit();
        var sequence: u64 = 0;
        self.iterate(iterator, bridge, &validator, &sequence) catch |err| {
            var original: ?c.JSValue = null;
            if (err == error.JavaScriptException) {
                if (self.engine.captured_exception) |value| original = c.JS_DupValue(self.engine.context, value);
            }
            defer if (original) |value| self.engine.freeValue(value);
            if (!self.retire(iterator)) {
                const failure = try self.engine.checked(c.JS_NewError(self.engine.context));
                defer self.engine.freeValue(failure);
                const text = if (original) |value| self.engine.toString(value) catch null else null;
                defer if (text) |value| self.engine.gpa.free(value);
                const message = try std.fmt.allocPrint(self.engine.gpa, "PI_PROVIDER_STREAM_RETIRE_TIMEOUT: {s}", .{text orelse "native iterator did not settle return()"});
                defer self.engine.gpa.free(message);
                try property(self.engine, failure, "message", try self.engine.checked(c.JS_NewStringLen(self.engine.context, message.ptr, message.len)));
                if (original) |value| try property(self.engine, failure, "cause", c.JS_DupValue(self.engine.context, value));
                _ = self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, failure))) catch {};
                return error.JavaScriptException;
            }
            if (original) |value| _ = self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, value))) catch {};
            return err;
        };
        if (validator.terminal == null) return error.NativeProviderStreamMissingTerminal;
        const summary = try self.engine.checked(c.JS_NewObject(self.engine.context));
        errdefer self.engine.freeValue(summary);
        try property(self.engine, summary, "invocationId", try self.engine.fromJsonValue(.{ .string = invocation_id }));
        try property(self.engine, summary, "events", c.JS_NewInt64(self.engine.context, @intCast(sequence)));
        try property(self.engine, summary, "terminal", c.JS_NewString(self.engine.context, if (validator.terminal.? == .done) "done" else "error"));
        try property(self.engine, summary, "reason", try self.engine.fromJsonValue(.{ .string = validator.reason }));
        try property(self.engine, summary, "bytes", c.JS_NewInt64(self.engine.context, @intCast(validator.total_bytes)));
        return summary;
    }

    fn iterate(self: *Runner, iterator: c.JSValue, bridge: Bridge, validator: *Validator, sequence: *u64) !void {
        while (true) {
            try self.poll();
            const next = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, iterator, "next"));
            defer self.engine.freeValue(next);
            const pending = try self.engine.checked(c.JS_Call(self.engine.context, next, iterator, 0, null));
            defer self.engine.freeValue(pending);
            const step = try self.engine.awaitValue(pending);
            defer self.engine.freeValue(step);
            try self.poll();
            if (!c.JS_IsObject(step)) return error.InvalidNativeProviderIteratorResult;
            const done = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, step, "done"));
            defer self.engine.freeValue(done);
            if (c.JS_ToBool(self.engine.context, done) != 0) return;
            const value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, step, "value"));
            defer self.engine.freeValue(value);
            const event = try validator.normalize(value);
            defer self.engine.gpa.free(event);
            sequence.* = std.math.add(u64, sequence.*, 1) catch return error.NativeProviderSequenceExhausted;
            try self.awaitAck(bridge, sequence.*, event);
        }
    }
};

test "native pi-ai EventStream exports preserve queue terminal result receiver and iterator cleanup" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const module = try engine.evalModule(
        "import {EventStream,AssistantMessageEventStream,createAssistantMessageEventStream} from '@earendil-works/pi-ai';import {EventStream as alias} from '@mariozechner/pi-ai';if(alias!==EventStream)throw Error('alias');const s=new EventStream(function(e){if(this!==s)throw Error('predicate receiver');return e.final},function(e){if(this!==s)throw Error('extract receiver');return e.value});s.push({value:1});s.push({final:true,value:2});s.push({value:3});let values=[];for await(const item of s)values.push(item.value);if(values.join(',')!=='1,2'||await s.result()!==2)throw Error('generic stream');const a=createAssistantMessageEventStream();if(!(a instanceof EventStream)||!(a instanceof AssistantMessageEventStream))throw Error('stream brand');const message={role:'assistant',content:[]};a.push({type:'done',message});if(await a.result()!==message)throw Error('result identity');const iterator=a[Symbol.asyncIterator]();if((await iterator.next()).value.message!==message||!(await iterator.next()).done)throw Error('terminal iteration');const open=new EventStream(()=>false,x=>x),waiting=open[Symbol.asyncIterator](),pending=waiting.next();await waiting.return();if(!(await pending).done)throw Error('return pending iterator');open.end(7);if(await open.result()!==7)throw Error('end result');",
        "native-event-stream.mjs",
    );
    defer engine.freeValue(module);
}

fn streamAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try install(engine);
    const target = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(target);
    try property(engine, target, "prototype", try engine.checked(c.JS_NewObject(engine.context)));
    const value = try constructValue(engine, target, true, &.{});
    defer engine.freeValue(value);
    const state: *Stream = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.event_stream_class).?));
    const event = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(event);
    try property(engine, event, "type", try engine.checked(c.JS_NewString(engine.context, "start")));
    _ = try streamOperation(state, value, 0, event);
    const iterator = try streamOperation(state, value, 3, value);
    defer engine.freeValue(iterator);
    const iterator_state: *Iterator = @ptrCast(@alignCast(c.JS_GetOpaque(iterator, engine.event_stream_iterator_class).?));
    const queued = try nextIterator(iterator_state, iterator, false);
    defer engine.freeValue(queued);
    const waiting = try nextIterator(iterator_state, iterator, false);
    defer engine.freeValue(waiting);
    c.JS_RunGC(engine.runtime);
    _ = try streamOperation(state, value, 1, event);
    const settled = try engine.awaitValue(waiting);
    defer engine.freeValue(settled);
    c.JS_RunGC(engine.runtime);
}

test "native EventStream allocation failures release queued values pending capabilities and iterator cycles" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, streamAllocationProbe, .{});
}

test "native EventStream producer queue overflow rejects its original result and closes after queued values" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const module = try engine.evalModule(
        "import {EventStream} from 'pi-ai';const stream=new EventStream(()=>false,x=>x);const failure=stream.result().catch(e=>e);for(let i=0;i<64;i++)stream.push(i);let original;try{stream.push(65)}catch(e){original=e}if(!(original instanceof RangeError)||await failure!==original)throw Error('queue failure identity');let count=0;for await(const event of stream)count++;if(count!==64)throw Error('queue cleanup');stream.push(66);",
        "native-event-queue-limit.mjs",
    );
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}

test "native provider validation accepts only exact event names numeric indices and JavaScript JSON number equality" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var validator: Validator = .{ .engine = engine, .started = true };
    defer validator.deinit();
    for ([_][]const u8{
        "{\"type\":\"text_extra_start\",\"contentIndex\":0,\"partial\":{\"role\":\"assistant\",\"content\":[]}}",
        "{\"type\":\"text_start\",\"contentIndex\":\"0\",\"partial\":{\"role\":\"assistant\",\"content\":[]}}",
    }, 0..) |source, index_value| {
        const event = try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "event-validation"));
        defer engine.freeValue(event);
        try std.testing.expectError(if (index_value == 0) error.InvalidNativeProviderEvent else error.InvalidNativeProviderContentIndex, validator.normalize(event));
    }
    var left = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"one\":1.0,\"large\":9007199254740993}", .{});
    defer left.deinit();
    var right = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"large\":9007199254740992,\"one\":1}", .{});
    defer right.deinit();
    try std.testing.expect(jsonEqual(left.value, right.value));
}

test "native provider cancellation retains supplied reason identity through throwing and hostile iterator cleanup" {
    const abort_signal = @import("abort_signal.zig");
    const Control = struct {
        fn pump(_: *engine_mod.Engine) !bool {
            return false;
        }
        fn event(_: ?*anyopaque, _: u64, _: []const u8) !void {
            return error.UnexpectedCancelledStreamEvent;
        }
    };
    for ([_]bool{ false, true }) |hostile| {
        const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        engine.native_io = std.testing.io;
        engine.host_control_pump = Control.pump;
        try abort_signal.install(engine);
        try install(engine);
        var providers = providers_mod.Providers.init(engine);
        defer providers.deinit();
        const source = if (hostile)
            "export const original={supplied:'cancelled-by-native-185'};export const config={callback(){return {[Symbol.asyncIterator](){return this},next(){return new Promise(()=>{})},return(){return new Promise(()=>{})}}}}"
        else
            "export const original={supplied:'cancelled-by-native-185'};export const config={callback(){return {[Symbol.asyncIterator](){return this},next(){return new Promise(()=>{})},return(){throw Error('secondary-cleanup-must-not-replace')}}}}";
        const module = try engine.evalModule(source, "native-stream-cancel-reason.mjs");
        defer engine.freeValue(module);
        const original = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "original"));
        defer engine.freeValue(original);
        const config = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "config"));
        defer engine.freeValue(config);
        const encoded = try providers.register("owned", config, false);
        defer engine.freeValue(encoded);
        const descriptor = try engine.checked(c.JS_GetPropertyStr(engine.context, encoded, "callback"));
        defer engine.freeValue(descriptor);
        const id_value = try engine.checked(c.JS_GetPropertyStr(engine.context, descriptor, "__pi_callback_id"));
        defer engine.freeValue(id_value);
        const id = try engine.toString(id_value);
        defer engine.gpa.free(id);
        const arguments = try engine.checked(c.JS_NewArray(engine.context));
        defer engine.freeValue(arguments);
        const signal = try abort_signal.create(engine);
        defer engine.freeValue(signal);
        try abort_signal.abort(engine, signal, original);
        var runner: Runner = .{ .engine = engine };
        try std.testing.expectError(error.JavaScriptException, runner.consume(&providers, id, "owned", 1, arguments, signal, .{ .context = null, .event = Control.event }, "1", false));
        if (hostile) {
            const failure = engine.captured_exception.?;
            const cause = try engine.checked(c.JS_GetPropertyStr(engine.context, failure, "cause"));
            defer engine.freeValue(cause);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, cause));
            try std.testing.expect(std.mem.indexOf(u8, engine.last_error.?, "PI_PROVIDER_STREAM_RETIRE_TIMEOUT") != null);
        } else try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.captured_exception.?));
        try std.testing.expect(!runner.active and !runner.cleaning);
    }
}
