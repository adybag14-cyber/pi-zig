//! Native process participant for isolated real mount/identity captures.
const std = @import("std");
const fs_module = @import("durable/filesystem.zig");
const watch = @import("durable/watch.zig");
const identity = @import("durable/watch_identity.zig");
const Sender = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    fn send(self: *Sender, value: anytype) !void {
        const encoded = try std.json.Stringify.valueAlloc(self.gpa, value, .{});
        defer self.gpa.free(encoded);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try std.Io.File.stdout().writeStreamingAll(self.io, encoded);
        try std.Io.File.stdout().writeStreamingAll(self.io, "\n");
    }
    fn callback(raw: ?*anyopaque, change: watch.Change) !void {
        const self: *Sender = @ptrCast(@alignCast(raw.?));
        switch (change) {
            .paths => |paths| try self.send(.{ .kind = "change", .paths = paths }),
            .overflow => try self.send(.{ .kind = "overflow" }),
            .@"error" => |err| try self.send(.{ .kind = "error", .message = err.message }),
        }
    }
};
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedDirectory;
    var filesystem = try fs_module.FileSystem.init(init.gpa, init.io, args[1], null);
    defer filesystem.deinit();
    var sender: Sender = .{ .gpa = init.gpa, .io = init.io };
    var opened = try watch.Watcher.open(&filesystem, &.{.{ .path = ".", .recursive = true }}, .{ .mode = .native }, Sender.callback, &sender, .{});
    if (opened == .failure) {
        defer opened.failure.deinit(init.gpa);
        try sender.send(.{ .kind = "error", .message = opened.failure.message });
        return error.WatchOpenFailed;
    }
    defer opened.value.deinit();
    const observed = try identity.query(init.gpa, args[1], true, 0);
    try sender.send(.{ .kind = "ready", .mode = @tagName(opened.value.mode.load(.acquire)), .identity = observed });
    var buffer: [4096]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    while (true) {
        const line = reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        reader.interface.toss(1);
        if (std.mem.eql(u8, line, "quit")) break;
        if (std.mem.eql(u8, line, "identity")) try sender.send(.{ .kind = "identity", .identity = try identity.query(init.gpa, args[1], true, 0) });
    }
    opened.value.close(.{});
    try sender.send(.{ .kind = "closed" });
}
