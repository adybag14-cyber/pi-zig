//! Read-only global inventory; never stop/restart a discovered process.
const std = @import("std");
const w = @import("win32.zig");
const process = @import("process.zig");
const job_module = @import("job.zig");
const deadline = @import("deadline.zig");
pub const Candidate = struct {
    pid: u32,
    observed_parent_pid: u32,
    kernel: process.KernelIdentity,
    is_own_attempt_member: bool,
    blocks_admission: bool,
};
pub const Sink = struct {
    context: *anyopaque,
    write_fn: *const fn (*anyopaque, *const Candidate) anyerror!void,
};

/// Run on a probe/worker thread, not supervisor's timing loop. Exclude only an
/// exact retained supervisor identity or membership in this attempt's exact job.
pub fn requireQuietNative(own_supervisor: *const process.KernelIdentity,
    owned_job: *const job_module.Job, sink: Sink) !void
{
    const self_now = try process.identity(w.GetCurrentProcess());
    if (self_now.pid != own_supervisor.pid or self_now.creation_filetime_utc != own_supervisor.creation_filetime_utc)
        return error.NativeAdmissionRequiresExactSupervisor;
    const snapshot = w.CreateToolhelp32Snapshot(2, 0);
    if (snapshot == w.invalid) return error.NativeInventoryUnverifiable;
    defer _ = w.CloseHandle(snapshot);
    var entry: w.ProcessEntry = std.mem.zeroes(w.ProcessEntry);
    entry.size = @sizeOf(w.ProcessEntry);
    if (w.Process32FirstW(snapshot, &entry) == 0) return error.NativeInventoryUnverifiable;
    var total: usize = 0;
    var blockers: usize = 0;
    while (true) {
        total += 1;
        if (total > 16384) return error.NativeInventoryLimit;
        const length = std.mem.indexOfScalar(u16, &entry.executable, 0) orelse return error.NativeNameUnterminated;
        const name = entry.executable[0..length];
        const zig = equalLiteral(name, "zig.exe");
        const maybe_generated = equalLiteral(name, "test.exe") or equalLiteral(name, "build.exe");
        if (zig or maybe_generated) {
            const handle = w.OpenProcess(w.process_query_limited | w.process_synchronize, 0, entry.pid);
            if (handle) |opened| {
                defer _ = w.CloseHandle(opened);
                const identity = try process.identity(opened);
                var own_member: w.B = 0;
                if (w.IsProcessInJob(opened, owned_job.handle orelse return error.JobClosed, &own_member) == 0)
                    return error.NativeMembershipUnverifiable;
                // Root's conservative global-native-zero rule includes visible
                // zig/build/test names regardless of path or container location.
                const blocked = own_member == 0;
                if (blocked) blockers += 1;
                const candidate: Candidate = .{ .pid = identity.pid, .observed_parent_pid = entry.parent_pid,
                    .kernel = identity, .is_own_attempt_member = own_member != 0, .blocks_admission = blocked };
                try sink.write_fn(sink.context, &candidate);
            } else if (w.GetLastError() != 87) return error.NativeCandidateUnverifiable;
        }
        if (w.Process32NextW(snapshot, &entry) == 0) {
            if (w.GetLastError() != 18) return error.NativeInventoryUnverifiable;
            break;
        }
    }
    if (blockers != 0) return error.OtherNativeJobPresent;
    try deadline.requireFreshMemory();
}
fn equalLiteral(value: []const u16, comptime literal: []const u8) bool {
    const wide = std.unicode.utf8ToUtf16LeStringLiteral(literal);
    return w.CompareStringOrdinal(value.ptr, @intCast(value.len), wide, literal.len, 1) == 2;
}
