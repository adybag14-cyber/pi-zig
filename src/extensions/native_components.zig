//! Owner-thread component factories and fenced native callback lifetimes.
//! Transport/frontend integration is separate; this module never touches JS off-thread.
const std = @import("std");
const engine_mod = @import("engine.zig");
pub const c = engine_mod.c;
pub const maximum_lines = 4096;
pub const maximum_frame_bytes = 1024 * 1024;

pub const Frame = @import("component_protocol.zig").Frame;

pub fn frameToValue(self: *const Frame, engine: *engine_mod.Engine) !c.JSValue {
    const array = try engine.checked(c.JS_NewArray(engine.context));
    errdefer engine.freeValue(array);
    for (self.lines, 0..) |line, index| {
        const value = try engine.checked(c.JS_NewStringLen(engine.context, line.ptr, line.len));
        if (c.JS_SetPropertyUint32(engine.context, array, @intCast(index), value) < 0) {
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
            return error.JavaScriptException;
        }
    }
    return array;
}

fn appendLines(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), bytes: *usize, text: []const u8) !void {
    if (text.len > maximum_frame_bytes - bytes.*) return error.NativeComponentFrameLimit;
    var iterator = std.mem.splitScalar(u8, text, '\n');
    while (iterator.next()) |line| {
        if (lines.items.len >= maximum_lines) return error.NativeComponentFrameLimit;
        const copy = try gpa.dupe(u8, line);
        errdefer gpa.free(copy);
        try lines.append(gpa, copy);
    }
    bytes.* += text.len;
}

/// Component.render returns string[]; a string is also accepted by the legacy
/// compatibility boundary. Copy all bytes before any later user callback.
pub fn normalize(engine: *engine_mod.Engine, value: c.JSValue) !Frame {
    const predicate = try arrayPredicate(engine);
    defer engine.freeValue(predicate);
    return normalizeWithPredicate(engine, value, predicate);
}

pub fn arrayPredicate(engine: *engine_mod.Engine) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const array = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Array"));
    defer engine.freeValue(array);
    const predicate = try engine.checked(c.JS_GetPropertyStr(engine.context, array, "isArray"));
    errdefer engine.freeValue(predicate);
    if (!c.JS_IsFunction(engine.context, predicate)) return error.NativeArrayIntrinsicMissing;
    return predicate;
}

pub fn normalizeWithPredicate(engine: *engine_mod.Engine, value: c.JSValue, predicate: c.JSValue) !Frame {
    var lines: std.ArrayList([]u8) = .empty;
    errdefer {
        for (lines.items) |line| engine.gpa.free(line);
        lines.deinit(engine.gpa);
    }
    var bytes: usize = 0;
    if (c.JS_IsString(value)) {
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        try appendLines(engine.gpa, &lines, &bytes, text);
    } else if (!c.JS_IsNull(value) and !c.JS_IsUndefined(value)) {
        var args = [_]c.JSValue{value};
        const is_array = try engine.checked(c.JS_Call(engine.context, predicate, c.pi_js_undefined(), 1, &args));
        defer engine.freeValue(is_array);
        if (c.JS_ToBool(engine.context, is_array) == 0) return error.InvalidNativeComponentLines;
        const length = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "length"));
        defer engine.freeValue(length);
        var number: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &number, length) < 0) {
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
            return error.JavaScriptException;
        }
        if (!std.math.isFinite(number) or number < 0 or number > maximum_lines) return error.NativeComponentFrameLimit;
        const count: usize = @intFromFloat(@floor(number));
        for (0..count) |index| {
            const line = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
            defer engine.freeValue(line);
            if (!c.JS_IsString(line)) return error.InvalidNativeComponentLines;
            const text = try engine.toString(line);
            defer engine.gpa.free(text);
            try appendLines(engine.gpa, &lines, &bytes, text);
        }
    }
    return .{ .gpa = engine.gpa, .lines = try lines.toOwnedSlice(engine.gpa), .bytes = bytes };
}

pub fn callMethod(engine: *engine_mod.Engine, component: c.JSValue, name: [*:0]const u8, args: []c.JSValue, optional: bool) !?c.JSValue {
    const function = try engine.checked(c.JS_GetPropertyStr(engine.context, component, name));
    defer engine.freeValue(function);
    if (c.JS_IsUndefined(function) or c.JS_IsNull(function)) {
        if (optional) return null;
        return error.NativeComponentMethodMissing;
    }
    if (!c.JS_IsFunction(engine.context, function)) return error.InvalidNativeComponentMethod;
    return try engine.checked(c.JS_Call(engine.context, function, component, @intCast(args.len), if (args.len == 0) null else args.ptr));
}

const Handle = struct { engine: *engine_mod.Engine, manager: ?*Manager, id: u64, generation: u64 };
const Entry = struct {
    id: u64,
    generation: u64,
    handle: c.JSValue,
    promise: c.JSValue,
    resolve: c.JSValue,
    reject: c.JSValue,
    component: ?c.JSValue = null,
    creating: bool = true,
    settled: bool = false,
    dirty: bool = true,
    revision: u64 = 0,
    pending_completion: ?c.JSValue = null,
    pending_success: bool = true,
};

fn handleFinalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const id = c.JS_GetClassID(object);
    const self: *Handle = @ptrCast(@alignCast(c.JS_GetOpaque(object, id) orelse return));
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    engine.gpa.destroy(self);
}

fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var class_id: u32 = 0;
    if (c.JS_ToUint32(context, &class_id, data[1]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    const handle: *Handle = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], class_id) orelse return c.JS_ThrowTypeError(context, "Invalid native component handle")));
    const value = if (argc == 0) c.pi_js_undefined() else argv[0];
    const manager = handle.manager orelse {
        if (magic == 2 and c.JS_IsObject(value)) {
            // A factory may settle after close/reload or manager destruction.
            // Its native callback needs no manager pointer to release it.
            if (callMethod(engine, value, "dispose", &.{}, true) catch null) |result| engine.freeValue(result);
        }
        return c.pi_js_undefined();
    };
    const entry = manager.entries.get(handle.id) orelse return c.pi_js_undefined();
    if (entry.generation != handle.generation or manager.generation != handle.generation or manager.retiring) return c.pi_js_undefined();
    if (magic == 2 or magic == 3) {
        if (magic == 2) manager.finishFactory(handle.id, handle.generation, value) catch |err| {
            if (err == error.JavaScriptException) return engine.throwCaptured();
            return c.JS_ThrowOutOfMemory(context);
        } else manager.rejectFactory(handle.id, handle.generation, value) catch |err| {
            if (err == error.JavaScriptException) return engine.throwCaptured();
            return c.JS_ThrowOutOfMemory(context);
        };
        return c.pi_js_undefined();
    }
    if (magic == 1) {
        if (entry.pending_completion != null) return c.pi_js_undefined();
        entry.dirty = true;
        entry.revision +%= 1;
        return c.pi_js_undefined();
    }
    manager.complete(handle.id, handle.generation, value) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return c.JS_ThrowTypeError(context, "Native component callback: %s", @as([*:0]const u8, @errorName(err)));
    };
    return c.pi_js_undefined();
}

pub const Open = struct { id: u64, generation: u64, result: c.JSValue };
pub const CompletionBridge = struct {
    context: ?*anyopaque,
    request_close: *const fn (?*anyopaque, u64, u64) anyerror!void,
};
pub const Manager = struct {
    engine: *engine_mod.Engine,
    array_is_array: c.JSValue,
    promise_type: c.JSValue,
    promise_resolve: c.JSValue,
    promise_then: c.JSValue,
    handle_class: c.JSClassID = 0,
    generation: u64 = 1,
    next_id: u64 = 1,
    retiring: bool = false,
    entries: std.AutoHashMapUnmanaged(u64, *Entry) = .empty,
    completion_bridge: ?CompletionBridge = null,

    pub fn init(engine: *engine_mod.Engine) !Manager {
        var id: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &id);
        const definition: c.JSClassDef = .{ .class_name = "Native Component Handle", .finalizer = handleFinalizer, .gc_mark = null, .call = null, .exotic = null };
        if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
        const array_is_array = try arrayPredicate(engine);
        errdefer engine.freeValue(array_is_array);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const promise_type = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Promise"));
        errdefer engine.freeValue(promise_type);
        const promise_resolve = try engine.checked(c.JS_GetPropertyStr(engine.context, promise_type, "resolve"));
        errdefer engine.freeValue(promise_resolve);
        const prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, promise_type, "prototype"));
        defer engine.freeValue(prototype);
        const promise_then = try engine.checked(c.JS_GetPropertyStr(engine.context, prototype, "then"));
        errdefer engine.freeValue(promise_then);
        if (!c.JS_IsFunction(engine.context, promise_resolve) or !c.JS_IsFunction(engine.context, promise_then)) return error.NativePromiseIntrinsicMissing;
        return .{ .engine = engine, .array_is_array = array_is_array, .promise_type = promise_type, .promise_resolve = promise_resolve, .promise_then = promise_then, .handle_class = id };
    }

    pub fn deinit(self: *Manager) void {
        self.retireGeneration(c.pi_js_undefined()) catch {};
        self.retiring = true;
        self.entries.deinit(self.engine.gpa);
        self.engine.freeValue(self.array_is_array);
        for ([_]c.JSValue{ self.promise_type, self.promise_resolve, self.promise_then }) |value| self.engine.freeValue(value);
    }
    pub fn forkInvocation(self: *const Manager) Manager {
        return .{ .engine = self.engine, .array_is_array = c.JS_DupValue(self.engine.context, self.array_is_array), .promise_type = c.JS_DupValue(self.engine.context, self.promise_type), .promise_resolve = c.JS_DupValue(self.engine.context, self.promise_resolve), .promise_then = c.JS_DupValue(self.engine.context, self.promise_then), .handle_class = self.handle_class, .generation = self.generation, .completion_bridge = self.completion_bridge };
    }

    fn freeEntry(self: *Manager, entry: *Entry) void {
        if (entry.component) |component| self.engine.freeValue(component);
        if (entry.pending_completion) |value| self.engine.freeValue(value);
        for ([_]c.JSValue{ entry.handle, entry.promise, entry.resolve, entry.reject }) |value| self.engine.freeValue(value);
        self.engine.gpa.destroy(entry);
    }

    fn settle(self: *Manager, entry: *Entry, value: c.JSValue, success: bool) !void {
        if (entry.settled) return;
        entry.settled = true;
        const function_value = c.JS_DupValue(self.engine.context, if (success) entry.resolve else entry.reject);
        defer self.engine.freeValue(function_value);
        var args = [_]c.JSValue{value};
        const result = try self.engine.checked(c.JS_Call(self.engine.context, function_value, c.pi_js_undefined(), 1, &args));
        self.engine.freeValue(result);
    }

    fn discardComponent(self: *Manager, component: c.JSValue) void {
        if (!c.JS_IsObject(component)) return;
        if (callMethod(self.engine, component, "dispose", &.{}, true) catch null) |value| self.engine.freeValue(value);
    }

    fn rejectFactory(self: *Manager, id: u64, generation: u64, reason: c.JSValue) !void {
        const entry = self.entries.get(id) orelse return;
        if (entry.generation != generation) return;
        if (entry.settled or entry.pending_completion != null) return;
        if (self.completion_bridge) |bridge| {
            entry.pending_completion = c.JS_DupValue(self.engine.context, reason);
            entry.pending_success = false;
            try bridge.request_close(bridge.context, id, generation);
            return;
        }
        try self.settle(entry, reason, false);
        self.close(id, generation, reason) catch {};
    }

    fn finishFactory(self: *Manager, id: u64, generation: u64, component: c.JSValue) !void {
        const entry = self.entries.get(id) orelse {
            self.discardComponent(component);
            return;
        };
        if (entry.generation != generation or generation != self.generation or self.retiring) {
            self.discardComponent(component);
            return;
        }
        if (!c.JS_IsObject(component)) {
            _ = c.JS_ThrowTypeError(self.engine.context, "Native custom factory must return a Component");
            const reason = c.JS_GetException(self.engine.context);
            defer self.engine.freeValue(reason);
            return self.rejectFactory(id, generation, reason);
        }
        entry.component = c.JS_DupValue(self.engine.context, component);
        entry.creating = false;
        entry.dirty = true;
        if (entry.settled) self.close(id, generation, c.pi_js_undefined()) catch {};
    }

    fn function(self: *Manager, handle: c.JSValue, name: [*:0]const u8, magic: c_int) !c.JSValue {
        var data = [_]c.JSValue{ handle, c.JS_NewInt64(self.engine.context, self.handle_class) };
        defer self.engine.freeValue(data[1]);
        return self.engine.checked(c.JS_NewCFunctionData2(self.engine.context, callback, name, 1, magic, 2, &data));
    }

    /// The caller supplies native theme/keybindings values. The TUI facade owns
    /// only requestRender here; scene/control methods are added by integration.
    pub fn open(self: *Manager, factory: c.JSValue, theme: c.JSValue, keybindings: c.JSValue) !Open {
        return self.openWithFacade(factory, theme, keybindings, c.pi_js_null());
    }

    pub fn openWithFacade(self: *Manager, factory: c.JSValue, theme: c.JSValue, keybindings: c.JSValue, facade: c.JSValue) !Open {
        const engine = self.engine;
        if (self.retiring) return error.NativeComponentGenerationRetired;
        if (!c.JS_IsFunction(engine.context, factory)) return error.InvalidNativeComponentFactory;
        if (self.entries.count() >= 128 or self.next_id > 9_007_199_254_740_991) return error.NativeComponentLimit;
        const id = self.next_id;
        self.next_id += 1;
        const generation = self.generation;
        var capabilities: [2]c.JSValue = undefined;
        const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &capabilities));
        var transferred = false;
        defer if (!transferred) for ([_]c.JSValue{ promise, capabilities[0], capabilities[1] }) |value| engine.freeValue(value);
        const handle = try engine.checked(c.JS_NewObjectClass(engine.context, self.handle_class));
        var handle_transferred = false;
        defer if (!handle_transferred) engine.freeValue(handle);
        const state = try engine.gpa.create(Handle);
        state.* = .{ .engine = engine, .manager = self, .id = id, .generation = generation };
        _ = c.JS_SetOpaque(handle, state);
        const entry = try engine.gpa.create(Entry);
        errdefer if (!transferred) engine.gpa.destroy(entry);
        entry.* = .{ .id = id, .generation = generation, .handle = handle, .promise = promise, .resolve = capabilities[0], .reject = capabilities[1] };
        try self.entries.put(engine.gpa, id, entry);
        transferred = true;
        handle_transferred = true;
        var keep = false;
        defer if (!keep) self.close(id, generation, c.pi_js_undefined()) catch {};
        const result_promise = c.JS_DupValue(engine.context, promise);
        errdefer engine.freeValue(result_promise);
        const tui = try engine.checked(c.JS_NewObjectProto(engine.context, facade));
        defer engine.freeValue(tui);
        const request = try self.function(handle, "requestRender", 1);
        if (c.JS_DefinePropertyValueStr(engine.context, tui, "requestRender", request, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        const done = try self.function(handle, "done", 0);
        defer engine.freeValue(done);
        var args = [_]c.JSValue{ tui, theme, keybindings, done };
        const returned = engine.checked(c.JS_Call(engine.context, factory, c.pi_js_undefined(), args.len, &args)) catch |err| {
            if (err != error.JavaScriptException) return err;
            if (self.entries.get(id)) |active| {
                if (!active.settled) try self.rejectFactory(id, generation, engine.captured_exception orelse c.pi_js_undefined()) else self.close(id, generation, c.pi_js_undefined()) catch {};
            }
            keep = true;
            return .{ .id = id, .generation = generation, .result = result_promise };
        };
        defer engine.freeValue(returned);
        var resolve_args = [_]c.JSValue{returned};
        const pending = try engine.checked(c.JS_Call(engine.context, self.promise_resolve, self.promise_type, 1, &resolve_args));
        defer engine.freeValue(pending);
        const state_value = c.JS_PromiseState(engine.context, pending);
        if (state_value == c.JS_PROMISE_FULFILLED or state_value == c.JS_PROMISE_REJECTED) {
            const component = c.JS_PromiseResult(engine.context, pending);
            defer engine.freeValue(component);
            if (state_value == c.JS_PROMISE_FULFILLED) try self.finishFactory(id, generation, component) else try self.rejectFactory(id, generation, component);
        } else {
            const resolved = try self.function(handle, "factoryReady", 2);
            defer engine.freeValue(resolved);
            const rejected = try self.function(handle, "factoryRejected", 3);
            defer engine.freeValue(rejected);
            var then_args = [_]c.JSValue{ resolved, rejected };
            const observed = try engine.checked(c.JS_Call(engine.context, self.promise_then, pending, 2, &then_args));
            engine.freeValue(observed);
        }
        // Resolve custom() immediately after done(), even if an asynchronous
        // factory has not returned its component yet. Reaction handles keep
        // late completion cleanup independent of this manager's lifetime.
        if (self.entries.get(id)) |active| if (active.settled) self.close(id, generation, c.pi_js_undefined()) catch {};
        keep = true;
        return .{ .id = id, .generation = generation, .result = result_promise };
    }

    fn snapshot(self: *Manager, id: u64, generation: u64) !c.JSValue {
        if (generation != self.generation or self.retiring) return error.NativeComponentGenerationRetired;
        const entry = self.entries.get(id) orelse return error.NativeComponentClosed;
        if (entry.generation != generation) return error.NativeComponentGenerationRetired;
        if (entry.pending_completion != null) return error.NativeComponentClosing;
        return c.JS_DupValue(self.engine.context, entry.component orelse return error.NativeComponentFactoryPending);
    }

    pub fn complete(self: *Manager, id: u64, generation: u64, value: c.JSValue) !void {
        if (generation != self.generation or self.retiring) return;
        const entry = self.entries.get(id) orelse return;
        if (entry.generation != generation or entry.settled or entry.pending_completion != null) return;
        if (self.completion_bridge) |bridge| {
            entry.pending_completion = c.JS_DupValue(self.engine.context, value);
            // The owner transport requests scene closure; no raw JS value
            // crosses this boundary. Keep the component until matching ACK.
            try bridge.request_close(bridge.context, id, generation);
            return;
        }
        try self.settle(entry, value, true);
        // Promise resolution can run a user then getter. Reselect the entry.
        const current = self.entries.get(id) orelse return;
        if (current.generation == generation) self.close(id, generation, c.pi_js_undefined()) catch {};
    }

    pub fn acknowledgeCompletion(self: *Manager, id: u64, generation: u64) !void {
        if (generation != self.generation or self.retiring) return;
        const entry = self.entries.get(id) orelse return;
        if (entry.generation != generation or entry.pending_completion == null) return;
        const value = c.JS_DupValue(self.engine.context, entry.pending_completion.?);
        defer self.engine.freeValue(value);
        try self.settle(entry, value, entry.pending_success);
        self.close(id, generation, c.pi_js_undefined()) catch {};
    }

    pub fn failAcknowledgement(self: *Manager, id: u64, generation: u64, reason: c.JSValue) !void {
        if (generation != self.generation or self.retiring) return;
        const entry = self.entries.get(id) orelse return;
        if (entry.generation != generation or entry.pending_completion == null) return;
        // Host cleanup can reject a staged success, but the original callback
        // rejection remains primary when cleanup also fails.
        if (!entry.pending_success) return self.acknowledgeCompletion(id, generation);
        self.engine.freeValue(entry.pending_completion.?);
        entry.pending_completion = null;
        try self.settle(entry, reason, false);
        self.close(id, generation, reason) catch {};
    }

    pub fn reject(self: *Manager, id: u64, generation: u64, reason: c.JSValue) !void {
        if (generation != self.generation or self.retiring) return;
        const entry = self.entries.get(id) orelse return;
        if (entry.generation != generation or entry.settled or entry.pending_completion != null) return;
        if (self.completion_bridge) |bridge| {
            entry.pending_completion = c.JS_DupValue(self.engine.context, reason);
            entry.pending_success = false;
            try bridge.request_close(bridge.context, id, generation);
        } else try self.rejectFactory(id, generation, reason);
    }

    pub fn property(self: *Manager, id: u64, generation: u64, name: [*:0]const u8) !c.JSValue {
        const component = try self.snapshot(id, generation);
        defer self.engine.freeValue(component);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, component, name));
    }

    pub fn render(self: *Manager, id: u64, generation: u64, width: usize) !Frame {
        if (width > 16_384) return error.NativeComponentViewportLimit;
        const component = try self.snapshot(id, generation);
        defer self.engine.freeValue(component);
        const revision = self.entries.get(id).?.revision;
        var args = [_]c.JSValue{c.JS_NewInt64(self.engine.context, @intCast(width))};
        defer self.engine.freeValue(args[0]);
        const pending = (try callMethod(self.engine, component, "render", &args, false)).?;
        defer self.engine.freeValue(pending);
        const value = try self.engine.awaitValue(pending);
        defer self.engine.freeValue(value);
        var frame = try normalizeWithPredicate(self.engine, value, self.array_is_array);
        errdefer frame.deinit();
        const active = self.entries.get(id) orelse return error.NativeComponentClosed;
        if (active.generation != generation or self.generation != generation) return error.NativeComponentGenerationRetired;
        if (active.revision == revision) active.dirty = false;
        return frame;
    }

    pub fn input(self: *Manager, id: u64, generation: u64, data: []const u8) !void {
        if (data.len > 64 * 1024) return error.NativeComponentInputLimit;
        const component = try self.snapshot(id, generation);
        defer self.engine.freeValue(component);
        var args = [_]c.JSValue{try self.engine.checked(c.JS_NewStringLen(self.engine.context, data.ptr, data.len))};
        defer self.engine.freeValue(args[0]);
        if (try callMethod(self.engine, component, "handleInput", &args, true)) |pending| {
            defer self.engine.freeValue(pending);
            const result = try self.engine.awaitValue(pending);
            self.engine.freeValue(result);
        }
        if (self.entries.get(id)) |entry| if (entry.generation == generation) {
            entry.dirty = true;
            entry.revision +%= 1;
        };
    }

    pub fn invalidate(self: *Manager, id: u64, generation: u64) !void {
        const component = try self.snapshot(id, generation);
        defer self.engine.freeValue(component);
        if (try callMethod(self.engine, component, "invalidate", &.{}, true)) |pending| {
            defer self.engine.freeValue(pending);
            const result = try self.engine.awaitValue(pending);
            self.engine.freeValue(result);
        }
        if (self.entries.get(id)) |entry| if (entry.generation == generation) {
            entry.dirty = true;
            entry.revision +%= 1;
        };
    }

    pub fn dirty(self: *Manager, id: u64, generation: u64) bool {
        if (generation != self.generation or self.retiring) return false;
        const entry = self.entries.get(id) orelse return false;
        return entry.generation == generation and entry.pending_completion == null and entry.dirty;
    }

    pub fn consumeHiddenFrame(self: *Manager, id: u64, generation: u64) void {
        if (self.entries.get(id)) |entry| if (entry.generation == generation) {
            entry.dirty = false;
        };
    }

    pub fn ready(self: *Manager, id: u64, generation: u64) bool {
        if (generation != self.generation or self.retiring) return false;
        const entry = self.entries.get(id) orelse return false;
        return entry.generation == generation and entry.pending_completion == null and !entry.creating and entry.component != null;
    }

    pub fn close(self: *Manager, id: u64, generation: u64, reason: c.JSValue) !void {
        const selected = self.entries.get(id) orelse return;
        if (selected.generation != generation) return;
        const entry = self.entries.fetchRemove(id).?.value;
        defer self.freeEntry(entry);
        const handle: *Handle = @ptrCast(@alignCast(c.JS_GetOpaque(entry.handle, self.handle_class).?));
        handle.manager = null;
        var first_error: ?anyerror = null;
        self.settle(entry, entry.pending_completion orelse reason, entry.pending_completion != null and entry.pending_success) catch |err| {
            first_error = err;
        };
        if (entry.component) |component| {
            const pending = callMethod(self.engine, component, "dispose", &.{}, true) catch |err| {
                if (first_error) |original| return original;
                return err;
            };
            if (pending) |value| {
                defer self.engine.freeValue(value);
                // Upstream dispose is synchronous; do not start an unbounded
                // await from retirement or teardown.
            }
        }
        if (first_error) |err| return err;
    }

    /// Cleanup must not replace the exception that caused the component to
    /// retire. Retain it across arbitrary dispose getters/callbacks.
    pub fn closePreservingException(self: *Manager, id: u64, generation: u64, reason: c.JSValue) !void {
        const original = if (self.engine.captured_exception) |value| c.JS_DupValue(self.engine.context, value) else null;
        defer if (original) |value| self.engine.freeValue(value);
        self.close(id, generation, reason) catch |err| {
            if (original) |value| {
                _ = self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, value))) catch {};
                return;
            }
            return err;
        };
        if (original) |value| _ = self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, value))) catch {};
    }

    pub fn retireGeneration(self: *Manager, reason: c.JSValue) !void {
        if (self.retiring) return;
        self.retiring = true;
        defer self.retiring = false;
        var first_error: ?anyerror = null;
        while (self.entries.count() != 0) {
            var entries = self.entries.iterator();
            const entry = entries.next().?.value_ptr.*;
            self.close(entry.id, entry.generation, reason) catch |err| {
                if (first_error == null) first_error = err;
            };
        }
        self.generation = std.math.add(u64, self.generation, 1) catch return error.NativeComponentGenerationLimit;
        if (first_error) |err| return err;
    }
};

test "native components retain factory result route input and invalidate then dispose once with stale callbacks fenced" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    defer manager.deinit();
    const module = try engine.evalModule("export let disposed=0;export let oldDone,oldRender;export function factory(tui,theme,keys,done){oldDone=done;oldRender=tui.requestRender;let text='first';return {render(width){return [text+':'+width,'a\\nb']},handleInput(data){if(data==='close')done('selected');else{text=data;tui.requestRender()}},invalidate(){text='invalidated'},dispose(){disposed++}}};export function stale(){oldDone('late');oldRender()}", "component-factory-input.mjs");
    defer engine.freeValue(module);
    const factory = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "factory"));
    defer engine.freeValue(factory);
    const opened = try manager.open(factory, c.pi_js_undefined(), c.pi_js_undefined());
    defer engine.freeValue(opened.result);
    var frame = try manager.render(opened.id, opened.generation, 12);
    defer frame.deinit();
    try std.testing.expectEqualStrings("first:12", frame.lines[0]);
    try std.testing.expectEqual(@as(usize, 3), frame.lines.len);
    try std.testing.expect(!manager.dirty(opened.id, opened.generation));
    try manager.input(opened.id, opened.generation, "second");
    try std.testing.expect(manager.dirty(opened.id, opened.generation));
    try manager.invalidate(opened.id, opened.generation);
    try manager.input(opened.id, opened.generation, "close");
    const result = try engine.awaitValue(opened.result);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("selected", text);
    const disposed = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "disposed"));
    defer engine.freeValue(disposed);
    var count: i32 = 0;
    _ = c.JS_ToInt32(engine.context, &count, disposed);
    try std.testing.expectEqual(@as(i32, 1), count);
    const stale = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "stale"));
    defer engine.freeValue(stale);
    const late = try engine.checked(c.JS_Call(engine.context, stale, c.pi_js_undefined(), 0, null));
    defer engine.freeValue(late);
    try std.testing.expectEqual(@as(usize, 0), manager.entries.count());
    c.JS_RunGC(engine.runtime);
}

test "native component done during factory and render disposes exactly once and render invalidation remains dirty" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    defer manager.deinit();
    const module = try engine.evalModule("export let disposed=0;export const immediate=(t,theme,keys,done)=>{done('early');return {dispose(){disposed++}}};export const closing=(t,theme,keys,done)=>({render(){done('render-close');return ['must-not-publish']},dispose(){disposed++}});export const invalidating=(t)=>{let first=true;return {render(){if(first){first=false;t.requestRender()}return ['live']},handleInput(){},invalidate(){}}}", "native-component-reentrancy.mjs");
    defer engine.freeValue(module);
    inline for (.{ "immediate", "closing", "invalidating" }) |name| {
        const factory = try engine.checked(c.JS_GetPropertyStr(engine.context, module, name));
        defer engine.freeValue(factory);
        const opened = try manager.open(factory, c.pi_js_undefined(), c.pi_js_undefined());
        defer engine.freeValue(opened.result);
        if (comptime std.mem.eql(u8, name, "immediate")) {
            try std.testing.expectEqual(@as(usize, 0), manager.entries.count());
            const result = try engine.awaitValue(opened.result);
            defer engine.freeValue(result);
        } else if (comptime std.mem.eql(u8, name, "closing")) {
            try std.testing.expectError(error.NativeComponentClosed, manager.render(opened.id, opened.generation, 12));
            const result = try engine.awaitValue(opened.result);
            defer engine.freeValue(result);
        } else {
            var first = try manager.render(opened.id, opened.generation, 12);
            defer first.deinit();
            try std.testing.expect(manager.dirty(opened.id, opened.generation));
            var second = try manager.render(opened.id, opened.generation, 12);
            defer second.deinit();
            try std.testing.expect(!manager.dirty(opened.id, opened.generation));
            try manager.input(opened.id, opened.generation, "key");
            try std.testing.expect(manager.dirty(opened.id, opened.generation));
            try manager.close(opened.id, opened.generation, c.pi_js_undefined());
        }
    }
    const disposed = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "disposed"));
    defer engine.freeValue(disposed);
    var count_value: i32 = 0;
    _ = c.JS_ToInt32(engine.context, &count_value, disposed);
    try std.testing.expectEqual(@as(i32, 2), count_value);
    c.JS_RunGC(engine.runtime);
}

test "native component render getter exception identity survives throwing disposal and generation retirement" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    defer manager.deinit();
    const module = try engine.evalModule("export const original={original:true};export let disposed=0;export const factory=()=>({get render(){throw original},dispose(){disposed++;throw Error('secondary-cleanup')}})", "native-component-original.mjs");
    defer engine.freeValue(module);
    const factory = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "factory"));
    defer engine.freeValue(factory);
    const original = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "original"));
    defer engine.freeValue(original);
    const opened = try manager.open(factory, c.pi_js_undefined(), c.pi_js_undefined());
    defer engine.freeValue(opened.result);
    try std.testing.expectError(error.JavaScriptException, manager.render(opened.id, opened.generation, 12));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.captured_exception.?));
    try manager.closePreservingException(opened.id, opened.generation, original);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.captured_exception.?));
    try manager.retireGeneration(original);
    try std.testing.expectError(error.NativeComponentGenerationRetired, manager.input(opened.id, opened.generation, "late"));
    const disposed = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "disposed"));
    defer engine.freeValue(disposed);
    var count_value: i32 = 0;
    _ = c.JS_ToInt32(engine.context, &count_value, disposed);
    try std.testing.expectEqual(@as(i32, 1), count_value);
}

fn componentAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    defer manager.deinit();
    const module = try engine.evalModule("export default ()=>({render(){return ['owned','lines']},dispose(){}})", "native-component-allocation.mjs");
    defer engine.freeValue(module);
    const factory = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "default"));
    defer engine.freeValue(factory);
    const opened = try manager.open(factory, c.pi_js_undefined(), c.pi_js_undefined());
    defer engine.freeValue(opened.result);
    var frame = try manager.render(opened.id, opened.generation, 12);
    defer frame.deinit();
    try manager.close(opened.id, opened.generation, c.pi_js_undefined());
    c.JS_RunGC(engine.runtime);
}

test "native component allocator failures release entries promise capabilities frames and retained callbacks" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, componentAllocationProbe, .{});
}

fn retireFromFactory(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const manager: *Manager = @ptrCast(@alignCast(engine.host_data.?));
    manager.retireGeneration(c.pi_js_undefined()) catch return engine.throwCaptured();
    return c.pi_js_undefined();
}

test "native async factory generation retirement disposes its late returned component and fences retained facade" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    defer manager.deinit();
    engine.host_data = &manager;
    defer engine.host_data = null;
    try engine.bindFunction("retireFactory", retireFromFactory, 0);
    const module = try engine.evalModule("export let disposed=0;export let late;export default async tui=>{late=tui.requestRender;await Promise.resolve();retireFactory();return {dispose(){disposed++}}};export function stale(){late()}", "native-component-late-factory.mjs");
    defer engine.freeValue(module);
    const factory = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "default"));
    defer engine.freeValue(factory);
    const opened = try manager.open(factory, c.pi_js_undefined(), c.pi_js_undefined());
    defer engine.freeValue(opened.result);
    try std.testing.expect(!manager.ready(opened.id, opened.generation));
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(opened.result));
    var jobs: usize = 0;
    while (c.JS_IsJobPending(engine.runtime)) : (jobs += 1) {
        if (jobs >= 1000) return error.NativeComponentTestJobLimit;
        var context: ?*c.JSContext = null;
        if (c.JS_ExecutePendingJob(engine.runtime, &context) < 0) return error.JavaScriptException;
    }
    const disposed = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "disposed"));
    defer engine.freeValue(disposed);
    var count_value: i32 = 0;
    _ = c.JS_ToInt32(engine.context, &count_value, disposed);
    try std.testing.expectEqual(@as(i32, 1), count_value);
    const stale = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "stale"));
    defer engine.freeValue(stale);
    const result = try engine.checked(c.JS_Call(engine.context, stale, c.pi_js_undefined(), 0, null));
    defer engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native component line getters preserve original exceptions and normalized frames own independent bytes" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const module = try engine.evalModule("export const original={lineGetter:true};export const lines=['stable','before'];Object.defineProperty(lines,1,{get(){throw original}});export const owned=['a\\nb','second'];", "native-component-lines.mjs");
    defer engine.freeValue(module);
    const lines = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "lines"));
    defer engine.freeValue(lines);
    const original = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "original"));
    defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, normalize(engine, lines));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.captured_exception.?));
    const owned = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "owned"));
    defer engine.freeValue(owned);
    var frame = try normalize(engine, owned);
    defer frame.deinit();
    try std.testing.expectEqual(@as(usize, 3), frame.lines.len);
    if (c.JS_SetPropertyUint32(engine.context, owned, 0, c.JS_NewString(engine.context, "mutated")) < 0) return error.JavaScriptException;
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqualStrings("a", frame.lines[0]);
    try std.testing.expectEqualStrings("b", frame.lines[1]);
}

test "native component cached array intrinsic accepts proxies after global replacement and bounds forged length" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    defer manager.deinit();
    const module = try engine.evalModule("Array.isArray=()=>false;export const factory=()=>({render(){return new Proxy(['proxy'],{})}});export const oversized=()=>({render(){return new Proxy([],{get(target,key){if(key==='length')return 4294967296;return Reflect.get(target,key)}})}})", "native-component-array-intrinsic.mjs");
    defer engine.freeValue(module);
    inline for (.{ "factory", "oversized" }) |name| {
        const factory = try engine.checked(c.JS_GetPropertyStr(engine.context, module, name));
        defer engine.freeValue(factory);
        const opened = try manager.open(factory, c.pi_js_undefined(), c.pi_js_undefined());
        defer engine.freeValue(opened.result);
        if (comptime std.mem.eql(u8, name, "factory")) {
            var frame = try manager.render(opened.id, opened.generation, 12);
            defer frame.deinit();
            try std.testing.expectEqualStrings("proxy", frame.lines[0]);
        } else try std.testing.expectError(error.NativeComponentFrameLimit, manager.render(opened.id, opened.generation, 12));
        try manager.close(opened.id, opened.generation, c.pi_js_undefined());
    }
}

test "native custom done resolves before an unresolved factory and ignores late factory or disposal failures" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    defer manager.deinit();
    const module = try engine.evalModule("export const pending=(t,theme,keys,done)=>{done('early');return new Promise(()=>{})};export const throwing=(t,theme,keys,done)=>{done('early');throw Error('ignored-late-factory')};export const disposal=(t,theme,keys,done)=>({render(){return ['ready']},handleInput(){done('early')},dispose(){throw Error('ignored-disposal')}})", "native-component-early-completion.mjs");
    defer engine.freeValue(module);
    inline for (.{ "pending", "throwing", "disposal" }) |name| {
        const factory = try engine.checked(c.JS_GetPropertyStr(engine.context, module, name));
        defer engine.freeValue(factory);
        const opened = try manager.open(factory, c.pi_js_undefined(), c.pi_js_undefined());
        defer engine.freeValue(opened.result);
        if (comptime std.mem.eql(u8, name, "disposal")) try manager.input(opened.id, opened.generation, "close");
        const result = try engine.awaitValue(opened.result);
        defer engine.freeValue(result);
        const text = try engine.toString(result);
        defer engine.gpa.free(text);
        try std.testing.expectEqualStrings("early", text);
        try std.testing.expectEqual(@as(usize, 0), manager.entries.count());
    }
    c.JS_RunGC(engine.runtime);
}

test "native asynchronous and thenable factory completion remains owner-thread ready and preserves rejection identity" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    defer manager.deinit();
    const module = try engine.evalModule("export const original={factoryFailure:true};export const asynchronous=async()=>{await Promise.resolve();return {render(){return ['async']}}};export const thenable=()=>({then(resolve){resolve({render(){return ['thenable']}})}});export const rejected=()=>({get then(){throw original}})", "native-component-promise-factories.mjs");
    defer engine.freeValue(module);
    inline for (.{ "asynchronous", "thenable", "rejected" }) |name| {
        const factory = try engine.checked(c.JS_GetPropertyStr(engine.context, module, name));
        defer engine.freeValue(factory);
        const opened = try manager.open(factory, c.pi_js_undefined(), c.pi_js_undefined());
        defer engine.freeValue(opened.result);
        var jobs: usize = 0;
        while (c.JS_IsJobPending(engine.runtime)) : (jobs += 1) {
            if (jobs >= 1000) return error.NativeComponentTestJobLimit;
            var context: ?*c.JSContext = null;
            if (c.JS_ExecutePendingJob(engine.runtime, &context) < 0) return error.JavaScriptException;
        }
        if (comptime std.mem.eql(u8, name, "rejected")) {
            const original = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "original"));
            defer engine.freeValue(original);
            try std.testing.expectError(error.JavaScriptException, engine.awaitValue(opened.result));
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.captured_exception.?));
        } else {
            try std.testing.expect(manager.ready(opened.id, opened.generation));
            var frame = try manager.render(opened.id, opened.generation, 12);
            defer frame.deinit();
            try std.testing.expectEqualStrings(if (comptime std.mem.eql(u8, name, "asynchronous")) "async" else "thenable", frame.lines[0]);
            try manager.close(opened.id, opened.generation, c.pi_js_undefined());
        }
    }
}

test "native custom async factory primary rejection waits for exact close acknowledgement and survives cleanup failure GC" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    defer manager.deinit();
    const Capture = struct {
        count: usize = 0,
        id: u64 = 0,
        generation: u64 = 0,
        fn close(context: ?*anyopaque, id: u64, generation: u64) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.count += 1;
            self.id = id;
            self.generation = generation;
        }
    };
    var capture: Capture = .{};
    manager.completion_bridge = .{ .context = &capture, .request_close = Capture.close };
    const module = try engine.evalModule("export const original={factory:true};export default async()=>{await Promise.resolve();throw original}", "factory-primary-ack.mjs");
    defer engine.freeValue(module);
    const factory = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "default"));
    defer engine.freeValue(factory);
    const original = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "original"));
    defer engine.freeValue(original);
    const opened = try manager.open(factory, c.pi_js_undefined(), c.pi_js_undefined());
    defer engine.freeValue(opened.result);
    _ = try engine.drainReadyJobs();
    try std.testing.expectEqual(@as(usize, 1), capture.count);
    try std.testing.expectEqual(opened.id, capture.id);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, opened.result));
    c.JS_RunGC(engine.runtime);
    const secondary = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(secondary);
    try manager.failAcknowledgement(opened.id, opened.generation + 1, secondary);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, opened.result));
    try manager.failAcknowledgement(opened.id, opened.generation, secondary);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, opened.result));
    const reason = c.JS_PromiseResult(engine.context, opened.result);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, original));
    try manager.failAcknowledgement(opened.id, opened.generation, secondary);
    try std.testing.expectEqual(@as(usize, 1), capture.count);
    try std.testing.expectEqual(@as(usize, 0), manager.entries.count());
    c.JS_RunGC(engine.runtime);
}

test "native custom completion bridge retains component until exact owner-thread scene close acknowledgement" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var manager = try Manager.init(engine);
    defer manager.deinit();
    const Closure = struct {
        calls: usize = 0,
        id: u64 = 0,
        generation: u64 = 0,
        fn request(context: ?*anyopaque, id: u64, generation: u64) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.calls += 1;
            self.id = id;
            self.generation = generation;
        }
    };
    var closure: Closure = .{};
    manager.completion_bridge = .{ .context = &closure, .request_close = Closure.request };
    const module = try engine.evalModule("export let disposed=0;export default (t,theme,keys,done)=>({render(){return ['active']},handleInput(){done('selected');done('duplicate')},dispose(){disposed++}})", "native-component-close-ack.mjs");
    defer engine.freeValue(module);
    const factory = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "default"));
    defer engine.freeValue(factory);
    const opened = try manager.open(factory, c.pi_js_undefined(), c.pi_js_undefined());
    defer engine.freeValue(opened.result);
    try manager.input(opened.id, opened.generation, "close");
    try std.testing.expectEqual(@as(usize, 1), closure.calls);
    try std.testing.expectEqual(@as(usize, 1), manager.entries.count());
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, opened.result));
    try std.testing.expectError(error.NativeComponentClosing, manager.input(opened.id, opened.generation, "late"));
    try manager.acknowledgeCompletion(opened.id + 1, opened.generation);
    try manager.acknowledgeCompletion(opened.id, opened.generation + 1);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, opened.result));
    try manager.acknowledgeCompletion(closure.id, closure.generation);
    const result = try engine.awaitValue(opened.result);
    defer engine.freeValue(result);
    const selected = try engine.toString(result);
    defer engine.gpa.free(selected);
    try std.testing.expectEqualStrings("selected", selected);
    const disposed = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "disposed"));
    defer engine.freeValue(disposed);
    var count_value: i32 = 0;
    _ = c.JS_ToInt32(engine.context, &count_value, disposed);
    try std.testing.expectEqual(@as(i32, 1), count_value);
    try std.testing.expectEqual(@as(usize, 0), manager.entries.count());
}
