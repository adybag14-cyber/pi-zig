// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! FileHandleCloseWrap = SimpleShutdownWrap<ReqWrap<uv_fs_t>>, and the actual
//! FileHandle CreateShutdownWrap / DoShutdown callback. No Promise, Global,
//! handle keepalive, replacement queue or synthesized close completion.
const a = @import("native_node_argument_values.zig");
const native = @import("native_node_async_wrap_state.zig");
const requests = @import("native_node_stream_request.zig");
const request_state = @import("native_node_request_state.zig");
const io = @import("native_node_fs_request_io.zig");
const close_request = @import("native_node_file_handle_close_request.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const uv = io.uv;

pub fn Type(comptime Handle: type) type {
    return struct {
        const Self = @This();

        shutdown: requests.Shutdown = .{},
        wrap: native.State = undefined,
        entry: request_state.Entry = undefined,
        actual: ?*uv.PiUvFsRequest = null,
        trace: close_request.Trace,
        request_attached: bool = false,
        state_attached: bool = false,
        entry_initialized: bool = false,

        pub fn fromEntry(entry: *request_state.Entry) *Self {
            return @fieldParentPtr("entry", entry);
        }
        pub fn fromShutdown(shutdown: *requests.Shutdown) *Self {
            return @fieldParentPtr("shutdown", shutdown);
        }
        fn getAsyncWrap(request: *requests.Request) *native.State {
            return &fromShutdown(requests.Shutdown.fromRequest(request)).wrap;
        }
        fn fromWrap(state: *native.State) *Self {
            return @fieldParentPtr("wrap", state);
        }
        fn mark(_: ?*c.JSRuntime, _: *native.State, _: ?*const c.JS_MarkFunc) void {
            // StreamReq::stream_ and the compiled trace inputs are borrowed.
        }
        fn retire(state: *native.State, _: *a.Scope) anyerror!void {
            const self = fromWrap(state);
            // The defaulted SimpleShutdownWrap destructor owns no handle or
            // uv cleanup. Its ReqWrapBase ListNode retires before AsyncWrap.
            if (self.entry_initialized) {
                self.entry_initialized = false;
                self.entry.deinit();
            }
        }
        fn destroy(state: *native.State) void {
            const allocator = state.registry.environment.allocator();
            const self = fromWrap(state);
            if (self.actual) |actual| {
                self.actual = null;
                uv.pi_uv_fs_request_release(actual);
            }
            allocator.destroy(self);
        }
        fn cancel(entry: *request_state.Entry) void {
            const self = fromEntry(entry);
            if (self.actual) |actual| _ = uv.pi_uv_fs_cancel(actual);
        }
        const derived: native.Derived = .{
            .mark = mark, .retire = retire, .destroy = destroy,
        };

        /// The caller supplies the genuine shutdown InstanceTemplate object.
        /// Its later BaseObjectPtr assignment is outside this full constructor.
        pub fn create(s: *a.Scope, handle: *Handle,
            wrapper: c.JSValue) anyerror!*Self
        {
            const registry = handle.getAsyncWrap().registry;
            const controller = handle.getReadInputs().controller;
            if (controller.environment != registry.environment or
                (try registry.environment.requireEngine()) != s.engine)
                return error.ActualFileHandleShutdownEnvironmentMismatch;
            try controller.beginCall(s.engine);
            defer controller.endCall();
            try s.pending();
            const self = try registry.environment.allocator().create(Self);
            self.* = .{ .trace = handle.getCloseTrace() };
            const result = uv.pi_uv_fs_request_create(controller.service,
                uv.PI_UV_FS_CLOSE, 0, &self.actual);
            if (result.allocation_failed != 0 or result.status < 0 or self.actual == null)
                return failConstruction(s, self, registry, wrapper,
                    if (result.allocation_failed != 0) error.OutOfMemory
                    else error.ActualFileHandleShutdownStorageRequired);
            initialize(self, s, handle, registry, wrapper) catch |err|
                return failConstruction(s, self, registry, wrapper, err);
            return self;
        }

        fn initialize(self: *Self, s: *a.Scope, handle: *Handle,
            registry: *native.Registry, wrapper: c.JSValue) anyerror!void
        {
            // Multiple-base construction: StreamReq slot first, then the real
            // AsyncWrap / ReqWrapBase / MakeWeak / Reset sequence.
            try self.shutdown.init(handle.getStreamBase(), registry, wrapper, getAsyncWrap);
            self.request_attached = true;
            self.wrap.initialize(registry, wrapper, derived,
                native.Provider.shutdownwrap, -1) catch |err|
            {
                self.state_attached = registry.unwrap(wrapper) == &self.wrap;
                requests.recordFailure(s, err);
                if (!self.state_attached or !self.wrap.init_hook_ran or
                    err != error.JavaScriptException or s.boundary.isFatal()) return err;
            };
            self.state_attached = true;
            try self.entry.initialize(&self.wrap, cancel);
            self.entry_initialized = true;
            try self.wrap.makeWeak();
            self.entry.reset();
            if (uv.pi_uv_fs_request_reset(self.actual.?) != 0)
                return error.ActualFileHandleShutdownInitialResetRequired;
        }

        fn failConstruction(s: *a.Scope, self: *Self,
            registry: *native.Registry, wrapper: c.JSValue,
            err: anyerror) anyerror!*Self
        {
            var completion = a.owned.Completion.initVoid(s.engine, err);
            if (self.request_attached) registry.clearRequestPointer(wrapper) catch {};
            if (self.state_attached) {
                self.wrap.retire(false) catch {};
            } else {
                if (self.actual) |actual| uv.pi_uv_fs_request_release(actual);
                registry.environment.allocator().destroy(self);
            }
            try completion.finishVoid();
            unreachable;
        }

        pub fn dispatch(s: *a.Scope, handle: *Handle,
            request: *requests.Shutdown) anyerror!c_int
        {
            const state = handle.getReadState();
            if (state.closing or state.closed) {
                request.request.done(0, null) catch |err| {
                    requests.recordFailure(s, err);
                    if (err != error.JavaScriptException or s.boundary.isFatal()) return err;
                };
                return 1;
            }
            const self = fromShutdown(request);
            state.closing = true;
            if (state.fd == -1) check.assertion(s.engine, .{
                .file_line = "src/node_file.cc:681",
                .message = "(fd_) != (-1)",
                .function = "node::fs::FileHandle::DoShutdown",
            });
            self.trace.begin_async(self.trace.raw, self);
            // Source deliberately ignores an immediate negative Dispatch. It
            // leaves closing_ and the real request alone, then returns zero.
            _ = try handle.getReadInputs().controller.dispatchRawClose(s,
                &self.entry, self.actual.?, state.fd, completed);
            return 0;
        }

        fn completed(entry: *request_state.Entry, actual_raw: *anyopaque) anyerror!void {
            const self = fromEntry(entry);
            const actual: *uv.PiUvFsRequest = @ptrCast(@alignCast(actual_raw));
            const trace_result: c_int = @truncate(uv.pi_uv_fs_request_info(actual).result);
            self.trace.end_async(self.trace.raw, self, trace_result);
            const handle: *Handle = @fieldParentPtr("stream", self.shutdown.request.stream);
            const environment = entry.wrap.registry.environment.retain();
            defer environment.release();
            const engine = try environment.requireEngine();
            var locals = a.Scope.init(engine);
            var failure: ?anyerror = null;
            var continue_done = true;
            handle.afterClose() catch |err| {
                requests.recordFailure(&locals, err);
                failure = err;
                continue_done = err == error.JavaScriptException and !locals.boundary.isFatal();
            };
            // Read req->result AFTER AfterClose, as Source does. Then clean the
            // actual uv_fs_t before Done; no FileHandle access follows it.
            const result: c_int = @truncate(uv.pi_uv_fs_request_info(actual).result);
            uv.pi_uv_fs_request_cleanup(actual);
            if (continue_done) {
                self.shutdown.request.done(result, null) catch |err| {
                    requests.recordFailure(&locals, err);
                    if (failure == null) failure = err;
                };
            } else {
                // A port terminal/aborted completion cannot enter more guest
                // code. Retire the native request while the outer real Wrapper
                // still owns it; this is not a synthesized native callback.
                self.shutdown.request.dispose() catch |err| {
                    requests.recordFailure(&locals, err);
                    if (failure == null) failure = err;
                };
            }
            // The Controller's actual Wrapper drops its pointer after return.
            const ignored = try locals.finish(if (failure) |err|
                @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
            engine.freeValue(ignored);
        }
    };
}
