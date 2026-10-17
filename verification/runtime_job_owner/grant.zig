//! A new native owner grant, never an old 12BA/Source/TLA grant reinterpreted.
const std = @import("std");
const files = @import("files.zig");
const w = @import("win32.zig");
const deadline = @import("deadline.zig");
pub const Phase = enum { npm_ci_offline, build_offline };
pub const Control = struct { path: []const u8, sha256: []const u8 };
pub const Data = struct {
    schema: u32,
    owner: []const u8,
    authorized: bool,
    scope: []const u8,
    phase: Phase,
    attempt: []const u8,
    grant_id: []const u8,
    design_sha256: []const u8,
    final_sealer_addendum_sha256: []const u8,
    implementation_commit: []const u8,
    owner_executable: []const u8,
    owner_executable_sha256: []const u8,
    controls_manifest: []const u8,
    controls_manifest_sha256: []const u8,
    phase_inputs_path: []const u8,
    phase_inputs_sha256: []const u8,
    current_lease_name: []const u8,
    current_lease_terminal_receipt: []const u8,
    current_lease_terminal_receipt_sha256: []const u8,
    root_verified_lease_terminal_and_absence: bool,
    released_owned_pids: []const u32,
    job_commit_bytes: u64,
    process_commit_bytes: u64,
    active_process_cap: u32,
    phase_deadline_ms: u64,
    node_deadline_ms: u64,
    retirement_reserve_ms: u64,
    final_verification_stage_ms: u64,
    fresh_memory_bytes: u64,
    prospective_tool_closure_sha256: []const u8,
    reviewed_ci_terminal_receipt_sha256: ?[]const u8 = null,
};
pub const Loaded = struct {
    bytes: []u8,
    parsed: std.json.Parsed(Data),
    allocator: std.mem.Allocator,
    pub fn deinit(self: *Loaded) void {
        self.parsed.deinit();
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};
pub fn sameHash(expected: []const u8, actual: files.Hash) !void {
    if (expected.len != 64) return error.InvalidSha256;
    var decoded: files.Hash = undefined;
    _ = try std.fmt.hexToBytes(&decoded, expected);
    if (!std.crypto.timing_safe.eql(files.Hash, decoded, actual)) return error.ControlHashMismatch;
}
pub const ReleasedPresence = enum { retired, pid_reused };
/// Births come from the hashed original receipt and the same held kernel handle.
/// A numeric PID alone is never evidence that the original owner remains live.
pub fn classifyReleasedIdentity(expected: ?u64, current: ?u64, wait: u32) !ReleasedPresence {
    const original = expected orelse return error.PreviousLeasePidPresent;
    const observed = current orelse return error.PreviousLeaseIdentityUnverifiable;
    if (original == 0 or observed == 0) return error.PreviousLeaseIdentityUnverifiable;
    if (wait == w.wait_object) return .retired;
    if (wait != w.wait_timeout) return error.PreviousLeaseAbsenceUnverifiable;
    if (original != observed) return .pid_reused;
    return error.PreviousLeasePidPresent;
}
pub fn checkReleasedHandle(handle: w.H, pid: u32, expected: ?u64) !ReleasedPresence {
    if (w.GetProcessId(handle) != pid) return error.PreviousLeaseIdentityUnverifiable;
    const wait = w.WaitForSingleObject(handle, 0);
    if (wait != w.wait_object and wait != w.wait_timeout) return error.PreviousLeaseAbsenceUnverifiable;
    var created: w.FileTime = undefined;
    var exited: w.FileTime = undefined;
    var kernel: w.FileTime = undefined;
    var user: w.FileTime = undefined;
    if (w.GetProcessTimes(handle, &created, &exited, &kernel, &user) == 0)
        return error.PreviousLeaseIdentityUnverifiable;
    var exit_code: u32 = 0;
    if (w.GetExitCodeProcess(handle, &exit_code) == 0) return error.PreviousLeaseAbsenceUnverifiable;
    // The signaled state proves retirement, independently of the exit value
    // (259 is also a possible actual exit code). No control is performed.
    return classifyReleasedIdentity(expected, created.ticks(), wait);
}
fn digits(bytes: []const u8) !u32 {
    if (bytes.len == 0) return error.PreviousLeaseIdentityUnverifiable;
    for (bytes) |byte| if (byte < '0' or byte > '9') return error.PreviousLeaseIdentityUnverifiable;
    return std.fmt.parseInt(u32, bytes, 10) catch return error.PreviousLeaseIdentityUnverifiable;
}
fn leap(year: u32) bool { return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0); }
fn daysBeforeYear(year: u32) u64 { const prior: u64 = year - 1; return 365 * prior + prior / 4 - prior / 100 + prior / 400; }
/// Exact ISO owner-receipt UTC conversion; no CIM/millisecond tolerance. Both
/// .NET seven-digit and trimmed fractional forms map to the same100ns FILETIME.
pub fn receiptFileTime(value: []const u8) !u64 {
    if (value.len < 20 or value.len > 33 or value[4] != '-' or value[7] != '-' or value[10] != 'T' or value[13] != ':' or value[16] != ':')
        return error.PreviousLeaseIdentityUnverifiable;
    const year = try digits(value[0..4]); const month = try digits(value[5..7]); const day = try digits(value[8..10]);
    const hour = try digits(value[11..13]); const minute = try digits(value[14..16]); const second = try digits(value[17..19]);
    if (year < 1601 or year > 9999 or month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59)
        return error.PreviousLeaseIdentityUnverifiable;
    const months = [_]u32{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const max_day = months[month - 1] + @as(u32, if (month == 2 and leap(year)) 1 else 0);
    if (day == 0 or day > max_day) return error.PreviousLeaseIdentityUnverifiable;
    var days = daysBeforeYear(year) - daysBeforeYear(1601) + day - 1;
    for (months[0 .. month - 1], 0..) |count, index| days += count + @as(u32, if (index == 1 and leap(year)) 1 else 0);
    var position: usize = 19; var fraction: u64 = 0;
    if (value[position] == '.') {
        position += 1; const start = position;
        while (position < value.len and value[position] >= '0' and value[position] <= '9') : (position += 1) {}
        const count = position - start;
        if (count == 0 or count > 7) return error.PreviousLeaseIdentityUnverifiable;
        fraction = try digits(value[start..position]);
        for (count..7) |_| fraction *= 10;
    }
    var offset: i64 = 0;
    if (position + 1 == value.len and value[position] == 'Z') {} else {
        if (position + 6 != value.len or (value[position] != '+' and value[position] != '-') or value[position + 3] != ':')
            return error.PreviousLeaseIdentityUnverifiable;
        const zone_hour = try digits(value[position + 1 .. position + 3]); const zone_minute = try digits(value[position + 4 .. position + 6]);
        if (zone_hour > 14 or zone_minute > 59 or (zone_hour == 14 and zone_minute != 0)) return error.PreviousLeaseIdentityUnverifiable;
        offset = @as(i64, zone_hour) * 3600 + @as(i64, zone_minute) * 60;
        if (value[position] == '-') offset = -offset;
    }
    const seconds: i128 = @as(i128, days) * 86400 + @as(i128, hour) * 3600 + @as(i128, minute) * 60 + second - offset;
    const ticks = seconds * 10_000_000 + fraction;
    if (ticks <= 0 or ticks > std.math.maxInt(u64)) return error.PreviousLeaseIdentityUnverifiable;
    return @intCast(ticks);
}
const LeaseRecord = struct { pid: u32, receipt: []const u8, sha256: ?[]const u8 = null, receipt_sha256: ?[]const u8 = null };
const LeaseRecords = struct { records: []const LeaseRecord };
const OwnerReceipt = struct { pid: u32, created_utc: ?[]const u8 = null, creation_filetime_utc: ?u64 = null };
fn originalBirth(allocator: std.mem.Allocator, record: LeaseRecord) !u64 {
    try files.contained(record.receipt, files.container);
    const bytes = try files.readBounded(allocator, record.receipt, 65536); defer allocator.free(bytes);
    const hash = record.sha256 orelse record.receipt_sha256 orelse return error.PreviousLeaseIdentityUnverifiable;
    if (record.sha256 != null and record.receipt_sha256 != null and !std.ascii.eqlIgnoreCase(record.sha256.?, record.receipt_sha256.?))
        return error.PreviousLeaseIdentityUnverifiable;
    var digest: files.Hash = undefined; std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{}); try sameHash(hash, digest);
    const parsed = try std.json.parseFromSlice(OwnerReceipt, allocator, bytes, .{ .ignore_unknown_fields = true }); defer parsed.deinit();
    if (parsed.value.pid != record.pid) return error.PreviousLeaseIdentityUnverifiable;
    const text_birth: ?u64 = if (parsed.value.created_utc) |text| try receiptFileTime(text) else null;
    if (text_birth != null and parsed.value.creation_filetime_utc != null and text_birth.? != parsed.value.creation_filetime_utc.?)
        return error.PreviousLeaseIdentityUnverifiable;
    const birth = text_birth orelse parsed.value.creation_filetime_utc orelse return error.PreviousLeaseIdentityUnverifiable;
    if (birth == 0) return error.PreviousLeaseIdentityUnverifiable;
    return birth;
}
/// Shared production/fixture policy. Each requested original owner is bound to
/// a unique actual receipt inside the hashed lease, never an inferred PID role.
pub fn verifyReleasedProcesses(allocator: std.mem.Allocator, lease_path: []const u8, lease_sha: []const u8, pids: []const u32) !void {
    if (pids.len == 0 or pids.len > 64) return error.PreviousLeaseIdentityUnverifiable;
    try files.contained(lease_path, files.container);
    const bytes = try files.readBounded(allocator, lease_path, 65536); defer allocator.free(bytes);
    var digest: files.Hash = undefined; std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{}); try sameHash(lease_sha, digest);
    const parsed = try std.json.parseFromSlice(LeaseRecords, allocator, bytes, .{ .ignore_unknown_fields = true }); defer parsed.deinit();
    if (parsed.value.records.len == 0 or parsed.value.records.len > 64) return error.PreviousLeaseIdentityUnverifiable;
    for (pids, 0..) |pid, index| {
        if (pid == 0 or std.mem.indexOfScalar(u32, pids[0..index], pid) != null) return error.InvalidPreviousLeasePid;
        var matched: ?LeaseRecord = null;
        for (parsed.value.records) |candidate_record| if (candidate_record.pid == pid) {
            if (matched != null) return error.PreviousLeaseIdentityUnverifiable;
            matched = candidate_record;
        };
        const original_record = matched orelse return error.PreviousLeasePidPresent;
        const birth = try originalBirth(allocator, original_record);
        if (w.OpenProcess(w.process_query_limited | w.process_synchronize, 0, pid)) |handle| {
            defer _ = w.CloseHandle(handle);
            _ = try checkReleasedHandle(handle, pid, birth);
        } else if (w.GetLastError() != 87) return error.PreviousLeaseAbsenceUnverifiable;
    }
}
pub fn load(allocator: std.mem.Allocator, path: []const u8, expected_grant_sha256: []const u8,
    phase: Phase, exact_owner: []const u8) !Loaded
{
    try files.contained(path, files.container);
    const bytes = try files.readBounded(allocator, path, 65536);
    errdefer allocator.free(bytes);
    var hash: files.Hash = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    try sameHash(expected_grant_sha256, hash);
    const parsed = try std.json.parseFromSlice(Data, allocator, bytes, .{});
    errdefer parsed.deinit();
    const data = parsed.value;
    if (data.schema != 1 or !data.authorized or !std.mem.eql(u8, data.owner, "Root") or
        !std.mem.eql(u8, data.scope, "original_19cb_runtime_reproduction_native_job_owner") or data.phase != phase)
        return error.ExplicitNativeOwnerGrantRequired;
    if (!std.mem.eql(u8, data.design_sha256, "41C8E303ABF6A85471EEAF8BFDB7345C0A89BE6B8DCFA869EF7F444C2BD85711"))
        return error.UnreviewedDesign;
    if (!std.mem.eql(u8, data.final_sealer_addendum_sha256,
        "191687FB996EB62D4E617D4B8C425521BCD5194EE1C13187CBB88AAB5DDEA9C6")) return error.UnreviewedFinalSealerContract;
    if (data.implementation_commit.len != 40 or data.attempt.len == 0 or data.attempt.len > 80 or
        data.grant_id.len == 0 or data.grant_id.len > 160) return error.InvalidGrantIdentity;
    for (data.implementation_commit) |byte| if (!std.ascii.isHex(byte)) return error.InvalidImplementationCommit;
    for (data.attempt) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-')
        return error.InvalidAttempt;
    if (!std.mem.eql(u8, data.owner_executable, exact_owner)) return error.GrantedOwnerPathMismatch;
    try files.contained(exact_owner, files.container);
    try sameHash(data.owner_executable_sha256, try files.hash(allocator, exact_owner));
    if (!data.root_verified_lease_terminal_and_absence or data.current_lease_name.len == 0 or
        data.released_owned_pids.len == 0 or data.released_owned_pids.len > 64)
        return error.CurrentRootLeaseReleaseRequired;
    try files.contained(data.current_lease_terminal_receipt, files.container);
    for (data.released_owned_pids, 0..) |pid, index| {
        if (pid == 0 or pid == w.GetCurrentProcessId() or
            std.mem.indexOfScalar(u32, data.released_owned_pids[0..index], pid) != null) return error.InvalidReleasedPidList;
    }
    try verifyReleasedProcesses(allocator, data.current_lease_terminal_receipt,
        data.current_lease_terminal_receipt_sha256, data.released_owned_pids);
    if (data.job_commit_bytes != 8 * 1024 * 1024 * 1024 or
        data.process_commit_bytes != 4 * 1024 * 1024 * 1024 or data.active_process_cap != 64 or
        data.phase_deadline_ms != 900000 or data.node_deadline_ms != 300000 or data.retirement_reserve_ms != 10000 or
        data.final_verification_stage_ms != 240000 or
        data.fresh_memory_bytes != 16 * 1024 * 1024 * 1024) return error.UnreviewedResourcePolicy;
    if (phase == .build_offline and data.reviewed_ci_terminal_receipt_sha256 == null)
        return error.ReviewedCiReceiptRequired;
    try verifyControls(allocator, data);
    try files.contained(data.phase_inputs_path, files.container);
    try sameHash(data.phase_inputs_sha256, try files.hash(allocator, data.phase_inputs_path));
    return .{ .bytes = bytes, .parsed = parsed, .allocator = allocator };
}
pub fn requireNamedControl(allocator: std.mem.Allocator, data: Data, path: []const u8) !void {
    try files.contained(path, files.container);
    const bytes = try files.readBounded(allocator, data.controls_manifest, 1024 * 1024);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice([]Control, allocator, bytes, .{});
    defer parsed.deinit();
    var matches: usize = 0;
    for (parsed.value) |control| {
        if (std.ascii.eqlIgnoreCase(control.path, path)) {
            matches += 1;
            try sameHash(control.sha256, try files.hash(allocator, path));
        }
    }
    if (matches != 1) return error.RequiredNamedControlMissing;
}
pub fn verifyControls(allocator: std.mem.Allocator, data: Data) !void {
    try files.contained(data.controls_manifest, files.container);
    const bytes = try files.readBounded(allocator, data.controls_manifest, 1024 * 1024);
    defer allocator.free(bytes);
    var hash: files.Hash = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    try sameHash(data.controls_manifest_sha256, hash);
    const parsed = try std.json.parseFromSlice([]Control, allocator, bytes, .{});
    defer parsed.deinit();
    if (parsed.value.len == 0 or parsed.value.len > 256) return error.ControlManifestLimit;
    for (parsed.value, 0..) |control, index| {
        try files.contained(control.path, files.container);
        for (parsed.value[0..index]) |previous| if (std.ascii.eqlIgnoreCase(previous.path, control.path))
            return error.DuplicateControlPath;
        try sameHash(control.sha256, try files.hash(allocator, control.path));
    }
}
pub fn requireMemoryBeforeResume() !void { try deadline.requireFreshMemory(); }
