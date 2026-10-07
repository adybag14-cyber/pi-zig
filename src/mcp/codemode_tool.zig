//! Agent-facing codemode adapter. Nested calls use the caller's validated
//! pipeline; this layer owns formatting and branch-local successful stores.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = json.Value;
const sandbox = @import("codemode.zig");
const source_format = @import("codemode_source.zig");
const tools = @import("../agent/tools.zig");
const session_mod = @import("../agent/session.zig");
const temporary = @import("../durable/temporary.zig");

pub fn loadBranchStore(gpa: std.mem.Allocator, session: *const session_mod.Session) !json.Owned {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    result.value = .{ .object = .empty };
    const a = result.arena.allocator();
    const entries = try session.branchEntries(gpa);
    defer gpa.free(entries);
    for (entries) |entry| {
        if (entry.custom_type == null or !std.mem.eql(u8, entry.custom_type.?, "codemode-store") or entry.data_json == null) continue;
        var parsed = try json.Owned.parse(gpa, entry.data_json.?);
        defer parsed.deinit();
        const set = json.get(parsed.value, "set") orelse continue;
        const deleted = json.get(parsed.value, "delete") orelse continue;
        if ((set != .object and set != .array) or deleted != .array) continue;
        var valid = true;
        for (deleted.array.items) |name| if (name != .string) {
            valid = false;
            break;
        };
        if (!valid) continue;
        for (deleted.array.items) |name| _ = result.value.object.orderedRemove(name.string);
        if (set == .object) {
            var iterator = set.object.iterator();
            while (iterator.next()) |value| try result.value.object.put(a, try a.dupe(u8, value.key_ptr.*), try json.clone(a, value.value_ptr.*));
        } else for (set.array.items, 0..) |value, index| try result.value.object.put(a, try std.fmt.allocPrint(a, "{d}", .{index}), try json.clone(a, value));
    }
    return result;
}
pub fn appendBranchStore(raw: ?*anyopaque, writes: Value) !void {
    const session: *session_mod.Session = @ptrCast(@alignCast(raw.?));
    const encoded = try json.stringify(session.gpa, writes);
    defer session.gpa.free(encoded);
    _ = try session.appendCustomEntry("codemode-store", encoded);
}

pub const Entry = struct {
    name: []const u8,
    description: []const u8,
    structured_result: bool = false,
};
pub const Invoke = *const fn (?*anyopaque, std.mem.Allocator, []const u8, []const u8, []const u8, ?*bool) anyerror!tools.ToolResult;
pub const Options = struct {
    context: ?*anyopaque,
    invoke: Invoke,
    entries: []const Entry,
    call_id: []const u8,
    store: Value = .{ .object = .empty },
    append_context: ?*anyopaque = null,
    append_store: ?*const fn (?*anyopaque, Value) anyerror!void = null,
    output_root: ?[]const u8 = null,
};
const Call = struct {
    options: *const Options,
    entry: Entry,
    sequence: *std.atomic.Value(u64),
    fn run(raw: ?*anyopaque, gpa: std.mem.Allocator, arguments: ?Value, abort_flag: ?*bool) !json.Owned {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const encoded = if (arguments) |value| try json.stringify(gpa, value) else try gpa.dupe(u8, "{}");
        defer gpa.free(encoded);
        const call_id = try std.fmt.allocPrint(gpa, "{s}/{d}", .{ self.options.call_id, self.sequence.fetchAdd(1, .monotonic) + 1 });
        defer gpa.free(call_id);
        var result = try self.options.invoke(self.options.context, gpa, call_id, self.entry.name, encoded, abort_flag);
        defer result.deinit(gpa);
        var output = try json.Owned.empty(gpa);
        errdefer output.deinit();
        const a = output.arena.allocator();
        if (self.entry.structured_result and result.details_json != null) {
            var details = try json.Owned.parse(gpa, result.details_json.?);
            defer details.deinit();
            if (json.get(details.value, "structuredContent")) |value| {
                output.value = try json.clone(a, value);
                return output;
            }
        }
        if (result.is_error) {
            output.value = .{ .object = .empty };
            try output.value.object.put(a, "__pi_codemode_error", .{ .string = try a.dupe(u8, result.content) });
            return output;
        }
        output.value = .{ .string = try a.dupe(u8, result.content) };
        return output;
    }
};
pub fn execute(gpa: std.mem.Allocator, io: std.Io, code: []const u8, options: Options, abort_flag: ?*bool) !tools.ToolResult {
    const parsed = source_format.parse(gpa, code) catch |cause| {
        if (cause == error.OutOfMemory) return cause;
        return .{ .content = try source_format.diagnosticForInput(gpa, code, cause), .is_error = true };
    };
    const calls = try gpa.alloc(Call, options.entries.len);
    defer gpa.free(calls);
    const descriptions = try gpa.alloc(sandbox.Tool, options.entries.len);
    defer gpa.free(descriptions);
    var sequence: std.atomic.Value(u64) = .init(0);
    for (options.entries, calls, descriptions) |entry, *call, *description| {
        call.* = .{ .options = &options, .entry = entry, .sequence = &sequence };
        description.* = .{ .name = entry.name, .description = entry.description, .context = call, .execute = Call.run, .error_marker = true };
    }
    const started = std.Io.Clock.awake.now(io).toMilliseconds();
    var result = try sandbox.execute(gpa, io, descriptions, parsed.code, .{ .abort_flag = abort_flag, .timeout_ms = parsed.timeout_ms orelse 300_000, .store = options.store });
    defer result.deinit();
    const ok = result.value.object.get("ok").?.bool;
    if (ok) if (options.append_store) |append| {
        const writes = result.value.object.get("storeWrites").?;
        if (writes.object.get("set").?.object.count() != 0 or writes.object.get("delete").?.array.items.len != 0) try append(options.append_context, writes);
    };
    const a = result.arena.allocator();
    const output = &result.value.object.getPtr("output").?.array;
    if (ok) if (result.value.object.get("value")) |value| {
        var item: Value = .{ .object = .empty };
        try item.object.put(a, "type", .{ .string = "text" });
        try item.object.put(a, "text", .{ .string = if (value == .string) value.string else try json.stringify(a, value) });
        try output.append(item);
    };
    var text: std.Io.Writer.Allocating = .init(gpa);
    defer text.deinit();
    const wall_ms = @max(0, std.Io.Clock.awake.now(io).toMilliseconds() - started);
    const tenths = @divTrunc(wall_ms + 50, 100);
    var total: usize = 0;
    for (output.items) |item| {
        const kind = try protocol.text(item, "type");
        if (std.mem.eql(u8, kind, "text") and json.get(item, "console") == null) total += 1;
    }
    var console: std.Io.Writer.Allocating = .init(gpa);
    defer console.deinit();
    var images: std.ArrayList(tools.ToolImage) = .empty;
    errdefer {
        for (images.items) |*image| image.deinit(gpa);
        images.deinit(gpa);
    }
    var index: usize = 0;
    for (output.items) |item| {
        const kind = try protocol.text(item, "type");
        if (std.mem.eql(u8, kind, "image")) {
            const data = try gpa.dupe(u8, try protocol.text(item, "data"));
            errdefer gpa.free(data);
            const mime = try gpa.dupe(u8, try protocol.text(item, "mimeType"));
            errdefer gpa.free(mime);
            try images.append(gpa, .{ .data_b64 = data, .mime_type = mime });
        } else if (json.get(item, "console") != null) {
            if (console.written().len != 0) try console.writer.writeByte('\n');
            try console.writer.writeAll(try protocol.text(item, "text"));
        } else {
            index += 1;
            if (index > 1) try text.writer.writeByte('\n');
            if (total > 1) try text.writer.print("==> text {d}/{d} <==\n", .{ index, total });
            try text.writer.writeAll(try protocol.text(item, "text"));
        }
    }
    if (console.written().len != 0) try text.writer.print("\n<console_output>\n{s}\n</console_output>", .{console.written()});
    if (!ok) try text.writer.print("\nScript error:\n{s}", .{try protocol.text(result.value.object.get("error").?, "message")});
    var combined: std.Io.Writer.Allocating = .init(gpa);
    defer combined.deinit();
    try combined.writer.print("Script {s}\nWall time {d}.{d} seconds\nOutput:\n", .{ if (ok) "completed" else "failed", @divTrunc(tenths, 10), @mod(tenths, 10) });
    var full_path: ?[]u8 = null;
    defer if (full_path) |path| gpa.free(path);
    errdefer if (full_path) |path| {
        std.Io.Dir.cwd().deleteFile(io, path) catch {};
        if (std.fs.path.dirname(path)) |parent| std.Io.Dir.cwd().deleteDir(io, parent) catch {};
    };
    const raw = text.written();
    const budget = (parsed.max_output_tokens orelse 10_000) *| 4;
    const length = utf16Units(raw);
    if (length > budget) {
        const head_count = @divTrunc(budget, 2);
        const tail_count = budget - head_count;
        const head_end = utf8AtUnit(raw, head_count);
        const tail_start = utf8AtUnit(raw, length - tail_count);
        try combined.writer.print("Warning: truncated output (original token count: {d})\nTotal output lines: {d}\n\n{s}…{d} tokens truncated…{s}", .{ (length + 3) / 4, std.mem.count(u8, raw, "\n") + 1, raw[0..head_end], (length - budget + 3) / 4, raw[tail_start..] });
        if (options.output_root) |root| {
            const file = temporary.file(gpa, io, root, "pi-codemode-", ".txt") catch |cause| blk: {
                if (cause == error.OutOfMemory) return cause;
                break :blk null;
            };
            if (file) |opened| {
                var wrote = true;
                opened.file.writeStreamingAll(io, raw) catch |cause| {
                    opened.file.close(io);
                    std.Io.Dir.cwd().deleteFile(io, opened.path) catch {};
                    if (std.fs.path.dirname(opened.path)) |parent| std.Io.Dir.cwd().deleteDir(io, parent) catch {};
                    gpa.free(opened.path);
                    try combined.writer.print("\n\n[Could not save the full output: {s}]", .{@errorName(cause)});
                    wrote = false;
                };
                if (wrote) {
                    opened.file.close(io);
                    full_path = opened.path;
                    try combined.writer.print("\n\n[Full output: {s} (read with offset/limit)]", .{opened.path});
                }
            } else try combined.writer.writeAll("\n\n[Could not save the full output: temporary file unavailable]");
        } else try combined.writer.writeAll("\n\n[Could not save the full output: temporary directory unavailable]");
    } else try combined.writer.writeAll(raw);
    const content = try combined.toOwnedSlice();
    errdefer gpa.free(content);
    const details = try json.stringify(gpa, .{ .object = blk: {
        var object: std.json.ObjectMap = .empty;
        try object.put(a, "calls", result.value.object.get("calls").?);
        if (full_path) |path| try object.put(a, "fullOutputPath", .{ .string = path });
        break :blk object;
    } });
    errdefer gpa.free(details);
    return .{ .content = content, .is_error = !ok, .details_json = details, .images = try images.toOwnedSlice(gpa) };
}
fn utf16Units(text: []const u8) u64 {
    var iterator = std.unicode.Wtf8View.initUnchecked(text).iterator();
    var units: u64 = 0;
    while (iterator.nextCodepoint()) |point| units += if (point > 0xffff) @as(u64, 2) else 1;
    return units;
}
fn utf8AtUnit(text: []const u8, limit: u64) usize {
    var iterator = std.unicode.Wtf8View.initUnchecked(text).iterator();
    var units: u64 = 0;
    while (iterator.nextCodepoint()) |point| {
        units += if (point > 0xffff) @as(u64, 2) else 1;
        if (units >= limit) return if (limit == 0) 0 else iterator.i;
    }
    return text.len;
}

test "native codemode agent adapter executes supplied nested pipeline and retains successful stores" {
    const Capture = struct {
        calls: usize = 0,
        persisted: bool = false,
        fn invoke(raw: ?*anyopaque, gpa: std.mem.Allocator, _: []const u8, name: []const u8, _: []const u8, _: ?*bool) !tools.ToolResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            try std.testing.expectEqualStrings("echo", name);
            return .{ .content = try gpa.dupe(u8, "nested answer"), .is_error = false };
        }
        fn append(raw: ?*anyopaque, writes: Value) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.persisted = std.mem.eql(u8, writes.object.get("set").?.object.get("answer").?.string, "nested answer");
        }
    };
    var capture: Capture = .{};
    var result = try execute(std.testing.allocator, std.testing.io, "const answer=await tools.echo({});store('answer',answer);text(answer);return 2;", .{ .context = &capture, .invoke = Capture.invoke, .entries = &.{.{ .name = "echo", .description = "echo" }}, .call_id = "outer", .append_context = &capture, .append_store = Capture.append }, null);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(!result.is_error and capture.persisted);
    try std.testing.expectEqual(@as(usize, 1), capture.calls);
    try std.testing.expect(std.mem.indexOf(u8, result.content, "==> text 1/2 <==\nnested answer") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.content, "==> text 2/2 <==\n2") != null);
}

test "native codemode agent adapter store replay follows selected branch and survives JSONL reload" {
    const gpa = std.testing.allocator;
    var session = try session_mod.Session.init(gpa, "store", ".");
    defer session.deinit();
    const first = try session.appendCustomEntry("codemode-store", "{\"set\":{\"shared\":1},\"delete\":[]}");
    const second = try session.appendCustomEntry("codemode-store", "{\"set\":{\"branch\":\"left\"},\"delete\":[]}");
    try session.setTip(first);
    _ = try session.appendCustomEntry("codemode-store", "{\"set\":{\"branch\":\"right\"},\"delete\":[\"shared\"]}");
    var right = try loadBranchStore(gpa, &session);
    defer right.deinit();
    try std.testing.expectEqualStrings("right", right.value.object.get("branch").?.string);
    try std.testing.expect(!right.value.object.contains("shared"));
    try session.setTip(second);
    var left = try loadBranchStore(gpa, &session);
    defer left.deinit();
    try std.testing.expectEqualStrings("left", left.value.object.get("branch").?.string);
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(left.value.object.get("shared").?));
    const bytes = try session.toJsonl(gpa);
    defer gpa.free(bytes);
    var loaded = try session_mod.Session.parseJsonl(gpa, bytes);
    defer loaded.deinit();
    // JSONL retains the complete append-only tree; select the same historical
    // tip explicitly before replaying that branch's stores.
    try loaded.setTip(second);
    var restored = try loadBranchStore(gpa, &loaded);
    defer restored.deinit();
    try std.testing.expectEqualStrings("left", restored.value.object.get("branch").?.string);
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(restored.value.object.get("shared").?));
}

test "native codemode agent adapter store replay matches original delete-set overlap array and invalid-entry captures" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/codemode-store-7fb.json"));
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |case| {
        var session = try session_mod.Session.init(gpa, "source-store", ".");
        defer session.deinit();
        for (case.object.get("entries").?.array.items) |entry| {
            const data = try json.stringify(gpa, entry.object.get("data").?);
            defer gpa.free(data);
            _ = try session.appendCustomEntry(entry.object.get("customType").?.string, data);
        }
        var actual = try loadBranchStore(gpa, &session);
        defer actual.deinit();
        try std.testing.expect(json.equal(case.object.get("result").?, actual.value));
    }
}

test "native codemode agent adapter allocation failures release nested workers formatted results and store ownership" {
    const Check = struct {
        fn invoke(_: ?*anyopaque, gpa: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8, _: ?*bool) !tools.ToolResult {
            return .{ .content = try gpa.dupe(u8, "owned answer"), .is_error = false };
        }
        fn run(gpa: std.mem.Allocator) !void {
            var result = execute(gpa, std.testing.io, "text(await tools.echo({}));store('answer',1);return 2;", .{ .context = null, .invoke = invoke, .entries = &.{.{ .name = "echo", .description = "owned" }}, .call_id = "outer" }, null) catch |cause| {
                var probe = std.testing.FailingAllocator.init(std.testing.allocator, .{});
                if (cause == error.WriteFailed and gpa.vtable == probe.allocator().vtable) {
                    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                    if (failing.has_induced_failure) return error.OutOfMemory;
                }
                return cause;
            };
            defer result.deinit(gpa);
            try std.testing.expect(!result.is_error);
        }
    };
    try @import("../test_support/allocation_shards.zig").check(Check.run);
}

test "native codemode agent adapter output budget saves full text in owned temporary file" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &path_buffer);
    const InvokeFn = struct {
        fn run(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8, _: ?*bool) !tools.ToolResult {
            return error.UnexpectedCodemodeCall;
        }
    };
    var result = try execute(gpa, io, "// @options: {\"max_output_tokens\":2}\ntext('abcdefghijklmnopqrstuvwxyz');", .{ .context = null, .invoke = InvokeFn.run, .entries = &.{}, .call_id = "budget", .output_root = path_buffer[0..count] }, null);
    defer result.deinit(gpa);
    try std.testing.expect(!result.is_error);
    try std.testing.expect(std.mem.indexOf(u8, result.content, "Warning: truncated output") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.content, "abcd") != null and std.mem.indexOf(u8, result.content, "wxyz") != null);
    var details = try json.Owned.parse(gpa, result.details_json.?);
    defer details.deinit();
    const path = try protocol.text(details.value, "fullOutputPath");
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024));
    defer gpa.free(bytes);
    try std.testing.expectEqualStrings("abcdefghijklmnopqrstuvwxyz", bytes);
}
