//! Original OAuth login raw protocol behavior, driven by Zig without Node.
const std = @import("std");
const builtin = @import("builtin");
const peer = @import("test_support/native_peer.zig");
const fixture = @import("test_support/provider_oauth_extension_fixture.zig");
const json = @import("test_support/json_fixture.zig");
const pty = @import("test_support/pty.zig");
fn login(worker: *peer.Peer, callback: []const u8, generation: i64, id: []const u8) !void {
    try worker.send(.{ .kind = "provider_oauth_login", .callbackId = callback, .providerName = "oauth-production-e2e", .callbackGeneration = generation, .abortable = true, .invocationId = id, .context = .{ .mode = "interactive", .hasUI = true } });
}
fn ok(value: std.json.Value) !std.json.Value {
    if (value.object.get("error")) |err| std.debug.print("OAuth native rejection: {s}\n", .{err.string});
    try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(value, "ok"));
    return json.field(value, "result");
}
fn failure(value: std.json.Value, message: []const u8) !void {
    try std.testing.expectEqual(std.json.Value{ .bool = false }, try json.field(value, "ok"));
    try std.testing.expect(std.mem.indexOf(u8, (try json.field(value, "error")).string, message) != null);
}
test "native raw OAuth preserves callbacks credential payload pending prompt abort reuse failure and unregister" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "oauth.mjs", .data = fixture.source });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const source = try std.fs.path.join(gpa, &.{ buffer[0..length], "oauth.mjs" });
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
    var config: ?std.json.Value = null;
    for ((try json.field(try json.field(ready.value, "manifest"), "providers")).array.items) |item| {
        if (std.mem.eql(u8, (try json.field(item, "name")).string, "oauth-production-e2e")) config = try json.field(item, "config");
    }
    const descriptor = try json.field(try json.field(config orelse return error.MissingProvider, "oauth"), "login");
    try json.text(try json.field(descriptor, "__pi_callback_kind"), "provider_method");
    try json.text(try json.field(descriptor, "__pi_callback_path"), "oauth.login");
    const callback = (try json.field(descriptor, "__pi_callback_id")).string;
    const generation = (try json.field(descriptor, "__pi_callback_generation")).integer;
    try std.testing.expect(callback.len > 0);
    const encoded = try std.json.Stringify.valueAlloc(gpa, config.?, .{});
    defer gpa.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "oauth-login-exploded-182") == null);
    try login(worker, callback, generation, "1");
    const action_methods = [_][]const u8{ "oauth_auth", "oauth_device_code", "oauth_progress" };
    const request_methods = [_][]const u8{ "oauth_prompt", "oauth_manual_code", "oauth_select" };
    const replies = [_][]const u8{ "tenant-answer", "manual-code-182", "team-b" };
    var actions: usize = 0;
    var requests: usize = 0;
    while (true) {
        const record = try worker.record();
        defer record.deinit();
        if (record.value.object.contains("ok")) {
            const value = try json.field(try ok(record.value), "value");
            try json.text(try json.field(value, "refresh"), "refresh-182");
            try json.text(try json.field(value, "access"), "access-182");
            try std.testing.expectEqual(@as(i64, 9999999999999), (try json.field(value, "expires")).integer);
            const tenant = try json.field(value, "tenant");
            try json.text(try json.field(tenant, "prompt"), replies[0]);
            try json.text(try json.field(tenant, "manual"), replies[1]);
            try json.text(try json.field(tenant, "team"), replies[2]);
            const arbitrary = try json.field(value, "arbitrary");
            try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(arbitrary, "retained"));
            try std.testing.expectEqual(@as(i64, 1), (try json.field(arbitrary, "generation")).integer);
            break;
        }
        const kind = (try json.field(record.value, "type")).string;
        const args = try json.field(record.value, "args");
        if (std.mem.eql(u8, kind, "ui_action")) {
            try std.testing.expect(actions < action_methods.len);
            try json.text(try json.field(record.value, "method"), action_methods[actions]);
            if (actions == 0) try json.text(try json.field(args, "url"), "https://login.invalid/start");
            if (actions == 1) {
                try json.text(try json.field(args, "userCode"), "DEVICE-182");
                try std.testing.expectEqual(@as(i64, 7), (try json.field(args, "intervalSeconds")).integer);
                try std.testing.expectEqual(@as(i64, 600), (try json.field(args, "expiresInSeconds")).integer);
            }
            actions += 1;
        } else {
            try json.text(try json.field(record.value, "type"), "ui_request");
            try std.testing.expect(requests < request_methods.len);
            try json.text(try json.field(record.value, "method"), request_methods[requests]);
            if (requests == 0) try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(args, "secret"));
            if (requests == 2) try json.text(try json.field((try json.field(args, "options")).array.items[1], "description"), "Preferred");
            try worker.send(.{ .kind = "ui_response", .invocationId = "1", .id = try json.field(record.value, "id"), .ok = true, .result = replies[requests] });
            requests += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), actions);
    try std.testing.expectEqual(@as(usize, 3), requests);
    try login(worker, callback, generation, "2");
    const prompt = try worker.record();
    defer prompt.deinit();
    try json.text(try json.field(prompt.value, "type"), "ui_request");
    try json.text(try json.field(prompt.value, "method"), "oauth_prompt");
    try worker.send(.{ .kind = "abort_current", .invocationId = "2", .reason = "Operation aborted" });
    const aborted = try worker.record();
    defer aborted.deinit();
    try failure(aborted.value, "Operation aborted");
    try login(worker, callback, generation, "3");
    const reused = try worker.record();
    defer reused.deinit();
    try json.text(try json.field(try json.field(try ok(reused.value), "value"), "access"), "worker-reused-after-abort");
    try login(worker, callback, generation, "4");
    const rejected = try worker.record();
    defer rejected.deinit();
    try failure(rejected.value, "oauth-login-exploded-182");
    try failure(rejected.value, "login");
    try worker.send(.{ .kind = "command", .name = "oauth-unregister", .rawArguments = "", .flags = std.json.Value{ .object = .empty }, .invocationId = "5", .context = .{ .mode = "print", .hasUI = false } });
    const removed = try worker.record();
    defer removed.deinit();
    var unregistered = false;
    for ((try json.field(try ok(removed.value), "actionQueue")).array.items) |action| {
        if (std.mem.eql(u8, (try json.field(action, "type")).string, "unregister_provider") and std.mem.eql(u8, (try json.field(action, "name")).string, "oauth-production-e2e")) unregistered = true;
    }
    try std.testing.expect(unregistered);
    try login(worker, callback, generation, "6");
    const unavailable = try worker.record();
    defer unavailable.deinit();
    try failure(unavailable.value, "UnknownNativeProviderCallback");
    try worker.shutdown();
    const stderr = try tmp.dir.readFileAlloc(io, "stderr.log", gpa, .limited(65536));
    defer gpa.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
    std.debug.print("NATIVE_PROVIDER_OAUTH_RAW_182=PASS\n", .{});
}
