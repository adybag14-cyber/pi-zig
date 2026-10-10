//! Typed unsolicited native metadata accepted by raw protocol fixtures.
const std = @import("std");
const activation = @import("../extensions/tool_activation.zig");
pub fn consume(gpa: std.mem.Allocator, value: std.json.Value) !bool {
    if (value != .object) return false;
    const object = value.object;
    const kind = object.get("type") orelse return false;
    if (kind != .string or !std.mem.eql(u8, kind.string, "native_metadata")) return false;
    const version = object.get("version") orelse return error.NativeFixtureInvalidMetadata;
    if (version != .integer or version.integer != 1) return error.NativeFixtureInvalidMetadata;
    const generation = try activation.Event.identifier(object.get("ownerGeneration") orelse return error.NativeFixtureInvalidMetadata);
    const revision = try activation.Event.identifier(object.get("revision") orelse return error.NativeFixtureInvalidMetadata);
    if (generation == 0 or revision == 0) return error.NativeFixtureInvalidMetadata;
    const extensions = object.get("extensions") orelse return error.NativeFixtureInvalidMetadata;
    if (extensions != .array or extensions.array.items.len > 4096) return error.NativeFixtureInvalidMetadata;
    for (extensions.array.items) |extension| {
        if (extension != .object) return error.NativeFixtureInvalidMetadata;
        const owner = try activation.Event.identifier(extension.object.get("extensionId") orelse return error.NativeFixtureInvalidMetadata);
        const path = extension.object.get("sourcePath") orelse return error.NativeFixtureInvalidMetadata;
        if (owner == 0 or path != .string) return error.NativeFixtureInvalidMetadata;
        for ([_][]const u8{ "tools", "commands", "hooks", "flags" }) |field| {
            const records = extension.object.get(field) orelse return error.NativeFixtureInvalidMetadata;
            if (records != .array) return error.NativeFixtureInvalidMetadata;
        }
    }
    if (object.get("toolRegistrations")) |records| {
        if (records != .array or records.array.items.len > 4096) return error.NativeFixtureInvalidMetadata;
        var previous: u64 = 0;
        for (records.array.items) |record| {
            var event = try activation.Event.parse(gpa, record);
            defer event.deinit(gpa);
            if (event.owner_generation != generation or event.sequence <= previous) return error.NativeFixtureInvalidMetadata;
            previous = event.sequence;
        }
        const last = try activation.Event.identifier(object.get("registrationSequence") orelse return error.NativeFixtureInvalidMetadata);
        if (previous != 0 and previous != last) return error.NativeFixtureInvalidMetadata;
    }
    return true;
}
