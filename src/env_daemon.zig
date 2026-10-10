//! Native Pi-env framed stdio endpoint. File handles belong to this process.
const std = @import("std");
const builtin = @import("builtin");
const frame = @import("env/frame.zig");
const files = @import("env/files.zig");
const startup = @import("durable/startup.zig");
const transport = @import("env/daemon_input.zig");
const execution = @import("env/daemon_exec.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    if (arguments.len != 4 or !std.mem.eql(u8, arguments[1], "serve") or !std.mem.eql(u8, arguments[2], "--token")) return error.InvalidDaemonArguments;
    _ = try frame.Sync.init(arguments[3]);
    const sync = try std.fmt.allocPrint(gpa, "PI-ENV {s}\n", .{arguments[3]});
    defer gpa.free(sync);
    try std.Io.File.stdout().writeStreamingAll(io, sync);
    var environ = try std.process.Environ.createMap(init.minimal.environ, gpa);
    defer environ.deinit();
    var drive_cwds = try @import("env/info.zig").driveCwds(gpa, &environ, builtin.os.tag == .windows);
    defer @import("env/info.zig").deinitDriveCwds(gpa, &drive_cwds);
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    // cwd() is an AT_FDCWD sentinel on POSIX, not a descriptor that can be
    // resolved through /proc/self/fd. Resolve a real leased directory handle.
    const current_directory = try std.Io.Dir.cwd().openDir(io, ".", .{});
    defer current_directory.close(io);
    const path_length = try current_directory.realPath(io, &path_buffer);
    const cwd = path_buffer[0..path_length];
    const home = startup.home(&environ) orelse "";
    const tmpdir = try startup.tempDirectory(gpa, &environ);
    defer gpa.free(tmpdir);
    var server = try files.Server.init(gpa, io, cwd, home);
    defer server.deinit();
    try server.filesystem.setTempDirectory(tmpdir);
    var input = transport.Input.init(io, std.Io.File.stdin());
    try input.start();
    defer input.deinit();
    var output: execution.Output = .{ .io = io, .file = std.Io.File.stdout() };
    try output.start();
    defer output.deinit();
    var parent_owner = try @import("durable/process_ownership.zig").ParentJob.init();
    defer parent_owner.deinit();
    var file_workers: @import("env/file_workers.zig").Pool = .{ .io = io, .input = &input, .output = &output, .server = &server };
    try file_workers.start();
    defer file_workers.deinit();
    var tasks: std.Io.Group = .init;
    defer tasks.cancel(io);
    while (true) {
        const event = try input.next();
        if (event == .ended) break;
        if (event == .tick) {
            try output.send(.ping, 0, std.json.Value{ .object = .empty }, "");
            continue;
        }
        const pending = event.request;
        var delegated = false;
        defer if (!delegated) input.complete(pending);
        const request = pending.frame;
        if (request.json.value == .object) {
            if (request.json.value.object.get("op")) |op| if (op == .string and std.mem.eql(u8, op.string, "hello")) {
                const protocol = request.json.value.object.get("protocol") orelse std.json.Value.null;
                if (protocol != .integer or protocol.integer != frame.protocol) {
                    try output.send(.remote_error, request.id, .{ .code = "EINVAL", .message = "Unsupported Pi-env protocol" }, "");
                    continue;
                }
                try output.send(.result, request.id, .{
                    .protocol = frame.protocol,
                    .version = @import("env/info.zig").version,
                    .os = if (builtin.os.tag == .macos) "darwin" else @tagName(builtin.os.tag),
                    .arch = @tagName(builtin.cpu.arch),
                    .home = home,
                    .tmpdir = tmpdir,
                    .cwd = cwd,
                    .driveCwds = drive_cwds,
                    .separator = if (builtin.os.tag == .windows) "\\" else "/",
                    .pid = if (builtin.os.tag == .windows) std.os.windows.GetCurrentProcessId() else std.c.getpid(),
                }, "");
                continue;
            };
            if (request.json.value.object.get("op")) |op| if (op == .string and std.mem.eql(u8, op.string, "exec")) {
                const task = try std.heap.page_allocator.create(execution.Task);
                errdefer std.heap.page_allocator.destroy(task);
                task.* = .{ .input = &input, .output = &output, .pending = pending, .environ = &environ, .cwd = cwd, .tmpdir = tmpdir, .parent_owner = &parent_owner };
                try tasks.concurrent(io, execution.Task.run, .{task});
                delegated = true;
                continue;
            };
            if (request.json.value.object.get("op")) |op| if (op == .string and std.mem.eql(u8, op.string, "watch")) {
                const watch_task = try std.heap.page_allocator.create(@import("env/daemon_watch.zig").Task);
                errdefer std.heap.page_allocator.destroy(watch_task);
                watch_task.* = .{ .input = &input, .output = &output, .pending = pending, .cwd = cwd, .home = home };
                try tasks.concurrent(io, @import("env/daemon_watch.zig").Task.run, .{watch_task});
                delegated = true;
                continue;
            };
        }
        try file_workers.enqueue(pending);
        delegated = true;
    }
}
