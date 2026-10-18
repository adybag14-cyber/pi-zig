//! Actual Linux native public admission provider: synchronous exec decision,
//! owner-scoped Engine cancellation, genuine negative errno and retained pipes.
const js = @import("native_js_values.zig");
const c = js.c;
const core = @import("native_child_process_driver_linux.zig");
const sync = @import("native_child_process_sync_admission_linux.zig");
const binding_api = @import("native_child_process_engine_cancel_binding_linux.zig");
const options = @import("native_child_process_options.zig");
const spawn = @import("native_child_process_spawn_linux.zig");
pub const OwnerBridge = core.Driver;
pub const Event = core.Event;
pub const Hooks = core.Hooks;
pub const HostFailure = struct {
    driver: ?*OwnerBridge,
    details: @FieldType(@import("native_child_process_handshake_linux.zig").Decision, "uncertain"),
};
pub const Attempt = union(enum) {
    ready: struct { driver: *OwnerBridge, errno: i32 = 0 },
    host_failure: HostFailure,
};
/// Errors before an actual Driver returns leave Hooks context caller-owned.
/// Once a real Driver exists, all conditions return it explicitly, including
/// host uncertainty; callers must link ownership BEFORE consuming/fatal cleanup.
/// recovery is CALLER-owned across every return, including clone failure with
/// failed mask restore; this function never abandons saved recovery on its stack.
pub fn startAttempt(engine: *js.Engine, config: options.Config, hooks: Hooks, roots: []const c.JSValue, recovery: *spawn.MaskRecovery, budget_ms: u32) !Attempt {
    var config_owned = true; defer if (config_owned) { var cleanup = config; cleanup.deinit(); };
    var binding = try binding_api.Binding.begin(engine);
    defer { _ = binding.end() catch @panic("native public admission cancellation ownership violated"); }
    config_owned = false;
    var outcome = sync.create(engine, config, hooks, roots, recovery, binding.reference, budget_ms) catch |failure| {
        recovery.restore() catch |restore_failure| return .{ .host_failure = .{ .driver = null, .details = .{ .reason = .{ .failure = restore_failure } } } };
        return failure;
    };
    switch (outcome) { .parent_mask_recovery_required => |pending| outcome = sync.resumeAfterMaskRecovery(pending), else => {} }
    return switch (outcome) {
        .spawned => |driver| success: {
            driver.transport.launch_delivered = true;
            break :success .{ .ready = .{ .driver = driver } };
        },
        .exec_failed_reaped => |actual| failed: {
            // Actual status and reap have been acknowledged by this native
            // admission caller, never represented by public spawn/exit events.
            actual.driver.transport.launch_delivered = true;
            actual.driver.transport.exit_delivered = true;
            if (actual.failure.errno_number == 0 or actual.failure.errno_number > 4095) break :failed .{ .host_failure = .{ .driver = actual.driver, .details = .{ .reason = .{ .failure = error.NativeLinuxChildInvalidExecStatus }, .known_failure = actual.failure } } };
            break :failed .{ .ready = .{ .driver = actual.driver, .errno = -@as(i32, @intCast(actual.failure.errno_number)) } };
        },
        .uncertain => |packet| .{ .host_failure = .{ .driver = packet.pending.driver, .details = packet.details } },
        .parent_mask_recovery_required => unreachable,
    };
}
/// Explicit native cleanup outcome. Failure leaves actual Driver ownership with
/// caller; pending mask recovery is never consumed. No error is silently ignored
/// and no queued/retained native result means independent process absence.
pub fn retireHostFailure(failure: HostFailure) !?core.NativeRetirement {
    const driver = failure.driver orelse return null;
    return try driver.retireUncertainAdmission();
}
/// Caller has installed the actual Driver/owner pointers. Uncertainty is a real
/// host fatal/cancel boundary, not a fabricated Node ETIMEDOUT or public errno.
pub fn throwHostFailure(engine: *js.Engine, _: u64) !void {
    // Actual pending/current invocation authority wins before a new native
    // host failure is materialized. Historical captured diagnostics stay DATA.
    try engine.checkNativeEntry();
    _ = c.JS_ThrowInternalError(engine.context, "Native Linux spawn admission could not establish a safe exec decision");
    const reason = c.JS_GetException(engine.context);
    if (c.JS_IsError(reason)) c.JS_SetUncatchableError(engine.context, reason);
    _ = try engine.checked(c.JS_Throw(engine.context, reason));
}
