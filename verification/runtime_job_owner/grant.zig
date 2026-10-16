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
    try sameHash(data.current_lease_terminal_receipt_sha256,
        try files.hash(allocator, data.current_lease_terminal_receipt));
    for (data.released_owned_pids, 0..) |pid, index| {
        if (pid == 0 or pid == w.GetCurrentProcessId() or
            std.mem.indexOfScalar(u32, data.released_owned_pids[0..index], pid) != null) return error.InvalidReleasedPidList;
        const process = w.OpenProcess(w.process_query_limited | w.process_synchronize, 0, pid);
        if (process) |handle| {
            defer _ = w.CloseHandle(handle);
            return error.PreviousLeasePidPresent;
        }
        if (w.GetLastError() != 87) return error.PreviousLeaseAbsenceUnverifiable;
    }
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
