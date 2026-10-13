const std = @import("std");
const runs = @import("mcp/codemode_run.zig");
const json = @import("mcp/protocol.zig").json;
const started_at: f64 = 1768471200000;
const Probe = struct {
    gpa: std.mem.Allocator,
    data: json.Owned,
    seq: f64 = 0,
    reject: bool = false,
    backwards: bool = false,
    reorder: bool = false,
    first_id: ?u64 = null,
    fn init(gpa: std.mem.Allocator) !Probe {
        var data = try json.Owned.empty(gpa);
        errdefer data.deinit();
        const a = data.arena.allocator();
        data.value = .{ .object = .empty };
        inline for (.{ "calls", "events", "idles" }) |name| try data.value.object.put(a, name, .{ .array = .init(a) });
        return .{ .gpa = gpa, .data = data };
    }
    fn event(self: *Probe, value: []const u8) !void {
        const a = self.data.arena.allocator();
        try self.data.value.object.getPtr("events").?.array.append(.{ .string = try a.dupe(u8, value) });
    }
    fn started(raw: ?*anyopaque, _: *runs.Run, fingerprint: []const u8) !void {
        const self: *Probe = @ptrCast(@alignCast(raw.?));
        try std.testing.expect(std.mem.startsWith(u8, fingerprint, "quickjs-native "));
        try self.event("started");
    }
    fn call(raw: ?*anyopaque, run: *runs.Run, value: runs.Call) !void {
        const self: *Probe = @ptrCast(@alignCast(raw.?));
        const a = self.data.arena.allocator();
        var record: json.Value = .{ .object = .empty };
        try record.object.put(a, "id", .{ .float = @floatFromInt(value.id) });
        try record.object.put(a, "target", .{ .string = @tagName(value.target) });
        try record.object.put(a, "name", .{ .string = try a.dupe(u8, value.name) });
        if (value.args) |args| try record.object.put(a, "args", try json.clone(a, args));
        try self.data.value.object.getPtr("calls").?.array.append(record);
        try self.event(try std.fmt.allocPrint(a, "call {d}", .{value.id}));
        if (self.reorder) {
            if (self.first_id) |first| {
                try run.deliver(2, started_at + 2000, value.id, .{ .success = "\"b\"" });
                try run.deliver(1, started_at + 1000, first, .{ .success = "\"a\"" });
            } else self.first_id = value.id;
            return;
        }
        self.seq += 1;
        const payload = if (value.args) |args| try json.stringify(self.gpa, args) else null;
        defer if (payload) |bytes| self.gpa.free(bytes);
        try run.deliver(self.seq, if (self.backwards) started_at - self.seq else started_at + 1000 * self.seq, value.id, if (self.reject) .{ .failure = .{ .message = "original failure", .properties = "{\"extra\":7,\"message\":\"ignored\",\"name\":\"ignored\",\"stack\":\"ignored\"}" } } else .{ .success = payload });
    }
    fn idle(raw: ?*anyopaque, _: *runs.Run, seq: f64, issued: f64) !void {
        const self: *Probe = @ptrCast(@alignCast(raw.?));
        const a = self.data.arena.allocator();
        var values: json.Value = .{ .array = .init(a) };
        try values.array.append(.{ .float = seq });
        try values.array.append(.{ .float = issued });
        try self.data.value.object.getPtr("idles").?.array.append(values);
        try self.event(try std.fmt.allocPrint(a, "idle {d}", .{seq}));
    }
};
const random_clock = "const values = [Date.now(), performance.now(), Math.random(), Math.random(), new Date().toISOString()]; const first = await tools.echo(values); text(JSON.stringify([Date.now(), performance.now(), Math.random()])); return await tools.echo(first.concat(Math.random()));";
pub const programs = [_][]const u8{
    random_clock,
    random_clock,
    random_clock,
    "return [Math.random(), Math.random()]",
    "return [Math.random(), Math.random()]",
    "return [new Date(0).getHours(), new Date(0).getTimezoneOffset(), typeof WeakRef, typeof FinalizationRegistry]",
    "const before=Date.now(); await tools.echo(1); return [before, Date.now(), performance.now()]",
    "const order=[]; await Promise.all([tools.wait(\"a\").then(()=>order.push([\"a\",Date.now()])),tools.wait(\"b\").then(()=>order.push([\"b\",Date.now()]))]); return order",
    "return await math.echo(1, {x:2})",
    "try { await tools.echo(1); } catch (error) { return [error.name,error.message,error.extra,Object.keys(error)] }",
    "const value=load(\"original\"); value.nested.push(3); store(\"out\", value); store(\"original\",undefined); return load(\"out\")",
    "text(\"first\"); return 7",
    "text(\"before\"); exit(); text(\"after\"); return 9",
    "await new Promise(()=>{})",
    "await null; await null; return await tools.echo(\"after\")",
    "throw Error(\"actual error\")",
};

test "native CodeMode controlled run preserves all sixteen actual Source calls events idles and complete replay results" {
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("mcp/fixtures/codemode-run-045-source.json"));
    defer source.deinit();
    const rows = source.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(programs.len, rows.len);
    var initial_store = try json.Owned.parse(std.testing.allocator, "{\"original\":{\"nested\":[1,2]}}");
    defer initial_store.deinit();
    for (rows, programs, 0..) |row, program, index| {
        var probe = try Probe.init(std.testing.allocator);
        defer probe.data.deinit();
        probe.reject = index == 9;
        probe.backwards = index == 6;
        probe.reorder = index == 7;
        const run = try runs.Run.create(std.testing.allocator, std.testing.io, program, .{ .started_at = started_at, .seed = if (index == 2) 2 else if (index == 3) 0 else if (index == 4) 4294967295 else 1, .tools = &.{ .{ .name = "echo" }, .{ .name = "wait" } }, .globals = &.{.{ .name = "math.echo", .spread = true }}, .store = initial_store.value, .interrupt_budget = 50000, .observer = .{ .context = &probe, .started = Probe.started, .call = Probe.call, .idle = Probe.idle } });
        defer run.deinit();
        const begin = std.Io.Clock.awake.now(std.testing.io).toMilliseconds();
        try run.begin();
        try std.testing.expect(run.finished);
        const elapsed = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() - begin;
        var actual = try json.Owned.empty(std.testing.allocator);
        defer actual.deinit();
        actual.value = try json.clone(actual.arena.allocator(), run.core.result.value);
        // Only wall-clock call duration differs across independent executions.
        // Validate the actual measurement before comparing the replay fields;
        // retain the full native result in Run and the raw upstream capture.
        for (actual.value.object.getPtr("calls").?.array.items) |*call| {
            const measured = call.object.get("durationMs") orelse return error.MissingActualDuration;
            const duration = try json.asNumber(measured);
            try std.testing.expect(std.math.isFinite(duration) and duration >= 0 and duration == @floor(duration) and duration <= @as(f64, @floatFromInt(elapsed + 1)));
            _ = call.object.orderedRemove("durationMs");
        }
        const expected = row.object.get("result").?;
        if (!json.equal(expected, actual.value)) {
            const bytes = try json.stringify(std.testing.allocator, actual.value);
            defer std.testing.allocator.free(bytes);
            std.debug.print("Controlled CodeMode Source row {d} {s} actual={s}\n", .{ index, row.object.get("name").?.string, bytes });
        }
        try std.testing.expect(json.equal(expected, actual.value));
        inline for (.{ "calls", "events", "idles" }) |name| {
            const observed = probe.data.value.object.get(name).?;
            if (!json.equal(row.object.get(name).?, observed)) std.debug.print("Controlled CodeMode Source row {d} differs in {s}\n", .{ index, name });
            try std.testing.expect(json.equal(row.object.get(name).?, observed));
        }
        try run.deliver(std.math.nan(f64), std.math.nan(f64), 0, .{ .success = "not JSON" });
    }
}

test "native CodeMode controlled run inventory records every actual compiled test" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(bytes);
    std.debug.print("CODEMODE_RUN_TEST_INVENTORY={s}\n", .{bytes});
}

test "native CodeMode controlled run releases every failed owner allocation through create call answer completion and teardown" {
    const Lifecycle = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            var probe = try Probe.init(std.testing.allocator);
            defer probe.data.deinit();
            const run = try runs.Run.create(gpa, std.testing.io, "store('value',await tools.echo({value:7})); return load('value')", .{ .started_at = started_at, .seed = 1, .tools = &.{.{ .name = "echo" }}, .observer = .{ .context = &probe, .started = Probe.started, .call = Probe.call, .idle = Probe.idle } });
            defer run.deinit();
            try run.begin();
            try std.testing.expect(run.finished and run.core.result.value.object.get("ok").?.bool);
            try std.testing.expectEqual(@as(f64, 7), try json.asNumber(run.core.result.value.object.get("value").?.object.get("value").?));
        }
    };
    try @import("test_support/exhaustive_allocation_shards.zig").check(.codemode, "codemode-controlled-run", Lifecycle.exercise, .{});
}

test "native CodeMode controlled run retains all eleven actual latest properties abort and callback outcomes" {
    const Edge = struct {
        row: json.Value,
        events: json.Owned,
        fn event(self: *@This(), value: json.Value) !void {
            try self.events.value.array.append(try json.clone(self.events.arena.allocator(), value));
        }
        fn started(raw: ?*anyopaque, run: *runs.Run, _: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try self.event(.{ .string = "started" });
            if (std.mem.eql(u8, self.row.object.get("mode").?.string, "throw-started")) try run.failHost("started original");
        }
        fn call(raw: ?*anyopaque, run: *runs.Run, value: runs.Call) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const a = self.events.arena.allocator();
            try self.event(.{ .string = try std.fmt.allocPrint(a, "call {d}", .{value.id}) });
            const mode = self.row.object.get("mode").?.string;
            if (std.mem.eql(u8, mode, "throw-call")) return run.failHost("call original");
            if (std.mem.eql(u8, mode, "throw-idle") or std.mem.eql(u8, mode, "abort-gap")) return;
            const payload = self.row.object.get("serialized").?.string;
            const success = std.mem.eql(u8, mode, "success");
            try run.deliver(1, started_at + 1, value.id, if (success) .{ .success = payload } else .{ .failure = .{ .message = "actual failure", .properties = payload } });
        }
        fn idle(raw: ?*anyopaque, run: *runs.Run, seq: f64, issued: f64) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var row: json.Value = .{ .array = .init(self.events.arena.allocator()) };
            try row.array.append(.{ .string = "idle" });
            try row.array.append(.{ .float = seq });
            try row.array.append(.{ .float = issued });
            try self.event(row);
            if (std.mem.eql(u8, self.row.object.get("mode").?.string, "throw-idle")) try run.failHost("idle original");
        }
    };
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("mcp/fixtures/codemode-run-ee409-edges-source.json"));
    defer source.deinit();
    const rows = source.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 11), rows.len);
    for (rows) |row| {
        var events = try json.Owned.empty(std.testing.allocator);
        events.value = .{ .array = .init(events.arena.allocator()) };
        var edge: Edge = .{ .row = row, .events = events };
        defer edge.events.deinit();
        const run = try runs.Run.create(std.testing.allocator, std.testing.io, row.object.get("code").?.string, .{ .started_at = started_at, .seed = 1, .tools = &.{ .{ .name = "echo" }, .{ .name = "wait" } }, .observer = .{ .context = &edge, .started = Edge.started, .call = Edge.call, .idle = Edge.idle } });
        defer run.deinit();
        const before = std.Io.Clock.awake.now(std.testing.io).toMilliseconds();
        try run.begin();
        if (std.mem.eql(u8, row.object.get("mode").?.string, "abort-gap")) {
            try std.testing.expect(!run.finished);
            try run.deliver(2, started_at + 2000, 2, .{ .success = "\"second\"" });
            try run.abortWithMessage("actual gap abort");
        }
        try std.testing.expect(run.finished);
        const elapsed = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() - before;
        var expected = try json.Owned.empty(std.testing.allocator);
        defer expected.deinit();
        expected.value = try json.clone(expected.arena.allocator(), row.object.get("result").?);
        var actual = try json.Owned.empty(std.testing.allocator);
        defer actual.deinit();
        actual.value = try json.clone(actual.arena.allocator(), run.core.result.value);
        for (expected.value.object.getPtr("calls").?.array.items) |*call| {
            const measured = try json.asNumber(call.object.get("durationMs").?);
            try std.testing.expect(std.math.isFinite(measured) and measured >= 0 and measured <= try json.asNumber(row.object.get("elapsedMs").?));
            _ = call.object.orderedRemove("durationMs");
        }
        for (actual.value.object.getPtr("calls").?.array.items) |*call| {
            const measured = try json.asNumber(call.object.get("durationMs").?);
            try std.testing.expect(std.math.isFinite(measured) and measured >= 0 and measured == @floor(measured) and measured <= @as(f64, @floatFromInt(elapsed + 1)));
            _ = call.object.orderedRemove("durationMs");
        }
        if (!json.equal(expected.value, actual.value)) {
            const bytes = try json.stringify(std.testing.allocator, actual.value);
            defer std.testing.allocator.free(bytes);
            std.debug.print("Latest controlled edge {s} actual={s}\n", .{ row.object.get("name").?.string, bytes });
        }
        try std.testing.expect(json.equal(expected.value, actual.value));
        try std.testing.expect(json.equal(row.object.get("events").?, edge.events.value));
    }
}

test "native CodeMode controlled run retains all ten actual latest declared aliases and admission failures" {
    const Alias = struct {
        fn idle(raw: ?*anyopaque, _: *runs.Run, seq: f64, issued: f64) !void {
            const probe: *Probe = @ptrCast(@alignCast(raw.?));
            const a = probe.data.arena.allocator();
            var event: json.Value = .{ .array = .init(a) };
            try event.array.append(.{ .string = "idle" });
            try event.array.append(.{ .float = seq });
            try event.array.append(.{ .float = issued });
            try probe.data.value.object.getPtr("events").?.array.append(event);
        }
    };
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("mcp/fixtures/codemode-run-ee409-alias-source.json"));
    defer source.deinit();
    const rows = source.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 10), rows.len);
    for (rows) |row| {
        var probe = try Probe.init(std.testing.allocator);
        defer probe.data.deinit();
        const declared = row.object.get("tools").?.array.items;
        const tools = try std.testing.allocator.alloc(runs.Tool, declared.len);
        defer std.testing.allocator.free(tools);
        for (declared, tools) |tool, *owned| owned.* = .{ .name = tool.object.get("name").?.string, .js_name = if (tool.object.get("jsName")) |name| name.string else null, .description = if (tool.object.get("description")) |description| description.string else "" };
        const options: runs.Options = .{ .started_at = started_at, .seed = 1, .tools = tools, .observer = .{ .context = &probe, .started = Probe.started, .call = Probe.call, .idle = Alias.idle } };
        if (row.object.get("admissionFailure")) |failure| {
            const cause = if (std.mem.eql(u8, failure.object.get("message").?.string, "Tool names must be unique")) error.DuplicateToolName else error.DuplicateToolScriptName;
            try std.testing.expectError(cause, runs.Run.create(std.testing.allocator, std.testing.io, row.object.get("code").?.string, options));
            try std.testing.expectEqual(@as(usize, 0), probe.data.value.object.get("events").?.array.items.len);
            continue;
        }
        const run = try runs.Run.create(std.testing.allocator, std.testing.io, row.object.get("code").?.string, options);
        defer run.deinit();
        const before = std.Io.Clock.awake.now(std.testing.io).toMilliseconds();
        try run.begin();
        try std.testing.expect(run.finished);
        const elapsed = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() - before;
        var expected = try json.Owned.empty(std.testing.allocator);
        defer expected.deinit();
        expected.value = try json.clone(expected.arena.allocator(), row.object.get("result").?);
        var actual = try json.Owned.empty(std.testing.allocator);
        defer actual.deinit();
        actual.value = try json.clone(actual.arena.allocator(), run.core.result.value);
        for (expected.value.object.getPtr("calls").?.array.items) |*call| {
            const measured = try json.asNumber(call.object.get("durationMs").?);
            try std.testing.expect(std.math.isFinite(measured) and measured >= 0 and measured <= try json.asNumber(row.object.get("elapsedMs").?));
            _ = call.object.orderedRemove("durationMs");
        }
        for (actual.value.object.getPtr("calls").?.array.items) |*call| {
            const measured = try json.asNumber(call.object.get("durationMs").?);
            try std.testing.expect(std.math.isFinite(measured) and measured >= 0 and measured == @floor(measured) and measured <= @as(f64, @floatFromInt(elapsed + 1)));
            _ = call.object.orderedRemove("durationMs");
        }
        if (!json.equal(expected.value, actual.value)) {
            const bytes = try json.stringify(std.testing.allocator, actual.value);
            defer std.testing.allocator.free(bytes);
            std.debug.print("Latest declared alias {s} actual={s}\n", .{ row.object.get("name").?.string, bytes });
        }
        try std.testing.expect(json.equal(expected.value, actual.value));
        inline for (.{ "calls", "events" }) |key| try std.testing.expect(json.equal(row.object.get(key).?, probe.data.value.object.get(key).?));
    }
}
