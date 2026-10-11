const std = @import("std");
const stdin = @import("tui/stdin_buffer.zig");
test {
    _ = @import("tui/terminal_image.zig");
}
fn checkStage(events: []const stdin.Event, buffer: []const u8, stage: std.json.Value) !void {
    var data: usize = 0;
    var paste: usize = 0;
    for (events) |event| switch (event) {
        .data => |bytes| {
            const expected = stage.object.get("data").?.array.items;
            if (data >= expected.len) return error.ExtraSourceDataEvent;
            try std.testing.expectEqualStrings(expected[data].string, bytes);
            data += 1;
        },
        .paste => |bytes| {
            const expected = stage.object.get("paste").?.array.items;
            if (paste >= expected.len) return error.ExtraSourcePasteEvent;
            try std.testing.expectEqualStrings(expected[paste].string, bytes);
            paste += 1;
        },
    };
    try std.testing.expectEqual(stage.object.get("data").?.array.items.len, data);
    try std.testing.expectEqual(stage.object.get("paste").?.array.items.len, paste);
    try std.testing.expectEqualStrings(stage.object.get("buffer").?.string, buffer);
}
test "Source8a9 pure stdin all14 actual delayed reply cancellation resync and legacy Alt stages" {
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("extensions/fixtures/stdin-herdr-original-8a9.json"), .{});
    defer fixture.deinit();
    const cases = fixture.value.object.get("stdin").?.array.items;
    try std.testing.expectEqual(@as(usize, 14), cases.len);
    for (cases) |row| {
        var buffer = stdin.StdinBuffer.init(std.testing.allocator, .{ .sequence_timeout_ms = 5, .escape_timeout_ms = 2 });
        defer buffer.deinit();
        var events: std.ArrayList(stdin.Event) = .empty;
        defer {
            for (events.items) |event| event.deinit(std.testing.allocator);
            events.deinit(std.testing.allocator);
        }
        const stages = row.object.get("stages").?.array.items;
        try buffer.process(row.object.get("first").?.string, &events);
        try checkStage(events.items, buffer.getBuffer(), stages[0]);
        _ = try buffer.advance(25, &events);
        try checkStage(events.items, buffer.getBuffer(), stages[1]);
        const tail = row.object.get("tail").?.string;
        if (tail.len > 0) try buffer.process(tail, &events);
        try checkStage(events.items, buffer.getBuffer(), stages[2]);
        _ = try buffer.advance(25, &events);
        checkStage(events.items, buffer.getBuffer(), stages[3]) catch |err| {
            std.debug.print("Source8a9 pure stdin case={s}\n", .{row.object.get("id").?.string});
            return err;
        };
    }
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    var buffer = stdin.StdinBuffer.init(gpa, .{ .sequence_timeout_ms = 5, .escape_timeout_ms = 2 });
    defer buffer.deinit();
    var events: std.ArrayList(stdin.Event) = .empty;
    defer {
        for (events.items) |event| event.deinit(gpa);
        events.deinit(gpa);
    }
    try buffer.process("\x1b]11;rgb:aa/", &events);
    if (try buffer.advance(25, &events) or events.items.len != 0) return error.DelayedReplyBecameKeyboardInput;
    try buffer.process("bb/cc\x07q", &events);
    try std.testing.expectEqualStrings("\x1b]11;rgb:aa/bb/cc\x07", events.items[0].data);
    try buffer.process("\x1b]hello\r", &events);
    _ = try buffer.advance(25, &events);
    try std.testing.expectEqualStrings("\r", events.items[events.items.len - 1].data);
    try buffer.process("\x1b_Gi=1;unfinished\x18z", &events);
    try std.testing.expectEqualStrings("z", events.items[events.items.len - 1].data);
}
test "Source8a9 pure stdin complete host allocation cleanup delayed reply legacy Alt and cancellation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
