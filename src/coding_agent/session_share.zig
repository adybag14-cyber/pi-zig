//! Active-branch session sharing through Radius artifacts with the upstream
//! private-GitHub-gist fallback.
const std = @import("std");
const Io = std.Io;
const session_mod = @import("../agent/session.zig");
const agent_tools = @import("../agent/tools.zig");
const bootstrap_http = @import("../ai/bootstrap_http.zig");
const radius_config = @import("../ai/radius_config.zig");

pub const DEFAULT_SHARE_VIEWER_URL = "https://pi.dev/session/";

fn toolFunction(value: std.json.Value) ?std.json.ObjectMap {
    if (value != .object) return null;
    const function = value.object.get("function") orelse return null;
    return if (function == .object) function.object else null;
}

fn toolName(value: std.json.Value) ?[]const u8 {
    const function = toolFunction(value) orelse return null;
    const name = function.get("name") orelse return null;
    return if (name == .string and name.string.len > 0) name.string else null;
}

fn appendShareTool(writer: *std.Io.Writer, tool: std.json.Value) !void {
    const function = toolFunction(tool) orelse return error.InvalidToolSchemaJson;
    const name = function.get("name") orelse return error.InvalidToolSchemaJson;
    if (name != .string or name.string.len == 0) return error.InvalidToolSchemaJson;
    const description = function.get("description") orelse std.json.Value{ .string = "" };
    if (description != .string) return error.InvalidToolSchemaJson;
    const parameters = function.get("parameters") orelse std.json.Value{ .object = .empty };
    if (parameters != .object) return error.InvalidToolSchemaJson;
    try writer.writeAll("{\"name\":");
    try std.json.Stringify.value(name.string, .{}, writer);
    try writer.writeAll(",\"description\":");
    try std.json.Stringify.value(description.string, .{}, writer);
    try writer.writeAll(",\"parameters\":");
    try std.json.Stringify.value(parameters, .{}, writer);
    try writer.writeByte('}');
}

fn appendShareTools(writer: *std.Io.Writer, gpa: std.mem.Allocator, builtins_json: []const u8, extras_json: []const u8) !void {
    var builtins = try std.json.parseFromSlice(std.json.Value, gpa, builtins_json, .{});
    defer builtins.deinit();
    var extras = try std.json.parseFromSlice(std.json.Value, gpa, extras_json, .{});
    defer extras.deinit();
    if (builtins.value != .array or extras.value != .array) return error.InvalidToolSchemaJson;

    var extra_names = std.StringHashMap(void).init(gpa);
    defer extra_names.deinit();
    for (extras.value.array.items) |tool| try extra_names.put(toolName(tool) orelse return error.InvalidToolSchemaJson, {});

    try writer.writeByte('[');
    var first = true;
    for (builtins.value.array.items) |tool| {
        const name = toolName(tool) orelse return error.InvalidToolSchemaJson;
        if (extra_names.contains(name)) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try appendShareTool(writer, tool);
    }
    for (extras.value.array.items) |tool| {
        if (!first) try writer.writeByte(',');
        first = false;
        try appendShareTool(writer, tool);
    }
    try writer.writeByte(']');
}

/// Export only the active root-to-tip branch and append the presentation-only
/// `pi.share` metadata entry used by the Radius viewer. The live Session is not
/// mutated, and abandoned branches remain private to the local JSONL file.
pub fn exportForShare(
    gpa: std.mem.Allocator,
    io: Io,
    sess: *const session_mod.Session,
    system_prompt: []const u8,
    tool_filter: agent_tools.ToolFilter,
    extra_tools_json: []const u8,
) ![]u8 {
    const full = try sess.toJsonl(gpa);
    defer gpa.free(full);
    const branch = try sess.branchEntries(gpa);
    defer gpa.free(branch);
    var branch_ids = std.StringHashMap(void).init(gpa);
    defer branch_ids.deinit();
    for (branch) |entry| try branch_ids.put(entry.id, {});

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var lines = std.mem.splitScalar(u8, full, '\n');
    const header = lines.next() orelse return error.InvalidSessionExport;
    if (header.len == 0) return error.InvalidSessionExport;
    try out.writer.writeAll(header);
    try out.writer.writeByte('\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = std.json.parseFromSlice(std.json.Value, gpa, line, .{}) catch continue;
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const id = parsed.value.object.get("id") orelse continue;
        if (id != .string or !branch_ids.contains(id.string)) continue;
        try out.writer.writeAll(line);
        try out.writer.writeByte('\n');
    }

    var random: [4]u8 = undefined;
    try io.randomSecure(&random);
    const id_hex = std.fmt.bytesToHex(random, .lower);
    const parent_id = if (branch.len > 0) branch[branch.len - 1].id else null;
    const timestamp = if (branch.len > 0 and branch[branch.len - 1].timestamp.len > 0) branch[branch.len - 1].timestamp else sess.created_at;
    const builtins = try agent_tools.toolSchemasJson(gpa, tool_filter);
    defer gpa.free(builtins);

    try out.writer.writeAll("{\"type\":\"custom\",\"customType\":\"pi.share\",\"id\":");
    try std.json.Stringify.value(id_hex[0..], .{}, &out.writer);
    try out.writer.writeAll(",\"parentId\":");
    if (parent_id) |parent| try std.json.Stringify.value(parent, .{}, &out.writer) else try out.writer.writeAll("null");
    try out.writer.writeAll(",\"timestamp\":");
    try std.json.Stringify.value(timestamp, .{}, &out.writer);
    try out.writer.writeAll(",\"data\":{\"systemPrompt\":");
    try std.json.Stringify.value(system_prompt, .{}, &out.writer);
    try out.writer.writeAll(",\"tools\":");
    try appendShareTools(&out.writer, gpa, builtins, extra_tools_json);
    try out.writer.writeAll("}}\n");
    return out.toOwnedSlice();
}

fn validateShareUrl(value: []const u8) !void {
    const uri = std.Uri.parse(value) catch return error.InvalidShareUrl;
    if (!(std.ascii.eqlIgnoreCase(uri.scheme, "https") or std.ascii.eqlIgnoreCase(uri.scheme, "http")) or uri.host == null) return error.InvalidShareUrl;
}

/// Upload a native JSONL branch to Radius. Credential discovery/refresh remains
/// with the caller so this function never reads or logs secret storage.
pub fn uploadRadius(
    gpa: std.mem.Allocator,
    io: Io,
    token: []const u8,
    gateway: []const u8,
    jsonl: []const u8,
    options: bootstrap_http.Options,
) ![]u8 {
    if (token.len == 0) return error.MissingRadiusCredential;
    const base = std.mem.trimEnd(u8, if (gateway.len > 0) gateway else radius_config.DEFAULT_GATEWAY, "/");
    const url = try std.fmt.allocPrint(gpa, "{s}/v1/artifacts?visibility=organization&title=Pi%20session", .{base});
    defer gpa.free(url);
    const authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
    defer gpa.free(authorization);
    const content_length = try std.fmt.allocPrint(gpa, "{d}", .{jsonl.len});
    defer gpa.free(content_length);
    var response = try bootstrap_http.request(gpa, io, .{
        .url = url,
        .method = .POST,
        .payload = jsonl,
        .headers = &.{
            .{ .name = "authorization", .value = authorization },
            .{ .name = "content-type", .value = "application/x-ndjson" },
            .{ .name = "content-length", .value = content_length },
            .{ .name = "accept", .value = "application/json" },
        },
        .options = options,
    });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return error.RadiusArtifactUploadFailed;
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, response.body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidRadiusArtifactResponse;
    const artifact = parsed.value.object.get("artifact") orelse return error.InvalidRadiusArtifactResponse;
    if (artifact != .object) return error.InvalidRadiusArtifactResponse;
    const canonical = artifact.object.get("canonical_url") orelse return error.InvalidRadiusArtifactResponse;
    if (canonical != .string or canonical.string.len == 0) return error.InvalidRadiusArtifactResponse;
    try validateShareUrl(canonical.string);
    return try gpa.dupe(u8, canonical.string);
}

fn runGh(gpa: std.mem.Allocator, io: Io, argv: []const []const u8, cwd: []const u8) ![]u8 {
    const result = std.process.run(gpa, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(60), .clock = .real } },
    }) catch |err| switch (err) {
        error.FileNotFound => return error.GitHubCliNotInstalled,
        error.Timeout => return error.GitHubCliTimedOut,
        else => return error.GitHubCliFailed,
    };
    defer gpa.free(result.stderr);
    const success = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!success) {
        gpa.free(result.stdout);
        return error.GitHubCliFailed;
    }
    return result.stdout;
}

pub fn createPrivateGist(gpa: std.mem.Allocator, io: Io, cwd: []const u8, html_path: []const u8) ![]u8 {
    const status = try runGh(gpa, io, &.{ "gh", "auth", "status" }, cwd);
    gpa.free(status);
    const output = try runGh(gpa, io, &.{ "gh", "gist", "create", "--public=false", html_path }, cwd);
    defer gpa.free(output);
    const gist_url = std.mem.trim(u8, output, " \t\r\n");
    if (gist_url.len == 0 or std.mem.indexOfAny(u8, gist_url, "\r\n") != null) return error.InvalidGistUrl;
    try validateShareUrl(gist_url);
    return try gpa.dupe(u8, gist_url);
}

pub fn viewerUrl(gpa: std.mem.Allocator, environ: *const std.process.Environ.Map, gist_url: []const u8) ![]u8 {
    const trimmed = std.mem.trimEnd(u8, gist_url, "/");
    const slash = std.mem.lastIndexOfScalar(u8, trimmed, '/') orelse return error.InvalidGistUrl;
    const gist_id = trimmed[slash + 1 ..];
    if (gist_id.len == 0 or std.mem.indexOfAny(u8, gist_id, "?#") != null) return error.InvalidGistUrl;
    const base = environ.get("PI_SHARE_VIEWER_URL") orelse DEFAULT_SHARE_VIEWER_URL;
    return std.fmt.allocPrint(gpa, "{s}#{s}", .{ base, gist_id });
}

test "share export keeps only active branch and appends prompt tool metadata" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "share-session", "/work");
    defer sess.deinit();
    const root = try sess.appendMessage(null, "user", "root", null, null);
    const active = try sess.appendMessage(root, "assistant", "active", null, null);
    try sess.setTip(root);
    _ = try sess.appendMessage(root, "assistant", "abandoned-secret", null, null);
    try sess.setTip(active);
    const jsonl = try exportForShare(gpa, std.testing.io, &sess, "SYSTEM", .{ .allow = &.{"read"} },
        \\[{"type":"function","function":{"name":"custom","description":"Custom","parameters":{"type":"object"}}}]
    );
    defer gpa.free(jsonl);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "abandoned-secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"customType\":\"pi.share\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"systemPrompt\":\"SYSTEM\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"name\":\"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"name\":\"custom\"") != null);
}

test "gist viewer URL uses hash fragment and custom base" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("PI_SHARE_VIEWER_URL", "https://viewer.example/session/");
    const url = try viewerUrl(gpa, &env, "https://gist.github.com/user/abc123");
    defer gpa.free(url);
    try std.testing.expectEqualStrings("https://viewer.example/session/#abc123", url);
}
