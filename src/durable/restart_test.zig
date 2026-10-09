const std = @import("std");
const backend = @import("backend/root.zig");
const model = @import("task_state.zig");
const session_mod = @import("session.zig");
const scheduling = @import("scheduler.zig");
const types = @import("types.zig");
const json = backend.json;
const Value = json.Value;
const gpa = std.testing.allocator;
const io = std.testing.io;
const Observer = struct {
    events: std.ArrayList(struct { phase: []const u8, reason: ?[]const u8 }) = .empty,
    fn observe(self: *@This(), record: Value, phase: []const u8) !void {
        const reason = json.get(record, "abortReason");
        try self.events.append(gpa, .{ .phase = phase, .reason = if (reason != null and reason.? == .string and std.mem.eql(u8, reason.?.string, "restart")) "restart" else null });
    }
    fn run(raw: ?*anyopaque, runtime: *scheduling.Runtime, record: Value, _: types.Context) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        try self.observe(record, "run");
        try runtime.commit(completed, null);
    }
    fn abort(raw: ?*anyopaque, runtime: *scheduling.Runtime, record: Value, _: types.Context) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        try self.observe(record, "abort");
        try runtime.commit(aborted, null);
    }
    fn completed(_: ?*anyopaque, tx: *session_mod.Transaction, _: Value) !?Value {
        return try model.outcomeState(tx.owned.arena.allocator(), "terminal", try model.makeOutcome(tx.owned.arena.allocator(), "completed", .{ .string = "result" }));
    }
    fn aborted(_: ?*anyopaque, tx: *session_mod.Transaction, _: Value) !?Value {
        var outcome: Value = .{ .object = .empty };
        try outcome.object.put(tx.owned.arena.allocator(), "status", .{ .string = "aborted" });
        return try model.outcomeState(tx.owned.arena.allocator(), "terminal", outcome);
    }
};
fn root(_: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
    return tx.createRootConversation();
}
const Add = struct {
    options: session_mod.TaskOptions,
    fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var checkpoint: Value = .{ .object = .empty };
        try checkpoint.object.put(tx.owned.arena.allocator(), "phase", .{ .string = "work" });
        return .{ .integer = @intCast(try tx.createTask("fixture.restart", 1, .null, checkpoint, self.options)) };
    }
};
fn add(current: *session_mod.Session, options: session_mod.TaskOptions) !u64 {
    var call: Add = .{ .options = options };
    var result = try current.commit(Add.apply, &call, .{}, .{});
    defer result.deinit();
    return json.asInteger(result.value.value);
}
fn view(record: Value, include_outcome: bool) !json.Owned {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const a = result.arena.allocator();
    result.value = .{ .object = .empty };
    inline for (.{ "abandonOnRestart", "abortRequested", "abortReason" }) |name|
        try result.value.object.put(a, name, try json.clone(a, json.get(record, name) orelse .null));
    if (include_outcome) try result.value.object.put(a, "outcome", try json.clone(a, try json.required(try json.required(record, "state"), "outcome")));
    return result;
}
test "durable.scheduler eba restart flags preserve Source five actual reservation and held-outcome traces" {
    var source = try json.Owned.parse(gpa, @embedFile("fixtures/durable-restart-eba.json"));
    defer source.deinit();
    for ((try json.required(source.value, "cases")).array.items) |row| {
        const mode = try json.asString(try json.required(row, "mode"));
        if (std.mem.eql(u8, mode, "upgrade-request-above-restart") or std.mem.eql(u8, mode, "fail-fast-request-wins")) continue;
        var memory = try backend.memory.Memory.init(gpa);
        defer memory.deinit();
        var current = session_mod.Session.init(gpa, io, .{ .memory = &memory });
        defer current.deinit();
        var observer: Observer = .{};
        defer observer.events.deinit(gpa);
        var scheduler = try scheduling.Scheduler.init(gpa, io, &current, .{});
        defer scheduler.deinit();
        try scheduler.register(.{ .name = "fixture.restart", .version = 1, .phases = &.{.{ .name = "work", .run = Observer.run }}, .abort = Observer.abort, .context = &observer });
        var created = try current.commit(root, null, .{}, .{});
        created.deinit();
        const options: session_mod.TaskOptions = .{ .conversationId = 1, .abandonOnRestart = !std.mem.eql(u8, mode, "existing-default") };
        var id: u64 = 0;
        var child: ?u64 = null;
        if (!std.mem.eql(u8, mode, "new-after-open")) id = try add(&current, options);
        if (std.mem.eql(u8, mode, "existing-requested") or std.mem.eql(u8, mode, "completing-holder")) {
            var original = (try current.storage.readTableRecord(gpa, .task, id)).?;
            defer original.deinit();
            const a = original.arena.allocator();
            var record = original.value;
            if (std.mem.eql(u8, mode, "existing-requested")) try record.object.put(a, "abortRequested", .{ .bool = true }) else {
                child = try add(&current, .{ .ownerTaskId = id });
                record = try model.withState(a, record, try model.outcomeState(a, "completing", try model.makeOutcome(a, "completed", .{ .string = "held" })));
            }
            var write: Value = .{ .object = .empty };
            try write.object.put(a, "type", .{ .string = "task" });
            try write.object.put(a, "value", record);
            var writes: Value = .{ .array = .init(a) };
            try writes.array.append(write);
            _ = try memory.commit(writes);
        }
        try scheduler.open();
        if (std.mem.eql(u8, mode, "new-after-open")) id = try add(&current, options);
        var before = (try current.storage.readTableRecord(gpa, .task, id)).?;
        defer before.deinit();
        var before_view = try view(before.value, false);
        defer before_view.deinit();
        try std.testing.expect(json.equal(try json.required(row, "before"), before_view.value));
        scheduler.enable();
        _ = try scheduler.driveRefilling();
        var after = (try current.storage.readTableRecord(gpa, .task, id)).?;
        defer after.deinit();
        var after_view = try view(after.value, true);
        defer after_view.deinit();
        if (!json.equal(try json.required(row, "after"), after_view.value)) {
            const encoded = try json.stringify(gpa, after_view.value);
            defer gpa.free(encoded);
            std.debug.print("Source restart case {s}: {s}\n", .{ mode, encoded });
            return error.SourceRestartTraceMismatch;
        }
        const encoded_events = try std.json.Stringify.valueAlloc(gpa, observer.events.items, .{});
        defer gpa.free(encoded_events);
        var actual_events = try json.Owned.parse(gpa, encoded_events);
        defer actual_events.deinit();
        try std.testing.expect(json.equal(try json.required(row, "events"), actual_events.value));
        try std.testing.expectEqual(@as(usize, 0), scheduler.reports.items.len);
        if (child) |child_id| {
            var child_record = (try current.storage.readTableRecord(gpa, .task, child_id)).?;
            defer child_record.deinit();
            const expected = try json.required(row, "child");
            try std.testing.expect(json.equal(try json.required(expected, "abortReason"), json.get(child_record.value, "abortReason") orelse .null));
            try std.testing.expect(json.equal(try json.required(expected, "outcome"), try json.required(try json.required(child_record.value, "state"), "outcome")));
        }
    }
}

const Fixture = struct {
    memory: backend.memory.Memory,
    current: session_mod.Session,
    scheduler: scheduling.Scheduler,
    observer: Observer = .{},
    fn init(self: *@This(), definitions: bool) !void {
        self.observer = .{};
        self.memory = try backend.memory.Memory.init(gpa);
        self.current = session_mod.Session.init(gpa, io, .{ .memory = &self.memory });
        self.scheduler = try scheduling.Scheduler.init(gpa, io, &self.current, .{});
        if (definitions) try self.scheduler.register(.{ .name = "fixture.restart", .version = 1, .phases = &.{.{ .name = "work", .run = block }}, .abort = Observer.abort, .context = &self.observer });
        var created = try self.current.commit(root, null, .{}, .{});
        created.deinit();
    }
    fn deinit(self: *@This()) void {
        self.scheduler.deinit();
        self.current.deinit();
        self.memory.deinit();
        self.observer.events.deinit(gpa);
    }
    fn block(_: ?*anyopaque, _: *scheduling.Runtime, _: Value, context: types.Context) !void {
        while (!context.aborted()) try io.sleep(.fromMilliseconds(1), .awake);
    }
    fn record(self: *@This(), id: u64) !json.Owned {
        return (try self.current.storage.readTableRecord(gpa, .task, id)).?;
    }
    fn replace(self: *@This(), next_record: Value) !void {
        var owned = try json.Owned.empty(gpa);
        defer owned.deinit();
        const a = owned.arena.allocator();
        var write: Value = .{ .object = .empty };
        try write.object.put(a, "type", .{ .string = "task" });
        try write.object.put(a, "value", try json.clone(a, next_record));
        owned.value = .{ .array = .init(a) };
        try owned.value.array.append(write);
        _ = try self.current.storage.commitAt(owned.value, null);
    }
};
fn compareOutcome(record: Value, expected: Value) !void {
    try std.testing.expect(json.equal(try json.required(expected, "abortReason"), json.get(record, "abortReason") orelse .null));
    try std.testing.expect(json.equal(try json.required(expected, "outcome"), try json.required(try json.required(record, "state"), "outcome")));
}
test "durable.scheduler eba explicit request upgrades inherited restart marks and missing descendants then orphan in Source order" {
    var source = try json.Owned.parse(gpa, @embedFile("fixtures/durable-restart-eba.json"));
    defer source.deinit();
    var expected: Value = undefined;
    for ((try json.required(source.value, "cases")).array.items) |row| if (std.mem.eql(u8, try json.asString(try json.required(row, "mode")), "upgrade-request-above-restart")) {
        expected = row;
        break;
    };
    var fixture: Fixture = undefined;
    try fixture.init(true);
    defer fixture.deinit();
    const top = try add(&fixture.current, .{ .conversationId = 1 });
    const middle = try add(&fixture.current, .{ .ownerTaskId = top, .abandonOnRestart = true });
    const leaf = try add(&fixture.current, .{ .ownerTaskId = middle });
    var original = try fixture.record(leaf);
    defer original.deinit();
    try original.value.object.put(original.arena.allocator(), "kind", .{ .string = "fixture.missing" });
    try fixture.replace(original.value);
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    const Driver = struct {
        scheduler: *scheduling.Scheduler,
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            _ = self.scheduler.driveRefilling() catch |err| {
                self.failure = err;
                return;
            };
        }
    };
    var driver: Driver = .{ .scheduler = &fixture.scheduler };
    const thread = try std.Thread.spawn(.{}, Driver.run, .{&driver});
    var joined = false;
    defer if (!joined) {
        fixture.scheduler.close();
        thread.join();
    };
    var observed = false;
    for (0..5000) |_| {
        var record = try fixture.record(leaf);
        defer record.deinit();
        const reason = json.get(record.value, "abortReason");
        if (reason != null and reason.? == .string and std.mem.eql(u8, reason.?.string, "restart")) {
            observed = true;
            break;
        }
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    try std.testing.expect(observed);
    var blocked = try fixture.record(leaf);
    defer blocked.deinit();
    try std.testing.expectEqualStrings(try json.asString(try json.required(try json.required(expected, "before"), "status")), try model.text(try model.field(blocked.value, "state"), "status"));
    try fixture.scheduler.abort(top);
    thread.join();
    joined = true;
    if (driver.failure) |err| return err;
    for ([_]u64{ leaf, middle, top }, (try json.required(expected, "after")).array.items) |id, result| {
        var record = try fixture.record(id);
        defer record.deinit();
        try compareOutcome(record.value, result);
    }
    try std.testing.expectEqual(@as(usize, 0), fixture.scheduler.reports.items.len);
}
test "durable.scheduler eba failFast request wins over restart propagation in the same reconciliation pass" {
    var source = try json.Owned.parse(gpa, @embedFile("fixtures/durable-restart-eba.json"));
    defer source.deinit();
    var expected: Value = undefined;
    for ((try json.required(source.value, "cases")).array.items) |row| if (std.mem.eql(u8, try json.asString(try json.required(row, "mode")), "fail-fast-request-wins")) {
        expected = row;
        break;
    };
    var fixture: Fixture = undefined;
    try fixture.init(false);
    defer fixture.deinit();
    const parent = try add(&fixture.current, .{ .conversationId = 1 });
    const failed = try add(&fixture.current, .{ .ownerTaskId = parent });
    const child = try add(&fixture.current, .{ .ownerTaskId = parent });
    var owner = try fixture.record(parent);
    defer owner.deinit();
    const a = owner.arena.allocator();
    var waiting = try model.checkpointState(a, "waiting", try model.field(try model.field(owner.value, "state"), "checkpoint"));
    var on: Value = .{ .array = .init(a) };
    try on.array.append(.{ .integer = @intCast(failed) });
    try on.array.append(.{ .integer = @intCast(child) });
    try waiting.object.put(a, "on", on);
    try waiting.object.put(a, "policy", .{ .string = "failFast" });
    try fixture.replace(try model.withState(a, try model.abortMark(a, owner.value, .restart), waiting));
    var failed_record = try fixture.record(failed);
    defer failed_record.deinit();
    try fixture.replace(try model.withState(a, failed_record.value, try model.outcomeState(a, "terminal", try model.makeOutcome(a, "failed", .{ .string = "failed" }))));
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    _ = try fixture.scheduler.driveRefilling();
    var record = try fixture.record(child);
    defer record.deinit();
    try compareOutcome(record.value, try json.required(expected, "after"));
    try std.testing.expectEqual(@as(usize, 0), fixture.scheduler.reports.items.len);
}

test "durable.scheduler eba abandoned admission and its first mark unwind every host allocation" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn exercise(allocator: std.mem.Allocator) !void {
            var memory = try backend.memory.Memory.init(allocator);
            defer memory.deinit();
            var current = session_mod.Session.init(allocator, io, .{ .memory = &memory });
            defer current.deinit();
            var scheduler = try scheduling.Scheduler.init(allocator, io, &current, .{});
            defer scheduler.deinit();
            var created = try current.commit(root, null, .{}, .{});
            created.deinit();
            _ = try add(&current, .{ .conversationId = 1, .abandonOnRestart = true });
            try scheduler.open();
            scheduler.enable();
            // One bounded reservation pass commits marks without entering a
            // phase. A missing definition retains this restart-marked task.
            try std.testing.expectEqual(@as(usize, 0), try scheduler.drive());
            var record = (try current.storage.readTableRecord(allocator, .task, 2)).?;
            defer record.deinit();
            try std.testing.expectEqualStrings("restart", try model.text(record.value, "abortReason"));
            try std.testing.expectEqual(model.Status.pending, try model.status(record.value));
        }
    }.exercise, .{});
}
