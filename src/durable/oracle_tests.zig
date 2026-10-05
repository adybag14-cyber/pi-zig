//! Data-only, independently captured pinned upstream conformance cases.
const std = @import("std");
const scan = @import("line_scan.zig");
const decode = @import("decode.zig");
const output = @import("output_window.zig");

test "durable decoder and scanner match 5000 independently captured upstream cases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const fixture = try std.json.parseFromSliceLeaky(std.json.Value, gpa, @embedFile("fixtures/line_scan_6100.json"), .{});
    try std.testing.expectEqualStrings("6100fe5a8358709a26050b8da97ccd188ae93101", fixture.object.get("upstream").?.string);
    const cases = fixture.object.get("cases").?.array.items;
    try std.testing.expectEqual(@as(usize, 5000), cases.len);
    for (cases) |row| {
        const value = row.object;
        const input = value.get("input").?.array.items;
        const bytes = try gpa.alloc(u8, input.len);
        for (bytes, input) |*byte, number| byte.* = @intCast(number.integer);
        var scanner = try scan.LineScanner.init(.{ .startLine = @intCast(value.get("startLine").?.integer), .endLine = if (value.get("endLine")) |number| @intCast(number.integer) else null });
        var decoder = decode.streamDecoder();
        var decoded_text: std.ArrayList(u8) = .empty;
        const sink: decode.Text = .{ .gpa = gpa, .output = &decoded_text };
        var offset: usize = 0;
        for (value.get("chunks").?.array.items) |number| {
            const size: usize = @intCast(number.integer);
            try scanner.push(bytes[offset..][0..size]);
            try decoder.push(bytes[offset..][0..size], sink);
            offset += size;
        }
        try decoder.finish(sink);
        try std.testing.expectEqualStrings(value.get("decoded").?.string, decoded_text.items);
        const result = try scanner.finish();
        inline for (std.meta.fields(scan.LineScan)) |field| {
            const expected = value.get("result").?.object.get(field.name).?.integer;
            if (@field(result, field.name) != expected) {
                std.debug.print("Durable oracle seed {d} field {s}: actual {d}, expected {d}\n", .{ value.get("seed").?.integer, field.name, @field(result, field.name), expected });
                return error.LineOracleMismatch;
            }
        }
    }
}

fn outputLimits(value: std.json.Value) output.Limits {
    return .{ .maxBytes = @intCast(value.object.get("maxBytes").?.integer), .maxLines = @intCast(value.object.get("maxLines").?.integer), .retain = if (std.mem.eql(u8, value.object.get("retain").?.string, "tail")) .tail else .head };
}
fn compareOutput(gpa: std.mem.Allocator, buffer: *output.OutputBuffer, expected: std.json.Value) !void {
    var actual = try buffer.snapshot();
    defer actual.deinit(gpa);
    try std.testing.expectEqualStrings(expected.object.get("text").?.string, actual.text);
    try std.testing.expectEqual(@as(u64, @intCast(expected.object.get("droppedBytes").?.integer)), actual.droppedBytes);
    try std.testing.expectEqual(@as(u64, @intCast(expected.object.get("droppedLines").?.integer)), actual.droppedLines);
}
test "durable output windows match 3000 upstream skip and snapshot sequences and 240 bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const fixture = try std.json.parseFromSliceLeaky(std.json.Value, gpa, @embedFile("fixtures/output_window_6100.json"), .{});
    const cases = fixture.object.get("cases").?.array.items;
    try std.testing.expectEqual(@as(usize, 3000), cases.len);
    for (cases) |row| {
        var buffer = output.OutputBuffer.init(gpa, outputLimits(row.object.get("limits").?));
        defer buffer.deinit();
        for (row.object.get("steps").?.array.items) |step| {
            const skipped: ?output.ShellOutputSkip = if (step.object.get("skipped")) |skip| .{ .bytes = @intCast(skip.object.get("bytes").?.integer), .newlines = @intCast(skip.object.get("newlines").?.integer), .endsWithNewline = skip.object.get("endsWithNewline").?.bool } else null;
            _ = try buffer.pushText(step.object.get("text").?.string, skipped);
            if (step.object.get("snapshot")) |expected| try compareOutput(gpa, &buffer, expected);
        }
        try buffer.end();
        compareOutput(gpa, &buffer, row.object.get("result").?) catch |err| {
            std.debug.print("Durable output oracle seed {d}\n", .{row.object.get("seed").?.integer});
            return err;
        };
    }
    const bounds = fixture.object.get("bounds").?.array.items;
    try std.testing.expectEqual(@as(usize, 240), bounds.len);
    for (bounds) |row| {
        const actual = try output.boundOutput(gpa, row.object.get("text").?.string, outputLimits(row.object.get("limits").?));
        defer gpa.free(actual.text);
        const expected = row.object.get("result").?.object;
        try std.testing.expectEqualStrings(expected.get("text").?.string, actual.text);
        try std.testing.expectEqual(@as(usize, @intCast(expected.get("bytes").?.integer)), actual.bytes);
        try std.testing.expectEqual(@as(usize, @intCast(expected.get("droppedBytes").?.integer)), actual.droppedBytes);
        try std.testing.expectEqual(@as(u64, @intCast(expected.get("droppedLines").?.integer)), actual.droppedLines);
    }
}
