//! Structured cancellation for trusted byte-only HTTP preparation callbacks.
//! All tasks are joined and racing owned Prepared results are destroyed.
const std = @import("std");
const prep = @import("native_ai_http_prepare.zig");
pub fn run(a: std.mem.Allocator, callback: prep.Callback, request: prep.View, data: []const u8, budget: prep.Budget) !prep.Prepared {
    _ = try budget.remaining();
    const Completion = union(enum) { prepared: anyerror!prep.Prepared, canceled: anyerror!void };
    var results: [2]Completion = undefined;
    var selected = std.Io.Select(Completion).init(budget.io, &results);
    // cancel drains both tasks even if the callback finishes while its watcher
    // detects abort/expiry. The fixed queue can hold every remaining result.
    defer while (selected.cancel()) |completion| switch (completion) {
        .prepared => |finished| if (finished) |value| {
            var owned = value;
            owned.deinit(a);
        } else |_| {},
        .canceled => {},
    };
    try selected.concurrent(.prepared, callback, .{ a, request, data, budget });
    try selected.concurrent(.canceled, watchBudget, .{budget});
    const prepared = switch (try selected.await()) {
        .prepared => |finished| try finished,
        .canceled => |finished| {
            try finished;
            unreachable;
        },
    };
    // Prefer an already observable abort/expiry over racing callback success,
    // and retire the successful allocation before propagating that failure.
    _ = budget.remaining() catch |err| {
        var owned = prepared;
        owned.deinit(a);
        return err;
    };
    return prepared;
}
fn watchBudget(budget: prep.Budget) !void {
    while (true) {
        _ = try budget.remaining();
        try budget.io.sleep(.fromMilliseconds(20), .awake);
    }
}
