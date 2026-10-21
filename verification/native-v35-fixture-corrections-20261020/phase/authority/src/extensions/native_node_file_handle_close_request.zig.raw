// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node v24.13 FileHandle::CloseReq. This is the actual ReqWrap owner:
//! one physical CLOSE request, the Environment's intrusive queue, and native
//! Global cells for the original Promise and FileHandle wrapper. Neither
//! persistent is an internal wrapper graph edge or a guest property.
const a = @import("native_node_argument_values.zig");
const native = @import("native_node_async_wrap_state.zig");
const callbacks = @import("native_node_callback_scope.zig");
const requests = @import("native_node_request_state.zig");
const globals = @import("native_node_weak_global.zig");
const io = @import("native_node_fs_request_io.zig");
const uv_exception = @import("native_node_uv_exception.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const uv = io.uv;
const Scope = a.Scope;

/// Original native trace operations. Their concrete category/controller and
/// clock ownership belong to the embedding and must outlive the real handle.
pub const Trace = struct {
    raw: ?*anyopaque,
    begin_sync: *const fn (?*anyopaque) void,
    end_sync: *const fn (?*anyopaque) void,
    begin_async: *const fn (?*anyopaque, *anyopaque) void,
    end_async: *const fn (?*anyopaque, *anyopaque, c_int) void,
};

pub fn Type(comptime Handle: type) type {
    return struct {
        const CloseReq = @This();

        wrap: native.State = undefined,
        entry: requests.Entry = undefined,
        // Original derived members, assigned in promise_.Reset/ref_.Reset order.
        promise: ?globals.Global = null,
        reference: ?globals.Global = null,
        actual: ?*uv.PiUvFsRequest = null,
        trace: Trace,
        diagnostics: ?*const check.Diagnostics,
        attached: bool = false,
        entry_initialized: bool = false,
        constructed: bool = false,

        pub fn fromEntry(entry: *requests.Entry) *CloseReq {
            return @alignCast(@fieldParentPtr("entry", entry));
        }
        fn fromWrap(wrap: *native.State) *CloseReq {
            return @alignCast(@fieldParentPtr("wrap", wrap));
        }
        fn mark(_: ?*c.JSRuntime, _: *native.State, _: ?*const c.JS_MarkFunc) void {
            // These are independent native Globals. Marking them as wrapper
            // edges would change the original native persistent cycle.
        }
        fn retire(wrap: *native.State, s: *Scope) !void {
            const self = fromWrap(wrap);
            if (self.constructed) {
                // Destructor body precedes the Global member destructors and
                // ReqWrapBase's actual queue-node destruction.
                uv.pi_uv_fs_request_cleanup(self.actual.?);
                resetGlobal(s, &self.promise);
                resetGlobal(s, &self.reference);
            } else {
                // A failed constructor has no derived destructor body.
                // Already-created members still unwind in reverse order.
                resetGlobal(s, &self.reference);
                resetGlobal(s, &self.promise);
            }
            if (self.entry_initialized) {
                self.entry_initialized = false;
                self.entry.deinit();
            }
        }
        fn destroy(wrap: *native.State) void {
            const allocator = wrap.registry.environment.allocator();
            const self = fromWrap(wrap);
            if (self.actual) |actual| {
                self.actual = null;
                // The dequeued event can independently retain these bytes
                // after the actual native ReqWrap has been destroyed.
                uv.pi_uv_fs_request_release(actual);
            }
            allocator.destroy(self);
        }
        fn resetGlobal(s: *Scope, slot: *?globals.Global) void {
            if (slot.*) |value| {
                slot.* = null;
                var previous = value;
                previous.release(s);
            }
        }
        fn cancel(entry: *requests.Entry) void {
            const self = fromEntry(entry);
            if (self.actual) |actual| _ = uv.pi_uv_fs_cancel(actual);
        }
        const derived: native.Derived = .{
            .mark = mark, .retire = retire, .destroy = destroy,
        };

        fn initialize(self: *CloseReq, s: *Scope, registry: *native.Registry,
            wrapper: c.JSValue, promise: c.JSValue, reference: c.JSValue) !void
        {
            self.wrap.initialize(registry, wrapper, derived,
                native.Provider.filehandleclosereq, -1) catch |err|
            {
                self.attached = registry.unwrap(wrapper) == &self.wrap;
                record(s, err);
                // ReqWrap construction follows the completed void AsyncReset,
                // including an ordinary init-hook rethrow.
                if (!self.attached or !self.wrap.init_hook_ran or
                    !canContinue(s, err)) return err;
            };
            self.attached = true;
            try self.entry.initialize(&self.wrap, cancel);
            self.entry_initialized = true;
            try self.wrap.makeWeak();
            self.entry.reset();
            if (uv.pi_uv_fs_request_reset(self.actual.?) != 0)
                return error.ActualFileHandleCloseInitialResetRequired;
            self.promise = try globals.Global.create(s, promise);
            self.reference = try globals.Global.create(s, reference);
            self.constructed = true;
        }

        /// The actual caller supplies fdclose_constructor_template's new
        /// instance and the original Promise/ref locals. This returns the
        /// original raw new CloseReq pointer, without an extra BaseObjectPtr.
        pub fn create(s: *Scope, handle: *Handle, wrapper: c.JSValue,
            promise: c.JSValue, reference: c.JSValue) !*CloseReq
        {
            const registry = handle.getAsyncWrap().registry;
            const inputs = handle.getReadInputs();
            if ((try registry.environment.requireEngine()) != s.engine or
                inputs.controller.environment != registry.environment or
                c.JS_GetClassID(wrapper) != registry.classId(.filehandleclosereq))
                return error.ActualFileHandleCloseEnvironmentMismatch;
            try inputs.controller.beginCall(s.engine);
            defer inputs.controller.endCall();
            try s.pending();
            const self = try registry.environment.allocator().create(CloseReq);
            self.* = .{
                .trace = handle.getCloseTrace(),
                .diagnostics = handle.getStreamBase().operations.heap_diagnostics,
            };
            const result = uv.pi_uv_fs_request_create(inputs.controller.service,
                uv.PI_UV_FS_CLOSE, 0, &self.actual);
            if (result.allocation_failed != 0 or result.status < 0 or self.actual == null) {
                const failure: anyerror = if (result.allocation_failed != 0)
                    error.OutOfMemory else error.ActualFileHandleCloseStorageRequired;
                return failConstruction(s, self, registry, failure);
            }
            self.initialize(s, registry, wrapper, promise, reference) catch |err|
                return failConstruction(s, self, registry, err);
            return self;
        }
        fn failConstruction(s: *Scope, self: *CloseReq,
            registry: *native.Registry, err: anyerror) !*CloseReq
        {
            var completion = a.owned.Completion.initVoid(s.engine, err);
            if (self.attached) {
                self.wrap.retire(false) catch {};
            } else {
                if (self.actual) |actual| uv.pi_uv_fs_request_release(actual);
                registry.environment.allocator().destroy(self);
            }
            try completion.finishVoid();
            unreachable;
        }

        pub fn fileHandle(self: *CloseReq) !*Handle {
            const engine = try self.wrap.registry.environment.requireEngine();
            var locals = Scope.init(engine);
            var selected: ?*Handle = null;
            const ignored = try locals.finish(self.fileHandleBody(&locals, &selected));
            engine.freeValue(ignored);
            return selected orelse return error.ActualFileHandleCloseReferenceRequired;
        }
        fn fileHandleBody(self: *CloseReq, s: *Scope, selected: *?*Handle) !c.JSValue {
            const value = if (self.reference) |*reference|
                try reference.get(s) else return error.ActualFileHandleCloseReferenceRequired;
            selected.* = try Handle.fromObject(self.wrap.registry, value);
            return c.pi_js_undefined();
        }
        pub fn resolve(self: *CloseReq) !void {
            return self.settle(c.pi_js_undefined(), false);
        }
        pub fn reject(self: *CloseReq, reason: c.JSValue) !void {
            return self.settle(reason, true);
        }
        fn settle(self: *CloseReq, value: c.JSValue, is_reject: bool) !void {
            const engine = try self.wrap.registry.environment.requireEngine();
            var handles = Scope.init(engine);
            var callback_scope: callbacks.Scope = undefined;
            callback_scope.initialized = false;
            var failure: ?anyerror = null;
            self.settleBody(&handles, &callback_scope, value, is_reject) catch |err| {
                record(&handles, err);
                failure = err;
            };
            // InternalCallbackScope is destroyed before the enclosing
            // HandleScope, including any failed ordinary completion.
            if (callback_scope.initialized) callback_scope.deinit() catch |err| {
                record(&handles, err);
                if (failure == null) failure = err;
            };
            const ignored = try handles.finish(if (failure) |err|
                @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
            engine.freeValue(ignored);
        }
        fn settleBody(self: *CloseReq, s: *Scope,
            callback_scope: *callbacks.Scope, value: c.JSValue, is_reject: bool) !void
        {
            const wrapper = self.wrap.object() orelse
                return error.ActualFileHandleCloseWrapperRequired;
            callback_scope.init(self.wrap.registry.environment, wrapper,
                self.wrap.context(), .{}, self.wrap.context_frame) catch |err|
            {
                record(s, err);
                // InternalCallbackScope is a void native constructor. Once
                // IDs are pushed, an ordinary EmitBefore stack-overflow
                // rethrow does not skip the following Resolver call. Preserve
                // that real completion in this HandleScope while performing
                // the original settlement and unchanged Maybe<void>::Check.
                if (!callback_scope.initialized or !callback_scope.pushed_ids or
                    !canContinue(s, err)) return err;
            };
            const resolver = if (self.promise) |*promise|
                try promise.get(s) else return error.ActualFileHandleClosePromiseRequired;
            try s.pending();
            var result = c.JS_PiSettlePromise(s.engine.context, resolver, value, is_reject);
            // Original Maybe<void>::Check terminates on an empty Maybe.
            // A rejected Promise or an ordinary Error value is not emptiness.
            if (c.JS_IsException(result)) check.maybeCheck(s.engine, self.diagnostics);
            s.boundary.release(&result);
            try s.pending();
        }

        /// Runs only through the real Controller/ReqWrap callback wrapper.
        /// That wrapper already holds one native pointer and decremented the
        /// Environment's waiting count before entering this original callback.
        pub fn completed(entry: *requests.Entry, actual_raw: *anyopaque) !void {
            const self = fromEntry(entry);
            const actual: *uv.PiUvFsRequest = @ptrCast(@alignCast(actual_raw));
            const info = uv.pi_uv_fs_request_info(actual);
            self.trace.end_async(self.trace.raw, self, @truncate(info.result));
            const environment = self.wrap.registry.environment;
            const engine = try environment.requireEngine();
            var handles = Scope.init(engine);
            var failure: ?anyerror = null;
            // Source constructs its own BaseObjectPtr<CloseReq> in addition to
            // the callback wrapper's pointer. The actual object cannot die
            // until both original scopes have released their entitlement.
            self.wrap.retainNative() catch |err| {
                record(&handles, err);
                failure = err;
            };
            if (failure == null) self.completeBody(&handles, info.result) catch |err| {
                record(&handles, err);
                failure = err;
            };
            // retainNative increments before its possible Environment check,
            // so even that failure owns the one matching decrement.
            self.wrap.releaseNative() catch |err| {
                record(&handles, err);
                if (failure == null) failure = err;
            };
            const ignored = try handles.finish(if (failure) |err|
                @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
            engine.freeValue(ignored);
        }
        fn completeBody(self: *CloseReq, s: *Scope, result: i64) !void {
            // The pointer is non-null by construction, matching CHECK(close).
            const handle = try self.fileHandle();
            handle.afterClose() catch |err| {
                record(s, err);
                if (!canContinue(s, err)) return err;
            };
            if (!self.wrap.registry.environment.canCallIntoJs()) return;
            if (result < 0) {
                // This source HandleScope is inside the negative branch and
                // retires before the callback's local BaseObjectPtr.
                var locals = Scope.init(s.engine);
                var failure: ?anyerror = null;
                self.rejectResult(&locals, @truncate(result)) catch |err| {
                    record(&locals, err);
                    failure = err;
                };
                const ignored = try locals.finish(if (failure) |err|
                    @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
                s.engine.freeValue(ignored);
            } else {
                try self.resolve();
            }
        }
        fn rejectResult(self: *CloseReq, s: *Scope, result: c_int) !void {
            const reason = try s.own(try uv_exception.create(s.engine,
                .{ .code = result, .syscall = "close" }));
            try self.reject(reason);
        }

        /// Immediate negative admission uses the caller's EscapableHandleScope,
        /// Reject then delete req. It neither invokes AfterClose nor changes
        /// the handle's original closing flag or Promise internal slot.
        pub fn rejectImmediateAndDelete(self: *CloseReq, s: *Scope, result: c_int) !void {
            var failure: ?anyerror = null;
            self.rejectResult(s, result) catch |err| {
                record(s, err);
                failure = err;
            };
            self.wrap.retire(false) catch |err| {
                record(s, err);
                if (failure == null) failure = err;
            };
            if (failure) |err| return err;
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
    };
}
