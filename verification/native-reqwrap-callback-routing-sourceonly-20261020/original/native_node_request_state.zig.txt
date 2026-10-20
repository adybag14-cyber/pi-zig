//! Actual Node24.13 ReqWrapBase intrusive queue and request_waiting_ state.
//! One Registry is embedded in the shared native callback Environment. Entries
//! are embedded in real derived requests; this owner allocates no replacement
//! request, resolver, callback, event loop, or per-FileHandle counter.
const std = @import("std");
const callbacks = @import("native_node_callback_scope.zig");
const wraps = @import("native_node_async_wrap_state.zig");
pub const Environment = callbacks.Environment;
pub const Cancel = *const fn (*Entry) void;

pub const Registry = struct {
    head: ?*Entry = null,
    tail: ?*Entry = null,
    // Original Environment field is int, not a count inferred from the queue.
    waiting: c_int = 0,

    fn append(self: *Registry, entry: *Entry) void {
        std.debug.assert(entry.queue == null);
        entry.previous = self.tail;
        entry.next = null;
        if (self.tail) |tail| tail.next = entry else self.head = entry;
        self.tail = entry;
        entry.queue = self;
    }
    fn remove(self: *Registry, entry: *Entry) void {
        if (entry.previous) |previous| previous.next = entry.next else self.head = entry.next;
        if (entry.next) |next| next.previous = entry.previous else self.tail = entry.previous;
        entry.previous = null;
        entry.next = null;
        entry.queue = null;
    }
    pub fn cancelAll(self: *Registry) void {
        var cursor = self.head;
        while (cursor) |entry| {
            // ReqWrap::Cancel is the actual native cancellation request; it
            // does not invoke a JS callback or remove the intrusive entry.
            cursor = entry.next;
            entry.cancel();
        }
    }
    pub fn requireNoWaiting(self: *const Registry, environment: *Environment) !void {
        _ = try environment.requireEngine();
        if (self.waiting != 0)
            return environment.operations.native_check_failure(environment, .waiting_requests_after_io_join);
    }
    pub fn requireEmpty(self: *const Registry, environment: *Environment) !void {
        try self.requireNoWaiting(environment);
        if (self.head != null or self.tail != null)
            return environment.operations.native_check_failure(environment, .request_queue_during_disarm);
    }
};

pub const Entry = struct {
    wrap: *wraps.State,
    cancel_native: Cancel,
    queue: ?*Registry = null,
    previous: ?*Entry = null,
    next: ?*Entry = null,
    dispatched: bool = false,
    counted: bool = false,

    /// ReqWrapBase construction follows AsyncWrap initialization and precedes
    /// MakeWeak/Reset and the derived FSReqBase member initialization.
    pub fn initialize(self: *Entry, wrap: *wraps.State, cancel_native: Cancel) !void {
        const environment = wrap.registry.environment;
        _ = try environment.requireEngine();
        if (!environment.has_run_bootstrapping_code)
            return environment.operations.native_check_failure(environment, .request_before_bootstrap);
        self.* = .{ .wrap = wrap, .cancel_native = cancel_native };
        environment.requests.append(self);
    }
    /// The real derived destructor removes ReqWrapBase's ListNode before the
    /// AsyncWrap base destructor. There is no independently owned queue root.
    pub fn deinit(self: *Entry) void {
        if (self.queue) |queue| queue.remove(self);
    }
    pub fn reset(self: *Entry) void {
        std.debug.assert(!self.counted);
        self.dispatched = false;
    }
    /// Source Dispatched() precedes the actual uv request initialization call.
    pub fn dispatchStarted(self: *Entry) void {
        self.dispatched = true;
    }
    /// Call only after successful real admission. A negative native Dispatch
    /// result neither strengthens the persistent nor increments this counter.
    pub fn dispatchAccepted(self: *Entry) !void {
        const environment = self.wrap.registry.environment;
        try self.wrap.clearWeak();
        environment.requests.waiting += 1;
        self.counted = true;
    }
    /// MakeLibuvRequestCallback::Wrapper owns a BaseObjectPtr, detaches, then
    /// decrements before entering the actual original completion callback.
    /// The caller must invoke endCallback after that callback and its scopes.
    pub fn beginCallback(self: *Entry) !void {
        const environment = self.wrap.registry.environment;
        try self.wrap.retainNative();
        try self.wrap.detach();
        environment.requests.waiting -= 1;
        self.counted = false;
        if (environment.requests.waiting < 0)
            return environment.operations.native_check_failure(environment, .negative_waiting_requests);
    }
    pub fn endCallback(self: *Entry) !void {
        // Last detached native pointer release may destroy this whole entry.
        return self.wrap.releaseNative();
    }
    pub fn cancel(self: *Entry) void {
        if (self.dispatched) self.cancel_native(self);
    }
};
