//! Pi-compatible configuration value resolution.
//!
//! Port of `core/resolve-config-value.ts`: literals, `$ENV`/`${ENV}` templates,
//! `$$` and `$!` escapes, and `!shell command` resolution with a 10-second
//! timeout. Command results (including failures) are cached per Resolver;
//! environment-backed values are deliberately resolved on every call.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const CachedCommand = struct { value: ?[]u8 };

pub const Resolver = struct {
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    command_cache: std.StringHashMap(CachedCommand),

    pub fn init(gpa: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map) Resolver {
        return .{
            .gpa = gpa,
            .io = io,
            .environ = environ,
            .command_cache = std.StringHashMap(CachedCommand).init(gpa),
        };
    }

    pub fn deinit(self: *Resolver) void {
        self.clearCommandCache();
        self.command_cache.deinit();
        self.* = undefined;
    }

    pub fn clearCommandCache(self: *Resolver) void {
        var it = self.command_cache.iterator();
        while (it.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            if (entry.value_ptr.value) |value| self.gpa.free(value);
        }
        self.command_cache.clearRetainingCapacity();
    }

    /// Caller owns the returned value.
    pub fn resolve(self: *Resolver, config: []const u8) !?[]u8 {
        if (config.len > 0 and config[0] == '!') return self.executeCommandCached(config);
        return resolveTemplate(self.gpa, self.environ, config);
    }

    /// Caller owns the returned value. Commands are always executed.
    pub fn resolveUncached(self: *Resolver, config: []const u8) !?[]u8 {
        if (config.len > 0 and config[0] == '!') return self.executeCommandUncached(config);
        return resolveTemplate(self.gpa, self.environ, config);
    }

    fn executeCommandCached(self: *Resolver, config: []const u8) !?[]u8 {
        if (self.command_cache.get(config)) |cached| {
            return if (cached.value) |value| try self.gpa.dupe(u8, value) else null;
        }
        const resolved = try self.executeCommandUncached(config);
        const key_owned = try self.gpa.dupe(u8, config);
        errdefer self.gpa.free(key_owned);
        const cached_value = if (resolved) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (cached_value) |value| self.gpa.free(value);
        try self.command_cache.put(key_owned, .{ .value = cached_value });
        return resolved;
    }

    fn executeCommandUncached(self: *Resolver, config: []const u8) !?[]u8 {
        if (config.len <= 1) return null;
        const command = config[1..];
        const argv: []const []const u8 = if (builtin.os.tag == .windows)
            &.{ "cmd.exe", "/C", command }
        else
            &.{ "sh", "-c", command };
        const result = std.process.run(self.gpa, self.io, .{
            .argv = argv,
            .stdout_limit = .limited(1024 * 1024),
            .stderr_limit = .limited(64 * 1024),
            .timeout = .{ .duration = .{ .raw = .fromSeconds(10), .clock = .real } },
        }) catch return null;
        defer self.gpa.free(result.stdout);
        defer self.gpa.free(result.stderr);
        switch (result.term) {
            .exited => |code| if (code != 0) return null,
            else => return null,
        }
        const value = std.mem.trim(u8, result.stdout, " \t\r\n");
        if (value.len == 0) return null;
        return try self.gpa.dupe(u8, value);
    }
};

fn isEnvStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isEnvContinue(c: u8) bool {
    return isEnvStart(c) or std.ascii.isDigit(c);
}

fn validEnvName(name: []const u8) bool {
    if (name.len == 0 or !isEnvStart(name[0])) return false;
    for (name[1..]) |c| if (!isEnvContinue(c)) return false;
    return true;
}

/// Resolve template syntax. Caller owns the returned value. Missing referenced
/// environment variables make the whole value unavailable, matching upstream.
pub fn resolveTemplate(
    gpa: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    config: []const u8,
) !?[]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    var i: usize = 0;
    while (i < config.len) {
        if (config[i] != '$') {
            try out.append(gpa, config[i]);
            i += 1;
            continue;
        }
        if (i + 1 >= config.len) {
            try out.append(gpa, '$');
            i += 1;
            continue;
        }
        const next = config[i + 1];
        if (next == '$' or next == '!') {
            try out.append(gpa, next);
            i += 2;
            continue;
        }
        if (next == '{') {
            const end = std.mem.indexOfScalarPos(u8, config, i + 2, '}') orelse {
                try out.append(gpa, '$');
                i += 1;
                continue;
            };
            const name = config[i + 2 .. end];
            if (!validEnvName(name)) {
                try out.appendSlice(gpa, config[i .. end + 1]);
                i = end + 1;
                continue;
            }
            const value = environ.get(name) orelse return null;
            try out.appendSlice(gpa, value);
            i = end + 1;
            continue;
        }
        if (isEnvStart(next)) {
            var end = i + 2;
            while (end < config.len and isEnvContinue(config[end])) : (end += 1) {}
            const name = config[i + 1 .. end];
            const value = environ.get(name) orelse return null;
            try out.appendSlice(gpa, value);
            i = end;
            continue;
        }
        try out.append(gpa, '$');
        i += 1;
    }
    return try out.toOwnedSlice(gpa);
}

pub fn isCommandConfigValue(config: []const u8) bool {
    return config.len > 0 and config[0] == '!';
}

/// Returns the single environment variable name only when the entire config is
/// exactly `$NAME` or `${NAME}`. This mirrors upstream's status/source helper.
pub fn getConfigValueEnvVarName(config: []const u8) ?[]const u8 {
    if (config.len >= 2 and config[0] == '$' and config[1] != '$' and config[1] != '!') {
        if (config[1] == '{') {
            if (config[config.len - 1] != '}') return null;
            const name = config[2 .. config.len - 1];
            return if (validEnvName(name)) name else null;
        }
        const name = config[1..];
        return if (validEnvName(name)) name else null;
    }
    return null;
}

test "config values resolve literals environment templates and escapes" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("TEST_CONFIG_LEFT", "left");
    try env.put("TEST_CONFIG_RIGHT", "right");
    var resolver = Resolver.init(gpa, std.testing.io, &env);
    defer resolver.deinit();

    const cases = [_]struct { config: []const u8, want: []const u8 }{
        .{ .config = "literal-key", .want = "literal-key" },
        .{ .config = "$TEST_CONFIG_LEFT", .want = "left" },
        .{ .config = "${TEST_CONFIG_LEFT}_$TEST_CONFIG_RIGHT", .want = "left_right" },
        .{ .config = "$$TEST_CONFIG_LEFT", .want = "$TEST_CONFIG_LEFT" },
        .{ .config = "$!literal-$TEST_CONFIG_RIGHT", .want = "!literal-right" },
    };
    for (cases) |case| {
        const got = (try resolver.resolve(case.config)).?;
        defer gpa.free(got);
        try std.testing.expectEqualStrings(case.want, got);
    }
    try std.testing.expect((try resolver.resolve("$MISSING_CONFIG_VALUE")) == null);
}

test "config values execute shell commands trim output and reject failure" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var resolver = Resolver.init(gpa, std.testing.io, &env);
    defer resolver.deinit();

    const spaced = (try resolver.resolve("!printf '  spaced-key  \\n'")).?;
    defer gpa.free(spaced);
    try std.testing.expectEqualStrings("spaced-key", spaced);
    const piped = (try resolver.resolve("!echo 'hello world' | tr ' ' '-' ")).?;
    defer gpa.free(piped);
    try std.testing.expectEqualStrings("hello-world", piped);
    try std.testing.expect((try resolver.resolve("!exit 1")) == null);
    try std.testing.expect((try resolver.resolve("!printf ''")) == null);
}

test "command resolution is cached while environment resolution is dynamic" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const counter = try std.fs.path.join(gpa, &.{ path_buf[0..n], "counter" });
    defer gpa.free(counter);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = counter, .data = "0" });

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("TEST_CONFIG_DYNAMIC", "first");
    var resolver = Resolver.init(gpa, io, &env);
    defer resolver.deinit();

    const command = try std.fmt.allocPrint(gpa, "!count=$(cat '{s}'); echo $((count + 1)) > '{s}'; echo value", .{ counter, counter });
    defer gpa.free(command);
    const first = (try resolver.resolve(command)).?;
    defer gpa.free(first);
    const second = (try resolver.resolve(command)).?;
    defer gpa.free(second);
    const raw1 = try std.Io.Dir.cwd().readFileAlloc(io, counter, gpa, .limited(32));
    defer gpa.free(raw1);
    try std.testing.expectEqualStrings("1", std.mem.trim(u8, raw1, " \r\n\t"));

    const env_first = (try resolver.resolve("$TEST_CONFIG_DYNAMIC")).?;
    defer gpa.free(env_first);
    try env.put("TEST_CONFIG_DYNAMIC", "second");
    const env_second = (try resolver.resolve("$TEST_CONFIG_DYNAMIC")).?;
    defer gpa.free(env_second);
    try std.testing.expectEqualStrings("first", env_first);
    try std.testing.expectEqualStrings("second", env_second);

    resolver.clearCommandCache();
    const third = (try resolver.resolve(command)).?;
    defer gpa.free(third);
    const raw2 = try std.Io.Dir.cwd().readFileAlloc(io, counter, gpa, .limited(32));
    defer gpa.free(raw2);
    try std.testing.expectEqualStrings("2", std.mem.trim(u8, raw2, " \r\n\t"));
}

test "single env reference detection matches upstream" {
    try std.testing.expectEqualStrings("ABC_1", getConfigValueEnvVarName("$ABC_1").?);
    try std.testing.expectEqualStrings("ABC_1", getConfigValueEnvVarName("${ABC_1}").?);
    try std.testing.expect(getConfigValueEnvVarName("prefix-$ABC_1") == null);
    try std.testing.expect(!isCommandConfigValue("$ABC"));
    try std.testing.expect(isCommandConfigValue("!echo hi"));
}
