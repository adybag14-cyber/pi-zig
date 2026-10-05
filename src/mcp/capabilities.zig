//! Native tools/resources/templates/prompts facade over the owned MCP client.
const std = @import("std");
const session = @import("session.zig");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = protocol.Value;
pub const List = enum { tools, resources, resource_templates, prompts };
fn method(kind: List) []const u8 {
    return switch (kind) {
        .tools => "tools/list",
        .resources => "resources/list",
        .resource_templates => "resources/templates/list",
        .prompts => "prompts/list",
    };
}
fn key(kind: List) []const u8 {
    return switch (kind) {
        .tools => "tools",
        .resources => "resources",
        .resource_templates => "resourceTemplates",
        .prompts => "prompts",
    };
}
pub fn validateItem(kind: List, value: Value) !void {
    if (value != .object) return error.InvalidMcpListItem;
    switch (kind) {
        .tools => {
            _ = try protocol.text(value, "name");
            if (try protocol.field(value, "inputSchema") != .object) return error.InvalidMcpTool;
        },
        .resources, .resource_templates => {
            _ = try protocol.text(value, if (kind == .resources) "uri" else "uriTemplate");
            if (json.get(value, "name")) |name| if (name != .string) return error.InvalidMcpResource;
        },
        .prompts => {
            _ = try protocol.text(value, "name");
            if (json.get(value, "arguments")) |arguments| {
                if (arguments != .array) return error.InvalidMcpPrompt;
                for (arguments.array.items) |argument| {
                    _ = try protocol.text(argument, "name");
                    if (json.get(argument, "required")) |required| if (required != .bool) return error.InvalidMcpPrompt;
                }
            }
        },
    }
}
pub fn listAll(client: *session.Client, kind: List, options: session.RequestOptions) !json.Owned {
    var owned = try json.Owned.empty(client.gpa);
    errdefer owned.deinit();
    const a = owned.arena.allocator();
    var items: Value = .{ .array = .init(a) };
    var cursors: std.StringHashMapUnmanaged(void) = .empty;
    var cursor: ?[]const u8 = null;
    for (0..1000) |_| {
        var params: Value = .{ .object = .empty };
        if (cursor) |value| try params.object.put(a, "cursor", .{ .string = value });
        var page = try client.request(method(kind), if (cursor != null) params else null, options);
        defer page.deinit();
        if (page.value != .object) return error.InvalidMcpListPage;
        const list = try protocol.field(page.value, key(kind));
        if (list != .array) return error.InvalidMcpListPage;
        for (list.array.items) |value| {
            try validateItem(kind, value);
            var item = try json.clone(a, value);
            if ((kind == .resources or kind == .resource_templates) and json.get(item, "name") == null) try item.object.put(a, "name", try protocol.field(item, if (kind == .resources) "uri" else "uriTemplate"));
            try items.array.append(item);
        }
        const next = json.get(page.value, "nextCursor") orelse .null;
        if (next == .null or (next == .string and next.string.len == 0)) {
            owned.value = items;
            return owned;
        }
        if (next != .string) return error.InvalidMcpCursor;
        if (cursors.contains(next.string)) return error.DuplicateMcpCursor;
        const copied = try a.dupe(u8, next.string);
        try cursors.put(a, copied, {});
        cursor = copied;
    }
    return error.TooManyMcpPages;
}
pub fn validateCallTool(value: *Value, a: std.mem.Allocator) !void {
    if (value.* != .object) return error.InvalidMcpToolResult;
    if (json.get(value.*, "content")) |content| {
        if (content != .array) return error.InvalidMcpToolResult;
    } else try value.object.put(a, "content", .{ .array = .init(a) });
    if (json.get(value.*, "structuredContent")) |content| if (content != .object) return error.InvalidMcpStructuredContent;
}
pub fn callTool(client: *session.Client, name: []const u8, args: ?Value, options: session.RequestOptions) !json.Owned {
    var params = try json.Owned.empty(client.gpa);
    defer params.deinit();
    const a = params.arena.allocator();
    var value: Value = .{ .object = .empty };
    try value.object.put(a, "name", .{ .string = name });
    if (args) |arguments| {
        if (arguments != .object) return error.InvalidMcpArguments;
        try value.object.put(a, "arguments", arguments);
    }
    var reply = try client.request("tools/call", value, options);
    errdefer reply.deinit();
    try validateCallTool(&reply.value, reply.arena.allocator());
    return reply;
}
pub fn validateResource(value: Value) !void {
    if (value != .object) return error.InvalidMcpResourceResult;
    const contents = try protocol.field(value, "contents");
    if (contents != .array) return error.InvalidMcpResourceResult;
    for (contents.array.items) |item| {
        _ = try protocol.text(item, "uri");
        const text = json.get(item, "text");
        const blob = json.get(item, "blob");
        if ((text == null or text.? != .string) and (blob == null or blob.? != .string)) return error.InvalidMcpResourceContents;
    }
}
pub fn readResource(client: *session.Client, uri: []const u8, options: session.RequestOptions) !json.Owned {
    var params = try json.Owned.empty(client.gpa);
    defer params.deinit();
    var value: Value = .{ .object = .empty };
    try value.object.put(params.arena.allocator(), "uri", .{ .string = uri });
    var reply = try client.request("resources/read", value, options);
    errdefer reply.deinit();
    try validateResource(reply.value);
    return reply;
}
pub fn getPrompt(client: *session.Client, name: []const u8, args: ?Value, options: session.RequestOptions) !json.Owned {
    var params = try json.Owned.empty(client.gpa);
    defer params.deinit();
    const a = params.arena.allocator();
    var value: Value = .{ .object = .empty };
    try value.object.put(a, "name", .{ .string = name });
    if (args) |arguments| {
        if (arguments != .object) return error.InvalidMcpPromptArguments;
        var iterator = arguments.object.iterator();
        while (iterator.next()) |item| if (item.value_ptr.* != .string) return error.InvalidMcpPromptArguments;
        try value.object.put(a, "arguments", arguments);
    }
    var reply = try client.request("prompts/get", value, options);
    errdefer reply.deinit();
    const messages = try protocol.field(reply.value, "messages");
    if (messages != .array) return error.InvalidMcpPromptResult;
    for (messages.array.items) |message| {
        const role = try protocol.text(message, "role");
        if (!std.mem.eql(u8, role, "user") and !std.mem.eql(u8, role, "assistant")) return error.InvalidMcpPromptRole;
        if (try protocol.field(message, "content") != .object) return error.InvalidMcpPromptResult;
    }
    return reply;
}
