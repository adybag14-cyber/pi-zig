const std = @import("std");
const builtin = @import("builtin");
const config = @import("config.zig");
const engine_mod = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");

test "agent directory contract matches actual upstream canonical override and home paths" {
    const gpa = std.testing.allocator;
    var source = try json.Owned.parse(gpa, if (builtin.os.tag == .windows) @embedFile("extensions/fixtures/agent-directory-original-win32.json") else @embedFile("extensions/fixtures/agent-directory-original-linux.json"));
    defer source.deinit();
    try std.testing.expectEqualStrings(source.value.object.get("canonical").?.string, config.ENV_AGENT_DIR);
    for (source.value.object.get("rows").?.array.items) |row| {
        var environment = std.process.Environ.Map.init(gpa);
        defer environment.deinit();
        try environment.put(if (builtin.os.tag == .windows) "USERPROFILE" else "HOME", source.value.object.get("home").?.string);
        const value = row.object.get("value").?;
        if (value != .null) try environment.put(config.ENV_AGENT_DIR, value.string);
        const expected = row.object.get("result").?.string;
        const cli = try config.agentDir(gpa, &environment);
        defer gpa.free(cli);
        try std.testing.expectEqualStrings(expected, cli);
        const engine = try engine_mod.Engine.init(gpa, .{});
        defer engine.deinit();
        try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"directory-contract"});
        const vm_path = try sdk.agentDir(engine);
        defer gpa.free(vm_path);
        try std.testing.expectEqualStrings(expected, vm_path);
    }
}

test "agent directory contract retains legacy alias while canonical nonempty value wins" {
    const gpa = std.testing.allocator;
    var environment = std.process.Environ.Map.init(gpa);
    defer environment.deinit();
    try environment.put(if (builtin.os.tag == .windows) "USERPROFILE" else "HOME", if (builtin.os.tag == .windows) "C:\\Users\\fixture" else "/home/fixture");
    try environment.put(config.ENV_AGENT_DIR_LEGACY, "legacy-agent");
    inline for (.{ .{ "", "legacy-agent" }, .{ "canonical-agent", "canonical-agent" } }) |entry| {
        try environment.put(config.ENV_AGENT_DIR, entry[0]);
        const cli = try config.agentDir(gpa, &environment);
        defer gpa.free(cli);
        try std.testing.expectEqualStrings(entry[1], cli);
        const engine = try engine_mod.Engine.init(gpa, .{});
        defer engine.deinit();
        try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"directory-alias"});
        const vm_path = try sdk.agentDir(engine);
        defer gpa.free(vm_path);
        try std.testing.expectEqualStrings(entry[1], vm_path);
    }
}
