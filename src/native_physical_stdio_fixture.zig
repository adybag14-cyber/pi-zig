//! Test executable exercising the same physical stdio owner used by Main.
const std = @import("std");
const Hub = @import("extensions/native_physical_stdio.zig").Hub;
const bridge = @import("extensions/process_stream_bridge.zig");
const protocol = @import("extensions/process_stream_protocol.zig");

const Sink = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,
    ended: std.atomic.Value(bool) = .init(false),
    fn input(raw: ?*anyopaque, _: protocol.Lease, bytes: []const u8) !void {
        const self: *Sink = @ptrCast(@alignCast(raw.?));
        try self.bytes.appendSlice(self.allocator, bytes);
    }
    fn end(raw: ?*anyopaque, _: protocol.Lease) !void {
        const self: *Sink = @ptrCast(@alignCast(raw.?));
        self.ended.store(true, .release);
    }
    fn resize(_: ?*anyopaque, _: protocol.Lease, _: u32, _: u32) !void {}
    fn callbacks(self: *Sink, generation: u64) bridge.Sink {
        return .{ .context = self, .lease = .{ .owner_generation = 1, .process_generation = generation }, .input_fn = input, .end_fn = end, .resize_fn = resize };
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const backing = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var hub: Hub = undefined;
    try hub.init(allocator, backing);
    defer hub.deinit();
    const owner = hub.bridge();
    var first: Sink = .{ .allocator = allocator };
    defer first.bytes.deinit(allocator);
    var second: Sink = .{ .allocator = allocator };
    defer second.bytes.deinit(allocator);
    try owner.attach_fn.?(owner.context, first.callbacks(1));
    defer owner.detach_fn.?(owner.context, first.callbacks(1));
    try owner.attach_fn.?(owner.context, second.callbacks(2));
    defer owner.detach_fn.?(owner.context, second.callbacks(2));
    // Register Main before allowing any physical byte to be consumed.
    _ = try @import("tui/platform_terminal.zig").waitInput(0);
    try owner.control_fn(owner.context, .{ .@"resume" = {} });
    try std.Io.File.stdout().writeStreamingAll(hub.io(), "PHYSICAL_READY\n");
    var received: std.ArrayList(u8) = .empty;
    defer received.deinit(allocator);
    var buffer: [4096]u8 = undefined;
    while (true) {
        var vectors = [_][]u8{&buffer};
        const count = std.Io.File.stdin().readStreaming(hub.io(), &vectors) catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        if (count == 0) break;
        try received.appendSlice(allocator, buffer[0..count]);
        if (args.len == 2 and std.mem.eql(u8, args[1], "cancel")) {
            try std.Io.File.stdout().writeStreamingAll(hub.io(), "PHYSICAL_CANCEL\n");
            return;
        }
    }
    const end_deadline = std.Io.Clock.awake.now(backing).toMilliseconds() + 5000;
    while (!first.ended.load(.acquire) or !second.ended.load(.acquire)) {
        if (std.Io.Clock.awake.now(backing).toMilliseconds() >= end_deadline) return error.PhysicalEndTimeout;
        try backing.sleep(.fromMilliseconds(1), .awake);
    }
    // Detach joins producer deliveries, so each byte buffer is now owner-only.
    owner.detach_fn.?(owner.context, first.callbacks(1));
    owner.detach_fn.?(owner.context, second.callbacks(2));
    if (!first.ended.load(.acquire) or !second.ended.load(.acquire)) return error.MissingPhysicalEnd;
    if (!std.mem.eql(u8, received.items, first.bytes.items) or !std.mem.eql(u8, received.items, second.bytes.items)) return error.PhysicalFanoutMismatch;
    var replacement: Sink = .{ .allocator = allocator };
    defer replacement.bytes.deinit(allocator);
    try owner.attach_fn.?(owner.context, replacement.callbacks(3));
    defer owner.detach_fn.?(owner.context, replacement.callbacks(3));
    if (!replacement.ended.load(.acquire) or replacement.bytes.items.len != 0) return error.PhysicalReplacementReplayMismatch;
    var result: std.Io.Writer.Allocating = .init(allocator);
    defer result.deinit();
    try result.writer.print("PHYSICAL_MATCH {d}\n", .{received.items.len});
    try std.Io.File.stdout().writeStreamingAll(hub.io(), result.written());
}
