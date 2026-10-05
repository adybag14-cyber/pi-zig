//! MCP result projection. Full content remains available to native script/tool callers.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = protocol.Value;
fn append(a: std.mem.Allocator, items: *Value, kind: []const u8, text: []const u8) !void {
    var block: Value = .{ .object = .empty };
    try block.object.put(a, "type", .{ .string = kind });
    try block.object.put(a, "text", .{ .string = try a.dupe(u8, text) });
    try items.array.append(block);
}
fn image(a: std.mem.Allocator, items: *Value, data: Value, mime: Value) !void {
    if (data != .string or mime != .string) return error.InvalidMcpImage;
    var block: Value = .{ .object = .empty };
    try block.object.put(a, "type", .{ .string = "image" });
    try block.object.put(a, "data", try json.clone(a, data));
    try block.object.put(a, "mimeType", try json.clone(a, mime));
    try items.array.append(block);
}
pub fn toLlmContent(gpa: std.mem.Allocator, result: Value) !json.Owned {
    var owned = try json.Owned.empty(gpa);
    errdefer owned.deinit();
    const a = owned.arena.allocator();
    var items: Value = .{ .array = .init(a) };
    if (json.get(result, "content")) |content| {
        if (content != .array) return error.InvalidMcpContent;
        for (content.array.items) |value| {
            const kind = try protocol.text(value, "type");
            if (std.mem.eql(u8, kind, "text")) try append(a, &items, "text", try protocol.text(value, "text")) else if (std.mem.eql(u8, kind, "image")) try image(a, &items, try protocol.field(value, "data"), try protocol.field(value, "mimeType")) else if (std.mem.eql(u8, kind, "audio")) try append(a, &items, "text", try std.fmt.allocPrint(a, "[audio {s} omitted]", .{try protocol.text(value, "mimeType")})) else if (std.mem.eql(u8, kind, "resource_link")) try append(a, &items, "text", try std.fmt.allocPrint(a, "{s}: {s}", .{ try protocol.text(value, "name"), try protocol.text(value, "uri") })) else if (std.mem.eql(u8, kind, "resource")) {
                const resource = try protocol.field(value, "resource");
                if (json.get(resource, "text")) |text| try append(a, &items, "text", try json.asString(text)) else {
                    const mime = if (json.get(resource, "mimeType")) |type_value| try json.asString(type_value) else "unknown type";
                    if (std.mem.startsWith(u8, mime, "image/")) try image(a, &items, try protocol.field(resource, "blob"), .{ .string = mime }) else try append(a, &items, "text", try std.fmt.allocPrint(a, "[binary resource {s} ({s}) omitted]", .{ try protocol.text(resource, "uri"), mime }));
                }
            } else try append(a, &items, "text", try std.fmt.allocPrint(a, "[unsupported MCP content {s}]", .{kind}));
        }
    }
    if (items.array.items.len == 0) if (json.get(result, "structuredContent")) |value| {
        const text = try std.json.Stringify.valueAlloc(a, value, .{ .whitespace = .indent_2 });
        try append(a, &items, "text", text);
    };
    owned.value = items;
    return owned;
}
