//! JavaScript-facing host execution for a controlled CodeMode run. The native
//! worker owns its VM; this owner alone calls user callbacks and settles result.
const std = @import("std");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const worker_mod = @import("../mcp/codemode_vm_worker.zig");
const run_mod = @import("../mcp/codemode_run.zig");
const host_mod = @import("../mcp/codemode_run_host.zig");
const json = @import("../mcp/protocol.zig").json;
const scopes = @import("native_async_scope.zig");
const Pending = struct { record: ?usize, started: i64 };
pub const Policy = struct { memory_limit: usize = std.math.maxInt(usize), deterministic: bool = true, worker_message_tasks: bool = false, interrupt_budget: ?f64 = null, on_finish: ?c.JSValue = null };
const Owner = struct {
    engine: *Engine,
    worker: ?*worker_mod.Session = null,
    host: host_mod.Host,
    pending: std.AutoHashMapUnmanaged(u64, Pending) = .empty,
    data: json.Owned,
    selected: ?json.Owned = null,
    finished: bool = false,
    worker_message_tasks: bool = false,
    resolve: c.JSValue,
    on_started: c.JSValue,
    on_call: c.JSValue,
    on_idle: c.JSValue,
    signal: c.JSValue,
    abort_listener: c.JSValue,
    async_scope: c.JSValue,
    deadline: ?i64 = null,
    timeout_ms: ?u64 = null,
    timeout_label: ?[]const u8 = null,
    on_finish: c.JSValue,

    fn release(self: *Owner, runtime: ?*c.JSRuntime) void {
        if (self.worker) |worker| worker.deinit();
        self.host.deinit();
        self.pending.deinit(self.engine.gpa);
        self.data.deinit();
        if (self.selected) |*value| value.deinit();
        // Runtime cycle collection can invoke this finalizer after the owning
        // JSContext has been destroyed. The runtime supplied by C stays valid.
        inline for (.{ "resolve", "on_started", "on_call", "on_idle", "signal", "abort_listener", "async_scope", "on_finish" }) |name| c.JS_FreeValueRT(runtime, @field(self, name));
        self.engine.gpa.destroy(self);
    }
    fn elapsed(self: *Owner, began: i64) i64 {
        return @max(0, std.Io.Clock.awake.now(self.engine.native_io.?).toMilliseconds() - began);
    }
    fn completeCall(self: *Owner, pending: Pending, status: []const u8) !void {
        const index = pending.record orelse return;
        const a = self.data.arena.allocator();
        const record = &self.data.value.object.getPtr("calls").?.array.items[index];
        try record.object.put(a, "status", .{ .string = status });
        try record.object.put(a, "durationMs", .{ .integer = self.elapsed(pending.started) });
    }
    fn finish(self: *Owner, result: json.Value) !void {
        if (self.finished) return;
        var selected = try json.Owned.empty(self.engine.gpa);
        errdefer selected.deinit();
        const a = selected.arena.allocator();
        // Preserve the public host result's insertion order as well as its
        // values; the VM transport builds its fields in a different order.
        selected.value = .{ .object = .empty };
        inline for (.{ "ok", "error", "value" }) |name| if (result.object.get(name)) |value| try selected.value.object.put(a, name, try json.clone(a, value));
        var pending = self.pending.valueIterator();
        while (pending.next()) |call| try self.completeCall(call.*, "cancelled");
        try selected.value.object.put(a, "output", try json.clone(a, self.data.value.object.get("output").?));
        try selected.value.object.put(a, "calls", try json.clone(a, self.data.value.object.get("calls").?));
        inline for (.{ "storeWrites", "during" }) |name| if (result.object.get(name)) |value| try selected.value.object.put(a, name, try json.clone(a, value));
        self.selected = selected;
        self.finished = true;
        self.host.finish();
        if (!c.JS_IsUndefined(self.on_finish)) {
            const cleanup = try js.call(self.engine, self.on_finish, c.pi_js_undefined(), &.{});
            self.engine.freeValue(cleanup);
        }
        if (!c.JS_IsUndefined(self.abort_listener)) {
            const event_name = try stringValue(self.engine, "abort");
            defer self.engine.freeValue(event_name);
            const removed = try js.invoke(self.engine, self.signal, "removeEventListener", &.{ event_name, self.abort_listener });
            self.engine.freeValue(removed);
        }
        if (self.worker) |worker| worker.abort();
    }
    fn failure(self: *Owner, kind: []const u8, message: []const u8) !void {
        var result = try json.Owned.empty(self.engine.gpa);
        defer result.deinit();
        const a = result.arena.allocator();
        result.value = .{ .object = .empty };
        try result.value.object.put(a, "ok", .{ .bool = false });
        var error_value: json.Value = .{ .object = .empty };
        try error_value.object.put(a, "kind", .{ .string = kind });
        try error_value.object.put(a, "message", .{ .string = message });
        try result.value.object.put(a, "error", error_value);
        try self.finish(result.value);
    }
    fn callback(self: *Owner, function: c.JSValue, args: []const c.JSValue) !void {
        const generation = self.engine.native_allocation_generation;
        const value = js.call(self.engine, function, c.pi_js_undefined(), args) catch |err| {
            const restored = self.engine.nativeAllocationError(err, generation);
            if (restored != error.JavaScriptException) return restored;
            const reason = self.engine.captured_exception orelse return err;
            const message = try errorMessage(self.engine, reason);
            defer self.engine.gpa.free(message);
            const full = try std.fmt.allocPrint(self.engine.gpa, "Sandbox host failed: {s}", .{message});
            defer self.engine.gpa.free(full);
            return self.failure("sandbox", full);
        };
        self.engine.freeValue(value);
    }
    fn event(self: *Owner, value: json.Value) !void {
        if (self.finished) return;
        const guard = scopes.enter(self.engine, self.async_scope);
        defer guard.restore();
        const kind = value.object.get("type").?.string;
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        if (std.mem.eql(u8, kind, "started")) {
            if (!c.JS_IsUndefined(self.on_started)) try self.callback(self.on_started, &.{try scope.text(value.object.get("fingerprint").?.string)});
        } else if (std.mem.eql(u8, kind, "idle")) {
            if (!c.JS_IsUndefined(self.on_idle)) try self.callback(self.on_idle, &.{ c.JS_NewFloat64(self.engine.context, try json.asNumber(value.object.get("seq").?)), c.JS_NewFloat64(self.engine.context, try json.asNumber(value.object.get("issued").?)) });
        } else if (std.mem.eql(u8, kind, "output")) {
            try self.data.value.object.getPtr("output").?.array.append(try json.clone(self.data.arena.allocator(), value.object.get("item").?));
        } else if (std.mem.eql(u8, kind, "call")) {
            const id: u64 = @intCast(try json.asInteger(value.object.get("id").?));
            try self.host.issue(id);
            const a = self.data.arena.allocator();
            const record: ?usize = if (std.mem.eql(u8, value.object.get("target").?.string, "tool")) record: {
                var call: json.Value = .{ .object = .empty };
                try call.object.put(a, "name", try json.clone(a, value.object.get("name").?));
                try call.object.put(a, "status", .{ .string = "cancelled" });
                try call.object.put(a, "durationMs", .{ .integer = 0 });
                const calls = &self.data.value.object.getPtr("calls").?.array;
                try calls.append(call);
                break :record calls.items.len - 1;
            } else null;
            try self.pending.put(self.engine.gpa, id, .{ .record = record, .started = std.Io.Clock.awake.now(self.engine.native_io.?).toMilliseconds() });
            const call = try scope.object();
            inline for (.{ "id", "target", "name" }) |name| try scope.put(call, name, try scope.own(try parsed(self.engine, value.object.get(name).?)));
            try scope.put(call, "args", if (value.object.get("args")) |args| try scope.own(try parsed(self.engine, args)) else c.pi_js_undefined());
            try self.callback(self.on_call, &.{call});
        } else if (std.mem.eql(u8, kind, "done")) try self.finish(value.object.get("result").?);
    }
};
const Hub = struct {
    engine: *Engine,
    class: c.JSClassID,
    active: std.ArrayList(c.JSValue) = .empty,
    pumping: bool = false,
};
fn owner(value: c.JSValue) ?*Owner {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value))));
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    if (owner(value)) |state| state.release(runtime);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state = owner(value) orelse return;
    inline for (.{ "resolve", "on_started", "on_call", "on_idle", "signal", "abort_listener", "async_scope", "on_finish" }) |name| c.JS_MarkValue(runtime, @field(state, name), visit);
}
fn hub(engine: *Engine) !*Hub {
    if (engine.native_codemode_owner) |raw| return @ptrCast(@alignCast(raw));
    if (engine.native_io == null) return error.NativeCodeModeIoUnavailable;
    const self = try engine.gpa.create(Hub);
    errdefer engine.gpa.destroy(self);
    self.* = .{ .engine = engine, .class = 0 };
    _ = c.JS_NewClassID(engine.runtime, &self.class);
    const definition: c.JSClassDef = .{ .class_name = "CodemodeRun", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, self.class, &definition) < 0) return error.OutOfMemory;
    engine.native_codemode_owner = self;
    engine.native_codemode_pump = pump;
    engine.native_codemode_deinit = deinit;
    return self;
}
fn deinit(engine: *Engine) void {
    const self: *Hub = @ptrCast(@alignCast(engine.native_codemode_owner.?));
    engine.native_codemode_owner = null;
    engine.native_codemode_pump = null;
    engine.native_codemode_deinit = null;
    for (self.active.items) |handle| {
        const state = owner(handle).?;
        if (state.worker) |worker| {
            worker.deinit();
            state.worker = null;
        }
        engine.freeValue(handle);
    }
    self.active.deinit(engine.gpa);
    engine.gpa.destroy(self);
}
fn pump(engine: *Engine) !bool {
    const self: *Hub = @ptrCast(@alignCast(engine.native_codemode_owner.?));
    if (self.pumping) return false;
    // Node dispatches worker messages as separate tasks. Each task's Promise
    // continuations finish before another message is admitted, including an
    // async tool callback that returns a synchronous value.
    self.pumping = true;
    defer self.pumping = false;
    var worked = false;
    var index: usize = 0;
    while (index < self.active.items.len) {
        const handle = self.active.items[index];
        const state = owner(handle).?;
        const worker = state.worker.?;
        if (state.worker_message_tasks and c.JS_IsJobPending(engine.runtime)) {
            index += 1;
            continue;
        }
        if (!state.finished) if (state.deadline) |deadline| if (std.Io.Clock.awake.now(engine.native_io.?).toMilliseconds() >= deadline) {
            const message = try std.fmt.allocPrint(engine.gpa, "Execution timed out after {s} ms", .{state.timeout_label.?});
            defer engine.gpa.free(message);
            try state.failure("timeout", message);
        };
        var count: usize = 0;
        while (count < 128) : (count += 1) {
            var event = (worker.next() catch |err| {
                if (err == error.OutOfMemory) return err;
                try state.failure("sandbox", @errorName(err));
                break;
            }) orelse break;
            defer event.deinit();
            worked = true;
            try state.event(event.value);
            if (state.worker_message_tasks and c.JS_IsJobPending(engine.runtime)) return worked;
        }
        if (state.finished and worker.isCompleted()) {
            const guard = scopes.enter(engine, state.async_scope);
            defer guard.restore();
            worker.join();
            const result = try parsed(engine, state.selected.?.value);
            defer engine.freeValue(result);
            const settled = try js.call(engine, state.resolve, c.pi_js_undefined(), &.{result});
            engine.freeValue(settled);
            worker.deinit();
            state.worker = null;
            _ = self.active.swapRemove(index);
            engine.freeValue(handle);
            worked = true;
        } else index += 1;
    }
    return worked;
}
fn parsed(engine: *Engine, value: json.Value) !c.JSValue {
    const bytes = try json.stringify(engine.gpa, value);
    defer engine.gpa.free(bytes);
    const terminated = try engine.gpa.dupeZ(u8, bytes);
    defer engine.gpa.free(terminated);
    return engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, terminated.len, "codemode-host.json"));
}
fn errorMessage(engine: *Engine, value: c.JSValue) ![]u8 {
    if (c.JS_IsError(value)) {
        const message = try js.get(engine, value, "message");
        defer engine.freeValue(message);
        return engine.toString(message);
    }
    return engine.toString(value);
}
fn throwError(engine: *Engine, message: []const u8) anyerror {
    const message_value = stringValue(engine, message) catch |err| return err;
    defer engine.freeValue(message_value);
    const reason = js.builtin(engine, "Error", &.{message_value}) catch |err| return err;
    _ = engine.checked(c.JS_Throw(engine.context, reason)) catch |err| return err;
    unreachable;
}
fn stringValue(engine: *Engine, bytes: []const u8) !c.JSValue {
    return engine.checked(c.JS_NewStringLen(engine.context, bytes.ptr, bytes.len));
}
fn failed(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowInternalError(engine.context, "%s", @as([*:0]const u8, @errorName(err)));
}
fn finished(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const state = owner(data[0]) orelse return c.JS_ThrowTypeError(context, "Invalid CodemodeRun receiver");
    return c.pi_js_bool(context, @intFromBool(state.finished));
}
fn delivery(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const state = owner(data[0]) orelse return c.JS_ThrowTypeError(context, "Invalid CodemodeRun receiver");
    deliver(state, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| return failed(engine, err);
    return c.pi_js_undefined();
}
fn deliver(self: *Owner, args: []const c.JSValue) !void {
    if (self.finished) return;
    const engine = self.engine;
    const seq = if (args.len > 0) args[0] else c.pi_js_undefined();
    const now = if (args.len > 1) args[1] else c.pi_js_undefined();
    const id = if (args.len > 2) args[2] else c.pi_js_undefined();
    const outcome = if (args.len > 3) args[3] else c.pi_js_undefined();
    var number: f64 = undefined;
    var clock: f64 = undefined;
    var call_id: f64 = undefined;
    const seq_text = try engine.toString(seq);
    defer engine.gpa.free(seq_text);
    if (!c.JS_IsNumber(now) or c.JS_ToFloat64(engine.context, &clock, now) < 0 or !std.math.isFinite(clock)) {
        const text = try std.fmt.allocPrint(engine.gpa, "The clock value of result {s} is not a finite number", .{seq_text});
        defer engine.gpa.free(text);
        return throwError(engine, text);
    }
    if (!c.JS_IsNumber(seq) or c.JS_ToFloat64(engine.context, &number, seq) < 0 or !std.math.isFinite(number) or number < 1 or @floor(number) != number or self.host.delivered.contains(@bitCast(number))) {
        const text = try std.fmt.allocPrint(engine.gpa, "Result number {s} is not a positive integer used once", .{seq_text});
        defer engine.gpa.free(text);
        return throwError(engine, text);
    }
    if (!c.JS_IsNumber(id) or c.JS_ToFloat64(engine.context, &call_id, id) < 0 or !std.math.isFinite(call_id) or call_id < 0 or @floor(call_id) != call_id or call_id > 9007199254740991 or !self.pending.contains(@intFromFloat(call_id))) {
        const id_text = try engine.toString(id);
        defer engine.gpa.free(id_text);
        const text = try std.fmt.allocPrint(engine.gpa, "Call {s} is not waiting for a result", .{id_text});
        defer engine.gpa.free(text);
        return throwError(engine, text);
    }
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const ok = c.JS_ToBool(engine.context, try scope.get(outcome, "ok")) != 0;
    const properties = if (ok) c.pi_js_undefined() else try scope.get(outcome, "properties");
    if (!c.JS_IsUndefined(properties) and (!c.JS_IsObject(properties) or c.JS_IsNull(properties) or c.JS_IsArray(properties) or c.JS_IsFunction(engine.context, properties))) {
        const text = try std.fmt.allocPrint(engine.gpa, "The properties of result {s} are not an object", .{seq_text});
        defer engine.gpa.free(text);
        return throwError(engine, text);
    }
    const payload = if (ok) try scope.get(outcome, "value") else try scope.get(outcome, "message");
    const bytes = if (ok) try serialized(engine, payload) else try engine.toString(payload);
    defer if (bytes) |text| engine.gpa.free(text);
    const props = if (c.JS_IsUndefined(properties)) null else try serialized(engine, properties);
    defer if (props) |text| engine.gpa.free(text);
    const native: host_mod.Outcome = if (ok) .{ .success = bytes } else .{ .failure = .{ .message = bytes orelse "undefined", .properties = props } };
    if (self.finished) return;
    const key: u64 = @intFromFloat(call_id);
    try self.host.deliver(number, clock, key, native);
    var accepted = self.host.early.fetchRemove(@bitCast(number)).?.value;
    defer accepted.deinit();
    const pending = self.pending.fetchRemove(key).?.value;
    try self.completeCall(pending, if (ok) "ok" else "error");
    try self.worker.?.post(number, clock, key, native);
}
fn serialized(engine: *Engine, value: c.JSValue) !?[]u8 {
    if (c.JS_IsUndefined(value)) return null;
    const json_object = try js.global(engine, "JSON");
    defer engine.freeValue(json_object);
    const encoded = try js.invoke(engine, json_object, "stringify", &.{value});
    defer engine.freeValue(encoded);
    return if (c.JS_IsUndefined(encoded)) null else try engine.toString(encoded);
}

fn snapshotStore(engine: *Engine, input: c.JSValue) !json.Owned {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const object = try scope.global("Object");
    const entries = try scope.invoke(object, "entries", &.{if (c.JS_IsNull(input) or c.JS_IsUndefined(input)) try scope.object() else input});
    const encoded = try scope.object();
    var count: u32 = 0;
    if (c.JS_ToUint32(engine.context, &count, try scope.get(entries, "length")) < 0) return js.capture(engine);
    // Upstream enumerates the container once and stringifies each value.
    // Its ordinary assignment semantics also apply to names like __proto__.
    for (0..count) |index| {
        const entry = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(index))));
        const key = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entry, 0)));
        const value = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entry, 1)));
        const text = try scope.invoke(try scope.global("JSON"), "stringify", &.{value});
        if (!c.JS_IsUndefined(text)) try js.setKey(engine, encoded, key, text);
    }
    const stored = try scope.invoke(object, "entries", &.{encoded});
    if (c.JS_ToUint32(engine.context, &count, try scope.get(stored, "length")) < 0) return js.capture(engine);
    var result = try json.Owned.empty(engine.gpa);
    errdefer result.deinit();
    result.value = .{ .object = .empty };
    for (0..count) |index| {
        const entry = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, stored, @intCast(index))));
        const key = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entry, 0)));
        const encoded_value = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entry, 1)));
        const name = try engine.toString(key);
        defer engine.gpa.free(name);
        const bytes = try engine.toString(encoded_value);
        defer engine.gpa.free(bytes);
        var parsed_value = try json.Owned.parse(engine.gpa, bytes);
        defer parsed_value.deinit();
        const a = result.arena.allocator();
        try result.value.object.put(a, try a.dupe(u8, name), try json.clone(a, parsed_value.value));
    }
    return result;
}
fn ownedText(engine: *Engine, arena: std.mem.Allocator, value: c.JSValue) ![]const u8 {
    const bytes = try engine.toString(value);
    defer engine.gpa.free(bytes);
    return arena.dupe(u8, bytes);
}
fn abortSignal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const state = owner(data[0]) orelse return c.pi_js_undefined();
    signalAborted(state) catch |err| return failed(engine, err);
    return c.pi_js_undefined();
}
fn signalAborted(self: *Owner) !void {
    const reason = try js.get(self.engine, self.signal, "reason");
    defer self.engine.freeValue(reason);
    const message = if (c.JS_IsError(reason)) try errorMessage(self.engine, reason) else try self.engine.gpa.dupe(u8, "Execution aborted");
    defer self.engine.gpa.free(message);
    try self.failure("aborted", message);
}

/// The sandbox class supplies memory/stack policy. All declared tools/globals
/// and callbacks belong to this run, independently of registered execute tools.
pub fn start(engine: *Engine, code: c.JSValue, options: c.JSValue, memory_limit: usize) !c.JSValue {
    return launch(engine, code, options, .{ .memory_limit = memory_limit });
}
pub fn launch(engine: *Engine, code: c.JSValue, options: c.JSValue, policy: Policy) !c.JSValue {
    const self = try hub(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const started = if (policy.deterministic) try scope.get(options, "startedAt") else c.JS_NewInt32(engine.context, 0);
    const seed = if (policy.deterministic) try scope.get(options, "seed") else c.JS_NewInt32(engine.context, 0);
    var time: f64 = undefined;
    var random: f64 = undefined;
    if (!c.JS_IsNumber(started) or c.JS_ToFloat64(engine.context, &time, started) < 0 or !std.math.isFinite(time) or time < 0) return throwError(engine, "startedAt must be a non-negative number of milliseconds since the epoch");
    if (!c.JS_IsNumber(seed) or c.JS_ToFloat64(engine.context, &random, seed) < 0 or !std.math.isFinite(random) or random < 0 or random > 4294967295 or @floor(random) != random) return throwError(engine, "seed must be a 32-bit unsigned integer");
    var inputs = std.heap.ArenaAllocator.init(engine.gpa);
    defer inputs.deinit();
    const a = inputs.allocator();
    const declared = try scope.get(options, "tools");
    var length: u32 = 0;
    if (!c.JS_IsUndefined(declared) and !c.JS_IsNull(declared)) {
        const value = try scope.get(declared, "length");
        if (c.JS_ToUint32(engine.context, &length, value) < 0) return js.capture(engine);
    }
    const tools = try a.alloc(run_mod.Tool, length);
    for (tools, 0..) |*tool, index| {
        const value = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, declared, @intCast(index))));
        const name = try scope.get(value, "name");
        const alias = try scope.get(value, "jsName");
        const description = try scope.get(value, "description");
        tool.* = .{ .name = try ownedText(engine, a, name), .js_name = if (c.JS_IsUndefined(alias) or c.JS_IsNull(alias)) null else try ownedText(engine, a, alias), .description = if (c.JS_IsUndefined(description) or c.JS_IsNull(description)) "" else try ownedText(engine, a, description) };
    }
    const declared_globals = try scope.get(options, "globals");
    var global_count: u32 = 0;
    if (!c.JS_IsUndefined(declared_globals) and !c.JS_IsNull(declared_globals)) if (c.JS_ToUint32(engine.context, &global_count, try scope.get(declared_globals, "length")) < 0) return js.capture(engine);
    const globals = try a.alloc(run_mod.Global, global_count);
    for (globals, 0..) |*global, index| {
        const value = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, declared_globals, @intCast(index))));
        global.* = .{ .name = try ownedText(engine, a, try scope.get(value, "name")), .spread = c.JS_IsStrictEqual(engine.context, try scope.get(value, "spread"), c.pi_js_bool(engine.context, 1)) };
    }
    if (policy.deterministic) run_mod.validateDeclarations(engine.gpa, tools, globals) catch |err| switch (err) {
        error.DuplicateToolName => return throwError(engine, "Tool names must be unique"),
        error.DuplicateToolScriptName => return throwError(engine, "Tool script names must be unique"),
        else => return err,
    };
    const source = try engine.toString(code);
    defer engine.gpa.free(source);
    const handle = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, self.class)));
    var functions: [2]c.JSValue = undefined;
    const raw_promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    defer engine.freeValue(functions[0]);
    defer engine.freeValue(functions[1]);
    const promise = try scope.own(raw_promise);
    const on_started = try scope.get(options, "onStarted");
    const on_call = try scope.get(options, "onCall");
    const on_idle = try scope.get(options, "onIdle");
    const signal = try scope.get(options, "signal");
    var host = try host_mod.Host.init(engine.gpa, time, random);
    var data = try json.Owned.empty(engine.gpa);
    var transferred = false;
    errdefer if (!transferred) {
        host.deinit();
        data.deinit();
    };
    const state = try engine.gpa.create(Owner);
    state.* = .{ .engine = engine, .host = host, .data = data, .resolve = c.JS_DupValue(engine.context, functions[0]), .on_started = c.JS_DupValue(engine.context, on_started), .on_call = c.JS_DupValue(engine.context, on_call), .on_idle = c.JS_DupValue(engine.context, on_idle), .signal = c.JS_DupValue(engine.context, signal), .abort_listener = c.pi_js_undefined(), .async_scope = scopes.capture(engine), .on_finish = c.JS_DupValue(engine.context, policy.on_finish orelse c.pi_js_undefined()), .worker_message_tasks = policy.worker_message_tasks };
    _ = c.JS_SetOpaque(handle, state);
    transferred = true;
    state.data.value = .{ .object = .empty };
    inline for (.{ "calls", "output" }) |name| try state.data.value.object.put(state.data.arena.allocator(), name, .{ .array = .init(state.data.arena.allocator()) });
    const store_value = try scope.get(options, "store");
    var store = try snapshotStore(engine, store_value);
    defer store.deinit();
    // The worker has a separate allocation domain, as an upstream worker does.
    // Outer owner allocation faults must not race another thread's allocator.
    const timeout_value = try scope.get(options, "timeoutMs");
    if (c.JS_IsNumber(timeout_value)) {
        var timeout_number: f64 = undefined;
        if (c.JS_ToFloat64(engine.context, &timeout_number, timeout_value) < 0) return js.capture(engine);
        if (std.math.isFinite(timeout_number)) {
            // The upstream worker host uses Node timers: finite delays outside
            // 1..2^31-1 become 1 ms; fractional accepted delays are truncated.
            state.timeout_ms = if (timeout_number < 1 or timeout_number > 2147483647) 1 else @intFromFloat(@trunc(timeout_number));
            state.timeout_label = try ownedText(engine, state.data.arena.allocator(), timeout_value);
            state.deadline = std.Io.Clock.awake.now(engine.native_io.?).toMilliseconds() +| @as(i64, @intCast(state.timeout_ms.?));
        }
    }
    state.worker = try worker_mod.Session.create(std.heap.smp_allocator, engine.native_io.?, source, .{ .started_at = time, .seed = random, .tools = tools, .globals = globals, .store = store.value, .memory_limit = policy.memory_limit, .interrupt_budget = policy.interrupt_budget, .deterministic = policy.deterministic, .notify_context = engine, .notify = Engine.notifyOwner });
    try scope.put(handle, "result", promise);
    var handle_root = [_]c.JSValue{handle};
    try scope.put(handle, "deliver", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, delivery, "deliver", 4, 0, handle_root.len, &handle_root))));
    const getter = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, finished, "get finished", 0, 0, handle_root.len, &handle_root)));
    const finished_atom = c.JS_NewAtom(engine.context, "finished");
    if (finished_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, finished_atom);
    if (c.JS_DefinePropertyGetSet(engine.context, handle, finished_atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    try self.active.ensureUnusedCapacity(engine.gpa, 1);
    if (!c.JS_IsUndefined(state.signal) and !c.JS_IsNull(state.signal)) {
        var root = [_]c.JSValue{handle};
        state.abort_listener = try engine.checked(c.JS_NewCFunctionData2(engine.context, abortSignal, "", 0, 0, root.len, &root));
        const event = try scope.text("abort");
        _ = try scope.invoke(state.signal, "addEventListener", &.{ event, state.abort_listener });
        if (c.JS_ToBool(engine.context, try scope.get(state.signal, "aborted")) != 0) try signalAborted(state);
    }
    try state.worker.?.start();
    self.active.appendAssumeCapacity(c.JS_DupValue(engine.context, handle));
    return c.JS_DupValue(engine.context, handle);
}

pub fn abort(engine: *Engine, handle: c.JSValue, message: []const u8) !void {
    const raw = engine.native_codemode_owner orelse return error.InvalidCodeModeRun;
    const owner_hub: *Hub = @ptrCast(@alignCast(raw));
    if (!c.JS_IsObject(handle) or c.JS_GetClassID(handle) != owner_hub.class) return error.InvalidCodeModeRun;
    const state = owner(handle) orelse return error.InvalidCodeModeRun;
    if (state.engine != engine) return error.InvalidCodeModeRun;
    try state.failure("aborted", message);
}

test "native CodeMode JavaScript owner drains host microtasks between already buffered worker messages" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(exports);
    try @import("native_codemode_sandbox.zig").install(engine, exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try js.get(engine, exports, "CodemodeSandbox");
    defer engine.freeValue(constructor);
    if (c.JS_SetPropertyStr(engine.context, global, "BufferedSandbox", c.JS_DupValue(engine.context, constructor)) < 0) return js.capture(engine);
    const pending = try engine.eval(
        "globalThis.bufferedSignal=null;globalThis.bufferedBox=new BufferedSandbox({tools:[{name:'echo',execute(args,context){bufferedSignal=context.signal;return 1}}]});bufferedBox.execute('tools.echo(1);return 9')",
        "buffered-worker-host-checkpoint.js",
        c.JS_EVAL_TYPE_GLOBAL,
    );
    defer engine.freeValue(pending);
    const owner_hub: *Hub = @ptrCast(@alignCast(engine.native_codemode_owner.?));
    try std.testing.expectEqual(@as(usize, 1), owner_hub.active.items.len);
    const worker = owner(owner_hub.active.items[0]).?.worker.?;
    // The worker does not await the tool result. Force its call and completion
    // messages to be available together before the host handles either one.
    const deadline = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() + 5000;
    while (!worker.isCompleted()) {
        if (std.Io.Clock.awake.now(std.testing.io).toMilliseconds() >= deadline) return error.BufferedWorkerDidNotComplete;
        try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    }
    const result = try engine.awaitValue(pending);
    defer engine.freeValue(result);
    const encoded = try engine.stringify(result);
    defer std.testing.allocator.free(encoded);
    var observed = try json.Owned.parse(std.testing.allocator, encoded);
    defer observed.deinit();
    try std.testing.expectEqual(@as(f64, 9), observed.value.object.get("value").?.float);
    const calls = observed.value.object.get("calls").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), calls.len);
    try std.testing.expectEqualStrings("ok", calls[0].object.get("status").?.string);
    const signal = try js.get(engine, global, "bufferedSignal");
    defer engine.freeValue(signal);
    const aborted = try js.get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    try std.testing.expect(c.JS_ToBool(engine.context, aborted) == 0);
    const closing = try engine.eval("bufferedBox.close()", "buffered-worker-close.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(closing);
    const closed = try engine.awaitValue(closing);
    engine.freeValue(closed);
}

test "native CodeMode JavaScript owner finalizer releases retained values after its context is gone" {
    const runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
    defer c.JS_FreeRuntime(runtime);
    const context = c.JS_NewContext(runtime) orelse return error.OutOfMemory;
    var context_live = true;
    defer if (context_live) c.JS_FreeContext(context);
    // Finalization may only use the allocator and the runtime passed by C.
    // The rest of this engine deliberately has no usable host context.
    var detached_engine: Engine = undefined;
    detached_engine.gpa = std.testing.allocator;
    detached_engine.context = context;
    detached_engine.runtime = runtime;
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "ContextlessCodeModeOwner", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(runtime, class, &definition) < 0) return error.OutOfMemory;
    const handle = c.JS_NewObjectProtoClass(context, c.pi_js_null(), class);
    if (c.JS_IsException(handle)) return error.OutOfMemory;
    defer c.JS_FreeValueRT(runtime, handle);
    const retained = c.JS_NewString(context, "retained CodeMode cleanup root");
    if (c.JS_IsException(retained)) return error.OutOfMemory;
    errdefer c.JS_FreeValueRT(runtime, retained);
    var data = try json.Owned.empty(std.testing.allocator);
    errdefer data.deinit();
    const retained_owner = try std.testing.allocator.create(Owner);
    retained_owner.* = .{
        .engine = &detached_engine,
        .host = try host_mod.Host.init(std.testing.allocator, 0, 1),
        .data = data,
        .resolve = retained,
        .on_started = c.pi_js_undefined(),
        .on_call = c.pi_js_undefined(),
        .on_idle = c.pi_js_undefined(),
        .signal = c.pi_js_undefined(),
        .abort_listener = c.pi_js_undefined(),
        .async_scope = c.pi_js_undefined(),
        .on_finish = c.pi_js_undefined(),
    };
    _ = c.JS_SetOpaque(handle, retained_owner);
    c.JS_FreeContext(context);
    context_live = false;
    detached_engine.context = undefined;
    // The real registered finalizer runs when handle's deferred RT release
    // executes. It must free both the retained JS string and native owner.
}
