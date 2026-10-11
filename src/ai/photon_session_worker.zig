//! Worker-owned copies preserve caller memory; codec sessions stay on their
//! creating thread. Result ownership transfers only after the explicit join.
const std = @import("std");
const resize = @import("photon_session_resize.zig");
pub const Worker = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    mime: []u8,
    options: resize.Options,
    thread: ?std.Thread = null,
    result: ?resize.Outcome = null,
    failure: ?anyerror = null,
    done: std.atomic.Value(bool) = .init(false),
    pub fn start(allocator: std.mem.Allocator, bytes: []const u8, mime: []const u8, options: resize.Options) !*Worker {
        const self = try allocator.create(Worker);
        errdefer allocator.destroy(self);
        const owned_bytes = try allocator.dupe(u8, bytes);
        errdefer allocator.free(owned_bytes);
        const owned_mime = try allocator.dupe(u8, mime);
        errdefer allocator.free(owned_mime);
        self.* = .{ .allocator = allocator, .bytes = owned_bytes, .mime = owned_mime, .options = options };
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }
    fn run(self: *Worker) void {
        self.result = resize.resize(self.allocator, self.bytes, self.mime, self.options) catch |err| blk: {
            self.failure = err;
            break :blk null;
        };
        self.done.store(true, .release);
    }
    pub fn isDone(self: *Worker) bool {
        return self.done.load(.acquire);
    }
    pub fn take(self: *Worker) !resize.Outcome {
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
        if (self.failure) |err| return err;
        const result = self.result orelse return error.WorkerResultAlreadyTaken;
        self.result = null;
        return result;
    }
    pub fn deinit(self: *Worker) void {
        if (self.thread) |thread| thread.join();
        if (self.result) |*result| switch (result.*) {
            .image => |*image| image.deinit(self.allocator),
            .failure => |*failure| failure.deinit(self.allocator),
            .none => {},
        };
        const allocator = self.allocator;
        allocator.free(self.bytes);
        allocator.free(self.mime);
        allocator.destroy(self);
    }
};
