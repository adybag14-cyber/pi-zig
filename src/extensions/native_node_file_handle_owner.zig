// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Concrete native node::fs::FileHandle for the reviewed StreamBase/read graph.
//! It owns the SAME AsyncWrap, StreamBase, flags, current_read_ and BindingData
//! used by ReadStart, explicit close, release and the GC destructor.
//!
//! This source unit implements the present-object native constructor and its
//! original callback checks. Publishing the complete FileHandle template still
//! requires the original StreamBase::AddMethods owner; newInstance(.filehandle)
//! deliberately retains that explicit dependency until that owner is supplied.
//! Native trace/backing-allocation and immediate-queue bootstrap inputs must be
//! the real embedding owners, never test implementations in production.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const native = @import("native_node_async_wrap_state.zig");
const templates = @import("native_node_async_wrap.zig");
const binding = @import("native_node_fs_binding_data.zig");
const stream_base = @import("native_node_stream_base.zig");
const read = @import("native_node_file_handle_read.zig");
const close_request = @import("native_node_file_handle_close_request.zig");
const gc_close = @import("native_node_file_handle_gc_close.zig");
const stream_requests = @import("native_node_stream_request.zig");
const shutdown_request = @import("native_node_file_handle_shutdown.zig");
const immediates = @import("native_node_native_immediates.zig");
const io = @import("native_node_fs_request_io.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const Scope = a.Scope;
const uv = @import("native_node_managed_buffers.zig").uv;

pub const Inputs = struct {
    controller: *io.Controller,
    immediate_queue: *immediates.Queue,
    handle_string: c.JSValue,
    read_trace: read.Trace,
    close_trace: close_request.Trace,
    stream: stream_base.Operations,
};

pub const Handle = struct {
    pub const Reader = read.Type(@This());
    pub const CloseReq = close_request.Type(@This());
    pub const ShutdownReq = shutdown_request.Type(@This());

    // Original bases and native members. The single Reader.State supplies all
    // fd/closed/closing/reading/offset/length/current_read_ members.
    wrap: native.State = undefined,
    stream: stream_base.Base = undefined,
    read_state: Reader.State = .{ .fd = -1 },
    binding_data: ?*binding.BindingData = null,

    // Actual retained native infrastructure, not another handle/request graph.
    controller: *io.Controller,
    immediate_queue: *immediates.Queue,
    handle_string: c.JSValue,
    read_trace: read.Trace,
    close_trace: close_request.Trace,
    stream_operations: stream_base.Operations,
    attached: bool = false,
    stream_initialized: bool = false,
    constructed: bool = false,

    fn fromWrap(wrap: *native.State) *Handle {
        return @alignCast(@fieldParentPtr("wrap", wrap));
    }
    fn streamWrap(base: *stream_base.Base) ?*native.State {
        const self: *Handle = @alignCast(@fieldParentPtr("stream", base));
        return &self.wrap;
    }
    fn streamIsAlive(base: *stream_base.Base) bool {
        const self: *Handle = @fieldParentPtr("stream", base);
        return self.isAlive();
    }
    fn streamGetFD(base: *stream_base.Base) c_int {
        const self: *Handle = @fieldParentPtr("stream", base);
        return self.getFD();
    }
    fn streamReadStart(base: *stream_base.Base, s: *Scope) anyerror!c_int {
        const self: *Handle = @fieldParentPtr("stream", base);
        return self.readStart(s);
    }
    fn streamReadStop(base: *stream_base.Base) c_int {
        const self: *Handle = @fieldParentPtr("stream", base);
        return self.readStop();
    }
    fn createShutdown(base: *stream_base.Base, s: *Scope,
        wrapper: c.JSValue) anyerror!?*stream_requests.Shutdown
    {
        const self: *Handle = @fieldParentPtr("stream", base);
        return &((try ShutdownReq.create(s, self, wrapper)).shutdown);
    }
    fn doShutdown(base: *stream_base.Base, s: *Scope,
        request: ?*stream_requests.Shutdown) anyerror!c_int
    {
        const self: *Handle = @fieldParentPtr("stream", base);
        return ShutdownReq.dispatch(s, self, request orelse
            return error.ActualFileHandleShutdownRequestRequired);
    }
    /// Exact node_file.cc:287-292. This is the original unsupported write
    /// virtual, not a missing implementation converted to success.
    fn doWrite(_: *stream_base.Base, _: *Scope, _: *stream_requests.Write,
        _: []uv.uv_buf_t, _: ?*uv.uv_stream_t) anyerror!c_int
    {
        return uv.UV_ENOSYS;
    }
    pub fn shutdown(self: *Handle, s: *Scope, wrapper: ?c.JSValue) anyerror!c_int {
        return self.stream.shutdownRequest(s, wrapper);
    }
    pub fn fromObject(registry: *native.Registry, wrapper: c.JSValue) !*Handle {
        if (c.JS_GetClassID(wrapper) != registry.classId(.filehandle))
            return registry.check(.invalid_wrap_brand);
        const wrap = registry.unwrap(wrapper) orelse return registry.check(.invalid_wrap_brand);
        if (wrap.provider != native.Provider.filehandle)
            return registry.check(.invalid_wrap_brand);
        return fromWrap(wrap);
    }
    pub fn getAsyncWrap(self: *Handle) *native.State { return &self.wrap; }
    pub fn getStreamBase(self: *Handle) *stream_base.Base { return &self.stream; }
    pub fn getReadState(self: *Handle) *Reader.State { return &self.read_state; }
    pub fn getBindingData(self: *Handle) *binding.BindingData { return self.binding_data.?; }
    pub fn getReadInputs(self: *Handle) read.Inputs {
        return .{ .controller = self.controller, .handle_string = self.handle_string,
            .trace = self.read_trace };
    }
    pub fn getCloseTrace(self: *Handle) close_request.Trace { return self.close_trace; }
    pub fn getImmediateQueue(self: *Handle) *immediates.Queue { return self.immediate_queue; }
    pub fn getFD(self: *const Handle) c_int { return self.read_state.fd; }
    pub fn isAlive(self: *const Handle) bool { return !self.read_state.closed; }
    pub fn isClosing(self: *const Handle) bool { return self.read_state.closing; }
    pub fn readStart(self: *Handle, s: *Scope) !c_int { return Reader.start(s, self); }
    pub fn readStop(self: *Handle) c_int { return Reader.stop(self); }
    pub fn afterClose(self: *Handle) !void { return Reader.afterClose(self); }

    fn mark(_: ?*c.JSRuntime, _: *native.State, _: ?*const c.JS_MarkFunc) void {
        // BindingData/current_read are native BaseObjectPtrs with independent
        // strong persistents. handle_string is an actual cached native root.
        // The Promise and onread edges belong to the wrapper's internal slots,
        // whose own class mark callback survives native Handle destruction.
    }
    fn retire(wrap: *native.State, s: *Scope) !void {
        const self = fromWrap(wrap);
        var failure: ?anyerror = null;
        if (self.constructed) {
            if (self.read_state.closing) check.assertion(s.engine, .{
                .file_line = "src/node_file.cc:282", .message = "!closing_",
                .function = "node::fs::FileHandle::~FileHandle",
            });
            gc_close.close(s, self) catch |err| {
                record(s, err);
                failure = err;
            };
            if (!self.read_state.closed) check.assertion(s.engine, .{
                .file_line = "src/node_file.cc:284", .message = "closed_",
                .function = "node::fs::FileHandle::~FileHandle",
            });
        }
        // Original member destruction reverses their declaration order:
        // binding_data_ is last, then current_read_, then StreamBase.
        if (self.binding_data) |data| {
            self.binding_data = null;
            data.releaseNative() catch |err| {
                record(s, err);
                if (failure == null) failure = err;
            };
        }
        if (self.read_state.current_read) |request| {
            self.read_state.current_read = null;
            request.release() catch |err| {
                record(s, err);
                if (failure == null) failure = err;
            };
        }
        if (self.stream_initialized) {
            self.stream_initialized = false;
            self.stream.deinit();
        }
        self.releaseInfrastructure(s);
        // State.retire now destroys AsyncWrap and its context/registry edges.
        if (failure) |err| return err;
    }
    fn releaseInfrastructure(self: *Handle, s: *Scope) void {
        s.boundary.release(&self.handle_string);
        self.immediate_queue.release();
        self.controller.release();
    }
    fn destroy(wrap: *native.State) void {
        wrap.registry.environment.allocator().destroy(fromWrap(wrap));
    }
    const derived: native.Derived = .{
        .mark = mark, .retire = retire, .destroy = destroy,
    };

    fn initialize(self: *Handle, s: *Scope, data: *binding.BindingData,
        wrapper: c.JSValue, descriptor: c_int) !void
    {
        self.wrap.initialize(data.registry, wrapper, derived,
            native.Provider.filehandle, -1) catch |err|
        {
            self.attached = data.registry.unwrap(wrapper) == &self.wrap;
            record(s, err);
            // Native AsyncWrap calls void AsyncReset: a completed ordinary
            // init rethrow does not skip StreamBase or derived construction.
            if (!self.attached or !self.wrap.init_hook_ran or
                !canContinue(s, err)) return err;
        };
        self.attached = true;
        try self.stream.init(data.environment,
            .{ .get_async_wrap = streamWrap,
                .is_alive = streamIsAlive, .get_fd = streamGetFD,
                .read_start = streamReadStart, .read_stop = streamReadStop,
                .create_shutdown = createShutdown, .do_shutdown = doShutdown,
                .do_write = doWrite },
            self.stream_operations);
        self.stream_initialized = true;
        self.read_state.fd = descriptor;
        try data.retainNative();
        self.binding_data = data;
        try self.wrap.makeWeak();
        try self.stream.attachToObject(data.registry, wrapper);
        self.constructed = true;
    }

    /// FileHandle::New(BindingData*, fd, optional object, optional offset/length).
    /// A present object is the real template receiver retained by the caller's
    /// HandleScope. The absent-object path uses the genuine stored template;
    /// it cannot substitute a plain object for an unimplemented template owner.
    pub fn create(s: *Scope, data: *binding.BindingData, descriptor: c_int,
        object: ?c.JSValue, offset: ?i64, length: ?i64, input: Inputs) !*Handle
    {
        if ((try data.environment.requireEngine()) != s.engine or
            input.controller.environment != data.environment or
            input.immediate_queue.engine != s.engine or
            binding.get(data.registry) != data)
            return error.ActualFileHandleEnvironmentMismatch;
        if (!c.JS_IsString(input.handle_string))
            return error.ActualFileHandleCachedHandleStringRequired;
        try input.controller.beginCall(s.engine);
        defer input.controller.endCall();
        const wrapper = if (object) |provided| provided else
            try s.own(try templates.newInstance(s.engine, data.template_owner, .filehandle));
        if (c.JS_GetClassID(wrapper) != data.registry.classId(.filehandle))
            return data.registry.check(.invalid_wrap_brand);
        try s.pending();
        const self = try data.environment.allocator().create(Handle);
        self.* = .{
            .controller = input.controller.retain(),
            .immediate_queue = input.immediate_queue.retain(),
            .handle_string = a.duplicate(s.engine, input.handle_string),
            .read_trace = input.read_trace, .close_trace = input.close_trace,
            .stream_operations = input.stream,
        };
        self.initialize(s, data, wrapper, descriptor) catch |err| {
            var completion = a.owned.Completion.initVoid(s.engine, err);
            if (self.attached) {
                self.wrap.retire(false) catch {};
            } else {
                var cleanup = Scope.init(s.engine);
                self.releaseInfrastructure(&cleanup);
                const ignored = cleanup.finish(c.pi_js_undefined()) catch c.pi_js_undefined();
                completion.release(ignored);
                data.environment.allocator().destroy(self);
            }
            try completion.finishVoid();
            unreachable;
        };
        // These writes follow the complete native constructor in Source.
        if (offset) |value| self.read_state.read_offset = value;
        if (length) |value| self.read_state.read_length = value;
        return self;
    }

    /// FileHandle::New callback after actual template receiver allocation.
    /// No guest coercion is performed by IsInt32/IsNumber/NumberToInt64.
    pub fn construct(s: *Scope, registry: *native.Registry, wrapper: c.JSValue,
        args: []const c.JSValue, constructing: bool, input: Inputs) !void
    {
        if (!constructing) check.assertion(s.engine, .{
            .file_line = "src/node_file.cc:252", .message = "args.IsConstructCall()",
            .function = "node::fs::FileHandle::New",
        });
        const descriptor = try int32(s, a.arg(args, 0));
        const data = binding.get(registry) orelse
            return error.ActualFileHandleRealmBindingDataRequired;
        const offset = try optionalInteger(s, a.arg(args, 1));
        const length = try optionalInteger(s, a.arg(args, 2));
        _ = try create(s, data, descriptor, wrapper, offset, length, input);
    }

    /// Same native FileHandle, same internal closing Promise. This Escapable
    /// HandleScope owns its locals and the escaped result through cleanup.
    pub fn closePromise(self: *Handle) !c.JSValue {
        const engine = try self.wrap.registry.environment.requireEngine();
        try self.controller.beginCall(engine);
        defer self.controller.endCall();
        return a.expression(engine, closeBody, .{self});
    }
    fn closeBody(s: *Scope, self: *Handle) !c.JSValue {
        const registry = self.wrap.registry;
        const wrapper = try s.own(a.duplicate(s.engine, self.wrap.object() orelse
            return error.ActualFileHandleWrapperRequired));
        const previous = try registry.fileHandleClosingPromise(s, wrapper);
        if (c.JS_IsPromise(previous)) return a.duplicate(s.engine, previous);

        if (self.read_state.closed) check.assertion(s.engine, .{
            .file_line = "src/node_file.cc:459", .message = "!closed_",
            .function = "node::fs::FileHandle::ClosePromise",
        });
        if (self.read_state.closing) check.assertion(s.engine, .{
            .file_line = "src/node_file.cc:460", .message = "!closing_",
            .function = "node::fs::FileHandle::ClosePromise",
        });
        if (self.read_state.reading) check.assertion(s.engine, .{
            .file_line = "src/node_file.cc:461", .message = "!reading_",
            .function = "node::fs::FileHandle::ClosePromise",
        });
        try s.pending();
        const raw_promise = c.JS_PiNewPendingPromise(s.engine.context);
        if (c.JS_IsException(raw_promise)) check.assertion(s.engine, .{
            .file_line = "src/node_file.cc:464",
            .message = "!maybe_resolver.IsEmpty()",
            .function = "node::fs::FileHandle::ClosePromise",
        });
        const promise = try s.checked(raw_promise);
        const close_wrapper = try s.own(try templates.newInstance(
            s.engine, self.getBindingData().template_owner, .filehandleclosereq));
        self.read_state.closing = true;
        try registry.setFileHandleClosingPromise(s, wrapper, promise);
        const request = try CloseReq.create(s, self, close_wrapper, promise, wrapper);
        if (self.read_state.fd == -1) check.assertion(s.engine, .{
            .file_line = "src/node_file.cc:495", .message = "(fd_) != (-1)",
            .function = "node::fs::FileHandle::ClosePromise",
        });
        self.close_trace.begin_async(self.close_trace.raw, request);
        const result = try self.controller.dispatchRawClose(s, &request.entry,
            request.actual.?, self.read_state.fd, CloseReq.completed);
        if (result < 0) try request.rejectImmediateAndDelete(s, result);
        return a.duplicate(s.engine, promise);
    }

    /// FileHandle::Release uses AfterClose but performs no close syscall.
    /// Descriptor zero is a valid transferred result.
    pub fn releaseDescriptor(self: *Handle, s: *Scope) !c_int {
        const descriptor = self.getFD();
        self.afterClose() catch |err| {
            record(s, err);
            if (!canContinue(s, err)) return err;
        };
        return descriptor;
    }
};

fn int32(s: *Scope, value: c.JSValue) !i32 {
    if (!c.JS_IsNumber(value)) invalidDescriptor(s);
    const number = try numberValue(s, value);
    const negative_zero = number == 0 and (@as(u64, @bitCast(number)) >> 63) != 0;
    if (!std.math.isFinite(number) or @trunc(number) != number or
        number < std.math.minInt(i32) or number > std.math.maxInt(i32) or negative_zero)
        invalidDescriptor(s);
    return @intFromFloat(number);
}
fn invalidDescriptor(s: *Scope) noreturn {
    check.assertion(s.engine, .{
        .file_line = "src/node_file.cc:253", .message = "args[0]->IsInt32()",
        .function = "node::fs::FileHandle::New",
    });
}
fn numberValue(s: *Scope, value: c.JSValue) !f64 {
    var result: f64 = 0;
    try s.pending();
    const status = c.JS_ToFloat64(s.engine.context, &result, value);
    try s.pending();
    if (status < 0) return error.ActualFileHandlePrimitiveNumberRequired;
    return result;
}
fn optionalInteger(s: *Scope, value: c.JSValue) !?i64 {
    if (!c.JS_IsNumber(value)) return null;
    const number = try numberValue(s, value);
    // V8 Value::IntegerValue takes NumberToInt64 directly for Number values.
    // NaN maps to zero; the endpoint casts saturate, then finite values truncate.
    // QuickJS JS_ToInt64 is modulo 2^64 and is not this source operation.
    if (std.math.isNan(number)) return 0;
    if (number >= 0x1p63) return std.math.maxInt(i64);
    if (number <= -0x1p63) return std.math.minInt(i64);
    return @intFromFloat(@trunc(number));
}
fn canContinue(s: *Scope, err: anyerror) bool {
    return err == error.JavaScriptException and !s.boundary.isFatal();
}
fn record(s: *Scope, err: anyerror) void {
    s.boundary.escaping();
    if (err == error.OutOfMemory and !s.boundary.isFatal()) {
        _ = s.engine.throwNativeOutOfMemoryFatal();
        s.boundary.escaping();
    }
}
