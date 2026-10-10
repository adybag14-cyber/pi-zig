//! Stable-address lazy SSH preparation: detect once, verify for every start.
const std = @import("std");
const ssh = @import("ssh.zig");
const remote = @import("ssh_remote.zig");
const deploy = @import("deploy.zig");
const lazy = @import("lazy_connection.zig");

pub const Hooks = struct {
    context: ?*anyopaque = null,
    detect: *const fn (?*anyopaque, std.mem.Allocator, std.Io, ssh.Target) anyerror!remote.Platform = defaultDetect,
    verify: *const fn (?*anyopaque, std.mem.Allocator, std.Io, ssh.Target, *const remote.Platform, []const u8) anyerror!deploy.Plan = defaultVerify,
    on_log: ?*const fn (?*anyopaque, []const u8) void = null,
    fn defaultDetect(_: ?*anyopaque, gpa: std.mem.Allocator, io: std.Io, target: ssh.Target) !remote.Platform {
        return remote.detect(gpa, io, target);
    }
    fn defaultVerify(_: ?*anyopaque, gpa: std.mem.Allocator, io: std.Io, target: ssh.Target, platform: *const remote.Platform, binary: []const u8) !deploy.Plan {
        return remote.verifyDeploy(gpa, io, target, platform, binary);
    }
};

pub const Options = struct {
    target: ssh.Target,
    /// Explicit packaged binary bytes; selecting a target-specific package is a caller responsibility.
    binary: []const u8,
    login_shell: bool = false,
    hooks: Hooks = .{},
};

pub const Factory = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    owned: std.heap.ArenaAllocator,
    options: Options,
    platform: ?remote.Platform = null,
    verified: ?deploy.Plan = null,
    connection: lazy.Connection,

    pub fn create(gpa: std.mem.Allocator, io: std.Io, options: Options) !*Factory {
        const self = try gpa.create(Factory);
        errdefer gpa.destroy(self);
        var arena = std.heap.ArenaAllocator.init(gpa);
        errdefer arena.deinit();
        const allocator = arena.allocator();
        var retained = options;
        retained.binary = try allocator.dupe(u8, options.binary);
        inline for (@typeInfo(ssh.Target).@"struct".fields) |field| {
            if (field.type == []const u8) {
                @field(retained.target, field.name) = try allocator.dupe(u8, @field(options.target, field.name));
            } else if (field.type == ?[]const u8) {
                @field(retained.target, field.name) = if (@field(options.target, field.name)) |value| try allocator.dupe(u8, value) else null;
            }
        }
        self.* = .{ .gpa = gpa, .io = io, .owned = arena, .options = retained, .connection = lazy.Connection.init(gpa, io, prepare, self) };
        return self;
    }

    fn ensurePlatform(self: *Factory) !void {
        if (self.platform != null) return;
        var detected = try self.options.hooks.detect(self.options.hooks.context, self.gpa, self.io, self.options.target);
        errdefer detected.deinit();
        if (self.options.hooks.on_log) |log| {
            for (detected.warnings) |warning| {
                const line = try std.fmt.allocPrint(self.gpa, "{s}\n", .{warning});
                defer self.gpa.free(line);
                log(self.options.hooks.context, line);
            }
        }
        self.platform = detected;
    }

    /// Eager connect verifies now; the next start consumes that verification once.
    pub fn verifyNow(self: *Factory) !void {
        self.connection.mutex.lockUncancelable(self.io);
        defer self.connection.mutex.unlock(self.io);
        if (self.connection.closed) return error.ConnectionClosed;
        try self.ensurePlatform();
        const plan = try self.options.hooks.verify(self.options.hooks.context, self.gpa, self.io, self.options.target, &self.platform.?, self.options.binary);
        if (self.verified) |*old| old.deinit();
        self.verified = plan;
    }

    fn prepare(raw: ?*anyopaque, gpa: std.mem.Allocator, _: std.Io) !lazy.Command {
        const self: *Factory = @ptrCast(@alignCast(raw.?));
        try self.ensurePlatform();
        var plan = if (self.verified) |verified| blk: {
            self.verified = null;
            break :blk verified;
        } else try self.options.hooks.verify(self.options.hooks.context, self.gpa, self.io, self.options.target, &self.platform.?, self.options.binary);
        defer plan.deinit();
        const launch = try launchCommand(gpa, &self.platform.?, plan.path, self.options.login_shell);
        defer gpa.free(launch);
        var args = try ssh.arguments(gpa, self.options.target, true, null);
        defer args.deinit();
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.append(gpa, self.options.target.program);
        try argv.appendSlice(gpa, args.values.items);
        try argv.append(gpa, launch);
        return lazy.Command.init(gpa, argv.items);
    }

    /// Tickets must be released before destruction. Hook context belongs to the caller.
    pub fn destroy(self: *Factory) void {
        const gpa = self.gpa;
        self.connection.deinit();
        if (self.verified) |*plan| plan.deinit();
        if (self.platform) |*platform| platform.deinit();
        self.owned.deinit();
        gpa.destroy(self);
    }
};

pub fn launchCommand(gpa: std.mem.Allocator, platform: *const remote.Platform, path: []const u8, login_shell: bool) ![]u8 {
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidDeploymentPath;
    if (platform.remote.platform == .windows) {
        if (platform.shell == .powershell) {
            var quoted: std.ArrayList(u8) = .empty;
            errdefer quoted.deinit(gpa);
            try quoted.appendSlice(gpa, "& '");
            for (path) |byte| try quoted.appendSlice(gpa, if (byte == '\'') "''" else &.{byte});
            try quoted.append(gpa, '\'');
            return quoted.toOwnedSlice(gpa);
        }
        if (std.mem.indexOfAny(u8, path, "\"\r\n") != null) return error.InvalidWindowsProgramPath;
        return if (std.mem.indexOfScalar(u8, path, ' ') != null) std.fmt.allocPrint(gpa, "\"{s}\"", .{path}) else gpa.dupe(u8, path);
    }
    const quoted = try ssh.quotePosix(gpa, path);
    if (!login_shell) return quoted;
    defer gpa.free(quoted);
    return std.fmt.allocPrint(gpa, "exec \"$SHELL\" -lc 'exec \"$0\" \"$@\"' {s}", .{quoted});
}

test "native SSH factory is inert, caches only successful detection and verifies every preparation" {
    const Probe = struct {
        detections: usize = 0,
        verifications: usize = 0,
        logs: usize = 0,
        fn detect(raw: ?*anyopaque, gpa: std.mem.Allocator, _: std.Io, _: ssh.Target) !remote.Platform {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.detections += 1;
            if (self.detections == 1) return error.HostKeyUnknown;
            const home = try gpa.dupe(u8, "/home/owner");
            errdefer gpa.free(home);
            const warnings = try gpa.alloc([]u8, 1);
            errdefer gpa.free(warnings);
            warnings[0] = try gpa.dupe(u8, "original warning");
            return .{ .gpa = gpa, .remote = .{ .platform = .linux, .arch = .x64, .home = home }, .warnings = warnings };
        }
        fn verify(raw: ?*anyopaque, gpa: std.mem.Allocator, _: std.Io, _: ssh.Target, platform: *const remote.Platform, binary: []const u8) !deploy.Plan {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.verifications += 1;
            if (self.verifications == 1) return error.ConnectionLost;
            return deploy.prepare(gpa, platform.remote, binary);
        }
        fn log(raw: ?*anyopaque, line: []const u8) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            std.debug.assert(std.mem.eql(u8, line, "original warning\n"));
            self.logs += 1;
        }
    };
    var probe: Probe = .{};
    const factory = try Factory.create(std.testing.allocator, std.testing.io, .{ .target = .{ .host = "box", .known_hosts_file = "private", .host_key_alias = "owned" }, .binary = "daemon", .hooks = .{ .context = &probe, .detect = Probe.detect, .verify = Probe.verify, .on_log = Probe.log } });
    defer factory.destroy();
    try std.testing.expectEqual(@as(usize, 0), probe.detections);
    try std.testing.expectError(error.HostKeyUnknown, Factory.prepare(factory, std.testing.allocator, std.testing.io));
    try std.testing.expect(factory.platform == null);
    try std.testing.expectError(error.ConnectionLost, Factory.prepare(factory, std.testing.allocator, std.testing.io));
    try std.testing.expect(factory.platform != null);
    try std.testing.expectEqual(@as(usize, 1), probe.logs);
    var first = try Factory.prepare(factory, std.testing.allocator, std.testing.io);
    defer first.deinit();
    try factory.verifyNow();
    const prior = probe.verifications;
    var eager = try Factory.prepare(factory, std.testing.allocator, std.testing.io);
    defer eager.deinit();
    try std.testing.expectEqual(prior, probe.verifications);
    var restarted = try Factory.prepare(factory, std.testing.allocator, std.testing.io);
    defer restarted.deinit();
    try std.testing.expectEqual(prior + 1, probe.verifications);
    try std.testing.expectEqual(@as(usize, 2), probe.detections);
}

test "native SSH launch commands match twenty captured original platform shell and login cases" {
    const gpa = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/ssh-launch-28dc.json"), .{});
    defer parsed.deinit();
    for (parsed.value.object.get("cases").?.array.items) |case| {
        const object = case.object;
        const platform: remote.Platform = .{ .gpa = gpa, .remote = .{ .platform = std.meta.stringToEnum(ssh.Platform, object.get("platform").?.string).?, .arch = .x64, .home = "unused" }, .shell = if (object.get("shell").? == .null) null else std.meta.stringToEnum(remote.Shell, object.get("shell").?.string).?, .warnings = &.{} };
        const launch = try launchCommand(gpa, &platform, object.get("path").?.string, object.get("loginShell").?.bool);
        defer gpa.free(launch);
        try std.testing.expectEqualStrings(object.get("command").?.string, launch);
    }
}

test "native SSH factory ownership and launch transfer survive every allocation failure" {
    const Sweep = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const factory = try Factory.create(gpa, std.testing.io, .{ .target = .{ .host = "box", .known_hosts_file = "private", .host_key_alias = "owned", .identity_file = "identity", .config_file = "config" }, .binary = "daemon" });
            defer factory.destroy();
            const platform: remote.Platform = .{ .gpa = gpa, .remote = .{ .platform = .windows, .arch = .x64, .home = "unused" }, .shell = .powershell, .warnings = &.{} };
            const launch = try launchCommand(gpa, &platform, "C:\\owner's Ω\\daemon.exe", true);
            defer gpa.free(launch);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Sweep.run, .{});
}

test "native lazy SSH factory verifies restart tampering over actual strict private SSH" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const root = environ.get("PI_TEST_REAL_LAZY_SSH_ROOT") orelse return error.SkipZigTest;
    const daemon = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const binary = try std.Io.Dir.cwd().readFileAlloc(io, daemon, gpa, .limited(32 * 1024 * 1024));
    defer gpa.free(binary);
    const identity = try std.fs.path.join(gpa, &.{ root, "client_key" });
    defer gpa.free(identity);
    const known = try std.fs.path.join(gpa, &.{ root, "known_hosts" });
    defer gpa.free(known);
    const Probe = struct {
        detections: usize = 0,
        verifications: usize = 0,
        fn detect(raw: ?*anyopaque, allocator: std.mem.Allocator, runtime_io: std.Io, target: ssh.Target) !remote.Platform {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.detections += 1;
            return remote.detect(allocator, runtime_io, target);
        }
        fn verify(raw: ?*anyopaque, allocator: std.mem.Allocator, runtime_io: std.Io, target: ssh.Target, platform: *const remote.Platform, bytes: []const u8) !deploy.Plan {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.verifications += 1;
            return remote.verifyDeploy(allocator, runtime_io, target, platform, bytes);
        }
    };
    var probe: Probe = .{};
    const target: ssh.Target = .{ .host = "127.0.0.1", .user = "tdamre", .port = 49238, .identity_file = identity, .known_hosts_file = known, .host_key_alias = "pi-env-owned-lazy", .config_file = "/dev/null", .program = "/usr/bin/ssh" };
    const factory = try Factory.create(gpa, io, .{ .target = target, .binary = binary, .hooks = .{ .context = &probe, .detect = Probe.detect, .verify = Probe.verify } });
    defer factory.destroy();
    try std.testing.expect(factory.platform == null);
    var hello = try factory.connection.begin(.{ .op = "hello", .protocol = 1 }, "", null);
    defer hello.deinit();
    var first = try hello.next(10_000);
    defer first.deinit();
    try std.testing.expectEqualStrings(root, first.json.value.object.get("home").?.string);
    try std.testing.expectEqual(@as(usize, 1), probe.detections);
    try std.testing.expectEqual(@as(usize, 1), probe.verifications);
    factory.connection.current.?.fail(error.ConnectionLost);
    factory.connection.current.?.stop();
    var plan = try deploy.prepare(gpa, factory.platform.?.remote, binary);
    defer plan.deinit();
    const quote = try ssh.quotePosix(gpa, plan.path);
    defer gpa.free(quote);
    const tamper = try std.fmt.allocPrint(gpa, "printf damaged > {s}", .{quote});
    defer gpa.free(tamper);
    var changed = try @import("ssh_process.zig").run(gpa, io, target, tamper, .{});
    defer changed.deinit();
    try changed.check();
    var restarted = try factory.connection.begin(.{ .op = "hello", .protocol = 1 }, "", null);
    defer restarted.deinit();
    var second = try restarted.next(10_000);
    defer second.deinit();
    try std.testing.expectEqualStrings(root, second.json.value.object.get("home").?.string);
    try std.testing.expect(restarted.session != hello.session);
    try std.testing.expectEqual(@as(usize, 1), probe.detections);
    try std.testing.expectEqual(@as(usize, 2), probe.verifications);
}
