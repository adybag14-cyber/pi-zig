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
    matches_native_name: bool,
    matches_cache_or_output_path: bool,
};
pub const Observation = union(enum) {
    candidate: Candidate,
    metadata_unavailable: struct { pid: u32, name: []const u16, win32_error: ?u32,
        required_by_name: bool, required_by_path: bool, observed_path: ?[]const u16 },
    gone_before_probe: struct { pid: u32, name: []const u16 },
};
pub const Sink = struct {
    context: *anyopaque,
    write_fn: *const fn (*anyopaque, Observation) anyerror!void,
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
        // Query observable paths for all rows, not only known basenames: e.g.
        // a main.exe in .zig-cache/zig-out is still a native-job candidate.
        const named_native = zig or maybe_generated;
        const handle = w.OpenProcess(w.process_query_limited | w.process_synchronize, 0, entry.pid);
        if (handle) |opened| {
            defer _ = w.CloseHandle(opened);
            const identity = process.identity(opened) catch |err| {
                if (w.WaitForSingleObject(opened, 0) == w.wait_object) {
                    try sink.write_fn(sink.context, .{ .gone_before_probe = .{ .pid = entry.pid, .name = name } });
                } else {
                    var partial_image: [32768]u16 = undefined;
                    var partial_units: u32 = partial_image.len;
                    const image_available = w.QueryFullProcessImageNameW(opened, 0, &partial_image, &partial_units) != 0 and
                        partial_units > 0 and partial_units < partial_image.len;
                    const image_path = if (image_available) partial_image[0..partial_units] else null;
                    const relevant_path = if (image_path) |image|
                        containsLiteral(image, "\\.zig-cache\\") or containsLiteral(image, "\\zig-out\\") else false;
                    try sink.write_fn(sink.context, .{ .metadata_unavailable = .{ .pid = entry.pid, .name = name,
                        .win32_error = null, .required_by_name = named_native,
                        .required_by_path = relevant_path, .observed_path = image_path } });
                    if (named_native or relevant_path) return err;
                }
                if (w.Process32NextW(snapshot, &entry) == 0) {
                    if (w.GetLastError() != 18) return error.NativeInventoryUnverifiable;
                    break;
                }
                continue;
            };
            const known_path = containsLiteral(identity.path(), "\\.zig-cache\\") or containsLiteral(identity.path(), "\\zig-out\\");
            if (named_native or known_path) {
                var own_member: w.B = 0;
                if (w.IsProcessInJob(opened, owned_job.handle orelse return error.JobClosed, &own_member) == 0)
                    return error.NativeMembershipUnverifiable;
                // Root's conservative global-native-zero rule includes visible
                // zig/build/test names regardless of path or container location.
                const exact_self = identity.pid == own_supervisor.pid and
                    identity.creation_filetime_utc == own_supervisor.creation_filetime_utc;
                const blocked = own_member == 0 and !exact_self;
                if (blocked) blockers += 1;
                const candidate: Candidate = .{ .pid = identity.pid, .observed_parent_pid = entry.parent_pid,
                    .kernel = identity, .is_own_attempt_member = own_member != 0 or exact_self, .blocks_admission = blocked,
                    .matches_native_name = named_native, .matches_cache_or_output_path = known_path };
                try sink.write_fn(sink.context, .{ .candidate = candidate });
            }
        } else {
            const cause = w.GetLastError();
            if (cause == 87 and entry.pid != 0) {
                try sink.write_fn(sink.context, .{ .gone_before_probe = .{ .pid = entry.pid, .name = name } });
            } else {
                // Some unrelated/system images are not queryable. Retain that
                // partial diagnostic honestly; never silently drop a required
                // known native row or invent its path/identity.
                try sink.write_fn(sink.context, .{ .metadata_unavailable = .{ .pid = entry.pid, .name = name,
                    .win32_error = cause, .required_by_name = named_native,
                    .required_by_path = false, .observed_path = null } });
                if (named_native) return error.NativeCandidateUnverifiable;
            }
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
fn containsLiteral(value: []const u16, comptime literal: []const u8) bool {
    if (value.len < literal.len) return false;
    for (0..value.len - literal.len + 1) |index| {
        if (equalLiteral(value[index..][0..literal.len], literal)) return true;
    }
    return false;
}
