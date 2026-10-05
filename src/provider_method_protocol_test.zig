//! Original provider-manifest raw protocol gates through the actual C worker.
const std = @import("std");
const builtin = @import("builtin");
const peer = @import("test_support/native_peer.zig");
const fixture = @import("test_support/provider_method_extension_fixture.zig");
const json = @import("test_support/json_fixture.zig");
const pty = @import("test_support/pty.zig");
fn descriptor(root: std.json.Value, path: []const u8) ![]const u8 {
    var current = root;
    var parts = std.mem.splitScalar(u8, path, '.');
    while (parts.next()) |part| {
        if (current == .array) current = current.array.items[try std.fmt.parseInt(usize, part, 10)] else current = try json.field(current, part);
    }
    try json.text(try json.field(current, "__pi_callback_kind"), "provider_method");
    try json.text(try json.field(current, "__pi_callback_path"), path);
    const id = try json.field(current, "__pi_callback_id");
    try std.testing.expect(id == .string and id.string.len > 0);
    return id.string;
}
fn invoke(worker: *peer.Peer, id: []const u8, args: anytype, signal: bool, invocation: u64) !std.json.Parsed(std.json.Value) {
    const wire_id = try std.fmt.allocPrint(worker.gpa, "{d}", .{invocation});
    defer worker.gpa.free(wire_id);
    try worker.send(.{ .kind = "provider_method", .callbackId = id, .args = args, .appendSignal = signal, .abortable = signal, .invocationId = wire_id, .context = .{ .mode = "print", .hasUI = false } });
    return final(worker);
}
fn final(worker: *peer.Peer) !std.json.Parsed(std.json.Value) {
    while (true) {
        const record = try worker.record();
        if (record.value.object.contains("ok")) return record;
        defer record.deinit();
        try json.text(try json.field(record.value, "type"), "ui_action");
        const encoded = try std.json.Stringify.valueAlloc(worker.gpa, record.value, .{});
        errdefer worker.gpa.free(encoded);
        try worker.actions.append(worker.gpa, encoded);
    }
}
fn command(worker: *peer.Peer, name: []const u8, id: u64) !std.json.Parsed(std.json.Value) {
    const wire_id = try std.fmt.allocPrint(worker.gpa, "{d}", .{id});
    defer worker.gpa.free(wire_id);
    try worker.send(.{ .kind = "command", .name = name, .rawArguments = "", .flags = std.json.Value{ .object = .empty }, .invocationId = wire_id, .context = .{ .mode = "print", .hasUI = false } });
    return final(worker);
}
fn ok(value: std.json.Value) !std.json.Value {
    if ((try json.field(value, "ok")) == .bool and !(try json.field(value, "ok")).bool) {
        const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, value, .{});
        defer std.testing.allocator.free(encoded);
        std.debug.print("Native provider raw failure: {s}\n", .{encoded});
    }
    try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(value, "ok"));
    return json.field(value, "result");
}
test "native provider raw manifest preserves closure receiver signal replacement cycle rejection and unregister" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "provider.mjs", .data = fixture.source });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const source = try std.fs.path.join(gpa, &.{ buffer[0..length], "provider.mjs" });
    defer gpa.free(source);
    var env = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer env.deinit();
    const binary = try pty.executablePath(gpa, io, env.get("PI_TEST_BINARY") orelse if (builtin.os.tag == .windows) "zig-out/bin/pi.exe" else "zig-out/bin/pi");
    defer gpa.free(binary);
    const errors_file = try tmp.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    const worker = try peer.Peer.start(gpa, io, binary, source, errors_file);
    defer worker.deinit();
    const ready = try worker.record();
    defer ready.deinit();
    try json.text(try json.field(ready.value, "type"), "ready");
    const providers = (try json.field(try json.field(ready.value, "manifest"), "providers")).array.items;
    var config: ?std.json.Value = null;
    for (providers) |registration| {
        const name = try json.field(registration, "name");
        if (std.mem.eql(u8, name.string, "production-e2e")) config = try json.field(registration, "config");
    }
    try std.testing.expect(config != null);
    const refresh = try descriptor(config.?, "oauth.refreshToken");
    const key = try descriptor(config.?, "oauth.getApiKey");
    const wait = try descriptor(config.?, "oauth.waitForAbort");
    const nested = try descriptor(config.?, "nested.methods.0");
    const manifest = try std.json.Stringify.valueAlloc(gpa, config.?, .{});
    defer gpa.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "production-bridge-181") == null);
    const refreshed = try invoke(worker, refresh, [_]struct { refresh: []const u8 }{.{ .refresh = "r181" }}, true, 1);
    defer refreshed.deinit();
    try json.text(try json.field(try json.field(try ok(refreshed.value), "value"), "access"), "production-bridge-181:r181");
    const api_key = try invoke(worker, key, [_]struct { access: []const u8 }{.{ .access = "a181" }}, false, 2);
    defer api_key.deinit();
    try json.text(try json.field(try ok(api_key.value), "value"), "production-bridge-181:a181");
    const nested_result = try invoke(worker, nested, [_][]const u8{"array"}, false, 3);
    defer nested_result.deinit();
    try json.text(try json.field(try ok(nested_result.value), "value"), "1:production-bridge-181:array");
    try worker.send(.{ .kind = "provider_method", .callbackId = wait, .args = [_]struct {}{.{}}, .appendSignal = true, .abortable = true, .invocationId = "4", .context = .{ .mode = "print", .hasUI = false } });
    try io.sleep(.fromMilliseconds(30), .awake);
    try worker.send(.{ .kind = "abort_current", .invocationId = "4", .reason = "Operation aborted" });
    const aborted = try worker.record();
    defer aborted.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = false }, try json.field(aborted.value, "ok"));
    try std.testing.expect(std.mem.indexOf(u8, (try json.field(aborted.value, "error")).string, "Operation aborted") != null);
    const replaced = try command(worker, "provider-replace", 5);
    defer replaced.deinit();
    const actions = (try json.field(try ok(replaced.value), "actionQueue")).array.items;
    var replacement: ?std.json.Value = null;
    for (actions) |action| {
        const name = try json.field(action, "name");
        if (std.mem.eql(u8, name.string, "production-e2e")) replacement = try json.field(action, "config");
    }
    try std.testing.expect(replacement != null);
    try json.text(try json.field(replacement.?, "name"), "Provider E2E Renamed");
    const next = try descriptor(replacement.?, "oauth.refreshToken");
    try std.testing.expect(!std.mem.eql(u8, refresh, next));
    const old = try invoke(worker, refresh, [_]struct { refresh: []const u8 }{.{ .refresh = "old" }}, true, 6);
    defer old.deinit();
    try json.text(try json.field(try json.field(try ok(old.value), "value"), "access"), "production-bridge-181:old");
    const fresh = try invoke(worker, next, [_]struct { refresh: []const u8 }{.{ .refresh = "new" }}, true, 7);
    defer fresh.deinit();
    try json.text(try json.field(try json.field(try ok(fresh.value), "value"), "access"), "production-bridge-181:new");
    const cycle = try command(worker, "provider-cycle", 8);
    defer cycle.deinit();
    _ = try ok(cycle.value);
    const after_cycle = try invoke(worker, next, [_]struct { refresh: []const u8 }{.{ .refresh = "after-cycle" }}, true, 9);
    defer after_cycle.deinit();
    try json.text(try json.field(try json.field(try ok(after_cycle.value), "value"), "access"), "production-bridge-181:after-cycle");
    const removed = try command(worker, "provider-unregister", 10);
    defer removed.deinit();
    var unregistered = false;
    for ((try json.field(try ok(removed.value), "actionQueue")).array.items) |action| {
        if (std.mem.eql(u8, (try json.field(action, "type")).string, "unregister_provider") and std.mem.eql(u8, (try json.field(action, "name")).string, "production-e2e")) unregistered = true;
    }
    try std.testing.expect(unregistered);
    const unavailable = try invoke(worker, next, [_]struct {}{.{}}, true, 11);
    defer unavailable.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = false }, try json.field(unavailable.value, "ok"));
    try std.testing.expect(std.mem.indexOf(u8, (try json.field(unavailable.value, "error")).string, "UnknownNativeProviderCallback") != null);
    const ping = try command(worker, "provider-ping", 12);
    defer ping.deinit();
    _ = try ok(ping.value);
    var notified = false;
    for (worker.actions.items) |action| if (std.mem.indexOf(u8, action, "worker-reused") != null) {
        notified = true;
    };
    try std.testing.expect(notified);
    try worker.shutdown();
    const errors = try tmp.dir.readFileAlloc(io, "stderr.log", gpa, .limited(65536));
    defer gpa.free(errors);
    try std.testing.expectEqualStrings("", errors);
    std.debug.print("NATIVE_PROVIDER_METHOD_RAW_181=PASS\n", .{});
}
