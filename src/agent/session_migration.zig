//! Upstream Pi JSONL session migration (v1 -> v2 -> v3).
//!
//! The TypeScript implementation rewrites legacy files when they are opened:
//! v1 entries gain an append-only tree identity, v1 compaction indexes become
//! entry ids, and v2 `hookMessage` roles become v3 `custom` roles.  Keeping the
//! migration separate from the session decoder makes the normal v3 parser
//! strict while allowing old on-disk sessions to become durable v3 files.
const std = @import("std");

pub const CURRENT_VERSION: u32 = 3;

pub const Result = struct {
    jsonl: []u8,
    changed: bool,
    from_version: u32,
    skipped_malformed_lines: usize = 0,

    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        gpa.free(self.jsonl);
        self.* = undefined;
    }
};

pub const Error = error{
    InvalidSession,
    UnsupportedFutureVersion,
};

/// Normalize and migrate a session JSONL document. Blank and malformed lines
/// are skipped, matching upstream `loadEntriesFromFile()`. A parsed non-session
/// first entry is still rejected so an unrelated JSONL file is never rewritten.
pub fn migrateJsonl(gpa: std.mem.Allocator, raw: []const u8) !Result {
    var arena_impl: std.heap.ArenaAllocator = .init(gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var values: std.ArrayList(std.json.Value) = .empty;
    defer values.deinit(arena);
    var source_lines: std.ArrayList([]const u8) = .empty;
    defer source_lines.deinit(arena);
    var skipped: usize = 0;

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;
        const parsed = std.json.parseFromSlice(std.json.Value, arena, line, .{}) catch {
            skipped += 1;
            continue;
        };
        // Retain parsed values until the arena is destroyed. Calling
        // Parsed.deinit() here invalidates object maps that are serialized later.
        if (parsed.value != .object) {
            skipped += 1;
            continue;
        }
        try values.append(arena, parsed.value);
        try source_lines.append(arena, line);
    }

    if (values.items.len == 0) return Error.InvalidSession;
    const header = &values.items[0];
    const header_type = header.object.get("type") orelse return Error.InvalidSession;
    if (header_type != .string or !std.mem.eql(u8, header_type.string, "session")) return Error.InvalidSession;
    const header_id = header.object.get("id") orelse return Error.InvalidSession;
    if (header_id != .string or header_id.string.len == 0) return Error.InvalidSession;

    const from_version: u32 = blk: {
        const value = header.object.get("version") orelse break :blk 1;
        if (value != .integer or value.integer < 1 or value.integer > std.math.maxInt(u32)) break :blk 1;
        break :blk @intCast(value.integer);
    };
    if (from_version > CURRENT_VERSION) return Error.UnsupportedFutureVersion;

    var changed = skipped != 0;
    if (from_version < 2) {
        try migrateV1ToV2(arena, values.items, source_lines.items, header_id.string);
        changed = true;
    }
    if (from_version < 3) {
        migrateV2ToV3(values.items);
        changed = true;
    }

    if (!changed) {
        return .{
            .jsonl = try gpa.dupe(u8, raw),
            .changed = false,
            .from_version = from_version,
            .skipped_malformed_lines = 0,
        };
    }

    try header.object.put(arena, "version", .{ .integer = CURRENT_VERSION });
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    for (values.items) |value| {
        try std.json.Stringify.value(value, .{}, &out.writer);
        try out.writer.writeByte('\n');
    }
    return .{
        .jsonl = try out.toOwnedSlice(),
        .changed = true,
        .from_version = from_version,
        .skipped_malformed_lines = skipped,
    };
}

fn migrateV1ToV2(
    arena: std.mem.Allocator,
    values: []std.json.Value,
    source_lines: []const []const u8,
    session_id: []const u8,
) !void {
    var used: std.StringHashMapUnmanaged(void) = .empty;
    defer used.deinit(arena);

    // Respect any partially migrated identities rather than replacing them.
    for (values[1..]) |value| {
        if (value.object.get("id")) |id| {
            if (id == .string and id.string.len > 0) try used.put(arena, id.string, {});
        }
    }

    var previous_id: ?[]const u8 = null;
    for (values[1..], 1..) |*value, index| {
        var id: []const u8 = undefined;
        if (value.object.get("id")) |existing| {
            if (existing == .string and existing.string.len > 0) {
                id = existing.string;
            } else {
                id = try generateLegacyId(arena, &used, session_id, source_lines[index], index);
                try value.object.put(arena, "id", .{ .string = id });
            }
        } else {
            id = try generateLegacyId(arena, &used, session_id, source_lines[index], index);
            try value.object.put(arena, "id", .{ .string = id });
        }

        if (previous_id) |parent| {
            try value.object.put(arena, "parentId", .{ .string = parent });
        } else {
            try value.object.put(arena, "parentId", .null);
        }
        previous_id = id;
    }

    // Upstream v1 indexes the complete file-entry array, including the header.
    for (values[1..]) |*value| {
        const typ = value.object.get("type") orelse continue;
        if (typ != .string or !std.mem.eql(u8, typ.string, "compaction")) continue;
        const old_index = value.object.get("firstKeptEntryIndex") orelse continue;
        if (old_index != .integer or old_index.integer < 0) continue;
        const target_index: usize = @intCast(old_index.integer);
        if (target_index < values.len) {
            const target_id = values[target_index].object.get("id");
            if (target_id) |resolved| {
                if (resolved == .string) {
                    try value.object.put(arena, "firstKeptEntryId", .{ .string = resolved.string });
                }
            }
        }
        _ = value.object.orderedRemove("firstKeptEntryIndex");
    }

    try values[0].object.put(arena, "version", .{ .integer = 2 });
}

fn migrateV2ToV3(values: []std.json.Value) void {
    for (values[1..]) |*value| {
        const typ = value.object.get("type") orelse continue;
        if (typ != .string or !std.mem.eql(u8, typ.string, "message")) continue;
        const message = value.object.getPtr("message") orelse continue;
        if (message.* != .object) continue;
        const role = message.object.getPtr("role") orelse continue;
        if (role.* == .string and std.mem.eql(u8, role.string, "hookMessage")) role.* = .{ .string = "custom" };
    }
}

fn generateLegacyId(
    arena: std.mem.Allocator,
    used: *std.StringHashMapUnmanaged(void),
    session_id: []const u8,
    source_line: []const u8,
    index: usize,
) ![]const u8 {
    var salt: u64 = @intCast(index);
    while (true) : (salt +%= 1) {
        var hasher = std.hash.Wyhash.init(salt);
        hasher.update(session_id);
        hasher.update(source_line);
        const hash = hasher.final();
        const candidate = try std.fmt.allocPrint(arena, "{x:0>8}", .{@as(u32, @truncate(hash))});
        if (!used.contains(candidate)) {
            try used.put(arena, candidate, {});
            return candidate;
        }
    }
}

test "migrate v1 adds tree ids and converts compaction index" {
    const raw =
        \\{"type":"session","id":"legacy","timestamp":"2025-01-01T00:00:00.000Z","cwd":"/tmp"}
        \\{"type":"message","timestamp":"2025-01-01T00:00:01.000Z","message":{"role":"user","content":"hello"}}
        \\not-json
        \\{"type":"compaction","timestamp":"2025-01-01T00:00:02.000Z","summary":"summary","firstKeptEntryIndex":1,"tokensBefore":20}
    ;
    var migrated = try migrateJsonl(std.testing.allocator, raw);
    defer migrated.deinit(std.testing.allocator);
    try std.testing.expect(migrated.changed);
    try std.testing.expectEqual(@as(u32, 1), migrated.from_version);
    try std.testing.expectEqual(@as(usize, 1), migrated.skipped_malformed_lines);

    var lines = std.mem.splitScalar(u8, migrated.jsonl, '\n');
    const header_line = lines.next().?;
    const message_line = lines.next().?;
    const compaction_line = lines.next().?;
    var header = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, header_line, .{});
    defer header.deinit();
    var message = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, message_line, .{});
    defer message.deinit();
    var compaction = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, compaction_line, .{});
    defer compaction.deinit();
    try std.testing.expectEqual(@as(i64, 3), header.value.object.get("version").?.integer);
    const message_id = message.value.object.get("id").?.string;
    try std.testing.expect(message_id.len == 8);
    try std.testing.expect(compaction.value.object.get("parentId") != null);
    try std.testing.expectEqualStrings(message_id, compaction.value.object.get("firstKeptEntryId").?.string);
    try std.testing.expect(compaction.value.object.get("firstKeptEntryIndex") == null);
}

test "migrate v2 renames hookMessage role and current v3 is unchanged" {
    const v2 =
        \\{"type":"session","version":2,"id":"v2","timestamp":"2025-01-01T00:00:00.000Z","cwd":"/tmp"}
        \\{"type":"message","id":"m1","parentId":null,"timestamp":"2025-01-01T00:00:01.000Z","message":{"role":"hookMessage","content":"x"}}
    ;
    var migrated = try migrateJsonl(std.testing.allocator, v2);
    defer migrated.deinit(std.testing.allocator);
    try std.testing.expect(migrated.changed);
    try std.testing.expect(std.mem.indexOf(u8, migrated.jsonl, "\"role\":\"custom\"") != null);

    var current = try migrateJsonl(std.testing.allocator, migrated.jsonl);
    defer current.deinit(std.testing.allocator);
    try std.testing.expect(!current.changed);
    try std.testing.expectEqualStrings(migrated.jsonl, current.jsonl);
}

test "future versions and unrelated JSONL are rejected" {
    try std.testing.expectError(Error.UnsupportedFutureVersion, migrateJsonl(std.testing.allocator, "{\"type\":\"session\",\"version\":99,\"id\":\"x\",\"cwd\":\"/\"}\n"));
    try std.testing.expectError(Error.InvalidSession, migrateJsonl(std.testing.allocator, "{\"type\":\"event\",\"id\":\"x\"}\n"));
}
