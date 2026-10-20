//! Source controls for the concrete native FileHandle/CloseReq/GC owners.
//! Every tested descriptor is actual libuv storage. This fixture supplies a
//! real Environment, BindingData, request queue, physical service and native
//! immediate queue. Its trace/allocation/caught hooks are observation points;
//! they do not qualify production trace, allocation retry or uncaught policy.
//! The present-object constructor is selected explicitly because the complete
//! FileHandle/StreamBase method template remains a separate production owner.
const std = @import("std");
pub const a = @import("extensions/native_node_argument_values.zig");
pub const em = a.v.em;
pub const c = a.c;
pub const native = @import("extensions/native_node_async_wrap_state.zig");
pub const callbacks = @import("extensions/native_node_callback_scope.zig");
pub const templates = @import("extensions/native_node_async_wrap.zig");
pub const binding = @import("extensions/native_node_fs_binding_data.zig");
pub const owner = @import("extensions/native_node_file_handle_owner.zig");
pub const Handle = owner.Handle;
const providers = @import("extensions/native_node_async_providers.zig");
const stream = @import("extensions/native_node_stream_base.zig");
const managed = @import("extensions/native_node_managed_buffers.zig");
const callable = @import("extensions/native_node_module_callable.zig");
pub const fs_io = @import("extensions/native_node_fs_request_io.zig");
pub const fs_promise = @import("extensions/native_node_fs_request_promise.zig");
const fs_read = @import("extensions/native_node_file_handle_read_binding.zig");
pub const uv = fs_io.uv;
pub const immediate = @import("extensions/native_node_native_immediates.zig");
pub const phase = @import("extensions/native_immediates.zig");
pub const physical = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("uv.h");
    @cInclude("fcntl.h");
});

/// Explicit selected test policy for a REAL throwing JavaScript before hook.
/// It consumes only the actual current pending value, verifies the selected
/// identity, and reinstalls that same value as an ordinary rethrow. This is
/// not the missing production kFatalRethrowStackOverflow classifier/fatal path.
fn selectedHookException(environment: *callbacks.Environment) anyerror!void {
    const engine = try environment.requireEngine();
    const f = fixtureOf(engine);
    const expected = f.selected_hook_reason orelse
        return error.UnselectedConcreteFileHandleHookPolicy;
    if (!c.JS_HasException(engine.context))
        return error.ConcreteFileHandleHookRequiresCurrentPending;
    const actual = c.JS_GetException(engine.context);
    if (!c.JS_IsStrictEqual(engine.context, actual, expected) or
        c.JS_IsUncatchableError(actual))
    {
        _ = c.JS_Throw(engine.context, actual);
        return error.UnselectedConcreteFileHandleHookReason;
    }
    f.hook_rethrows += 1;
    _ = c.JS_Throw(engine.context, actual);
    return error.JavaScriptException;
}
fn warningFlag(context: ?*c.JSContext, _: c.JSValue, _: c_int,
    _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const engine = em.Engine.fromContext(context.?);
    return c.pi_js_bool(engine.context,
        @intFromBool(fixtureOf(engine).env().emit_filehandle_warning));
}
fn unselected(_: *callbacks.Environment) anyerror!void {
    return error.UnselectedConcreteFileHandleEnvironmentOperation;
}
fn unselectedCheck(_: *callbacks.Environment, _: callbacks.Check) anyerror {
    return error.UnselectedConcreteFileHandleCheck;
}
fn unselectedCorruption(_: *callbacks.Environment, _: f64) anyerror {
    return error.UnselectedConcreteFileHandleStackCorruption;
}
const operations: callbacks.Operations = .{
    .on_hook_exception = selectedHookException,
    .native_check_failure = unselectedCheck,
    .fail_corrupted_async_stack = unselectedCorruption,
    .perform_checkpoint = unselected,
    .schedule_destroy_immediate = unselected,
    .request_destroy_interrupt = unselected,
};

const NativeCallback = struct {
    scope: callbacks.Scope = undefined,
    fixture: *Fixture,
    prior_javascript: ?bool = null,
};
fn fixtureOf(engine: *em.Engine) *Fixture {
    return @ptrCast(@alignCast(engine.host_control_context orelse unreachable));
}
fn beginImmediate(engine: *em.Engine, mode: immediate.Mode) !immediate.CallbackScope {
    const f = fixtureOf(engine);
    const frame = try f.env().allocator().create(NativeCallback);
    frame.* = .{ .fixture = f };
    frame.scope.initialized = false;
    errdefer {
        if (frame.scope.initialized) {
            frame.scope.markFailed();
            frame.scope.deinit() catch {};
        }
        f.env().allocator().destroy(frame);
    }
    try frame.scope.init(f.env(), c.pi_js_undefined(),
        .{ .async_id = 0, .trigger_async_id = 0 },
        .{ .skip_async_hooks = true, .skip_task_queues = true },
        c.pi_js_undefined());
    if (mode == .cleanup)
        frame.prior_javascript = c.JS_PiExchangeJavascriptExecutionAllowed(engine.runtime, false);
    f.immediate_scopes += 1;
    return .{ .raw = frame, .finish = finishImmediate };
}
fn finishImmediate(engine: *em.Engine, raw: ?*anyopaque, outcome: anyerror!bool) !bool {
    const frame: *NativeCallback = @ptrCast(@alignCast(raw.?));
    const f = frame.fixture;
    var handles = a.Scope.init(engine);
    var worked = false;
    var failure: ?anyerror = null;
    if (outcome) |value| worked = value else |err| {
        handles.boundary.escaping();
        failure = err;
        frame.scope.markFailed();
    }
    frame.scope.deinit() catch |err| {
        handles.boundary.escaping();
        if (failure == null) failure = err;
    };
    if (frame.prior_javascript) |previous|
        _ = c.JS_PiExchangeJavascriptExecutionAllowed(engine.runtime, previous);
    f.env().allocator().destroy(frame);
    const ignored = try handles.finish(if (failure) |err|
        @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
    engine.freeValue(ignored);
    return worked;
}
fn caughtImmediate(engine: *em.Engine, err: anyerror) void {
    const f = fixtureOf(engine);
    if (err != error.JavaScriptException or f.caught_count == f.caught.len)
        @panic("unselected native immediate failure in concrete FileHandle fixture");
    const reason = engine.captured_exception orelse
        @panic("native immediate did not preserve its actual caught reason");
    engine.captured_exception = null;
    if (c.JS_IsUncatchableError(reason))
        @panic("unselected native fatal in concrete FileHandle fixture");
    f.caught[f.caught_count] = reason;
    f.caught_count += 1;
}
const immediate_hooks: immediate.Hooks = .{
    .begin = beginImmediate, .caught = caughtImmediate,
};

fn allocateFirst(raw: ?*anyopaque, env: *callbacks.Environment,
    length: usize, initialization: stream.Initialization) managed.Token
{
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    std.debug.assert(env == f.env());
    var value: managed.Token = std.mem.zeroes(managed.Token);
    const status = c.JS_PiTryNewArrayBufferBackingStore(
        f.engine.runtime, length, initialization == .zero_initialized, &value);
    if (status != 1) {
        c.JS_PiReleaseArrayBufferBackingStore(&value);
        @panic("unselected backing allocation failure in concrete FileHandle fixture");
    }
    f.allocations += 1;
    return value;
}
fn beforeReadCallback(raw: ?*anyopaque, _: *native.State) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    f.before_read_callbacks += 1;
}
fn afterReadCallback(raw: ?*anyopaque, _: u32, _: f64) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    f.after_read_callbacks += 1;
}
fn beginRead(raw: ?*anyopaque, value: *anyopaque) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    const request: *Handle.Reader.ReadWrap = @ptrCast(@alignCast(value));
    std.debug.assert(f.read_begins < f.read_requests.len);
    f.read_requests[f.read_begins] = @intFromPtr(request.actual.?);
    f.read_ids[f.read_begins] = request.wrap.async_id;
    f.read_begins += 1;
    f.read_member_exact = f.read_member_exact and
        request.file_handle.read_state.current_read == request;
}
fn endRead(raw: ?*anyopaque, _: *anyopaque, result: c_int) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    f.last_read_result = result;
    f.read_ends += 1;
}
fn beginSyncClose(raw: ?*anyopaque) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    f.sync_begins += 1;
}
fn endSyncClose(raw: ?*anyopaque) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    f.sync_ends += 1;
}
fn beginAsyncClose(raw: ?*anyopaque, value: *anyopaque) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    const request: *Handle.CloseReq = @ptrCast(@alignCast(value));
    f.close_begins += 1;
    f.close_actual = @intFromPtr(request.actual.?);
    f.close_begin_provider = request.wrap.provider;
    f.close_begin_kind = uv.pi_uv_fs_request_info(request.actual.?).kind;
    f.close_begin_unsubmitted = !request.entry.dispatched and !request.entry.counted;
    f.close_begin_globals = request.promise != null and request.reference != null;
}
fn endAsyncClose(raw: ?*anyopaque, value: *anyopaque, result: c_int) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    const request: *Handle.CloseReq = @ptrCast(@alignCast(value));
    const info = uv.pi_uv_fs_request_info(request.actual.?);
    f.close_ends += 1;
    f.close_result = result;
    f.close_end_actual = @intFromPtr(request.actual.?);
    f.close_end_references = request.wrap.native_references;
    f.close_end_uncounted = !request.entry.counted and f.env().requests.waiting == 0;
    f.close_end_accepted_uncleaned = info.accepted != 0 and info.cleaned == 0;
}
fn onRead(context: ?*c.JSContext, _: c.JSValue, argc: c_int,
    argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const engine = em.Engine.fromContext(context.?);
    const f: *Fixture = @ptrCast(@alignCast(c.JS_GetOpaque(
        roots[0], c.JS_GetClassID(roots[0])) orelse unreachable));
    return a.expression(engine, onReadBody, .{ f, argc, argv }) catch |err|
        callable.failure(engine, err, 0);
}
fn onReadBody(s: *a.Scope, f: *Fixture, argc: c_int, argv: [*c]c.JSValue) !c.JSValue {
    if (argc != 1) return error.ConcreteFileHandleReadArity;
    const handle = try f.handle();
    f.read_callbacks += 1;
    f.last_nread = f.env().streamBaseField(.read_bytes_or_error).*;
    f.last_read_length = 0;
    if (!c.JS_IsUndefined(argv[0])) {
        var length: usize = 0;
        const bytes = c.JS_GetArrayBuffer(s.engine.context, &length, argv[0]);
        try s.pending();
        if (length > f.read_bytes.len or (bytes == null and length != 0))
            return error.ConcreteFileHandleReadExtent;
        if (length != 0) @memcpy(f.read_bytes[0..length], bytes[0..length]);
        f.last_read_length = length;
    }
    _ = handle.readStop();
    return c.pi_js_undefined();
}

pub const Fixture = struct {
    native_environment: std.process.Environ.Map,
    native_environment_alive: bool = true,
    engine: *em.Engine = undefined,
    engine_alive: bool = false,
    environment: ?*callbacks.Environment = null,
    template_owner: ?c.JSValue = null,
    registry_owner: ?*native.Registry = null,
    controller: ?*fs_io.Controller = null,
    queue: ?*immediate.Queue = null,
    binding_target: ?c.JSValue = null,
    prototype: ?c.JSValue = null,
    handle_key: ?c.JSValue = null,
    primary_wrapper: ?c.JSValue = null,
    outer: callbacks.Scope = undefined,
    outer_initialized: bool = false,
    io_stopped: bool = false,
    marker_class: c.JSClassID = 0,
    immediate_scopes: usize = 0,
    caught: [8]c.JSValue = undefined,
    caught_count: usize = 0,
    selected_hook_reason: ?c.JSValue = null,
    hook_rethrows: usize = 0,
    allocations: usize = 0,
    before_read_callbacks: usize = 0,
    after_read_callbacks: usize = 0,
    read_begins: usize = 0,
    read_ends: usize = 0,
    read_requests: [8]usize = undefined,
    read_ids: [8]f64 = undefined,
    read_member_exact: bool = true,
    last_read_result: c_int = 0,
    read_callbacks: usize = 0,
    last_nread: i32 = 0,
    read_bytes: [32]u8 = @splat(0),
    last_read_length: usize = 0,
    sync_begins: usize = 0,
    sync_ends: usize = 0,
    close_begins: usize = 0,
    close_ends: usize = 0,
    close_actual: usize = 0,
    close_end_actual: usize = 0,
    close_begin_provider: u32 = 0,
    close_begin_kind: c_int = 0,
    close_begin_unsubmitted: bool = false,
    close_begin_globals: bool = false,
    close_result: c_int = 0,
    close_end_references: usize = 0,
    close_end_uncounted: bool = false,
    close_end_accepted_uncleaned: bool = false,

    pub fn init(self: *Fixture) !void {
        self.* = .{ .native_environment = .init(std.testing.allocator) };
        errdefer self.deinit();
        self.engine = try em.Engine.init(std.testing.allocator, .{});
        self.engine_alive = true;
        self.engine.host_control_context = self;
        try @import("extensions/native_process.zig").install(self.engine,
            std.testing.io, &self.native_environment, &.{"native-filehandle-owner"});
        const value = try a.expression(self.engine, bootstrap, .{self});
        self.engine.freeValue(value);
        try self.engine.bindFunction("actualOwnerWarningFlag", warningFlag, 0);
        self.controller = switch (try fs_io.acquire(self.engine, self.env())) {
            .ready => |actual| actual,
            .failed => return error.ConcreteFileHandleServiceAdmissionFailed,
        };
        try templates.configureFSReqCallback(self.engine, self.template_owner.?, self.controller.?);
        try phase.install(self.engine);
        self.queue = try phase.acquireNative(self.engine, immediate_hooks);
        self.outer.initialized = false;
        self.outer.init(self.env(), c.pi_js_undefined(),
            .{ .async_id = 0, .trigger_async_id = 0 },
            .{ .skip_async_hooks = true, .skip_task_queues = true },
            c.pi_js_undefined()) catch |err| {
            if (self.outer.initialized) {
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
        self.template_owner = try templates.acquire(s.engine, self.env());
        self.registry_owner = try templates.registry(s.engine, self.template_owner.?);
        const object = try s.get(global, "Object");
        const object_prototype = try s.get(object, "prototype");
        const async_constructor = try s.own(try templates.constructor(
            s.engine, self.template_owner.?, .async_wrap));
        self.prototype = a.duplicate(s.engine, try s.get(async_constructor, "prototype"));
        self.handle_key = a.duplicate(s.engine, try s.text("handle"));
        const shape = try binding.TargetTemplate.create(s);
        const target = try shape.newInstance(s, object_prototype);
        self.binding_target = a.duplicate(s.engine, target);
        _ = try binding.BindingData.create(s, shape, target,
            self.template_owner.?, try s.text("promise"));
        const class_generation = try s.beforeAllocation();
        if (c.JS_NewClassID(s.engine.runtime, &self.marker_class) == 0) return error.OutOfMemory;
        const definition: c.JSClassDef = .{ .class_name = "Concrete FileHandle observation" };
        if (c.JS_NewClass(s.engine.runtime, self.marker_class, &definition) < 0)
            return error.OutOfMemory;
        try s.boundary.checkPendingSince(class_generation);
        return c.pi_js_undefined();
    }
    pub fn env(self: *Fixture) *callbacks.Environment { return self.environment.?; }
    pub fn registry(self: *Fixture) *native.Registry { return self.registry_owner.?; }
    pub fn handle(self: *Fixture) !*Handle {
        return Handle.fromObject(self.registry(), self.primary_wrapper orelse
            return error.ConcreteFileHandleWrapperRequired);
    }
    fn inputs(self: *Fixture) owner.Inputs {
        return .{
            .controller = self.controller.?, .immediate_queue = self.queue.?,
            .handle_string = self.handle_key.?,
            .read_trace = .{ .raw = self, .begin_read = beginRead, .end_read = endRead },
            .close_trace = .{ .raw = self, .begin_sync = beginSyncClose,
                .end_sync = endSyncClose, .begin_async = beginAsyncClose, .end_async = endAsyncClose },
            .stream = .{
                .allocation = .{ .raw = self, .new_backing_store = allocateFirst },
                .trace = .{ .raw = self, .before = beforeReadCallback, .after = afterReadCallback },
                .heap_diagnostics = null,
            },
        };
    }
    pub fn create(self: *Fixture, descriptor: c_int, offset: ?f64, length: ?f64) !*Handle {
        const args = [_]c.JSValue{
            c.JS_NewInt32(self.engine.context, descriptor),
            if (offset) |value| c.JS_NewFloat64(self.engine.context, value) else c.pi_js_undefined(),
            if (length) |value| c.JS_NewFloat64(self.engine.context, value) else c.pi_js_undefined(),
        };
        return self.createArgs(&args);
    }
    pub fn createArgs(self: *Fixture, args: []const c.JSValue) !*Handle {
        if (self.primary_wrapper != null) return error.ConcreteFileHandlePreviousWrapperRequiredGone;
        const value = try a.expression(self.engine, createBody, .{ self, args });
        self.engine.freeValue(value);
        return self.handle();
    }
    fn createBody(s: *a.Scope, self: *Fixture, args: []const c.JSValue) !c.JSValue {
        // The fixture supplies a genuine FileHandle internal-field class and
        // parent prototype. It does not publish the missing complete template.
        const wrapper = try self.registry().newInstance(s, .filehandle, self.prototype.?);
        self.primary_wrapper = a.duplicate(s.engine, wrapper);
        try Handle.construct(s, self.registry(), wrapper, args, true, self.inputs());
        const generation = try s.beforeAllocation();
        const marker = try s.checkedAllocation(c.JS_NewObjectClass(
            s.engine.context, self.marker_class), generation);
        _ = c.JS_SetOpaque(marker, self);
        var roots = [_]c.JSValue{marker};
        const function_generation = try s.beforeAllocation();
        const function = try s.checkedAllocation(c.JS_NewCFunctionData2(
            s.engine.context, onRead, "concreteFileHandleOnRead", 1, 0,
            roots.len, &roots), function_generation);
        try self.registry().setStreamOnRead(s, wrapper, function);
        return c.pi_js_undefined();
    }
    pub fn start(self: *Fixture) !c_int {
        var result: c_int = undefined;
        const ignored = try a.expression(self.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, output: *c_int) !c.JSValue {
                output.* = try (try f.handle()).readStart(s);
                return c.pi_js_undefined();
            }
        }.body, .{ self, &result });
        self.engine.freeValue(ignored);
        return result;
    }
    pub fn releaseDescriptor(self: *Fixture) !c_int {
        var result: c_int = undefined;
        const ignored = try a.expression(self.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, output: *c_int) !c.JSValue {
                output.* = try (try f.handle()).releaseDescriptor(s);
                return c.pi_js_undefined();
            }
        }.body, .{ self, &result });
        self.engine.freeValue(ignored);
        return result;
    }
    pub fn collectHandle(self: *Fixture) void {
        self.drop(&self.primary_wrapper);
        c.JS_RunGC(self.engine.runtime);
    }
    pub fn dropBindingTarget(self: *Fixture) void {
        self.drop(&self.binding_target);
        c.JS_RunGC(self.engine.runtime);
    }
    pub fn pendingClose(self: *Fixture) !*Handle.CloseReq {
        var cursor = self.env().requests.head;
        while (cursor) |entry| : (cursor = entry.next) {
            if (entry.wrap.provider == native.Provider.filehandleclosereq)
                return Handle.CloseReq.fromEntry(entry);
        }
        return error.ConcreteFileHandleCloseRequestRequired;
    }
    pub fn pendingFs(self: *Fixture) !*fs_promise.Request {
        var cursor = self.env().requests.head;
        while (cursor) |entry| : (cursor = entry.next) {
            if (entry.wrap.provider == native.Provider.fsreqpromise)
                return @alignCast(@fieldParentPtr("entry", entry));
        }
        return error.ConcreteFSBeforeHookRequestRequired;
    }
    pub fn queueCount(self: *Fixture) usize {
        var count: usize = 0;
        var cursor = self.env().requests.head;
        while (cursor) |entry| : (cursor = entry.next) count += 1;
        return count;
    }
    pub fn waitNativeQueued(self: *Fixture, count: usize) !void {
        const service = self.controller.?.service;
        const limit = physical.uv_hrtime() + 10 * std.time.ns_per_s;
        while (uv.pi_uv_service_snapshot(service).queued_events < count) {
            if (physical.uv_hrtime() >= limit) return error.ConcreteFileHandleCompletionTimeout;
            physical.uv_sleep(1);
        }
    }
    pub fn pumpIo(self: *Fixture) !void {
        const limit = physical.uv_hrtime() + 10 * std.time.ns_per_s;
        while (self.env().requests.waiting != 0) {
            if (c.JS_IsJobPending(self.engine.runtime)) return error.UnselectedConcreteFileHandleJobQueue;
            const pump = self.engine.native_env_pump orelse return error.ConcreteFileHandleHubRequired;
            _ = try pump(self.engine);
            if (self.env().requests.waiting == 0) break;
            if (physical.uv_hrtime() >= limit) return error.ConcreteFileHandleCompletionTimeout;
            physical.uv_sleep(1);
        }
    }
    pub fn value(self: *Fixture, source: []const u8) !c.JSValue {
        return self.engine.eval(source, "concrete-filehandle-control.js", c.JS_EVAL_TYPE_GLOBAL);
    }
    pub fn expect(self: *Fixture, expression: []const u8) !void {
        const result = try self.value(expression);
        defer self.engine.freeValue(result);
        try std.testing.expect(c.JS_IsBool(result));
        try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(self.engine.context, result));
    }
    pub fn takeCaught(self: *Fixture) !c.JSValue {
        if (c.JS_HasException(self.engine.context))
            return error.ConcreteOwnerPendingWasNotCaptured;
        const reason = self.engine.captured_exception orelse
            return error.ConcreteOwnerCaughtReasonRequired;
        self.engine.captured_exception = null;
        return reason;
    }
    pub fn evaluate(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "concrete-filehandle-control.js", c.JS_EVAL_TYPE_GLOBAL);
        self.engine.freeValue(result);
    }
    pub fn global(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        return a.expression(self.engine, struct {
            fn body(s: *a.Scope, key: [*:0]const u8) !c.JSValue {
                const object = try s.checked(c.JS_GetGlobalObject(s.engine.context));
                return a.duplicate(s.engine, try s.get(object, key));
            }
        }.body, .{name});
    }
    pub fn expose(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const result = try a.expression(self.engine, struct {
            fn body(s: *a.Scope, key: [*:0]const u8, value_to_set: c.JSValue) !c.JSValue {
                const object = try s.checked(c.JS_GetGlobalObject(s.engine.context));
                try s.put(object, key, value_to_set);
                return c.pi_js_undefined();
            }
        }.body, .{ name, value });
        self.engine.freeValue(result);
    }
    pub fn installThrowingBeforeHook(self: *Fixture) !void {
        try self.evaluate(
            "globalThis.ownerHookReason=new RangeError('Maximum call stack size exceeded');" ++
            "globalThis.ownerBeforeIds=[];globalThis.ownerAfterIds=[];" ++
            "globalThis.ownerBeforeHook=function(id){ownerBeforeIds.push(id);throw ownerHookReason;};" ++
            "globalThis.ownerAfterHook=function(id){ownerAfterIds.push(id);};" ++
            "globalThis.ownerUnselectedHook=function(){throw Error('unselected async hook');};");
        self.selected_hook_reason = try self.global("ownerHookReason");
        const before = try self.global("ownerBeforeHook");
        defer self.engine.freeValue(before);
        const after = try self.global("ownerAfterHook");
        defer self.engine.freeValue(after);
        const other = try self.global("ownerUnselectedHook");
        defer self.engine.freeValue(other);
        try self.env().installHooks(.{ .init = other, .before = before, .after = after,
            .destroy = other, .promise_resolve = other }, self.binding_target.?);
        self.env().field(.before).* = 1;
        self.env().field(.after).* = 1;
    }
    pub fn installFsRead(self: *Fixture) !void {
        const result = try a.expression(self.engine, struct {
            fn body(s: *a.Scope, f: *Fixture) !c.JSValue {
                const data = binding.get(f.registry()) orelse
                    return error.ConcreteFSBeforeHookBindingDataRequired;
                const factory = try s.own(try fs_promise.acquire(s.engine, data));
                const generation = try s.beforeAllocation();
                const marker = try s.checkedAllocation(c.JS_NewSymbol(
                    s.engine.context, "fs_use_promises", false), generation);
                const function = try s.own(try fs_read.create(s.engine, .{
                    .controller = f.controller.?, .use_promises = marker,
                    .request_factory = factory,
                }));
                const global_object = try s.checked(c.JS_GetGlobalObject(s.engine.context));
                try s.define(global_object, "actualOwnerFsRead", function, c.JS_PROP_C_W_E);
                try s.define(global_object, "actualOwnerUsePromises", marker, c.JS_PROP_C_W_E);
                return c.pi_js_undefined();
            }
        }.body, .{self});
        self.engine.freeValue(result);
    }
    pub fn installInitRecorder(self: *Fixture) !void {
        try self.evaluate(
            "globalThis.ownerInitEvents=[];globalThis.ownerCloseResources=[];" ++
            "globalThis.ownerInitHook=function(id,type,trigger,resource){" ++
            "ownerInitEvents.push([type,id,trigger]);" ++
            "if(type==='FILEHANDLECLOSEREQ')ownerCloseResources.push(resource);};" ++
            "globalThis.ownerUnselectedHook=function(){throw Error('unselected async hook');};");
        const init = try self.global("ownerInitHook");
        defer self.engine.freeValue(init);
        const other = try self.global("ownerUnselectedHook");
        defer self.engine.freeValue(other);
        try self.env().installHooks(.{ .init = init, .before = other, .after = other,
            .destroy = other, .promise_resolve = other }, self.binding_target.?);
        self.env().field(.init).* = 1;
    }
    pub fn stopIo(self: *Fixture) void {
        if (self.io_stopped) return;
        self.io_stopped = true;
        if (self.primary_wrapper) |wrapper| {
            if (self.registry_owner) |registry| if (registry.unwrap(wrapper)) |state| {
                const handle_value: *Handle = @alignCast(@fieldParentPtr("wrap", state));
                _ = handle_value.readStop();
            };
        }
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
            self.outer.deinit() catch @panic("concrete FileHandle outer scope teardown failed");
        }
        if (self.environment) |environment|
            environment.cleanupRealmAfterIoJoin() catch @panic("concrete FileHandle realm cleanup failed");
        if (self.queue) |queue| {
            queue.close(self.engine) catch @panic("concrete FileHandle native queue cleanup failed");
            self.queue = null;
            queue.release();
        }
        if (self.environment) |environment|
            environment.disarm() catch @panic("concrete FileHandle Environment disarm failed");
        self.registry_owner = null;
        if (self.engine_alive) {
            for (self.caught[0..self.caught_count]) |value| self.engine.freeValue(value);
            self.caught_count = 0;
            self.drop(&self.primary_wrapper);
            self.drop(&self.selected_hook_reason);
            self.drop(&self.binding_target);
            self.drop(&self.prototype);
            self.drop(&self.handle_key);
            self.drop(&self.template_owner);
            self.engine.host_control_context = null;
        }
        if (self.environment) |environment| {
            self.environment = null;
            environment.release();
        }
        if (self.engine_alive) { self.engine_alive = false; self.engine.deinit(); }
        if (self.native_environment_alive) {
            self.native_environment_alive = false;
            self.native_environment.deinit();
        }
    }
};

pub const File = struct {
    temporary: std.testing.TmpDir = undefined,
    temporary_ready: bool = false,
    path: ?[:0]u8 = null,
    descriptor: c_int = -1,

    pub fn init(self: *File) !void {
        self.* = .{};
        errdefer self.deinit();
        self.temporary = std.testing.tmpDir(.{});
        self.temporary_ready = true;
        try self.temporary.dir.writeFile(std.testing.io,
            .{ .sub_path = "owner.bin", .data = "ABCDEFGH" });
        const directory = try self.temporary.dir.realPathFileAlloc(
            std.testing.io, ".", std.testing.allocator);
        defer std.testing.allocator.free(directory);
        const joined = try std.fs.path.join(std.testing.allocator, &.{ directory, "owner.bin" });
        defer std.testing.allocator.free(joined);
        self.path = try std.testing.allocator.dupeZ(u8, joined);
        var request: physical.uv_fs_t = undefined;
        const status = physical.uv_fs_open(null, &request, self.path.?.ptr,
            physical.O_RDONLY, 0, null);
        physical.uv_fs_req_cleanup(&request);
        if (status < 0) return error.ConcreteFileHandlePhysicalOpenFailed;
        self.descriptor = status;
    }
    pub fn take(self: *File) c_int {
        std.debug.assert(self.descriptor >= 0);
        const descriptor = self.descriptor;
        self.descriptor = -1;
        return descriptor;
    }
    pub fn status(descriptor: c_int) c_int {
        var request: physical.uv_fs_t = undefined;
        const result = physical.uv_fs_fstat(null, &request, descriptor, null);
        physical.uv_fs_req_cleanup(&request);
        return result;
    }
    pub fn close(self: *File) !void {
        if (self.descriptor < 0) return;
        var request: physical.uv_fs_t = undefined;
        const result = physical.uv_fs_close(null, &request, self.descriptor, null);
        physical.uv_fs_req_cleanup(&request);
        if (result != 0) return error.ConcreteFileHandlePhysicalCloseFailed;
        self.descriptor = -1;
    }
    pub fn deinit(self: *File) void {
        self.close() catch @panic("concrete FileHandle fixture descriptor close failed");
        if (self.path) |path| { self.path = null; std.testing.allocator.free(path); }
        if (self.temporary_ready) { self.temporary_ready = false; self.temporary.cleanup(); }
    }
};
