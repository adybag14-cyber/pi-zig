//! Managed fd/ripgrep discovery and acquisition.
//!
//! Original Pi prefers binaries already installed in the agent-private bin
//! directory, then system commands, and only downloads a release when a tool is
//! actually needed.  Downloads share the bounded management HTTP policy,
//! respect PI_OFFLINE/proxy/NO_PROXY settings, extract into unique temporary
//! directories, and commit the binary atomically.
const std = @import("std");
const builtin = @import("builtin");
const config = @import("../config.zig");
const bootstrap_http = @import("../ai/bootstrap_http.zig");

const Io = std.Io;

pub const Tool = enum { fd, rg };

const Descriptor = struct {
    display_name: []const u8,
    repository: []const u8,
    binary_name: []const u8,
    tag_prefix: []const u8,
    system_names: []const []const u8,
};

const fd_names = [_][]const u8{ "fd", "fdfind" };
const rg_names = [_][]const u8{"rg"};

fn descriptor(tool: Tool) Descriptor {
    return switch (tool) {
        .fd => .{
            .display_name = "fd",
            .repository = "sharkdp/fd",
            .binary_name = "fd",
            .tag_prefix = "v",
            .system_names = &fd_names,
        },
        .rg => .{
            .display_name = "ripgrep",
            .repository = "BurntSushi/ripgrep",
            .binary_name = "rg",
            .tag_prefix = "",
            .system_names = &rg_names,
        },
    };
}

pub const EnsureOptions = struct {
    /// Hard network gate. PI_OFFLINE remains authoritative even when false.
    offline: bool = false,
    /// Optional direct endpoints used by deterministic integration tests and
    /// private mirrors. Environment overrides are also supported.
    release_url: ?[]const u8 = null,
    download_url: ?[]const u8 = null,
    /// Override the bootstrap policy. Null fields are populated from settings.
    http: ?bootstrap_http.Options = null,
};

const EffectiveHttp = struct {
    gpa: std.mem.Allocator,
    options: bootstrap_http.Options,
    setting_proxy: ?[]u8 = null,

    fn deinit(self: *EffectiveHttp) void {
        if (self.setting_proxy) |value| self.gpa.free(value);
        self.* = undefined;
    }
};

fn envTrue(environ: ?*const std.process.Environ.Map, key: []const u8) bool {
    const value = (environ orelse return false).get(key) orelse return false;
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    return std.mem.eql(u8, trimmed, "1") or std.ascii.eqlIgnoreCase(trimmed, "true") or std.ascii.eqlIgnoreCase(trimmed, "yes") or std.ascii.eqlIgnoreCase(trimmed, "on");
}

fn isOffline(environ: ?*const std.process.Environ.Map, explicit: bool) bool {
    return explicit or envTrue(environ, "PI_OFFLINE");
}

fn isTermux(environ: ?*const std.process.Environ.Map) bool {
    const map = environ orelse return false;
    if (map.get("TERMUX_VERSION") != null) return true;
    if (map.get("PREFIX")) |prefix| return std.mem.indexOf(u8, prefix, "com.termux") != null;
    return false;
}

fn binaryExtension() []const u8 {
    return if (builtin.os.tag == .windows) ".exe" else "";
}

fn executablePermissions() std.Io.File.Permissions {
    if (@hasDecl(std.Io.File.Permissions, "fromMode")) return std.Io.File.Permissions.fromMode(0o755);
    return .default_file;
}

fn existingFile(io: Io, path: []const u8) bool {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return stat.kind == .file;
}

fn agentBinDir(gpa: std.mem.Allocator, environ: ?*const std.process.Environ.Map) !?[]u8 {
    const map = environ orelse return null;
    const agent_dir = config.agentDir(gpa, map) catch return null;
    defer gpa.free(agent_dir);
    return try std.fs.path.join(gpa, &.{ agent_dir, "bin" });
}

fn localPath(gpa: std.mem.Allocator, io: Io, environ: ?*const std.process.Environ.Map, tool: Tool) !?[]u8 {
    const bin_dir = (try agentBinDir(gpa, environ)) orelse return null;
    defer gpa.free(bin_dir);
    const d = descriptor(tool);
    const file_name = try std.fmt.allocPrint(gpa, "{s}{s}", .{ d.binary_name, binaryExtension() });
    defer gpa.free(file_name);
    const path = try std.fs.path.join(gpa, &.{ bin_dir, file_name });
    if (existingFile(io, path)) return path;
    gpa.free(path);
    return null;
}

fn pathDelimiter() u8 {
    return if (builtin.os.tag == .windows) ';' else ':';
}

fn commandCandidate(gpa: std.mem.Allocator, io: Io, dir: []const u8, name: []const u8) !?[]u8 {
    const with_extension = if (builtin.os.tag == .windows and std.fs.path.extension(name).len == 0)
        try std.fmt.allocPrint(gpa, "{s}.exe", .{name})
    else
        try gpa.dupe(u8, name);
    defer gpa.free(with_extension);
    const path = if (dir.len == 0)
        try gpa.dupe(u8, with_extension)
    else
        try std.fs.path.join(gpa, &.{ dir, with_extension });
    if (existingFile(io, path)) return path;
    gpa.free(path);
    return null;
}

fn systemPath(gpa: std.mem.Allocator, io: Io, environ: ?*const std.process.Environ.Map, tool: Tool) !?[]u8 {
    const map = environ orelse return null;
    const path_value = map.get("PATH") orelse return null;
    const d = descriptor(tool);
    var dirs = std.mem.splitScalar(u8, path_value, pathDelimiter());
    while (dirs.next()) |dir| {
        for (d.system_names) |name| if (try commandCandidate(gpa, io, dir, name)) |path| return path;
    }
    return null;
}

/// Locate a managed or system binary without network access. Returned path is
/// owned by the caller.
pub fn resolve(gpa: std.mem.Allocator, io: Io, environ: ?*const std.process.Environ.Map, tool: Tool) !?[]u8 {
    if (try localPath(gpa, io, environ, tool)) |path| return path;
    return systemPath(gpa, io, environ, tool);
}

fn optionalUnsigned(object: std.json.ObjectMap, names: []const []const u8) ?u64 {
    for (names) |name| if (object.get(name)) |value| {
        if (value == .integer and value.integer >= 0) return @intCast(value.integer);
    };
    return null;
}

fn loadHttpSettings(gpa: std.mem.Allocator, io: Io, environ: ?*const std.process.Environ.Map) !EffectiveHttp {
    var out = EffectiveHttp{
        .gpa = gpa,
        .options = .{
            .policy = .{ .timeout_ms = 10_000, .max_retries = 2, .max_retry_delay_ms = 60_000 },
            .proxy = .{ .environ = environ },
        },
    };
    errdefer out.deinit();
    const map = environ orelse return out;
    const agent_dir = config.agentDir(gpa, map) catch return out;
    defer gpa.free(agent_dir);
    const settings_path = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(settings_path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(1024 * 1024)) catch return out;
    defer gpa.free(raw);

    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return out;
    defer parsed.deinit();
    if (parsed.value != .object) return out;
    const root = parsed.value.object;
    if (root.get("httpProxy") orelse root.get("http_proxy")) |value| {
        if (value == .string and std.mem.trim(u8, value.string, " \t\r\n").len > 0) {
            out.setting_proxy = try gpa.dupe(u8, value.string);
            out.options.proxy.setting = out.setting_proxy;
        }
    }
    if (root.get("retry")) |retry_value| if (retry_value == .object) {
        if (retry_value.object.get("provider")) |provider_value| if (provider_value == .object) {
            const provider = provider_value.object;
            if (optionalUnsigned(provider, &.{ "timeoutMs", "timeout_ms" })) |value| out.options.policy.timeout_ms = value;
            if (optionalUnsigned(provider, &.{ "maxRetries", "max_retries" })) |value| out.options.policy.max_retries = @intCast(value);
            if (optionalUnsigned(provider, &.{ "maxRetryDelayMs", "max_retry_delay_ms", "maxDelayMs" })) |value| out.options.policy.max_retry_delay_ms = value;
        };
    };
    return out;
}

fn envOverride(environ: ?*const std.process.Environ.Map, tool: Tool, suffix: []const u8) ?[]const u8 {
    const map = environ orelse return null;
    const key = switch (tool) {
        .fd => if (std.mem.eql(u8, suffix, "RELEASE_URL")) "PI_TOOL_FD_RELEASE_URL" else "PI_TOOL_FD_DOWNLOAD_URL",
        .rg => if (std.mem.eql(u8, suffix, "RELEASE_URL")) "PI_TOOL_RG_RELEASE_URL" else "PI_TOOL_RG_DOWNLOAD_URL",
    };
    return map.get(key);
}

fn releaseUrl(gpa: std.mem.Allocator, environ: ?*const std.process.Environ.Map, tool: Tool, explicit: ?[]const u8) ![]u8 {
    if (explicit orelse envOverride(environ, tool, "RELEASE_URL")) |value| return gpa.dupe(u8, value);
    return std.fmt.allocPrint(gpa, "https://api.github.com/repos/{s}/releases/latest", .{descriptor(tool).repository});
}

fn parseLatestVersion(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidToolReleaseResponse;
    const tag_value = parsed.value.object.get("tag_name") orelse return error.InvalidToolReleaseResponse;
    if (tag_value != .string) return error.InvalidToolReleaseResponse;
    var tag = std.mem.trim(u8, tag_value.string, " \t\r\n");
    if (tag.len > 0 and (tag[0] == 'v' or tag[0] == 'V')) tag = tag[1..];
    if (tag.len == 0) return error.InvalidToolReleaseResponse;
    return gpa.dupe(u8, tag);
}

fn latestVersion(gpa: std.mem.Allocator, io: Io, environ: ?*const std.process.Environ.Map, tool: Tool, url_override: ?[]const u8, options: bootstrap_http.Options) ![]u8 {
    const url = try releaseUrl(gpa, environ, tool, url_override);
    defer gpa.free(url);
    const user_agent = "pi-zig-tool-manager";
    const headers = [_]std.http.Header{
        .{ .name = "User-Agent", .value = user_agent },
        .{ .name = "Accept", .value = "application/vnd.github+json" },
    };
    var request_options = options;
    if (request_options.policy.timeout_ms == null) request_options.policy.timeout_ms = 10_000;
    request_options.max_response_bytes = @min(request_options.max_response_bytes, 1024 * 1024);
    var response = try bootstrap_http.request(gpa, io, .{ .url = url, .headers = &headers, .options = request_options });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return error.ToolReleaseLookupFailed;
    return parseLatestVersion(gpa, response.body);
}

fn targetArch() ?[]const u8 {
    return switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        else => null,
    };
}

fn assetName(gpa: std.mem.Allocator, tool: Tool, version_in: []const u8) ![]u8 {
    const arch = targetArch() orelse return error.UnsupportedToolPlatform;
    var version = version_in;
    // The current fd x86_64 macOS release asset regressed in upstream Pi; keep
    // the same known-good pin used by the TypeScript implementation.
    if (tool == .fd and builtin.os.tag == .macos and builtin.cpu.arch == .x86_64) version = "10.3.0";
    return switch (tool) {
        .fd => switch (builtin.os.tag) {
            .macos => std.fmt.allocPrint(gpa, "fd-v{s}-{s}-apple-darwin.tar.gz", .{ version, arch }),
            .linux => std.fmt.allocPrint(gpa, "fd-v{s}-{s}-unknown-linux-gnu.tar.gz", .{ version, arch }),
            .windows => std.fmt.allocPrint(gpa, "fd-v{s}-{s}-pc-windows-msvc.zip", .{ version, arch }),
            else => error.UnsupportedToolPlatform,
        },
        .rg => switch (builtin.os.tag) {
            .macos => std.fmt.allocPrint(gpa, "ripgrep-{s}-{s}-apple-darwin.tar.gz", .{ version, arch }),
            .linux => if (builtin.cpu.arch == .aarch64)
                std.fmt.allocPrint(gpa, "ripgrep-{s}-aarch64-unknown-linux-gnu.tar.gz", .{version})
            else
                std.fmt.allocPrint(gpa, "ripgrep-{s}-x86_64-unknown-linux-musl.tar.gz", .{version}),
            .windows => std.fmt.allocPrint(gpa, "ripgrep-{s}-{s}-pc-windows-msvc.zip", .{ version, arch }),
            else => error.UnsupportedToolPlatform,
        },
    };
}

fn downloadUrl(gpa: std.mem.Allocator, environ: ?*const std.process.Environ.Map, tool: Tool, version: []const u8, asset: []const u8, explicit: ?[]const u8) ![]u8 {
    if (explicit orelse envOverride(environ, tool, "DOWNLOAD_URL")) |value| return gpa.dupe(u8, value);
    const d = descriptor(tool);
    return std.fmt.allocPrint(gpa, "https://github.com/{s}/releases/download/{s}{s}/{s}", .{ d.repository, d.tag_prefix, version, asset });
}

fn runExtraction(gpa: std.mem.Allocator, io: Io, argv: []const []const u8) !bool {
    const result = std.process.run(gpa, io, .{
        .argv = argv,
        .stdout_limit = .limited(256 * 1024),
        .stderr_limit = .limited(256 * 1024),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(60), .clock = .real } },
    }) catch return false;
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    return switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn extractArchive(gpa: std.mem.Allocator, io: Io, archive_path: []const u8, extract_dir: []const u8, asset: []const u8) !void {
    if (std.mem.endsWith(u8, asset, ".tar.gz")) {
        if (!try runExtraction(gpa, io, &.{ "tar", "xzf", archive_path, "-C", extract_dir })) return error.ToolArchiveExtractionFailed;
        return;
    }
    if (std.mem.endsWith(u8, asset, ".zip")) {
        if (builtin.os.tag == .windows) {
            if (try runExtraction(gpa, io, &.{ "tar.exe", "xf", archive_path, "-C", extract_dir })) return;
            const script = "& { param($archive, $destination) $ErrorActionPreference = 'Stop'; Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force }";
            if (try runExtraction(gpa, io, &.{ "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script, archive_path, extract_dir })) return;
        } else {
            if (try runExtraction(gpa, io, &.{ "unzip", "-q", archive_path, "-d", extract_dir })) return;
            if (try runExtraction(gpa, io, &.{ "tar", "xf", archive_path, "-C", extract_dir })) return;
        }
        return error.ToolArchiveExtractionFailed;
    }
    return error.UnsupportedToolArchive;
}

fn findBinary(gpa: std.mem.Allocator, io: Io, root: []const u8, file_name: []const u8) !?[]u8 {
    var dir = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.eql(u8, entry.basename, file_name)) continue;
        const found = try std.fs.path.join(gpa, &.{ root, entry.path });
        return found;
    }
    return null;
}

var tool_temp_counter: std.atomic.Value(u64) = .init(1);

fn uniqueSuffix() u64 {
    return tool_temp_counter.fetchAdd(1, .monotonic);
}

fn installDownloaded(
    gpa: std.mem.Allocator,
    io: Io,
    environ: ?*const std.process.Environ.Map,
    tool: Tool,
    version: []const u8,
    asset: []const u8,
    body: []const u8,
) ![]u8 {
    const bin_dir = (try agentBinDir(gpa, environ)) orelse return error.NoAgentDirectory;
    defer gpa.free(bin_dir);
    try std.Io.Dir.cwd().createDirPath(io, bin_dir);

    const suffix = uniqueSuffix();
    const archive_name = try std.fmt.allocPrint(gpa, ".{s}-{x}-{s}", .{ descriptor(tool).binary_name, suffix, asset });
    defer gpa.free(archive_name);
    const archive_path = try std.fs.path.join(gpa, &.{ bin_dir, archive_name });
    defer {
        std.Io.Dir.cwd().deleteFile(io, archive_path) catch {};
        gpa.free(archive_path);
    }
    {
        const archive = try std.Io.Dir.cwd().createFile(io, archive_path, .{ .truncate = true });
        defer archive.close(io);
        try archive.writePositionalAll(io, body, 0);
        try archive.sync(io);
    }

    const extract_name = try std.fmt.allocPrint(gpa, ".extract-{s}-{x}", .{ descriptor(tool).binary_name, suffix });
    defer gpa.free(extract_name);
    const extract_dir = try std.fs.path.join(gpa, &.{ bin_dir, extract_name });
    defer {
        std.Io.Dir.cwd().deleteTree(io, extract_dir) catch {};
        gpa.free(extract_dir);
    }
    try std.Io.Dir.cwd().createDirPath(io, extract_dir);
    try extractArchive(gpa, io, archive_path, extract_dir, asset);

    const file_name = try std.fmt.allocPrint(gpa, "{s}{s}", .{ descriptor(tool).binary_name, binaryExtension() });
    defer gpa.free(file_name);
    const extracted = (try findBinary(gpa, io, extract_dir, file_name)) orelse return error.ToolBinaryMissingFromArchive;
    defer gpa.free(extracted);
    const binary = try std.Io.Dir.cwd().readFileAlloc(io, extracted, gpa, .limited(128 * 1024 * 1024));
    defer gpa.free(binary);

    const final_path = try std.fs.path.join(gpa, &.{ bin_dir, file_name });
    errdefer gpa.free(final_path);
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, final_path, .{
        .replace = true,
        .make_path = true,
        .permissions = executablePermissions(),
    });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, binary, 0);
    atomic.file.setPermissions(io, executablePermissions()) catch {};
    try atomic.file.sync(io);
    try atomic.replace(io);
    _ = version;
    return final_path;
}

/// Resolve a tool, downloading the matching release only when no managed or
/// system binary is present. A null result is used for deliberate offline and
/// Termux cases so callers can fall back to native Zig implementations.
pub fn ensure(gpa: std.mem.Allocator, io: Io, environ: ?*const std.process.Environ.Map, tool: Tool, options: EnsureOptions) !?[]u8 {
    if (try resolve(gpa, io, environ, tool)) |path| return path;
    if (isOffline(environ, options.offline) or envTrue(environ, "PI_SKIP_TOOL_DOWNLOADS")) return null;
    if (isTermux(environ)) return null;

    var effective = if (options.http) |provided|
        EffectiveHttp{ .gpa = gpa, .options = provided }
    else
        try loadHttpSettings(gpa, io, environ);
    defer effective.deinit();

    const version = try latestVersion(gpa, io, environ, tool, options.release_url, effective.options);
    defer gpa.free(version);
    const asset = try assetName(gpa, tool, version);
    defer gpa.free(asset);
    const url = try downloadUrl(gpa, environ, tool, version, asset, options.download_url);
    defer gpa.free(url);

    var download_options = effective.options;
    if (download_options.policy.timeout_ms == null or download_options.policy.timeout_ms.? < 120_000) download_options.policy.timeout_ms = 120_000;
    download_options.max_response_bytes = 128 * 1024 * 1024;
    const headers = [_]std.http.Header{.{ .name = "User-Agent", .value = "pi-zig-tool-manager" }};
    var response = try bootstrap_http.request(gpa, io, .{ .url = url, .headers = &headers, .options = download_options });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return error.ToolDownloadFailed;
    const installed = try installDownloaded(gpa, io, environ, tool, version, asset, response.body);
    return installed;
}

pub fn assetNameForTarget(gpa: std.mem.Allocator, tool: Tool, version: []const u8) ![]u8 {
    return assetName(gpa, tool, version);
}

test "tool release response strips v prefix" {
    const version = try parseLatestVersion(std.testing.allocator, "{\"tag_name\":\"v14.1.1\"}");
    defer std.testing.allocator.free(version);
    try std.testing.expectEqualStrings("14.1.1", version);
}

test "tool manager resolves agent-private binary before PATH" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const root = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", gpa);
    defer gpa.free(root);
    const temp = try std.fs.path.join(gpa, &.{ root, ".tool-manager-test" });
    defer gpa.free(temp);
    std.Io.Dir.cwd().deleteTree(io, temp) catch {};
    defer std.Io.Dir.cwd().deleteTree(io, temp) catch {};
    const agent_dir = try std.fs.path.join(gpa, &.{ temp, "agent" });
    defer gpa.free(agent_dir);
    const bin_dir = try std.fs.path.join(gpa, &.{ agent_dir, "bin" });
    defer gpa.free(bin_dir);
    try std.Io.Dir.cwd().createDirPath(io, bin_dir);
    const rg_name = try std.fmt.allocPrint(gpa, "rg{s}", .{binaryExtension()});
    defer gpa.free(rg_name);
    const rg_path = try std.fs.path.join(gpa, &.{ bin_dir, rg_name });
    defer gpa.free(rg_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = rg_path, .data = "fixture" });

    var environ = std.process.Environ.Map.init(gpa);
    defer environ.deinit();
    try environ.put(config.ENV_AGENT_DIR, agent_dir);
    try environ.put("PATH", "");
    const found = (try resolve(gpa, io, &environ, .rg)).?;
    defer gpa.free(found);
    try std.testing.expectEqualStrings(rg_path, found);
}

test "offline and Termux tool acquisition remain nonfatal" {
    const gpa = std.testing.allocator;
    var environ = std.process.Environ.Map.init(gpa);
    defer environ.deinit();
    try environ.put("PI_OFFLINE", "true");
    try environ.put("PATH", "");
    try std.testing.expect((try ensure(gpa, std.testing.io, &environ, .rg, .{})) == null);

    _ = environ.swapRemove("PI_OFFLINE");
    try environ.put("TERMUX_VERSION", "0.118");
    try std.testing.expect((try ensure(gpa, std.testing.io, &environ, .fd, .{})) == null);
}
