//! Native, lifetime-stable names from the upstream MCP extension's owner map.
const std = @import("std");
const json = @import("protocol.zig").json;
const projection = @import("agent_tools.zig");

pub const Registry = struct {
    gpa: std.mem.Allocator,
    owners: json.Owned,

    pub fn init(gpa: std.mem.Allocator) !Registry {
        var owners = try json.Owned.empty(gpa);
        owners.value = .{ .object = .empty };
        return .{ .gpa = gpa, .owners = owners };
    }
    pub fn deinit(self: *Registry) void {
        self.owners.deinit();
        self.* = undefined;
    }
    /// Names own their storage. Failed allocation leaves all prior reservations intact.
    pub fn assign(self: *Registry, server: []const u8, raw_names: []const []const u8) !json.Owned {
        var candidate = try json.Owned.empty(self.gpa);
        errdefer candidate.deinit();
        const a = candidate.arena.allocator();
        candidate.value = try json.clone(a, self.owners.value);
        var result = try json.Owned.empty(self.gpa);
        errdefer result.deinit();
        const r = result.arena.allocator();
        result.value = .{ .array = .init(r) };
        var unique: std.StringHashMapUnmanaged(void) = .empty;
        var bases: std.StringHashMapUnmanaged(usize) = .empty;
        var current: std.StringHashMapUnmanaged(void) = .empty;
        for (raw_names) |raw| {
            const added = try unique.getOrPut(r, raw);
            if (added.found_existing) continue;
            const base = try projection.toolName(r, server, raw, false);
            const count = try bases.getOrPut(r, base);
            if (!count.found_existing) count.value_ptr.* = 0;
            count.value_ptr.* += 1;
        }
        for (raw_names) |raw| {
            const base = try projection.toolName(r, server, raw, false);
            const existing = candidate.value.object.get(base);
            const another_owner = if (existing) |owner| !std.mem.eql(u8, owner.object.get("server").?.string, server) or !std.mem.eql(u8, owner.object.get("tool").?.string, raw) else false;
            const name = try projection.toolName(r, server, raw, another_owner or current.contains(base) or bases.get(base).? > 1);
            try current.put(r, name, {});
            var owner: json.Value = .{ .object = .empty };
            try owner.object.put(a, "server", .{ .string = try a.dupe(u8, server) });
            try owner.object.put(a, "tool", .{ .string = try a.dupe(u8, raw) });
            try candidate.value.object.put(a, try a.dupe(u8, name), owner);
            try result.value.array.append(.{ .string = name });
        }
        self.owners.deinit();
        self.owners = candidate;
        return result;
    }
};

test "MCP name reservations replay original colliding batches duplicates withdrawal and later refresh" {
    const gpa = std.testing.allocator;
    var corpus = try json.Owned.parse(gpa, @embedFile("fixtures/mcp-tools-refresh-original-6fb.json"));
    defer corpus.deinit();
    for (corpus.value.object.get("rows").?.array.items) |row| {
        var registry = try Registry.init(gpa);
        defer registry.deinit();
        var registration_index: usize = 0;
        for (row.object.get("phases").?.array.items, 0..) |phase, phase_index| {
            const names = try gpa.alloc([]const u8, phase.array.items.len);
            defer gpa.free(names);
            for (names, phase.array.items) |*name, value| name.* = value.string;
            var assigned = try registry.assign("native", names);
            defer assigned.deinit();
            const registrations = row.object.get("registrations").?.array.items;
            for (assigned.value.array.items, 0..) |name, index| try std.testing.expectEqualStrings(registrations[registration_index + index].object.get("name").?.string, name.string);
            registration_index += phase.array.items.len;
            if (phase_index != 0) break;
        }
    }
}

test "MCP name reservations retain returned strings and release failed transaction ownership" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var registry = try Registry.init(gpa);
            defer registry.deinit();
            var original = try registry.assign("native", &.{ "a-b", "plain" });
            defer original.deinit();
            var next = try registry.assign("native", &.{ "a_b", "plain" });
            defer next.deinit();
            try std.testing.expectEqualStrings("mcp__native__a_b", original.value.array.items[0].string);
            try std.testing.expectEqualStrings("mcp__native__plain", next.value.array.items[1].string);
            try std.testing.expect(!std.mem.eql(u8, original.value.array.items[0].string, next.value.array.items[0].string));
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}
