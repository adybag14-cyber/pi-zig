//! File settings exposed to extensions preserve unknown keys and original migrations.
const std = @import("std");
const json = @import("../durable/backend/json.zig");
const Value = std.json.Value;
fn object(value: Value) bool {
    return value == .object;
}
fn spread(a: std.mem.Allocator, value: Value) !Value {
    if (value == .object) return json.clone(a, value);
    var result: Value = .{ .object = .empty };
    if (value == .array) for (value.array.items, 0..) |entry, index| try result.object.put(a, try std.fmt.allocPrint(a, "{d}", .{index}), try json.clone(a, entry));
    return result;
}
fn migrate(a: std.mem.Allocator, value: *Value) !void {
    if (!object(value.*)) value.* = try spread(a, value.*);
    const fields = &value.object;
    if (fields.get("queueMode")) |old| if (!fields.contains("steeringMode")) {
        try fields.put(a, "steeringMode", old);
        _ = fields.orderedRemove("queueMode");
    };
    if (!fields.contains("transport")) if (fields.get("websockets")) |old| if (old == .bool) {
        try fields.put(a, "transport", .{ .string = if (old.bool) "websocket" else "sse" });
        _ = fields.orderedRemove("websockets");
    };
    if (fields.get("skills")) |skills| if (object(skills)) {
        if (skills.object.get("enableSkillCommands")) |enabled| if (!fields.contains("enableSkillCommands")) try fields.put(a, "enableSkillCommands", enabled);
        if (skills.object.get("customDirectories")) |directories| {
            if (directories == .array and directories.array.items.len > 0) {
                try fields.put(a, "skills", directories);
            } else _ = fields.orderedRemove("skills");
        } else _ = fields.orderedRemove("skills");
    };
    if (fields.getPtr("retry")) |retry| if (object(retry.*)) {
        if (retry.object.get("maxDelayMs")) |delay| {
            if (delay == .integer or delay == .float or delay == .number_string) {
                var provider = retry.object.get("provider") orelse Value{ .object = .empty };
                if (!object(provider)) provider = try spread(a, provider);
                const current = provider.object.get("maxRetryDelayMs");
                if (current == null or current.? == .null) {
                    try provider.object.put(a, "maxRetryDelayMs", delay);
                    try retry.object.put(a, "provider", provider);
                }
            }
        }
        _ = retry.object.orderedRemove("maxDelayMs");
    };
}
fn merge(a: std.mem.Allocator, base: Value, overrides: Value, root: bool) !Value {
    if (!object(base) or !object(overrides)) return json.clone(a, overrides);
    var result = try json.clone(a, base);
    var iterator = overrides.object.iterator();
    while (iterator.next()) |field| {
        if (std.mem.eql(u8, field.key_ptr.*, "__proto__") and !result.object.contains("__proto__")) continue;
        const old = result.object.get(field.key_ptr.*);
        const value = if (old != null and object(old.?) and object(field.value_ptr.*)) try merge(a, old.?, field.value_ptr.*, false) else try json.clone(a, field.value_ptr.*);
        try result.object.put(a, try a.dupe(u8, field.key_ptr.*), value);
    }
    const first = base.object.get("defaultTools");
    const second = overrides.object.get("defaultTools");
    if (root and first != null and first.? == .array and second != null and second.? == .array) {
        var modifiers = true;
        for (second.?.array.items) |entry| if (entry != .string or entry.string.len == 0 or (entry.string[0] != '+' and entry.string[0] != '-')) {
            modifiers = false;
            break;
        };
        if (modifiers) {
            var tools: Value = .{ .array = .init(a) };
            for (first.?.array.items) |entry| try tools.array.append(try json.clone(a, entry));
            for (second.?.array.items) |entry| try tools.array.append(try json.clone(a, entry));
            try result.object.put(a, "defaultTools", tools);
        }
    }
    return result;
}
pub fn fromValues(gpa: std.mem.Allocator, global: Value, project: Value, trusted: bool) !json.Owned {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const a = result.arena.allocator();
    var base = try json.clone(a, global);
    var overrides = if (trusted) try json.clone(a, project) else Value{ .object = .empty };
    try migrate(a, &base);
    try migrate(a, &overrides);
    result.value = try merge(a, base, overrides, true);
    return result;
}
fn file(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !json.Owned {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch |cause| switch (cause) {
        error.OutOfMemory => return cause,
        else => return json.Owned.parse(gpa, "{}"),
    };
    defer gpa.free(bytes);
    const text = if (std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) bytes[3..] else bytes;
    return json.Owned.parse(gpa, text) catch |cause| switch (cause) {
        error.OutOfMemory => return cause,
        else => return json.Owned.parse(gpa, "{}"),
    };
}
pub fn loadJson(gpa: std.mem.Allocator, io: std.Io, cwd: []const u8, agent_dir: ?[]const u8, trusted: bool) ![]u8 {
    var global = if (agent_dir) |directory| blk: {
        const path = try std.fs.path.join(gpa, &.{ directory, "settings.json" });
        defer gpa.free(path);
        break :blk try file(gpa, io, path);
    } else try json.Owned.parse(gpa, "{}");
    defer global.deinit();
    var project = if (trusted) blk: {
        const path = try std.fs.path.join(gpa, &.{ cwd, ".pi", "settings.json" });
        defer gpa.free(path);
        break :blk try file(gpa, io, path);
    } else try json.Owned.parse(gpa, "{}");
    defer project.deinit();
    var result = try fromValues(gpa, global.value, project.value, trusted);
    defer result.deinit();
    return json.stringify(gpa, result.value);
}

test "extension settings preserve original migrations unknown data scoped merge and malformed tool lists" {
    const gpa = std.testing.allocator;
    var original = try json.Owned.parse(gpa, @embedFile("fixtures/extension-settings-original-6fb.json"));
    defer original.deinit();
    for (original.value.object.get("rows").?.array.items, 0..) |row, index| {
        var result = try fromValues(gpa, row.object.get("global").?, row.object.get("project").?, row.object.get("trusted").?.bool);
        defer result.deinit();
        if (!json.equal(row.object.get("result").?, result.value)) {
            const expected = try json.stringify(gpa, row.object.get("result").?);
            defer gpa.free(expected);
            const actual = try json.stringify(gpa, result.value);
            defer gpa.free(actual);
            std.debug.print("Settings original case{} expected{s} actual{s}\n", .{ index, expected, actual });
            return error.OriginalExtensionSettingsMismatch;
        }
    }
}
