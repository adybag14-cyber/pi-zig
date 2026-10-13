//! Owned native SSH I/O fixture; never installed as a production tool.
const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const mode = if (args.len > 1) args[1] else "upload";
    if (std.mem.eql(u8, mode, "old-daemon")) {
        const frame = @import("env/frame.zig");
        const gpa = init.arena.allocator();
        var token: []const u8 = "";
        for (args, 0..) |arg, index| if (std.mem.eql(u8, arg, "--token") and index + 1 < args.len) {
            token = args[index + 1];
        };
        const greeting = try std.fmt.allocPrint(gpa, "PI-ENV {s}\n", .{token});
        try std.Io.File.stdout().writeStreamingAll(init.io, greeting);
        var input_buffer: [4096]u8 = undefined;
        var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
        while (true) {
            var header: [4]u8 = undefined;
            input.interface.readSliceAll(&header) catch |err| {
                if (err == error.EndOfStream) return;
                return err;
            };
            const length = std.mem.readInt(u32, &header, .big);
            if (length > frame.maximum_frame) return error.InvalidFrameLength;
            const bytes = try gpa.alloc(u8, length + 4);
            @memcpy(bytes[0..4], &header);
            try input.interface.readSliceAll(bytes[4..]);
            var request = try frame.decode(gpa, bytes);
            defer request.deinit();
            const op = if (request.json.value == .object) request.json.value.object.get("op") else null;
            const response = if (request.kind == .ping) try frame.encode(gpa, .ping, request.id, .{}, "") else if (op != null and op.? == .string and std.mem.eql(u8, op.?.string, "hello")) try frame.encode(gpa, .result, request.id, .{ .protocol = 1, .version = "1.1.0", .os = "linux", .arch = "x86_64", .home = "/", .cwd = "/", .driveCwds = .{} }, "") else try frame.encode(gpa, .remote_error, request.id, .{ .code = "EINVAL", .message = "unknown operation" }, "");
            try std.Io.File.stdout().writeStreamingAll(init.io, response);
        }
    }
    if (std.mem.eql(u8, mode, "flood")) {
        const bytes = [_]u8{'x'} ** (64 * 1024);
        for (0..1024) |_| try std.Io.File.stdout().writeStreamingAll(init.io, &bytes);
        return;
    }
    if (std.mem.eql(u8, mode, "unicode")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "Ω🦊\n");
        try std.Io.File.stderr().writeStreamingAll(init.io, "owned-error\n");
        std.process.exit(37);
    }
    if (std.mem.eql(u8, mode, "tick")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "producer-entered\n");
        try init.io.sleep(.fromSeconds(30), .awake);
        return;
    }
    if (std.mem.eql(u8, mode, "end-marker")) {
        var input_buffer: [4096]u8 = undefined;
        var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
        while (true) {
            const line = try input.interface.takeDelimiterExclusive('\n');
            input.interface.toss(1);
            if (std.mem.eql(u8, line, "PI-ENV-END")) break;
        }
        try std.Io.File.stdout().writeStreamingAll(init.io, "END-MARKER-ACK\n");
        return;
    }
    if (std.mem.eql(u8, mode, "closed-output")) {
        std.Io.File.stdout().close(init.io);
        std.Io.File.stderr().close(init.io);
        try init.io.sleep(.fromSeconds(30), .awake);
        return;
    }
    if (std.mem.eql(u8, mode, "timeout")) {
        try init.io.sleep(.fromSeconds(30), .awake);
        return;
    }
    if (std.mem.eql(u8, mode, "untrusted")) {
        try std.Io.File.stderr().writeStreamingAll(init.io, "Host key verification failed.\n");
        std.process.exit(255);
    }
    const noise = [_]u8{'x'} ** (64 * 1024);
    try std.Io.File.stdout().writeStreamingAll(init.io, &noise);
    try std.Io.File.stderr().writeStreamingAll(init.io, &noise);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [4096]u8 = undefined;
    var reader_buffer: [4096]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &reader_buffer);
    var length: usize = 0;
    while (true) {
        const count = try reader.interface.readSliceShort(&buffer);
        if (count == 0) break;
        hash.update(buffer[0..count]);
        length += count;
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const report = try std.fmt.allocPrint(init.arena.allocator(), "\n{d}:{s}\n", .{ length, std.fmt.bytesToHex(digest, .lower) });
    try std.Io.File.stdout().writeStreamingAll(init.io, report);
}
