//! AgentSession command admission uses ExtensionRunner's ordered collision aliases.
//! Resolve only this session's live owners; registration replacement retains its
//! original insertion position, as Map.set does in the Source loader.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const em = @import("engine.zig");
const c = em.c;

pub fn resolve(owner: *sdk.State) !c.JSValue {
    const engine = owner.engine;
    const group: *@import("native_group.zig").Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.NativeSDKGroupUnavailable));
    const ids = try @import("native_sdk_resource_owners.zig").sessionOwnerIds(engine, owner.data);
    defer engine.freeValue(ids);
    var arena: std.heap.ArenaAllocator = .init(engine.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    var names: std.ArrayList([]const u8) = .empty;
    var counts: std.StringHashMapUnmanaged(usize) = .empty;
    if (c.JS_IsArray(ids)) for (0..try sdk.length(engine, ids)) |extension_index| {
        const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, ids, @intCast(extension_index)));
        defer engine.freeValue(id);
        var number: i64 = 0;
        if (c.JS_ToInt64(engine.context, &number, id) < 0) return error.JavaScriptException;
        const binding = try group.selected(@intCast(number));
        for (binding.command_order.items) |registered_name| {
            if (!binding.commands.contains(registered_name)) continue;
            const name = try allocator.dupe(u8, registered_name);
            try names.append(allocator, name);
            const count = try counts.getOrPut(allocator, name);
            if (!count.found_existing) count.value_ptr.* = 0;
            count.value_ptr.* += 1;
        }
    };
    var seen: std.StringHashMapUnmanaged(usize) = .empty;
    var taken: std.StringHashMapUnmanaged(void) = .empty;
    const commands = try sdk.array(engine);
    errdefer engine.freeValue(commands);
    for (names.items) |name| {
        const occurrence = try seen.getOrPut(allocator, name);
        if (!occurrence.found_existing) occurrence.value_ptr.* = 0;
        occurrence.value_ptr.* += 1;
        var suffix = occurrence.value_ptr.*;
        var invocation = if (counts.get(name).? > 1) try std.fmt.allocPrint(allocator, "{s}:{d}", .{ name, suffix }) else name;
        while (taken.contains(invocation)) {
            suffix += 1;
            invocation = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ name, suffix });
        }
        try taken.put(allocator, invocation, {});
        const row = try sdk.object(engine);
        defer engine.freeValue(row);
        try sdk.put(engine, row, "invocationName", try sdk.text(engine, invocation));
        try sdk.append(engine, commands, c.JS_DupValue(engine.context, row));
    }
    return commands;
}
