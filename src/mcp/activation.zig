//! Session activation is decided from enabled configuration before connections.
const std = @import("std");
const json = @import("protocol.zig").json;
pub const Needs = struct { codemode: bool = false, search: bool = false };
pub fn configuredNeeds(loaded: json.Value) Needs {
    var needs: Needs = .{};
    const servers = json.get(loaded, "servers") orelse return needs;
    if (servers != .array) return needs;
    for (servers.array.items) |entry| {
        const config = json.get(entry, "config") orelse continue;
        if (json.get(config, "enabled")) |enabled| if (enabled == .bool and !enabled.bool) continue;
        const base = json.get(config, "exposure") orelse json.Value{ .string = "codemode" };
        include(&needs, base);
        if (json.get(config, "toolExposure")) |overrides| if (overrides == .object) for (overrides.object.values()) |value| include(&needs, value);
    }
    return needs;
}
fn include(needs: *Needs, value: json.Value) void {
    if (value != .string) return;
    if (std.mem.eql(u8, value.string, "codemode") or std.mem.eql(u8, value.string, "codemode-deferred")) needs.codemode = true;
    if (std.mem.eql(u8, value.string, "deferred")) needs.search = true;
}
pub const Options = struct { has_codemode: bool, has_search: bool, active_codemode: bool = false, active_search: bool = false, auto_enable_codemode: bool = true };
pub const Decision = struct { activate_codemode: bool = false, activate_search: bool = false, warning: ?[]const u8 = null };
pub fn decide(needs: Needs, options: Options) Decision {
    if (!needs.codemode and !needs.search) return .{};
    var result: Decision = .{ .activate_codemode = needs.codemode and options.has_codemode and options.auto_enable_codemode and !options.active_codemode, .activate_search = needs.search and options.has_search and !options.active_search };
    if ((options.has_codemode and (options.active_codemode or result.activate_codemode)) or (options.has_search and (options.active_search or result.activate_search))) return result;
    result.warning = if (needs.codemode and options.has_codemode and !options.auto_enable_codemode) "MCP tools are only reachable from the codemode or tool_search tool, but neither is active (autoEnableCodemode is false); they cannot be called." else "MCP tools are only reachable from the codemode or tool_search tool, but neither is active; they cannot be called.";
    return result;
}
test "MCP activation replays actual upstream extension before transport startup" {
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("fixtures/mcp-autoactivation-original-6fb.json"));
    defer fixture.deinit();
    for (fixture.value.object.get("rows").?.array.items) |row| {
        const builtins = row.object.get("builtins").?.string;
        const initial = row.object.get("initial").?.array.items;
        var active_codemode = false;
        var active_search = false;
        for (initial) |name| {
            active_codemode = active_codemode or std.mem.eql(u8, name.string, "codemode");
            active_search = active_search or std.mem.eql(u8, name.string, "tool_search");
        }
        var loaded = try json.Owned.empty(std.testing.allocator);
        defer loaded.deinit();
        const a = loaded.arena.allocator();
        var entry: json.Value = .{ .object = .empty };
        try entry.object.put(a, "config", row.object.get("configuration").?);
        var servers: json.Value = .{ .array = .init(a) };
        try servers.array.append(entry);
        loaded.value = .{ .object = .empty };
        try loaded.value.object.put(a, "servers", servers);
        const result = decide(configuredNeeds(loaded.value), .{ .has_codemode = std.mem.eql(u8, builtins, "both") or std.mem.eql(u8, builtins, "codemode"), .has_search = std.mem.eql(u8, builtins, "both") or std.mem.eql(u8, builtins, "search"), .active_codemode = active_codemode, .active_search = active_search, .auto_enable_codemode = row.object.get("autoEnableCodemode").?.bool });
        const active = row.object.get("active").?.array.items;
        try std.testing.expectEqual(initial.len + @as(usize, @intFromBool(result.activate_codemode)) + @as(usize, @intFromBool(result.activate_search)), active.len);
        for (initial, active[0..initial.len]) |before, after| try std.testing.expectEqualStrings(before.string, after.string);
        var next = initial.len;
        if (result.activate_codemode) {
            try std.testing.expectEqualStrings("codemode", active[next].string);
            next += 1;
        }
        if (result.activate_search) try std.testing.expectEqualStrings("tool_search", active[next].string);
        const warnings = row.object.get("warnings").?.array.items;
        try std.testing.expectEqual(@as(usize, if (result.warning != null) 1 else 0), warnings.len);
        if (result.warning) |warning| try std.testing.expectEqualStrings(warnings[0].object.get("text").?.string, warning);
    }
}
