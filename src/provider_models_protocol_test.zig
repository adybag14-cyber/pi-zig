//! Original refresh-model publication gates through the actual native worker.
const std = @import("std");
const builtin = @import("builtin");
const peer = @import("test_support/native_peer.zig");
const fixture = @import("test_support/provider_models_extension_fixture.zig");
const json = @import("test_support/json_fixture.zig");
const pty = @import("test_support/pty.zig");
fn start(worker: *peer.Peer, descriptor: std.json.Value, provider: []const u8, id: []const u8, context: anytype) !void {
    try worker.send(.{ .kind = "provider_refresh_models", .callbackId = try json.field(descriptor, "__pi_callback_id"), .callbackGeneration = try json.field(descriptor, "__pi_callback_generation"), .providerName = provider, .refreshContext = context, .abortable = true, .invocationId = id, .context = .{ .mode = "print", .hasUI = false } });
}
fn model(id: []const u8, name: []const u8) Model {
    return .{ .id = id, .name = name };
}
const Model = struct { id: []const u8, name: []const u8, reasoning: bool = false, input: [1][]const u8 = .{"text"}, cost: struct { input: u32 = 0, output: u32 = 0, cacheRead: u32 = 0, cacheWrite: u32 = 0 } = .{}, contextWindow: u32 = 4096, maxTokens: u32 = 512 };
fn request(worker: *peer.Peer, method: []const u8) !std.json.Parsed(std.json.Value) {
    const record = try worker.record();
    errdefer record.deinit();
    if (record.value.object.get("error")) |err| std.debug.print("Native model publication rejected: {s}\n", .{err.string});
    try json.text(try json.field(record.value, "type"), "ui_request");
    try json.text(try json.field(record.value, "method"), method);
    return record;
}
fn respond(worker: *peer.Peer, record: std.json.Value, invocation: []const u8, accepted: bool) !void {
    try worker.send(.{ .kind = "ui_response", .invocationId = invocation, .id = try json.field(record, "id"), .ok = true, .result = accepted });
}
fn result(worker: *peer.Peer) !std.json.Parsed(std.json.Value) {
    const record = try worker.record();
    errdefer record.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(record.value, "ok"));
    return record;
}
fn firstModel(value: std.json.Value, field: []const u8) !std.json.Value {
    return (try json.field(try json.field(value, field), "models")).array.items[0];
}
fn failure(value: std.json.Value, message: []const u8) !void {
    try std.testing.expectEqual(std.json.Value{ .bool = false }, try json.field(value, "ok"));
    try std.testing.expect(std.mem.indexOf(u8, (try json.field(value, "error")).string, message) != null);
}
fn ping(worker: *peer.Peer, id: []const u8, expected: ?[]const u8) !void {
    try worker.send(.{ .kind = "command", .name = "refresh-ping", .rawArguments = "", .flags = std.json.Value{ .object = .empty }, .invocationId = id, .context = .{ .mode = "interactive", .hasUI = true } });
    var notified = false;
    while (true) {
        const record = try worker.record();
        defer record.deinit();
        if (record.value.object.contains("ok")) {
            try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(record.value, "ok"));
            break;
        }
        if (expected) |text| {
            const encoded = try std.json.Stringify.valueAlloc(worker.gpa, record.value, .{});
            defer worker.gpa.free(encoded);
            if (std.mem.indexOf(u8, encoded, text) != null) notified = true;
        }
    }
    if (expected != null) try std.testing.expect(notified);
}
test "native raw refresh models preserves frozen snapshots publication ACKs object provider stale abort and reuse" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "models.mjs", .data = fixture.source });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const source = try std.fs.path.join(gpa, &.{ buffer[0..length], "models.mjs" });
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
    var descriptor: ?std.json.Value = null;
    var object_descriptor: ?std.json.Value = null;
    for ((try json.field(try json.field(ready.value, "manifest"), "providers")).array.items) |item| {
        const name = (try json.field(item, "name")).string;
        const config = try json.field(item, "config");
        if (std.mem.eql(u8, name, "refresh-production-e2e")) descriptor = try json.field(config, "refreshModels");
        if (std.mem.eql(u8, name, "object-refresh-production-e2e")) object_descriptor = try json.field(config, "refreshModels");
    }
    try std.testing.expect(descriptor != null and object_descriptor != null);
    try json.text(try json.field(descriptor.?, "__pi_callback_kind"), "provider_method");
    try json.text(try json.field(descriptor.?, "__pi_callback_path"), "refreshModels");
    try json.text(try json.field(object_descriptor.?, "__pi_callback_path"), "refreshModels");
    const provider = "refresh-production-e2e";
    try start(worker, descriptor.?, provider, "1", .{ .generation = 1, .allowNetwork = false, .credential = .{ .type = "api_key", .key = "local" }, .stored = .{ .models = [_]Model{model("cached", "Cached")}, .checkedAt = 1 } });
    const offline = try request(worker, "provider_models_publish");
    defer offline.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = false }, try json.field(try json.field(offline.value, "args"), "hasPersist"));
    try respond(worker, offline.value, "1", true);
    const offline_catalog = try request(worker, "provider_models_catalog");
    defer offline_catalog.deinit();
    try json.text(try json.field(try firstModel(offline_catalog.value, "args"), "name"), "Cached:updated");
    try respond(worker, offline_catalog.value, "1", true);
    const offline_result = try result(worker);
    defer offline_result.deinit();
    try json.text(try json.field(try firstModel(offline_result.value, "result"), "id"), "cached");
    try start(worker, descriptor.?, provider, "2", .{ .generation = 2, .allowNetwork = true, .force = true, .credential = .{ .type = "oauth", .access = "a", .refresh = "r", .expires = @as(i64, 9999999999999), .tenant = "corp" }, .stored = .{ .models = [_]Model{model("cached", "cached")}, .checkedAt = 1 } });
    const online = try request(worker, "provider_models_publish");
    defer online.deinit();
    const online_args = try json.field(online.value, "args");
    try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(online_args, "hasPersist"));
    const persist = try json.field(online_args, "persist");
    try std.testing.expectEqual(@as(i64, 183), (try json.field(persist, "checkedAt")).integer);
    try json.text(try json.field(persist, "etag"), "\"etag-183\"");
    try respond(worker, online.value, "2", true);
    const online_catalog = try request(worker, "provider_models_catalog");
    defer online_catalog.deinit();
    try json.text(try json.field(try firstModel(online_catalog.value, "args"), "name"), "Fresh:committed");
    try respond(worker, online_catalog.value, "2", true);
    const online_result = try result(worker);
    defer online_result.deinit();
    try json.text(try json.field(try firstModel(online_result.value, "result"), "name"), "Fresh");
    try start(worker, object_descriptor.?, "object-refresh-production-e2e", "3", .{ .generation = 1, .allowNetwork = false, .credential = .{ .type = "api_key", .key = "local" } });
    const object_publish = try request(worker, "provider_models_publish");
    defer object_publish.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = false }, try json.field(try json.field(object_publish.value, "args"), "hasPersist"));
    try respond(worker, object_publish.value, "3", true);
    const object_catalog = try request(worker, "provider_models_catalog");
    defer object_catalog.deinit();
    try json.text(try json.field(try firstModel(object_catalog.value, "args"), "id"), "object-fresh");
    try respond(worker, object_catalog.value, "3", true);
    const object_result = try result(worker);
    defer object_result.deinit();
    try json.text(try json.field(try firstModel(object_result.value, "result"), "name"), "Object Fresh");
    try start(worker, descriptor.?, provider, "4", .{ .generation = 3, .allowNetwork = false, .stored = .{ .mode = "stale", .models = [_]Model{model("old", "old")} } });
    const stale = try request(worker, "provider_models_publish");
    defer stale.deinit();
    try respond(worker, stale.value, "4", false);
    const stale_result = try result(worker);
    defer stale_result.deinit();
    try json.text(try json.field(try firstModel(stale_result.value, "result"), "id"), "stale-result");
    try ping(worker, "5", "Fresh:committed");
    try start(worker, descriptor.?, provider, "6", .{ .generation = 4, .allowNetwork = false, .stored = .{ .mode = "abort", .models = [0]Model{} } });
    const pending = try request(worker, "provider_models_publish");
    defer pending.deinit();
    try worker.send(.{ .kind = "abort_current", .invocationId = "6", .reason = "Operation aborted" });
    const aborted = try worker.record();
    defer aborted.deinit();
    try failure(aborted.value, "Operation aborted");
    try start(worker, descriptor.?, provider, "7", .{ .generation = 5, .allowNetwork = false, .stored = .{ .mode = "reject", .models = [0]Model{} } });
    const rejected = try worker.record();
    defer rejected.deinit();
    try failure(rejected.value, "refresh-models-exploded-183");
    try failure(rejected.value, "refreshModels");
    try ping(worker, "8", null);
    try worker.shutdown();
    const stderr = try tmp.dir.readFileAlloc(io, "stderr.log", gpa, .limited(65536));
    defer gpa.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
    std.debug.print("NATIVE_PROVIDER_MODELS_RAW_183=PASS\n", .{});
}
