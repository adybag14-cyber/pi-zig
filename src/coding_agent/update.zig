//! Upstream Pi release discovery, changelog projection, and anonymous install
//! lifecycle reporting. All network traffic uses the shared bounded bootstrap
//! transport so retry, timeout, proxy, NO_PROXY, and cancellation semantics
//! match OAuth/catalog management requests.
const std = @import("std");
const Io = std.Io;
const bootstrap_http = @import("../ai/bootstrap_http.zig");
const config = @import("../config.zig");

pub const latest_version_url = "https://pi.dev/api/latest-version";
pub const report_install_url = "https://pi.dev/api/report-install";
pub const startup_version_timeout_ms: u64 = 1_500;
pub const explicit_version_timeout_ms: u64 = 10_000;
pub const install_report_timeout_ms: u64 = 5_000;
pub const max_changelog_bytes: usize = 256 * 1024;

const bundled_changelog = @embedFile("assets/UPSTREAM-CHANGELOG.md");

pub const LatestRelease = struct {
    version: []u8,
    package_name: ?[]u8 = null,
    note: ?[]u8 = null,

    pub fn deinit(self: *LatestRelease, gpa: std.mem.Allocator) void {
        gpa.free(self.version);
        if (self.package_name) |value| gpa.free(value);
        if (self.note) |value| gpa.free(value);
        self.* = undefined;
    }
};

pub const FetchOptions = struct {
    endpoint: ?[]const u8 = null,
    timeout_ms: u64 = explicit_version_timeout_ms,
    retry: bool = false,
    environ: ?*const std.process.Environ.Map = null,
    setting_proxy: ?[]const u8 = null,
    abort_flag: ?*bool = null,
};

pub const StartupLifecycle = struct {
    changelog: ?[]u8 = null,
    recorded_version: bool = false,
    report_install: bool = false,

    pub fn deinit(self: *StartupLifecycle, gpa: std.mem.Allocator) void {
        if (self.changelog) |value| gpa.free(value);
        self.* = undefined;
    }
};

const ParsedVersion = struct {
    major: u64,
    minor: u64,
    patch: u64,
    prerelease: ?[]const u8,
};

fn parseVersion(raw_value: []const u8) ?ParsedVersion {
    var raw = std.mem.trim(u8, raw_value, " \t\r\n");
    if (raw.len > 0 and (raw[0] == 'v' or raw[0] == 'V')) raw = raw[1..];
    if (raw.len == 0) return null;
    const build_index = std.mem.indexOfScalar(u8, raw, '+') orelse raw.len;
    const without_build = raw[0..build_index];
    const pre_index = std.mem.indexOfScalar(u8, without_build, '-');
    const core = if (pre_index) |index| without_build[0..index] else without_build;
    const prerelease = if (pre_index) |index| blk: {
        if (index + 1 >= without_build.len) return null;
        break :blk without_build[index + 1 ..];
    } else null;

    var parts = std.mem.splitScalar(u8, core, '.');
    const major_text = parts.next() orelse return null;
    const minor_text = parts.next() orelse return null;
    const patch_text = parts.next() orelse return null;
    if (parts.next() != null or major_text.len == 0 or minor_text.len == 0 or patch_text.len == 0) return null;
    if ((major_text.len > 1 and major_text[0] == '0') or
        (minor_text.len > 1 and minor_text[0] == '0') or
        (patch_text.len > 1 and patch_text[0] == '0')) return null;

    return .{
        .major = std.fmt.parseUnsigned(u64, major_text, 10) catch return null,
        .minor = std.fmt.parseUnsigned(u64, minor_text, 10) catch return null,
        .patch = std.fmt.parseUnsigned(u64, patch_text, 10) catch return null,
        .prerelease = prerelease,
    };
}

fn numericIdentifier(value: []const u8) ?u64 {
    if (value.len == 0) return null;
    if (value.len > 1 and value[0] == '0') return null;
    for (value) |byte| if (!std.ascii.isDigit(byte)) return null;
    return std.fmt.parseUnsigned(u64, value, 10) catch null;
}

fn comparePrerelease(left: ?[]const u8, right: ?[]const u8) std.math.Order {
    if (left == null and right == null) return .eq;
    if (left == null) return .gt;
    if (right == null) return .lt;
    var left_parts = std.mem.splitScalar(u8, left.?, '.');
    var right_parts = std.mem.splitScalar(u8, right.?, '.');
    while (true) {
        const l = left_parts.next();
        const r = right_parts.next();
        if (l == null and r == null) return .eq;
        if (l == null) return .lt;
        if (r == null) return .gt;
        const ln = numericIdentifier(l.?);
        const rn = numericIdentifier(r.?);
        if (ln != null and rn != null) {
            if (ln.? < rn.?) return .lt;
            if (ln.? > rn.?) return .gt;
            continue;
        }
        if (ln != null) return .lt;
        if (rn != null) return .gt;
        const ordered = std.mem.order(u8, l.?, r.?);
        if (ordered != .eq) return ordered;
    }
}

pub fn comparePackageVersions(left_raw: []const u8, right_raw: []const u8) ?std.math.Order {
    const left = parseVersion(left_raw) orelse return null;
    const right = parseVersion(right_raw) orelse return null;
    if (left.major < right.major) return .lt;
    if (left.major > right.major) return .gt;
    if (left.minor < right.minor) return .lt;
    if (left.minor > right.minor) return .gt;
    if (left.patch < right.patch) return .lt;
    if (left.patch > right.patch) return .gt;
    return comparePrerelease(left.prerelease, right.prerelease);
}

pub fn isNewerPackageVersion(candidate: []const u8, current: []const u8) bool {
    if (comparePackageVersions(candidate, current)) |order| return order == .gt;
    return !std.mem.eql(u8, std.mem.trim(u8, candidate, " \t\r\n"), std.mem.trim(u8, current, " \t\r\n"));
}

pub fn truthyEnv(value: ?[]const u8) bool {
    const raw = value orelse return false;
    return std.mem.eql(u8, raw, "1") or std.ascii.eqlIgnoreCase(raw, "true") or std.ascii.eqlIgnoreCase(raw, "yes");
}

pub fn telemetryEnabled(environ: *const std.process.Environ.Map, setting: ?bool) bool {
    if (environ.get("PI_TELEMETRY")) |value| return truthyEnv(value);
    return setting orelse true;
}

pub fn offline(environ: *const std.process.Environ.Map) bool {
    return environ.get("PI_OFFLINE") != null;
}

pub fn shouldCheckVersion(environ: *const std.process.Environ.Map) bool {
    return !offline(environ) and environ.get("PI_SKIP_VERSION_CHECK") == null;
}

pub fn effectiveLatestUrl(environ: ?*const std.process.Environ.Map) []const u8 {
    if (environ) |map| if (map.get("PI_LATEST_VERSION_URL")) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len > 0) return trimmed;
    };
    return latest_version_url;
}

pub fn effectiveReportUrl(environ: ?*const std.process.Environ.Map) []const u8 {
    if (environ) |map| if (map.get("PI_REPORT_INSTALL_URL")) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len > 0) return trimmed;
    };
    return report_install_url;
}

fn requestOptions(options: FetchOptions) bootstrap_http.Options {
    return .{
        .policy = .{
            .timeout_ms = options.timeout_ms,
            .max_retries = if (options.retry) 2 else 0,
            .max_retry_delay_ms = 60_000,
        },
        .abort_flag = options.abort_flag,
        .proxy = .{
            .environ = options.environ,
            .setting = options.setting_proxy,
        },
    };
}

pub fn userAgent(gpa: std.mem.Allocator, upstream_version: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "pi-coding-agent/{s} pi-zig/{s}", .{ upstream_version, config.version });
}

pub fn getLatestRelease(
    gpa: std.mem.Allocator,
    io: Io,
    current_version: []const u8,
    options: FetchOptions,
) !?LatestRelease {
    const endpoint = options.endpoint orelse effectiveLatestUrl(options.environ);
    const ua = try userAgent(gpa, current_version);
    defer gpa.free(ua);
    const headers = [_]std.http.Header{
        .{ .name = "user-agent", .value = ua },
        .{ .name = "accept", .value = "application/json" },
    };
    var response = try bootstrap_http.request(gpa, io, .{
        .url = endpoint,
        .headers = &headers,
        .options = requestOptions(options),
    });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return null;

    var parsed = std.json.parseFromSlice(std.json.Value, gpa, response.body, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const version_value = parsed.value.object.get("version") orelse return null;
    if (version_value != .string) return null;
    const version = std.mem.trim(u8, version_value.string, " \t\r\n");
    if (version.len == 0) return null;

    var release = LatestRelease{ .version = try gpa.dupe(u8, version) };
    errdefer release.deinit(gpa);
    if (parsed.value.object.get("packageName")) |package_value| if (package_value == .string) {
        const package_name = std.mem.trim(u8, package_value.string, " \t\r\n");
        if (package_name.len > 0) release.package_name = try gpa.dupe(u8, package_name);
    };
    if (parsed.value.object.get("note")) |note_value| if (note_value == .string) {
        const note = std.mem.trim(u8, note_value.string, " \t\r\n");
        if (note.len > 0) release.note = try gpa.dupe(u8, note);
    };
    return release;
}

fn appendPercentEncoded(writer: *std.Io.Writer, value: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~') {
            try writer.writeByte(byte);
        } else {
            try writer.writeByte('%');
            try writer.writeByte(hex[byte >> 4]);
            try writer.writeByte(hex[byte & 0x0f]);
        }
    }
}

pub fn reportInstall(
    gpa: std.mem.Allocator,
    io: Io,
    version: []const u8,
    options: FetchOptions,
) !bool {
    const endpoint = options.endpoint orelse effectiveReportUrl(options.environ);
    var url: std.Io.Writer.Allocating = .init(gpa);
    defer url.deinit();
    try url.writer.writeAll(endpoint);
    try url.writer.writeByte(if (std.mem.indexOfScalar(u8, endpoint, '?') == null) '?' else '&');
    try url.writer.writeAll("version=");
    try appendPercentEncoded(&url.writer, version);

    const ua = try userAgent(gpa, version);
    defer gpa.free(ua);
    const headers = [_]std.http.Header{.{ .name = "user-agent", .value = ua }};
    var response = try bootstrap_http.request(gpa, io, .{
        .url = url.written(),
        .headers = &headers,
        .options = requestOptions(options),
    });
    defer response.deinit(gpa);
    return response.status >= 200 and response.status < 300;
}

fn parseHeaderVersion(line: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, "## ")) return null;
    var rest = std.mem.trimStart(u8, line[3..], " \t");
    if (rest.len > 0 and rest[0] == '[') {
        const close = std.mem.indexOfScalar(u8, rest, ']') orelse return null;
        rest = rest[1..close];
    } else {
        const end = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
        rest = rest[0..end];
    }
    return if (parseVersion(rest) != null) rest else null;
}

/// Return changelog sections newer than `last_version` and no newer than
/// `current_version`, retaining the upstream newest-first order.
pub fn collectNewChangelog(
    gpa: std.mem.Allocator,
    changelog: []const u8,
    last_version: []const u8,
    current_version: []const u8,
) !?[]u8 {
    if (comparePackageVersions(last_version, current_version)) |order| if (order != .lt) return null;
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    var section_start: ?usize = null;
    var section_version: ?[]const u8 = null;
    var line_start: usize = 0;
    while (line_start <= changelog.len) {
        const relative_end = std.mem.indexOfScalar(u8, changelog[line_start..], '\n');
        const line_end = if (relative_end) |offset| line_start + offset else changelog.len;
        const line = std.mem.trimEnd(u8, changelog[line_start..line_end], "\r");
        if (std.mem.startsWith(u8, line, "## ")) {
            if (section_start) |start| if (section_version) |version| {
                const newer_than_last = comparePackageVersions(version, last_version) orelse .eq;
                const no_newer_than_current = comparePackageVersions(version, current_version) orelse .gt;
                if (newer_than_last == .gt and (no_newer_than_current == .lt or no_newer_than_current == .eq)) {
                    if (output.written().len > 0) try output.writer.writeAll("\n\n");
                    const end = line_start -| 1;
                    const section = std.mem.trim(u8, changelog[start..end], " \t\r\n");
                    if (output.written().len + section.len > max_changelog_bytes) return error.ChangelogTooLarge;
                    try output.writer.writeAll(section);
                }
            };
            section_start = line_start;
            section_version = parseHeaderVersion(line);
        }
        if (line_end == changelog.len) break;
        line_start = line_end + 1;
    }

    if (section_start) |start| if (section_version) |version| {
        const newer_than_last = comparePackageVersions(version, last_version) orelse .eq;
        const no_newer_than_current = comparePackageVersions(version, current_version) orelse .gt;
        if (newer_than_last == .gt and (no_newer_than_current == .lt or no_newer_than_current == .eq)) {
            if (output.written().len > 0) try output.writer.writeAll("\n\n");
            const section = std.mem.trim(u8, changelog[start..], " \t\r\n");
            if (output.written().len + section.len > max_changelog_bytes) return error.ChangelogTooLarge;
            try output.writer.writeAll(section);
        }
    };

    if (output.written().len == 0) {
        output.deinit();
        return null;
    }
    return try output.toOwnedSlice();
}

pub fn bundledChangelog() []const u8 {
    return bundled_changelog;
}

pub fn bundledNewChangelog(gpa: std.mem.Allocator, last_version: []const u8, current_version: []const u8) !?[]u8 {
    return collectNewChangelog(gpa, bundled_changelog, last_version, current_version);
}

pub fn startupLifecycle(
    gpa: std.mem.Allocator,
    last_version: ?[]const u8,
    current_version: []const u8,
    resumed: bool,
) !StartupLifecycle {
    if (resumed) return .{};
    const previous = last_version orelse return .{ .recorded_version = true, .report_install = true };
    const comparison: std.math.Order = comparePackageVersions(previous, current_version) orelse if (std.mem.eql(u8, previous, current_version)) .eq else .lt;
    if (comparison != .lt) return .{};
    return .{
        .changelog = try bundledNewChangelog(gpa, previous, current_version),
        .recorded_version = true,
        .report_install = true,
    };
}

test "semantic versions include prerelease precedence and fallback inequality" {
    try std.testing.expectEqual(std.math.Order.lt, comparePackageVersions("0.84.1-alpha.2", "0.84.1-alpha.10").?);
    try std.testing.expectEqual(std.math.Order.lt, comparePackageVersions("v0.84.1-rc.1", "0.84.1").?);
    try std.testing.expectEqual(std.math.Order.gt, comparePackageVersions("0.85.0", "0.84.99").?);
    try std.testing.expect(comparePackageVersions("not-semver", "0.84.1") == null);
    try std.testing.expect(isNewerPackageVersion("build-next", "build-current"));
}

test "latest release parser and install URL use owned normalized values" {
    try std.testing.expectEqualStrings(latest_version_url, effectiveLatestUrl(null));
    try std.testing.expectEqualStrings(report_install_url, effectiveReportUrl(null));
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("PI_LATEST_VERSION_URL", "  http://127.0.0.1/latest  ");
    try env.put("PI_REPORT_INSTALL_URL", "http://127.0.0.1/report?source=test");
    try std.testing.expectEqualStrings("http://127.0.0.1/latest", effectiveLatestUrl(&env));
    try std.testing.expectEqualStrings("http://127.0.0.1/report?source=test", effectiveReportUrl(&env));
}

test "changelog parser retains only bounded newer released sections" {
    const sample =
        \\# Changelog
        \\
        \\## [Unreleased]
        \\ignore
        \\
        \\## [0.84.1]
        \\new one
        \\
        \\## [0.84.0]
        \\new zero
        \\
        \\## [0.83.0]
        \\old
    ;
    const out = (try collectNewChangelog(std.testing.allocator, sample, "0.83.0", "0.84.1")).?;
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "0.84.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "0.84.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Unreleased") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "## [0.83.0]") == null);
}

test "startup lifecycle records fresh installs and skips resumed sessions" {
    const fresh = try startupLifecycle(std.testing.allocator, null, config.upstream_version, false);
    try std.testing.expect(fresh.recorded_version);
    try std.testing.expect(fresh.report_install);
    var resumed = try startupLifecycle(std.testing.allocator, "0.1.0", config.upstream_version, true);
    defer resumed.deinit(std.testing.allocator);
    try std.testing.expect(!resumed.recorded_version);
}

pub const InstallMethod = enum { npm, pnpm, yarn, bun, unknown };

pub const SelfUpdateTarget = struct {
    installed_package_name: []const u8,
    package_name: []const u8,
    install_spec: []const u8,
};

pub const SelfUpdateBuildOptions = struct {
    method: InstallMethod,
    configured_command: ?[]const []const u8 = null,
    npm_prefix: ?[]const u8 = null,
    pnpm_global_bin_dir: ?[]const u8 = null,
    target: SelfUpdateTarget,
};

pub const SelfUpdateStep = struct {
    gpa: std.mem.Allocator,
    argv: []const []const u8,

    pub fn deinit(self: *SelfUpdateStep) void {
        for (self.argv) |part| self.gpa.free(part);
        self.gpa.free(self.argv);
        self.* = undefined;
    }

    fn writeDisplay(self: *const SelfUpdateStep, writer: *std.Io.Writer) !void {
        for (self.argv, 0..) |part, index| {
            if (index > 0) try writer.writeByte(' ');
            if (std.mem.indexOfAny(u8, part, " \t\r\n\"") == null) {
                try writer.writeAll(part);
            } else {
                try writer.writeByte('"');
                for (part) |byte| {
                    if (byte == '"' or byte == '\\') try writer.writeByte('\\');
                    try writer.writeByte(byte);
                }
                try writer.writeByte('"');
            }
        }
    }
};

pub const SelfUpdateCommand = struct {
    gpa: std.mem.Allocator,
    steps: []SelfUpdateStep,

    pub fn deinit(self: *SelfUpdateCommand) void {
        for (self.steps) |*step| step.deinit();
        self.gpa.free(self.steps);
        self.* = undefined;
    }

    pub fn display(self: *const SelfUpdateCommand, gpa: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(gpa);
        errdefer out.deinit();
        for (self.steps, 0..) |*step, index| {
            if (index > 0) try out.writer.writeAll(" && ");
            try step.writeDisplay(&out.writer);
        }
        return out.toOwnedSlice();
    }
};

pub fn detectInstallMethod(executable_path: []const u8, npm_command: ?[]const []const u8) InstallMethod {
    var lowered_buf: [8192]u8 = undefined;
    const path = executable_path[0..@min(executable_path.len, lowered_buf.len)];
    for (path, 0..) |byte, index| lowered_buf[index] = if (byte == '\\') '/' else std.ascii.toLower(byte);
    const lowered = lowered_buf[0..path.len];
    if (std.mem.indexOf(u8, lowered, "/.pnpm/") != null or std.mem.indexOf(u8, lowered, "/pnpm/global/") != null) return .pnpm;
    if (std.mem.indexOf(u8, lowered, "/.yarn/") != null or std.mem.indexOf(u8, lowered, "/yarn/global/") != null) return .yarn;
    if (std.mem.indexOf(u8, lowered, "/install/global/node_modules/") != null) return .bun;
    if (std.mem.indexOf(u8, lowered, "/npm/node_modules/") != null or std.mem.indexOf(u8, lowered, "/lib/node_modules/") != null) return .npm;
    // A configured wrapper is useful for command construction, but it does not
    // prove that an arbitrary executable is owned by that package manager.
    _ = npm_command;
    return .unknown;
}

pub fn inferNpmPrefix(gpa: std.mem.Allocator, executable_path: []const u8) !?[]u8 {
    if (@import("builtin").os.tag == .windows or std.mem.indexOfScalar(u8, executable_path, '\\') != null) return null;
    const marker = "/node_modules/";
    const index = std.mem.indexOf(u8, executable_path, marker) orelse return null;
    const root = executable_path[0 .. index + marker.len - 1];
    const root_parent = std.fs.path.dirname(root) orelse return null;
    if (!std.mem.eql(u8, std.fs.path.basename(root_parent), "lib")) return null;
    const prefix = std.fs.path.dirname(root_parent) orelse return null;
    return try gpa.dupe(u8, prefix);
}

pub fn inferPnpmGlobalBinDir(gpa: std.mem.Allocator, executable_path: []const u8) !?[]u8 {
    var normalized = try gpa.dupe(u8, executable_path);
    defer gpa.free(normalized);
    for (normalized) |*byte| {
        if (byte.* == '\\') byte.* = '/';
    }
    const pnpm_index = std.mem.indexOf(u8, normalized, "/.pnpm/") orelse return null;
    const before = normalized[0..pnpm_index];
    const global_index = std.mem.lastIndexOf(u8, before, "/global/") orelse return null;
    const version_tail = before[global_index + "/global/".len ..];
    if (version_tail.len == 0 or std.mem.indexOfScalar(u8, version_tail, '/') != null) return null;
    return try gpa.dupe(u8, before[0..global_index]);
}

pub fn isSafeManagedInstallPath(method: InstallMethod, executable_path: []const u8) bool {
    var normalized_buf: [8192]u8 = undefined;
    if (executable_path.len > normalized_buf.len) return false;
    for (executable_path, 0..) |byte, index| normalized_buf[index] = if (byte == '\\') '/' else std.ascii.toLower(byte);
    const normalized = normalized_buf[0..executable_path.len];
    return switch (method) {
        .npm => std.mem.indexOf(u8, normalized, "/lib/node_modules/") != null or
            std.mem.indexOf(u8, normalized, "/appdata/roaming/npm/node_modules/") != null or
            std.mem.indexOf(u8, normalized, "/npm/node_modules/") != null,
        .pnpm => std.mem.indexOf(u8, normalized, "/global/") != null and std.mem.indexOf(u8, normalized, "/.pnpm/") != null,
        .yarn => std.mem.indexOf(u8, normalized, "/yarn/global/") != null or std.mem.indexOf(u8, normalized, "/.yarn/") != null,
        .bun => std.mem.indexOf(u8, normalized, "/install/global/node_modules/") != null,
        .unknown => false,
    };
}

fn packageDirFromExecutable(executable_path: []const u8) []const u8 {
    const Marker = struct { index: usize, len: usize };
    const marker: Marker = if (std.mem.lastIndexOf(u8, executable_path, "/node_modules/")) |index|
        .{ .index = index, .len = "/node_modules/".len }
    else if (std.mem.lastIndexOf(u8, executable_path, "\\node_modules\\")) |index|
        .{ .index = index, .len = "\\node_modules\\".len }
    else
        return std.fs.path.dirname(executable_path) orelse executable_path;
    const tail_start = marker.index + marker.len;
    const tail = executable_path[tail_start..];
    var segment_count: usize = if (tail.len > 0 and tail[0] == '@') 2 else 1;
    var cursor: usize = 0;
    while (segment_count > 0 and cursor < tail.len) : (segment_count -= 1) {
        const next = std.mem.indexOfAnyPos(u8, tail, cursor, "/\\") orelse return executable_path[0 .. tail_start + tail.len];
        cursor = next + 1;
    }
    return executable_path[0 .. tail_start + @max(cursor, @as(usize, 1)) - 1];
}

pub fn isSelfUpdatePathWritable(io: Io, executable_path: []const u8) bool {
    const package_dir = packageDirFromExecutable(executable_path);
    const parent = std.fs.path.dirname(package_dir) orelse package_dir;
    const dir: std.Io.Dir = .cwd();
    dir.access(io, package_dir, .{ .write = true }) catch return false;
    dir.access(io, parent, .{ .write = true }) catch return false;
    return true;
}

fn cloneStep(gpa: std.mem.Allocator, parts: []const []const u8) !SelfUpdateStep {
    const result = try gpa.alloc([]const u8, parts.len);
    var initialized: usize = 0;
    errdefer {
        for (result[0..initialized]) |part| gpa.free(part);
        gpa.free(result);
    }
    for (parts, 0..) |part, index| {
        result[index] = try gpa.dupe(u8, part);
        initialized += 1;
    }
    return .{ .gpa = gpa, .argv = result };
}

fn appendOwnedStep(gpa: std.mem.Allocator, steps: *std.ArrayList(SelfUpdateStep), parts: []const []const u8) !void {
    var step = try cloneStep(gpa, parts);
    errdefer step.deinit();
    try steps.append(gpa, step);
}

pub fn buildSelfUpdateCommand(gpa: std.mem.Allocator, options: SelfUpdateBuildOptions) !?SelfUpdateCommand {
    if (options.method == .unknown) return null;
    var steps: std.ArrayList(SelfUpdateStep) = .empty;
    errdefer {
        for (steps.items) |*step| step.deinit();
        steps.deinit(gpa);
    }
    const renamed = !std.mem.eql(u8, options.target.installed_package_name, options.target.package_name);

    switch (options.method) {
        .npm => {
            var prefix: std.ArrayList([]const u8) = .empty;
            defer prefix.deinit(gpa);
            if (options.configured_command) |command| {
                if (command.len == 0) return null;
                try prefix.appendSlice(gpa, command);
            } else {
                try prefix.append(gpa, "npm");
                if (options.npm_prefix) |value| try prefix.appendSlice(gpa, &.{ "--prefix", value });
            }
            if (renamed) {
                var uninstall: std.ArrayList([]const u8) = .empty;
                defer uninstall.deinit(gpa);
                try uninstall.appendSlice(gpa, prefix.items);
                try uninstall.appendSlice(gpa, &.{ "uninstall", "-g", options.target.installed_package_name });
                try appendOwnedStep(gpa, &steps, uninstall.items);
            }
            var install: std.ArrayList([]const u8) = .empty;
            defer install.deinit(gpa);
            try install.appendSlice(gpa, prefix.items);
            try install.appendSlice(gpa, &.{ "install", "-g", "--ignore-scripts", "--min-release-age=0", options.target.install_spec });
            try appendOwnedStep(gpa, &steps, install.items);
        },
        .pnpm => {
            const global_arg = if (options.pnpm_global_bin_dir) |value|
                try std.fmt.allocPrint(gpa, "--config.global-bin-dir={s}", .{value})
            else
                null;
            defer if (global_arg) |value| gpa.free(value);
            if (renamed) {
                var uninstall: std.ArrayList([]const u8) = .empty;
                defer uninstall.deinit(gpa);
                try uninstall.appendSlice(gpa, &.{ "pnpm", "remove", "-g" });
                if (global_arg) |value| try uninstall.append(gpa, value);
                try uninstall.append(gpa, options.target.installed_package_name);
                try appendOwnedStep(gpa, &steps, uninstall.items);
            }
            var install: std.ArrayList([]const u8) = .empty;
            defer install.deinit(gpa);
            try install.appendSlice(gpa, &.{ "pnpm", "install", "-g", "--ignore-scripts", "--config.minimumReleaseAge=0" });
            if (global_arg) |value| try install.append(gpa, value);
            try install.append(gpa, options.target.install_spec);
            try appendOwnedStep(gpa, &steps, install.items);
        },
        .yarn => {
            if (renamed) try appendOwnedStep(gpa, &steps, &.{ "yarn", "global", "remove", options.target.installed_package_name });
            try appendOwnedStep(gpa, &steps, &.{ "yarn", "global", "add", "--ignore-scripts", options.target.install_spec });
        },
        .bun => {
            if (renamed) try appendOwnedStep(gpa, &steps, &.{ "bun", "uninstall", "-g", options.target.installed_package_name });
            try appendOwnedStep(gpa, &steps, &.{ "bun", "install", "-g", "--ignore-scripts", "--minimum-release-age=0", options.target.install_spec });
        },
        .unknown => unreachable,
    }
    return .{ .gpa = gpa, .steps = try steps.toOwnedSlice(gpa) };
}

pub fn executeSelfUpdate(gpa: std.mem.Allocator, io: Io, command: *const SelfUpdateCommand) !void {
    for (command.steps) |step| {
        const result = try std.process.run(gpa, io, .{
            .argv = step.argv,
            .stdout_limit = .limited(4 * 1024 * 1024),
            .stderr_limit = .limited(4 * 1024 * 1024),
        });
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        switch (result.term) {
            .exited => |code| if (code != 0) return error.SelfUpdateFailed,
            else => return error.SelfUpdateFailed,
        }
    }
}

test "self update manager detection preserves global install safety" {
    try std.testing.expectEqual(InstallMethod.pnpm, detectInstallMethod("/opt/pnpm/global/5/.pnpm/pkg/node_modules/pi", null));
    try std.testing.expectEqual(InstallMethod.npm, detectInstallMethod("/usr/lib/node_modules/pi/dist/index.js", null));
    try std.testing.expectEqual(InstallMethod.bun, detectInstallMethod("/home/u/.bun/install/global/node_modules/pi/bin/pi", null));
    try std.testing.expectEqual(InstallMethod.unknown, detectInstallMethod("/work/node_modules/pi/bin/pi", null));
    const wrapper = [_][]const u8{ "mise", "exec", "node@22", "--", "pnpm" };
    try std.testing.expectEqual(InstallMethod.unknown, detectInstallMethod("/usr/local/bin/pi", &wrapper));
    try std.testing.expect(isSafeManagedInstallPath(.npm, "/usr/lib/node_modules/pi/bin/pi"));
    try std.testing.expect(!isSafeManagedInstallPath(.npm, "/work/node_modules/pi/bin/pi"));
}

test "self update commands support package rename wrappers and prefixes" {
    const target: SelfUpdateTarget = .{
        .installed_package_name = "@earendil-works/pi-coding-agent",
        .package_name = "@scope/new-pi",
        .install_spec = "@scope/new-pi@0.85.0",
    };
    const wrapper = [_][]const u8{ "mise", "exec", "node@22", "--", "npm" };
    var wrapped = (try buildSelfUpdateCommand(std.testing.allocator, .{
        .method = .npm,
        .configured_command = &wrapper,
        .target = target,
    })).?;
    defer wrapped.deinit();
    try std.testing.expectEqual(@as(usize, 2), wrapped.steps.len);
    try std.testing.expectEqualStrings("uninstall", wrapped.steps[0].argv[5]);
    try std.testing.expectEqualStrings("install", wrapped.steps[1].argv[5]);
    const display = try wrapped.display(std.testing.allocator);
    defer std.testing.allocator.free(display);
    try std.testing.expect(std.mem.indexOf(u8, display, " && ") != null);

    var prefixed = (try buildSelfUpdateCommand(std.testing.allocator, .{
        .method = .npm,
        .npm_prefix = "/opt/custom node",
        .target = .{
            .installed_package_name = "pi",
            .package_name = "pi",
            .install_spec = "pi@0.85.0",
        },
    })).?;
    defer prefixed.deinit();
    try std.testing.expectEqualStrings("--prefix", prefixed.steps[0].argv[1]);
    try std.testing.expectEqualStrings("/opt/custom node", prefixed.steps[0].argv[2]);
    const prefixed_display = try prefixed.display(std.testing.allocator);
    defer std.testing.allocator.free(prefixed_display);
    try std.testing.expect(std.mem.indexOf(u8, prefixed_display, "\"/opt/custom node\"") != null);
}

test "self update prefix and pnpm global bin inference mirror global layouts" {
    if (@import("builtin").os.tag != .windows) {
        const prefix = (try inferNpmPrefix(std.testing.allocator, "/opt/pi/lib/node_modules/@scope/pi/bin/pi")).?;
        defer std.testing.allocator.free(prefix);
        try std.testing.expectEqualStrings("/opt/pi", prefix);
    }
    const pnpm_home = (try inferPnpmGlobalBinDir(std.testing.allocator, "/home/u/.local/share/pnpm/global/5/.pnpm/pi@1/node_modules/pi/bin/pi")).?;
    defer std.testing.allocator.free(pnpm_home);
    try std.testing.expectEqualStrings("/home/u/.local/share/pnpm", pnpm_home);
}

pub const UpdateTarget = union(enum) {
    self,
    all,
    models,
    extensions: ?[]const u8,
};

pub const CommandOptions = struct {
    target: UpdateTarget = .self,
    force: bool = false,
    check: bool = false,
    json: bool = false,
    offline: bool = false,
    help: bool = false,
    trust_override: ?bool = null,
    show_extensions_skipped_note: bool = false,
};

pub fn parseCommandOptions(args: []const []const u8) !CommandOptions {
    var options: CommandOptions = .{};
    var self_flag = false;
    var extensions_flag = false;
    var models_flag = false;
    var all_flag = false;
    var extension_source: ?[]const u8 = null;
    var positional: ?[]const u8 = null;

    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--json")) options.json = true else if (std.mem.eql(u8, arg, "--offline")) options.offline = true else if (std.mem.eql(u8, arg, "--force")) options.force = true else if (std.mem.eql(u8, arg, "--check")) options.check = true else if (std.mem.eql(u8, arg, "--self")) self_flag = true else if (std.mem.eql(u8, arg, "--extensions")) extensions_flag = true else if (std.mem.eql(u8, arg, "--models")) models_flag = true else if (std.mem.eql(u8, arg, "--all")) all_flag = true else if (std.mem.eql(u8, arg, "--approve") or std.mem.eql(u8, arg, "-a")) options.trust_override = true else if (std.mem.eql(u8, arg, "--no-approve") or std.mem.eql(u8, arg, "-na")) options.trust_override = false else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) options.help = true else if (std.mem.eql(u8, arg, "--extension")) {
            if (extension_source != null) return error.ConflictingOptions;
            index += 1;
            if (index >= args.len or std.mem.startsWith(u8, args[index], "-")) return error.MissingOptionValue;
            extension_source = args[index];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return error.UnknownOption;
        } else if (positional == null) {
            positional = arg;
        } else {
            return error.TooManyArguments;
        }
    }

    if (all_flag and (self_flag or extensions_flag or models_flag or extension_source != null or positional != null)) return error.ConflictingOptions;
    if (models_flag and (self_flag or extensions_flag or extension_source != null or positional != null)) return error.ConflictingOptions;
    if (extension_source != null and (self_flag or extensions_flag or positional != null)) return error.ConflictingOptions;

    if (models_flag) {
        options.target = .models;
    } else if (extension_source) |source| {
        options.target = .{ .extensions = source };
    } else if (positional) |source| {
        if (std.mem.eql(u8, source, "self") or std.mem.eql(u8, source, "pi")) {
            options.target = if (extensions_flag) .all else .self;
        } else {
            if (self_flag or extensions_flag) return error.ConflictingOptions;
            options.target = .{ .extensions = source };
        }
    } else if (all_flag or (self_flag and extensions_flag)) {
        options.target = .all;
    } else if (extensions_flag) {
        options.target = .{ .extensions = null };
    } else {
        options.target = .self;
        options.show_extensions_skipped_note = !self_flag;
    }
    return options;
}

test "update command target parser matches upstream defaults aliases and conflicts" {
    const none = [_][]const u8{};
    const default = try parseCommandOptions(&none);
    try std.testing.expect(default.target == .self);
    try std.testing.expect(default.show_extensions_skipped_note);

    const both_args = [_][]const u8{ "--self", "--extensions", "--check" };
    const both = try parseCommandOptions(&both_args);
    try std.testing.expect(both.target == .all and both.check);

    const package_args = [_][]const u8{ "--extension", "npm:@scope/pkg", "--json" };
    const package = try parseCommandOptions(&package_args);
    try std.testing.expectEqualStrings("npm:@scope/pkg", package.target.extensions.?);
    try std.testing.expect(package.json);

    const conflict = [_][]const u8{ "--models", "--self" };
    try std.testing.expectError(error.ConflictingOptions, parseCommandOptions(&conflict));
}
