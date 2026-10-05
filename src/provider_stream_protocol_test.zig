//! Original raw streaming gates driven by Zig through the real native worker.
const std = @import("std");
const builtin = @import("builtin");
const peer = @import("test_support/native_peer.zig");
const fixture = @import("test_support/provider_stream_extension_fixture.zig");
const json = @import("test_support/json_fixture.zig");
const pty = @import("test_support/pty.zig");

fn start(worker: *peer.Peer, callback: []const u8, generation: i64, invocation: []const u8, mode: []const u8) !void {
    try worker.send(.{ .kind = "provider_stream_simple", .callbackId = callback, .providerName = "stream-production-e2e", .callbackGeneration = generation, .invocationId = invocation, .abortable = true, .model = .{ .id = "stream-model", .provider = "stream-production-e2e", .api = "custom-stream" }, .streamContext = .{ .mode = mode, .messages = [_]struct { role: []const u8, content: []const u8, timestamp: u32 }{.{ .role = "user", .content = "hello", .timestamp = 1 }} }, .options = .{ .apiKey = "secret", .maxTokens = 128, .sessionId = "session-185" }, .context = .{ .mode = "print", .hasUI = false } });
}
fn ack(worker: *peer.Peer, record: std.json.Value, accepted: bool) !void {
    try worker.send(.{ .kind = "provider_stream_ack", .invocationId = try json.field(record, "invocationId"), .sequence = try json.field(record, "sequence"), .ok = accepted, .accepted = accepted, .@"error" = if (accepted) "" else "rejected-for-test" });
}
fn isEvent(value: std.json.Value) bool {
    const kind = value.object.get("type") orelse return false;
    return kind == .string and std.mem.eql(u8, kind.string, "provider_stream_event");
}
fn failure(value: std.json.Value, message: []const u8) !void {
    try std.testing.expectEqual(std.json.Value{ .bool = false }, try json.field(value, "ok"));
    const err = try json.field(value, "error");
    if (std.mem.indexOf(u8, err.string, message) == null) std.debug.print("Stream failure mismatch: {s}\n", .{err.string});
    try std.testing.expect(std.mem.indexOf(u8, err.string, message) != null);
}

test "native raw stream preserves ordered deltas terminal errors cancellation queue bound ACK rejection and reuse" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "stream.mjs", .data = fixture.source });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const source = try std.fs.path.join(gpa, &.{ buffer[0..length], "stream.mjs" });
    defer gpa.free(source);
    var env = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer env.deinit();
    const binary = try pty.executablePath(gpa, io, env.get("PI_TEST_BINARY") orelse if (builtin.os.tag == .windows) "zig-out/bin/pi.exe" else "zig-out/bin/pi");
    defer gpa.free(binary);
    const errors = try tmp.dir.createFile(io, "stderr.log", .{});
    defer errors.close(io);
    const worker = try peer.Peer.start(gpa, io, binary, source, errors);
    defer worker.deinit();
    const ready = try worker.record();
    defer ready.deinit();
    try json.text(try json.field(ready.value, "type"), "ready");
    var registration: ?std.json.Value = null;
    for ((try json.field(try json.field(ready.value, "manifest"), "providers")).array.items) |item| {
        if (std.mem.eql(u8, (try json.field(item, "name")).string, "stream-production-e2e")) registration = try json.field(item, "config");
    }
    const descriptor = try json.field(registration orelse return error.MissingProvider, "streamSimple");
    try json.text(try json.field(descriptor, "__pi_callback_kind"), "provider_method");
    try json.text(try json.field(descriptor, "__pi_callback_path"), "streamSimple");
    const callback = (try json.field(descriptor, "__pi_callback_id")).string;
    const generation = (try json.field(descriptor, "__pi_callback_generation")).integer;
    try std.testing.expect(callback.len > 0);
    try start(worker, callback, generation, "1", "good");
    var count: i64 = 0;
    var text_count: usize = 0;
    const expected_deltas = [_][]const u8{ "A", "", "🚀" };
    var last_done = false;
    while (true) {
        const record = try worker.record();
        defer record.deinit();
        if (!isEvent(record.value)) {
            if (record.value.object.get("error")) |err| std.debug.print("Successful stream rejected: {s}\n", .{err.string});
            try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(record.value, "ok"));
            const result = try json.field(record.value, "result");
            try json.text(try json.field(result, "invocationId"), "1");
            try std.testing.expectEqual(count, (try json.field(result, "events")).integer);
            try json.text(try json.field(result, "terminal"), "done");
            break;
        }
        count += 1;
        try std.testing.expectEqual(count, (try json.field(record.value, "sequence")).integer);
        const event = try json.field(record.value, "event");
        const kind = (try json.field(event, "type")).string;
        if (std.mem.eql(u8, kind, "text_delta")) {
            try std.testing.expect(text_count < expected_deltas.len);
            try json.text(try json.field(event, "delta"), expected_deltas[text_count]);
            text_count += 1;
        }
        last_done = std.mem.eql(u8, kind, "done");
        if (last_done) {
            const content = (try json.field(try json.field(event, "message"), "content")).array.items;
            try std.testing.expectEqual(@as(i64, 1), (try json.field(try json.field(try json.field(content[2], "arguments"), "nested"), "a")).integer);
        }
        try ack(worker, record.value, true);
    }
    try std.testing.expectEqual(@as(usize, 3), text_count);
    try std.testing.expect(last_done);
    try start(worker, callback, generation, "2", "throw-after-terminal");
    var terminal_seen = false;
    while (true) {
        const record = try worker.record();
        defer record.deinit();
        if (isEvent(record.value)) {
            if (std.mem.eql(u8, (try json.field(try json.field(record.value, "event"), "type")).string, "done")) terminal_seen = true;
            try ack(worker, record.value, true);
        } else {
            try std.testing.expect(terminal_seen);
            try failure(record.value, "iterator-exploded-after-terminal-185");
            break;
        }
    }
    try start(worker, callback, generation, "3", "tool-mismatch");
    while (true) {
        const record = try worker.record();
        defer record.deinit();
        if (isEvent(record.value)) try ack(worker, record.value, true) else {
            try failure(record.value, "NativeProviderToolArgumentsMismatch");
            break;
        }
    }
    for ([_]struct { id: []const u8, mode: []const u8, reason: []const u8, acknowledge: bool }{
        .{ .id = "4", .mode = "cancel", .reason = "cancelled-by-native-185", .acknowledge = false },
        .{ .id = "5", .mode = "cancel-ignores-signal", .reason = "ignored-signal-abort-185", .acknowledge = true },
    }) |case| {
        try start(worker, callback, generation, case.id, case.mode);
        const first = try worker.record();
        defer first.deinit();
        try std.testing.expect(isEvent(first.value));
        try json.text(try json.field(try json.field(first.value, "event"), "type"), "start");
        if (case.acknowledge) try ack(worker, first.value, true);
        try worker.send(.{ .kind = "abort_current", .invocationId = case.id, .reason = case.reason });
        const cancelled = try worker.record();
        defer cancelled.deinit();
        try failure(cancelled.value, case.reason);
    }
    try start(worker, callback, generation, "6", "queue-overflow");
    const overflow = try worker.record();
    defer overflow.deinit();
    try failure(overflow.value, "bounded pending queue");
    try start(worker, callback, generation, "7", "good");
    const rejected_event = try worker.record();
    defer rejected_event.deinit();
    try std.testing.expect(isEvent(rejected_event.value));
    try ack(worker, rejected_event.value, false);
    const rejected = try worker.record();
    defer rejected.deinit();
    try failure(rejected.value, "rejected-for-test");
    try worker.send(.{ .kind = "command", .name = "stream-ping", .rawArguments = "", .flags = std.json.Value{ .object = .empty }, .invocationId = "8", .context = .{ .mode = "print", .hasUI = false } });
    var notified = false;
    while (true) {
        const record = try worker.record();
        defer record.deinit();
        if (record.value.object.contains("ok")) {
            try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(record.value, "ok"));
            break;
        }
        const bytes = try std.json.Stringify.valueAlloc(gpa, record.value, .{});
        defer gpa.free(bytes);
        if (std.mem.indexOf(u8, bytes, "stream-worker-reused-185") != null) notified = true;
    }
    try std.testing.expect(notified);
    try worker.shutdown();
    const stderr = try tmp.dir.readFileAlloc(io, "stderr.log", gpa, .limited(65536));
    defer gpa.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
    std.debug.print("NATIVE_PROVIDER_STREAM_RAW_185=PASS ({d} ordered events)\n", .{count});
}
