//! Workload preparation/copy may mutate only the reviewed fresh reproduction root.
const std = @import("std");
const w = @import("win32.zig");
const files = @import("files.zig");
const inputs = @import("inputs.zig");
const grant = @import("grant.zig");
const tools = @import("tools.zig");
const command = @import("command.zig");
const junctions = @import("junctions.zig");
const absence = @import("absence.zig");
const manifest = @import("manifest.zig");
const Deadline = @import("deadline.zig").Deadline;
pub fn prepareBuildLinks(allocator: std.mem.Allocator, cfg: inputs.Config, deadline: Deadline,
    sink: manifest.Sink) !void
{
    const root = try junctions.WriteRoot.reviewed(cfg.reproduction, cfg.protected_stage);
    var pre = try manifest.Manifest.loadAbsolute(allocator, cfg.prebuild28293, inputs.original_prefix, 28293);
    defer pre.deinit();
    const actual = try manifest.checkTree(allocator, cfg.reproduction, &pre, deadline, sink);
    try actual.requireExact(0);
    const bundle = try files.join(allocator, cfg.reproduction, "packages\\coding-agent\\dist\\bundle");
    defer allocator.free(bundle);
    if (try absence.inspectPhysicalPath(allocator, bundle) != .absent) return error.FreshBundleRequired;
    const rows = try inputs.links(allocator, cfg, cfg.reproduction);
    defer inputs.releaseLinks(allocator, rows);
    for (rows) |row| {
        try deadline.normal();
        try junctions.create(allocator, root, row);
    }
}
pub fn transferExactHiddenLock(allocator: std.mem.Allocator, cfg: inputs.Config) !void {
    _ = try junctions.WriteRoot.reviewed(cfg.reproduction, cfg.protected_stage);
    const source = try files.join(allocator, cfg.metadata, inputs.hidden_relative);
    defer allocator.free(source);
    const target = try files.join(allocator, cfg.reproduction, inputs.hidden_relative);
    defer allocator.free(target);
    var pinned = try files.Pinned.open(allocator, source);
    defer pinned.close() catch {};
    try grant.sameHash(inputs.hidden_sha, try pinned.digest(std.crypto.hash.sha2.Sha256));
    try files.requirePhysicalAncestors(allocator, target);
    if (try absence.inspectPhysicalPath(allocator, target) != .absent) return error.ExistingHiddenLockPreserved;
    const from = try std.unicode.utf8ToUtf16LeAllocZ(allocator, source);
    defer allocator.free(from);
    const to = try std.unicode.utf8ToUtf16LeAllocZ(allocator, target);
    defer allocator.free(to);
    if (w.CopyFileW(from.ptr, to.ptr, 1) == 0) return error.HiddenLockTransferFailed;
    try grant.sameHash(inputs.hidden_sha, try files.hash(allocator, target));
}
pub fn checkCiOutput(allocator: std.mem.Allocator, cfg: inputs.Config, deadline: Deadline, sink: manifest.Sink) !void {
    var expected = try manifest.Manifest.loadAbsolute(allocator, cfg.prebuild28293, inputs.original_prefix, 28293);
    defer expected.deinit();
    var hydrated = try manifest.Manifest.loadAbsolute(allocator, cfg.hydrated43, inputs.original_prefix, 43);
    defer hydrated.deinit();
    var iterator = hydrated.entries.keyIterator();
    while (iterator.next()) |key| try expected.remove(key.*);
    const actual = try manifest.checkTree(allocator, cfg.metadata, &expected, deadline, sink);
    try actual.requireExact(16);
    const rows = try inputs.links(allocator, cfg, cfg.metadata);
    defer inputs.releaseLinks(allocator, rows);
    for (rows) |row| try junctions.check(allocator, row);
}
pub fn argv(allocator: std.mem.Allocator, selected: grant.Phase) ![]const []const u8 {
    const arguments = if (selected == .npm_ci_offline) &[_][]const u8{
        tools.node_path, "--max-old-space-size=1536", tools.npm_cli_path,
        "ci", "--offline", "--ignore-scripts", "--no-audit", "--no-fund", "--update-notifier=false",
    } else &[_][]const u8{
        tools.node_path, "--max-old-space-size=1536", tools.npm_cli_path,
        "run", "build:offline", "--offline", "--no-audit", "--no-fund", "--update-notifier=false",
    };
    return allocator.dupe([]const u8, arguments);
}
pub fn environment(allocator: std.mem.Allocator, cfg: inputs.Config, prospective: tools.Prospective,
    selected: grant.Phase, private_home: []const u8, private_temp: []const u8) ![]u16
{
    try files.contained(private_home, cfg.evidence_packet);
    try files.contained(private_temp, cfg.evidence_packet);
    const roaming = try std.fmt.allocPrint(allocator, "{s}\\AppData\\Roaming", .{private_home});
    defer allocator.free(roaming);
    const local = try std.fmt.allocPrint(allocator, "{s}\\AppData\\Local", .{private_home});
    defer allocator.free(local);
    return command.environment(allocator, &.{
        .{ .key = "SystemRoot", .value = "C:\\Windows" }, .{ .key = "windir", .value = "C:\\Windows" },
        .{ .key = "SystemDrive", .value = "C:" }, .{ .key = "ComSpec", .value = prospective.cmd_path },
        .{ .key = "PATH", .value = prospective.private_tool_root }, .{ .key = "PATHEXT", .value = ".COM;.EXE;.BAT;.CMD" },
        .{ .key = "HOME", .value = private_home }, .{ .key = "USERPROFILE", .value = private_home },
        .{ .key = "APPDATA", .value = roaming }, .{ .key = "LOCALAPPDATA", .value = local },
        .{ .key = "TEMP", .value = private_temp }, .{ .key = "TMP", .value = private_temp },
        .{ .key = "NODE_OPTIONS", .value = "--max-old-space-size=1536" }, .{ .key = "CI", .value = "true" },
        .{ .key = "HUSKY", .value = "0" }, .{ .key = "FORCE_COLOR", .value = "0" },
        .{ .key = "NPM_CONFIG_CACHE", .value = cfg.cache },
        .{ .key = "NPM_CONFIG_USERCONFIG", .value = cfg.empty_user_npmrc },
        .{ .key = "NPM_CONFIG_GLOBALCONFIG", .value = cfg.empty_global_npmrc },
        .{ .key = "NPM_CONFIG_SCRIPT_SHELL", .value = prospective.cmd_path },
        .{ .key = "NPM_CONFIG_OFFLINE", .value = "true" }, .{ .key = "NPM_CONFIG_AUDIT", .value = "false" },
        .{ .key = "NPM_CONFIG_FUND", .value = "false" }, .{ .key = "NPM_CONFIG_UPDATE_NOTIFIER", .value = "false" },
        .{ .key = "NPM_CONFIG_PROGRESS", .value = "false" },
        .{ .key = "NPM_CONFIG_IGNORE_SCRIPTS", .value = if (selected == .npm_ci_offline) "true" else "false" },
    });
}
