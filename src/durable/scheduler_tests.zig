const std = @import("std");
const backend = @import("backend/root.zig");
const json = backend.json;
const model = @import("task_state.zig");
const session_mod = @import("session.zig");
const scheduler_mod = @import("scheduler.zig");
const types = @import("types.zig");
const Value = json.Value;
const gpa = std.testing.allocator;
const io = std.testing.io;
const Fixture = struct {
    store: backend.memory.Memory,
    session: session_mod.Session,
    scheduler: scheduler_mod.Scheduler,
    fn init(self: *@This()) !void {
        self.store = try backend.memory.Memory.init(gpa);
        self.session = session_mod.Session.init(gpa, io, .{ .memory = &self.store });
        self.scheduler = try scheduler_mod.Scheduler.init(gpa, io, &self.session, .{});
        var result = try self.session.commit(root, null, .{}, .{});
        result.deinit();
    }
    fn deinit(self: *@This()) void {
        self.scheduler.deinit();
        self.session.deinit();
        self.store.deinit();
    }
    fn add(self: *@This(), name: []const u8, state: []const u8, options: session_mod.TaskOptions) !u64 {
        var checkpoint = try json.Owned.parse(gpa, state);
        defer checkpoint.deinit();
        var call: Add = .{ .name = name, .checkpoint = checkpoint.value, .options = options };
        var result = try self.session.commit(Add.apply, &call, .{}, .{});
        defer result.deinit();
        return json.asInteger(result.value.value);
    }
    fn record(self: *@This(), id: u64) !json.Owned {
        return (try self.store.readRecord(gpa, id)).?;
    }
};
fn root(_: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
    return tx.createRootConversation();
}
const Add = struct {
    name: []const u8,
    checkpoint: Value,
    options: session_mod.TaskOptions,
    fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        return .{ .integer = @intCast(try tx.createTask(self.name, 1, .null, self.checkpoint, self.options)) };
    }
};
fn completed(_: ?*anyopaque, tx: *session_mod.Transaction, _: Value) !?Value {
    return try model.outcomeState(tx.owned.arena.allocator(), "terminal", try model.makeOutcome(tx.owned.arena.allocator(), "completed", .{ .string = "done" }));
}
fn aborted(_: ?*anyopaque, tx: *session_mod.Transaction, _: Value) !?Value {
    return try model.outcomeState(tx.owned.arena.allocator(), "terminal", try model.makeOutcome(tx.owned.arena.allocator(), "aborted", .{ .string = "stopped" }));
}
fn finish(_: ?*anyopaque, runtime: *scheduler_mod.Runtime, _: Value, _: types.Context) !void {
    try runtime.commit(completed, null);
}
fn stop(_: ?*anyopaque, runtime: *scheduler_mod.Runtime, _: Value, _: types.Context) !void {
    try runtime.commit(aborted, null);
}
fn noop(_: ?*anyopaque, _: *scheduler_mod.Runtime, _: Value, _: types.Context) !void {}
fn fail(_: ?*anyopaque, _: *scheduler_mod.Runtime, _: Value, _: types.Context) !void {
    return error.OriginalPhaseFailure;
}
fn def(name: []const u8, comptime handler: scheduler_mod.Handler) scheduler_mod.Definition {
    return .{ .name = name, .version = 1, .phases = &.{.{ .name = "start", .run = handler }}, .abort = stop };
}
fn terminalThenError(raw: ?*anyopaque, runtime: *scheduler_mod.Runtime, record: Value, context: types.Context) !void {
    try finish(raw, runtime, record, context);
    return error.OriginalPhaseFailure;
}
fn waitSelf(_: ?*anyopaque, runtime: *scheduler_mod.Runtime, _: Value, _: types.Context) !void {
    const Change = struct {
        fn apply(_: ?*anyopaque, tx: *session_mod.Transaction, record: Value) !?Value {
            const a = tx.owned.arena.allocator();
            var state = try model.checkpointState(a, "waiting", try model.field(try model.field(record, "state"), "checkpoint"));
            var on: Value = .{ .array = .init(a) };
            try on.array.append(try model.field(record, "id"));
            try state.object.put(a, "on", on);
            try state.object.put(a, "policy", .{ .string = "allSettled" });
            return state;
        }
    };
    try runtime.commit(Change.apply, null);
}
fn oracleCase(value: Value, name: []const u8) !Value {
    for ((try model.field(value, "cases")).array.items) |item| if (std.mem.eql(u8, try model.text(item, "scenario"), name)) return item;
    return error.MissingOracleScenario;
}
test "durable.scheduler actual upstream captured task records completed fault aborted and recovery" {
    var oracle = try json.Owned.parse(gpa, @embedFile("fixtures/scheduler_b7df.json"));
    defer oracle.deinit();
    const handlers = [_]struct { name: []const u8, handler: scheduler_mod.Handler }{
        .{ .name = "completed", .handler = finish }, .{ .name = "noop", .handler = noop }, .{ .name = "failed", .handler = fail }, .{ .name = "terminalThenError", .handler = terminalThenError }, .{ .name = "aborted", .handler = finish }, .{ .name = "waitingSelf", .handler = waitSelf },
    };
    inline for (handlers) |scenario| {
        var fixture: Fixture = undefined;
        try fixture.init();
        defer fixture.deinit();
        try fixture.scheduler.register(def("job", scenario.handler));
        const id = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
        try fixture.scheduler.open();
        if (std.mem.eql(u8, scenario.name, "aborted")) try fixture.scheduler.abort(id);
        fixture.scheduler.enable();
        _ = try fixture.scheduler.runUntilBlocked(5);
        var record = try fixture.record(id);
        defer record.deinit();
        try std.testing.expect(json.equal(try model.field(try oracleCase(oracle.value, scenario.name), "record"), record.value));
    }
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const id = try fixture.add("job", "{\"phase\":\"start\",\"count\":7}", .{ .conversationId = 1 });
    const RecoverSetup = struct {
        id: u64,
        fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const record = (try tx.currentRecord(self.id, .task)).?;
            try tx.setTask(try model.withState(tx.owned.arena.allocator(), record, try model.checkpointState(tx.owned.arena.allocator(), "running", try model.field(try model.field(record, "state"), "checkpoint"))));
            return .null;
        }
    };
    var call: RecoverSetup = .{ .id = id };
    var result = try fixture.session.commit(RecoverSetup.apply, &call, .{}, .{});
    result.deinit();
    try fixture.scheduler.open();
    var record = try fixture.record(id);
    defer record.deinit();
    try std.testing.expect(json.equal(try model.field(try oracleCase(oracle.value, "recoveryBeforeResume"), "record"), record.value));
    try std.testing.expectEqual(@as(usize, 0), try fixture.scheduler.drive());
}

test "durable.scheduler phases complete and invocation late writes cannot enter Session" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const Capture = struct {
        runtime: ?scheduler_mod.Runtime = null,
        fn run(raw: ?*anyopaque, runtime: *scheduler_mod.Runtime, record: Value, context: types.Context) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.runtime = runtime.retain();
            try finish(null, runtime, record, context);
        }
    };
    var capture: Capture = .{};
    var definition = def("job", Capture.run);
    definition.context = &capture;
    try fixture.scheduler.register(definition);
    const id = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    try std.testing.expectEqual(@as(usize, 1), try fixture.scheduler.runUntilBlocked(5));
    var record = try fixture.record(id);
    defer record.deinit();
    try std.testing.expectEqual(model.Status.terminal, try model.status(record.value));
    const generation = fixture.store.generation;
    try std.testing.expectError(error.InvocationEnded, capture.runtime.?.commit(completed, null));
    try std.testing.expectEqual(generation, fixture.store.generation);
    capture.runtime.?.release();
}
test "durable.scheduler fault precedence no progress handler failures and unknown phase" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.scheduler.register(def("noop", noop));
    try fixture.scheduler.register(def("fail", fail));
    const no_progress = try fixture.add("noop", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    const failure = try fixture.add("fail", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    const unknown = try fixture.add("noop", "{\"phase\":\"missing\"}", .{ .conversationId = 1 });
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    _ = try fixture.scheduler.runUntilBlocked(5);
    for ([_]u64{ no_progress, failure, unknown }) |id| {
        var record = try fixture.record(id);
        defer record.deinit();
        try std.testing.expectEqual(model.Status.terminal, try model.status(record.value));
        try std.testing.expectEqualStrings("faulted", try model.text(try model.field(try model.field(record.value, "state"), "outcome"), "status"));
    }
    var record = try fixture.record(failure);
    defer record.deinit();
    try std.testing.expectEqualStrings("OriginalPhaseFailure", try model.text(try model.field(try model.field(try model.field(record.value, "state"), "outcome"), "error"), "message"));
}
test "durable.scheduler holds parent outcomes until owned tasks and owned conversations settle" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.scheduler.register(def("job", finish));
    const parent = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    const child = try fixture.add("missing", "{\"phase\":\"start\"}", .{ .ownerTaskId = parent });
    const MakeConversation = struct {
        owner: u64,
        fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return tx.createConversation(null, self.owner);
        }
    };
    var call: MakeConversation = .{ .owner = parent };
    var conversation = try fixture.session.commit(MakeConversation.apply, &call, .{}, .{});
    defer conversation.deinit();
    const descendant = try fixture.add("missing", "{\"phase\":\"start\"}", .{ .conversationId = try model.number(conversation.value.value, "id") });
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    try std.testing.expectEqual(@as(usize, 1), try fixture.scheduler.drive());
    {
        var record = try fixture.record(parent);
        defer record.deinit();
        try std.testing.expectEqual(model.Status.completing, try model.status(record.value));
    }
    try fixture.scheduler.abort(child);
    try fixture.scheduler.abort(descendant);
    _ = try fixture.scheduler.runUntilBlocked(5);
    var record = try fixture.record(parent);
    defer record.deinit();
    try std.testing.expectEqual(model.Status.terminal, try model.status(record.value));
}
test "durable.scheduler recovery cascades cancelled owners bottom up excludes background boundaries" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.scheduler.register(def("job", finish));
    const parent = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    const child = try fixture.add("job", "{\"phase\":\"start\"}", .{ .ownerTaskId = parent });
    const background = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1, .background = true });
    try fixture.scheduler.abort(parent);
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    _ = try fixture.scheduler.runUntilBlocked(8);
    for ([_]u64{ parent, child }) |id| {
        var record = try fixture.record(id);
        defer record.deinit();
        try std.testing.expectEqualStrings("aborted", try model.text(try model.field(try model.field(record.value, "state"), "outcome"), "status"));
    }
    var record = try fixture.record(background);
    defer record.deinit();
    try std.testing.expectEqualStrings("completed", try model.text(try model.field(try model.field(record.value, "state"), "outcome"), "status"));
    var oracle = try json.Owned.parse(gpa, @embedFile("fixtures/scheduler_b7df.json"));
    defer oracle.deinit();
    const expected = try model.field(try oracleCase(oracle.value, "cascade"), "records");
    for ([_]u64{ parent, child, background }, expected.array.items) |id, oracle_record| {
        var actual = try fixture.record(id);
        defer actual.deinit();
        try std.testing.expect(json.equal(oracle_record, actual.value));
    }
}
test "durable.scheduler Session rejects new work with owner's final abort or outcome candidate" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const owner = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    const Illegal = struct {
        id: u64,
        fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const record = (try tx.currentRecord(self.id, .task)).?;
            _ = try tx.createTask("child", 1, .null, try model.field(try model.field(record, "state"), "checkpoint"), .{ .ownerTaskId = self.id });
            try tx.setTask(try model.withState(tx.owned.arena.allocator(), record, (try completed(null, tx, record)).?));
            return .null;
        }
    };
    var illegal: Illegal = .{ .id = owner };
    const generation = fixture.store.generation;
    try std.testing.expectError(error.TaskOwnerSettling, fixture.session.commit(Illegal.apply, &illegal, .{}, .{}));
    try std.testing.expectEqual(generation, fixture.store.generation);
    try std.testing.expectError(error.BackgroundChildTask, fixture.add("child", "{\"phase\":\"start\"}", .{ .ownerTaskId = owner, .background = true }));
    try std.testing.expectError(error.ChildTaskConversationMismatch, fixture.add("child", "{\"phase\":\"start\"}", .{ .ownerTaskId = owner, .conversationId = 99 }));
}

test "durable.scheduler real concurrent phases commit on one Session line" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const Parallel = struct {
        arrived: std.atomic.Value(usize) = .init(0),
        fn run(raw: ?*anyopaque, runtime: *scheduler_mod.Runtime, _: Value, _: types.Context) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            _ = self.arrived.fetchAdd(1, .acq_rel);
            var ready = false;
            for (0..2000) |_| {
                if (self.arrived.load(.acquire) == 4) {
                    ready = true;
                    break;
                }
                try std.Io.sleep(io, .fromMilliseconds(1), .awake);
            }
            if (!ready) return error.ParallelPhaseDeadline;
            try runtime.commit(change, null);
        }
        fn change(_: ?*anyopaque, tx: *session_mod.Transaction, record: Value) !?Value {
            var draft = model.object(tx.owned.arena.allocator());
            try draft.object.put(tx.owned.arena.allocator(), "kind", .{ .string = "proof" });
            _ = try tx.appendEntry(1, draft);
            return try completed(null, tx, record);
        }
    };
    var parallel: Parallel = .{};
    var definition = def("parallel", Parallel.run);
    definition.context = &parallel;
    try fixture.scheduler.register(definition);
    for (0..4) |_| _ = try fixture.add("parallel", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    try std.testing.expectEqual(@as(usize, 4), try fixture.scheduler.drive());
    try std.testing.expectEqual(@as(usize, 4), parallel.arrived.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), fixture.scheduler.reports.items.len);
    var rows = fixture.store.state.rows.iterator();
    var entries: usize = 0;
    while (rows.next()) |item| if (item.value_ptr.table == .entry) {
        entries += 1;
        try std.testing.expect(json.get(item.value_ptr.record, "byTaskId") != null);
    };
    try std.testing.expectEqual(@as(usize, 4), entries);
    try std.testing.expect(try fixture.scheduler.idle(1));
}

test "durable.scheduler running abort fences write before handler failure and executes abort once" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const Gated = struct {
        started: std.atomic.Value(bool) = .init(false),
        aborts: std.atomic.Value(usize) = .init(0),
        rejected: std.atomic.Value(bool) = .init(false),
        fn run(raw: ?*anyopaque, runtime: *scheduler_mod.Runtime, _: Value, context: types.Context) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.started.store(true, .release);
            for (0..2000) |_| {
                if (context.aborted()) break;
                try std.Io.sleep(io, .fromMilliseconds(1), .awake);
            }
            if (!context.aborted()) return error.AbortPhaseDeadline;
            runtime.commit(completed, null) catch |err| {
                if (err == error.TaskAbortMarked) self.rejected.store(true, .release);
                return error.LateOriginalFailure;
            };
            return error.UnexpectedAcceptedWrite;
        }
        fn abortRun(raw: ?*anyopaque, runtime: *scheduler_mod.Runtime, record: Value, context: types.Context) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            _ = self.aborts.fetchAdd(1, .acq_rel);
            try stop(null, runtime, record, context);
        }
        fn drive(scheduler: *scheduler_mod.Scheduler) void {
            _ = scheduler.drive() catch {};
        }
    };
    var gate: Gated = .{};
    var definition = def("gated", Gated.run);
    definition.context = &gate;
    definition.abort = Gated.abortRun;
    try fixture.scheduler.register(definition);
    const id = try fixture.add("gated", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    const worker = try std.Thread.spawn(.{}, Gated.drive, .{&fixture.scheduler});
    defer worker.join();
    var started = false;
    for (0..2000) |_| {
        if (gate.started.load(.acquire)) {
            started = true;
            break;
        }
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(started);
    try std.testing.expectError(error.ConcurrentSchedulerDrive, fixture.scheduler.drive());
    try fixture.scheduler.abort(id);
    // Wait for the drive owner rather than racing another drive; the deferred join still runs on assertion failure.
    for (0..2000) |_| {
        if (!fixture.scheduler.driving.load(.acquire)) break;
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(!fixture.scheduler.driving.load(.acquire));
    _ = try fixture.scheduler.runUntilBlocked(5);
    try std.testing.expect(gate.rejected.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), gate.aborts.load(.acquire));
    var record = try fixture.record(id);
    defer record.deinit();
    try std.testing.expectEqualStrings("aborted", try model.text(try model.field(try model.field(record.value, "state"), "outcome"), "status"));
}

test "durable.scheduler version migration failures cache per definition and compatible replacement hands over" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const Migrate = struct {
        count: usize = 0,
        fn bad(raw: ?*anyopaque, _: std.mem.Allocator, _: Value, _: Value, _: u64) !scheduler_mod.Migrated {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.count += 1;
            return error.OriginalMigrationFailure;
        }
        fn good(raw: ?*anyopaque, _: std.mem.Allocator, input: Value, checkpoint: Value, version: u64) !scheduler_mod.Migrated {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.count += 1;
            try std.testing.expectEqual(@as(u64, 1), version);
            return .{ .input = input, .checkpoint = checkpoint };
        }
    };
    const id = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    var migration: Migrate = .{};
    var definition = def("job", finish);
    definition.version = 2;
    definition.context = &migration;
    definition.migrate = Migrate.bad;
    try fixture.scheduler.register(definition);
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    try std.testing.expectEqual(@as(usize, 0), try fixture.scheduler.drive());
    try std.testing.expectEqual(@as(usize, 0), try fixture.scheduler.drive());
    try std.testing.expectEqual(@as(usize, 1), migration.count);
    definition.migrate = Migrate.good;
    try fixture.scheduler.register(definition);
    _ = try fixture.scheduler.runUntilBlocked(5);
    try std.testing.expectEqual(@as(usize, 2), migration.count);
    var record = try fixture.record(id);
    defer record.deinit();
    try std.testing.expectEqual(@as(u64, 2), try model.number(record.value, "version"));
    try std.testing.expectEqual(model.Status.terminal, try model.status(record.value));
}

test "durable.scheduler same version definition replacement switches only after committed progress" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const Replace = struct {
        scheduler: *scheduler_mod.Scheduler,
        fn progress(_: ?*anyopaque, tx: *session_mod.Transaction, _: Value) !?Value {
            const checkpoint = try json.parseLeaky(tx.owned.arena.allocator(), "{\"phase\":\"start\",\"count\":1}");
            return try model.checkpointState(tx.owned.arena.allocator(), "running", checkpoint);
        }
        fn run(raw: ?*anyopaque, runtime: *scheduler_mod.Runtime, _: Value, _: types.Context) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try self.scheduler.register(def("job", finish));
            try runtime.commit(progress, null);
        }
    };
    var replacement: Replace = .{ .scheduler = &fixture.scheduler };
    var definition = def("job", Replace.run);
    definition.context = &replacement;
    try fixture.scheduler.register(definition);
    const id = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    _ = try fixture.scheduler.drive();
    {
        var record = try fixture.record(id);
        defer record.deinit();
        try std.testing.expectEqual(model.Status.pending, try model.status(record.value));
    }
    _ = try fixture.scheduler.runUntilBlocked(5);
    var record = try fixture.record(id);
    defer record.deinit();
    try std.testing.expectEqual(model.Status.terminal, try model.status(record.value));
}

test "durable.scheduler waiting allSettled resumes after terminal members failFast aborts surviving owned members" {
    for ([_]bool{ false, true }) |fail_fast| {
        var fixture: Fixture = undefined;
        try fixture.init();
        defer fixture.deinit();
        try fixture.scheduler.register(def("job", finish));
        const parent = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
        const failed_child = try fixture.add("missing", "{\"phase\":\"start\"}", .{ .ownerTaskId = parent });
        const sibling = try fixture.add("missing", "{\"phase\":\"start\"}", .{ .ownerTaskId = parent });
        const Waiting = struct {
            parent: u64,
            failed_child: u64,
            sibling: u64,
            fail_fast: bool,
            fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
                const self: *@This() = @ptrCast(@alignCast(raw.?));
                const a = tx.owned.arena.allocator();
                const record = (try tx.currentRecord(self.parent, .task)).?;
                var state = try model.checkpointState(a, "waiting", try model.field(try model.field(record, "state"), "checkpoint"));
                var on: Value = .{ .array = .init(a) };
                try on.array.append(.{ .integer = @intCast(self.failed_child) });
                try on.array.append(.{ .integer = @intCast(self.sibling) });
                try state.object.put(a, "on", on);
                try state.object.put(a, "policy", .{ .string = if (self.fail_fast) "failFast" else "allSettled" });
                try tx.setTask(try model.withState(a, record, state));
                const child = (try tx.currentRecord(self.failed_child, .task)).?;
                try tx.setTask(try model.withState(a, child, try model.outcomeState(a, "terminal", try model.makeOutcome(a, "failed", .{ .string = "bad" }))));
                return .null;
            }
        };
        var call: Waiting = .{ .parent = parent, .failed_child = failed_child, .sibling = sibling, .fail_fast = fail_fast };
        var result = try fixture.session.commit(Waiting.apply, &call, .{}, .{});
        result.deinit();
        try fixture.scheduler.open();
        fixture.scheduler.enable();
        _ = try fixture.scheduler.drive();
        {
            var record = try fixture.record(sibling);
            defer record.deinit();
            try std.testing.expectEqual(fail_fast, try model.flag(record.value, "abortRequested"));
        }
        if (!fail_fast) try fixture.scheduler.abort(sibling);
        _ = try fixture.scheduler.runUntilBlocked(5);
        var record = try fixture.record(parent);
        defer record.deinit();
        try std.testing.expectEqualStrings("completed", try model.text(try model.field(try model.field(record.value, "state"), "outcome"), "status"));
    }
}

test "durable.scheduler terminal task retires existing and newly staged task documents atomically" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const id = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    const Retire = struct {
        id: u64,
        fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const a = tx.owned.arena.allocator();
            const doc_id = try tx.session.storage.mintId();
            const wire = try std.fmt.allocPrint(a, "{{\"type\":\"document.create\",\"record\":{{\"id\":{d},\"kind\":\"memo\",\"scope\":{{\"kind\":\"task\",\"taskId\":{d}}}}},\"content\":{{\"kind\":\"base\",\"version\":1,\"value\":{{\"v\":1}}}}}}", .{ doc_id, self.id });
            try tx.documentCommand(try json.parseLeaky(a, wire));
            const record = (try tx.currentRecord(self.id, .task)).?;
            try tx.setTask(try model.withState(a, record, (try completed(null, tx, record)).?));
            return .{ .integer = @intCast(doc_id) };
        }
    };
    var call: Retire = .{ .id = id };
    var result = try fixture.session.commit(Retire.apply, &call, .{}, .{});
    defer result.deinit();
    const document = fixture.store.state.documents.get(try json.asInteger(result.value.value)).?;
    try std.testing.expectEqual(result.seq.?, try model.number(document.record, "retiredAt"));
    try std.testing.expectEqual(result.seq.?, try model.number(document.record, "createdAt"));
    try std.testing.expect((try fixture.store.readDocument(gpa, try json.asInteger(result.value.value), .current)) == null);
}

test "durable.scheduler SQLite reopen resumes running checkpoint and old writer fence rejects mutation" {
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "scheduler.sqlite" });
    defer gpa.free(path);
    const Start = struct {
        fn apply(_: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            _ = try tx.createRootConversation();
            const a = tx.owned.arena.allocator();
            const checkpoint = try json.parseLeaky(a, "{\"phase\":\"start\",\"count\":7}");
            const id = try tx.createTask("job", 1, .null, checkpoint, .{ .conversationId = 1 });
            const record = (try tx.currentRecord(id, .task)).?;
            try tx.setTask(try model.withState(a, record, try model.checkpointState(a, "running", checkpoint)));
            return .{ .integer = @intCast(id) };
        }
    };
    var first = try backend.sqlite.Sqlite.open(gpa, io, path, .{});
    defer first.deinit();
    var first_session = session_mod.Session.init(gpa, io, .{ .sqlite = first });
    defer first_session.deinit();
    var start_result = try first_session.commit(Start.apply, null, .{}, .{});
    defer start_result.deinit();
    const id = try json.asInteger(start_result.value.value);
    var reopened = try backend.sqlite.Sqlite.open(gpa, io, path, .{});
    defer reopened.deinit();
    var reopened_session = session_mod.Session.init(gpa, io, .{ .sqlite = reopened });
    defer reopened_session.deinit();
    var scheduler = try scheduler_mod.Scheduler.init(gpa, io, &reopened_session, .{});
    defer scheduler.deinit();
    try scheduler.register(def("job", finish));
    try scheduler.open();
    {
        var record = (try reopened.readRecord(gpa, id)).?;
        defer record.deinit();
        try std.testing.expectEqual(model.Status.pending, try model.status(record.value));
        try std.testing.expectEqual(@as(u64, 7), try model.number(try model.field(try model.field(record.value, "state"), "checkpoint"), "count"));
    }
    const InvalidWriter = struct {
        id: u64,
        fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var record = (try tx.currentRecord(self.id, .task)).?;
            record = try json.clone(tx.owned.arena.allocator(), record);
            try record.object.put(tx.owned.arena.allocator(), "abortRequested", .{ .bool = true });
            try tx.setTask(record);
            return .null;
        }
    };
    var invalid: InvalidWriter = .{ .id = id };
    try std.testing.expectError(error.LostWriterFence, first_session.commit(InvalidWriter.apply, &invalid, .{}, .{}));
    scheduler.enable();
    _ = try scheduler.runUntilBlocked(5);
    var reader = try backend.sqlite.Sqlite.open(gpa, io, path, .{ .claim_writer = false });
    defer reader.deinit();
    var record = (try reader.readRecord(gpa, id)).?;
    defer record.deinit();
    try std.testing.expectEqual(model.Status.terminal, try model.status(record.value));
}

test "durable.scheduler allocation failures release registry resources and leave recovery admission atomic" {
    const Allocate = struct {
        fn run(allocator: std.mem.Allocator) !void {
            const Resource = struct {
                balance: usize = 0,
                fn retain(raw: ?*anyopaque) void {
                    const self: *@This() = @ptrCast(@alignCast(raw.?));
                    self.balance += 1;
                }
                fn release(raw: ?*anyopaque) void {
                    const self: *@This() = @ptrCast(@alignCast(raw.?));
                    self.balance -= 1;
                }
            };
            var resource: Resource = .{};
            defer std.debug.assert(resource.balance == 0);
            var store = try backend.memory.Memory.init(allocator);
            defer store.deinit();
            var session = session_mod.Session.init(allocator, io, .{ .memory = &store });
            defer session.deinit();
            var scheduler = try scheduler_mod.Scheduler.init(allocator, io, &session, .{});
            defer scheduler.deinit();
            var definition = def("job", finish);
            definition.context = &resource;
            definition.retain = Resource.retain;
            definition.release = Resource.release;
            try scheduler.register(definition);
            var result = try session.commit(start, null, .{}, .{});
            result.deinit();
            try scheduler.open();
        }
        fn start(_: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            _ = try tx.createRootConversation();
            const a = tx.owned.arena.allocator();
            const checkpoint = try json.parseLeaky(a, "{\"phase\":\"start\"}");
            const id = try tx.createTask("job", 1, .null, checkpoint, .{ .conversationId = 1 });
            const record = (try tx.currentRecord(id, .task)).?;
            try tx.setTask(try model.withState(a, record, try model.checkpointState(a, "running", checkpoint)));
            return .null;
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Allocate.run, .{});
}

test "durable.scheduler actual crashed native worker leaves running SQLite state and reopens once" {
    var environment = try std.testing.environ.createMap(gpa);
    defer environment.deinit();
    const fixture = environment.get("PI_DURABLE_SCHEDULER_FIXTURE") orelse return error.SkipZigTest;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "crashed.sqlite" });
    defer gpa.free(path);
    var child = try std.process.spawn(io, .{ .argv = &.{ fixture, path }, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore, .create_no_window = true });
    var live_child = true;
    defer if (live_child) child.kill(io);
    const termination = try child.wait(io);
    live_child = false;
    try std.testing.expectEqual(@as(u8, 86), termination.exited);
    var store = try backend.sqlite.Sqlite.open(gpa, io, path, .{});
    defer store.deinit();
    {
        var record = (try store.readRecord(gpa, 2)).?;
        defer record.deinit();
        try std.testing.expectEqual(model.Status.running, try model.status(record.value));
    }
    var session = session_mod.Session.init(gpa, io, .{ .sqlite = store });
    defer session.deinit();
    var scheduler = try scheduler_mod.Scheduler.init(gpa, io, &session, .{});
    defer scheduler.deinit();
    try scheduler.register(def("crash", finish));
    try scheduler.open();
    {
        var record = (try store.readRecord(gpa, 2)).?;
        defer record.deinit();
        try std.testing.expectEqual(model.Status.pending, try model.status(record.value));
        try std.testing.expectEqual(@as(u64, 7), try model.number(try model.field(try model.field(record.value, "state"), "checkpoint"), "count"));
    }
    scheduler.enable();
    try std.testing.expectEqual(@as(usize, 1), try scheduler.runUntilBlocked(5));
    var record = (try store.readRecord(gpa, 2)).?;
    defer record.deinit();
    try std.testing.expectEqual(model.Status.terminal, try model.status(record.value));
}

test "durable.scheduler Session close observers run outside locks once and can unsubscribe or reenter" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const Close = struct {
        session: *session_mod.Session,
        removed: u64 = 0,
        calls: usize = 0,
        later_calls: usize = 0,
        rejected: bool = false,
        fn notify(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            self.session.unsubscribeClose(self.removed);
            self.session.close();
            var result = self.session.commit(root, null, .{}, .{}) catch |err| {
                self.rejected = err == error.SessionClosed;
                return;
            };
            result.deinit();
        }
        fn later(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.later_calls += 1;
        }
        fn closeInside(_: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            tx.session.close();
            return .null;
        }
    };
    var close: Close = .{ .session = &fixture.session };
    _ = try fixture.session.subscribeClose(Close.notify, &close);
    close.removed = try fixture.session.subscribeClose(Close.later, &close);
    var result = try fixture.session.commit(Close.closeInside, null, .{}, .{});
    result.deinit();
    fixture.session.close();
    fixture.session.unsubscribeClose(close.removed);
    try std.testing.expectEqual(@as(usize, 1), close.calls);
    try std.testing.expectEqual(@as(usize, 0), close.later_calls);
    try std.testing.expect(close.rejected);
    try std.testing.expectError(error.SessionClosed, fixture.session.subscribeClose(Close.notify, &close));
}

test "durable.scheduler Session close cancels real active handler writes no outcome and retained runtime rejects" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const Closing = struct {
        ready: std.atomic.Value(bool) = .init(false),
        runtime: ?scheduler_mod.Runtime = null,
        fn run(raw: ?*anyopaque, runtime: *scheduler_mod.Runtime, _: Value, context: types.Context) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.runtime = runtime.retain();
            self.ready.store(true, .release);
            for (0..2000) |_| {
                if (context.aborted()) return;
                try std.Io.sleep(io, .fromMilliseconds(1), .awake);
            }
            return error.ClosePhaseDeadline;
        }
        fn drive(scheduler: *scheduler_mod.Scheduler) void {
            _ = scheduler.drive() catch {};
        }
    };
    var closing: Closing = .{};
    var definition = def("closing", Closing.run);
    definition.context = &closing;
    try fixture.scheduler.register(definition);
    const id = try fixture.add("closing", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    const owner = try std.Thread.spawn(.{}, Closing.drive, .{&fixture.scheduler});
    var ready = false;
    for (0..2000) |_| {
        if (closing.ready.load(.acquire)) {
            ready = true;
            break;
        }
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    }
    fixture.session.close();
    owner.join();
    try std.testing.expect(ready);
    try std.testing.expect(fixture.scheduler.closing.load(.acquire));
    try std.testing.expectError(error.InvocationEnded, closing.runtime.?.commit(completed, null));
    closing.runtime.?.release();
    var record = try fixture.record(id);
    defer record.deinit();
    try std.testing.expectEqual(model.Status.running, try model.status(record.value));
}

test "durable.scheduler settled background owner still bounds owned conversation idle and scope abort" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.scheduler.register(def("job", finish));
    const background = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1, .background = true });
    const Owned = struct {
        id: u64,
        fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return tx.createConversation(null, self.id);
        }
    };
    var call: Owned = .{ .id = background };
    var owned = try fixture.session.commit(Owned.apply, &call, .{}, .{});
    defer owned.deinit();
    const conversation = try model.number(owned.value.value, "id");
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    _ = try fixture.scheduler.runUntilBlocked(5);
    const child = try fixture.add("missing", "{\"phase\":\"start\"}", .{ .conversationId = conversation });
    try std.testing.expect(try fixture.scheduler.idle(1));
    try std.testing.expect(try fixture.scheduler.idle(null));
    try std.testing.expect(!try fixture.scheduler.idle(conversation));
    try fixture.scheduler.abortConversation(1, false);
    {
        var record = try fixture.record(child);
        defer record.deinit();
        try std.testing.expect(!try model.flag(record.value, "abortRequested"));
    }
    try fixture.scheduler.abortConversation(1, true);
    _ = try fixture.scheduler.runUntilBlocked(5);
    var record = try fixture.record(child);
    defer record.deinit();
    try std.testing.expectEqualStrings("orphaned", try model.text(try model.field(try model.field(record.value, "state"), "outcome"), "status"));
    try std.testing.expect(try fixture.scheduler.idle(conversation));
}

test "durable.scheduler abort waiting on unrelated task ignores wait set and uses fresh abort context" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const Fresh = struct {
        fn abortRun(_: ?*anyopaque, runtime: *scheduler_mod.Runtime, record: Value, context: types.Context) !void {
            try std.testing.expect(!context.aborted());
            try std.testing.expect(!runtime.context().aborted());
            try stop(null, runtime, record, context);
        }
    };
    var definition = def("job", finish);
    definition.abort = Fresh.abortRun;
    try fixture.scheduler.register(definition);
    const member = try fixture.add("missing", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    const waiter = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    const SetWait = struct {
        waiter: u64,
        member: u64,
        fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const a = tx.owned.arena.allocator();
            const record = (try tx.currentRecord(self.waiter, .task)).?;
            var state = try model.checkpointState(a, "waiting", try model.field(try model.field(record, "state"), "checkpoint"));
            var on: Value = .{ .array = .init(a) };
            try on.array.append(.{ .integer = @intCast(self.member) });
            try state.object.put(a, "on", on);
            try state.object.put(a, "policy", .{ .string = "allSettled" });
            try tx.setTask(try model.withState(a, record, state));
            return .null;
        }
    };
    var call: SetWait = .{ .waiter = waiter, .member = member };
    var result = try fixture.session.commit(SetWait.apply, &call, .{}, .{});
    result.deinit();
    try fixture.scheduler.open();
    try fixture.scheduler.abort(waiter);
    fixture.scheduler.enable();
    _ = try fixture.scheduler.runUntilBlocked(5);
    var record = try fixture.record(waiter);
    defer record.deinit();
    try std.testing.expectEqualStrings("aborted", try model.text(try model.field(try model.field(record.value, "state"), "outcome"), "status"));
    var remaining = try fixture.record(member);
    defer remaining.deinit();
    try std.testing.expectEqual(model.Status.pending, try model.status(remaining.value));
}

test "durable.scheduler queued input withdrawal and scheduler outcome cleanup share durable transaction" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const Hooks = struct {
        withdrawals: usize = 0,
        outcomes: usize = 0,
        fn withdraw(raw: ?*anyopaque, tx: *session_mod.Transaction, conversation: u64) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.withdrawals += 1;
            const a = tx.owned.arena.allocator();
            const view = try tx.session.storage.snapshot(gpa);
            defer view.destroy(gpa);
            var rows = view.rows.iterator();
            while (rows.next()) |item| {
                const row = item.value_ptr.*;
                if (row.table != .submission or try model.number(row.record, "conversationId") != conversation or !std.mem.eql(u8, try model.text(row.record, "status"), "queued")) continue;
                var record = try json.clone(a, row.record);
                try record.object.put(a, "status", .{ .string = "unanswered" });
                try record.object.put(a, "reason", .{ .string = "aborted" });
                try tx.writeRecord(.submission, record);
            }
        }
        fn settle(raw: ?*anyopaque, tx: *session_mod.Transaction, _: Value, _: Value) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.outcomes += 1;
            var draft = model.object(tx.owned.arena.allocator());
            try draft.object.put(tx.owned.arena.allocator(), "kind", .{ .string = "cleanup" });
            _ = try tx.appendEntry(1, draft);
        }
        fn seed(_: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            const a = tx.owned.arena.allocator();
            const id = try tx.session.storage.mintId();
            const wire = try std.fmt.allocPrint(a, "{{\"id\":{d},\"conversationId\":1,\"type\":\"input\",\"status\":\"queued\"}}", .{id});
            try tx.writeRecord(.submission, try json.parseLeaky(a, wire));
            return .{ .integer = @intCast(id) };
        }
    };
    var hooks: Hooks = .{};
    fixture.scheduler.options.callback_context = &hooks;
    fixture.scheduler.options.withdraw_inputs = Hooks.withdraw;
    fixture.scheduler.options.settle_outcome = Hooks.settle;
    const id = try fixture.add("missing", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    var seeded = try fixture.session.commit(Hooks.seed, null, .{}, .{});
    defer seeded.deinit();
    try fixture.scheduler.open();
    try fixture.scheduler.abortConversation(1, false);
    fixture.scheduler.enable();
    _ = try fixture.scheduler.runUntilBlocked(5);
    try std.testing.expectEqual(@as(usize, 1), hooks.withdrawals);
    try std.testing.expectEqual(@as(usize, 1), hooks.outcomes);
    var submission = try fixture.record(try json.asInteger(seeded.value.value));
    defer submission.deinit();
    try std.testing.expectEqualStrings("unanswered", try model.text(submission.value, "status"));
    const task_row = fixture.store.state.rows.get(id).?;
    var entries: usize = 0;
    var rows = fixture.store.state.rows.iterator();
    while (rows.next()) |item| if (item.value_ptr.table == .entry) {
        entries += 1;
        try std.testing.expectEqual(task_row.commitSeq, item.value_ptr.commitSeq);
    };
    try std.testing.expectEqual(@as(usize, 1), entries);
}

test "durable.scheduler task definition resources release exactly once and retained callback can reenter registration" {
    var fixture: Fixture = undefined;
    try fixture.init();
    const Resource = struct {
        scheduler: *scheduler_mod.Scheduler,
        retained: usize = 0,
        released: usize = 0,
        failed: bool = false,
        fn retain(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.retained += 1;
            self.scheduler.register(def("helper", finish)) catch {
                self.failed = true;
            };
        }
        fn release(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.released += 1;
        }
    };
    var resource: Resource = .{ .scheduler = &fixture.scheduler };
    var definition = def("job", finish);
    definition.context = &resource;
    definition.retain = Resource.retain;
    definition.release = Resource.release;
    try fixture.scheduler.register(definition);
    try fixture.scheduler.register(definition);
    try std.testing.expectEqual(@as(usize, 2), resource.retained);
    try std.testing.expect(!resource.failed);
    fixture.deinit();
    try std.testing.expectEqual(@as(usize, 2), resource.released);
}

test "durable.scheduler native initial callback validates admission first and preserves original errors" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const Initial = struct {
        scheduler: *scheduler_mod.Scheduler,
        calls: usize = 0,
        conversation: u64 = 99,
        fn initial(raw: ?*anyopaque, _: std.mem.Allocator, _: Value) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            return error.OriginalInitialFailure;
        }
        fn create(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            _ = try self.scheduler.createTask(tx, "job", .null, .{ .conversationId = self.conversation });
            return .null;
        }
    };
    var initial: Initial = .{ .scheduler = &fixture.scheduler };
    var definition = def("job", finish);
    definition.context = &initial;
    definition.initial = Initial.initial;
    try fixture.scheduler.register(definition);
    const generation = fixture.store.generation;
    const next_id = fixture.store.state.nextId;
    try std.testing.expectError(error.UnknownConversation, fixture.session.commit(Initial.create, &initial, .{}, .{}));
    try std.testing.expectEqual(@as(usize, 0), initial.calls);
    initial.conversation = 1;
    try std.testing.expectError(error.OriginalInitialFailure, fixture.session.commit(Initial.create, &initial, .{}, .{}));
    try std.testing.expectEqual(@as(usize, 1), initial.calls);
    try std.testing.expectEqual(generation, fixture.store.generation);
    try std.testing.expectEqual(next_id, fixture.store.state.nextId);
}

test "durable.scheduler terminal records cannot be replaced and corrupt ownership cycles fail closed" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.scheduler.register(def("job", finish));
    const id = try fixture.add("job", "{\"phase\":\"start\"}", .{ .conversationId = 1 });
    try fixture.scheduler.open();
    fixture.scheduler.enable();
    _ = try fixture.scheduler.runUntilBlocked(5);
    const Replace = struct {
        id: u64,
        fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const record = (try tx.currentRecord(self.id, .task)).?;
            try tx.setTask(try model.withState(tx.owned.arena.allocator(), record, try model.checkpointState(tx.owned.arena.allocator(), "pending", try json.parseLeaky(tx.owned.arena.allocator(), "{\"phase\":\"start\"}"))));
            return .null;
        }
    };
    var call: Replace = .{ .id = id };
    const generation = fixture.store.generation;
    try std.testing.expectError(error.TaskAlreadyTerminal, fixture.session.commit(Replace.apply, &call, .{}, .{}));
    try std.testing.expectEqual(generation, fixture.store.generation);
    var corrupt = try json.Owned.parse(gpa, "[{\"type\":\"task\",\"value\":{\"id\":10,\"conversationId\":1,\"kind\":\"job\",\"version\":1,\"input\":null,\"owner\":10,\"background\":false,\"abortRequested\":false,\"state\":{\"status\":\"pending\",\"checkpoint\":{\"phase\":\"start\"}}}}]");
    defer corrupt.deinit();
    _ = try fixture.store.commit(corrupt.value);
    const corrupt_generation = fixture.store.generation;
    try std.testing.expectError(error.TaskOwnershipCycle, fixture.scheduler.reconcile());
    try std.testing.expectEqual(corrupt_generation, fixture.store.generation);
}
