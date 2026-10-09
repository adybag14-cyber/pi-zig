const std = @import("std");
const session_mod = @import("session.zig");
const backend = @import("backend/root.zig");
const json = backend.json;
const types = @import("types.zig");
const Session = session_mod.Session;
const Fault = struct {
    operation: enum { mintId, commitAt, snapshot, readRecord, readTableRecord, readEntry, readDocument, scan },
    failure: anyerror = error.OriginalBackendFailure,
    calls: usize = 0,
    abort: ?*std.atomic.Value(bool) = null,
    assert_unlocked: ?*Session = null,
    fn check(raw: ?*anyopaque, operation: @FieldType(Fault, "operation")) !void {
        const self: *Fault = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        if (self.assert_unlocked) |current| {
            if (!current.mutex.tryLock()) return error.SessionMutexHeldAcrossOwnerCallback;
            current.mutex.unlock(current.io);
            if (!current.storage.backend_mutex.tryLock()) return error.StorageMutexHeldAcrossOwnerCallback;
            current.storage.backend_mutex.unlock(current.io);
        }
        if (self.abort) |flag| flag.store(true, .release);
        if (self.operation == operation) return self.failure;
    }
    fn mintId(raw: ?*anyopaque) !u64 {
        try check(raw, .mintId);
        return 8;
    }
    fn commitAt(raw: ?*anyopaque, _: json.Value, _: ?u64) !u64 {
        try check(raw, .commitAt);
        return 1;
    }
    fn snapshot(raw: ?*anyopaque, gpa: std.mem.Allocator) !*backend.memory.State {
        try check(raw, .snapshot);
        return backend.memory.State.create(gpa);
    }
    fn readRecord(raw: ?*anyopaque, _: std.mem.Allocator, _: u64) !?json.Owned {
        try check(raw, .readRecord);
        return null;
    }
    fn readTableRecord(raw: ?*anyopaque, _: std.mem.Allocator, _: backend.memory.Table, _: u64) !?json.Owned {
        try check(raw, .readTableRecord);
        return null;
    }
    fn readEntry(raw: ?*anyopaque, _: std.mem.Allocator, _: u64, _: ?u64) !?json.Owned {
        try check(raw, .readEntry);
        return null;
    }
    fn readDocument(raw: ?*anyopaque, _: std.mem.Allocator, _: u64, _: backend.memory.Point) !?json.Owned {
        try check(raw, .readDocument);
        return null;
    }
    fn scan(raw: ?*anyopaque, gpa: std.mem.Allocator, _: backend.query.Query) !json.Owned {
        try check(raw, .scan);
        return json.Owned.empty(gpa);
    }
    const vtable: backend.Custom.VTable = .{ .mintId = mintId, .commitAt = commitAt, .snapshot = snapshot, .readRecord = readRecord, .readTableRecord = readTableRecord, .readEntry = readEntry, .readDocument = readDocument, .scan = scan };
    fn capability(self: *Fault) backend.Backend {
        return .{ .custom = .{ .context = self, .vtable = &vtable } };
    }
};
fn exercise(current: *Session, operation: @FieldType(Fault, "operation")) !void {
    const gpa = current.gpa;
    switch (operation) {
        .mintId => _ = try current.storage.mintId(),
        .commitAt => _ = try current.storage.commitAt(.{ .array = .init(gpa) }, null),
        .snapshot => {
            const value = try current.storage.snapshot(gpa);
            value.destroy(gpa);
        },
        .readRecord => {
            if (try current.storage.readRecord(gpa, 1)) |owned| {
                var value = owned;
                value.deinit();
            }
        },
        .readTableRecord => {
            if (try current.storage.readTableRecord(gpa, .conversation, 1)) |owned| {
                var value = owned;
                value.deinit();
            }
        },
        .readEntry => {
            if (try current.storage.readEntry(gpa, 1, null)) |owned| {
                var value = owned;
                value.deinit();
            }
        },
        .readDocument => {
            if (try current.storage.readDocument(gpa, 1, .current)) |owned| {
                var value = owned;
                value.deinit();
            }
        },
        .scan => {
            var owned = try current.storage.scan(gpa, .{ .table = .conversation });
            owned.deinit();
        },
    }
}
test "durable eba every backend capability fails Session once and prevents later backend admission" {
    inline for (std.meta.tags(@FieldType(Fault, "operation"))) |operation| {
        for ([_]anyerror{ error.OriginalBackendFailure, error.OutOfMemory }) |failure| {
            var fault: Fault = .{ .operation = operation, .failure = failure };
            var current = Session.init(std.testing.allocator, std.testing.io, fault.capability());
            defer current.deinit();
            var closes: usize = 0;
            _ = try current.subscribeClose(struct {
                fn close(raw: ?*anyopaque) void {
                    const n: *usize = @ptrCast(@alignCast(raw.?));
                    n.* += 1;
                }
            }.close, &closes);
            try std.testing.expectError(failure, exercise(&current, operation));
            try std.testing.expectEqual(failure, current.failure().?);
            try std.testing.expectEqual(@as(usize, 1), closes);
            try std.testing.expectError(error.SessionFailed, exercise(&current, operation));
            try std.testing.expectEqual(@as(usize, 1), fault.calls);
            try std.testing.expect(!current.fail(error.LaterFailure));
            try std.testing.expectEqual(failure, current.failure().?);
        }
    }
}
test "durable eba request errors exempt reads only and cancellation never exempts mint or commit" {
    for ([_]anyerror{ error.StorageRequestError, error.UnknownConversation, error.InvalidStorageCursor }) |failure| {
        var fault: Fault = .{ .operation = .readTableRecord, .failure = failure };
        var current = Session.init(std.testing.allocator, std.testing.io, fault.capability());
        defer current.deinit();
        try std.testing.expectError(failure, exercise(&current, .readTableRecord));
        try std.testing.expect(current.failure() == null);
        try std.testing.expectEqual(@as(u64, 8), try current.storage.mintId());
    }
    for ([_]@FieldType(Fault, "operation"){ .mintId, .commitAt }) |operation| {
        var fault: Fault = .{ .operation = operation, .failure = error.StorageRequestError };
        var current = Session.init(std.testing.allocator, std.testing.io, fault.capability());
        defer current.deinit();
        try std.testing.expectError(error.StorageRequestError, exercise(&current, operation));
        try std.testing.expectEqual(error.StorageRequestError, current.failure().?);
    }
    var abort = std.atomic.Value(bool).init(false);
    var fault: Fault = .{ .operation = .readTableRecord, .abort = &abort };
    var current = Session.init(std.testing.allocator, std.testing.io, fault.capability());
    defer current.deinit();
    try std.testing.expectError(error.OriginalBackendFailure, current.storage.readTableRecordContext(current.gpa, .conversation, 1, .{ .abort_flag = &abort }));
    try std.testing.expect(current.failure() == null);
    fault.operation = .mintId;
    try std.testing.expectError(error.OriginalBackendFailure, current.storage.mintId());
    try std.testing.expectEqual(error.OriginalBackendFailure, current.failure().?);
}
test "durable eba host listener faults are contained and internal faults seal later calls after a successful commit" {
    for ([_]bool{ false, true }) |internal| {
        var memory = try backend.memory.Memory.init(std.testing.allocator);
        defer memory.deinit();
        var current = Session.init(std.testing.allocator, std.testing.io, .{ .memory = &memory });
        defer current.deinit();
        const Observer = struct {
            calls: usize = 0,
            reports: usize = 0,
            fn report(raw: ?*anyopaque, err: anyerror) void {
                const self: *@This() = @ptrCast(@alignCast(raw.?));
                std.debug.assert(err == error.ListenerFailure);
                self.reports += 1;
            }
            fn fail(_: ?*anyopaque, _: *const session_mod.Publication, _: types.Context) !void {
                return error.ListenerFailure;
            }
            fn success(raw: ?*anyopaque, _: *const session_mod.Publication, _: types.Context) !void {
                const self: *@This() = @ptrCast(@alignCast(raw.?));
                self.calls += 1;
            }
            fn create(_: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !json.Value {
                return tx.createRootConversation();
            }
            fn noWrites(_: ?*anyopaque, _: *session_mod.Transaction, _: types.Context) !json.Value {
                return .{ .bool = true };
            }
        };
        var observer: Observer = .{};
        current.report_error = Observer.report;
        current.report_context = &observer;
        if (internal) _ = try current.observeCommits(Observer.fail, null) else _ = try current.subscribe(Observer.fail, null);
        _ = try current.subscribe(Observer.success, &observer);
        var result = try current.commit(Observer.create, null, .{}, .{});
        defer result.deinit();
        try std.testing.expectEqual(@as(?u64, 1), result.seq);
        try std.testing.expectEqual(@as(usize, 1), observer.calls);
        try std.testing.expectEqual(@as(usize, 1), observer.reports);
        if (internal) try std.testing.expectError(error.SessionFailed, current.commit(Observer.noWrites, null, .{}, .{})) else {
            var later = try current.commit(Observer.noWrites, null, .{}, .{});
            later.deinit();
            try std.testing.expect(current.failure() == null);
        }
    }
}

test "durable eba mutation line and owner custom Storage callbacks hold no Session or backend mutex" {
    var fault: Fault = .{ .operation = .scan };
    var capability = fault.capability();
    capability.custom.callbacks_on_owner = true;
    var current = Session.init(std.testing.allocator, std.testing.io, capability);
    defer current.deinit();
    fault.assert_unlocked = &current;
    const callback = struct {
        fn run(_: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !json.Value {
            try std.testing.expect(tx.session.mutex.tryLock());
            tx.session.mutex.unlock(tx.session.io);
            try std.testing.expect(tx.session.storage.backend_mutex.tryLock());
            tx.session.storage.backend_mutex.unlock(tx.session.io);
            return tx.createRootConversation();
        }
    };
    var result = try current.commit(callback.run, null, .{}, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(?u64, 1), result.seq);
    try std.testing.expect(current.failure() == null);
    try std.testing.expectEqual(@as(usize, 2), fault.calls);
}

test "durable eba failure discards an underway successful read and backend drain waits for its actual settlement" {
    const Race = struct {
        current: *Session,
        began: std.Io.Event = .unset,
        release: std.Io.Event = .unset,
        drain_began: std.Io.Event = .unset,
        drained: std.atomic.Value(bool) = .init(false),
        result_error: ?anyerror = null,
        fn snapshot(raw: ?*anyopaque, gpa: std.mem.Allocator) !*backend.memory.State {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.began.set(self.current.io);
            self.release.waitUncancelable(self.current.io);
            return backend.memory.State.create(gpa);
        }
        fn read(self: *@This()) void {
            const value = self.current.storage.snapshot(self.current.gpa) catch |err| {
                self.result_error = err;
                return;
            };
            value.destroy(self.current.gpa);
        }
        fn drain(self: *@This()) void {
            self.drain_began.set(self.current.io);
            self.current.storage.drain();
            self.drained.store(true, .release);
        }
    };
    var vtable = Fault.vtable;
    vtable.snapshot = Race.snapshot;
    var current = Session.init(std.testing.allocator, std.testing.io, .{ .custom = .{ .context = null, .vtable = &vtable } });
    defer current.deinit();
    var race: Race = .{ .current = &current };
    current.storage.raw.custom.context = &race;
    const reader = try std.Thread.spawn(.{}, Race.read, .{&race});
    var reader_joined = false;
    defer if (!reader_joined) reader.join();
    race.began.waitUncancelable(current.io);
    defer race.release.set(current.io);
    try std.testing.expect(current.fail(error.FirstRacingFailure));
    const closer = try std.Thread.spawn(.{}, Race.drain, .{&race});
    var closer_joined = false;
    defer {
        race.release.set(current.io);
        if (!closer_joined) closer.join();
    }
    race.drain_began.waitUncancelable(current.io);
    try std.testing.expect(!race.drained.load(.acquire));
    race.release.set(current.io);
    closer.join();
    closer_joined = true;
    // The drain observes settlement; join establishes the read's result write.
    reader.join();
    reader_joined = true;
    try std.testing.expectEqual(error.SessionFailed, race.result_error.?);
    try std.testing.expect(race.drained.load(.acquire));
    try std.testing.expectEqual(error.FirstRacingFailure, current.failure().?);
}
