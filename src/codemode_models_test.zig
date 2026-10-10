test {
    _ = @import("mcp/codemode_models.zig");
}
const std = @import("std");
const sandbox = @import("mcp/codemode.zig");
const models = @import("mcp/codemode_models.zig");
const json = @import("mcp/protocol.zig").json;
// FailingAllocator's counters are intentionally plain fields; serialize them
// when the real sandbox and native model workers share an injected allocator.
const SynchronizedAllocator = struct {
    child_allocator: std.mem.Allocator,
    mutex: std.Io.Mutex = .init,
    fn allocator(self: *@This()) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(raw: *anyopaque, size: usize, alignment: std.mem.Alignment, address: usize) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.mutex.lockUncancelable(std.testing.io);
        defer self.mutex.unlock(std.testing.io);
        return self.child_allocator.rawAlloc(size, alignment, address);
    }
    fn resize(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, size: usize, address: usize) bool {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.mutex.lockUncancelable(std.testing.io);
        defer self.mutex.unlock(std.testing.io);
        return self.child_allocator.rawResize(memory, alignment, size, address);
    }
    fn remap(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, size: usize, address: usize) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.mutex.lockUncancelable(std.testing.io);
        defer self.mutex.unlock(std.testing.io);
        return self.child_allocator.rawRemap(memory, alignment, size, address);
    }
    fn free(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, address: usize) void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.mutex.lockUncancelable(std.testing.io);
        defer self.mutex.unlock(std.testing.io);
        self.child_allocator.rawFree(memory, alignment, address);
    }
};
const State = struct {
    source: json.Value,
    active: std.atomic.Value(usize) = .init(0),
    peak: std.atomic.Value(usize) = .init(0),
    publications: usize = 0,
    fn progress(raw: ?*anyopaque, _: json.Value) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.publications += 1;
    }
    fn invoke(raw: ?*anyopaque, gpa: std.mem.Allocator, operation: models.Operation, args: json.Value, _: ?*bool) !json.Owned {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var result = try json.Owned.empty(gpa);
        errdefer result.deinit();
        const a = result.arena.allocator();
        const items = args.array.items;
        if (operation == .classify or operation == .generateImages) {
            try std.testing.expectEqualStrings("PRIVATE_HEADER", json.get(json.get(items[0], "headers").?, "Authorization").?.string);
            try std.testing.expect(json.get(items[0], "baseUrl") == null);
            const count = self.active.fetchAdd(1, .acq_rel) + 1;
            defer _ = self.active.fetchSub(1, .acq_rel);
            _ = self.peak.fetchMax(count, .acq_rel);
            try std.testing.io.sleep(.fromMilliseconds(30), .awake);
            result.value = try json.clone(a, json.get(json.get(self.source, "rows").?.array.items[if (operation == .classify) @as(usize, 14) else 13], "result").?);
            if (operation == .classify) if (json.get(items[1], "state")) |state| {
                if (json.get(state, "reason")) |reason| try result.value.object.put(a, "stopReason", try json.clone(a, reason));
                if (json.get(state, "error")) |message| try result.value.object.put(a, "errorMessage", try json.clone(a, message));
                if (json.get(state, "markers")) |markers| if (markers == .bool and markers.bool) {
                    try result.value.object.put(a, "__pi_codemode_error", .{ .string = "ordinary model data" });
                    var nested: json.Value = .{ .object = .empty };
                    try nested.object.put(a, "nested", .{ .bool = true });
                    try result.value.object.put(a, "__pi_codemode_value", nested);
                };
            };
            return result;
        }
        result.value = if (operation == .getModelOfType) .null else .{ .array = .init(a) };
        for (json.get(self.source, "models").?.array.items) |model| {
            if (!std.mem.eql(u8, json.get(model, "type").?.string, items[0].string)) continue;
            if (items.len > 1 and items[1] == .string and !std.mem.eql(u8, json.get(model, "provider").?.string, items[1].string)) continue;
            if (operation == .getModelOfType) {
                if (std.mem.eql(u8, json.get(model, "id").?.string, items[2].string)) result.value = try json.clone(a, model);
            } else try result.value.array.append(try json.clone(a, model));
        }
        return result;
    }
};
test "native codemode models VM facade replays exact source results errors undefined and canonical resolution" {
    const gpa = std.testing.allocator;
    var captured = try json.Owned.parse(gpa, @embedFile("mcp/fixtures/codemode-models-original-6fb.json"));
    defer captured.deinit();
    var state: State = .{ .source = captured.value };
    for (json.get(captured.value, "rows").?.array.items) |row| {
        const args = try json.stringify(gpa, json.get(row, "args").?);
        defer gpa.free(args);
        const code = try std.fmt.allocPrint(gpa, "try{{const result=await {s}(...{s});text({{result:result??null,undefined:result===undefined}})}}catch(error){{text({{error:{{name:error.name,message:error.message}}}})}}", .{ json.get(row, "name").?.string, args });
        defer gpa.free(code);
        var result = try sandbox.execute(gpa, std.testing.io, &.{}, code, .{ .model_runtime = .{ .context = &state, .invoke = State.invoke, .docs_path = json.get(captured.value, "docsPath").?.string } });
        defer result.deinit();
        try std.testing.expect(json.get(result.value, "ok").?.bool);
        var actual = try json.Owned.parse(gpa, json.get(json.get(result.value, "output").?.array.items[0], "text").?.string);
        defer actual.deinit();
        if (json.get(row, "error")) |failure| {
            const error_ = json.get(actual.value, "error") orelse return error.ExpectedOriginalModelError;
            try std.testing.expect(json.equal(failure, error_));
            try std.testing.expectEqual(@as(usize, 0), json.get(result.value, "calls").?.array.items.len);
        } else {
            try std.testing.expect(json.equal(json.get(row, "result").?, json.get(actual.value, "result").?));
            try std.testing.expectEqual(json.get(row, "undefined").?.bool, json.get(actual.value, "undefined").?.bool);
        }
    }
}
test "native codemode models adapter matches complete upstream execution usage statuses notices and progress" {
    const gpa = std.testing.allocator;
    var captured = try json.Owned.parse(gpa, @embedFile("mcp/fixtures/codemode-models-original-6fb.json"));
    defer captured.deinit();
    var full = try json.Owned.parse(gpa, @embedFile("mcp/fixtures/codemode-models-metadata-original-6fb.json"));
    defer full.deinit();
    const adapter = @import("mcp/codemode_tool.zig");
    const Probe = struct {
        updates: std.ArrayList(json.Owned) = .empty,
        fn progress(raw: ?*anyopaque, bytes: []const u8) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var parsed = json.Owned.parse(std.testing.allocator, bytes) catch @panic("test progress allocation");
            self.updates.append(std.testing.allocator, parsed) catch {
                parsed.deinit();
                @panic("test progress append");
            };
        }
        fn call(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8, _: ?*bool) anyerror!@import("agent/tools.zig").ToolResult {
            return error.UnexpectedNestedTool;
        }
    };
    for (json.get(full.value, "rows").?.array.items) |row| {
        var state: State = .{ .source = captured.value };
        var probe: Probe = .{};
        defer {
            for (probe.updates.items) |*update| update.deinit();
            probe.updates.deinit(gpa);
        }
        var result = try adapter.execute(gpa, std.testing.io, json.get(row, "code").?.string, .{ .context = null, .invoke = Probe.call, .entries = &.{}, .call_id = "outer", .model_runtime = .{ .context = &state, .invoke = State.invoke }, .progress_context = &probe, .progress = Probe.progress }, null);
        defer result.deinit(gpa);
        try std.testing.expect(!result.is_error);
        const expected = json.get(row, "result").?;
        const content = json.get(expected, "content").?.array.items;
        const marker = "Output:\n";
        const offset = (std.mem.indexOf(u8, result.content, marker) orelse return error.MissingOutputHeader) + marker.len;
        try std.testing.expectEqual(@as(usize, 2), content.len);
        try std.testing.expectEqualStrings(json.get(content[1], "text").?.string, result.content[offset..]);
        const usage = result.usage orelse return error.MissingModelUsage;
        try std.testing.expectEqual(@as(u64, 1), usage.input);
        try std.testing.expectEqual(@as(u64, 3), usage.total_tokens);
        try std.testing.expectApproxEqAbs(@as(f64, 0.3), usage.cost.total, 0.000001);
        var details = try json.Owned.parse(gpa, result.details_json.?);
        defer details.deinit();
        for (json.get(details.value, "calls").?.array.items) |*call| _ = call.object.swapRemove("durationMs");
        var expected_details = try json.Owned.empty(gpa);
        defer expected_details.deinit();
        expected_details.value = try json.clone(expected_details.arena.allocator(), json.get(expected, "details").?);
        for (json.get(expected_details.value, "calls").?.array.items) |*call| _ = call.object.swapRemove("durationMs");
        try std.testing.expect(json.equal(expected_details.value, details.value));
        const updates = json.get(row, "updates").?.array.items;
        try std.testing.expectEqual(updates.len, probe.updates.items.len);
        for (updates, probe.updates.items) |source, *actual| {
            var snapshot = try json.Owned.empty(gpa);
            defer snapshot.deinit();
            snapshot.value = try json.clone(snapshot.arena.allocator(), json.get(source, "details").?);
            for (json.get(snapshot.value, "calls").?.array.items) |*call| _ = call.object.swapRemove("durationMs");
            for (json.get(actual.value, "calls").?.array.items) |*call| _ = call.object.swapRemove("durationMs");
            try std.testing.expect(json.equal(snapshot.value, actual.value));
        }
    }
}
test "native codemode models VM queues nine calls with source maximum four and owned call rows" {
    const gpa = std.testing.allocator;
    var captured = try json.Owned.parse(gpa, @embedFile("mcp/fixtures/codemode-models-original-6fb.json"));
    defer captured.deinit();
    var state: State = .{ .source = captured.value };
    const args = try json.stringify(gpa, json.get(json.get(captured.value, "rows").?.array.items[14], "args").?);
    defer gpa.free(args);
    const code = try std.fmt.allocPrint(gpa, "await Promise.all(Array.from({{length:9}},()=>models.classify(...{s})));text('done')", .{args});
    defer gpa.free(code);
    var result = try sandbox.execute(gpa, std.testing.io, &.{}, code, .{ .model_runtime = .{ .context = &state, .invoke = State.invoke }, .model_call_id = "outer", .progress_context = &state, .progress = State.progress });
    defer result.deinit();
    try std.testing.expect(json.get(result.value, "ok").?.bool);
    try std.testing.expectEqual(@as(usize, 4), state.peak.load(.acquire));
    try std.testing.expectEqual(@as(usize, 18), state.publications);
    const usage = json.get(result.value, "usage").?;
    try std.testing.expectEqual(@as(f64, 9), try json.asNumber(json.get(usage, "input").?));
    try std.testing.expectEqual(@as(f64, 27), try json.asNumber(json.get(usage, "totalTokens").?));
    try std.testing.expectApproxEqAbs(@as(f64, 2.7), try json.asNumber(json.get(json.get(usage, "cost").?, "total").?), 0.000001);
    const calls = json.get(result.value, "calls").?.array.items;
    try std.testing.expectEqual(@as(usize, 9), calls.len);
    for (calls) |call| {
        try std.testing.expectEqualStrings("models.classify", json.get(call, "name").?.string);
        try std.testing.expectEqualStrings("fixture/classify", json.get(call, "args").?.string);
        try std.testing.expectEqualStrings("ok", json.get(call, "status").?.string);
        try std.testing.expectApproxEqAbs(@as(f64, 0.3), try json.asNumber(json.get(call, "cost").?), 0.000001);
    }
}
test "native codemode models allocation failures release queued workers canonical metadata and accounting" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var synchronized: SynchronizedAllocator = .{ .child_allocator = gpa };
            const allocator = synchronized.allocator();
            var captured = try json.Owned.parse(allocator, @embedFile("mcp/fixtures/codemode-models-original-6fb.json"));
            defer captured.deinit();
            var state: State = .{ .source = captured.value };
            const args = try json.stringify(allocator, json.get(json.get(captured.value, "rows").?.array.items[14], "args").?);
            defer allocator.free(args);
            const code = try std.fmt.allocPrint(allocator, "text(await models.getModelOfType('image','fixture','missing'));await Promise.all(Array.from({{length:5}},()=>models.classify(...{s})));try{{await models.classify(null,{{}})}}catch(error){{text(error.message)}}", .{args});
            defer allocator.free(code);
            var result = try sandbox.execute(allocator, std.testing.io, &.{}, code, .{ .model_runtime = .{ .context = &state, .invoke = State.invoke } });
            defer result.deinit();
            try std.testing.expect(json.get(result.value, "ok").?.bool);
        }
    };
    try @import("test_support/sdk_allocation_shards.zig").check("codemode-models", Check.run, .{});
}
test "native codemode models structured tool fields named like protocol markers remain ordinary source data" {
    const gpa = std.testing.allocator;
    var captured = try json.Owned.parse(gpa, @embedFile("mcp/fixtures/codemode-structured-marker-original-6fb.json"));
    defer captured.deinit();
    const Probe = struct {
        fn call(raw: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8, _: ?*bool) !@import("agent/tools.zig").ToolResult {
            const value: *json.Value = @ptrCast(@alignCast(raw.?));
            const content = try allocator.dupe(u8, "shown");
            errdefer allocator.free(content);
            var fields: std.json.ObjectMap = .empty;
            defer fields.deinit(allocator);
            try fields.put(allocator, "structuredContent", value.*);
            return .{ .content = content, .is_error = false, .details_json = try json.stringify(allocator, .{ .object = fields }) };
        }
    };
    var value = json.get(captured.value, "value").?;
    var result = try @import("mcp/codemode_tool.zig").execute(gpa, std.testing.io, json.get(captured.value, "code").?.string, .{ .context = &value, .invoke = Probe.call, .entries = &.{.{ .name = "echo", .description = "Echo", .structured_result = true }}, .call_id = "outer" }, null);
    defer result.deinit(gpa);
    try std.testing.expect(!result.is_error);
    const marker = "Output:\n";
    const offset = (std.mem.indexOf(u8, result.content, marker) orelse return error.MissingOutputHeader) + marker.len;
    try std.testing.expectEqualStrings(json.get(json.get(json.get(captured.value, "result").?, "content").?.array.items[1], "text").?.string, result.content[offset..]);
}
