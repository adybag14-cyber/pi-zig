//! Real ReqWrap original-callback routing on the single shared UV service.
//! The fixture supplies a compiled native derived ReqWrap with a real State,
//! intrusive Entry, physical request and borrowed raw span. It does not install
//! a FileHandle constructor, freelist, Promise substitute or checkpoint hook.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const em = a.v.em;
const c = em.c;
const callbacks = @import("extensions/native_node_callback_scope.zig");
const providers = @import("extensions/native_node_async_providers.zig");
const native = @import("extensions/native_node_async_wrap_state.zig");
const request_state = @import("extensions/native_node_request_state.zig");
const fs_io = @import("extensions/native_node_fs_request_io.zig");
const uv = fs_io.uv;
const physical = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("uv.h");
    @cInclude("fcntl.h");
});

fn unselected(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedReqWrapRoutingOperation;
}
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror {
    return error.UnselectedReqWrapRoutingNativeCheck;
}
fn unselectedCorruption(_: *callbacks.Environment, _: f64) anyerror {
    return error.UnselectedReqWrapRoutingCorruption;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = unselected,
    .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption,
    .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected,
    .request_destroy_interrupt = unselected,
};
const Failure = enum { none, host, ordinary, fatal };
const Observation = struct {
    node_index: usize,
    callback_id: u8,
    result: i64,
    byte: u8,
    waiting: c_int,
    counted: bool,
    dispatched: bool,
    detached: bool,
    references: usize,
    strong: bool,
    selected: bool,
    cleaned: bool,
    js_disabled: bool,
};
const Node = struct {
    state: native.State = undefined,
    entry: request_state.Entry = undefined,
    fixture: *Fixture,
    index: usize,
    attached: bool = false,
    entry_initialized: bool = false,
    actual: ?*uv.PiUvFsRequest = null,
    held_native_pointer: bool = false,
    buffer: [8]u8 = @splat(0xa5),
    descriptor: c_int = -1,
    position: i64 = 0,
    redispatch: bool = false,
    fail_first: bool = false,
    release_in_callback: bool = false,
    failure: Failure = .none,

    fn cancel(entry: *request_state.Entry) void {
        const self: *Node = @alignCast(@fieldParentPtr("entry", entry));
        self.fixture.cancellations += 1;
        if (self.actual) |actual| _ = uv.pi_uv_fs_cancel(actual);
    }
    fn mark(_: ?*c.JSRuntime, _: *native.State, _: ?*const c.JS_MarkFunc) void {}
    fn retire(state: *native.State, _: *a.Scope) !void {
        const self: *Node = @alignCast(@fieldParentPtr("state", state));
        self.fixture.retired += 1;
        self.fixture.append('r');
        if (self.actual) |actual| uv.pi_uv_fs_request_cleanup(actual);
        if (self.entry_initialized) {
            self.entry_initialized = false;
            self.entry.deinit();
        }
    }
    fn destroy(state: *native.State) void {
        const self: *Node = @alignCast(@fieldParentPtr("state", state));
        const allocator = state.registry.environment.allocator();
        std.debug.assert(!self.held_native_pointer);
        self.fixture.nodes[self.index] = null;
        self.fixture.destroyed += 1;
        self.fixture.append('d');
        if (self.actual) |actual| {
            self.actual = null;
            uv.pi_uv_fs_request_release(actual);
        }
        allocator.destroy(self);
    }
    const derived: native.Derived = .{ .mark = mark, .retire = retire, .destroy = destroy };
};

fn firstCallback(entry: *request_state.Entry, raw: *anyopaque) !void {
    return completed(entry, raw, 1);
}
fn secondCallback(entry: *request_state.Entry, raw: *anyopaque) !void {
    return completed(entry, raw, 2);
}
fn completed(entry: *request_state.Entry, raw: *anyopaque, callback_id: u8) !void {
    const self: *Node = @alignCast(@fieldParentPtr("entry", entry));
    const f = self.fixture;
    const actual: *uv.PiUvFsRequest = @ptrCast(@alignCast(raw));
    if (self.actual != actual) return error.ActualReqWrapCallbackAddressMismatch;
    const info = uv.pi_uv_fs_request_info(actual);
    // Complete physical cleanup before any fallible observer. Reset below may
    // immediately reuse this request, so there is no deferred old cleanup.
    uv.pi_uv_fs_request_cleanup(actual);
    if (f.observation_count == f.observations.len)
        return error.ActualReqWrapObservationCapacity;
    const expected_callback: *const fn (*request_state.Entry, *anyopaque) anyerror!void =
        if (callback_id == 1) firstCallback else secondCallback;
    const selected = if (entry.original_callback) |original|
        original.request == raw and original.call == expected_callback else false;
    f.observations[f.observation_count] = .{
        .node_index = self.index, .callback_id = callback_id,
        .result = info.result, .byte = self.buffer[0],
        .waiting = f.env().requests.waiting, .counted = entry.counted,
        .dispatched = entry.dispatched, .detached = self.state.detached,
        .references = self.state.native_references,
        .strong = self.state.strong_wrapper != null, .selected = selected,
        .cleaned = uv.pi_uv_fs_request_info(actual).cleaned != 0,
        .js_disabled = !f.env().canCallIntoJs(),
    };
    f.observation_count += 1;
    f.append(if (callback_id == 1) 'a' else 'b');

    if (self.redispatch and callback_id == 1) {
        if (!self.held_native_pointer) return error.ActualReqWrapReusePointerRequired;
        entry.reset();
        f.reset_cleared = entry.original_callback == null and !entry.dispatched and !entry.counted;
        const reset_status = uv.pi_uv_fs_request_reset(actual);
        if (reset_status != 0) return error.ActualReqWrapPhysicalResetFailed;
        const status = try f.dispatch(self, self.descriptor, &self.buffer, 1,
            self.position + 1, secondCallback);
        if (status < 0) return error.ActualReqWrapRedispatchFailed;
        f.redispatch_counted = entry.counted and f.env().requests.waiting == 1 and
            self.state.native_references == 2;
        // The next actual completion is queued while the old delivery still
        // owns its event ticket and Wrapper pointer.
        try f.waitQueued(1);
        f.queued_inside_callback = true;
        if (self.fail_first) {
            _ = c.JS_Throw(f.engine.context, a.duplicate(f.engine, f.reason.?));
            return error.JavaScriptException;
        }
        return;
    }
    if (self.release_in_callback and self.held_native_pointer) {
        self.held_native_pointer = false;
        try self.state.releaseNative();
        // The outer Wrapper remains the one live native pointer until return.
        f.last_pointer_in_callback = self.state.native_references == 1;
    }
    switch (self.failure) {
        .none => {},
        .host => return error.ActualReqWrapSelectedCallbackFailure,
        .ordinary => {
            _ = c.JS_Throw(f.engine.context, a.duplicate(f.engine, f.reason.?));
            return error.JavaScriptException;
        },
        .fatal => {
            _ = f.engine.throwNativeOutOfMemoryFatal();
            return error.JavaScriptException;
        },
    }
}

const Fixture = struct {
    native_environment: std.process.Environ.Map,
    native_environment_alive: bool = true,
    engine: *em.Engine = undefined,
    engine_alive: bool = false,
    environment: ?*callbacks.Environment = null,
    registry_owner: ?*native.Registry = null,
    prototype: ?c.JSValue = null,
    reason: ?c.JSValue = null,
    controller: ?*fs_io.Controller = null,
    nodes: [8]?*Node = @splat(null),
    wrappers: [8]?c.JSValue = @splat(null),
    observations: [16]Observation = undefined,
    observation_count: usize = 0,
    retired: usize = 0,
    destroyed: usize = 0,
    cancellations: usize = 0,
    reset_cleared: bool = false,
    redispatch_counted: bool = false,
    queued_inside_callback: bool = false,
    last_pointer_in_callback: bool = false,
    trace: [64]u8 = undefined,
    trace_length: usize = 0,

    fn init(self: *Fixture) !void {
        self.* = .{ .native_environment = .init(std.testing.allocator) };
        errdefer self.deinit();
        self.engine = try em.Engine.init(std.testing.allocator, .{});
        self.engine_alive = true;
        try @import("extensions/native_process.zig").install(
            self.engine, std.testing.io, &self.native_environment, &.{"native-reqwrap-routing"});
        const ignored = try a.expression(self.engine, bootstrap, .{self});
        self.engine.freeValue(ignored);
        self.controller = switch (try fs_io.acquire(self.engine, self.env())) {
            .ready => |actual| actual,
            .failed => return error.ActualReqWrapServiceAdmissionFailed,
        };
    }
    fn bootstrap(s: *a.Scope, self: *Fixture) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const process = try s.get(global, "process");
        const generation = try s.beforeAllocation();
        const symbol = try s.checkedAllocation(
            c.JS_NewSymbol(s.engine.context, "node:resource_symbol", false), generation);
        const environment = try callbacks.Environment.create(s.engine, .{
            .provider_names = providers.names(false), .resource_symbol = symbol,
            .process_object = process, .async_context_frame = true, .operations = operations,
        });
        self.environment = environment;
        environment.markBootstrapComplete();
        self.registry_owner = try native.Registry.create(s.engine, environment);
        const object = try s.get(global, "Object");
        self.prototype = a.duplicate(s.engine, try s.get(object, "prototype"));
        self.reason = a.duplicate(s.engine, try s.object());
        return c.pi_js_undefined();
    }
    fn env(self: *Fixture) *callbacks.Environment { return self.environment.?; }
    fn registry(self: *Fixture) *native.Registry { return self.registry_owner.?; }
    fn append(self: *Fixture, byte: u8) void {
        std.debug.assert(self.trace_length < self.trace.len);
        self.trace[self.trace_length] = byte;
        self.trace_length += 1;
    }
    fn request(self: *Fixture, hold_pointer: bool) !*Node {
        var output: ?*Node = null;
        const ignored = try a.expression(self.engine, createBody, .{ self, hold_pointer, &output });
        self.engine.freeValue(ignored);
        return output orelse error.ActualReqWrapControlRequestRequired;
    }
    fn createBody(s: *a.Scope, self: *Fixture, hold_pointer: bool, output: *?*Node) !c.JSValue {
        var index: usize = 0;
        while (index < self.nodes.len and
            (self.nodes[index] != null or self.wrappers[index] != null)) : (index += 1) {}
        if (index == self.nodes.len) return error.ActualReqWrapControlCapacity;
        const node = try self.env().allocator().create(Node);
        node.* = .{ .fixture = self, .index = index };
        self.nodes[index] = node;
        errdefer if (!node.attached) {
            self.nodes[index] = null;
            if (node.actual) |actual| uv.pi_uv_fs_request_release(actual);
            self.env().allocator().destroy(node);
        };
        const allocated = uv.pi_uv_fs_request_create(self.controller.?.service,
            uv.PI_UV_FS_READ, @intCast(index + 1), &node.actual);
        if (allocated.allocation_failed != 0) return error.OutOfMemory;
        if (allocated.status < 0) return error.ActualReqWrapControlAllocationStatus;
        if (node.actual == null) return error.ActualReqWrapControlNativeRequestRequired;
        const wrapper_value = try self.registry().newInstance(s, .async_wrap, self.prototype.?);
        // Generic ReqWrap<T> accepts its actual object and provider. This
        // compiled test derivative is not a substitute FileHandle template.
        node.state.initialize(self.registry(), wrapper_value, Node.derived, 8, -1) catch |err| {
            node.attached = self.registry().unwrap(wrapper_value) == &node.state;
            return err;
        };
        node.attached = true;
        try node.entry.initialize(&node.state, Node.cancel);
        node.entry_initialized = true;
        try node.state.makeWeak();
        node.entry.reset();
        if (uv.pi_uv_fs_request_reset(node.actual.?) != 0)
            return error.ActualReqWrapInitialResetFailed;
        if (hold_pointer) {
            try node.state.retainNative();
            node.held_native_pointer = true;
        }
        self.wrappers[index] = a.duplicate(s.engine, wrapper_value);
        output.* = node;
        return c.pi_js_undefined();
    }
    fn dispatch(self: *Fixture, node: *Node, descriptor: c_int, base: ?[*]u8,
        length: usize, position: i64,
        selected_callback: *const fn (*request_state.Entry, *anyopaque) anyerror!void) !c_int
    {
        var status: c_int = undefined;
        const ignored = try a.expression(self.engine, dispatchBody,
            .{ self, node, descriptor, base, length, position, selected_callback, &status });
        self.engine.freeValue(ignored);
        return status;
    }
    fn dispatchBody(s: *a.Scope, self: *Fixture, node: *Node, descriptor: c_int,
        base: ?[*]u8, length: usize, position: i64,
        selected_callback: *const fn (*request_state.Entry, *anyopaque) anyerror!void,
        status: *c_int) !c.JSValue
    {
        node.descriptor = descriptor;
        node.position = position;
        status.* = try self.controller.?.dispatchRawRead(s, &node.entry, node.actual.?,
            descriptor, base, length, position, selected_callback);
        return c.pi_js_undefined();
    }
    fn waitQueued(self: *Fixture, count: usize) !void {
        const until = physical.uv_hrtime() + 10 * std.time.ns_per_s;
        while (uv.pi_uv_service_snapshot(self.controller.?.service).queued_events < count) {
            if (physical.uv_hrtime() >= until) return error.ActualReqWrapCompletionTimeout;
            physical.uv_sleep(1);
        }
    }
    fn pump(self: *Fixture) !void {
        const until = physical.uv_hrtime() + 10 * std.time.ns_per_s;
        while (self.env().requests.waiting != 0) {
            if (c.JS_IsJobPending(self.engine.runtime)) return error.UnselectedReqWrapTaskQueue;
            const pump_native = self.engine.native_env_pump orelse return error.ActualReqWrapHubRequired;
            _ = try pump_native(self.engine);
            if (self.env().requests.waiting == 0) break;
            if (physical.uv_hrtime() >= until) return error.ActualReqWrapCompletionTimeout;
            physical.uv_sleep(1);
        }
    }
    fn takeCaught(self: *Fixture) !c.JSValue {
        const actual = self.engine.captured_exception orelse return error.ActualReqWrapReasonRequired;
        self.engine.captured_exception = null;
        return actual;
    }
    fn stopIo(self: *Fixture) void {
        if (self.environment) |environment| environment.can_call_into_js = false;
        if (self.engine_alive) if (self.engine.native_env_deinit) |stop| stop(self.engine);
        self.controller = null;
    }
    fn deinit(self: *Fixture) void {
        self.stopIo();
        // Any test-owned BaseObjectPtr outlives physical join and delivery.
        for (&self.nodes) |*slot| if (slot.*) |node| if (node.held_native_pointer) {
            node.held_native_pointer = false;
            node.state.releaseNative() catch @panic("ReqWrap native pointer retirement failed");
        };
        if (self.environment) |environment| {
            environment.cleanupRealmAfterIoJoin() catch @panic("ReqWrap realm cleanup failed");
            environment.disarm() catch @panic("ReqWrap environment disarm failed");
        }
        if (self.registry_owner) |registry_value| {
            self.registry_owner = null;
            registry_value.release();
        }
        for (&self.wrappers) |*slot| if (slot.*) |wrapper_value| {
            slot.* = null;
            self.engine.freeValue(wrapper_value);
        };
        if (self.reason) |actual| { self.reason = null; self.engine.freeValue(actual); }
        if (self.prototype) |actual| { self.prototype = null; self.engine.freeValue(actual); }
        if (self.environment) |environment| { self.environment = null; environment.release(); }
        if (self.engine_alive) { self.engine_alive = false; self.engine.deinit(); }
        if (self.native_environment_alive) {
            self.native_environment_alive = false;
            self.native_environment.deinit();
        }
    }
};
const File = struct {
    fixture: *Fixture,
    temporary: std.testing.TmpDir = undefined,
    temporary_ready: bool = false,
    path: ?[:0]u8 = null,
    descriptor: c_int = -1,
    fn init(self: *File, fixture: *Fixture) !void {
        self.* = .{ .fixture = fixture };
        errdefer self.deinit();
        self.temporary = std.testing.tmpDir(.{});
        self.temporary_ready = true;
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "routing.bin", .data = "ABCDEFGH" });
        const directory = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
        defer std.testing.allocator.free(directory);
        const joined = try std.fs.path.join(std.testing.allocator, &.{directory, "routing.bin"});
        defer std.testing.allocator.free(joined);
        self.path = try std.testing.allocator.dupeZ(u8, joined);
        var actual: physical.uv_fs_t = undefined;
        const status = physical.uv_fs_open(null, &actual, self.path.?.ptr, physical.O_RDONLY, 0, null);
        physical.uv_fs_req_cleanup(&actual);
        if (status >= 0) self.descriptor = status;
        if (status < 0) return error.ActualReqWrapFileOpenFailed;
    }
    fn deinit(self: *File) void {
        self.fixture.stopIo();
        if (self.descriptor >= 0) {
            var actual: physical.uv_fs_t = undefined;
            const status = physical.uv_fs_close(null, &actual, self.descriptor, null);
            physical.uv_fs_req_cleanup(&actual);
            if (status != 0) @panic("ReqWrap descriptor close failed");
            self.descriptor = -1;
        }
        if (self.path) |path| { self.path = null; std.testing.allocator.free(path); }
        if (self.temporary_ready) { self.temporary_ready = false; self.temporary.cleanup(); }
    }
};
fn expectRetired(f: *Fixture, count: usize) !void {
    try std.testing.expectEqual(count, f.retired);
    try std.testing.expectEqual(count, f.destroyed);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expect(f.env().requests.head == null and f.env().requests.tail == null);
}
fn expectWrapper(observed: Observation, references: usize) !void {
    try std.testing.expect(observed.dispatched and !observed.counted and observed.detached);
    try std.testing.expect(observed.strong and observed.selected and observed.cleaned);
    try std.testing.expectEqual(references, observed.references);
}

test "native ReqWrap routing Reset clears the actual callback before reuse without counting admission" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const node = try f.request(false);
    try std.testing.expect(node.entry.original_callback == null and !node.entry.dispatched);
    try std.testing.expect(node.state.wants_weak and node.state.strong_wrapper == null);
    node.entry.dispatchStarted();
    try node.entry.setCallback(.{ .request = node.actual.?, .call = firstCallback });
    try std.testing.expect(node.entry.original_callback.?.request == @as(*anyopaque, @ptrCast(node.actual.?)));
    try std.testing.expect(node.entry.original_callback.?.call == firstCallback);
    try std.testing.expect(node.entry.dispatched and !node.entry.counted);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    node.entry.reset();
    try std.testing.expect(node.entry.original_callback == null and !node.entry.dispatched);
    try std.testing.expectEqual(@as(c_int, 0), uv.pi_uv_fs_request_reset(node.actual.?));
    try std.testing.expectEqual(@as(usize, 0), f.observation_count);
}

test "native ReqWrap routing selects the real callback after retain Detach and waiting decrement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    const node = try f.request(false);
    const index = node.index;
    try std.testing.expectEqual(@as(c_int, 0),
        try f.dispatch(node, file.descriptor, &node.buffer, 1, 1, firstCallback));
    try std.testing.expect(node.entry.counted and node.state.strong_wrapper != null);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try f.pump();
    try std.testing.expectEqual(@as(usize, 1), f.observation_count);
    try expectWrapper(f.observations[0], 1);
    try std.testing.expectEqual(@as(c_int, 0), f.observations[0].waiting);
    try std.testing.expectEqual(@as(i64, 1), f.observations[0].result);
    try std.testing.expectEqual(@as(u8, 'B'), f.observations[0].byte);
    try std.testing.expect(f.nodes[index] == null);
    try std.testing.expect(f.registry().unwrap(f.wrappers[index].?) == null);
    try expectRetired(&f, 1);
    try std.testing.expectEqualStrings("ard", f.trace[0..f.trace_length]);
}

test "native ReqWrap routing negative raw admission keeps callback but does not strengthen count or synthesize completion" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    const node = try f.request(false);
    try std.testing.expectEqual(@as(c_int, physical.UV_EINVAL),
        try f.dispatch(node, file.descriptor, null, 1, 0, firstCallback));
    try std.testing.expect(node.entry.dispatched and node.entry.original_callback != null);
    try std.testing.expect(!node.entry.counted and node.state.strong_wrapper == null);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expectEqual(@as(usize, 0), f.observation_count);
    try std.testing.expectEqual(@as(usize, 0),
        uv.pi_uv_service_snapshot(f.controller.?.service).queued_events);
    node.entry.reset();
    try std.testing.expectEqual(@as(c_int, 0), uv.pi_uv_fs_request_reset(node.actual.?));
    try std.testing.expectEqual(@as(c_int, 0),
        try f.dispatch(node, file.descriptor, &node.buffer, 1, 2, secondCallback));
    try f.pump();
    try std.testing.expectEqual(@as(usize, 1), f.observation_count);
    try std.testing.expectEqual(@as(u8, 2), f.observations[0].callback_id);
    try std.testing.expectEqual(@as(u8, 'C'), f.observations[0].byte);
    try expectRetired(&f, 1);
}

test "native ReqWrap routing accepted bad descriptor preserves the real callback negative result" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const node = try f.request(false);
    try std.testing.expectEqual(@as(c_int, 0),
        try f.dispatch(node, -1, &node.buffer, 1, 0, secondCallback));
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try f.pump();
    try std.testing.expectEqual(@as(usize, 1), f.observation_count);
    try std.testing.expectEqual(@as(u8, 2), f.observations[0].callback_id);
    try std.testing.expectEqual(@as(i64, physical.UV_EBADF), f.observations[0].result);
    try expectWrapper(f.observations[0], 1);
    try expectRetired(&f, 1);
}

test "native ReqWrap routing reset and redispatch precede old Wrapper and event retirement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    const node = try f.request(true);
    node.redispatch = true;
    node.release_in_callback = true;
    try std.testing.expectEqual(@as(c_int, 0),
        try f.dispatch(node, file.descriptor, &node.buffer, 1, 0, firstCallback));
    try f.pump();
    try std.testing.expectEqual(@as(usize, 2), f.observation_count);
    try expectWrapper(f.observations[0], 2);
    try expectWrapper(f.observations[1], 2);
    try std.testing.expectEqual(@as(u8, 1), f.observations[0].callback_id);
    try std.testing.expectEqual(@as(u8, 2), f.observations[1].callback_id);
    try std.testing.expectEqual(@as(u8, 'A'), f.observations[0].byte);
    try std.testing.expectEqual(@as(u8, 'B'), f.observations[1].byte);
    try std.testing.expect(f.reset_cleared and f.redispatch_counted and
        f.queued_inside_callback and f.last_pointer_in_callback);
    try expectRetired(&f, 1);
    try std.testing.expectEqualStrings("abrd", f.trace[0..f.trace_length]);
}

test "native ReqWrap routing callback error after redispatch preserves the new request pointer and event" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    const node = try f.request(true);
    node.redispatch = true;
    node.release_in_callback = true;
    node.fail_first = true;
    try std.testing.expectEqual(@as(c_int, 0),
        try f.dispatch(node, file.descriptor, &node.buffer, 1, 2, firstCallback));
    try std.testing.expectError(error.JavaScriptException, f.pump());
    const reason = try f.takeCaught(); defer f.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, f.reason.?));
    try std.testing.expectEqual(@as(usize, 1), f.observation_count);
    try std.testing.expectEqual(@as(usize, 0), f.destroyed);
    try std.testing.expectEqual(@as(usize, 1), node.state.native_references);
    try std.testing.expect(node.entry.counted and node.entry.original_callback.?.call == secondCallback);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try f.pump();
    try std.testing.expectEqual(@as(usize, 2), f.observation_count);
    try std.testing.expectEqual(@as(u8, 'D'), f.observations[1].byte);
    try expectRetired(&f, 1);
}

test "native ReqWrap routing typed callback failure still retires the final native Wrapper pointer" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    const node = try f.request(false);
    node.failure = .host;
    try std.testing.expectEqual(@as(c_int, 0),
        try f.dispatch(node, file.descriptor, &node.buffer, 1, 0, firstCallback));
    try std.testing.expectError(error.ActualReqWrapSelectedCallbackFailure, f.pump());
    try std.testing.expectEqual(@as(usize, 1), f.observation_count);
    try expectRetired(&f, 1);
    try std.testing.expect(!c.JS_HasException(f.engine.context) and f.engine.captured_exception == null);
}

test "native ReqWrap routing actual ordinary callback reason survives Entry destruction" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    const node = try f.request(false);
    node.failure = .ordinary;
    try std.testing.expectEqual(@as(c_int, 0),
        try f.dispatch(node, file.descriptor, &node.buffer, 1, 0, firstCallback));
    try std.testing.expectError(error.JavaScriptException, f.pump());
    const reason = try f.takeCaught(); defer f.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, f.reason.?));
    try expectRetired(&f, 1);
    try std.testing.expectEqualStrings("ard", f.trace[0..f.trace_length]);
}

test "native ReqWrap routing actual native fatal callback still completes native request retirement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    const node = try f.request(false);
    node.failure = .fatal;
    try std.testing.expectEqual(@as(c_int, 0),
        try f.dispatch(node, file.descriptor, &node.buffer, 1, 0, firstCallback));
    try std.testing.expectError(error.JavaScriptException, f.pump());
    const reason = try f.takeCaught(); defer f.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsError(reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(usize, 1), f.observation_count);
    try expectRetired(&f, 1);
}

test "native ReqWrap routing shared shutdown drains real callbacks after JavaScript is disabled" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    const first = try f.request(false);
    const second = try f.request(false);
    try std.testing.expectEqual(@as(c_int, 0),
        try f.dispatch(first, file.descriptor, &first.buffer, 1, 3, firstCallback));
    try f.waitQueued(1);
    try std.testing.expectEqual(@as(c_int, 0),
        try f.dispatch(second, file.descriptor, &second.buffer, 1, 5, secondCallback));
    try f.waitQueued(2);
    f.stopIo();
    try std.testing.expectEqual(@as(usize, 2), f.observation_count);
    try std.testing.expect(f.observations[0].js_disabled and f.observations[1].js_disabled);
    try std.testing.expectEqual(@as(c_int, 1), f.observations[0].waiting);
    try std.testing.expectEqual(@as(c_int, 0), f.observations[1].waiting);
    try std.testing.expectEqual(@as(u8, 'D'), f.observations[0].byte);
    try std.testing.expectEqual(@as(u8, 'F'), f.observations[1].byte);
    try expectRetired(&f, 2);
}

test "native ReqWrap routing stopped native service returns its real status without a callback or count" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const node = try f.request(false);
    try std.testing.expectEqual(@as(c_int, 0), uv.pi_uv_service_stop(f.controller.?.service));
    try std.testing.expectEqual(@as(c_int, physical.UV_ECANCELED),
        try f.dispatch(node, -1, &node.buffer, 1, 0, firstCallback));
    try std.testing.expect(node.entry.dispatched and node.entry.original_callback != null);
    try std.testing.expect(!node.entry.counted and node.state.strong_wrapper == null);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expectEqual(@as(usize, 0), f.observation_count);
    try std.testing.expectEqual(@as(usize, 0),
        uv.pi_uv_service_snapshot(f.controller.?.service).queued_events);
}

test "native ReqWrap routing retained Controller rejects a retired Hub before touching Entry inputs" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const node = try f.request(false);
    const retained = f.controller.?.retain();
    defer retained.release();
    f.stopIo();
    var scope = a.Scope.init(f.engine);
    const outcome = retained.dispatchRawRead(&scope, &node.entry, node.actual.?,
        -1, &node.buffer, 1, 0, firstCallback);
    const closed = scope.finish(if (outcome) |_| c.pi_js_undefined() else |err|
        @as(anyerror!c.JSValue, err));
    if (closed) |owned| f.engine.freeValue(owned) else |_| {}
    try std.testing.expectError(error.NativeEnvClosed, closed);
    try std.testing.expect(node.entry.original_callback == null and !node.entry.dispatched);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expectEqual(@as(usize, 0), f.observation_count);
}
