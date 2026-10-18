//! Native synchronous Source exec-status admission over the real Linux Driver.
//! No early public result, guest callback or event-loop tick enters this scope.
const js = @import("native_js_values.zig");
const c = js.c;
const options = @import("native_child_process_options.zig");
const spawn = @import("native_child_process_spawn_linux.zig");
const driver_api = @import("native_child_process_driver_linux.zig");
const waits = @import("native_child_process_epoll_linux.zig");
const handshake = @import("native_child_process_handshake_linux.zig");
pub const Pending = struct {
    driver: *driver_api.Driver,
    deadline: handshake.Deadline,
    cancellation: handshake.Cancellation,
};
pub const Outcome = union(enum) {
    spawned: *driver_api.Driver,
    // A real failure record and real native child reap; parent endpoints remain
    // genuinely owned so Source may construct/flush/close the failed pipes.
    exec_failed_reaped: struct { driver: *driver_api.Driver, failure: spawn.Failure },
    parent_mask_recovery_required: Pending,
    // Neither success nor UV errno. Caller must retire exact native ownership
    // through Driver/owned native reaper/quarantine before its host fatal exit.
    uncertain: struct { pending: Pending, details: @FieldType(handshake.Decision, "uncertain") },
};
pub const RetainedHostFailure = struct {
    retirement: driver_api.NativeRetirement,
    details: @FieldType(handshake.Decision, "uncertain"),
};
/// Consumes the actual uncertain Driver only after its native stop/handoff has
/// succeeded. No public spawn/error/tick is fabricated; the embedding retains
/// these native diagnostics for its actual host fatal/cancellation boundary.
pub fn retireUncertainty(packet: @FieldType(Outcome, "uncertain")) !RetainedHostFailure {
    return .{ .retirement = try packet.pending.driver.retireUncertainAdmission(), .details = packet.details };
}
/// Caller reserves/publishes the native cancellation ref before entering the
/// synchronous call and releases it only after return (or recovery continuation).
/// Config is consumed on every return, as by actual Driver.create. A failed
/// clone+failed mask restore leaves the separate caller recovery object intact.
pub fn create(engine: *js.Engine, config: options.Config, hooks: driver_api.Hooks, roots: []const c.JSValue, recovery: *spawn.MaskRecovery, cancellation: handshake.Cancellation, budget_ms: u32) !Outcome {
    // Budget begins before host reservation and actual clone/pre-exec setup.
    const deadline = handshake.startDeadline(budget_ms) catch |failure| { var cleanup = config; cleanup.deinit(); return failure; };
    const admitted = try driver_api.Driver.create(engine, config, hooks, roots, recovery);
    return switch (admitted) {
        .pending => |driver| finish(.{ .driver = driver, .deadline = deadline, .cancellation = cancellation }),
        .parent_mask_recovery_required => |driver| .{ .parent_mask_recovery_required = .{ .driver = driver, .deadline = deadline, .cancellation = cancellation } },
    };
}
/// Trusted host continuation only. It preserves the ORIGINAL deadline and exact
/// saved mask; it cannot grant another interval or turn recovery into VM work.
pub fn resumeAfterMaskRecovery(pending: Pending) Outcome {
    pending.driver.restoreParentMask() catch |failure| return .{ .uncertain = .{ .pending = pending, .details = .{ .reason = .{ .failure = failure } } } };
    return finish(pending);
}
fn finish(pending: Pending) Outcome {
    waits.withdraw(pending.driver.lease) catch |failure| return .{ .uncertain = .{ .pending = pending, .details = .{ .reason = .{ .failure = failure } } } };
    // The owner is inside a synchronous native frame, so Hub cannot dispatch
    // queued Driver/VM work. All external epoll interests are now withdrawn.
    const decision = handshake.awaitDecision(&pending.driver.transport.process, pending.deadline, pending.cancellation);
    waits.requestStep(pending.driver.lease);
    return switch (decision) {
        .exec_channel_closed => .{ .spawned = pending.driver },
        .exec_failed_reaped => |failure| .{ .exec_failed_reaped = .{ .driver = pending.driver, .failure = failure } },
        .uncertain => |details| .{ .uncertain = .{ .pending = pending, .details = details } },
    };
}
