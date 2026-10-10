//! Native platform detection and verified deploy/start over the SSH process API.
const std = @import("std");
const ssh = @import("ssh.zig");
const process = @import("ssh_process.zig");
const deploy = @import("deploy.zig");
const lazy = @import("lazy_connection.zig");
pub const Shell = enum { cmd, powershell };
pub const Platform = struct {
    gpa: std.mem.Allocator,
    remote: ssh.Remote,
    shell: ?Shell = null,
    warnings: [][]u8,
    pub fn deinit(self: *Platform) void {
        self.gpa.free(self.remote.home);
        for (self.warnings) |warning| self.gpa.free(warning);
        self.gpa.free(self.warnings);
    }
};
pub const posix_probe = "sh -c 'echo PI-ENV-PROBE; uname -s; uname -m; uname -o 2>/dev/null || echo -; printf \"%s\\n\" \"$HOME\" \"${TMPDIR:--}\" \"${LD_PRELOAD:--}\"'";
fn probe(gpa: std.mem.Allocator, io: std.Io, target: ssh.Target, probe_command: []const u8) !process.Result {
    var result = try process.run(gpa, io, target, probe_command, .{});
    errdefer result.deinit();
    try result.check();
    _ = try ssh.parseProbe(result.stdout);
    return result;
}
pub fn detect(gpa: std.mem.Allocator, io: std.Io, target: ssh.Target) !Platform {
    const windows_probe = try deploy.powershell(gpa, "'PI-ENV-PROBE'; 'Windows'; [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString(); '-'; $HOME; '-'; '-'");
    defer gpa.free(windows_probe);
    var result = probe(gpa, io, target, posix_probe) catch |err| switch (err) {
        error.HostKeyChanged, error.HostKeyUnknown, error.OutOfMemory => return err,
        else => try probe(gpa, io, target, windows_probe),
    };
    defer result.deinit();
    var parsed = try ssh.parseProbe(result.stdout);
    if (ssh.needsWindowsProbe(parsed)) {
        const windows = try probe(gpa, io, target, windows_probe);
        result.deinit();
        result = windows;
        parsed = try ssh.parseProbe(result.stdout);
    }
    var remote = try ssh.classify(parsed);
    remote.home = try gpa.dupe(u8, remote.home);
    errdefer gpa.free(remote.home);
    var shell: ?Shell = null;
    if (remote.platform == .windows) {
        var response = try process.run(gpa, io, target, "echo %OS%", .{});
        defer response.deinit();
        try response.check();
        shell = if (std.mem.indexOf(u8, response.stdout, "Windows_NT") != null) .cmd else .powershell;
    }
    var warnings: std.ArrayList([]u8) = .empty;
    errdefer {
        for (warnings.items) |warning| gpa.free(warning);
        warnings.deinit(gpa);
    }
    if (remote.platform == .android) {
        const add = struct {
            fn run(allocator: std.mem.Allocator, list: *std.ArrayList([]u8), text: []const u8) !void {
                const owned = try allocator.dupe(u8, text);
                errdefer allocator.free(owned);
                try list.append(allocator, owned);
            }
        }.run;
        if (std.mem.eql(u8, parsed.tmpdir, "-")) try add(gpa, &warnings, "TMPDIR is not set; Termux's sshd normally sets it to $PREFIX/tmp.");
        if (std.mem.indexOf(u8, parsed.preload, "termux-exec") == null) try add(gpa, &warnings, "termux-exec is not loaded (LD_PRELOAD); scripts with #!/usr/bin/env shebangs will fail.");
        try add(gpa, &warnings, "Android may suspend Termux; run termux-wake-lock on the device to keep the connection alive.");
    }
    return .{ .gpa = gpa, .remote = remote, .shell = shell, .warnings = try warnings.toOwnedSlice(gpa) };
}
pub fn verifyDeploy(gpa: std.mem.Allocator, io: std.Io, target: ssh.Target, platform: *const Platform, binary: []const u8) !deploy.Plan {
    var plan = try deploy.prepare(gpa, platform.remote, binary);
    errdefer plan.deinit();
    var checked = try process.run(gpa, io, target, plan.check_command, .{});
    defer checked.deinit();
    try checked.check();
    const last = std.mem.trim(u8, checked.stdout, " \t\r\n");
    if (!std.mem.endsWith(u8, last, "present")) {
        var uploaded = try process.run(gpa, io, target, plan.upload_command, .{ .stdin = plan.upload_input, .keep_stdin_open = platform.remote.platform == .windows });
        defer uploaded.deinit();
        try uploaded.check();
    }
    return plan;
}
pub fn command(gpa: std.mem.Allocator, target: ssh.Target, plan: *const deploy.Plan) !lazy.Command {
    var arguments = try ssh.arguments(gpa, target, true, null);
    defer arguments.deinit();
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, target.program);
    try argv.appendSlice(gpa, arguments.values.items);
    try argv.append(gpa, plan.start_program);
    return lazy.Command.init(gpa, argv.items);
}
test "native SSH detection deployment and framed startup cross an actual private SSH server" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const root = environ.get("PI_TEST_REAL_SSH_ROOT") orelse return error.SkipZigTest;
    const port = try std.fmt.parseInt(u32, environ.get("PI_TEST_REAL_SSH_PORT") orelse "49237", 10);
    const identity = try std.fs.path.join(gpa, &.{ root, "client_key" });
    defer gpa.free(identity);
    const known_hosts = try std.fs.path.join(gpa, &.{ root, "known_hosts" });
    defer gpa.free(known_hosts);
    const target: ssh.Target = .{ .host = "127.0.0.1", .user = "tdamre", .port = port, .identity_file = identity, .known_hosts_file = known_hosts, .host_key_alias = "pi-env-owned-test", .config_file = "/dev/null", .program = "/usr/bin/ssh" };
    const empty_path = try std.fs.path.join(gpa, &.{ root, "empty_known_hosts" });
    defer gpa.free(empty_path);
    const empty_file = try std.Io.Dir.cwd().createFile(io, empty_path, .{});
    empty_file.close(io);
    var unknown_target = target;
    unknown_target.known_hosts_file = empty_path;
    try std.testing.expectError(error.HostKeyUnknown, detect(gpa, io, unknown_target));
    if (environ.get("PI_TEST_REAL_SSH_CHANGED_HOSTS")) |changed| {
        var changed_target = target;
        changed_target.known_hosts_file = changed;
        try std.testing.expectError(error.HostKeyChanged, detect(gpa, io, changed_target));
    }
    var platform = try detect(gpa, io, target);
    defer platform.deinit();
    try std.testing.expectEqual(ssh.Platform.linux, platform.remote.platform);
    try std.testing.expect(std.mem.startsWith(u8, platform.remote.home, root));
    const daemon = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const binary = try std.Io.Dir.cwd().readFileAlloc(io, daemon, gpa, .limited(32 * 1024 * 1024));
    defer gpa.free(binary);
    var plan = try verifyDeploy(gpa, io, target, &platform, binary);
    defer plan.deinit();
    var argv = try command(gpa, target, &plan);
    defer argv.deinit();
    const connection = try @import("connection.zig").Connection.start(gpa, io, argv.argv, 83);
    defer connection.deinit();
    var hello = try connection.begin(.{ .op = "hello", .protocol = 1 }, "", null);
    defer hello.deinit();
    var received = try hello.next(10_000);
    defer received.deinit();
    try std.testing.expectEqual(@import("frame.zig").Kind.result, received.kind);
    try std.testing.expectEqualStrings(platform.remote.home, received.json.value.object.get("home").?.string);
    var reuse = try verifyDeploy(gpa, io, target, &platform, binary);
    defer reuse.deinit();
    try std.testing.expectEqualStrings(plan.path, reuse.path);
}
