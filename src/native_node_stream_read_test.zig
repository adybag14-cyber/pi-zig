//! Actual selected StreamBase read and AsyncWrap callback composition controls.
//! The real Environment, wrapper, managed table, backing API and callback Scope
//! are used. The allocator fixture admits only a real FIRST successful native
//! allocation; unexpected failure fails this fixture and does not emulate the
//! missing original retry/GC policy. Native Trace callbacks observe delegation,
//! not category/controller/output qualification. The outer actual callback
//! scope skips task queues, whose real bootstrap remains a separate dependency.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const em = a.v.em;
const c = em.c;
const callbacks = @import("extensions/native_node_callback_scope.zig");
const providers = @import("extensions/native_node_async_providers.zig");
const wraps = @import("extensions/native_node_async_wrap_state.zig");
const base = @import("extensions/native_node_stream_base.zig");
const resources = @import("extensions/native_node_stream_resource.zig");
const managed = @import("extensions/native_node_managed_buffers.zig");
const callable = @import("extensions/native_node_module_callable.zig");
const uv = managed.uv;

fn unselected(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedStreamReadOperation;
}
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror {
    return error.UnselectedStreamReadCheck;
}
fn unselectedCorruption(_: *callbacks.Environment, _: f64) anyerror {
    return error.UnselectedStreamReadCorruption;
}
const environment_operations: callbacks.Operations = .{
    .on_hook_exception = unselected,
    .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption,
    .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected,
    .request_destroy_interrupt = unselected,
};

const Action = enum {
    normal, return_data, throw_reason, replace_callback,
    return_marker, delete_native,
};
const Probe = struct { fixture: *Fixture, index: usize };
const AllocationRecord = struct {
    length: usize,
    initialization: base.Initialization,
    pointer: usize,
};

fn markerFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe: *Probe = @ptrCast(@alignCast(
        c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    _ = c.JS_SetOpaque(value, null);
    probe.fixture.finalized[probe.index] += 1;
    probe.fixture.append(if (probe.index == 2) 'x' else 'm');
}

fn readCallback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int,
    argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const probe: *Probe = @ptrCast(@alignCast(
        c.JS_GetOpaque(data[0], c.JS_GetClassID(data[0])) orelse unreachable));
    const engine = em.Engine.fromContext(context.?);
    return a.expression(engine, readCallbackBody, .{ probe, receiver, argc, argv }) catch |err|
        callable.failure(engine, err, 0);
}
fn readCallbackBody(s: *a.Scope, probe: *Probe, receiver: c.JSValue,
    argc: c_int, argv: [*c]c.JSValue) !c.JSValue
{
    const f = probe.fixture;
    if (argc != 1) return error.ActualStreamReadArgumentCount;
    f.calls += 1;
    f.last_callback = probe.index;
    f.append('c');
    f.saw_receiver = c.JS_IsStrictEqual(s.engine.context, receiver, f.wrapper_value.?);
    f.observed_read = f.env().streamBaseField(.read_bytes_or_error).*;
    f.observed_offset = f.env().streamBaseField(.array_buffer_offset).*;
    f.observed_counter = if (f.node) |node| node.stream.resource.bytes_read else 0;
    f.observed_id = f.env().executionAsyncId();
    const frame = try s.own(try f.env().currentContextFrame());
    f.saw_captured_frame = c.JS_IsStrictEqual(s.engine.context, frame, f.child_frame.?);
    f.argument_undefined = c.JS_IsUndefined(argv[0]);
    if (!f.argument_undefined) {
        var length: usize = 0;
        const pointer = c.JS_GetArrayBuffer(s.engine.context, &length, argv[0]);
        try s.pending();
        if (pointer == null and length != 0) return error.ActualStreamArrayBufferRequired;
        if (length > f.bytes.len) return error.ActualStreamTestPayloadTooLarge;
        f.received_pointer = @intFromPtr(pointer);
        f.received_length = length;
        if (length != 0) @memcpy(f.bytes[0..length], pointer[0..length]);
        const next = a.duplicate(s.engine, argv[0]);
        if (f.received) |previous| s.engine.freeValue(previous);
        f.received = next;
    }
    switch (f.action) {
        .normal => return c.pi_js_undefined(),
        .return_data => return a.duplicate(s.engine, f.reason.?),
        .throw_reason => return a.raise(s, f.reason.?),
        .replace_callback => {
            try f.registry().setStreamOnRead(s, f.wrapper_value.?, f.replacement.?);
            return c.pi_js_undefined();
        },
        .return_marker => {
            const generation = try s.beforeAllocation();
            const result = try s.checkedAllocation(
                c.JS_NewObjectClass(s.engine.context, f.marker_class), generation);
            _ = c.JS_SetOpaque(result, &f.probes[2]);
            return a.duplicate(s.engine, result);
        },
        .delete_native => {
            try f.node.?.state.deleteMe();
            return c.pi_js_undefined();
        },
    }
}

fn traceBefore(raw: ?*anyopaque, state: *wraps.State) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    f.before_count += 1;
    f.before_id = state.async_id;
    f.before_provider = state.provider;
    f.append('b');
}
fn traceAfter(raw: ?*anyopaque, provider: u32, async_id: f64) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    f.after_count += 1;
    f.after_id = async_id;
    f.after_provider = provider;
    f.after_destroyed = f.destroyed;
    f.after_callback_finalized = f.finalized[0];
    f.after_result_finalized = f.finalized[2];
    f.append('a');
}
fn firstSuccessfulAllocation(raw: ?*anyopaque, environment: *callbacks.Environment,
    length: usize, initialization: base.Initialization) managed.Token
{
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    std.debug.assert(environment == f.env());
    // These positive controls admit the first actual native allocation only.
    // No retry count, GC, terminal policy, or fake backing is substituted.
    var token: managed.Token = std.mem.zeroes(managed.Token);
    const status = c.JS_PiTryNewArrayBufferBackingStore(f.engine.runtime, length,
        initialization == .zero_initialized, &token);
    if (status != 1) {
        c.JS_PiReleaseArrayBufferBackingStore(&token);
        @panic("unexpected allocation failure in first-success StreamBase fixture");
    }
    std.debug.assert(token.owner != null and f.allocation_count < f.allocations.len);
    f.allocations[f.allocation_count] = .{
        .length = length,
        .initialization = initialization,
        .pointer = @intFromPtr(c.JS_PiArrayBufferBackingStoreData(&token)),
    };
    f.allocation_count += 1;
    return token;
}

const Node = struct {
    state: wraps.State = undefined,
    stream: base.Base = undefined,
    fixture: *Fixture,

    fn getWrap(stream: *base.Base) ?*wraps.State {
        const self: *Node = @fieldParentPtr("stream", stream);
        self.fixture.virtual_calls += 1;
        return &self.state;
    }
    fn retire(state: *wraps.State, _: *a.Scope) !void {
        const self: *Node = @alignCast(@fieldParentPtr("state", state));
        self.stream.deinit();
        self.fixture.retired += 1;
        self.fixture.append('r');
    }
    fn destroy(state: *wraps.State) void {
        const self: *Node = @alignCast(@fieldParentPtr("state", state));
        const allocator = state.registry.environment.allocator();
        const f = self.fixture;
        f.node = null;
        f.destroyed += 1;
        f.append('d');
        allocator.destroy(self);
    }
    fn mark(_: ?*c.JSRuntime, _: *wraps.State, _: ?*const c.JS_MarkFunc) void {}
    const derived: wraps.Derived = .{ .mark = mark, .retire = retire, .destroy = destroy };
};

const Fixture = struct {
    native_environment: std.process.Environ.Map,
    native_environment_alive: bool = true,
    engine: *em.Engine = undefined,
    engine_alive: bool = false,
    environment: ?*callbacks.Environment = null,
    registry_owner: ?*wraps.Registry = null,
    prototype: ?c.JSValue = null,
    wrapper_value: ?c.JSValue = null,
    child_frame: ?c.JSValue = null,
    parent_frame: ?c.JSValue = null,
    reason: ?c.JSValue = null,
    replacement: ?c.JSValue = null,
    received: ?c.JSValue = null,
    node: ?*Node = null,
    outer: callbacks.Scope = undefined,
    outer_initialized: bool = false,
    marker_class: c.JSClassID = 0,
    probes: [3]Probe = undefined,
    finalized: [3]usize = .{ 0, 0, 0 },
    allocations: [8]AllocationRecord = undefined,
    allocation_count: usize = 0,
    trace: [128]u8 = undefined,
    trace_length: usize = 0,
    action: Action = .normal,
    calls: usize = 0,
    last_callback: usize = 0,
    virtual_calls: usize = 0,
    before_count: usize = 0,
    after_count: usize = 0,
    before_id: f64 = 0,
    after_id: f64 = 0,
    before_provider: u32 = 0,
    after_provider: u32 = 0,
    after_destroyed: usize = 0,
    after_callback_finalized: usize = 0,
    after_result_finalized: usize = 0,
    saw_receiver: bool = false,
    argument_undefined: bool = false,
    observed_read: i32 = 0,
    observed_offset: i32 = 0,
    observed_counter: u64 = 0,
    observed_id: f64 = 0,
    saw_captured_frame: bool = false,
    received_pointer: usize = 0,
    received_length: usize = 0,
    bytes: [64]u8 = undefined,
    retired: usize = 0,
    destroyed: usize = 0,
    direct_empty: bool = false,

    fn init(self: *Fixture) !void {
        self.* = .{ .native_environment = .init(std.testing.allocator) };
        for (&self.probes, 0..) |*probe, index| probe.* = .{ .fixture = self, .index = index };
        errdefer self.deinit();
        self.engine = try em.Engine.init(std.testing.allocator, .{});
        self.engine_alive = true;
        try @import("extensions/native_process.zig").install(
            self.engine, std.testing.io, &self.native_environment, &.{"native-stream-read"});
        const ignored = try a.expression(self.engine, bootstrap, .{self});
        self.engine.freeValue(ignored);
        self.outer.initialized = false;
        self.outer.init(self.env(), self.wrapper_value.?,
            .{ .async_id = 0, .trigger_async_id = 0 },
            .{ .skip_async_hooks = true, .skip_task_queues = true }, self.parent_frame.?) catch |err| {
            if (self.outer.initialized and !self.outer.deinitialized) {
                self.outer.markFailed();
                self.outer.deinit() catch {};
            }
            return err;
        };
        self.outer_initialized = true;
    }
    fn bootstrap(s: *a.Scope, self: *Fixture) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const process = try s.get(global, "process");
        const generation = try s.beforeAllocation();
        const symbol = try s.checkedAllocation(
            c.JS_NewSymbol(s.engine.context, "node:resource_symbol", false), generation);
        self.environment = try callbacks.Environment.create(s.engine, .{
            .provider_names = providers.names(false),
            .resource_symbol = symbol,
            .process_object = process,
            .async_context_frame = true,
            .operations = environment_operations,
        });
        self.env().markBootstrapComplete();
        self.registry_owner = try wraps.Registry.create(s.engine, self.env());
        const object = try s.get(global, "Object");
        self.prototype = a.duplicate(s.engine, try s.get(object, "prototype"));
        self.child_frame = a.duplicate(s.engine, try s.text("actual-stream-child-frame"));
        self.parent_frame = a.duplicate(s.engine, try s.text("actual-stream-parent-frame"));
        try self.env().setContextFrame(self.child_frame.?);
        const class_generation = try s.beforeAllocation();
        if (c.JS_NewClassID(s.engine.runtime, &self.marker_class) == 0) return error.OutOfMemory;
        const definition: c.JSClassDef = .{
            .class_name = "Actual StreamBase selected value marker",
            .finalizer = markerFinalizer,
        };
        const status = c.JS_NewClass(s.engine.runtime, self.marker_class, &definition);
        try s.boundary.checkPendingSince(class_generation);
        if (status < 0) return error.OutOfMemory;
        self.wrapper_value = a.duplicate(s.engine,
            try self.registry().newInstance(s, .filehandle, self.prototype.?));
        const node = try self.env().allocator().create(Node);
        node.* = .{ .fixture = self };
        node.stream.initialized = false;
        self.node = node;
        errdefer if (self.registry().unwrap(self.wrapper_value.?) != &node.state) {
            self.node = null;
            self.env().allocator().destroy(node);
        };
        try node.state.initialize(self.registry(), self.wrapper_value.?,
            Node.derived, wraps.Provider.filehandle, -1);
        try node.stream.init(self.env(), .{ .get_async_wrap = Node.getWrap }, .{
            .allocation = .{ .raw = self, .new_backing_store = firstSuccessfulAllocation },
            .trace = .{ .raw = self, .before = traceBefore, .after = traceAfter },
            .heap_diagnostics = null,
        });
        try node.stream.attachToObject(self.registry(), self.wrapper_value.?);
        const callback = try makeCallback(s, self, 0);
        try self.registry().setStreamOnRead(s, self.wrapper_value.?, callback);
        try self.env().setContextFrame(self.parent_frame.?);
        return c.pi_js_undefined();
    }
    fn makeCallback(s: *a.Scope, self: *Fixture, index: usize) !c.JSValue {
        const generation = try s.beforeAllocation();
        const marker = try s.checkedAllocation(
            c.JS_NewObjectClass(s.engine.context, self.marker_class), generation);
        _ = c.JS_SetOpaque(marker, &self.probes[index]);
        var roots = [_]c.JSValue{marker};
        const callable_generation = try s.beforeAllocation();
        return s.checkedAllocation(c.JS_NewCFunctionData2(s.engine.context,
            readCallback, "actualNativeStreamOnread", 1, 0, roots.len, &roots), callable_generation);
    }
    fn env(self: *Fixture) *callbacks.Environment { return self.environment.?; }
    fn registry(self: *Fixture) *wraps.Registry { return self.registry_owner.?; }
    fn append(self: *Fixture, byte: u8) void {
        std.debug.assert(self.trace_length < self.trace.len);
        self.trace[self.trace_length] = byte;
        self.trace_length += 1;
    }
    fn expectTrace(self: *Fixture, expected: []const u8) !void {
        try std.testing.expectEqualSlices(u8, expected, self.trace[0..self.trace_length]);
    }
    fn allocate(self: *Fixture, length: usize) !uv.uv_buf_t {
        return self.node.?.stream.resource.emitAlloc(length);
    }
    fn fill(buffer: uv.uv_buf_t, bytes: []const u8) void {
        std.debug.assert(bytes.len <= buffer.len);
        const pointer: [*]u8 = @ptrCast(buffer.base);
        @memcpy(pointer[0..bytes.len], bytes);
    }
    fn read(self: *Fixture, nread: isize, buffer: uv.uv_buf_t) !void {
        return self.node.?.stream.resource.emitRead(nread, buffer);
    }
    fn direct(self: *Fixture, nread: isize, array_buffer: ?c.JSValue,
        offset: usize, mode: base.ReadChecks) !c.JSValue
    {
        return a.expression(self.engine, directBody, .{ self, nread, array_buffer, offset, mode });
    }
    fn directBody(s: *a.Scope, self: *Fixture, nread: isize,
        array_buffer: ?c.JSValue, offset: usize, mode: base.ReadChecks) !c.JSValue
    {
        const result = try self.node.?.stream.callJSOnread(s, nread, array_buffer, offset, mode);
        self.direct_empty = result == null;
        return a.duplicate(s.engine, result orelse c.pi_js_undefined());
    }
    fn installReplacement(self: *Fixture) !void {
        self.replacement = try a.expression(self.engine, struct {
            fn body(s: *a.Scope, f: *Fixture) !c.JSValue {
                return a.duplicate(s.engine, try Fixture.makeCallback(s, f, 1));
            }
        }.body, .{self});
    }
    fn setReason(self: *Fixture, fatal: bool) !void {
        self.reason = try self.engine.checked(c.JS_NewError(self.engine.context));
        if (fatal) c.JS_SetUncatchableError(self.engine.context, self.reason.?);
    }
    fn takeCaught(self: *Fixture) !c.JSValue {
        const reason = self.engine.captured_exception orelse return error.ExpectedActualStreamReadReason;
        self.engine.captured_exception = null;
        return reason;
    }
    fn evaluate(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-stream-read-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
    }
    fn drop(self: *Fixture, value: *?c.JSValue) void {
        if (value.*) |owned| {
            value.* = null;
            self.engine.freeValue(owned);
        }
    }
    fn deinit(self: *Fixture) void {
        if (self.outer_initialized) {
            self.outer_initialized = false;
            self.outer.deinit() catch @panic("actual StreamBase outer scope teardown failed");
        }
        if (self.environment) |environment| {
            environment.can_call_into_js = false;
            environment.cleanupRealmAfterIoJoin() catch @panic("actual StreamBase realm cleanup failed");
            environment.disarm() catch @panic("actual StreamBase Environment disarm failed");
        }
        if (self.registry_owner) |owned_registry| {
            self.registry_owner = null;
            owned_registry.release();
        }
        if (self.engine_alive) {
            self.drop(&self.received);
            self.drop(&self.replacement);
            self.drop(&self.reason);
            self.drop(&self.wrapper_value);
            self.drop(&self.parent_frame);
            self.drop(&self.child_frame);
            self.drop(&self.prototype);
        }
        if (self.environment) |environment| {
            self.environment = null;
            environment.release();
        }
        if (self.engine_alive) {
            self.engine.deinit();
            self.engine_alive = false;
        }
        if (self.native_environment_alive) {
            self.native_environment_alive = false;
            self.native_environment.deinit();
        }
    }
};

fn expectThrown(f: *Fixture, outcome: anyerror!void) !void {
    if (outcome) |_| return error.ExpectedActualStreamReadFailure
    else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    const actual = try f.takeCaught();
    defer f.engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, actual, f.reason.?));
}

const Forwarder = struct {
    listener: resources.Listener = .{ .read_methods = &methods },
    allocations: usize = 0,
    reads: usize = 0,
    seen_counter: u64 = 0,
    fn allocate(listener: *resources.Listener, length: usize) !uv.uv_buf_t {
        const self: *Forwarder = @fieldParentPtr("listener", listener);
        self.allocations += 1;
        const previous = listener.previous_listener.?;
        return previous.read_methods.?.allocate(previous, length);
    }
    fn read(listener: *resources.Listener, nread: isize, buffer: uv.uv_buf_t) !void {
        const self: *Forwarder = @fieldParentPtr("listener", listener);
        self.reads += 1;
        self.seen_counter = listener.stream.?.bytes_read;
        const previous = listener.previous_listener.?;
        // Exercise the live actual list: this listener removes itself before
        // forwarding, and the selected downstream call can delete the stream.
        listener.deinit();
        return previous.read_methods.?.read(previous, nread, buffer);
    }
    const methods: resources.ReadMethods = .{ .allocate = allocate, .read = read };
};

test "Node StreamBase read initializes the real default listener and native wrapper pointer" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const node = f.node.?;
    try std.testing.expect(node.stream.resource.listener == &node.stream.default_listener);
    try std.testing.expect(node.stream.default_listener.stream == &node.stream.resource);
    try std.testing.expect(base.Base.fromObject(f.registry(), f.wrapper_value.?) == &node.stream);
    try std.testing.expectEqual(@as(u64, 0), node.stream.resource.bytes_read);
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
    try std.testing.expectEqual(@as(usize, 1), f.env().callback_depth);
}

test "Node StreamBase read selects internal onread beneath an ordinary own property and writes aliases first" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const ignored = try a.expression(f.engine, struct {
        fn body(s: *a.Scope, object: c.JSValue) !c.JSValue {
            try s.define(object, "onread", c.JS_NewInt32(s.engine.context, 99), c.JS_PROP_C_W_E);
            return c.pi_js_undefined();
        }
    }.body, .{f.wrapper_value.?});
    f.engine.freeValue(ignored);
    const result = try f.direct(7, null, 9, .skip_nread_checks);
    defer f.engine.freeValue(result);
    try std.testing.expectEqual(@as(i32, 7), f.observed_read);
    try std.testing.expectEqual(@as(i32, 9), f.observed_offset);
    try std.testing.expect(f.argument_undefined and f.saw_receiver and !f.direct_empty);
    try std.testing.expectEqual(@as(usize, 1), f.virtual_calls);
    try f.expectTrace("bca");
}

test "Node StreamBase read allocates actual native backing without a JS wrapper under an exhausted JS heap" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.engine.runtime);
    c.JS_SetMemoryLimit(f.engine.runtime, 1);
    const outcome = f.allocate(16);
    c.JS_SetMemoryLimit(f.engine.runtime, f.engine.options.memory_limit);
    const buffer = try outcome;
    try std.testing.expect(buffer.base != null);
    try std.testing.expectEqual(@as(usize, 16), @as(usize, buffer.len));
    try std.testing.expectEqual(@as(usize, 1), f.env().managed_buffers.count());
    try std.testing.expectEqual(@as(usize, 1), f.allocation_count);
    try std.testing.expectEqual(base.Initialization.uninitialized, f.allocations[0].initialization);
    try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.engine.runtime));
    try std.testing.expect(!c.JS_HasException(f.engine.context));
    try std.testing.expectEqual(@as(usize, 0), f.calls);
    try f.read(0, buffer);
}

test "Node StreamBase read zero bytes consumes the managed token without a callback or trace" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const buffer = try f.allocate(16);
    try f.read(0, buffer);
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
    try std.testing.expectEqual(@as(usize, 1), f.allocation_count);
    try std.testing.expectEqual(@as(usize, 0), f.calls);
    try std.testing.expectEqual(@as(u64, 0), f.node.?.stream.resource.bytes_read);
    try std.testing.expectEqual(@as(usize, 0), f.virtual_calls);
    try f.expectTrace("");
}

test "Node StreamBase read negative status publishes undefined and leaves the positive byte counter unchanged" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const buffer = try f.allocate(16);
    try f.read(-7, buffer);
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
    try std.testing.expectEqual(@as(i32, -7), f.observed_read);
    try std.testing.expectEqual(@as(i32, 0), f.observed_offset);
    try std.testing.expectEqual(@as(u64, 0), f.observed_counter);
    try std.testing.expect(f.argument_undefined and f.saw_receiver);
    try std.testing.expectEqual(@as(usize, 1), f.allocation_count);
    try f.expectTrace("bca");
}

test "Node StreamBase read full extent adopts the same native bytes and advances the counter before callback" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const payload = "native-map-bytes!";
    const buffer = try f.allocate(payload.len);
    Fixture.fill(buffer, payload);
    try f.read(@intCast(payload.len), buffer);
    try std.testing.expectEqual(@intFromPtr(buffer.base), f.received_pointer);
    try std.testing.expectEqual(@as(usize, payload.len), f.received_length);
    try std.testing.expectEqualSlices(u8, payload, f.bytes[0..f.received_length]);
    try std.testing.expectEqual(@as(u64, payload.len), f.observed_counter);
    try std.testing.expectEqual(@as(i32, @intCast(payload.len)), f.observed_read);
    try std.testing.expectEqual(@as(usize, 1), f.allocation_count);
    try std.testing.expectEqual(@as(usize, payload.len), f.allocations[0].length);
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
    try f.expectTrace("bca");
}

test "Node StreamBase read short extent performs the real exact native reallocation and copies before adoption" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const buffer = try f.allocate(32);
    Fixture.fill(buffer, "short-read");
    try f.read(10, buffer);
    try std.testing.expectEqual(@as(usize, 2), f.allocation_count);
    try std.testing.expectEqual(@as(usize, 32), f.allocations[0].length);
    try std.testing.expectEqual(@as(usize, 10), f.allocations[1].length);
    try std.testing.expectEqual(base.Initialization.uninitialized, f.allocations[1].initialization);
    try std.testing.expect(f.allocations[0].pointer != f.allocations[1].pointer);
    try std.testing.expectEqual(f.allocations[1].pointer, f.received_pointer);
    try std.testing.expectEqualSlices(u8, "short-read", f.bytes[0..f.received_length]);
    try std.testing.expectEqual(@as(u64, 10), f.observed_counter);
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
}

test "Node StreamBase read later ArrayBuffer adoption bypasses the live global constructor" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\globalThis.ArrayBuffer = function() { throw new Error("poisoned public ArrayBuffer"); };
    );
    const buffer = try f.allocate(4);
    Fixture.fill(buffer, "live");
    try f.read(4, buffer);
    try std.testing.expectEqualSlices(u8, "live", f.bytes[0..f.received_length]);
    try std.testing.expectEqual(@as(usize, 1), f.calls);
    try std.testing.expect(f.engine.captured_exception == null);
}

test "Node StreamBase read a returned flagged Error stays successful DATA" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.setReason(true);
    f.action = .return_data;
    const result = try f.direct(-2, null, 0, .check_nread);
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, result, f.reason.?));
    try std.testing.expect(c.JS_IsUncatchableError(result));
    try std.testing.expect(f.engine.captured_exception == null and !c.JS_HasException(f.engine.context));
    try f.expectTrace("bca");
}

test "Node StreamBase read actual ordinary callback failure retains its exact reason through native cleanup" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.setReason(false);
    f.action = .throw_reason;
    const buffer = try f.allocate(4);
    Fixture.fill(buffer, "fail");
    try expectThrown(&f, f.read(4, buffer));
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
    try std.testing.expectEqual(@as(usize, 1), f.after_count);
    try std.testing.expectEqual(@as(usize, 1), f.env().callback_depth);
    try std.testing.expectEqual(@as(f64, 0), f.env().executionAsyncId());
    try f.expectTrace("bca");
}

test "Node StreamBase read actual fatal callback reason remains owned while static after trace still runs" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.setReason(true);
    f.action = .throw_reason;
    const buffer = try f.allocate(4);
    Fixture.fill(buffer, "stop");
    try expectThrown(&f, f.read(4, buffer));
    try std.testing.expect(c.JS_IsUncatchableError(f.reason.?));
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
    try std.testing.expectEqual(@as(usize, 1), f.after_count);
    try f.expectTrace("bca");
}

test "Node StreamBase read retains the selected callback across live replacement until caller scope retirement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.installReplacement();
    f.action = .replace_callback;
    const first = try f.direct(-1, null, 0, .check_nread);
    f.engine.freeValue(first);
    try std.testing.expectEqual(@as(usize, 0), f.after_callback_finalized);
    try std.testing.expectEqual(@as(usize, 1), f.finalized[0]);
    try f.expectTrace("bcam");
    f.action = .normal;
    const second = try f.direct(-1, null, 0, .check_nread);
    f.engine.freeValue(second);
    try std.testing.expectEqual(@as(usize, 1), f.last_callback);
    try std.testing.expectEqual(@as(usize, 2), f.calls);
}

test "Node StreamBase read ignored callback return retires only after the static after operation" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.action = .return_marker;
    const buffer = try f.allocate(4);
    Fixture.fill(buffer, "done");
    try f.read(4, buffer);
    try std.testing.expectEqual(@as(usize, 0), f.after_result_finalized);
    try std.testing.expectEqual(@as(usize, 1), f.finalized[2]);
    try f.expectTrace("bcax");
}

test "Node StreamBase read can delete its actual native State before static after uses cached identifiers" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const async_id = f.node.?.state.async_id;
    const provider = f.node.?.state.provider;
    f.action = .delete_native;
    const buffer = try f.allocate(4);
    Fixture.fill(buffer, "last");
    try f.read(4, buffer);
    try std.testing.expect(f.node == null and f.registry().unwrap(f.wrapper_value.?) == null);
    try std.testing.expect(base.Base.fromObject(f.registry(), f.wrapper_value.?) == null);
    try std.testing.expectEqual(@as(usize, 1), f.retired);
    try std.testing.expectEqual(@as(usize, 1), f.destroyed);
    try std.testing.expectEqual(@as(usize, 1), f.after_destroyed);
    try std.testing.expectEqual(async_id, f.before_id);
    try std.testing.expectEqual(async_id, f.after_id);
    try std.testing.expectEqual(provider, f.before_provider);
    try std.testing.expectEqual(provider, f.after_provider);
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
    try f.expectTrace("bcrda");
}

test "Node StreamBase read enters the real captured frame and restores the enclosing native callback scope" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const async_id = f.node.?.state.async_id;
    const result = try f.direct(-1, null, 0, .check_nread);
    defer f.engine.freeValue(result);
    try std.testing.expect(f.saw_captured_frame and f.saw_receiver);
    try std.testing.expectEqual(async_id, f.observed_id);
    try std.testing.expectEqual(@as(f64, 0), f.env().executionAsyncId());
    try std.testing.expectEqual(@as(usize, 1), f.env().callback_depth);
    const restored = try f.env().currentContextFrame();
    defer f.engine.freeValue(restored);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, restored, f.parent_frame.?));
}

test "Node StreamBase read disabled JS returns the actual empty callback while native buffer cleanup completes" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const buffer = try f.allocate(4);
    Fixture.fill(buffer, "skip");
    f.env().can_call_into_js = false;
    try f.read(4, buffer);
    try std.testing.expectEqual(@as(usize, 0), f.calls);
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
    try std.testing.expectEqual(@as(i32, 4), f.env().streamBaseField(.read_bytes_or_error).*);
    try std.testing.expectEqual(@as(usize, 1), f.env().callback_depth);
    try std.testing.expect(f.engine.captured_exception == null and !c.JS_HasException(f.engine.context));
    try f.expectTrace("ba");
}

test "Node StreamBase read uses the live listener head and advances bytes before a real forwarding method" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var forwarder: Forwarder = .{};
    f.node.?.stream.resource.push(&forwarder.listener);
    defer forwarder.listener.deinit();
    const buffer = try f.allocate(4);
    Fixture.fill(buffer, "head");
    try f.read(4, buffer);
    try std.testing.expectEqual(@as(usize, 1), forwarder.allocations);
    try std.testing.expectEqual(@as(usize, 1), forwarder.reads);
    try std.testing.expectEqual(@as(u64, 4), forwarder.seen_counter);
    try std.testing.expect(forwarder.listener.stream == null and forwarder.listener.previous_listener == null);
    try std.testing.expect(f.node.?.stream.resource.listener == &f.node.?.stream.default_listener);
    try std.testing.expectEqualSlices(u8, "head", f.bytes[0..f.received_length]);
}

test "Node StreamBase read null buffer negative status bypasses the managed map without an allocation" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const buffer: uv.uv_buf_t = std.mem.zeroes(uv.uv_buf_t);
    try f.read(-1, buffer);
    try std.testing.expectEqual(@as(usize, 0), f.allocation_count);
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
    try std.testing.expectEqual(@as(i32, -1), f.observed_read);
    try std.testing.expect(f.argument_undefined);
    try f.expectTrace("bca");
}
