//! Native Pi-env SSH argument contract and remote platform detection.
const std = @import("std");
pub const Target = struct {
    host: []const u8,
    known_hosts_file: []const u8,
    host_key_alias: []const u8,
    user: ?[]const u8 = null,
    port: ?u32 = null,
    identity_file: ?[]const u8 = null,
    config_file: ?[]const u8 = null,
    program: []const u8 = "ssh",
};
pub const Arguments = struct {
    gpa: std.mem.Allocator,
    values: std.ArrayList([]const u8) = .empty,
    pub fn deinit(self: *Arguments) void {
        for (self.values.items) |value| self.gpa.free(value);
        self.values.deinit(self.gpa);
    }
    fn append(self: *Arguments, text: []const u8) !void {
        if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSshArgument;
        const owned = try self.gpa.dupe(u8, text);
        errdefer self.gpa.free(owned);
        try self.values.append(self.gpa, owned);
    }
    fn formatted(self: *Arguments, comptime format: []const u8, args: anytype) !void {
        const owned = try std.fmt.allocPrint(self.gpa, format, args);
        defer self.gpa.free(owned);
        try self.append(owned);
    }
    fn option(self: *Arguments, text: []const u8) !void {
        try self.append("-o");
        try self.append(text);
    }
};
fn whitespace(codepoint: u21) bool {
    return switch (codepoint) {
        0x09...0x0d, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
pub fn validateField(value: []const u8) !void {
    if (value.len == 0 or value[0] == '-') return error.InvalidSshField;
    const view = std.unicode.Utf8View.init(value) catch return error.InvalidSshField;
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |cp| if (cp <= 0x1f or cp == 0x7f or whitespace(cp)) return error.InvalidSshField;
}
pub fn configPath(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return error.InvalidSshArgument;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);
    try output.append(gpa, '"');
    for (path) |byte| {
        if (byte == '"' or byte < 0x20 or byte == 0x7f) return error.InvalidSshArgument;
        if (byte == '%') try output.append(gpa, '%');
        try output.append(gpa, byte);
    }
    try output.append(gpa, '"');
    return output.toOwnedSlice(gpa);
}
pub fn arguments(gpa: std.mem.Allocator, target: Target, strict: bool, known_hosts_override: ?[]const u8) !Arguments {
    try validateField(target.host);
    try validateField(target.host_key_alias);
    if (target.user) |user| try validateField(user);
    if (target.port) |port| if (port == 0 or port > 65535) return error.InvalidSshPort;
    var result: Arguments = .{ .gpa = gpa };
    errdefer result.deinit();
    if (target.config_file) |path| {
        try result.append("-F");
        try result.append(path);
    }
    try result.append("-T");
    try result.append("-a");
    try result.append("-x");
    for ([_][]const u8{ "BatchMode=yes", "ClearAllForwardings=yes", "ForwardAgent=no", "ForwardX11=no", "ControlMaster=no", "ControlPath=none", "RemoteCommand=none", "PermitLocalCommand=no", "SendEnv=-*", "ServerAliveInterval=15" }) |value| try result.option(value);
    try result.option(if (strict) "StrictHostKeyChecking=yes" else "StrictHostKeyChecking=accept-new");
    try result.append("-o");
    const known = try configPath(gpa, known_hosts_override orelse target.known_hosts_file);
    defer gpa.free(known);
    try result.formatted("UserKnownHostsFile={s}", .{known});
    try result.option("GlobalKnownHostsFile=none");
    try result.option("HashKnownHosts=no");
    try result.append("-o");
    try result.formatted("HostKeyAlias={s}", .{target.host_key_alias});
    if (target.user) |user| {
        try result.append("-l");
        try result.append(user);
    }
    if (target.port) |port| {
        try result.append("-p");
        try result.formatted("{d}", .{port});
    }
    if (target.identity_file) |path| {
        const identity = try configPath(gpa, path);
        defer gpa.free(identity);
        try result.append("-o");
        try result.formatted("IdentityFile={s}", .{identity});
        try result.option("IdentitiesOnly=yes");
    }
    try result.append("--");
    try result.append(target.host);
    return result;
}
pub const Platform = enum { linux, android, darwin, windows };
pub const Architecture = enum { x64, arm64 };
pub const Remote = struct { platform: Platform, arch: Architecture, home: []const u8 };
pub const Probe = struct { system: []const u8, machine: []const u8, os: []const u8, home: []const u8, tmpdir: []const u8 = "-", preload: []const u8 = "-" };
/// Slices borrow the probe output; callers that retain the remote must own it.
pub fn parseProbe(output: []const u8) !Probe {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (!std.mem.eql(u8, std.mem.trimEnd(u8, line, "\r"), "PI-ENV-PROBE")) continue;
        return .{ .system = std.mem.trimEnd(u8, lines.next() orelse "", "\r"), .machine = std.mem.trimEnd(u8, lines.next() orelse "", "\r"), .os = std.mem.trimEnd(u8, lines.next() orelse "", "\r"), .home = std.mem.trimEnd(u8, lines.next() orelse "", "\r"), .tmpdir = std.mem.trimEnd(u8, lines.next() orelse "-", "\r"), .preload = std.mem.trimEnd(u8, lines.next() orelse "-", "\r") };
    }
    return error.UnexpectedRemoteProbe;
}
pub fn classify(probe: Probe) !Remote {
    const arch: Architecture = if (std.ascii.eqlIgnoreCase(probe.machine, "x86_64") or std.ascii.eqlIgnoreCase(probe.machine, "amd64") or std.ascii.eqlIgnoreCase(probe.machine, "x64")) .x64 else if (std.ascii.eqlIgnoreCase(probe.machine, "aarch64") or std.ascii.eqlIgnoreCase(probe.machine, "arm64")) .arm64 else return error.UnsupportedRemoteArchitecture;
    const platform: Platform = if (std.mem.eql(u8, probe.system, "Windows")) .windows else if (std.mem.eql(u8, probe.system, "Darwin")) .darwin else if (std.mem.eql(u8, probe.system, "Linux")) if (std.mem.eql(u8, probe.os, "Android")) .android else .linux else return error.UnsupportedRemoteSystem;
    return .{ .platform = platform, .arch = arch, .home = probe.home };
}
pub fn needsWindowsProbe(probe: Probe) bool {
    for ([_][]const u8{ "MINGW", "MSYS", "CYGWIN" }) |prefix| if (std.mem.startsWith(u8, probe.system, prefix)) return true;
    return false;
}
pub fn packagedDaemon(gpa: std.mem.Allocator, package_root: []const u8, platform: Platform, arch: Architecture) ![]u8 {
    const directory = try std.fmt.allocPrint(gpa, "pi-env-{s}-{s}", .{ @tagName(platform), @tagName(arch) });
    defer gpa.free(directory);
    return std.fs.path.join(gpa, &.{ package_root, "bin", directory, if (platform == .windows) "pi-env.exe" else "pi-env" });
}
pub fn quotePosix(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSshArgument;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);
    try output.append(gpa, '\'');
    for (text) |byte| try output.appendSlice(gpa, if (byte == '\'') "'\\''" else &.{byte});
    try output.append(gpa, '\'');
    return output.toOwnedSlice(gpa);
}
test "SSH arguments retain strict private host trust no forwarding locale and literal paths" {
    const gpa = std.testing.allocator;
    var args = try arguments(gpa, .{ .host = "gpu-box", .known_hosts_file = "C:\\private space\\known_hosts", .host_key_alias = "pi-env-gpu", .user = "owner", .port = 2222, .identity_file = "id with space", .config_file = "config with space" }, true, null);
    defer args.deinit();
    const capture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/node-b7df-contracts.json"), .{});
    defer capture.deinit();
    const expected = capture.value.object.get("args").?.array.items[0].array.items;
    try std.testing.expectEqual(expected.len, args.values.items.len);
    for (expected, args.values.items) |wanted, actual| try std.testing.expectEqualStrings(wanted.string, actual);
    var scan = try arguments(gpa, .{ .host = "gpu", .known_hosts_file = "real", .host_key_alias = "fixed" }, false, "temporary");
    defer scan.deinit();
    const expected_scan = capture.value.object.get("args").?.array.items[1].array.items;
    try std.testing.expectEqual(expected_scan.len, scan.values.items.len);
    for (expected_scan, scan.values.items) |wanted, actual| try std.testing.expectEqualStrings(wanted.string, actual);
}
test "SSH rejects option injection whitespace control characters invalid ports and embedded NUL paths" {
    for ([_][]const u8{ "", "-oProxyCommand=bad", "host name", "host\n", "\x00", "host\x7f", "host\xc2\xa0", "host\xef\xbb\xbf", "\xff" }) |text| try std.testing.expectError(error.InvalidSshField, validateField(text));
    try validateField("owner@example.org");
    try validateField("[::1]");
    for ([_]u32{ 0, 65536, 0xffffffff }) |port| try std.testing.expectError(error.InvalidSshPort, arguments(std.testing.allocator, .{ .host = "gpu", .host_key_alias = "fixed", .known_hosts_file = "known", .port = port }, true, null));
    try std.testing.expectError(error.InvalidSshArgument, arguments(std.testing.allocator, .{ .host = "gpu", .host_key_alias = "fixed", .known_hosts_file = "bad\x00path" }, true, null));
}
test "SSH platform probe accepts banners CRLF architecture aliases and Windows shell fallback" {
    const probe = try parseProbe("login banner\r\nPI-ENV-PROBE\r\nLinux\r\nAARCH64\r\nAndroid\r\n/data/data/com.termux/files/home\r\n");
    const remote = try classify(probe);
    try std.testing.expectEqual(Platform.android, remote.platform);
    try std.testing.expectEqual(Architecture.arm64, remote.arch);
    try std.testing.expectEqualStrings("/data/data/com.termux/files/home", remote.home);
    try std.testing.expectError(error.UnexpectedRemoteProbe, parseProbe("banner only"));
    try std.testing.expectError(error.UnsupportedRemoteArchitecture, classify(.{ .system = "Linux", .machine = "i686", .os = "GNU/Linux", .home = "/home/u" }));
    try std.testing.expect(needsWindowsProbe(.{ .system = "MINGW64_NT", .machine = "x86_64", .os = "-", .home = "/c/u" }));
    const windows = try classify(try parseProbe("PI-ENV-PROBE\nWindows\nX64\n-\nC:\\Users\\u\n"));
    try std.testing.expectEqual(Platform.windows, windows.platform);
    const quoted = try quotePosix(std.testing.allocator, "/home/o'neil/path $(literal)");
    defer std.testing.allocator.free(quoted);
    try std.testing.expectEqualStrings("'/home/o'\\''neil/path $(literal)'", quoted);
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    var args = try arguments(gpa, .{ .host = "gpu", .host_key_alias = "fixed", .known_hosts_file = "known", .user = "owner", .port = 65535, .identity_file = "key", .config_file = "config" }, true, null);
    defer args.deinit();
    const path = try packagedDaemon(gpa, "/package", .windows, .arm64);
    defer gpa.free(path);
    const quoted = try quotePosix(gpa, "a'b");
    defer gpa.free(quoted);
}
test "SSH argument platform-path and quoting allocation failures release all owned values" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
