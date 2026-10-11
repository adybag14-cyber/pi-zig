const std = @import("std");
const worker = @import("photon_session_worker.zig");
test "native resize worker owns copied input and transfers its result exactly once" {
    const original = @embedFile("fixtures/photon-source-8x5.png");
    const input = try std.testing.allocator.dupe(u8, original);
    defer std.testing.allocator.free(input);
    const task = try worker.Worker.start(std.testing.allocator, input, "image/png", .{ .max_width = 4 });
    defer task.deinit();
    @memset(input, 0);
    var result = try task.take();
    switch (result) {
        .image => |*image| {
            defer image.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(f64, 4), image.width);
            try std.testing.expectEqual(@as(f64, 3), image.height);
        },
        .failure => |*failure| {
            failure.deinit(std.testing.allocator);
            return error.UnexpectedCodecFailure;
        },
        .none => return error.ExpectedImage,
    }
    try std.testing.expectError(error.WorkerResultAlreadyTaken, task.take());
    try std.testing.expect(task.isDone());
}
test "closing an unconsumed resize worker joins and releases its genuine result" {
    const task = try worker.Worker.start(std.testing.allocator, @embedFile("fixtures/photon-source-8x5.png"), "image/png", .{ .max_width = -1 });
    task.deinit();
}
