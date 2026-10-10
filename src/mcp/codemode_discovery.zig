//! Session codemode discovery over the invocation's owned tool metadata.
const std = @import("std");
const search = @import("tool_search.zig");
pub const Namespace = search.Namespace;
pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    sample: []const u8,
    parameters: std.json.Value = .null,
    namespace: ?Namespace = null,
};
pub fn identifier(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);
    var iterator = std.unicode.Wtf8View.initUnchecked(name).iterator();
    while (iterator.nextCodepoint()) |point| {
        const valid = point < 128 and (std.ascii.isAlphabetic(@intCast(point)) or point == '_' or point == '$' or (output.items.len != 0 and std.ascii.isDigit(@intCast(point))));
        try output.append(gpa, if (valid) @intCast(point) else '_');
    }
    if (output.items.len == 0) try output.append(gpa, '_');
    return output.toOwnedSlice(gpa);
}
pub fn namespaceMatches(gpa: std.mem.Allocator, namespace: []const u8, query: []const u8) !bool {
    const id = try identifier(gpa, namespace);
    defer gpa.free(id);
    const query_id = try identifier(gpa, query);
    defer gpa.free(query_id);
    if (std.mem.eql(u8, namespace, query) or std.mem.eql(u8, id, query_id)) return true;
    if (std.mem.lastIndexOf(u8, namespace, "__")) |offset| if (std.mem.eql(u8, namespace[offset + 2 ..], query)) return true;
    if (std.mem.lastIndexOf(u8, id, "__")) |offset| if (std.mem.eql(u8, id[offset + 2 ..], query_id)) return true;
    return false;
}
pub fn findTool(gpa: std.mem.Allocator, tools: []const Tool, name: []const u8) !?usize {
    for (tools, 0..) |tool, index| {
        if (std.mem.eql(u8, tool.name, name)) return index;
        const id = try identifier(gpa, tool.name);
        defer gpa.free(id);
        if (std.mem.eql(u8, id, name)) return index;
    }
    return null;
}
pub fn rank(gpa: std.mem.Allocator, tools: []const Tool, query: []const u8, limit: usize, namespace: ?[]const u8) ![]search.Match {
    var documents: std.ArrayList(search.Document) = .empty;
    defer {
        for (documents.items) |document| gpa.free(document.text);
        documents.deinit(gpa);
    }
    for (tools) |tool| {
        if (namespace) |filter| if (filter.len > 0) {
            const info = tool.namespace orelse continue;
            if (!try namespaceMatches(gpa, info.name, filter)) continue;
        };
        const document = try search.createDocument(gpa, .{ .name = tool.name, .description = tool.description, .parameters = tool.parameters }, tool.namespace);
        documents.append(gpa, document) catch |cause| {
            gpa.free(document.text);
            return cause;
        };
    }
    return search.rank(gpa, query, documents.items, limit, .{});
}
