const std = @import("std");
const read = @import("tool_read.zig");
const env_module = @import("execution_env.zig");
const values = @import("tool_types.zig");
const json = @import("backend/json.zig");
fn text(value: json.Value, name: []const u8) ![]const u8 {
    return json.asString(try json.required(value, name));
}
fn field(a: std.mem.Allocator, object: *json.Value, name: []const u8, value: json.Value) !void {
    try object.object.put(a, name, value);
}
fn encodedResult(gpa: std.mem.Allocator, result: *const values.ToolResult) !json.Owned {
    var owned = try json.Owned.empty(gpa);
    errdefer owned.deinit();
    const a = owned.arena.allocator();
    owned.value = .{ .object = .empty };
    var output: json.Value = .{ .array = .init(a) };
    if (result.text) |content| if (content.len != 0) {
        var block: json.Value = .{ .object = .empty };
        try field(a, &block, "type", .{ .string = "text" });
        try field(a, &block, "text", .{ .string = content });
        try output.array.append(block);
    };
    for (result.images.items) |image| {
        var block: json.Value = .{ .object = .empty };
        try field(a, &block, "type", .{ .string = "image" });
        try field(a, &block, "data", .{ .string = image.data });
        try field(a, &block, "mimeType", .{ .string = image.mimeType });
        try output.array.append(block);
    }
    try field(a, &owned.value, "output", output);
    if (result.isError) try field(a, &owned.value, "isError", .{ .bool = true });
    var diagnostics: json.Value = .{ .array = .init(a) };
    for (result.diagnostics.items) |item| {
        var row: json.Value = .{ .object = .empty };
        try field(a, &row, "severity", .{ .string = if (item.severity == .err) "error" else @tagName(item.severity) });
        if (item.code) |code| try field(a, &row, "code", .{ .string = code });
        try field(a, &row, "message", .{ .string = item.message });
        try diagnostics.array.append(row);
    }
    try field(a, &owned.value, "diagnostics", diagnostics);
    return owned;
}
const Preparation = struct {
    source: json.Value,
    gif: []const u8,
    empty: bool,
    calls: usize = 0,
    fn prepare(raw: ?*anyopaque, gpa: std.mem.Allocator, bytes: []const u8, mime: []const u8, limits: read.images.Limits) !?read.images.Prepared {
        const self: *Preparation = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        const expected = try json.required(self.source, "bytes");
        try std.testing.expectEqual(expected.array.items.len, bytes.len);
        for (bytes, expected.array.items) |byte, value| try std.testing.expectEqual(try json.asInteger(value), byte);
        try std.testing.expectEqualStrings(try text(self.source, "mimeType"), mime);
        const source_limits = try json.required(self.source, "limits");
        try std.testing.expectEqual(try json.asNumber(try json.required(source_limits, "maxWidth")), limits.maxWidth);
        try std.testing.expectEqual(try json.asNumber(try json.required(source_limits, "maxHeight")), limits.maxHeight);
        try std.testing.expectEqual(try json.asNumber(try json.required(source_limits, "maxBytes")), limits.maxBytes);
        if (self.empty) return null;
        const data = try gpa.alloc(u8, std.base64.standard.Encoder.calcSize(self.gif.len));
        errdefer gpa.free(data);
        _ = std.base64.standard.Encoder.encode(data, self.gif);
        const output_mime = try gpa.dupe(u8, "image/gif");
        errdefer gpa.free(output_mime);
        return .{ .data = data, .mimeType = output_mime, .convertedFrom = try gpa.dupe(u8, "image/png"), .resized = .{ .from = .{ .width = 8, .height = 6 }, .to = .{ .width = 4, .height = 3 } } };
    }
};
const Mutation = struct {
    writer: std.Io.File,
    size: u64,
    always: bool,
    calls: usize = 0,
    fn resolve(raw: ?*anyopaque, _: @import("types.zig").Context) !read.images.Model {
        const self: *Mutation = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        if (self.always or self.calls == 1) {
            try self.writer.writePositionalAll(std.testing.io, &.{0}, self.size);
            self.size += 1;
        }
        return .{};
    }
};
test "durable read images42a matches actual Source header limits vision arbitrary processor inputs and image-only output" {
    const gpa = std.testing.allocator;
    var source = try json.Owned.parse(gpa, @embedFile("fixtures/durable-read-images42a.json"));
    defer source.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixtures = try json.required(source.value, "fixtures");
    var gif: []u8 = &.{};
    defer if (gif.len != 0) gpa.free(gif);
    for (fixtures.array.items) |fixture| {
        const bytes_json = try json.required(fixture, "bytes");
        const bytes = try gpa.alloc(u8, bytes_json.array.items.len);
        defer gpa.free(bytes);
        for (bytes, bytes_json.array.items) |*byte, value| byte.* = @intCast(try json.asInteger(value));
        const name = try text(fixture, "name");
        try temporary.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = bytes });
        if (std.mem.eql(u8, name, "tiny.gif")) gif = try gpa.dupe(u8, bytes);
    }
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_size = try temporary.dir.realPath(std.testing.io, &root_buffer);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    var env = try env_module.ExecutionEnv.init(gpa, std.testing.io, .{ .cwd = root_buffer[0..root_size], .environ = &environment });
    defer env.deinit();
    const calls = try json.required(source.value, "calls");
    const cases = try json.required(source.value, "cases");
    for (cases.array.items) |case| {
        var options: read.Options = .{};
        var mutation: ?Mutation = null;
        defer if (mutation) |value| value.writer.close(std.testing.io);
        if (json.get(case, "mutation")) |policy| {
            mutation = .{ .writer = try temporary.dir.openFile(std.testing.io, try text(case, "path"), .{ .mode = .read_write }), .size = gif.len, .always = std.mem.eql(u8, try json.asString(policy), "twice") };
            options.model_context = &mutation.?;
            options.resolve_model = Mutation.resolve;
        }
        if (json.get(case, "resize")) |resize| {
            if (json.get(resize, "maxWidth")) |width| options.model.limits.maxWidth = try json.asNumber(width);
            if (json.get(resize, "maxHeight")) |height| options.model.limits.maxHeight = try json.asNumber(height);
            if (json.get(resize, "maxBytes")) |bytes| options.model.limits.maxBytes = try json.asNumber(bytes);
        }
        if (json.get(case, "input")) |input| {
            options.model.vision = false;
            for (input.array.items) |kind| if (std.mem.eql(u8, try json.asString(kind), "image")) {
                options.model.vision = true;
                break;
            };
        }
        var preparation: Preparation = undefined;
        if (json.get(case, "processor")) |processor| {
            const name = try text(case, "name");
            var expected_call: ?json.Value = null;
            for (calls.array.items) |call| if (std.mem.eql(u8, try text(call, "name"), name)) {
                expected_call = call;
                break;
            };
            preparation = .{ .source = expected_call orelse return error.MissingSourceProcessorCall, .gif = gif, .empty = std.mem.eql(u8, try json.asString(processor), "undefined") };
            options.images = .{ .context = &preparation, .prepare = Preparation.prepare };
        }
        var result = try read.executeWithOptions(&env, .{ .path = try text(case, "path") }, options, .{});
        defer result.deinit(gpa);
        if (mutation) |value| try std.testing.expectEqual(try json.asInteger(try json.required(case, "modelCalls")), value.calls);
        if (json.get(case, "error")) |expected_error| {
            try std.testing.expect(result == .failure);
            try std.testing.expectEqualStrings(try text(expected_error, "message"), result.failure.message);
            continue;
        }
        if (result != .value) {
            std.debug.print("Image Source case {s} failed: {s}\n", .{ try text(case, "name"), result.failure.message });
            return error.UnexpectedImageReadFailure;
        }
        var actual = try encodedResult(gpa, &result.value);
        defer actual.deinit();
        const expected = try json.required(case, "result");
        if (!json.equal(actual.value, expected)) {
            const actual_text = try json.stringify(gpa, actual.value);
            defer gpa.free(actual_text);
            const expected_text = try json.stringify(gpa, expected);
            defer gpa.free(expected_text);
            std.debug.print("Image Source case {s}\nactual {s}\nexpected {s}\n", .{ try text(case, "name"), actual_text, expected_text });
            return error.ImageSourceMismatch;
        }
        if (options.images != null) try std.testing.expectEqual(@as(usize, 1), preparation.calls);
    }
}

test "durable read images42a header and processor outputs release every failed host allocation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const gif_base64 = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7";
    const gif = try std.testing.allocator.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(gif_base64));
    defer std.testing.allocator.free(gif);
    try std.base64.standard.Decoder.decode(gif, gif_base64);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "a.gif", .data = gif });
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_size = try temporary.dir.realPath(std.testing.io, &root_buffer);
    const Probe = struct {
        fn prepare(_: ?*anyopaque, gpa: std.mem.Allocator, bytes: []const u8, _: []const u8, _: read.images.Limits) !?read.images.Prepared {
            const data = try gpa.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
            errdefer gpa.free(data);
            _ = std.base64.standard.Encoder.encode(data, bytes);
            const mime = try gpa.dupe(u8, "image/gif");
            errdefer gpa.free(mime);
            return .{ .data = data, .mimeType = mime, .convertedFrom = try gpa.dupe(u8, "image/png"), .resized = .{ .from = .{ .width = 2, .height = 2 }, .to = .{ .width = 1, .height = 1 } } };
        }
        fn run(gpa: std.mem.Allocator, root: []const u8) !void {
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            var env = try env_module.ExecutionEnv.init(gpa, std.testing.io, .{ .cwd = root, .environ = &environment });
            defer env.deinit();
            for ([_]read.Options{ .{}, .{ .images = .{ .prepare = prepare }, .model = .{ .vision = false } }, .{ .model = .{ .limits = .{ .maxBytes = 1 } } } }, 0..) |options, index| {
                var result = try read.executeWithOptions(&env, .{ .path = "a.gif" }, options, .{});
                defer result.deinit(gpa);
                if (result == .failure) {
                    const allocator: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                    if (allocator.has_induced_failure) return error.OutOfMemory;
                    return error.ImageAllocationBaselineFailed;
                }
                try std.testing.expectEqual(@as(usize, if (index == 2) 0 else 1), result.value.images.items.len);
                try std.testing.expectEqual(index == 2, result.value.isError);
            }
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{root_buffer[0..root_size]});
}
