//! Byte-only credential process execution with direct ownership of its child.
//! Windows pipe reads cannot be relied upon to observe Io cancellation before
//! the child exits: terminate the exact owned process handle before joining them.
const std = @import("std");
const Budget = @import("native_ai_http_prepare.zig").Budget;
const windows = std.os.windows;
pub fn run(a: std.mem.Allocator, argv: []const []const u8, parent: Budget) !std.process.RunResult {
    const now = std.Io.Clock.awake.now(parent.io).toMilliseconds();
    var budget = parent;
    budget.deadline_ms = @min(parent.deadline_ms orelse std.math.maxInt(i64), now +| 15000);
    _ = try budget.remaining();
    return if (@import("builtin").os.tag == .windows) runWindows(a, argv, budget) else runCooperative(a, argv, budget);
}
fn watch(budget: Budget) !void {
    while (true) {
        _ = try budget.remaining();
        try budget.io.sleep(.fromMilliseconds(20), .awake);
    }
}
fn destroy(a: std.mem.Allocator, result: std.process.RunResult) void {
    @memset(result.stdout, 0);
    @memset(result.stderr, 0);
    a.free(result.stdout);
    a.free(result.stderr);
}
fn runCooperative(a: std.mem.Allocator, argv: []const []const u8, budget: Budget) !std.process.RunResult {
    const Completion = union(enum) { child: anyerror!std.process.RunResult, canceled: anyerror!void };
    var buffer: [2]Completion = undefined;
    var selected = std.Io.Select(Completion).init(budget.io, &buffer);
    defer while (selected.cancel()) |completion| switch (completion) {
        .child => |finished| if (finished) |value| destroy(a, value) else |_| {},
        .canceled => {},
    };
    try selected.concurrent(.child, std.process.run, .{ a, budget.io, std.process.RunOptions{ .argv = argv, .stdout_limit = .limited(64 * 1024), .stderr_limit = .limited(8 * 1024), .create_no_window = true, .timeout = .{ .duration = .{ .raw = .fromMilliseconds(@intCast((try budget.remaining()).?)), .clock = .awake } } } });
    try selected.concurrent(.canceled, watch, .{budget});
    return switch (try selected.await()) {
        .child => |result| result,
        .canceled => |failure| {
            try failure;
            unreachable;
        },
    };
}
const Output = struct { stdout: []u8, stderr: []u8 };
fn destroyOutput(a: std.mem.Allocator, output: Output) void {
    @memset(output.stdout, 0);
    @memset(output.stderr, 0);
    a.free(output.stdout);
    a.free(output.stderr);
}
fn terminateOwned(handle: windows.HANDLE) !void {
    // This is the hProcess returned by our own spawn, held open throughout all
    // readers and observers. There is no PID lookup, PID reuse or broad kill.
    switch (windows.ntdll.NtTerminateProcess(handle, @enumFromInt(1))) {
        .SUCCESS, .PROCESS_IS_TERMINATING => {},
        .ACCESS_DENIED => {
            const timeout: windows.LARGE_INTEGER = 0;
            if (windows.ntdll.NtWaitForSingleObject(handle, .FALSE, &timeout) != windows.NTSTATUS.WAIT_0) return error.OwnedCredentialProcessTerminationFailed;
        },
        else => |status| return windows.unexpectedStatus(status),
    }
}
fn observeExit(handle: windows.HANDLE, io: std.Io) !void {
    const timeout: windows.LARGE_INTEGER = 0;
    while (true) switch (windows.ntdll.NtWaitForSingleObject(handle, .FALSE, &timeout)) {
        windows.NTSTATUS.WAIT_0 => return,
        .TIMEOUT => try io.sleep(.fromMilliseconds(20), .awake),
        else => |status| return windows.unexpectedStatus(status),
    };
}
fn collect(a: std.mem.Allocator, io: std.Io, stdout: std.Io.File, stderr: std.Io.File, handle: windows.HANDLE) !Output {
    var buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(a, io, buffer.toStreams(), &.{ stdout, stderr });
    defer reader.deinit();
    // Run before MultiReader.deinit: an output limit/error must also close the
    // child's write ends before the outstanding synchronous read is joined.
    errdefer terminateOwned(handle) catch {};
    while (reader.fill(64, .none)) |_| {
        if (reader.reader(0).buffered().len > 64 * 1024 or reader.reader(1).buffered().len > 8 * 1024) return error.CredentialProcessOutputLimit;
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }
    try reader.checkAnyError();
    const out = try reader.toOwnedSlice(0);
    errdefer {
        @memset(out, 0);
        a.free(out);
    }
    return .{ .stdout = out, .stderr = try reader.toOwnedSlice(1) };
}
fn runWindows(a: std.mem.Allocator, argv: []const []const u8, budget: Budget) !std.process.RunResult {
    const io = budget.io;
    var child = try std.process.spawn(io, .{ .argv = argv, .stdin = .ignore, .stdout = .pipe, .stderr = .pipe, .create_no_window = true });
    const handle = child.id.?;
    const Completion = union(enum) { output: anyerror!Output, exited: anyerror!void, canceled: anyerror!void };
    var buffer: [3]Completion = undefined;
    var selected = std.Io.Select(Completion).init(io, &buffer);
    // The parent exclusively owns Child and its handles. Termination does not
    // close them; join every borrower before the final kill/wait cleans them.
    defer {
        if (child.id) |owned| terminateOwned(owned) catch {};
        while (selected.cancel()) |completion| switch (completion) {
            .output => |finished| if (finished) |value| destroyOutput(a, value) else |_| {},
            .exited, .canceled => {},
        };
        child.kill(io);
    }
    try selected.concurrent(.output, collect, .{ a, io, child.stdout.?, child.stderr.?, handle });
    try selected.concurrent(.exited, observeExit, .{ handle, io });
    try selected.concurrent(.canceled, watch, .{budget});
    var output: ?Output = null;
    errdefer if (output) |value| destroyOutput(a, value);
    var exited = false;
    while (output == null or !exited) switch (try selected.await()) {
        .output => |finished| output = try finished,
        .exited => |finished| {
            try finished;
            exited = true;
        },
        .canceled => |failure| {
            try failure;
            unreachable;
        },
    };
    _ = try budget.remaining();
    // The signaled hProcess remains open until this sole owner's wait. Both
    // pipe collectors have finished, so cleanup cannot race a borrowed handle.
    const term = try child.wait(io);
    return .{ .term = term, .stdout = output.?.stdout, .stderr = output.?.stderr };
}
