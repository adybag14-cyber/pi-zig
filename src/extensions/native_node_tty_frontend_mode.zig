//! Genuine EMBEDDED frontend console-mode capability. This is not hydrated
//! isTTY metadata, a remote HANDLE transfer, or a worker stdio reinterpretation.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const streams = @import("native_process_streams.zig");
const frontend = @import("native_stdio_frontend.zig");
const consoles = @import("native_node_tty_windows_console.zig");
pub const Snapshot = struct {
    lease: streams.Lease,
    original_mode: u32,
    source_handle: std.os.windows.HANDLE,
    pub fn validate(self: Snapshot, engine: *v.em.Engine) !void {
        if (!streams.ownsLease(engine, self.lease)) return error.NativeTtyFrontendLeaseRetired;
        // A real native descriptor mapping must exist. A Bridge tty bool or
        // framed worker stdout cannot satisfy this exact native handle check.
        const observed = switch (consoles.probe(0)) { .console => |value| value, .failed => return error.NativeTtyFrontendNativeDescriptorRequired };
        if (observed.kind != .input or observed.borrowed != self.source_handle) return error.NativeTtyFrontendDescriptorMismatch;
    }
};
/// Called on the actual frontend owner before guest execution. Snapshot copies
/// its ORIGINAL native mode, not the current mode after TUI raw-mode changes.
/// No pointer to Frontend enters native worker storage or mode authority.
pub fn capture(engine: *v.em.Engine, actual: *frontend.Frontend) !?Snapshot {
    if (@import("builtin").os.tag != .windows) return null;
    if (actual.engine != engine or std.Thread.getCurrentId() != actual.owner or !actual.active.load(.acquire)) return error.NativeTtyActualFrontendOwnerRequired;
    const original = actual.console.input orelse return null;
    const lease = actual.lease orelse return error.NativeTtyFrontendLeaseRetired;
    const snapshot: Snapshot = .{ .lease = lease, .original_mode = original.mode, .source_handle = std.Io.File.stdin().handle };
    try snapshot.validate(engine); return snapshot;
}
