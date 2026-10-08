//! Agent-facing MCP resource tools over explicitly admitted native server operations.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = json.Value;
pub const Operation = enum { resources_page, templates_page, all_resources, all_templates, read };
pub const Server = struct { name: []const u8, timeout_ms: f64, context: ?*anyopaque, invoke: *const fn (?*anyopaque, std.mem.Allocator, Operation, ?[]const u8, ?*const bool) anyerror!Reply };
pub const Reply = struct { value: json.Owned, error_message: ?[]const u8 = null };
pub const Outcome = struct { value: json.Owned, is_error: bool = false };
fn failure(gpa: std.mem.Allocator, message: []const u8) !Outcome {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    result.value = .{ .object = .empty };
    const a = result.arena.allocator();
    try result.value.object.put(a, "name", .{ .string = "Error" });
    try result.value.object.put(a, "message", .{ .string = try a.dupe(u8, message) });
    return .{ .value = result, .is_error = true };
}
fn argument(value: Value, key: []const u8) error{InvalidArgument}!?[]const u8 {
    const item = json.get(value, key) orelse return null;
    if (item == .null) return null;
    if (item != .string) return error.InvalidArgument;
    const trimmed = @import("codemode_declarations.zig").trimJs(item.string);
    return if (trimmed.len == 0) null else trimmed;
}
pub fn isApp(item: Value) bool {
    const primary = json.get(item, "uri");
    const uri = if (primary == null or primary.? == .null) json.get(item, "uriTemplate") else primary;
    if (uri) |value| if (value == .string and std.mem.startsWith(u8, value.string, "ui://")) return true;
    const mime = json.get(item, "mimeType") orelse return false;
    if (mime != .string) return false;
    var start: usize = 0;
    while (std.mem.indexOfScalarPos(u8, mime.string, start, ';')) |index| {
        var text = @import("codemode_declarations.zig").trimJs(mime.string[index + 1 ..]);
        if (text.len >= 7 and std.ascii.eqlIgnoreCase(text[0..7], "profile")) {
            text = @import("codemode_declarations.zig").trimJs(text[7..]);
            if (text.len > 0 and text[0] == '=') {
                text = @import("codemode_declarations.zig").trimJs(text[1..]);
                if (text.len > 0 and text[0] == '"') text = text[1..];
                if (text.len >= 7 and std.ascii.eqlIgnoreCase(text[0..7], "mcp-app")) return true;
            }
        }
        start = index + 1;
    }
    return false;
}
fn listing(a: std.mem.Allocator, name: []const u8, item: Value) !Value {
    var result: Value = .{ .object = .empty };
    try result.object.put(a, "server", .{ .string = try a.dupe(u8, name) });
    if (item == .object) {
        var iterator = item.object.iterator();
        while (iterator.next()) |field| {
            if (std.mem.eql(u8, field.key_ptr.*, "_meta") or std.mem.eql(u8, field.key_ptr.*, "icons")) continue;
            try result.object.put(a, try a.dupe(u8, field.key_ptr.*), try json.clone(a, field.value_ptr.*));
        }
    }
    return result;
}
fn namespaceLess(_: void, left: Server, right: Server) bool {
    const n = @min(left.name.len, right.name.len);
    for (left.name[0..n], right.name[0..n]) |l, r| if (namespaceWeight(l) != namespaceWeight(r)) return namespaceWeight(l) < namespaceWeight(r);
    if (left.name.len != right.name.len) return left.name.len < right.name.len;
    for (left.name, right.name) |l, r| if (l != r) return std.ascii.isLower(l);
    return false;
}
fn namespaceWeight(byte: u8) u8 {
    // MCP config permits only ASCII letters, digits, underscore and hyphen.
    // ICU's primary ordering puts underscore before hyphen before digits.
    return switch (byte) {
        '_' => 0,
        '-' => 1,
        else => std.ascii.toLower(byte),
    };
}
const ListingJob = struct {
    gpa: std.mem.Allocator,
    server: Server,
    operation: Operation,
    aborted: ?*const bool,
    reply: ?Reply = null,
    cause: ?anyerror = null,
    future: ?std.Io.Future(void) = null,
    fn run(self: *ListingJob) void {
        self.reply = self.server.invoke(self.server.context, self.gpa, self.operation, null, self.aborted) catch |cause| {
            self.cause = cause;
            return;
        };
    }
    fn deinit(self: *ListingJob, io: std.Io) void {
        if (self.future) |*future| future.cancel(io);
        if (self.reply) |*reply| reply.value.deinit();
    }
};

test "MCP resource adapter admits every server concurrently before settling sorted results" {
    const Backend = struct {
        io: std.Io,
        entered: std.atomic.Value(usize) = .init(0),
        all_entered: std.Io.Event = .unset,
        fn invoke(raw: ?*anyopaque, gpa: std.mem.Allocator, _: Operation, _: ?[]const u8, flag: ?*const bool) !Reply {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (self.entered.fetchAdd(1, .acq_rel) == 2) self.all_entered.set(self.io);
            try self.all_entered.waitTimeout(self.io, .{ .duration = .{ .raw = .fromSeconds(2), .clock = .awake } });
            try std.testing.expect(flag != null);
            return .{ .value = try json.Owned.parse(gpa, "[]") };
        }
    };
    var backend: Backend = .{ .io = std.testing.io };
    var flag = false;
    const servers = [_]Server{
        .{ .name = "zeta", .timeout_ms = 73, .context = &backend, .invoke = Backend.invoke },
        .{ .name = "Alpha", .timeout_ms = 73, .context = &backend, .invoke = Backend.invoke },
        .{ .name = "beta", .timeout_ms = 73, .context = &backend, .invoke = Backend.invoke },
    };
    var result = try execute(std.testing.allocator, std.testing.io, &servers, "list_mcp_resources", .{ .object = .empty }, &flag);
    defer result.value.deinit();
    try std.testing.expectEqual(@as(usize, 3), backend.entered.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), result.value.value.object.get("resources").?.array.items.len);
}

test "MCP resource adapter owns every allocation across concurrent success and typed failures" {
    const Check = struct {
        fn invoke(_: ?*anyopaque, gpa: std.mem.Allocator, _: Operation, _: ?[]const u8, _: ?*const bool) !Reply {
            return .{ .value = try json.Owned.parse(gpa, "[{\"uri\":\"file:///resource\",\"name\":\"visible\",\"_meta\":{\"hidden\":true}}]") };
        }
        fn run(gpa: std.mem.Allocator) !void {
            const servers = [_]Server{.{ .name = "native", .timeout_ms = 73, .context = null, .invoke = invoke }};
            var result = try execute(gpa, std.testing.io, &servers, "list_mcp_resources", .{ .object = .empty }, null);
            defer result.value.deinit();
            var converted = try toToolResult(gpa, std.testing.io, ".", "list_mcp_resources", &result);
            defer converted.deinit(gpa);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}

test "MCP resource adapter client pages replay original validation cursor normalization and fallback names" {
    const gpa = std.testing.allocator;
    var corpus = try json.Owned.parse(gpa, @embedFile("fixtures/mcp-resource-client-original-6fb.json"));
    defer corpus.deinit();
    for ((try protocol.field(corpus.value, "rows")).array.items) |row| {
        var page = try json.Owned.empty(gpa);
        defer page.deinit();
        page.value = try json.clone(page.arena.allocator(), try protocol.field(row, "payload"));
        const templates = std.mem.eql(u8, try protocol.text(row, "method"), "templates");
        @import("capabilities.zig").normalizeListPage(&page, if (templates) .resource_templates else .resources) catch |cause| {
            if (cause == error.OutOfMemory) return cause;
            try std.testing.expect(json.get(row, "error") != null);
            continue;
        };
        try std.testing.expect(json.get(row, "error") == null);
        try std.testing.expect(json.equal(try protocol.field(row, "result"), page.value));
    }
}

test "MCP resource adapter replays original binary text MIME decoding image bytes and saved files" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var corpus = try json.Owned.parse(gpa, @embedFile("fixtures/mcp-resource-content-original-6fb.json"));
    defer corpus.deinit();
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_length = try scratch.dir.realPath(io, &path_buffer);
    for (corpus.value.object.get("rows").?.array.items, 0..) |row, index| {
        var outcome: Outcome = .{ .value = try json.Owned.empty(gpa) };
        defer outcome.value.deinit();
        const a = outcome.value.arena.allocator();
        outcome.value.value = .{ .object = .empty };
        try outcome.value.value.object.put(a, "server", .{ .string = "native" });
        try outcome.value.value.object.put(a, "uri", try json.clone(a, try protocol.field(try protocol.field(row, "resource"), "uri")));
        var contents: Value = .{ .array = .init(a) };
        try contents.array.append(try json.clone(a, try protocol.field(row, "resource")));
        try outcome.value.value.object.put(a, "contents", contents);
        var result = try toToolResult(gpa, io, path_buffer[0..path_length], "read_mcp_resource", &outcome);
        defer result.deinit(gpa);
        const expected = (try protocol.field(row, "content")).array.items[0];
        const saved = (try protocol.field(row, "saved")).array.items;
        if (std.mem.eql(u8, try protocol.text(expected, "type"), "image")) {
            try std.testing.expectEqual(@as(usize, 1), result.images.len);
            try std.testing.expectEqualStrings(try protocol.text(expected, "data"), result.images[0].data_b64);
            try std.testing.expectEqualStrings(try protocol.text(expected, "mimeType"), result.images[0].mime_type);
            try std.testing.expectEqualStrings("", result.content);
        } else if (saved.len == 0) {
            if (!std.mem.eql(u8, try protocol.text(expected, "text"), result.content)) {
                std.debug.print("Resource content case{} expected{s} actual{s}\n", .{ index, try protocol.text(expected, "text"), result.content });
                return error.OriginalResourceContentMismatch;
            }
        } else {
            const marker = std.mem.indexOf(u8, result.content, " saved to ") orelse return error.MissingSavedResource;
            const path = result.content[marker + " saved to ".len .. result.content.len - 1];
            const suffix = try protocol.text(saved[0], "extension");
            try std.testing.expect(std.mem.endsWith(u8, path, suffix));
            const normalized = try std.fmt.allocPrint(gpa, "{s}SAVED{s}]", .{ result.content[0 .. marker + " saved to ".len], suffix });
            defer gpa.free(normalized);
            try std.testing.expectEqualStrings(try protocol.text(expected, "text"), normalized);
            const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024));
            defer gpa.free(bytes);
            const original_bytes = (try protocol.field(saved[0], "bytes")).array.items;
            try std.testing.expectEqual(original_bytes.len, bytes.len);
            for (original_bytes, bytes) |byte, actual| try std.testing.expectEqual(try json.asNumber(byte), @as(f64, @floatFromInt(actual)));
        }
    }
}

pub fn execute(gpa: std.mem.Allocator, io: std.Io, servers: []const Server, name: []const u8, params: Value, aborted: ?*const bool) !Outcome {
    const server_name = argument(params, "server") catch return failure(gpa, "server must be a string");
    const read = std.mem.eql(u8, name, "read_mcp_resource");
    const templates = std.mem.eql(u8, name, "list_mcp_resource_templates");
    const key = if (templates) "resourceTemplates" else "resources";
    const cursor_or_uri = argument(params, if (read) "uri" else "cursor") catch return failure(gpa, if (read) "uri must be a string" else "cursor must be a string");
    if (read and server_name == null) return failure(gpa, "server must be provided");
    if (read and cursor_or_uri == null) return failure(gpa, "uri must be provided");
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const a = result.arena.allocator();
    result.value = .{ .object = .empty };
    var selected: ?Server = null;
    if (server_name) |requested| for (servers) |server| if (std.mem.eql(u8, requested, server.name)) {
        selected = server;
        break;
    };
    if (server_name != null and selected == null) {
        var names: std.ArrayList([]const u8) = .empty;
        for (servers) |server| try names.append(a, server.name);
        const available = try std.mem.join(a, ", ", names.items);
        const message = if (available.len == 0) try std.fmt.allocPrint(a, "MCP server \"{s}\" has no resources", .{server_name.?}) else try std.fmt.allocPrint(a, "MCP server \"{s}\" has no resources. Servers with resources: {s}", .{ server_name.?, available });
        const failed = try failure(gpa, message);
        result.deinit();
        return failed;
    }
    if (selected) |server| {
        var reply = try server.invoke(server.context, gpa, if (read) .read else if (templates) .templates_page else .resources_page, cursor_or_uri, aborted);
        defer reply.value.deinit();
        if (reply.error_message) |message| {
            const failed = try failure(gpa, message);
            result.deinit();
            return failed;
        }
        try result.value.object.put(a, "server", .{ .string = try a.dupe(u8, server.name) });
        if (read) {
            try result.value.object.put(a, "uri", .{ .string = try a.dupe(u8, cursor_or_uri.?) });
            var contents: Value = .{ .array = .init(a) };
            for ((try protocol.field(reply.value.value, "contents")).array.items) |item| {
                var clean = try json.clone(a, item);
                if (clean == .object) _ = clean.object.orderedRemove("_meta");
                try contents.array.append(clean);
            }
            try result.value.object.put(a, "contents", contents);
        } else {
            var items: Value = .{ .array = .init(a) };
            for ((try protocol.field(reply.value.value, key)).array.items) |item| if (!isApp(item)) try items.array.append(try listing(a, server.name, item));
            try result.value.object.put(a, key, items);
            if (json.get(reply.value.value, "nextCursor")) |next| try result.value.object.put(a, "nextCursor", try json.clone(a, next));
        }
    } else {
        if (cursor_or_uri != null) {
            result.deinit();
            return failure(gpa, "cursor can only be used when a server is specified");
        }
        const ordered = try a.dupe(Server, servers);
        std.mem.sort(Server, ordered, {}, namespaceLess);
        var items: Value = .{ .array = .init(a) };
        var errors: Value = .{ .array = .init(a) };
        const jobs = try gpa.alloc(ListingJob, ordered.len);
        defer gpa.free(jobs);
        for (jobs, ordered) |*job, server| job.* = .{ .gpa = gpa, .server = server, .operation = if (templates) .all_templates else .all_resources, .aborted = aborted };
        defer for (jobs) |*job| job.deinit(io);
        for (jobs) |*job| job.future = try io.concurrent(ListingJob.run, .{job});
        // Admit every server before joining; retain sorted output order after all settle.
        for (jobs) |*job| {
            job.future.?.await(io);
            job.future = null;
        }
        for (jobs) |*job| {
            const server = job.server;
            if (job.cause) |cause| {
                if (cause == error.OutOfMemory) return cause;
                var item: Value = .{ .object = .empty };
                try item.object.put(a, "server", .{ .string = try a.dupe(u8, server.name) });
                try item.object.put(a, "error", .{ .string = try a.dupe(u8, @errorName(cause)) });
                try errors.array.append(item);
                continue;
            }
            const reply = &job.reply.?;
            if (reply.error_message) |message| {
                var item: Value = .{ .object = .empty };
                try item.object.put(a, "server", .{ .string = try a.dupe(u8, server.name) });
                try item.object.put(a, "error", .{ .string = try a.dupe(u8, message) });
                try errors.array.append(item);
                continue;
            }
            if (reply.value.value != .array) return error.InvalidMcpResourceList;
            for (reply.value.value.array.items) |item| if (!isApp(item)) try items.array.append(try listing(a, server.name, item));
        }
        try result.value.object.put(a, key, items);
        if (errors.array.items.len > 0) try result.value.object.put(a, "errors", errors);
    }
    return .{ .value = result };
}

test "MCP resource adapter replays original app filtering pagination errors and structured payloads" {
    const gpa = std.testing.allocator;
    var original = try json.Owned.parse(gpa, @embedFile("fixtures/mcp-resource-tools-original-6fb.json"));
    defer original.deinit();
    const Backend = struct {
        name: []const u8,
        original: Value,
        fn invoke(raw: ?*anyopaque, allocator: std.mem.Allocator, operation: Operation, input: ?[]const u8, _: ?*const bool) !Reply {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var result = try json.Owned.empty(allocator);
            errdefer result.deinit();
            const a = result.arena.allocator();
            if (std.mem.eql(u8, self.name, "bad") or (operation == .read and std.mem.eql(u8, input.?, "fail"))) {
                const message = if (operation == .read) "read failure" else if (operation == .all_templates or operation == .templates_page) "templates failure bad" else "list failure bad";
                result.value = .{ .string = try a.dupe(u8, message) };
                return .{ .value = result, .error_message = result.value.string };
            }
            const templates = operation == .all_templates or operation == .templates_page;
            if (operation == .all_resources or operation == .all_templates) result.value = try json.clone(a, self.original.object.get(if (templates) "templates" else "resources").?) else if (operation == .read) {
                var contents: Value = .{ .array = .init(a) };
                if (!std.mem.eql(u8, input.?, "empty")) {
                    const texts: []const []const u8 = if (std.mem.eql(u8, input.?, "many")) &.{ "first", "second" } else &.{"single"};
                    for (texts, 0..) |text, index| {
                        var item: Value = .{ .object = .empty };
                        try item.object.put(a, "uri", .{ .string = if (texts.len == 1) input.? else if (index == 0) "file:///one" else "file:///two" });
                        try item.object.put(a, "text", .{ .string = text });
                        try contents.array.append(item);
                    }
                }
                result.value = .{ .object = .empty };
                try result.value.object.put(a, "contents", contents);
            } else {
                result.value = .{ .object = .empty };
                try result.value.object.put(a, if (templates) "resourceTemplates" else "resources", try json.clone(a, self.original.object.get(if (templates) "templates" else "resources").?));
                if (templates or input == null) try result.value.object.put(a, "nextCursor", .{ .string = if (templates) "more" else "next" });
            }
            return .{ .value = result };
        }
    };
    var backends = [_]Backend{ .{ .name = "zeta", .original = original.value }, .{ .name = "Alpha", .original = original.value }, .{ .name = "bad", .original = original.value } };
    var servers: [3]Server = undefined;
    for (&backends, &servers) |*backend, *server| server.* = .{ .name = backend.name, .timeout_ms = 73, .context = backend, .invoke = Backend.invoke };
    for (original.value.object.get("appCases").?.array.items) |row| try std.testing.expectEqual(row.object.get("result").?.bool, isApp(row.object.get("input").?));
    for (original.value.object.get("nameComparisons").?.array.items) |row| {
        const left: Server = .{ .name = row.array.items[0].string, .timeout_ms = 73, .context = null, .invoke = Backend.invoke };
        var right = left;
        right.name = row.array.items[1].string;
        try std.testing.expectEqual((try json.asNumber(row.array.items[2])) < 0, namespaceLess({}, left, right));
    }
    for (original.value.object.get("rows").?.array.items, 0..) |row, index| {
        var result = try execute(gpa, std.testing.io, &servers, row.object.get("tool").?.string, row.object.get("input").?, null);
        defer result.value.deinit();
        const expected_error = row.object.get("error");
        const expected = expected_error orelse row.object.get("result").?.object.get("structuredContent").?;
        if (!result.is_error) {
            var rendered = try toToolResult(gpa, std.testing.io, ".", row.object.get("tool").?.string, &result);
            defer rendered.deinit(gpa);
            const original_result = row.object.get("result").?;
            var text: std.ArrayList([]const u8) = .empty;
            defer text.deinit(gpa);
            for (original_result.object.get("content").?.array.items) |block| if (std.mem.eql(u8, block.object.get("type").?.string, "text")) try text.append(gpa, block.object.get("text").?.string);
            const expected_text = try std.mem.join(gpa, "\n", text.items);
            defer gpa.free(expected_text);
            try std.testing.expectEqualStrings(expected_text, rendered.content);
            var details = try json.Owned.parse(gpa, rendered.details_json.?);
            defer details.deinit();
            try std.testing.expect(json.equal(original_result.object.get("structuredContent").?, details.value.object.get("structuredContent").?));
            try std.testing.expectEqualStrings(original_result.object.get("details").?.object.get("server").?.string, details.value.object.get("server").?.string);
        }
        if (result.is_error != (expected_error != null) or !json.equal(expected, result.value.value)) {
            const before = try json.stringify(gpa, expected);
            defer gpa.free(before);
            const after = try json.stringify(gpa, result.value.value);
            defer gpa.free(after);
            std.debug.print("Resource original case{} expected{s} actual{s}\n", .{ index, before, after });
            return error.OriginalResourceToolMismatch;
        }
    }
}

pub fn toToolResult(gpa: std.mem.Allocator, io: std.Io, output_root: []const u8, tool_name: []const u8, outcome: *const Outcome) !@import("../agent/tools.zig").ToolResult {
    if (outcome.is_error) return .{ .content = try gpa.dupe(u8, try protocol.text(outcome.value.value, "message")), .is_error = true };
    var envelope = try json.Owned.empty(gpa);
    defer envelope.deinit();
    const a = envelope.arena.allocator();
    envelope.value = .{ .object = .empty };
    var content: Value = .{ .array = .init(a) };
    const payload = outcome.value.value;
    const server = if (json.get(payload, "server")) |value| value.string else "";
    if (std.mem.eql(u8, tool_name, "read_mcp_resource")) {
        const contents = try protocol.field(payload, "contents");
        for (contents.array.items) |item| {
            if (contents.array.items.len > 1) {
                var label: Value = .{ .object = .empty };
                try label.object.put(a, "type", .{ .string = "text" });
                try label.object.put(a, "text", .{ .string = try std.fmt.allocPrint(a, "{s}:", .{try protocol.text(item, "uri")}) });
                try content.array.append(label);
            }
            var block: Value = .{ .object = .empty };
            try block.object.put(a, "type", .{ .string = "resource" });
            try block.object.put(a, "resource", try json.clone(a, item));
            try content.array.append(block);
        }
        if (content.array.items.len == 0) {
            var block: Value = .{ .object = .empty };
            try block.object.put(a, "type", .{ .string = "text" });
            try block.object.put(a, "text", .{ .string = try std.fmt.allocPrint(a, "Resource {s} is empty.", .{try protocol.text(payload, "uri")}) });
            try content.array.append(block);
        }
    } else {
        var block: Value = .{ .object = .empty };
        try block.object.put(a, "type", .{ .string = "text" });
        try block.object.put(a, "text", .{ .string = try json.stringify(a, payload) });
        try content.array.append(block);
    }
    try envelope.value.object.put(a, "content", content);
    var result = try @import("agent_tools.zig").convert(gpa, io, output_root, server, tool_name, envelope.value);
    errdefer result.deinit(gpa);
    var details = try json.Owned.parse(gpa, result.details_json.?);
    defer details.deinit();
    try details.value.object.put(details.arena.allocator(), "structuredContent", try json.clone(details.arena.allocator(), payload));
    const encoded = try json.stringify(gpa, details.value);
    gpa.free(result.details_json.?);
    result.details_json = encoded;
    return result;
}
