//! Source-backed direct MCP tool names, input schemas and model-facing results.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = protocol.Value;
const tools = @import("../agent/tools.zig");
const temporary = @import("../durable/temporary.zig");
const decode = @import("../durable/decode.zig");
const url = @import("../extensions/url_parser.zig");
pub const output_max_bytes = 20 * 1024;

fn usv(a: std.mem.Allocator, text: []const u8) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(a);
    var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
    while (iterator.nextCodepoint()) |point| {
        var encoded: [4]u8 = undefined;
        const n = try std.unicode.utf8Encode(if (point >= 0xd800 and point <= 0xdfff) 0xfffd else point, &encoded);
        try bytes.appendSlice(a, encoded[0..n]);
    }
    return bytes.toOwnedSlice(a);
}
pub fn toolName(a: std.mem.Allocator, server: []const u8, tool: []const u8, taken: bool) ![]u8 {
    const raw = try std.fmt.allocPrint(a, "mcp__{s}__{s}", .{ server, tool });
    defer a.free(raw);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(a);
    var iterator = (try std.unicode.Wtf8View.init(raw)).iterator();
    while (iterator.nextCodepoint()) |point| {
        if (point < 128 and (std.ascii.isAlphanumeric(@intCast(point)) or point == '_')) try output.append(a, @intCast(point)) else {
            try output.append(a, '_');
            if (point > 0xffff) try output.append(a, '_');
        }
    }
    if (output.items.len <= 64 and !taken) return output.toOwnedSlice(a);
    const first = try usv(a, server);
    defer a.free(first);
    const second = try usv(a, tool);
    defer a.free(second);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(first);
    hash.update(&.{0});
    hash.update(second);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    return std.fmt.allocPrint(a, "{s}_{s}", .{ output.items[0..@min(55, output.items.len)], hex[0..8] });
}
pub fn trimJs(text: []const u8) ![]const u8 {
    var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
    var begin: usize = 0;
    var end: usize = 0;
    var leading = true;
    while (iterator.nextCodepoint()) |point| {
        const whitespace = (point >= 9 and point <= 13) or point == 0x20 or point == 0xa0 or point == 0x1680 or (point >= 0x2000 and point <= 0x200a) or point == 0x2028 or point == 0x2029 or point == 0x202f or point == 0x205f or point == 0x3000 or point == 0xfeff;
        if (leading and whitespace) begin = iterator.i else if (!whitespace) {
            leading = false;
            end = iterator.i;
        }
    }
    return text[begin..@max(begin, end)];
}

pub fn schema(a: std.mem.Allocator, server: []const u8, model_name: []const u8, tool: Value) !Value {
    const raw_name = try protocol.text(tool, "name");
    var parameters = try json.clone(a, try protocol.field(tool, "inputSchema"));
    if (parameters != .object) return error.InvalidMcpTool;
    if (json.get(parameters, "type") == null or json.get(parameters, "type").? == .null) try parameters.object.put(a, "type", .{ .string = "object" });
    if (json.get(parameters, "properties") == null) try parameters.object.put(a, "properties", .{ .object = .empty });
    var description: ?[]const u8 = null;
    if (json.get(tool, "description")) |item| if (item == .string and (try trimJs(item.string)).len > 0) {
        description = try trimJs(item.string);
    };
    if (description == null) if (json.get(tool, "title")) |item| if (item == .string and item.string.len > 0) {
        description = item.string;
    };
    if (description == null and (json.get(tool, "title") == null or json.get(tool, "title").? == .null)) if (json.get(tool, "annotations")) |annotation| if (json.get(annotation, "title")) |item| if (item == .string and item.string.len > 0) {
        description = item.string;
    };
    var function: Value = .{ .object = .empty };
    try function.object.put(a, "name", .{ .string = try a.dupe(u8, model_name) });
    try function.object.put(a, "description", .{ .string = if (description) |value| try a.dupe(u8, value) else try std.fmt.allocPrint(a, "MCP tool {s} from server {s}", .{ raw_name, server }) });
    try function.object.put(a, "parameters", parameters);
    var result: Value = .{ .object = .empty };
    try result.object.put(a, "type", .{ .string = "function" });
    try result.object.put(a, "function", function);
    return result;
}
/// Discovery metadata stays separate from the provider-facing function schema.
pub fn codemodeMetadata(a: std.mem.Allocator, server: []const u8, configuration: Value, initialized: Value, tool: Value) !Value {
    const namespace_name = try std.fmt.allocPrint(a, "mcp__{s}", .{server});
    for (namespace_name) |*byte| if (byte.* == '-') {
        byte.* = '_';
    };
    var namespace: Value = .{ .object = .empty };
    try namespace.object.put(a, "name", .{ .string = namespace_name });
    for ([_]struct { source: Value, key: []const u8 }{ .{ .source = configuration, .key = "description" }, .{ .source = initialized, .key = "instructions" } }) |field| {
        if (json.get(field.source, field.key)) |text| if (text == .string) {
            const trimmed = try trimJs(text.string);
            if (trimmed.len > 0) try namespace.object.put(a, field.key, .{ .string = try a.dupe(u8, trimmed) });
        };
    }
    var result_schema = try json.Owned.parse(a, "{\"type\":\"object\",\"properties\":{\"content\":{\"type\":\"array\",\"items\":{\"type\":\"object\"}},\"isError\":{\"type\":\"boolean\"},\"_meta\":{\"type\":\"object\"}},\"required\":[\"content\"]}");
    defer result_schema.deinit();
    var output = try json.clone(a, result_schema.value);
    if (json.get(tool, "outputSchema")) |structured| if (structured == .object) try output.object.getPtr("properties").?.object.put(a, "structuredContent", try json.clone(a, structured));
    var metadata: Value = .{ .object = .empty };
    try metadata.object.put(a, "namespace", namespace);
    try metadata.object.put(a, "outputSchema", output);
    return metadata;
}
fn size(a: std.mem.Allocator, n: f64) ![]u8 {
    if (n < 1024) return std.fmt.allocPrint(a, "{d}B", .{n});
    return std.fmt.allocPrint(a, "{d:.1}{s}", .{ n / @as(f64, if (n < 1024 * 1024) 1024 else 1024 * 1024), if (n < 1024 * 1024) "KB" else "MB" });
}
fn textBlock(a: std.mem.Allocator, list: *Value, text: []const u8) !void {
    var value: Value = .{ .object = .empty };
    try value.object.put(a, "type", .{ .string = "text" });
    try value.object.put(a, "text", .{ .string = try a.dupe(u8, text) });
    try list.array.append(value);
}
fn removeSaved(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch {};
    // temporary.file creates and exclusively owns this UUID parent directory.
    if (std.fs.path.dirname(path)) |directory| std.Io.Dir.cwd().deleteDir(io, directory) catch {};
}
fn save(a: std.mem.Allocator, io: std.Io, root: []const u8, bytes: []const u8, suffix: []const u8) ![]u8 {
    const file = try temporary.file(a, io, root, "pi-mcp-", suffix);
    errdefer {
        removeSaved(io, file.path);
        a.free(file.path);
    }
    defer file.file.close(io);
    try file.file.writeStreamingAll(io, bytes);
    return file.path;
}
fn saveTracked(a: std.mem.Allocator, io: std.Io, root: []const u8, bytes: []const u8, suffix: []const u8, paths: *std.ArrayList([]const u8)) ![]u8 {
    const path = try save(a, io, root, bytes, suffix);
    paths.append(a, path) catch |cause| {
        removeSaved(io, path);
        a.free(path);
        return cause;
    };
    return path;
}
fn extension(a: std.mem.Allocator, uri: []const u8) ![]u8 {
    var record = url.parse(a, uri, null) catch |cause| {
        if (cause == error.OutOfMemory) return cause;
        return extensionRaw(a, uri);
    };
    defer record.deinit(a);
    return extensionRaw(a, record.path);
}
fn extensionRaw(a: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '.')) |at| if (path.len - at >= 2 and path.len - at <= 9) {
        for (path[at + 1 ..]) |byte| if (!std.ascii.isAlphanumeric(byte)) return a.dupe(u8, ".bin");
        return a.dupe(u8, path[at..]);
    };
    return a.dupe(u8, ".bin");
}
fn decodedText(a: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const Sink = struct {
        a: std.mem.Allocator,
        list: std.ArrayList(u8) = .empty,
        pub fn codepoint(self: *@This(), point: u21) !void {
            var encoded: [4]u8 = undefined;
            const n = try std.unicode.utf8Encode(point, &encoded);
            try self.list.appendSlice(self.a, encoded[0..n]);
        }
    };
    var sink: Sink = .{ .a = a };
    errdefer sink.list.deinit(a);
    var decoder: decode.Decoder = .{};
    try decoder.push(bytes, &sink);
    try decoder.finish(&sink);
    return sink.list.toOwnedSlice(a);
}
fn block(a: std.mem.Allocator, io: std.Io, root: []const u8, server: []const u8, item: Value, list: *Value, saved: *std.ArrayList([]const u8)) !void {
    const kind = try protocol.text(item, "type");
    if (std.mem.eql(u8, kind, "resource_link")) {
        const uri = try protocol.text(item, "uri");
        const title = if (json.get(item, "title")) |value| if (value != .null) try json.asString(value) else try protocol.text(item, "name") else try protocol.text(item, "name");
        var extras: std.ArrayList(u8) = .empty;
        defer extras.deinit(a);
        if (json.get(item, "mimeType")) |value| try extras.appendSlice(a, try json.asString(value));
        if (json.get(item, "size")) |value| {
            if (extras.items.len > 0) try extras.appendSlice(a, ", ");
            const formatted = try size(a, try json.asNumber(value));
            defer a.free(formatted);
            try extras.appendSlice(a, formatted);
        }
        const details = if (extras.items.len > 0) try std.fmt.allocPrint(a, " ({s})", .{extras.items}) else try a.dupe(u8, "");
        defer a.free(details);
        const description = if (json.get(item, "description")) |value| try std.fmt.allocPrint(a, ": {s}", .{try json.asString(value)}) else try a.dupe(u8, "");
        defer a.free(description);
        const text = try std.fmt.allocPrint(a, "[Resource {s} \"{s}\"{s}{s}]", .{ uri, title, details, description });
        defer a.free(text);
        try textBlock(a, list, text);
        return;
    }
    if (std.mem.eql(u8, kind, "resource")) {
        const resource = try protocol.field(item, "resource");
        if (json.get(resource, "blob")) |blob_value| {
            const mime = if (json.get(resource, "mimeType")) |value| try json.asString(value) else "unknown type";
            if (!std.mem.startsWith(u8, mime, "image/")) {
                const encoded = try json.asString(blob_value);
                const n = try std.base64.standard.Decoder.calcSizeForSlice(encoded);
                const bytes = try a.alloc(u8, n);
                defer a.free(bytes);
                try std.base64.standard.Decoder.decode(bytes, encoded);
                const semicolon = std.mem.indexOfScalar(u8, mime, ';') orelse mime.len;
                const normalized = try std.ascii.allocLowerString(a, try trimJs(mime[0..semicolon]));
                defer a.free(normalized);
                if (std.mem.startsWith(u8, normalized, "text/") or std.mem.eql(u8, normalized, "application/json") or std.mem.endsWith(u8, normalized, "+json") or std.mem.endsWith(u8, normalized, "+xml")) {
                    const text = try decodedText(a, bytes);
                    defer a.free(text);
                    try textBlock(a, list, text);
                    return;
                }
                const uri = try protocol.text(resource, "uri");
                const suffix = try extension(a, uri);
                defer a.free(suffix);
                const path = saveTracked(a, io, root, bytes, suffix, saved) catch |cause| {
                    if (cause == error.OutOfMemory) return cause;
                    const message = try std.fmt.allocPrint(a, "[Binary resource {s} ({s}) could not be saved: {s}]", .{ uri, mime, @errorName(cause) });
                    defer a.free(message);
                    try textBlock(a, list, message);
                    return;
                };

                const formatted = try size(a, @floatFromInt(bytes.len));
                defer a.free(formatted);
                const message = try std.fmt.allocPrint(a, "[Binary resource {s} ({s}, {s}) saved to {s}]", .{ uri, mime, formatted, path });
                defer a.free(message);
                try textBlock(a, list, message);
                return;
            }
        }
    }
    var single: Value = .{ .object = .empty };
    var content: Value = .{ .array = .init(a) };
    try content.array.append(item);
    try single.object.put(a, "content", content);
    var projection = try @import("content.zig").toLlmContent(a, single);
    defer projection.deinit();
    for (projection.value.array.items) |value| try list.array.append(try json.clone(a, value));
    _ = server;
}
pub fn convert(gpa: std.mem.Allocator, io: std.Io, root: []const u8, server: []const u8, tool: []const u8, reply: Value) !tools.ToolResult {
    var owned = try json.Owned.empty(gpa);
    defer owned.deinit();
    const a = owned.arena.allocator();
    var saved: std.ArrayList([]const u8) = .empty;
    errdefer for (saved.items) |path| removeSaved(io, path);
    var projected: Value = .{ .array = .init(a) };
    const content = try protocol.field(reply, "content");
    if (content != .array) return error.InvalidMcpToolResult;
    if (content.array.items.len > 0) {
        for (content.array.items) |item| try block(a, io, root, server, item, &projected, &saved);
    } else {
        var fallback = try @import("content.zig").toLlmContent(gpa, reply);
        defer fallback.deinit();
        projected = try json.clone(a, fallback.value);
    }
    var combined: std.ArrayList(u8) = .empty;
    defer combined.deinit(a);
    var text_count: usize = 0;
    for (projected.array.items) |item| if (std.mem.eql(u8, try protocol.text(item, "type"), "text")) {
        if (text_count > 0) try combined.append(a, '\n');
        try combined.appendSlice(a, try protocol.text(item, "text"));
        text_count += 1;
    };
    const is_error = if (json.get(reply, "isError")) |value| if (value == .bool) value.bool else return error.InvalidMcpToolResult else false;
    if (is_error and combined.items.len == 0) {
        if (text_count > 0) try combined.append(a, '\n');
        try combined.appendSlice(a, try std.fmt.allocPrint(a, "MCP tool {s}/{s} returned an error", .{ server, tool }));
    }
    var full_path: ?[]const u8 = null;
    if (combined.items.len > output_max_bytes) {
        const bytes = try usv(a, combined.items);
        var head: usize = output_max_bytes / 2;
        while (head > 0 and (bytes[head] & 0xc0) == 0x80) head -= 1;
        var tail = bytes.len - output_max_bytes / 2;
        while (tail < bytes.len and (bytes[tail] & 0xc0) == 0x80) tail += 1;
        var removed: usize = 0;
        for (bytes[head..tail]) |byte| if ((byte & 0xc0) != 0x80) {
            removed += 1;
        };
        const line_count = std.mem.count(u8, bytes, "\n") + @as(usize, @intFromBool(bytes.len > 0 and bytes[bytes.len - 1] != '\n'));
        const where = blk: {
            full_path = saveTracked(a, io, root, bytes, ".txt", &saved) catch |cause| {
                if (cause == error.OutOfMemory) return cause;
                break :blk try std.fmt.allocPrint(a, "[Could not save the full output: {s}]", .{@errorName(cause)});
            };
            break :blk try std.fmt.allocPrint(a, "[Full output: {s} (read it with offset/limit)]", .{full_path.?});
        };
        const limited = try std.fmt.allocPrint(a, "Warning: truncated output (original token count: {d})\nTotal output lines: {d}\n\n{s}…{d} chars truncated…{s}\n\n{s}", .{ (bytes.len + 3) / 4, line_count, bytes[0..head], removed, bytes[tail..], where });
        combined.clearRetainingCapacity();
        try combined.appendSlice(a, limited);
    }
    var images: std.ArrayList(tools.ToolImage) = .empty;
    errdefer {
        for (images.items) |*image| image.deinit(gpa);
        images.deinit(gpa);
    }
    for (projected.array.items) |item| if (std.mem.eql(u8, try protocol.text(item, "type"), "image")) {
        const data = try gpa.dupe(u8, try protocol.text(item, "data"));
        errdefer gpa.free(data);
        const mime = try gpa.dupe(u8, try protocol.text(item, "mimeType"));
        errdefer gpa.free(mime);
        try images.append(gpa, .{ .data_b64 = data, .mime_type = mime });
    };
    var details: Value = .{ .object = .empty };
    try details.object.put(a, "server", .{ .string = server });
    try details.object.put(a, "tool", .{ .string = tool });
    if (full_path) |path| try details.object.put(a, "fullOutputPath", .{ .string = path });
    var structured = try json.clone(a, reply);
    _ = structured.object.orderedRemove("_meta");
    try details.object.put(a, "structuredContent", structured);
    const text = try gpa.dupe(u8, combined.items);
    errdefer gpa.free(text);
    const details_json = try json.stringify(gpa, details);
    errdefer gpa.free(details_json);
    const owned_images = try images.toOwnedSlice(gpa);
    return .{ .content = text, .is_error = is_error, .images = owned_images, .details_json = details_json };
}
