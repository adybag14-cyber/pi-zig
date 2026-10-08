test "native SDK SessionManager Source retained identity compaction edits branches and public migration helpers" {
    try inputCase(@embedFile("extensions/fixtures/sdk-session-manager-options-6fb2e78.input.json"), @embedFile("extensions/fixtures/sdk-session-manager-options-6fb2e78.json"));
}
const std = @import("std");
const builtin = @import("builtin");
test "native SDK private session contexts retain exact registry affinity and reject stale getters" {
    try inputCase(@embedFile("extensions/fixtures/sdk-private-context-models-6fb2e78.input.json"), @embedFile("extensions/fixtures/sdk-private-context-models-6fb2e78.json"));
}
test "native SDK SettingsManager storage queue scoped merge trust failures reload and migration match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-settings-storage-6fb2e78.input.json"), @embedFile("extensions/fixtures/sdk-settings-storage-6fb2e78.json"));
}
test "native SDK selected API version and current source lifecycle are independent of CLI certification" {
    try inputCase(@embedFile("extensions/fixtures/sdk-lifecycle-version-6fb2e78.input.json"), @embedFile("extensions/fixtures/sdk-lifecycle-version-6fb2e78.json"));
}
test "native SDK SettingsManager getter facade defaults overrides mutations and isolation match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-settings-6fb2e78.input.json"), @embedFile("extensions/fixtures/sdk-settings-6fb2e78.json"));
}
test "native SDK API streams and deferred fetch cancel auth and error contracts match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-stream-modes-6fb2e78.input.json"), @embedFile("extensions/fixtures/sdk-stream-modes-6fb2e78.json"));
}
test "native SDK virtual session user continuation branch state and physical responses match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-virtual-session-6fb2e78.input.json"), @embedFile("extensions/fixtures/sdk-virtual-session-6fb2e78.json"));
}
test "native SDK virtual routing reentry retired definitions cancellation and credentials match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-virtual-races-6fb2e78.input.json"), @embedFile("extensions/fixtures/sdk-virtual-races-6fb2e78.json"));
}
test "native SDK virtual catalog routing canonical targets filters and direct streams match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-virtual-6fb2e78.input.json"), @embedFile("extensions/fixtures/sdk-virtual-6fb2e78.json"));
}
test "native SDK request headers preserve model provider and configured precedence and resolution identity" {
    try inputCase(@embedFile("extensions/fixtures/sdk-model-headers-1cedd32.input.json"), @embedFile("extensions/fixtures/sdk-model-headers-1cedd32.json"));
}
const http_fixture = @import("ai/http_fixture.zig");
const EnvValue = struct { name: []const u8, value: []const u8 };
test "native SDK 1.1 settled event includes actual abort request flag" {
    try inputCase(@embedFile("extensions/fixtures/sdk-settled-1cedd32.input.json"), @embedFile("extensions/fixtures/sdk-settled-1cedd32.json"));
}
test "native SDK models JSONC immutable load reload composition and errors match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-model-config-1cedd32.input.json"), @embedFile("extensions/fixtures/sdk-model-config-1cedd32.json"));
}
test "native SDK models schema validation ordering unions and bounded diagnostics match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-config-schema-6fb2e78.input.json"), @embedFile("extensions/fixtures/sdk-config-schema-6fb2e78.json"));
}
test "native SDK configured auth templates request environment and headers match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-config-auth-1cedd32.input.json"), @embedFile("extensions/fixtures/sdk-config-auth-1cedd32.json"));
}
test "native SDK config native extension precedence dynamic rows reload and restoration match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-config-overlays-1cedd32.input.json"), @embedFile("extensions/fixtures/sdk-config-overlays-1cedd32.json"));
}
test "native SDK auth caller abort credential errors and live callbacks match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-auth-resolution-1cedd32.input.json"), @embedFile("extensions/fixtures/sdk-auth-resolution-1cedd32.json"));
}
test "native SDK OAuth auth validity floor rotation and cancellation match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-auth-oauth-1cedd32.input.json"), @embedFile("extensions/fixtures/sdk-auth-oauth-1cedd32.json"));
}
test "native SDK cached auth status and runtime key synchronization match actual source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-auth-snapshot-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-auth-snapshot-7fb59f9.json"));
}
test "native stored provider registration publishes source provisional configured state" {
    try inputCase(@embedFile("extensions/fixtures/sdk-auth-provisional-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-auth-provisional-7fb59f9.json"));
}
test "native OAuth subscription status and error constructor inheritance match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-oauth-status-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-oauth-status-7fb59f9.json"));
}
test "native SDK credential errors queued cancel and retained committed key match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-credential-sync-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-credential-sync-7fb59f9.json"));
}
test "native SDK active key cancellation preserves committed key and source error class" {
    try inputCase(@embedFile("extensions/fixtures/sdk-active-key-cancel-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-active-key-cancel-7fb59f9.json"));
}
test "native SDK stale availability queries preserve newest error and cached state" {
    try inputCase(@embedFile("extensions/fixtures/sdk-auth-races-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-auth-races-7fb59f9.json"));
}
test "native SDK availability shares caller or local signals across auth and store" {
    try inputCase(@embedFile("extensions/fixtures/sdk-auth-signals-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-auth-signals-7fb59f9.json"));
}
test "native Models refresh supports ambient auth with no effective API key" {
    try inputCase(@embedFile("extensions/fixtures/sdk-models-ambient-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-models-ambient-7fb59f9.json"));
}
test "native public model store graph clones and async abort identity match actual source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-model-store-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-model-store-7fb59f9.json"));
}
test "native public Models refresh cache network and publication matches actual source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-model-refresh-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-model-refresh-7fb59f9.json"));
}
test "native model refresh blocked write replacement cancellation and errors match actual source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-model-refresh-races-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-model-refresh-races-7fb59f9.json"));
}
test "native OAuth rotation persists after cancel and serializes the next refresh like source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-model-refresh-oauth-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-model-refresh-oauth-7fb59f9.json"));
}
test "native SDK runtime refresh creation cache selected availability and abort match source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-runtime-refresh-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-runtime-refresh-7fb59f9.json"));
}
test "native completed refresh controllers retire and stale publication returns false like source" {
    try inputCase(@embedFile("extensions/fixtures/sdk-model-refresh-retirement-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-model-refresh-retirement-7fb59f9.json"));
}
test "native SDK builtin chat HTTP stream completion and actual session prompt match original" {
    const response = "data: {\"id\":\"chat-sdk\",\"object\":\"chat.completion.chunk\",\"model\":\"fixture-model\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}\n\n" ++
        "data: {\"id\":\"chat-sdk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"SDK \"},\"finish_reason\":null}]}\n\n" ++
        "data: {\"id\":\"chat-sdk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"chat\"},\"finish_reason\":null}]}\n\n" ++
        "data: {\"id\":\"chat-sdk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":4,\"completion_tokens\":3,\"total_tokens\":7}}\n\n" ++ "data: [DONE]\n\n";
    const replies = [_]http_fixture.Reply{
        .{ .path = "/chat/chat/completions", .body = response, .headers = &.{.{ .name = "content-type", .value = "text/event-stream" }}, .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer fixture-key" }} },
        .{ .path = "/chat/chat/completions", .body = response, .headers = &.{.{ .name = "content-type", .value = "text/event-stream" }} },
        .{ .path = "/chat/chat/completions", .body = response, .headers = &.{.{ .name = "content-type", .value = "text/event-stream" }} },
    };
    const server = try http_fixture.PlanServer.init(std.testing.allocator, std.testing.io, &replies);
    defer server.deinit();
    const url = try server.url(std.testing.allocator, "/chat");
    defer std.testing.allocator.free(url);
    try inputCaseEnv(@embedFile("extensions/fixtures/sdk-chat-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-chat-7fb59f9.json"), &.{.{ .name = "SDK_CHAT_URL", .value = url }});
    try server.finish();
    try std.testing.expectEqual(@as(usize, 3), server.captured.items.len);
}
test "native SDK delayed chat and session abort results and settlement order match source" {
    for (0..2) |index| {
        const replies = [_]http_fixture.Reply{.{ .path = "/chat/completions", .body = "data: [DONE]\n\n", .delay_ms = 1000, .headers = &.{.{ .name = "content-type", .value = "text/event-stream" }}, .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer fixture-key" }} }};
        const server = try http_fixture.PlanServer.init(std.testing.allocator, std.testing.io, &replies);
        defer server.deinit();
        const url = try server.url(std.testing.allocator, "");
        defer std.testing.allocator.free(url);
        try inputCaseEnv(if (index == 0) @embedFile("extensions/fixtures/sdk-chat-cancel-7fb59f9.input.json") else @embedFile("extensions/fixtures/sdk-session-cancel-7fb59f9.input.json"), if (index == 0) @embedFile("extensions/fixtures/sdk-chat-cancel-7fb59f9.json") else @embedFile("extensions/fixtures/sdk-session-cancel-7fb59f9.json"), &.{ .{ .name = "SDK_CHAT_URL", .value = url }, .{ .name = "SDK_CANCEL_SESSION", .value = if (index == 0) "0" else "1" } });
        server.finish() catch |err| switch (err) {
            error.WriteFailed, error.ConnectionResetByPeer, error.BrokenPipe, error.HttpConnectionClosing => {},
            else => return err,
        };
        try std.testing.expectEqual(@as(usize, 1), server.captured.items.len);
    }
}
test "native SDK resource discovery and actual inline extension startup match original" {
    try inputCase(@embedFile("extensions/fixtures/sdk-resources-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-resources-7fb59f9.json"));
}
test "native SDK cached availability timing and credential-aware filters match original" {
    try inputCase(@embedFile("extensions/fixtures/sdk-availability-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-availability-7fb59f9.json"));
}
test "same full SDK input executes without Node and matches original source lifecycle capture" {
    try inputCase(@embedFile("extensions/fixtures/sdk-lifecycle-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-lifecycle-7fb59f9.json"));
}
test "native SDK typed models credentials auth transforms negative promises and selection match upstream" {
    try inputCatalogCase(@embedFile("extensions/fixtures/sdk-models-6fb2e78.input.json"), @embedFile("extensions/fixtures/sdk-models-6fb2e78.json"));
}
fn inputCase(input: []const u8, expected_output: []const u8) !void {
    return inputCaseEnv(input, expected_output, &.{});
}
fn inputCaseEnv(input: []const u8, expected_output: []const u8, additional_environment: []const EnvValue) !void {
    return inputCaseEnvCatalog(input, expected_output, additional_environment, false);
}
fn inputCatalogCase(input: []const u8, expected_output: []const u8) !void {
    return inputCaseEnvCatalog(input, expected_output, &.{}, true);
}
fn inputCaseEnvCatalog(input: []const u8, expected_output: []const u8, additional_environment: []const EnvValue, selected_catalog: bool) !void {
    const Fixture = struct { schemaVersion: u32, sourceCommit: []const u8, inputSha256: []const u8, input: []const u8 };
    var parsed = try std.json.parseFromSlice(Fixture, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.schemaVersion);
    try std.testing.expect(std.mem.eql(u8, "7fb59f995b0a1db552001a8577b234e4105d7179", parsed.value.sourceCommit) or std.mem.eql(u8, "1cedd32724abfcb0915f76cc61b6827e2c16dbad", parsed.value.sourceCommit) or std.mem.eql(u8, "6fb2e7815167e6b19006fc526d1a5d0f5f998787", parsed.value.sourceCommit));
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(parsed.value.input, &digest, .{});
    const hash = std.fmt.bytesToHex(digest, .lower);
    try std.testing.expectEqualStrings(&hash, parsed.value.inputSha256);
    try runCase(parsed.value.input, expected_output, additional_environment, selected_catalog);
}
fn runCase(input: []const u8, expected_output: []const u8, additional_environment: []const EnvValue, selected_catalog: bool) !void {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_dir = try std.Io.Dir.cwd().openDir(io, ".", .{});
    defer root_dir.close(io);
    const root_length = try root_dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_length];
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "agent");
    try temporary.dir.createDirPath(io, "workspace");
    try temporary.dir.createDirPath(io, "home");
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(io, &buffer);
    const agent = try std.fs.path.join(gpa, &.{ buffer[0..count], "agent" });
    defer gpa.free(agent);
    const home = try std.fs.path.join(gpa, &.{ buffer[0..count], "home" });
    defer gpa.free(home);
    const workspace = try std.fs.path.join(gpa, &.{ buffer[0..count], "workspace" });
    defer gpa.free(workspace);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    const binary = try std.fs.path.join(gpa, &.{ root, "zig-out", "bin", if (builtin.os.tag == .windows) "pi-sdk-embedder.exe" else "pi-sdk-embedder" });
    defer gpa.free(binary);
    const script = try std.fs.path.join(gpa, &.{ buffer[0..count], "entry.mjs" });
    defer gpa.free(script);
    try temporary.dir.writeFile(io, .{ .sub_path = "entry.mjs", .data = input });
    // The process has no Node or shell directory available for fallback.
    try environment.put("PATH", std.fs.path.dirname(binary).?);
    try environment.put("SystemRoot", "C:/Windows");
    try environment.put("WINDIR", "C:/Windows");
    try environment.put("PI_AGENT_DIR", agent);
    try environment.put("HOME", home);
    try environment.put("USERPROFILE", home);
    try environment.put("PI_OFFLINE", "1");
    try environment.put("SDK_CONFIG_DIR", workspace);
    for (additional_environment) |entry| try environment.put(entry.name, entry.value);
    const result = try std.process.run(gpa, io, .{
        .argv = &.{ binary, script },
        .cwd = .{ .path = workspace },
        .environ_map = &environment,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        std.debug.print("{s}\n", .{result.stderr});
        return error.NativeSDKCorpusFailed;
    }
    const original = expected_output;
    var expected = try std.json.parseFromSlice(std.json.Value, gpa, original, .{});
    defer expected.deinit();
    var actual = try std.json.parseFromSlice(std.json.Value, gpa, result.stdout, .{});
    defer actual.deinit();
    if (selected_catalog) {
        const exported_path = try std.fs.path.join(gpa, &.{ agent, "sdk-builtin-models.json" });
        defer gpa.free(exported_path);
        const exported_bytes = try std.Io.Dir.cwd().readFileAlloc(io, exported_path, gpa, .limited(8 * 1024 * 1024));
        defer gpa.free(exported_bytes);
        var exported = try std.json.parseFromSlice(std.json.Value, gpa, exported_bytes, .{});
        defer exported.deinit();
        var selected = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("ai/catalog_source.json"), .{});
        defer selected.deinit();
        const rows = selected.value.object.get("models").?;
        // Compare every builtin definition to the selected source catalog.
        // Captured historical counts remain unchanged provenance evidence.
        try equal(rows, exported.value);
        var counts = [_]i64{ 0, @intCast(rows.array.items.len), 0, 0 };
        for (rows.array.items) |row| {
            const kind = row.object.get("type");
            const name = if (kind) |value| value.string else "chat";
            if (std.mem.eql(u8, name, "chat")) counts[0] += 1 else if (std.mem.eql(u8, name, "image")) counts[2] += 1 else if (std.mem.eql(u8, name, "classifier")) counts[3] += 1;
        }
        const observed = actual.value.object.get("catalog").?;
        inline for (.{ "chat", "all", "images", "classifiers" }, 0..) |field, index| try std.testing.expectEqual(counts[index], observed.object.get(field).?.integer);
        const captured = expected.value.object.get("catalog").?;
        try std.testing.expectEqual(captured.object.count(), observed.object.count());
        var fields = captured.object.iterator();
        while (fields.next()) |field| {
            if (std.mem.eql(u8, field.key_ptr.*, "chat") or std.mem.eql(u8, field.key_ptr.*, "all") or std.mem.eql(u8, field.key_ptr.*, "images") or std.mem.eql(u8, field.key_ptr.*, "classifiers")) continue;
            try equal(field.value_ptr.*, observed.object.get(field.key_ptr.*) orelse return error.MissingNativeSDKField);
        }
        try std.testing.expectEqual(expected.value.object.count(), actual.value.object.count());
        fields = expected.value.object.iterator();
        while (fields.next()) |field| {
            if (std.mem.eql(u8, field.key_ptr.*, "catalog")) continue;
            try equal(field.value_ptr.*, actual.value.object.get(field.key_ptr.*) orelse return error.MissingNativeSDKField);
        }
    } else try equal(expected.value, actual.value);
}
test "native SDK builtin classifier and image HTTP results match full source capture without Node" {
    const replies = [_]http_fixture.Reply{
        .{ .path = "/class/systemone", .body = "{\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":0.9}},\"usage\":{\"input_tokens\":1,\"output_tokens\":2}}", .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer fixture-key" }} },
        .{ .path = "/image/chat/completions", .body = "{\"id\":\"sdk-img\",\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2},\"choices\":[{\"message\":{\"images\":[{\"image_url\":\"data:image/png;base64,YWJj\"}]}}]}", .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer fixture-key" }} },
    };
    const server = try http_fixture.PlanServer.init(std.testing.allocator, std.testing.io, &replies);
    defer server.deinit();
    const class_url = try server.url(std.testing.allocator, "/class");
    defer std.testing.allocator.free(class_url);
    const image_url = try server.url(std.testing.allocator, "/image");
    defer std.testing.allocator.free(image_url);
    try inputCaseEnv(@embedFile("extensions/fixtures/sdk-http-7fb59f9.input.json"), @embedFile("extensions/fixtures/sdk-http-7fb59f9.json"), &.{ .{ .name = "SDK_CLASS_URL", .value = class_url }, .{ .name = "SDK_IMAGE_URL", .value = image_url } });
    try server.finish();
}
test "native SDK builtin HTTP aborts preserve source results Promise timing and ownership" {
    for (0..2) |index| {
        const replies = [_]http_fixture.Reply{.{ .path = if (index == 0) "/systemone" else "/chat/completions", .body = "{\"answers\":{\"q\":{\"type\":\"noul\",\"noul\":0.9}}}", .delay_ms = 1000, .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer fixture-key" }} }};
        const server = try http_fixture.PlanServer.init(std.testing.allocator, std.testing.io, &replies);
        defer server.deinit();
        const url = try server.url(std.testing.allocator, "");
        defer std.testing.allocator.free(url);
        try inputCaseEnv(@embedFile("extensions/fixtures/sdk-http-cancel-7fb59f9.input.json"), if (index == 0) @embedFile("extensions/fixtures/sdk-http-cancel-7fb59f9.json") else @embedFile("extensions/fixtures/sdk-image-cancel-7fb59f9.json"), &.{ .{ .name = "SDK_CLASS_URL", .value = url }, .{ .name = "SDK_KIND", .value = if (index == 0) "classifier" else "image" } });
        server.finish() catch |err| switch (err) {
            error.WriteFailed, error.ConnectionResetByPeer, error.BrokenPipe, error.HttpConnectionClosing => {},
            else => return err,
        };
        try std.testing.expectEqual(@as(usize, 1), server.captured.items.len);
    }
}
fn equal(expected: std.json.Value, actual: std.json.Value) !void {
    try std.testing.expectEqual(std.meta.activeTag(expected), std.meta.activeTag(actual));
    switch (expected) {
        .object => |fields| {
            try std.testing.expectEqual(fields.count(), actual.object.count());
            var it = fields.iterator();
            while (it.next()) |field| try equal(field.value_ptr.*, actual.object.get(field.key_ptr.*) orelse return error.MissingNativeSDKField);
        },
        .array => |items| {
            try std.testing.expectEqual(items.items.len, actual.array.items.len);
            for (items.items, actual.array.items) |lhs, rhs| try equal(lhs, rhs);
        },
        .string => |value| try std.testing.expectEqualStrings(value, actual.string),
        .integer => |value| try std.testing.expectEqual(value, actual.integer),
        .float => |value| try std.testing.expectApproxEqAbs(value, actual.float, 1e-12),
        .bool => |value| try std.testing.expectEqual(value, actual.bool),
        .null => {},
        else => return error.UnexpectedCorpusValue,
    }
}
