//! Historical1774 authority is node.exe + complete npm subtree, not its parent.
const std = @import("std");
const files = @import("files.zig");
const manifest = @import("manifest.zig");
const grant = @import("grant.zig");
const Deadline = @import("deadline.zig").Deadline;
const absence = @import("absence.zig");
pub const node_path = "C:\\Program Files\\nodejs\\node.exe";
pub const node_root = "C:\\Program Files\\nodejs";
pub const npm_root = "C:\\Program Files\\nodejs\\node_modules\\npm";
pub const npm_cli_path = npm_root ++ "\\bin\\npm-cli.js";
pub const node_hash = "63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088";
const Row = struct { path: []const u8, sha256: []const u8 };
pub const Report = struct { original_files: usize, node_exact: bool, npm: manifest.Report };
pub const additional_manifest_sha = "35F1F2B0F12BF79C06B47AE2BA8C485EF10A7714BE3F129772E3BA1BBB97B927";
const FullFrozen = struct { node_complete: []Row };

/// Additional original tool authority explicitly released by Root. It does not
/// rewrite1774 or restore runtime authority. Actual full1838 hashes/inventory
/// must match at each future before/after gate, including all64 additional files.
pub fn checkAdditionalOriginal1838(allocator: std.mem.Allocator, authority: []const u8,
    deadline: Deadline, sink: manifest.Sink) !manifest.Report
{
    try files.contained(authority, files.container ++ "\\evidence");
    const bytes = try files.readBounded(allocator, authority, 16 * 1024 * 1024);
    defer allocator.free(bytes);
    var digest: files.Hash = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    try grant.sameHash(additional_manifest_sha, digest);
    const parsed = try std.json.parseFromSlice(FullFrozen, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    if (parsed.value.node_complete.len != 1838) return error.ExactOriginal1838ToolFilesRequired;
    var expected: manifest.Manifest = .{ .allocator = allocator };
    defer expected.deinit();
    const prefix = node_root ++ "\\";
    for (parsed.value.node_complete) |row| {
        if (!std.mem.startsWith(u8, row.path, prefix)) return error.UnexpectedFullNodeToolPath;
        try expected.add(row.path[prefix.len..], row.sha256);
    }
    const report = try manifest.checkTree(allocator, node_root, &expected, deadline, sink);
    try report.requireExact(0);
    return report;
}
pub fn checkOriginal1774(allocator: std.mem.Allocator, authority: []const u8,
    deadline: Deadline, sink: manifest.Sink) !Report
{
    const bytes = try files.readBounded(allocator, authority, 2 * 1024 * 1024);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice([]Row, allocator, bytes, .{});
    defer parsed.deinit();
    if (parsed.value.len != 1774) return error.Exact1774ToolFilesRequired;
    var npm: manifest.Manifest = .{ .allocator = allocator };
    defer npm.deinit();
    var node_count: usize = 0;
    for (parsed.value) |row| {
        if (std.mem.eql(u8, row.path, node_path)) {
            node_count += 1;
            if (!std.ascii.eqlIgnoreCase(row.sha256, node_hash)) return error.OriginalNodeAuthorityMismatch;
            continue;
        }
        const prefix = npm_root ++ "\\";
        if (!std.mem.startsWith(u8, row.path, prefix)) return error.UnexpectedHistoricalToolPath;
        try npm.add(row.path[prefix.len..], row.sha256);
    }
    if (node_count != 1 or npm.entries.count() != 1773) return error.HistoricalToolScopeMismatch;
    try deadline.normal();
    try grant.sameHash(node_hash, try files.hash(allocator, node_path));
    const report = try manifest.checkTree(allocator, npm_root, &npm, deadline, sink);
    try report.requireExact(0);
    return .{ .original_files = 1774, .node_exact = true, .npm = report };
}

pub const Prospective = struct {
    schema: u32,
    authority_scope: []const u8,
    cmd_path: []const u8,
    cmd_sha256: []const u8,
    private_tool_root: []const u8,
    private_node_sha256: []const u8,
    npm_wrapper_sha256: []const u8,
};
pub fn loadProspective(allocator: std.mem.Allocator, path: []const u8, expected_sha: []const u8) !Prospective {
    try files.contained(path, files.container);
    const bytes = try files.readBounded(allocator, path, 65536);
    defer allocator.free(bytes);
    var digest: files.Hash = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    try grant.sameHash(expected_sha, digest);
    const parsed = try std.json.parseFromSlice(Prospective, allocator, bytes, .{});
    defer parsed.deinit();
    const data = parsed.value;
    if (data.schema != 1 or !std.mem.eql(u8, data.authority_scope, "prospective_control_tools_not_historical_1774") or
        !std.mem.eql(u8, data.cmd_path, "C:\\Windows\\System32\\cmd.exe") or
        !std.ascii.eqlIgnoreCase(data.private_node_sha256, node_hash)) return error.UnreviewedProspectiveToolScope;
    try files.contained(data.private_tool_root, files.container ++ "\\upstream\\runtime");
    const leaf = data.private_tool_root[(files.container ++ "\\upstream\\runtime\\").len..];
    if (!std.mem.startsWith(u8, leaf, "19cb534-owner-tools-")) return error.UnreviewedPrivateToolRoot;
    for (leaf) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-') return error.UnreviewedPrivateToolRoot;
    return cloneProspective(allocator, data);
}
pub fn checkProspective(allocator: std.mem.Allocator, path: []const u8, expected_sha: []const u8,
    deadline: Deadline, sink: manifest.Sink) !Prospective
{
    const data = try loadProspective(allocator, path, expected_sha);
    errdefer releaseProspective(allocator, data);
    try grant.sameHash(data.cmd_sha256, try files.hash(allocator, data.cmd_path));
    var expected: manifest.Manifest = .{ .allocator = allocator };
    defer expected.deinit();
    try expected.add("node.exe", node_hash);
    try expected.add("npm.cmd", data.npm_wrapper_sha256);
    const report = try manifest.checkTree(allocator, data.private_tool_root, &expected, deadline, sink);
    try report.requireExact(0);
    return data;
}
fn cloneProspective(allocator: std.mem.Allocator, data: Prospective) !Prospective {
    const scope = try allocator.dupe(u8, data.authority_scope);
    errdefer allocator.free(scope);
    const cmd = try allocator.dupe(u8, data.cmd_path);
    errdefer allocator.free(cmd);
    const cmd_sha = try allocator.dupe(u8, data.cmd_sha256);
    errdefer allocator.free(cmd_sha);
    const root = try allocator.dupe(u8, data.private_tool_root);
    errdefer allocator.free(root);
    const node_sha = try allocator.dupe(u8, data.private_node_sha256);
    errdefer allocator.free(node_sha);
    const npm_sha = try allocator.dupe(u8, data.npm_wrapper_sha256);
    return .{ .schema = data.schema, .authority_scope = scope, .cmd_path = cmd, .cmd_sha256 = cmd_sha,
        .private_tool_root = root, .private_node_sha256 = node_sha, .npm_wrapper_sha256 = npm_sha };
}
pub fn releaseProspective(allocator: std.mem.Allocator, data: Prospective) void {
    allocator.free(data.authority_scope);
    allocator.free(data.cmd_path);
    allocator.free(data.cmd_sha256);
    allocator.free(data.private_tool_root);
    allocator.free(data.private_node_sha256);
    allocator.free(data.npm_wrapper_sha256);
}

pub const AncestorBin = struct {
    path: []const u8,
    scope: enum { original_runtime_manifest, prospective_required_absent },
    state: ?absence.State,
};
pub const AncestorSink = struct {
    context: *anyopaque,
    write_fn: *const fn (*anyopaque, AncestorBin) anyerror!void,
};
/// npm's sealed set-path.js prepends .bin from every ancestor to drive root,
/// before private PATH. All outside-runtime ancestors must therefore be absent,
/// rather than silently becoming executable search authority. No npm edits.
pub fn checkAncestorBins(allocator: std.mem.Allocator, reproduction: []const u8,
    script_cwds: []const []const u8, deadline: Deadline, sink: AncestorSink) !void
{
    try files.contained(reproduction, files.container ++ "\\upstream\\runtime");
    if (script_cwds.len == 0 or script_cwds.len > 32) return error.BuildCwdClosureLimit;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var keys = seen.keyIterator();
        while (keys.next()) |key| allocator.free(key.*);
        seen.deinit(allocator);
    }
    var unexpected: usize = 0;
    for (script_cwds) |cwd| {
        if (!std.mem.eql(u8, cwd, reproduction)) try files.contained(cwd, reproduction);
        try files.absolute(cwd);
        var parent = cwd;
        while (true) {
            try deadline.normal();
            const path = try std.fmt.allocPrint(allocator, "{s}{s}node_modules\\.bin",
                .{ parent, if (std.mem.endsWith(u8, parent, "\\")) "" else "\\" });
            const entry = seen.getOrPut(allocator, path) catch |err| {
                allocator.free(path);
                return err;
            };
            if (entry.found_existing) {
                allocator.free(path);
            } else {
                // Ownership transfers to seen, including subsequent errors.
                const in_runtime = path.len > reproduction.len and path[reproduction.len] == '\\' and
                    std.ascii.eqlIgnoreCase(path[0..reproduction.len], reproduction);
                if (in_runtime) {
                    try sink.write_fn(sink.context, .{ .path = path, .scope = .original_runtime_manifest, .state = null });
                } else {
                    const state = try absence.inspectPhysicalPath(allocator, path);
                    if (state == .present) unexpected += 1;
                    try sink.write_fn(sink.context, .{ .path = path, .scope = .prospective_required_absent, .state = state });
                }
            }
            if (parent.len == 3) break;
            const end = std.mem.lastIndexOfScalar(u8, parent, '\\') orelse return error.InvalidBuildCwd;
            parent = parent[0..if (end == 2) 3 else end];
        }
    }
    if (unexpected != 0) return error.UnsealedAncestorBinPresent;
}
