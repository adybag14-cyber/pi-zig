//! Actual Linux stdio/argv/env assembly for the reviewed clone3 ticket. All
//! allocations/conversions occur before clone. There is no VM/public selection.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const spawn = @import("native_child_process_spawn_linux.zig");
const transport = @import("native_child_process_transport.zig");
const Environment = @import("native_child_process_environment.zig").Environment;
pub const Spawned = struct {
    ticket: spawn.Ticket,
    // Actual distinct parent socket endpoints. Child sides closed before return.
    parents: [3]?linux.fd_t,
};
var preparing: std.atomic.Value(u32) = .init(0);
fn reservePreparation() !void {
    var observed = preparing.load(.acquire);
    while (observed < 16) {
        if (preparing.cmpxchgWeak(observed, observed + 1, .acq_rel, .acquire)) |actual| observed = actual else return;
    }
    return error.NativeLinuxChildPreparationCapacity;
}
fn ownedText(gpa: std.mem.Allocator, value: []const u8) ![:0]u8 {
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.NativeLinuxChildEmbeddedNul;
    return gpa.dupeZ(u8, value);
}
fn closeOwned(fd: linux.fd_t) void { _ = linux.close(fd); }
fn nonblocking(fd: linux.fd_t) !void {
    const flags = linux.fcntl(fd, linux.F.GETFL, 0);
    if (linux.errno(flags) != .SUCCESS) return error.NativeLinuxChildStdioFlagsFailed;
    const changed = linux.fcntl(fd, linux.F.SETFL, flags | (@as(usize, 1) << @bitOffsetOf(linux.O, "NONBLOCK")));
    if (linux.errno(changed) != .SUCCESS) return error.NativeLinuxChildStdioFlagsFailed;
}
/// recovery is caller-owned across ALL errors, including failed clone+failed
/// parent-mask restore. The owner must restore that exact thread before resuming
/// VM work or discarding recovery state. No fallback to non-atomic fork/spawn.
pub fn create(gpa: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8, environment: *const Environment, options: transport.Options, recovery: *spawn.MaskRecovery) !Spawned {
    if (builtin.os.tag != .linux or (builtin.cpu.arch != .x86_64 and builtin.cpu.arch != .aarch64)) return error.RequiredLinuxX64Arm64Clone3;
    if (argv.len == 0) return error.NativeLinuxAbsoluteExecutableRequired;
    const file = options.executable orelse argv[0];
    if (file.len == 0 or file[0] != '/') return error.NativeLinuxAbsoluteExecutableRequired;
    try reservePreparation(); defer _ = preparing.fetchSub(1, .acq_rel);
    const executable = try ownedText(gpa, file); defer gpa.free(executable);
    const directory = if (cwd) |path| try ownedText(gpa, path) else null;
    defer if (directory) |path| gpa.free(path);
    var arguments: std.ArrayList([:0]u8) = .empty;
    defer { for (arguments.items) |value| gpa.free(value); arguments.deinit(gpa); }
    for (argv) |value| {
        const text = try ownedText(gpa, value);
        arguments.append(gpa, text) catch |failure| { gpa.free(text); return failure; };
    }
    const argument_pointers = try gpa.allocSentinel(?[*:0]const u8, arguments.items.len, null);
    defer gpa.free(argument_pointers);
    for (arguments.items, argument_pointers) |value, *pointer| pointer.* = value.ptr;
    var variables: std.ArrayList([:0]u8) = .empty;
    defer { for (variables.items) |value| gpa.free(value); variables.deinit(gpa); }
    for (environment.pairs.items) |value| {
        // Dedicated execve raw pairs preserve empty/equals-prefixed names/order;
        // no std.process.Environ.Map projection can assert or silently drop data.
        const text = try ownedText(gpa, value);
        variables.append(gpa, text) catch |failure| { gpa.free(text); return failure; };
    }
    const environment_pointers = try gpa.allocSentinel(?[*:0]const u8, variables.items.len, null);
    defer gpa.free(environment_pointers);
    for (variables.items, environment_pointers) |value, *pointer| pointer.* = value.ptr;
    var parents: [3]?linux.fd_t = .{null} ** 3;
    errdefer for (parents) |maybe_fd| if (maybe_fd) |fd| closeOwned(fd);
    var children: [3]?linux.fd_t = .{null} ** 3;
    defer for (children) |maybe_fd| if (maybe_fd) |fd| closeOwned(fd);
    for (options.stdio, 0..) |mode, index| {
        if ((mode == .inherited) != (options.linux_stdio[index] != null)) return error.NativeStdioLeaseModeMismatch;
        if (mode == .inherited) {
            children[index] = try @import("native_child_process_stdio_linux.zig").duplicateForChild(options.linux_stdio[index] orelse return error.NativeStdioLeaseRequired);
        } else if (mode == .ignore) {
            const fd = linux.open("/dev/null", .{ .ACCMODE = if (index == 0) .RDONLY else .WRONLY, .CLOEXEC = true }, 0);
            if (linux.errno(fd) != .SUCCESS) return error.NativeLinuxChildNullDeviceFailed;
            children[index] = @intCast(fd);
        } else {
            var pair: [2]linux.fd_t = undefined;
            if (linux.errno(linux.socketpair(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0, &pair)) != .SUCCESS) return error.NativeLinuxChildSocketpairFailed;
            parents[index] = pair[0]; children[index] = pair[1];
            try nonblocking(pair[0]);
        }
    }
    // No fallible parent-side work after clone returns a live ticket. Child owns
    // its forked memory image until direct execve/status exit; parent frees its
    // own argument storage without changing child pointers or pipe endpoint OFDs.
    const ticket = try spawn.spawnAbsolute(.{ .absolute_file = executable.ptr, .argv = argument_pointers.ptr, .envp = environment_pointers.ptr, .child_stdio = .{ children[0].?, children[1].?, children[2].? }, .cwd_path = if (directory) |path| path.ptr else null, .detached = options.detached, .parent_mask_recovery = recovery });
    return .{ .ticket = ticket, .parents = parents };
}
pub const Write = union(enum) { pending, accepted: usize, failure: anyerror };
/// Actual one-attempt send on the owned stdin socket. MSG_NOSIGNAL confines pipe
/// failure handling to this call; no process-global SIGPIPE disposition changes.
pub fn writeOnce(fd: linux.fd_t, bytes: []const u8) Write {
    const count = linux.sendto(fd, bytes.ptr, bytes.len, linux.MSG.NOSIGNAL, null, 0);
    return switch (linux.errno(count)) {
        .SUCCESS => if (count <= bytes.len) .{ .accepted = count } else .{ .failure = error.NativeLinuxChildWriteProgressInvalid },
        .AGAIN, .INTR => .pending,
        .PIPE, .CONNRESET => .{ .failure = error.BrokenPipe },
        else => .{ .failure = error.NativeLinuxChildInputWriteFailed },
    };
}
