//! Native fixture admission is separate from reproduction/old12BA grants.
const std = @import("std");
const w = @import("../win32.zig");
const files = @import("../files.zig");
const grant = @import("../grant.zig");
const common = @import("../common.zig");
extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, ?[*]u16, u32) callconv(.winapi) u32;
pub const Data = struct {
    schema: u32,
    owner: []const u8,
    authorized: bool,
    scope: []const u8,
    source_commit: []const u8,
    controls_manifest: []const u8,
    controls_manifest_sha256: []const u8,
    tests_executable: []const u8,
    tests_sha256: []const u8,
    actor_executable: []const u8,
    actor_sha256: []const u8,
    evidence_root: []const u8,
    working_root: []const u8,
    current_lease_terminal: []const u8,
    current_lease_terminal_sha256: []const u8,
    root_verified_lease_terminal_and_absence: bool,
    released_owned_pids: []const u32,
    planned_controls: u32,
};
pub const Loaded = struct { data: Data, bytes: []u8, parsed: std.json.Parsed(Data), path: []u8, sha: []u8 };
fn environment(allocator: std.mem.Allocator, comptime name: []const u8) ![]u8 {
    var wide: [32768]u16 = undefined;
    const count = GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral(name), &wide, wide.len);
    if (count == 0 or count >= wide.len) return error.FixtureGrantEnvironmentRequired;
    return std.unicode.utf16LeToUtf8Alloc(allocator, wide[0..count]);
}
pub fn load(allocator: std.mem.Allocator, actor: bool) !Loaded {
    const path = try environment(allocator, "PI_ZIG_FIXTURE_GRANT");
    const sha = try environment(allocator, "PI_ZIG_FIXTURE_GRANT_SHA256");
    try files.contained(path, files.container);
    const bytes = try files.readBounded(allocator, path, 65536);
    var digest: files.Hash = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    try grant.sameHash(sha, digest);
    const parsed = try std.json.parseFromSlice(Data, allocator, bytes, .{});
    const data = parsed.value;
    if (data.schema != 1 or !data.authorized or !std.mem.eql(u8, data.owner, "Root") or
        !std.mem.eql(u8, data.scope, "runtime_job_owner_native_fixture29") or data.planned_controls != 29 or
        data.source_commit.len != 40 or !data.root_verified_lease_terminal_and_absence or
        data.released_owned_pids.len == 0 or data.released_owned_pids.len > 64) return error.NativeFixtureGrantRequired;
    for (data.source_commit) |byte| if (!std.ascii.isHex(byte)) return error.NativeFixtureGrantRequired;
    try files.contained(data.controls_manifest, files.container);
    const control_bytes = try files.readBounded(allocator, data.controls_manifest, 1024 * 1024);
    var control_hash: files.Hash = undefined;
    std.crypto.hash.sha2.Sha256.hash(control_bytes, &control_hash, .{});
    try grant.sameHash(data.controls_manifest_sha256, control_hash);
    const controls = try std.json.parseFromSlice([]grant.Control, allocator, control_bytes, .{});
    if (controls.value.len == 0 or controls.value.len > 256) return error.FixtureControlsBound;
    for (controls.value, 0..) |control, index| {
        try files.contained(control.path, files.container);
        for (controls.value[0..index]) |prior| if (std.ascii.eqlIgnoreCase(prior.path, control.path)) return error.DuplicateFixtureControl;
        try grant.sameHash(control.sha256, try files.hash(allocator, control.path));
    }
    try files.contained(data.tests_executable, files.container);
    try files.contained(data.actor_executable, files.container);
    try files.contained(data.evidence_root, files.container ++ "\\evidence");
    try files.contained(data.working_root, files.container ++ "\\upstream\\runtime");
    const work_prefix = files.container ++ "\\upstream\\runtime\\19cb534-reproduction-controls-";
    if (!std.mem.startsWith(u8, data.working_root, work_prefix)) return error.FreshFixtureWorkingRootRequired;
    const actual = try common.selfPath(allocator);
    if (!std.ascii.eqlIgnoreCase(actual, if (actor) data.actor_executable else data.tests_executable)) {
        // The foreign-census controls use a byte-identical copied native actor
        // with the required basename/path. Restrict these two aliases to the
        // explicitly granted fresh fixture working root; never execute PATH.
        if (!actor) return error.FixtureExecutableMismatch;
        try files.contained(actual, data.working_root);
        if (!std.mem.endsWith(u8, actual, "\\.zig-cache\\main.exe") and
            !std.mem.endsWith(u8, actual, "\\.zig-cache\\test.exe")) return error.FixtureExecutableMismatch;
    }
    try grant.sameHash(if (actor) data.actor_sha256 else data.tests_sha256, try files.hash(allocator, actual));
    try files.contained(data.current_lease_terminal, files.container ++ "\\evidence");
    try grant.verifyReleasedProcesses(allocator, data.current_lease_terminal,
        data.current_lease_terminal_sha256, data.released_owned_pids);
    return .{ .data = data, .bytes = bytes, .parsed = parsed, .path = path, .sha = sha };
}
