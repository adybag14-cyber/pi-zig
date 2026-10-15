//! Real loopback RFC6455 wire proof, separate from provider/cleanup parity.
const std = @import("std");
const raw = @import("extensions/native_ai_codex_socket_worker.zig");
const fixture = @import("test_support/codex_socket_peer.zig");
fn object(value: std.json.Value, key: []const u8) std.json.Value {
    return value.object.get(key).?;
}
fn stringify(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return std.json.Stringify.valueAlloc(gpa, value, .{});
}
const Notice = struct {
    io: std.Io,
    event: std.Io.Event = .unset,
    fn notify(context: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.event.set(self.io);
    }
};
fn next(worker: *raw.Worker, notice: *Notice) !raw.Event {
    while (true) {
        if (worker.pop()) |event| return event;
        if (worker.finished.load(.acquire)) return worker.failure orelse error.SourceSocketEndedEarly;
        try notice.event.waitTimeout(notice.io, .{ .duration = .{ .raw = .fromSeconds(2), .clock = .awake } });
        notice.event.reset();
    }
}
test "native Codex socket replays genuine captured Source path headers and two cached request frames over real loopback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // This data is genuine Source protocol output. Its original lifecycle job
    // timed out; this test makes no provider or Source-cleanup qualification.
    const source = try std.json.parseFromSlice(std.json.Value, a, @embedFile("../verification/native-codex-socket10-negative-20261015/ai-codex-socket10-5ab-source10-first-20261015-output.json"), .{});
    try std.testing.expectEqualStrings("5ab7fe74c400097b386662205cd93900695b8a71", object(source.value, "sourceHead").string);
    const row = object(source.value, "rows").array.items[0];
    const connection = object(row, "connections").array.items[0];
    try std.testing.expectEqualStrings("cached-continuation", object(row, "name").string);
    const original_url = try std.Uri.parse(object(connection, "url").string);
    const path = switch (original_url.path) {
        .raw, .percent_encoded => |value| value,
    };
    const route = if (original_url.query) |query| try std.fmt.allocPrint(a, "{s}?{s}", .{ path, switch (query) {
        .raw, .percent_encoded => |value| value,
    } }) else path;
    var headers: std.ArrayList(std.http.Header) = .empty;
    var header_iterator = object(connection, "headers").object.iterator();
    while (header_iterator.next()) |entry| try headers.append(a, .{ .name = entry.key_ptr.*, .value = entry.value_ptr.string });
    const sends = object(connection, "sends").array.items;
    const observations = object(row, "turns").array.items;
    try std.testing.expectEqual(@as(usize, 2), sends.len);
    var turns = try a.alloc(fixture.Turn, sends.len);
    for (sends, observations, 0..) |send, observed, index| {
        var replies: std.ArrayList([]const u8) = .empty;
        for (object(observed, "trace").array.items) |trace| {
            if (!std.mem.eql(u8, trace.array.items[0].string, "provider-enter")) continue;
            try replies.append(a, try stringify(a, trace.array.items[3]));
        }
        turns[index] = .{ .request = try stringify(a, send), .replies = try replies.toOwnedSlice(a) };
    }
    const server = try fixture.Peer.init(std.testing.allocator, std.testing.io, route, headers.items, turns);
    defer server.deinit();
    const rebound_url = try server.url(a); // Only the origin is rebound.
    var notice: Notice = .{ .io = std.testing.io };
    const worker = try raw.Worker.create(std.testing.io, .{ .url = rebound_url, .headers = headers.items, .connect_timeout_ms = 1000 }, &notice, Notice.notify);
    defer worker.destroy();
    const opened = try next(worker, &notice);
    defer opened.deinit();
    try std.testing.expect(opened == .connected);
    for (turns) |turn| {
        try worker.send(turn.request);
        const sent = try next(worker, &notice);
        defer sent.deinit();
        try std.testing.expect(sent == .sent);
        for (turn.replies) |expected| {
            try worker.read(1000);
            const response = try next(worker, &notice);
            defer response.deinit();
            try std.testing.expect(response == .message);
            try std.testing.expectEqualStrings(expected, response.message);
        }
    }
    try server.finish();
}
