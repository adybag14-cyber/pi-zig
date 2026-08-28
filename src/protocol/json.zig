//! Strict JSON decoding for the Pi client command envelope.
const std = @import("std");
const msg = @import("messages.zig");

pub const ParseError = error{ InvalidMessage, UnsupportedVersion };

fn onlyKeys(o: std.json.ObjectMap, allowed: []const []const u8) bool {
    var it = o.iterator();
    while (it.next()) |entry| {
        var ok = false;
        for (allowed) |key| if (std.mem.eql(u8, entry.key_ptr.*, key)) {
            ok = true;
            break;
        };
        if (!ok) return false;
    }
    return true;
}

fn stringAllowEmpty(gpa: std.mem.Allocator, o: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const v = o.get(key) orelse return ParseError.InvalidMessage;
    if (v != .string) return ParseError.InvalidMessage;
    return try gpa.dupe(u8, v.string);
}

pub fn parseClientMessage(gpa: std.mem.Allocator, input: []const u8) !msg.ClientMessage {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, input, .{}) catch return ParseError.InvalidMessage;
    defer parsed.deinit();
    if (parsed.value != .object) return ParseError.InvalidMessage;
    const obj = parsed.value.object;
    const typv = obj.get("type") orelse return ParseError.InvalidMessage;
    if (typv != .string) return ParseError.InvalidMessage;
    if (std.mem.eql(u8, typv.string, "hello")) {
        if (!onlyKeys(obj, &.{ "type", "version" })) return ParseError.InvalidMessage;
        const vv = obj.get("version") orelse return ParseError.InvalidMessage;
        if (vv != .integer or vv.integer < 0 or vv.integer > std.math.maxInt(u32)) return ParseError.InvalidMessage;
        return .{ .hello = .{ .version = @intCast(vv.integer) } };
    }
    if (!std.mem.eql(u8, typv.string, "request")) return ParseError.InvalidMessage;
    if (!onlyKeys(obj, &.{ "type", "id", "request" })) return ParseError.InvalidMessage;
    const idv = obj.get("id") orelse return ParseError.InvalidMessage;
    const rv = obj.get("request") orelse return ParseError.InvalidMessage;
    if (idv != .string or idv.string.len == 0 or rv != .object) return ParseError.InvalidMessage;
    const cv = rv.object.get("command") orelse return ParseError.InvalidMessage;
    if (cv != .string) return ParseError.InvalidMessage;
    const cn = msg.parseCommandName(cv.string) orelse return ParseError.InvalidMessage;
    const id = try gpa.dupe(u8, idv.string);
    errdefer gpa.free(id);
    const command = try parseCommand(gpa, cn, rv.object);
    return .{ .request = .{ .id = id, .request = command } };
}

fn reqString(gpa: std.mem.Allocator, o: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const v = o.get(key) orelse return ParseError.InvalidMessage;
    if (v != .string or v.string.len == 0) return ParseError.InvalidMessage;
    return try gpa.dupe(u8, v.string);
}

fn optString(gpa: std.mem.Allocator, o: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const v = o.get(key) orelse return null;
    if (v != .string) return ParseError.InvalidMessage;
    return try gpa.dupe(u8, v.string);
}

fn parseModel(gpa: std.mem.Allocator, v: std.json.Value) !msg.ModelRef {
    if (v != .object) return ParseError.InvalidMessage;
    return .{ .provider = try reqString(gpa, v.object, "provider"), .id = try reqString(gpa, v.object, "id") };
}

fn parseCommand(gpa: std.mem.Allocator, name: msg.CommandName, o: std.json.ObjectMap) !msg.Command {
    return switch (name) {
        .list => blk: {
            if (!onlyKeys(o, &.{"command"})) return ParseError.InvalidMessage;
            break :blk .{ .list = {} };
        },
        .create => blk: {
            if (!onlyKeys(o, &.{ "command", "cwd", "name", "model", "thinkingLevel" })) return ParseError.InvalidMessage;
            var model: ?msg.ModelRef = null;
            if (o.get("model")) |m| model = try parseModel(gpa, m);
            var tl: ?msg.ThinkingLevel = null;
            if (o.get("thinkingLevel")) |t| {
                if (t != .string) return ParseError.InvalidMessage;
                tl = msg.parseThinkingLevel(t.string) orelse return ParseError.InvalidMessage;
            }
            const cwd = try optString(gpa, o, "cwd");
            errdefer if (cwd) |v| gpa.free(v);
            if (cwd) |v| if (v.len == 0) return ParseError.InvalidMessage;
            break :blk .{ .create = .{ .cwd = cwd, .name = try optString(gpa, o, "name"), .model = model, .thinking_level = tl } };
        },
        .attach => blk: {
            if (!onlyKeys(o, &.{ "command", "sessionId" })) return ParseError.InvalidMessage;
            break :blk .{ .attach = .{ .session_id = try reqString(gpa, o, "sessionId") } };
        },
        .detach => blk: {
            if (!onlyKeys(o, &.{ "command", "sessionId" })) return ParseError.InvalidMessage;
            break :blk .{ .detach = .{ .session_id = try reqString(gpa, o, "sessionId") } };
        },
        .prompt => blk: {
            if (!onlyKeys(o, &.{ "command", "sessionId", "text" })) return ParseError.InvalidMessage;
            break :blk .{ .prompt = .{ .session_id = try reqString(gpa, o, "sessionId"), .text = try stringAllowEmpty(gpa, o, "text") } };
        },
        .steer => blk: {
            if (!onlyKeys(o, &.{ "command", "sessionId", "text" })) return ParseError.InvalidMessage;
            break :blk .{ .steer = .{ .session_id = try reqString(gpa, o, "sessionId"), .text = try stringAllowEmpty(gpa, o, "text") } };
        },
        .abort => blk: {
            if (!onlyKeys(o, &.{ "command", "sessionId" })) return ParseError.InvalidMessage;
            break :blk .{ .abort = .{ .session_id = try reqString(gpa, o, "sessionId") } };
        },
        .set_model => blk: {
            if (!onlyKeys(o, &.{ "command", "sessionId", "model" })) return ParseError.InvalidMessage;
            const mv = o.get("model") orelse return ParseError.InvalidMessage;
            break :blk .{ .set_model = .{ .session_id = try reqString(gpa, o, "sessionId"), .model = try parseModel(gpa, mv) } };
        },
        .set_thinking => blk: {
            if (!onlyKeys(o, &.{ "command", "sessionId", "thinkingLevel" })) return ParseError.InvalidMessage;
            const tv = o.get("thinkingLevel") orelse return ParseError.InvalidMessage;
            if (tv != .string) return ParseError.InvalidMessage;
            const tl = msg.parseThinkingLevel(tv.string) orelse return ParseError.InvalidMessage;
            break :blk .{ .set_thinking = .{ .session_id = try reqString(gpa, o, "sessionId"), .thinking_level = tl } };
        },
    };
}

pub fn deinitClientMessage(gpa: std.mem.Allocator, m: *msg.ClientMessage) void {
    switch (m.*) {
        .hello => {},
        .request => |*r| {
            gpa.free(r.id);
            deinitCommand(gpa, &r.request);
        },
    }
    m.* = undefined;
}

fn deinitCommand(gpa: std.mem.Allocator, c: *msg.Command) void {
    switch (c.*) {
        .list => {},
        .create => |x| {
            if (x.cwd) |v| gpa.free(v);
            if (x.name) |v| gpa.free(v);
            if (x.model) |m| {
                gpa.free(m.provider);
                gpa.free(m.id);
            }
        },
        .attach => |x| gpa.free(x.session_id),
        .detach => |x| gpa.free(x.session_id),
        .prompt => |x| {
            gpa.free(x.session_id);
            gpa.free(x.text);
        },
        .steer => |x| {
            gpa.free(x.session_id);
            gpa.free(x.text);
        },
        .abort => |x| gpa.free(x.session_id),
        .set_model => |x| {
            gpa.free(x.session_id);
            gpa.free(x.model.provider);
            gpa.free(x.model.id);
        },
        .set_thinking => |x| gpa.free(x.session_id),
    }
}

test "parse upstream hello and prompt envelopes" {
    const gpa = std.testing.allocator;
    var h = try parseClientMessage(gpa, "{\"type\":\"hello\",\"version\":1}");
    defer deinitClientMessage(gpa, &h);
    try std.testing.expect(h == .hello);
    var p = try parseClientMessage(gpa, "{\"type\":\"request\",\"id\":\"r1\",\"request\":{\"command\":\"prompt\",\"sessionId\":\"s1\",\"text\":\"hi\"}}");
    defer deinitClientMessage(gpa, &p);
    try std.testing.expect(p == .request);
    try std.testing.expect(p.request.request == .prompt);
    try std.testing.expectEqualStrings("hi", p.request.request.prompt.text);
}

test "protocol objects are closed and prompt text may be empty" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(ParseError.InvalidMessage, parseClientMessage(gpa, "{\"type\":\"hello\",\"version\":1,\"extra\":true}"));
    try std.testing.expectError(ParseError.InvalidMessage, parseClientMessage(gpa, "{\"type\":\"request\",\"id\":\"1\",\"request\":{\"command\":\"list\",\"extra\":1}}"));
    var p = try parseClientMessage(gpa, "{\"type\":\"request\",\"id\":\"1\",\"request\":{\"command\":\"prompt\",\"sessionId\":\"s\",\"text\":\"\"}}");
    defer deinitClientMessage(gpa, &p);
    try std.testing.expectEqualStrings("", p.request.request.prompt.text);
}
