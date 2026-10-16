//! Exact reviewed phase roots/manifests, distinct from source-only old owners.
const std = @import("std");
const files = @import("files.zig");
const grant = @import("grant.zig");
const junctions = @import("junctions.zig");
pub const original_prefix = "C:\\Users\\adyba\\pi-upstream-runtime-19cb534-20261012\\";
pub const hidden_relative = "node_modules\\.package-lock.json";
pub const hidden_sha = "AF509CE546BBE5CEB218CB054DDFD216C0D814FD611130492AE22B6C4A0446AF";
pub const Config = struct {
    schema: u32,
    metadata: []const u8,
    reproduction: []const u8,
    cache: []const u8,
    protected_stage: []const u8,
    evidence_packet: []const u8,
    source1898: []const u8,
    prebuild28293: []const u8,
    hydrated43: []const u8,
    generated2771: []const u8,
    runtime31064: []const u8,
    protected30555_jsonl: []const u8,
    tools1774: []const u8,
    tools1838: []const u8,
    cache_pins365: []const u8,
    initial_cache558_jsonl: []const u8,
    absence84: []const u8,
    junction_plan: []const u8,
    prospective_tools: []const u8,
    empty_user_npmrc: []const u8,
    empty_global_npmrc: []const u8,
    reviewed_ci_terminal: ?[]const u8 = null,
    prior_cache_snapshot: ?[]const u8 = null,
    prior_cache_snapshot_sha256: ?[]const u8 = null,
};
pub const Loaded = struct {
    bytes: []u8,
    parsed: std.json.Parsed(Config),
    allocator: std.mem.Allocator,
    pub fn close(self: *Loaded) void {
        self.parsed.deinit();
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};
pub fn load(allocator: std.mem.Allocator, data: grant.Data) !Loaded {
    const bytes = try files.readBounded(allocator, data.phase_inputs_path, 65536);
    errdefer allocator.free(bytes);
    var hash: files.Hash = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    try grant.sameHash(data.phase_inputs_sha256, hash);
    const parsed = try std.json.parseFromSlice(Config, allocator, bytes, .{});
    errdefer parsed.deinit();
    const cfg = parsed.value;
    if (cfg.schema != 1) return error.PhaseInputsSchema;
    _ = try junctions.WriteRoot.reviewed(cfg.metadata, cfg.protected_stage);
    _ = try junctions.WriteRoot.reviewed(cfg.reproduction, cfg.protected_stage);
    if (!std.mem.startsWith(u8, cfg.metadata[(files.container ++ "\\upstream\\runtime\\").len..], "19cb534-metadata-install-") or
        !std.mem.startsWith(u8, cfg.reproduction[(files.container ++ "\\upstream\\runtime\\").len..], "19cb534-reproduction-"))
        return error.PhaseRootRolesMismatch;
    try files.contained(cfg.protected_stage, files.container ++ "\\upstream\\runtime");
    try files.contained(cfg.cache, files.container ++ "\\upstream\\runtime");
    try files.contained(cfg.evidence_packet, files.container ++ "\\evidence");
    const runtime_prefix = files.container ++ "\\upstream\\runtime\\";
    if (!std.mem.startsWith(u8, cfg.cache[runtime_prefix.len..], "19cb534-reproduction-cache-") or
        !std.mem.startsWith(u8, cfg.protected_stage[runtime_prefix.len..], "19cb534-recovery-staging-"))
        return error.CacheOrStageRoleMismatch;
    const evidence_prefix = files.container ++ "\\evidence\\";
    if (!std.mem.startsWith(u8, cfg.evidence_packet[evidence_prefix.len..], "runtime-reproduction-native-owner-"))
        return error.FreshNativeEvidencePacketRequired;
    const roots = [_][]const u8{ cfg.metadata, cfg.reproduction, cfg.cache, cfg.protected_stage };
    for (roots, 0..) |root, index| {
        for (roots[0..index]) |other| {
            if (std.ascii.eqlIgnoreCase(root, other) or isDescendant(root, other) or isDescendant(other, root))
                return error.PhaseRootsOverlap;
        }
    }
    for ([_][]const u8{ cfg.source1898, cfg.prebuild28293, cfg.hydrated43, cfg.generated2771, cfg.runtime31064,
        cfg.protected30555_jsonl, cfg.tools1774, cfg.tools1838, cfg.cache_pins365, cfg.initial_cache558_jsonl,
        cfg.absence84, cfg.junction_plan, cfg.prospective_tools, cfg.empty_user_npmrc, cfg.empty_global_npmrc }) |path|
        try grant.requireNamedControl(allocator, data, path);
    const empty_sha = "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855";
    try grant.sameHash(empty_sha, try files.hash(allocator, cfg.empty_user_npmrc));
    try grant.sameHash(empty_sha, try files.hash(allocator, cfg.empty_global_npmrc));
    if (data.phase == .build_offline) {
        const ci = cfg.reviewed_ci_terminal orelse return error.ReviewedCiPathRequired;
        try files.contained(ci, files.container ++ "\\evidence");
        try grant.sameHash(data.reviewed_ci_terminal_receipt_sha256 orelse return error.ReviewedCiHashRequired,
            try files.hash(allocator, ci));
        const ci_bytes = try files.readBounded(allocator, ci, 1024 * 1024);
        defer allocator.free(ci_bytes);
        const Ci = struct { phase: grant.Phase, status: []const u8, all_final_assertions_exact: bool,
            job_zero: bool, runtime_status: []const u8, authority_complete: bool };
        const ci_parsed = try std.json.parseFromSlice(Ci, allocator, ci_bytes, .{ .ignore_unknown_fields = true });
        defer ci_parsed.deinit();
        if (ci_parsed.value.phase != .npm_ci_offline or !std.mem.eql(u8, ci_parsed.value.status, "ci_reproduced_exact") or
            !ci_parsed.value.all_final_assertions_exact or !ci_parsed.value.job_zero or ci_parsed.value.authority_complete or
            !std.mem.eql(u8, ci_parsed.value.runtime_status, "recovery_pending")) return error.CiQualificationRequired;
        if (cfg.prior_cache_snapshot == null or cfg.prior_cache_snapshot_sha256 == null)
            return error.ReviewedPriorCacheSnapshotRequired;
        try files.contained(cfg.prior_cache_snapshot.?, files.container ++ "\\evidence");
        try grant.sameHash(cfg.prior_cache_snapshot_sha256.?, try files.hash(allocator, cfg.prior_cache_snapshot.?));
    }
    return .{ .bytes = bytes, .parsed = parsed, .allocator = allocator };
}
fn isDescendant(path: []const u8, root: []const u8) bool {
    return path.len > root.len and path[root.len] == '\\' and std.ascii.eqlIgnoreCase(path[0..root.len], root);
}
pub const PlanRow = struct { root: []const u8, path: []const u8, target: []const u8 };
pub fn links(allocator: std.mem.Allocator, cfg: Config, root: []const u8) ![]junctions.Plan {
    const bytes = try files.readBounded(allocator, cfg.junction_plan, 65536);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice([]PlanRow, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    if (parsed.value.len != 32) return error.Exact32TwoRootPlanRequired;
    var list: std.ArrayList(junctions.Plan) = .empty;
    errdefer {
        for (list.items) |row| { allocator.free(row.root); allocator.free(row.path); allocator.free(row.target); }
        list.deinit(allocator);
    }
    for (parsed.value) |row| {
        if (!std.mem.eql(u8, row.root, root)) continue;
        const owned_root = try allocator.dupe(u8, row.root);
        errdefer allocator.free(owned_root);
        const path = try allocator.dupe(u8, row.path);
        errdefer allocator.free(path);
        const target = try allocator.dupe(u8, row.target);
        errdefer allocator.free(target);
        try list.append(allocator, .{ .root = owned_root, .path = path, .target = target });
    }
    try junctions.validatePlan(list.items, root);
    return list.toOwnedSlice(allocator);
}
pub fn releaseLinks(allocator: std.mem.Allocator, rows: []junctions.Plan) void {
    for (rows) |row| { allocator.free(row.root); allocator.free(row.path); allocator.free(row.target); }
    allocator.free(rows);
}
