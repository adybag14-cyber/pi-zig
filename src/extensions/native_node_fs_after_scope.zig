//! Actual Node24.13 FSReqAfterScope for the selected FSReqPromise requests.
//! The physical request supplies its real, idempotent native cleanup operation.
//! This scope owns a BaseObjectPtr and a genuine local HandleScope; it does not
//! allocate another Promise, retain another wrapper JS root, or change waiting.
const a = @import("native_node_argument_values.zig");
const requests = @import("native_node_fs_request_promise.zig");
const errors = @import("native_node_uv_exception.zig");
const c = a.c;
const Scope = a.Scope;

/// Private compiled-I/O operation corresponding to uv_fs_req_cleanup. The
/// stable raw owner and all syscall/path bytes remain live until it is called.
/// Its implementation is native only; no arbitrary guest callback is accepted.
pub const Cleanup = struct {
    raw: *anyopaque,
    run: *const fn (*anyopaque) void,
};

pub const AfterScope = struct {
    handles: Scope,
    request: ?*requests.Request = null,
    cleanup: Cleanup,
    initialized: bool = false,
    finished: bool = false,

    /// Caller storage is stable through finish. The original native strong
    /// pointer is initialized before HandleScope/Context::Scope construction.
    pub fn init(self: *AfterScope, request: *requests.Request, cleanup: Cleanup) !void {
        const engine = try request.environment().requireEngine();
        try request.wrap.retainNative();
        self.* = .{
            .handles = Scope.init(engine), .request = request,
            .cleanup = cleanup, .initialized = true,
        };
    }

    /// Destructor-body ordering: cleanup the real physical request, detach the
    /// native BaseObject, then reset this scope's native pointer. The original
    /// enclosing HandleScope still owns its Local values throughout this call.
    pub fn clear(self: *AfterScope) !void {
        const request = self.request orelse return;
        self.cleanup.run(self.cleanup.raw);
        try request.wrap.detach();
        self.request = null;
        // This may delete the native request when Dispatch failed and no
        // MakeLibuvRequestCallback pointer surrounds the original callback.
        try request.wrap.releaseNative();
    }

    /// This is the real Proceed predicate. An environment already stopping
    /// skips JS settlement; finish still performs the original native cleanup.
    pub fn proceed(self: *AfterScope, input: errors.Input) !bool {
        const request = self.request orelse return error.ActualFSAfterScopeRequestRequired;
        if (!request.environment().canCallIntoJs()) return false;
        if (input.code < 0) {
            try self.reject(input);
            return false;
        }
        return true;
    }

    /// Reject's local BaseObjectPtr survives Clear, then the actual request's
    /// Reject performs its own callback scope and live "promise" property Get.
    fn reject(self: *AfterScope, input: errors.Input) !void {
        const request = self.request orelse return error.ActualFSAfterScopeRequestRequired;
        try request.wrap.retainNative();
        var failure: ?anyerror = null;
        self.rejectBody(request, input) catch |err| {
            self.handles.boundary.escaping();
            failure = err;
        };
        request.wrap.releaseNative() catch |err| {
            self.handles.boundary.escaping();
            if (failure == null) failure = err;
        };
        if (failure) |err| return err;
    }
    fn rejectBody(self: *AfterScope, request: *requests.Request, input: errors.Input) !void {
        // UVException is created while the native request's original strings
        // still exist. Clear then runs before any live request promise lookup.
        const reason = try self.handles.own(try errors.create(self.handles.engine, input));
        try self.clear();
        try request.reject(reason);
    }

    /// A caller invokes finish on every initialized path, including ordinary
    /// callback failure and stopped-runtime completion. Preserve that failure
    /// before native pointer destruction can produce another pending reason.
    pub fn finish(self: *AfterScope, incoming: anyerror!void) !void {
        if (!self.initialized or self.finished) return incoming;
        self.finished = true;
        var failure: ?anyerror = null;
        if (incoming) |_| {} else |err| {
            self.handles.boundary.escaping();
            if (err == error.OutOfMemory and !self.handles.boundary.isFatal()) {
                _ = self.handles.engine.throwNativeOutOfMemoryFatal();
                self.handles.boundary.escaping();
            }
            failure = err;
        }
        self.clear() catch |err| {
            self.handles.boundary.escaping();
            if (failure == null) failure = err;
        };
        const result = try self.handles.finish(if (failure) |err|
            @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
        self.handles.engine.freeValue(result);
    }
};
