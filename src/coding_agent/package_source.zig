//! Native parsing and validation for Pi local, npm, and Git package sources.
const std = @import("std");

pub const Kind = enum { local, npm, git };

pub const Source = struct {
    gpa: std.mem.Allocator,
    kind: Kind,
    original: []u8,
    /// Local path, npm install spec, or Git clone URL.
    spec: []u8,
    /// Npm package name or Git repository basename. Empty for local sources.
    name: []u8,
    version: ?[]u8 = null,
    host: ?[]u8 = null,
    repository_path: ?[]u8 = null,
    git_ref: ?[]u8 = null,
    pinned: bool = false,

    pub fn deinit(self: *Source) void {
        self.gpa.free(self.original);
        self.gpa.free(self.spec);
        self.gpa.free(self.name);
        if (self.version) |value| self.gpa.free(value);
        if (self.host) |value| self.gpa.free(value);
        if (self.repository_path) |value| self.gpa.free(value);
        if (self.git_ref) |value| self.gpa.free(value);
        self.* = undefined;
    }
};

pub fn parse(gpa: std.mem.Allocator, raw: []const u8) !Source {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0 or std.mem.indexOfScalar(u8, trimmed, 0) != null) return error.InvalidPackageSource;
    if (std.mem.startsWith(u8, trimmed, "npm:")) return parseNpm(gpa, trimmed, std.mem.trim(u8, trimmed[4..], " \t\r\n"));
    if (looksLocal(trimmed)) return parseLocal(gpa, trimmed);
    if (looksGit(trimmed)) return parseGit(gpa, trimmed);
    // Upstream treats unrecognised bare values as local paths, not implicit npm
    // package names. Npm sources are deliberately explicit through `npm:`.
    return parseLocal(gpa, trimmed);
}

fn parseLocal(gpa: std.mem.Allocator, original: []const u8) !Source {
    const path = if (std.mem.startsWith(u8, original, "path:")) std.mem.trim(u8, original[5..], " \t\r\n") else original;
    if (path.len == 0) return error.InvalidPackageSource;
    return .{
        .gpa = gpa,
        .kind = .local,
        .original = try gpa.dupe(u8, original),
        .spec = try gpa.dupe(u8, path),
        .name = try gpa.dupe(u8, ""),
    };
}

fn parseNpm(gpa: std.mem.Allocator, original: []const u8, spec: []const u8) !Source {
    if (spec.len == 0 or std.mem.indexOfAny(u8, spec, " \t\r\n") != null) return error.InvalidNpmPackageSource;
    var separator: ?usize = null;
    if (spec[0] == '@') {
        const slash = std.mem.indexOfScalar(u8, spec, '/') orelse return error.InvalidNpmPackageSource;
        separator = std.mem.indexOfScalarPos(u8, spec, slash + 1, '@');
    } else {
        separator = std.mem.indexOfScalar(u8, spec, '@');
    }
    const name = if (separator) |index| spec[0..index] else spec;
    const version = if (separator) |index| spec[index + 1 ..] else null;
    if (!validNpmName(name) or (version != null and version.?.len == 0)) return error.InvalidNpmPackageSource;

    const original_owned = try gpa.dupe(u8, original);
    errdefer gpa.free(original_owned);
    const spec_owned = try gpa.dupe(u8, spec);
    errdefer gpa.free(spec_owned);
    const name_owned = try gpa.dupe(u8, name);
    errdefer gpa.free(name_owned);
    const version_owned = if (version) |value| try gpa.dupe(u8, value) else null;
    errdefer if (version_owned) |value| gpa.free(value);
    return .{
        .gpa = gpa,
        .kind = .npm,
        .original = original_owned,
        .spec = spec_owned,
        .name = name_owned,
        .version = version_owned,
        .pinned = if (version) |value| isExactVersion(value) else false,
    };
}

fn parseGit(gpa: std.mem.Allocator, original: []const u8) !Source {
    var value = original;
    const had_prefix = std.mem.startsWith(u8, value, "git:") and !std.mem.startsWith(u8, value, "git://");
    if (had_prefix) value = std.mem.trim(u8, value[4..], " \t\r\n");
    if (std.mem.startsWith(u8, value, "git+")) value = value[4..];
    if (value.len == 0) return error.InvalidGitPackageSource;

    var repo = value;
    var ref: ?[]const u8 = null;
    if (std.mem.lastIndexOfScalar(u8, repo, '#')) |index| {
        if (index + 1 >= repo.len) return error.InvalidGitPackageSource;
        ref = repo[index + 1 ..];
        repo = repo[0..index];
    } else if (std.mem.startsWith(u8, repo, "git@")) {
        const colon = std.mem.indexOfScalar(u8, repo, ':') orelse return error.InvalidGitPackageSource;
        if (std.mem.lastIndexOfScalar(u8, repo[colon + 1 ..], '@')) |relative_index| {
            const index = colon + 1 + relative_index;
            if (index + 1 < repo.len) {
                ref = repo[index + 1 ..];
                repo = repo[0..index];
            }
        }
    } else {
        const slash = std.mem.lastIndexOfScalar(u8, repo, '/');
        const at = std.mem.lastIndexOfScalar(u8, repo, '@');
        if (at != null and (slash == null or at.? > slash.?) and at.? + 1 < repo.len) {
            ref = repo[at.? + 1 ..];
            repo = repo[0..at.?];
        }
    }

    var host: []const u8 = undefined;
    var path: []const u8 = undefined;
    var clone_url_owned: ?[]u8 = null;
    defer if (clone_url_owned) |owned| gpa.free(owned);

    if (std.mem.startsWith(u8, repo, "git@")) {
        const colon = std.mem.indexOfScalar(u8, repo, ':') orelse return error.InvalidGitPackageSource;
        host = repo[4..colon];
        path = repo[colon + 1 ..];
    } else if (std.mem.indexOf(u8, repo, "://")) |scheme_end| {
        const authority_start = scheme_end + 3;
        if (authority_start >= repo.len) return error.InvalidGitPackageSource;
        const slash_rel = std.mem.indexOfScalar(u8, repo[authority_start..], '/') orelse return error.InvalidGitPackageSource;
        const slash = authority_start + slash_rel;
        const authority = repo[authority_start..slash];
        // Strip optional userinfo and port for the install-directory identity.
        const host_with_port = if (std.mem.lastIndexOfScalar(u8, authority, '@')) |at| authority[at + 1 ..] else authority;
        if (host_with_port.len > 0 and host_with_port[0] == '[') {
            const close = std.mem.indexOfScalar(u8, host_with_port, ']') orelse return error.InvalidGitPackageSource;
            host = host_with_port[1..close];
        } else {
            host = if (std.mem.indexOfScalar(u8, host_with_port, ':')) |colon| host_with_port[0..colon] else host_with_port;
        }
        path = repo[slash + 1 ..];
    } else {
        if (!had_prefix) return error.InvalidGitPackageSource;
        const slash = std.mem.indexOfScalar(u8, repo, '/') orelse return error.InvalidGitPackageSource;
        host = repo[0..slash];
        path = repo[slash + 1 ..];
        if (!std.mem.eql(u8, host, "localhost") and std.mem.indexOfScalar(u8, host, '.') == null) {
            return error.InvalidGitPackageSource;
        }
        clone_url_owned = try std.fmt.allocPrint(gpa, "https://{s}", .{repo});
        repo = clone_url_owned.?;
    }

    path = std.mem.trim(u8, path, "/");
    if (std.mem.endsWith(u8, path, ".git")) path = path[0 .. path.len - 4];
    if (!validManagedPart(host, false) or !validManagedPart(path, true) or std.mem.count(u8, path, "/") < 1) {
        return error.InvalidGitPackageSource;
    }
    if (ref) |value_ref| if (!validRef(value_ref)) return error.InvalidGitPackageSource;

    const original_owned = try gpa.dupe(u8, original);
    errdefer gpa.free(original_owned);
    const spec_owned = try gpa.dupe(u8, repo);
    errdefer gpa.free(spec_owned);
    const basename = std.fs.path.basename(path);
    const name_owned = try gpa.dupe(u8, basename);
    errdefer gpa.free(name_owned);
    const host_owned = try gpa.dupe(u8, host);
    errdefer gpa.free(host_owned);
    const path_owned = try gpa.dupe(u8, path);
    errdefer gpa.free(path_owned);
    const ref_owned = if (ref) |value_ref| try gpa.dupe(u8, value_ref) else null;
    errdefer if (ref_owned) |value_ref| gpa.free(value_ref);
    return .{
        .gpa = gpa,
        .kind = .git,
        .original = original_owned,
        .spec = spec_owned,
        .name = name_owned,
        .host = host_owned,
        .repository_path = path_owned,
        .git_ref = ref_owned,
        .pinned = ref != null,
    };
}

fn looksLocal(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "path:") or
        std.mem.startsWith(u8, value, "./") or
        std.mem.startsWith(u8, value, "../") or
        std.mem.startsWith(u8, value, "/") or
        std.mem.startsWith(u8, value, "~/") or
        (value.len >= 3 and std.ascii.isAlphabetic(value[0]) and value[1] == ':' and (value[2] == '/' or value[2] == '\\'));
}

fn looksGit(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "git:") or
        std.mem.startsWith(u8, value, "git+") or
        std.mem.startsWith(u8, value, "https://") or
        std.mem.startsWith(u8, value, "http://") or
        std.mem.startsWith(u8, value, "ssh://") or
        std.mem.startsWith(u8, value, "git://");
}

fn validNpmName(name: []const u8) bool {
    if (name.len == 0 or name.len > 214 or std.mem.indexOfAny(u8, name, " \\:\t\r\n") != null) return false;
    if (name[0] == '@') {
        const slash = std.mem.indexOfScalar(u8, name, '/') orelse return false;
        return slash > 1 and slash + 1 < name.len and std.mem.indexOfScalarPos(u8, name, slash + 1, '/') == null;
    }
    return std.mem.indexOfScalar(u8, name, '/') == null;
}

fn validManagedPartDecoded(value: []const u8, allow_slash: bool) bool {
    if (value.len == 0 or value[0] == '/' or std.mem.indexOfAny(u8, value, "\\\x00") != null) return false;
    if (!allow_slash and std.mem.indexOfScalar(u8, value, '/') != null) return false;
    var components = std.mem.splitScalar(u8, value, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return false;
    }
    return true;
}

fn validManagedPart(value: []const u8, allow_slash: bool) bool {
    if (!validManagedPartDecoded(value, allow_slash)) return false;
    if (value.len > std.Io.Dir.max_path_bytes) return false;
    var decoded_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    @memcpy(decoded_buffer[0..value.len], value);
    const decoded = std.Uri.percentDecodeInPlace(decoded_buffer[0..value.len]);
    return validManagedPartDecoded(decoded, allow_slash);
}

fn validRef(value: []const u8) bool {
    return value.len > 0 and std.mem.indexOfAny(u8, value, "\x00\r\n") == null and
        !std.mem.startsWith(u8, value, "-") and std.mem.indexOf(u8, value, "..") == null;
}

fn isExactVersion(value: []const u8) bool {
    var normalized = value;
    if (normalized.len > 0 and (normalized[0] == 'v' or normalized[0] == '=')) normalized = normalized[1..];
    if (normalized.len == 0) return false;
    var parts = std.mem.splitScalar(u8, normalized, '.');
    var count: usize = 0;
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        var numeric = part;
        if (count == 2) {
            const suffix = std.mem.indexOfAny(u8, part, "-+");
            if (suffix) |index| numeric = part[0..index];
        }
        if (numeric.len == 0) return false;
        for (numeric) |char| if (!std.ascii.isDigit(char)) return false;
        count += 1;
    }
    return count == 3;
}

test "package source parser distinguishes local npm and validated git" {
    const gpa = std.testing.allocator;
    var local = try parse(gpa, "path:./fixture");
    defer local.deinit();
    try std.testing.expectEqual(Kind.local, local.kind);
    try std.testing.expectEqualStrings("./fixture", local.spec);

    var npm = try parse(gpa, "npm:@scope/demo@1.2.3");
    defer npm.deinit();
    try std.testing.expectEqual(Kind.npm, npm.kind);
    try std.testing.expectEqualStrings("@scope/demo", npm.name);
    try std.testing.expectEqualStrings("1.2.3", npm.version.?);
    try std.testing.expect(npm.pinned);

    var alias = try parse(gpa, "npm:demo-alias@npm:@scope/demo@1.2.3");
    defer alias.deinit();
    try std.testing.expectEqualStrings("demo-alias", alias.name);
    try std.testing.expectEqualStrings("npm:@scope/demo@1.2.3", alias.version.?);
    try std.testing.expect(!alias.pinned);

    var git = try parse(gpa, "git:github.com/example/pi-demo@v2");
    defer git.deinit();
    try std.testing.expectEqual(Kind.git, git.kind);
    try std.testing.expectEqualStrings("https://github.com/example/pi-demo", git.spec);
    try std.testing.expectEqualStrings("github.com", git.host.?);
    try std.testing.expectEqualStrings("example/pi-demo", git.repository_path.?);
    try std.testing.expectEqualStrings("v2", git.git_ref.?);

    var scp_without_prefix = try parse(gpa, "git@example.com:owner/repo.git");
    defer scp_without_prefix.deinit();
    try std.testing.expectEqual(Kind.local, scp_without_prefix.kind);

    var scp_with_prefix = try parse(gpa, "git:git@example.com:owner/repo.git@main");
    defer scp_with_prefix.deinit();
    try std.testing.expectEqual(Kind.git, scp_with_prefix.kind);
    try std.testing.expectEqualStrings("example.com", scp_with_prefix.host.?);
    try std.testing.expectEqualStrings("owner/repo", scp_with_prefix.repository_path.?);
    try std.testing.expectEqualStrings("main", scp_with_prefix.git_ref.?);

    var git_protocol = try parse(gpa, "git://127.0.0.1:9418/example/pi-demo.git");
    defer git_protocol.deinit();
    try std.testing.expectEqualStrings("git://127.0.0.1:9418/example/pi-demo.git", git_protocol.spec);
    try std.testing.expectEqualStrings("127.0.0.1", git_protocol.host.?);
    try std.testing.expectEqualStrings("example/pi-demo", git_protocol.repository_path.?);
}

test "package source parser rejects unsafe managed paths" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.InvalidGitPackageSource, parse(gpa, "git:github.com/example/../escape"));
    try std.testing.expectError(error.InvalidGitPackageSource, parse(gpa, "git:github.com/example/%2e%2e/escape"));
    try std.testing.expectError(error.InvalidGitPackageSource, parse(gpa, "git:internal/example/repo"));
    try std.testing.expectError(error.InvalidNpmPackageSource, parse(gpa, "npm:@broken"));

    var versioned = try parse(gpa, "npm:demo@v1.2.3");
    defer versioned.deinit();
    try std.testing.expect(versioned.pinned);
}
