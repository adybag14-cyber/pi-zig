//! REVIEW ONLY: explicit private capability; no existing descriptor opts in.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const c = js.c;
const uv = @import("native_uv_api").c;

pub const Policy = struct {
    engine: *js.Engine,
    hooks: c.JSPiIOMapHooks,

    pub fn init(engine: *js.Engine, virtual_limit: usize) !Policy {
        try (try @import("native_env_io.zig").get(engine)).assertOwner();
        // Only Windows has actual page-boundary error references today.
        // This new private admission boundary is not a public fallback.
        if (builtin.os.tag != .windows) return error.PendingIOPlatformUnqualified;
        var hooks: c.JSPiIOMapHooks = undefined;
        if (c.pi_js_io_map_hooks(engine.native_memory_owner, virtual_limit, &hooks) < 0)
            return error.InvalidPendingIOVirtualReservationPolicy;
        return .{ .engine = engine, .hooks = hooks };
    }
};

pub const Lease = struct {
    engine: *js.Engine,
    token: *c.JSPiIOLease,

    pub fn acquire(policy: *const Policy, backing: c.JSValue, offset: usize, length: usize, destination: bool) !Lease {
        try (try @import("native_env_io.zig").get(policy.engine)).assertOwner();
        var token: ?*c.JSPiIOLease = null;
        if (c.JS_PiAcquireIOLease(policy.engine.context, backing, offset, length, @intFromBool(destination), &policy.hooks, &token) < 0)
            return js.capture(policy.engine);
        return .{ .engine = policy.engine, .token = token.? };
    }
    pub fn acquireExternal(engine: *js.Engine, backing: c.JSValue, offset: usize, length: usize, destination: bool, provider: *const c.JSPiIOExternalHooks, provider_context: ?*anyopaque) !Lease {
        try (try @import("native_env_io.zig").get(engine)).assertOwner();
        var token: ?*c.JSPiIOLease = null;
        if (c.JS_PiAcquireExternalIOLease(engine.context, backing, offset, length, @intFromBool(destination), provider, provider_context, &token) < 0)
            return js.capture(engine);
        return .{ .engine = engine, .token = token.? };
    }
    // These two operations may execute on the native worker. Neither enters
    // the VM nor releases storage. The task must retain this Lease until join.
    pub fn buffer(self: Lease) uv.uv_buf_t {
        return uv.uv_buf_init(c.JS_PiIOLeaseData(self.token), @intCast(c.JS_PiIOLeaseLength(self.token)));
    }
    pub fn status(self: Lease, operation: c.JSPiIOOperation, index: usize) c.JSPiIOStatus {
        var result: c.JSPiIOStatus = undefined;
        c.JS_PiIOLeaseStatus(self.token, operation, index, &result);
        return result;
    }
    pub fn nativeStatus(result: c.JSPiIOStatus) !c_int {
        if (result.reason == c.JS_PI_IO_READY) return 0;
        if (result.reason == c.JS_PI_IO_EXTERNAL_PROTOCOL) return error.InvalidExternalIOStatus;
        if (result.reason == c.JS_PI_IO_EXTERNAL_UNAVAILABLE) return error.ExternalIOStatusUnqualified;
        // A valid prefix in this span, or an earlier vector, can change partial
        // syscall counts/file offset. Genuine vector references are required;
        // do not replace partial execution with a fabricated whole-job failure.
        if (result.available != 0 or result.operation == c.JS_PI_IO_READV or result.operation == c.JS_PI_IO_WRITEV)
            return error.PendingIOPartialSpanPolicyUnqualified;
        // Actual Windows Node24 page-shrink read/write outcomes. The physical
        // bytes stay mapped and retained even when this admitted span rejects.
        return if (result.operation == c.JS_PI_IO_READ) uv.UV_EFAULT else uv.UV_UNKNOWN;
    }
    pub fn deinit(self: *Lease) void {
        // VM owner only, after task.finish / worker join; C asserts the owner.
        c.JS_PiReleaseIOLease(self.engine.runtime, self.token);
        self.* = undefined;
    }
};

// A Job owns this table, including during partial admission failures. Allocate
// before pinning any vector; every unused slot is initialized to null. Deinit
// is called before receiver/view roots, only after the worker is terminal.
pub const Set = struct {
    engine: *js.Engine,
    slots: []?Lease = &.{},
    pub fn init(engine: *js.Engine, count: usize) !Set {
        const slots = try engine.gpa.alloc(?Lease, count);
        @memset(slots, null);
        return .{ .engine = engine, .slots = slots };
    }
    pub fn deinit(self: *Set) void {
        for (self.slots) |*slot| if (slot.*) |*lease| lease.deinit();
        self.engine.gpa.free(self.slots);
        self.slots = &.{};
    }
};
