//! Shared source controls for actual FileHandle read and FSReqCallback owners.
//! This fixture assembles a native derived stream from the production State,
//! BindingData, StreamBase, ReqWrap, true templates and single UV Controller.
//! It is not the missing complete native FileHandle constructor/close/GC port.
//! Trace probes observe delegation only. Backing allocation admits the first
//! actual successful allocation; the production retry/GC policy is separate.
const std = @import("std");
pub const a = @import("extensions/native_node_argument_values.zig");
pub const em = a.v.em;
pub const c = em.c;
pub const callbacks = @import("extensions/native_node_callback_scope.zig");
const providers = @import("extensions/native_node_async_providers.zig");
pub const native = @import("extensions/native_node_async_wrap_state.zig");
pub const templates = @import("extensions/native_node_async_wrap.zig");
pub const binding = @import("extensions/native_node_fs_binding_data.zig");
pub const callback_request = @import("extensions/native_node_fs_request_callback.zig");
pub const file_read = @import("extensions/native_node_file_handle_read.zig");
const base = @import("extensions/native_node_stream_base.zig");
const managed = @import("extensions/native_node_managed_buffers.zig");
const callable = @import("extensions/native_node_module_callable.zig");
pub const fs_io = @import("extensions/native_node_fs_request_io.zig");
pub const uv = fs_io.uv;
pub const physical = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("uv.h");
    @cInclude("fcntl.h");
});

fn unselected(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedFileHandleReadOperation;
}
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror {
    return error.UnselectedFileHandleReadCheck;
}
fn unselectedCorruption(_: *callbacks.Environment, _: f64) anyerror {
    return error.UnselectedFileHandleReadCorruption;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = unselected,
    .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption,
    .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected,
    .request_destroy_interrupt = unselected,
};

pub const Action = enum { stop, until_eof, restart_once, throw_once_continue };
pub const Observation = struct {
    nread: i32,
    length: usize,
    bytes: [16]u8,
    waiting: c_int,
    current_empty: bool,
    freelist: usize,
    stream_bytes: u64,
};
pub const Read = file_read.Type(Handle);
pub const Handle = struct {
    state: native.State = undefined,
    stream: base.Base = undefined,
    read_state: Read.State = .{ .fd = -1 },
    inputs: file_read.Inputs,
    data: ?*binding.BindingData = null,
    fixture: *Fixture,

    pub fn getReadState(self: *Handle) *Read.State { return &self.read_state; }
    pub fn getReadInputs(self: *Handle) file_read.Inputs { return self.inputs; }
    pub fn getStreamBase(self: *Handle) *base.Base { return &self.stream; }
    pub fn getAsyncWrap(self: *Handle) *native.State { return &self.state; }
    pub fn getBindingData(self: *Handle) *binding.BindingData { return self.data.?; }
    fn getWrap(stream: *base.Base) ?*native.State {
        const self: *Handle = @fieldParentPtr("stream", stream);
        return &self.state;
    }
    fn mark(_: ?*c.JSRuntime, _: *native.State, _: ?*const c.JS_MarkFunc) void {}
    fn retire(state: *native.State, s: *a.Scope) !void {
        const self: *Handle = @alignCast(@fieldParentPtr("state", state));
        // The fixture joins/drains all actual I/O before native teardown.
        // It does not implement or qualify production FileHandle GC closure.
        std.debug.assert(self.read_state.current_read == null);
        self.stream.deinit();
        if (self.data) |data| {
            self.data = null;
            data.releaseNative() catch |err| {
                s.boundary.escaping();
                return err;
            };
        }
    }
    fn destroy(state: *native.State) void {
        const self: *Handle = @alignCast(@fieldParentPtr("state", state));
        const allocator = state.registry.environment.allocator();
        self.fixture.handle = null;
        self.fixture.handle_destroyed += 1;
        allocator.destroy(self);
    }
    const derived: native.Derived = .{
        .mark = mark, .retire = retire, .destroy = destroy,
    };
};

fn traceBegin(raw: ?*anyopaque, request: *anyopaque) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    const actual: *Read.ReadWrap = @ptrCast(@alignCast(request));
    std.debug.assert(f.begin_count < f.begin_pointers.len);
    f.begin_pointers[f.begin_count] = @intFromPtr(actual.actual.?);
    f.begin_ids[f.begin_count] = actual.wrap.async_id;
    f.begin_count += 1;
    f.begin_saw_member = f.begin_saw_member and
        f.handle.?.read_state.current_read == actual;
    f.begin_saw_undispatched = f.begin_saw_undispatched and !actual.entry.dispatched;
}
fn traceEnd(raw: ?*anyopaque, request: *anyopaque, result: c_int) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    const actual: *Read.ReadWrap = @ptrCast(@alignCast(request));
    std.debug.assert(f.end_count < f.end_results.len);
    f.end_results[f.end_count] = result;
    f.end_references[f.end_count] = actual.wrap.native_references;
    f.end_count += 1;
    f.end_saw_member = f.end_saw_member and
        f.handle.?.read_state.current_read == actual;
    f.end_saw_uncounted = f.end_saw_uncounted and !actual.entry.counted;
    f.end_saw_uncleaned = f.end_saw_uncleaned and
        uv.pi_uv_fs_request_info(actual.actual.?).cleaned == 0;
}
fn traceBefore(raw: ?*anyopaque, _: *native.State) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    f.before_count += 1;
}
fn traceAfter(raw: ?*anyopaque, _: u32, _: f64) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    f.after_count += 1;
}
fn allocateFirst(raw: ?*anyopaque, environment: *callbacks.Environment,
    length: usize, initialization: base.Initialization) managed.Token
{
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    std.debug.assert(environment == f.env());
    var result: managed.Token = std.mem.zeroes(managed.Token);
    const status = c.JS_PiTryNewArrayBufferBackingStore(f.engine.runtime,
        length, initialization == .zero_initialized, &result);
    if (status != 1) {
        c.JS_PiReleaseArrayBufferBackingStore(&result);
        @panic("unexpected backing failure in first-success FileHandle fixture");
    }
    std.debug.assert(f.allocation_count < f.allocation_lengths.len);
    f.allocation_lengths[f.allocation_count] = length;
    f.allocation_count += 1;
    return result;
}
fn onRead(context: ?*c.JSContext, _: c.JSValue, argc: c_int,
    argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const f: *Fixture = @ptrCast(@alignCast(c.JS_GetOpaque(
        data[0], c.JS_GetClassID(data[0])) orelse unreachable));
    const engine = em.Engine.fromContext(context.?);
    return a.expression(engine, onReadBody, .{ f, argc, argv }) catch |err|
        callable.failure(engine, err, 0);
}
fn onReadBody(s: *a.Scope, f: *Fixture, argc: c_int, argv: [*c]c.JSValue) !c.JSValue {
    if (argc != 1 or f.read_count == f.observations.len)
        return error.ActualFileHandleReadObservationCapacity;
    const node = f.handle.?;
    const nread = f.env().streamBaseField(.read_bytes_or_error).*;
    var observation: Observation = .{
        .nread = nread, .length = 0, .bytes = @splat(0),
        .waiting = f.env().requests.waiting,
        .current_empty = node.read_state.current_read == null,
        .freelist = node.data.?.file_handle_read_wrap_freelist.items.len,
        .stream_bytes = node.stream.resource.bytes_read,
    };
    if (!c.JS_IsUndefined(argv[0])) {
        var length: usize = 0;
        const bytes = c.JS_GetArrayBuffer(s.engine.context, &length, argv[0]);
        try s.pending();
        if (length > observation.bytes.len or (bytes == null and length != 0))
            return error.ActualFileHandleReadObservedBufferRequired;
        observation.length = length;
        if (length != 0) @memcpy(observation.bytes[0..length], bytes[0..length]);
    }
    f.observations[f.read_count] = observation;
    f.read_count += 1;
    switch (f.action) {
        .stop => { _ = Read.stop(node); },
        .until_eof => if (nread < 0) { _ = Read.stop(node); },
        .restart_once => {
            if (f.read_count == 1) {
                _ = try Read.start(s, node);
                f.reentrant_waiting = f.env().requests.waiting;
            } else { _ = Read.stop(node); }
        },
        .throw_once_continue => {
            if (f.read_count == 1) return a.raise(s, f.reason.?);
            _ = Read.stop(node);
        },
    }
    return c.pi_js_undefined();
}

pub const Fixture = struct {
    native_environment: std.process.Environ.Map,
    native_environment_alive: bool = true,
    engine: *em.Engine = undefined,
    engine_alive: bool = false,
    environment: ?*callbacks.Environment = null,
    templates_owner: ?c.JSValue = null,
    registry_owner: ?*native.Registry = null, // borrowed from templates_owner
    controller: ?*fs_io.Controller = null, // Hub owns; templates retain
    data: ?*binding.BindingData = null, // borrowed actual Realm object
    binding_target: ?c.JSValue = null, // bootstrap local until actual Handle retains data
    prototype: ?c.JSValue = null,
    handle_key: ?c.JSValue = null,
    wrapper_value: ?c.JSValue = null,
    reason: ?c.JSValue = null,
    handle: ?*Handle = null,
    handle_destroyed: usize = 0,
    marker_class: c.JSClassID = 0,
    outer: callbacks.Scope = undefined,
    outer_initialized: bool = false,
    io_stopped: bool = false,
    action: Action = .stop,
    observations: [16]Observation = undefined,
    read_count: usize = 0,
    allocation_lengths: [32]usize = undefined,
    allocation_count: usize = 0,
    begin_pointers: [16]usize = undefined,
    begin_ids: [16]f64 = undefined,
    begin_count: usize = 0,
    end_results: [16]c_int = undefined,
    end_references: [16]usize = undefined,
    end_count: usize = 0,
    before_count: usize = 0,
    after_count: usize = 0,
    begin_saw_member: bool = true,
    begin_saw_undispatched: bool = true,
    end_saw_member: bool = true,
    end_saw_uncounted: bool = true,
    end_saw_uncleaned: bool = true,
    reentrant_waiting: c_int = 0,

    pub fn init(self: *Fixture) !void {
        self.* = .{ .native_environment = .init(std.testing.allocator) };
        errdefer self.deinit();
        self.engine = try em.Engine.init(std.testing.allocator, .{});
        self.engine_alive = true;
        try @import("extensions/native_process.zig").install(
            self.engine, std.testing.io, &self.native_environment,
            &.{"native-filehandle-read"});
        const initialized = try a.expression(self.engine, bootstrap, .{self});
        self.engine.freeValue(initialized);
        self.controller = switch (try fs_io.acquire(self.engine, self.env())) {
            .ready => |controller| controller,
            .failed => return error.ActualFileHandleReadServiceAdmissionFailed,
        };
        try templates.configureFSReqCallback(self.engine,
            self.templates_owner.?, self.controller.?);
        const assembled = try a.expression(self.engine, assemble, .{self});
        self.engine.freeValue(assembled);
        self.drop(&self.binding_target);
        self.outer.initialized = false;
        self.outer.init(self.env(), self.wrapper_value.?,
            .{ .async_id = 0, .trigger_async_id = 0 },
            .{ .skip_async_hooks = true, .skip_task_queues = true },
            c.pi_js_undefined()) catch |err| {
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
        const symbol = try s.checkedAllocation(c.JS_NewSymbol(
            s.engine.context, "node:resource_symbol", false), generation);
        self.environment = try callbacks.Environment.create(s.engine, .{
            .provider_names = providers.names(false), .resource_symbol = symbol,
            .process_object = process, .async_context_frame = true,
            .operations = operations,
        });
        self.env().markBootstrapComplete();
        self.templates_owner = try templates.acquire(s.engine, self.env());
        self.registry_owner = try templates.registry(s.engine, self.templates_owner.?);
        const object = try s.get(global, "Object");
        self.prototype = a.duplicate(s.engine, try s.get(object, "prototype"));
        self.handle_key = a.duplicate(s.engine, try s.text("handle"));
        self.reason = a.duplicate(s.engine, try s.object());
        const shape = try binding.TargetTemplate.create(s);
        const target = try shape.newInstance(s, self.prototype.?);
        self.binding_target = a.duplicate(s.engine, target);
        self.data = try binding.BindingData.create(s, shape, target,
            self.templates_owner.?, try s.text("promise"));
        return c.pi_js_undefined();
    }
    fn assemble(s: *a.Scope, self: *Fixture) !c.JSValue {
        const wrapper = try self.registry().newInstance(s, .filehandle, self.prototype.?);
        self.wrapper_value = a.duplicate(s.engine, wrapper);
        const node = try self.env().allocator().create(Handle);
        node.* = .{
            .fixture = self,
            .inputs = .{ .controller = self.controller.?, .handle_string = self.handle_key.?,
                .trace = .{ .raw = self, .begin_read = traceBegin, .end_read = traceEnd } },
        };
        node.stream.initialized = false;
        self.handle = node;
        errdefer if (self.registry().unwrap(wrapper) != &node.state) {
            self.handle = null;
            self.env().allocator().destroy(node);
        };
        try node.state.initialize(self.registry(), wrapper, Handle.derived,
            native.Provider.filehandle, -1);
        try self.data.?.retainNative();
        node.data = self.data;
        try node.stream.init(self.env(), .{ .get_async_wrap = Handle.getWrap }, .{
            .allocation = .{ .raw = self, .new_backing_store = allocateFirst },
            .trace = .{ .raw = self, .before = traceBefore, .after = traceAfter },
            .heap_diagnostics = null,
        });
        try node.stream.attachToObject(self.registry(), wrapper);
        const class_generation = try s.beforeAllocation();
        if (c.JS_NewClassID(s.engine.runtime, &self.marker_class) == 0)
            return error.OutOfMemory;
        const definition: c.JSClassDef = .{ .class_name = "Actual FileHandle read probe" };
        if (c.JS_NewClass(s.engine.runtime, self.marker_class, &definition) < 0)
            return error.OutOfMemory;
        try s.boundary.checkPendingSince(class_generation);
        const marker_generation = try s.beforeAllocation();
        const marker = try s.checkedAllocation(c.JS_NewObjectClass(
            s.engine.context, self.marker_class), marker_generation);
        _ = c.JS_SetOpaque(marker, self);
        var roots = [_]c.JSValue{marker};
        const function_generation = try s.beforeAllocation();
        const function = try s.checkedAllocation(c.JS_NewCFunctionData2(
            s.engine.context, onRead, "actualFileHandleRead", 1, 0,
            roots.len, &roots), function_generation);
        try self.registry().setStreamOnRead(s, wrapper, function);
        return c.pi_js_undefined();
    }
    pub fn env(self: *Fixture) *callbacks.Environment { return self.environment.?; }
    pub fn registry(self: *Fixture) *native.Registry { return self.registry_owner.?; }
    pub fn start(self: *Fixture) !c_int {
        var status: c_int = undefined;
        const ignored = try a.expression(self.engine, startBody, .{ self, &status });
        self.engine.freeValue(ignored);
        return status;
    }
    fn startBody(s: *a.Scope, self: *Fixture, status: *c_int) !c.JSValue {
        status.* = try Read.start(s, self.handle.?);
        return c.pi_js_undefined();
    }
    pub fn seed(self: *Fixture, count: usize) !void {
        const ignored = try a.expression(self.engine, seedBody, .{ self, count });
        self.engine.freeValue(ignored);
    }
    fn seedBody(s: *a.Scope, self: *Fixture, count: usize) !c.JSValue {
        for (0..count) |_| {
            const wrapper = try templates.newFSReqCallbackInstance(s, self.templates_owner.?);
            const request = try Read.ReadWrap.createDetached(s,
                self.controller.?, self.handle.?, wrapper);
            self.data.?.file_handle_read_wrap_freelist.append(
                self.env().allocator(), &request.wrap) catch |err| {
                var completion = a.owned.Completion.initVoid(s.engine, err);
                request.release() catch {};
                try completion.finishVoid();
            };
        }
        return c.pi_js_undefined();
    }
    pub fn queueCount(self: *Fixture) usize {
        var count: usize = 0;
        var cursor = self.env().requests.head;
        while (cursor) |entry| : (cursor = entry.next) count += 1;
        return count;
    }
    pub fn waitQueued(self: *Fixture, count: usize) !void {
        const until = physical.uv_hrtime() + 10 * std.time.ns_per_s;
        while (uv.pi_uv_service_snapshot(self.controller.?.service).queued_events < count) {
            if (physical.uv_hrtime() >= until) return error.ActualFileHandleReadCompletionTimeout;
            physical.uv_sleep(1);
        }
    }
    pub fn pump(self: *Fixture) !void {
        const until = physical.uv_hrtime() + 10 * std.time.ns_per_s;
        while (self.env().requests.waiting != 0) {
            if (c.JS_IsJobPending(self.engine.runtime)) return error.UnselectedFileHandleReadTaskQueue;
            const pump_native = self.engine.native_env_pump orelse return error.ActualFileHandleReadHubRequired;
            _ = try pump_native(self.engine);
            if (self.env().requests.waiting == 0) break;
            if (physical.uv_hrtime() >= until) return error.ActualFileHandleReadCompletionTimeout;
            physical.uv_sleep(1);
        }
    }
    pub fn takeCaught(self: *Fixture) !c.JSValue {
        const reason = self.engine.captured_exception orelse return error.ActualFileHandleReadReasonRequired;
        self.engine.captured_exception = null;
        return reason;
    }
    pub fn evaluate(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-filehandle-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
    }
    pub fn expose(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const ignored = try a.expression(self.engine, struct {
            fn body(s: *a.Scope, key: [*:0]const u8, item: c.JSValue) !c.JSValue {
                const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
                try s.put(global, key, item);
                return c.pi_js_undefined();
            }
        }.body, .{ name, value });
        self.engine.freeValue(ignored);
    }
    pub fn stopIo(self: *Fixture) void {
        if (self.io_stopped) return;
        self.io_stopped = true;
        if (self.handle) |node| { _ = Read.stop(node); }
        if (self.environment) |environment| environment.can_call_into_js = false;
        if (self.engine_alive) if (self.engine.native_env_deinit) |stop| stop(self.engine);
        self.controller = null;
    }
    fn drop(self: *Fixture, slot: *?c.JSValue) void {
        if (slot.*) |value| { slot.* = null; self.engine.freeValue(value); }
    }
    pub fn deinit(self: *Fixture) void {
        self.stopIo();
        if (self.outer_initialized) {
            self.outer_initialized = false;
            self.outer.deinit() catch @panic("FileHandle fixture callback scope teardown failed");
        }
        if (self.environment) |environment| {
            environment.cleanupRealmAfterIoJoin() catch @panic("FileHandle fixture realm cleanup failed");
            environment.disarm() catch @panic("FileHandle fixture Environment disarm failed");
        }
        self.data = null;
        self.registry_owner = null;
        if (self.engine_alive) {
            self.drop(&self.wrapper_value);
            self.drop(&self.binding_target);
            self.drop(&self.reason);
            self.drop(&self.handle_key);
            self.drop(&self.prototype);
            self.drop(&self.templates_owner);
        }
        if (self.environment) |environment| { self.environment = null; environment.release(); }
        if (self.engine_alive) { self.engine_alive = false; self.engine.deinit(); }
        if (self.native_environment_alive) {
            self.native_environment_alive = false;
            self.native_environment.deinit();
        }
    }
};

pub const File = struct {
    fixture: *Fixture,
    temporary: std.testing.TmpDir = undefined,
    temporary_ready: bool = false,
    path: ?[:0]u8 = null,
    descriptor: c_int = -1,
    pub fn init(self: *File, fixture: *Fixture) !void {
        self.* = .{ .fixture = fixture };
        errdefer self.deinit();
        self.temporary = std.testing.tmpDir(.{});
        self.temporary_ready = true;
        try self.temporary.dir.writeFile(std.testing.io,
            .{ .sub_path = "read.bin", .data = "ABCDEFGH" });
        const directory = try self.temporary.dir.realPathFileAlloc(
            std.testing.io, ".", std.testing.allocator);
        defer std.testing.allocator.free(directory);
        const joined = try std.fs.path.join(std.testing.allocator, &.{directory, "read.bin"});
        defer std.testing.allocator.free(joined);
        self.path = try std.testing.allocator.dupeZ(u8, joined);
        var actual: physical.uv_fs_t = undefined;
        const status = physical.uv_fs_open(null, &actual, self.path.?.ptr,
            physical.O_RDONLY, 0, null);
        physical.uv_fs_req_cleanup(&actual);
        if (status >= 0) self.descriptor = status;
        if (status < 0) return error.ActualFileHandleReadFileOpenFailed;
        fixture.handle.?.read_state.fd = self.descriptor;
    }
    pub fn close(self: *File) !void {
        if (self.descriptor < 0) return;
        var actual: physical.uv_fs_t = undefined;
        const status = physical.uv_fs_close(null, &actual, self.descriptor, null);
        physical.uv_fs_req_cleanup(&actual);
        if (status != 0) return error.ActualFileHandleReadFileCloseFailed;
        self.descriptor = -1;
    }
    pub fn deinit(self: *File) void {
        self.fixture.stopIo();
        self.close() catch @panic("FileHandle fixture descriptor close failed");
        if (self.path) |path| { self.path = null; std.testing.allocator.free(path); }
        if (self.temporary_ready) { self.temporary_ready = false; self.temporary.cleanup(); }
    }
};
