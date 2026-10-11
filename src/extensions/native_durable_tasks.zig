//! Public task runtime. Scheduler threads carry native leases and owned JSON only.
const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const scheduling = @import("../durable/scheduler.zig");
const owner_index = @import("../durable/ownership_index.zig");
const session_mod = @import("../durable/session.zig");
const backend = @import("../durable/backend/root.zig");
const broker_mod = @import("native_durable_broker.zig");
const aborts = @import("abort_signal.zig");
const json = backend.json;
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Migration = struct { key: []u8, value: ?json.Owned };
const NativeDefinition = struct { manager: *Manager, id: usize, migrations: std.ArrayList(Migration) = .empty };
const Definition = struct { native: *NativeDefinition, token: c.JSValue };
const Event = struct {
    seq: u64,
    changes: json.Owned,
    ready: bool = true,
    index: ?owner_index.Index = null,
    fn deinit(self: *Event) void {
        self.changes.deinit();
        if (self.index) |*index| index.deinit();
    }
};
const DispatchPhase = enum(u8) { pending, active, done };
const Entry = struct {
    manager: *Manager,
    runtime: scheduling.Runtime,
    generation: u64,
    definition: usize,
    active: std.atomic.Value(bool) = .init(true),
    dispatch_phase: std.atomic.Value(DispatchPhase) = .init(.pending),
    reply_mutex: std.Io.Mutex = .init,
    reply_done: std.Io.Event = .unset,
    reply_settled: bool = false,
    reply_failure: ?anyerror = null,
    refs: std.atomic.Value(usize) = .init(2), // Worker + ledger.
    fn retain(self: *Entry) *Entry {
        _ = self.refs.fetchAdd(1, .monotonic);
        return self;
    }
    fn release(self: *Entry) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) {
            self.runtime.release();
            const manager = self.manager;
            manager.engine.gpa.destroy(self);
            manager.release();
        }
    }
    fn finishReply(self: *Entry, failure: ?anyerror) void {
        const io = self.manager.lease.value.io;
        self.reply_mutex.lockUncancelable(io);
        defer self.reply_mutex.unlock(io);
        if (self.reply_settled) return;
        self.reply_failure = failure;
        self.reply_settled = true;
        self.reply_done.set(io);
    }
    fn awaitReply(self: *Entry) !void {
        const io = self.manager.lease.value.io;
        self.reply_done.waitUncancelable(io);
        self.reply_mutex.lockUncancelable(io);
        defer self.reply_mutex.unlock(io);
        if (self.reply_failure) |failure| return failure;
    }
};
const PendingPhase = struct {
    next: ?*PendingPhase = null,
    entry: *Entry,
    promise: c.JSValue,
    runtime_value: c.JSValue,
    context: c.JSValue,
    allocation_generation: u64,
};
const Runtime = struct { entry: *Entry, session: c.JSValue, signal: c.JSValue, context: c.JSValue, agent: c.JSValue, snapshot: c.JSValue };
const RuntimeMethod = enum(c_int) { getTask, outcomes, conversation, entry, now, report, memo, snapshot, snapshotAsOf, watchDoc, agent, env, context, sleep, waitForTask, ownedTasks, abortOwned };
const Waiter = struct { id: ?u64, conversation: ?u64, resolve: c.JSValue, reject: c.JSValue, context: c.JSValue };
const Signal = struct { entry: *Entry, value: c.JSValue, context: c.JSValue };
const Sleeper = struct { runtime: c.JSValue, until: f64, context: c.JSValue, resolve: c.JSValue, reject: c.JSValue };
const ReadQuery = struct { id: u64, generation: u64, owner_generation: u64 };
const ReadReply = struct { query: ReadQuery, record: ?json.Owned };
pub const Manager = struct {
    engine: *Engine,
    hub: *Hub,
    lease: *durable.SessionLease,
    session: c.JSValue,
    options: c.JSValue,
    context: c.JSValue,
    registry: c.JSValue,
    snapshot: c.JSValue,
    scheduler: scheduling.Scheduler,
    broker: broker_mod.Broker,
    definitions: std.ArrayList(Definition) = .empty,
    ledger: std.ArrayList(*Entry) = .empty,
    events: std.ArrayList(Event) = .empty,
    mutex: std.Io.Mutex = .init,
    waiters: std.ArrayList(Waiter) = .empty,
    terminal_tasks: std.AutoHashMapUnmanaged(u64, json.Owned) = .empty,
    // Source's #live owns committed copies; Storage reads must not replace
    // them. Terminal publications release these records immediately.
    live_task_records: std.AutoHashMapUnmanaged(u64, json.Owned) = .empty,
    missing_tasks: std.AutoHashMapUnmanaged(u64, void) = .empty,
    pending_reads: std.AutoHashMapUnmanaged(u64, u64) = .empty,
    read_queries: std.ArrayList(ReadQuery) = .empty,
    read_replies: std.ArrayList(ReadReply) = .empty,
    next_read_generation: u64 = 1,
    signals: std.ArrayList(Signal) = .empty,
    watches: std.ArrayList(struct { entry: *Entry, value: c.JSValue }) = .empty,
    contexts: std.AutoHashMapUnmanaged(u64, ?@import("native_durable_context_view.zig").Cache) = .empty,
    sleepers: std.ArrayList(Sleeper) = .empty,
    next_invocation: u64 = 1,
    generation: u64,
    refs: std.atomic.Value(usize) = .init(1),
    thread: ?std.Thread = null,
    finished: std.atomic.Value(bool) = .init(true),
    closed: bool = false,
    enabled: bool = false,
    // Owner-thread publications may arrive after an empty driver has selected
    // its return value. Keep their refill request separate from last_count,
    // which the driver writes and the owner reads only after joining it.
    drive_requested: bool = false,
    last_count: usize = 0,
    driver_failure: ?anyerror = null,
    clock_value: std.atomic.Value(i64) = .init(0),
    custom_clock: bool = false,
    clock_callback: c.JSValue,
    vm_owner: ?c.JSValue = null,
    published_index: ?owner_index.Index = null,
    pending_index: ?owner_index.Index = null,
    prepared_publication_index: ?owner_index.Index = null,
    prepared_publication_seq: ?u64 = null,
    abort_controls: @import("native_durable_abort_control.zig").Queue = .{},
    task_aborts: @import("native_durable_task_abort.zig").Queue = .{},
    active_dispatches: usize = 0,
    first_phase: ?*PendingPhase = null,
    last_phase: ?*PendingPhase = null,
    join_waiters: std.ArrayList(c.JSValue) = .empty,
    fn nativeClock(raw: ?*anyopaque) i64 {
        const self: *Manager = @ptrCast(@alignCast(raw.?));
        return if (self.custom_clock) self.clock_value.load(.acquire) else std.Io.Clock.real.now(self.lease.value.io).toMilliseconds();
    }
    pub fn updateClock(self: *Manager) !void {
        if (!self.custom_clock) return;
        const value = try self.engine.checked(c.JS_Call(self.engine.context, self.clock_callback, c.pi_js_undefined(), 0, null));
        defer self.engine.freeValue(value);
        var number: f64 = 0;
        if (c.JS_ToFloat64(self.engine.context, &number, value) < 0) return error.JavaScriptException;
        if (!std.math.isFinite(number) or number != @trunc(number) or @abs(number) > backend.memory.max_integer) return error.InvalidTaskClock;
        self.clock_value.store(@intFromFloat(number), .release);
    }
    fn refreshRegistry(self: *Manager) !void {
        const next = try sdk.invoke(self.engine, self.registry, "snapshot", &.{});
        var installed = false;
        errdefer if (!installed) self.engine.freeValue(next);
        if (c.JS_IsStrictEqual(self.engine.context, next, self.snapshot)) {
            self.engine.freeValue(next);
            return;
        }
        self.engine.freeValue(self.snapshot);
        self.snapshot = next;
        installed = true;
        try loadDefinitions(self);
        for (self.definitions.items) |definition| {
            const value = try sdk.get(self.engine, definition.token, "definition");
            defer self.engine.freeValue(value);
            const name_value = try sdk.get(self.engine, value, "name");
            defer self.engine.freeValue(name_value);
            const name = try self.engine.toString(name_value);
            defer self.engine.gpa.free(name);
            const queried_name = try sdk.text(self.engine, name);
            defer self.engine.freeValue(queried_name);
            const current = try sdk.invoke(self.engine, self.snapshot, "task", &.{queried_name});
            defer self.engine.freeValue(current);
            if (c.JS_IsUndefined(current)) self.scheduler.removeDefinition(name);
        }
    }
    fn retain(self: *Manager) *Manager {
        _ = self.refs.fetchAdd(1, .monotonic);
        return self;
    }
    fn release(self: *Manager) void {
        if (self.refs.fetchSub(1, .acq_rel) != 1) return;
        std.debug.assert(self.closed and self.thread == null and self.ledger.items.len == 0 and self.first_phase == null and self.active_dispatches == 0);
        self.task_aborts.deinit(self.engine);
        self.scheduler.deinit();
        self.abort_controls.deinit(self.engine);
        for (self.join_waiters.items) |resolve| self.engine.freeValue(resolve);
        self.join_waiters.deinit(self.engine.gpa);
        if (self.published_index) |*index| index.deinit();
        if (self.pending_index) |*index| index.deinit();
        if (self.prepared_publication_index) |*index| index.deinit();
        self.broker.deinit();
        for (self.definitions.items) |definition| {
            for (definition.native.migrations.items) |*migration| {
                self.engine.gpa.free(migration.key);
                if (migration.value) |*value| value.deinit();
            }
            definition.native.migrations.deinit(self.engine.gpa);
            self.engine.gpa.destroy(definition.native);
        }
        self.definitions.deinit(self.engine.gpa);
        for (self.events.items) |*event| event.deinit();
        self.events.deinit(std.heap.page_allocator);
        self.ledger.deinit(std.heap.page_allocator);
        self.waiters.deinit(self.engine.gpa);
        var terminal = self.terminal_tasks.valueIterator();
        while (terminal.next()) |item| item.deinit();
        self.terminal_tasks.deinit(self.engine.gpa);
        self.clearLiveTaskRecords();
        self.live_task_records.deinit(self.engine.gpa);
        self.missing_tasks.deinit(self.engine.gpa);
        self.pending_reads.deinit(self.engine.gpa);
        self.read_queries.deinit(std.heap.page_allocator);
        for (self.read_replies.items) |*reply| if (reply.record) |*record| record.deinit();
        self.read_replies.deinit(std.heap.page_allocator);
        self.signals.deinit(self.engine.gpa);
        self.watches.deinit(self.engine.gpa);
        self.contexts.deinit(self.engine.gpa);
        self.sleepers.deinit(self.engine.gpa);
        self.lease.release();
        self.engine.gpa.destroy(self);
    }
    fn driver(self: *Manager) void {
        self.last_count = self.scheduler.driveRefilling() catch |err| {
            self.driver_failure = err;
            self.finished.store(true, .release);
            if (self.broker.notify.call) |notify| notify(self.broker.notify.context);
            return;
        };
        self.finished.store(true, .release);
        if (self.broker.notify.call) |notify| notify(self.broker.notify.context);
    }
    fn start(self: *Manager) !void {
        if (self.closed or !self.enabled or self.thread != null) return;
        try self.updateClock();
        try self.prepareMigrations();
        const requested = self.drive_requested;
        self.drive_requested = false;
        errdefer self.drive_requested = requested;
        self.finished.store(false, .release);
        self.last_count = 0;
        self.driver_failure = null;
        self.thread = std.Thread.spawn(.{}, driver, .{self}) catch |err| {
            self.finished.store(true, .release);
            return err;
        };
    }
    fn prepareMigrations(self: *Manager) !void {
        var snapshot = try self.lease.value.storage.snapshot(self.engine.gpa);
        defer snapshot.destroy(self.engine.gpa);
        var rows = snapshot.rows.iterator();
        while (rows.next()) |row| {
            if (row.value_ptr.table != .task) continue;
            const record = row.value_ptr.record;
            const status = try json.asString(try json.required(try json.required(record, "state"), "status"));
            if (std.mem.eql(u8, status, "terminal") or std.mem.eql(u8, status, "completing")) continue;
            const name = try json.asString(try json.required(record, "kind"));
            const current = try sdk.text(self.engine, name);
            defer self.engine.freeValue(current);
            const token = try sdk.invoke(self.engine, self.snapshot, "task", &.{current});
            defer self.engine.freeValue(token);
            if (c.JS_IsUndefined(token)) continue;
            for (self.definitions.items) |definition| {
                if (!c.JS_IsStrictEqual(self.engine.context, token, definition.token)) continue;
                const object = try sdk.get(self.engine, token, "definition");
                defer self.engine.freeValue(object);
                const version = try sdk.get(self.engine, object, "version");
                defer self.engine.freeValue(version);
                const from = try json.asInteger(try json.required(record, "version"));
                if (try durable.number(self.engine, version) <= from) continue;
                const callback = try sdk.get(self.engine, object, "migrate");
                defer self.engine.freeValue(callback);
                if (!c.JS_IsFunction(self.engine.context, callback)) continue;
                const input = try json.required(record, "input");
                const checkpoint = try json.required(try json.required(record, "state"), "checkpoint");
                const key = try migrationKey(self.engine.gpa, input, checkpoint, from);
                var known = false;
                for (definition.native.migrations.items) |migration| if (std.mem.eql(u8, migration.key, key)) {
                    known = true;
                    break;
                };
                if (known) {
                    self.engine.gpa.free(key);
                    continue;
                }
                errdefer self.engine.gpa.free(key);
                try definition.native.migrations.ensureUnusedCapacity(self.engine.gpa, 1);
                const input_value = try durable.jsValue(self.engine, input);
                defer self.engine.freeValue(input_value);
                const checkpoint_value = try durable.jsValue(self.engine, checkpoint);
                defer self.engine.freeValue(checkpoint_value);
                var args = [_]c.JSValue{ input_value, checkpoint_value, c.JS_NewInt64(self.engine.context, @intCast(from)) };
                const result = c.JS_Call(self.engine.context, callback, object, args.len, &args);
                var prepared: ?json.Owned = null;
                if (c.JS_IsException(result)) {
                    const exception = c.JS_GetException(self.engine.context);
                    self.engine.freeValue(exception);
                } else {
                    defer self.engine.freeValue(result);
                    prepared = try durable.owned(self.engine, result);
                }
                definition.native.migrations.appendAssumeCapacity(.{ .key = key, .value = prepared });
            }
        }
    }
    fn migrate(raw: ?*anyopaque, allocator: std.mem.Allocator, input: json.Value, checkpoint: json.Value, from: u64) !scheduling.Migrated {
        const self: *NativeDefinition = @ptrCast(@alignCast(raw.?));
        const key = try migrationKey(std.heap.page_allocator, input, checkpoint, from);
        defer std.heap.page_allocator.free(key);
        for (self.migrations.items) |migration| if (std.mem.eql(u8, migration.key, key)) {
            const value = migration.value orelse return error.TaskMigrationFailed;
            return .{ .input = try json.clone(allocator, try json.required(value.value, "input")), .checkpoint = try json.clone(allocator, try json.required(value.value, "checkpoint")) };
        };
        return error.TaskMigrationNotPrepared;
    }
    pub fn @"resume"(self: *Manager) !void {
        self.enabled = true;
        self.scheduler.enable();
        try self.start();
    }
    fn forward(raw: ?*anyopaque, event: *const session_mod.Publication) !void {
        const self: *Manager = @ptrCast(@alignCast(raw.?));
        var changes = try json.Owned.empty(std.heap.page_allocator);
        errdefer changes.deinit();
        changes.value = try json.clone(changes.arena.allocator(), event.changes);
        self.mutex.lockUncancelable(self.lease.value.io);
        // Native Session runs internal observers before external subscribers.
        // Usually the scheduler has already prepared this exact sequence's
        // index. The reverse order is also supported, without draining an
        // event before the corresponding internal tracking has completed.
        if (self.prepared_publication_index != null and self.prepared_publication_seq != event.seq) {
            self.mutex.unlock(self.lease.value.io);
            return error.PublicationOwnershipIndexSequenceMismatch;
        }
        const prepared = self.prepared_publication_index;
        self.events.append(std.heap.page_allocator, .{ .seq = event.seq, .changes = changes, .index = prepared, .ready = prepared != null or self.lease.value.ownerThread.load(.acquire) == 0 }) catch |err| {
            self.mutex.unlock(self.lease.value.io);
            return err;
        };
        self.prepared_publication_index = null;
        self.prepared_publication_seq = null;
        // The new publication's snapshot supersedes earlier load-only jobs.
        // Keeping one would restore older ownership after this event drains.
        if (self.pending_index) |*previous| previous.deinit();
        self.pending_index = null;
        self.mutex.unlock(self.lease.value.io);
        if (self.broker.notify.call) |notify| notify(self.broker.notify.context);
    }
    fn forwardIndex(raw: ?*anyopaque, seq: ?u64, index: *const owner_index.Index) !void {
        const self: *Manager = @ptrCast(@alignCast(raw.?));
        var copied = try index.duplicate(std.heap.page_allocator);
        errdefer copied.deinit();
        self.mutex.lockUncancelable(self.lease.value.io);
        if (seq) |committed| {
            for (self.events.items) |*event| if (event.seq == committed) {
                if (event.index) |*previous| previous.deinit();
                event.index = copied;
                event.ready = true;
                self.mutex.unlock(self.lease.value.io);
                if (self.broker.notify.call) |notify| notify(self.broker.notify.context);
                return;
            };
            if (self.prepared_publication_index != null) {
                self.mutex.unlock(self.lease.value.io);
                return error.PublicationOwnershipIndexOverlap;
            }
            self.prepared_publication_index = copied;
            self.prepared_publication_seq = committed;
            self.mutex.unlock(self.lease.value.io);
            return;
        }
        if (self.pending_index) |*previous| previous.deinit();
        self.pending_index = copied;
        self.mutex.unlock(self.lease.value.io);
        if (self.broker.notify.call) |notify| notify(self.broker.notify.context);
    }
    fn adoptIndex(self: *Manager, index: *?owner_index.Index) void {
        if (index.*) |next| {
            if (self.published_index) |*previous| previous.deinit();
            self.published_index = next;
            index.* = null;
        }
    }
    fn publishedIdle(self: *Manager, conversation: ?u64) !bool {
        const index = if (self.published_index) |*current| current else return error.TaskPublicationIndexUnavailable;
        return index.idle(self.engine.gpa, conversation);
    }
    fn publicationPending(self: *Manager) bool {
        self.mutex.lockUncancelable(self.lease.value.io);
        defer self.mutex.unlock(self.lease.value.io);
        return self.events.items.len != 0 and !self.events.items[0].ready;
    }
    pub fn deliver(raw: ?*anyopaque) !void {
        const self: *Manager = @ptrCast(@alignCast(raw.?));
        while (true) {
            self.mutex.lockUncancelable(self.lease.value.io);
            if (self.events.items.len == 0) {
                self.adoptIndex(&self.pending_index);
                self.mutex.unlock(self.lease.value.io);
                return;
            }
            if (!self.events.items[0].ready) {
                self.mutex.unlock(self.lease.value.io);
                return;
            }
            var event = self.events.orderedRemove(0);
            self.mutex.unlock(self.lease.value.io);
            defer event.deinit();
            self.adoptIndex(&event.index);
            try self.cachePublication(event.changes.value);
            const parent = try durable.state(self.engine, self.session);
            try durable.deliverPublication(parent, &.{ .seq = event.seq, .changes = event.changes.value });
        }
    }
    fn cachePublication(self: *Manager, changes: json.Value) !void {
        try @import("native_durable_documents.zig").adoptNativePublication(try durable.state(self.engine, self.session), changes);
        for (changes.array.items) |change| {
            const kind = try json.asString(try json.required(change, "type"));
            if (std.mem.eql(u8, kind, "task") or std.mem.eql(u8, kind, "conversation")) self.drive_requested = true;
        }
        if (self.published_index == null) self.published_index = owner_index.Index.init(self.engine.gpa);
        const index = &self.published_index.?;
        for (changes.array.items) |change| {
            if (!std.mem.eql(u8, try json.asString(try json.required(change, "type")), "conversation")) continue;
            const record = try json.required(change, "value");
            const id = try json.asInteger(try json.required(record, "id"));
            if (!index.edges.contains(id)) try index.setEdge(id, if (json.get(record, "owner")) |owner| try json.asInteger(try json.required(owner, "taskId")) else null);
        }
        for (changes.array.items) |change| {
            if (!std.mem.eql(u8, try json.asString(try json.required(change, "type")), "task")) continue;
            const record = try json.required(change, "value");
            const model = @import("../durable/task_state.zig");
            const status = try model.status(record);
            var members: std.ArrayList(u64) = .empty;
            defer members.deinit(self.engine.gpa);
            if (status == .waiting) for ((try json.required(try json.required(record, "state"), "on")).array.items) |member| try members.append(self.engine.gpa, try json.asInteger(member));
            try index.track(.{ .id = try model.number(record, "id"), .link = .{ .conversation = try model.number(record, "conversationId"), .owner = if (json.get(record, "owner")) |owner| try json.asInteger(owner) else null, .background = try model.flag(record, "background") }, .status = @enumFromInt(@intFromEnum(status)), .abort_requested = try model.flag(record, "abortRequested"), .failed_outcome = try model.failed(record), .wait_on = members.items });
        }
        try index.sweep();
        // The owner sees an immutable, owned committed publication. Retain
        // terminal task records for reads while the scheduler is committing.
        // This also prevents a fixed-period owner poll from starving behind
        // the refill driver's repeated Session transactions.
        for (changes.array.items) |change| {
            if (!std.mem.eql(u8, try json.asString(try json.required(change, "type")), "task")) continue;
            const record = try json.required(change, "value");
            const id = try json.asInteger(try json.required(record, "id"));
            try self.cacheLiveTaskRecord(record);
            // A serialized publication supersedes any earlier requested read.
            self.retireRead(id);
            _ = self.missing_tasks.remove(id);
            const status = try json.asString(try json.required(try json.required(record, "state"), "status"));
            if (!std.mem.eql(u8, status, "terminal")) {
                if (self.terminal_tasks.fetchRemove(id)) |removed| {
                    var previous = removed.value;
                    previous.deinit();
                }
                continue;
            }
            var waiting = false;
            for (self.waiters.items) |waiter| if (waiter.id == id) {
                waiting = true;
                break;
            };
            if (!waiting) continue;
            var snapshot = try json.Owned.empty(self.engine.gpa);
            errdefer snapshot.deinit();
            snapshot.value = try json.clone(snapshot.arena.allocator(), record);
            const entry = try self.terminal_tasks.getOrPut(self.engine.gpa, id);
            if (entry.found_existing) entry.value_ptr.deinit();
            entry.value_ptr.* = snapshot;
        }
        // Source resolves its waiters while observing the committed publication,
        // before finishing a phase aborts its invocation signal. A later poll
        // cannot decide which of those already-ordered events won.
        try settlePublishedWaiters(self, false);
    }
    fn clearLiveTaskRecords(self: *Manager) void {
        var records = self.live_task_records.valueIterator();
        while (records.next()) |record| record.deinit();
        self.live_task_records.clearRetainingCapacity();
    }
    fn cacheLiveTaskRecord(self: *Manager, record: json.Value) !void {
        if (self.closed) return;
        const id = try json.asInteger(try json.required(record, "id"));
        if (!try @import("../durable/task_state.zig").live(record)) {
            if (self.live_task_records.fetchRemove(id)) |removed| {
                var previous = removed.value;
                previous.deinit();
            }
            return;
        }
        var copied = try json.Owned.empty(self.engine.gpa);
        errdefer copied.deinit();
        copied.value = try json.clone(copied.arena.allocator(), record);
        const slot = try self.live_task_records.getOrPut(self.engine.gpa, id);
        if (slot.found_existing) slot.value_ptr.deinit();
        slot.value_ptr.* = copied;
    }
    fn requestWaiterRead(self: *Manager, id: u64) !void {
        if (self.pending_reads.contains(id)) return;
        try self.pending_reads.ensureUnusedCapacity(self.engine.gpa, 1);
        const query: ReadQuery = .{ .id = id, .generation = self.next_read_generation, .owner_generation = self.generation };
        self.mutex.lockUncancelable(self.lease.value.io);
        defer self.mutex.unlock(self.lease.value.io);
        try self.read_queries.append(std.heap.page_allocator, query);
        self.pending_reads.putAssumeCapacity(id, query.generation);
        self.next_read_generation += 1;
    }
    fn retireRead(self: *Manager, id: u64) void {
        _ = self.pending_reads.remove(id);
        self.mutex.lockUncancelable(self.lease.value.io);
        defer self.mutex.unlock(self.lease.value.io);
        var index = self.read_queries.items.len;
        while (index > 0) {
            index -= 1;
            if (self.read_queries.items[index].id == id) _ = self.read_queries.orderedRemove(index);
        }
    }
    fn pollReads(raw: ?*anyopaque, session: *session_mod.Session) !void {
        const self: *Manager = @ptrCast(@alignCast(raw.?));
        std.debug.assert(session == &self.lease.value);
        // The scheduler calls this on its existing serialized Session line.
        // It touches native owned DTOs only; it never calls the language VM.
        while (true) {
            self.mutex.lockUncancelable(self.lease.value.io);
            if (self.read_queries.items.len == 0) {
                self.mutex.unlock(self.lease.value.io);
                return;
            }
            self.read_replies.ensureUnusedCapacity(std.heap.page_allocator, 1) catch |err| {
                self.mutex.unlock(self.lease.value.io);
                return err;
            };
            const query = self.read_queries.orderedRemove(0);
            self.mutex.unlock(self.lease.value.io);
            if (query.owner_generation != self.generation) continue;
            const record = try session.storage.readTableRecord(std.heap.page_allocator, .task, query.id);
            self.mutex.lockUncancelable(self.lease.value.io);
            self.read_replies.appendAssumeCapacity(.{ .query = query, .record = record });
            self.mutex.unlock(self.lease.value.io);
        }
    }
    fn recoveredContext(raw: ?*anyopaque) !void {
        const self: *Manager = @ptrCast(@alignCast(raw.?));
        // The initial scans and recovery reads use Harness.open's original
        // Context. Subsequent scheduler work keeps its keyed values while
        // deliberately detaching the caller's abort signal, as actual Source.
        if (self.lease.adapter) |adapter| adapter.setBackgroundContext(self.context);
    }
    fn drainReads(self: *Manager) !void {
        while (true) {
            self.mutex.lockUncancelable(self.lease.value.io);
            if (self.read_replies.items.len == 0) {
                self.mutex.unlock(self.lease.value.io);
                return;
            }
            var reply = self.read_replies.orderedRemove(0);
            self.mutex.unlock(self.lease.value.io);
            defer if (reply.record) |*record| record.deinit();
            if (reply.query.owner_generation != self.generation) continue;
            const generation = self.pending_reads.get(reply.query.id) orelse continue;
            if (generation != reply.query.generation) continue;
            _ = self.pending_reads.remove(reply.query.id);
            if (reply.record) |record| {
                const id = try json.asInteger(try json.required(record.value, "id"));
                if (id != reply.query.id) return error.InvalidWaiterReadIdentity;
                const status = try json.asString(try json.required(try json.required(record.value, "state"), "status"));
                if (!std.mem.eql(u8, status, "terminal")) continue;
                const entry = try self.terminal_tasks.getOrPut(self.engine.gpa, id);
                if (entry.found_existing) entry.value_ptr.deinit();
                entry.value_ptr.* = record;
                reply.record = null;
            } else try self.missing_tasks.put(self.engine.gpa, reply.query.id, {});
        }
    }
    fn pollSignals(self: *Manager) !void {
        var watch_index = self.watches.items.len;
        while (watch_index > 0) {
            watch_index -= 1;
            const watch = self.watches.items[watch_index];
            const closed = try sdk.get(self.engine, watch.value, "closed");
            defer self.engine.freeValue(closed);
            const finished = c.JS_PromiseState(self.engine.context, closed) != c.JS_PROMISE_PENDING;
            if (!finished and watch.entry.runtime.isActive() and !self.closed) continue;
            if (!finished) {
                const stopped = try sdk.invoke(self.engine, watch.value, "stop", &.{});
                self.engine.freeValue(stopped);
            }
            _ = self.watches.orderedRemove(watch_index);
            self.engine.freeValue(watch.value);
            watch.entry.release();
        }
        var index = self.signals.items.len;
        while (index > 0) {
            index -= 1;
            if (index >= self.signals.items.len) continue;
            const signal = self.signals.items[index];
            if (signal.entry.runtime.isActive() and !signal.entry.runtime.context().aborted() and !self.closed) continue;
            const entry = signal.entry.retain();
            defer entry.release();
            const value = c.JS_DupValue(self.engine.context, signal.value);
            defer self.engine.freeValue(value);
            // A worker can enqueue its last publication after the outer drain
            // but before this acquire observes invocation retirement. Admit it
            // before firing the phase signal, as Source's commit observer does.
            if (!self.closed) try Manager.deliver(self);
            // The observer has enqueued this publication, but its ownership
            // tracking may still be finishing on the native line. Retiring the
            // signal now would cancel waits before that committed event wins.
            if (!self.closed and self.publicationPending()) continue;
            // Delivery and abort listeners may reenter this pump and retire or
            // reallocate the signal array. Re-find its retained private owner.
            if (self.signalIndex(entry, value) == null) continue;
            const aborted = try sdk.get(self.engine, value, "aborted");
            defer self.engine.freeValue(aborted);
            if (c.JS_ToBool(self.engine.context, aborted) == 0) {
                const failure = try endedError(self.engine, entry.runtime.taskId());
                defer self.engine.freeValue(failure);
                try aborts.abort(self.engine, value, failure);
            }
            if (!entry.runtime.isActive()) {
                const retired_index = self.signalIndex(entry, value) orelse continue;
                const retired = self.signals.orderedRemove(retired_index);
                self.engine.freeValue(retired.value);
                self.engine.freeValue(retired.context);
                retired.entry.release();
            }
            index = @min(index, self.signals.items.len);
        }
    }
    fn signalIndex(self: *Manager, entry: *Entry, value: c.JSValue) ?usize {
        for (self.signals.items, 0..) |signal, index| if (signal.entry == entry and c.JS_IsStrictEqual(self.engine.context, signal.value, value)) return index;
        return null;
    }
    fn pollSleepers(self: *Manager) !void {
        if (self.sleepers.items.len == 0) return;
        try self.updateClock();
        const now: f64 = @floatFromInt(Manager.nativeClock(self));
        var index = self.sleepers.items.len;
        while (index > 0) {
            index -= 1;
            const sleeper = self.sleepers.items[index];
            const runtime = runtimeState(self.engine, sleeper.runtime).?;
            const signal = try sdk.get(self.engine, sleeper.context, "abortSignal");
            defer self.engine.freeValue(signal);
            const aborted = try sdk.get(self.engine, signal, "aborted");
            defer self.engine.freeValue(aborted);
            const ended = self.closed or !runtime.entry.runtime.isActive();
            const canceled = c.JS_ToBool(self.engine.context, aborted) != 0;
            if (!ended and !canceled and !(sleeper.until - now <= 0)) continue;
            _ = self.sleepers.orderedRemove(index);
            runtime.entry.runtime.resumeWait();
            defer self.engine.freeValue(sleeper.runtime);
            defer self.engine.freeValue(sleeper.context);
            defer self.engine.freeValue(sleeper.resolve);
            defer self.engine.freeValue(sleeper.reject);
            const failure = if (canceled) try sdk.get(self.engine, signal, "reason") else if (ended) try endedError(self.engine, runtime.entry.runtime.taskId()) else c.pi_js_undefined();
            defer self.engine.freeValue(failure);
            var args = [_]c.JSValue{failure};
            const ignored = try self.engine.checked(c.JS_Call(self.engine.context, if (ended or canceled) sleeper.reject else sleeper.resolve, c.pi_js_undefined(), 1, &args));
            self.engine.freeValue(ignored);
        }
    }
    fn invoke(native: *NativeDefinition, runtime: *scheduling.Runtime, record: json.Value, is_abort: bool) !void {
        const self = native.manager;
        const entry = try self.engine.gpa.create(Entry);
        self.mutex.lockUncancelable(self.lease.value.io);
        const generation = self.next_invocation;
        self.next_invocation += 1;
        entry.* = .{ .manager = self.retain(), .runtime = runtime.retain(), .generation = generation, .definition = native.id };
        self.ledger.append(std.heap.page_allocator, entry) catch |err| {
            self.mutex.unlock(self.lease.value.io);
            entry.refs.store(1, .release);
            entry.release();
            return err;
        };
        self.mutex.unlock(self.lease.value.io);
        runtime.beginOwnerDispatch();
        defer {
            // A rejected queued request never reached the VM. An admitted
            // callback owns completion until its actual guest promise ends.
            if (entry.dispatch_phase.cmpxchgStrong(.pending, .done, .acq_rel, .acquire) == null) runtime.endOwnerDispatch();
            entry.active.store(false, .release);
            entry.release();
            if (self.broker.notify.call) |notify| notify(self.broker.notify.context);
        }
        var payload = try json.Owned.empty(std.heap.page_allocator);
        defer payload.deinit();
        payload.value = .{ .object = .empty };
        try payload.value.object.put(payload.arena.allocator(), "record", try json.clone(payload.arena.allocator(), record));
        try payload.value.object.put(payload.arena.allocator(), "abort", .{ .bool = is_abort });
        // Phase cancellation signals the guest, but does not finish an
        // admitted handler. Broker close still releases workers on shutdown;
        // the dispatch lease above then preserves the real guest join.
        var result = try self.broker.call(std.heap.page_allocator, .{ .owner_generation = self.generation, .task_id = runtime.taskId(), .invocation_generation = generation }, payload.value, null);
        result.deinit();
        try entry.awaitReply();
    }
    fn run(raw: ?*anyopaque, runtime: *scheduling.Runtime, record: json.Value, _: @import("../durable/types.zig").Context) !void {
        return invoke(@ptrCast(@alignCast(raw.?)), runtime, record, false);
    }
    fn abort(raw: ?*anyopaque, runtime: *scheduling.Runtime, record: json.Value, _: @import("../durable/types.zig").Context) !void {
        return invoke(@ptrCast(@alignCast(raw.?)), runtime, record, true);
    }
    fn dispatch(raw: ?*anyopaque, identity: broker_mod.Identity, payload: json.Value, _: *const std.atomic.Value(bool)) !json.Owned {
        const self: *Manager = @ptrCast(@alignCast(raw.?));
        std.debug.assert(std.Thread.getCurrentId() == self.broker.owner);
        self.active_dispatches += 1;
        var admitted = false;
        defer if (!admitted) {
            self.active_dispatches -= 1;
        };
        self.mutex.lockUncancelable(self.lease.value.io);
        var found: ?*Entry = null;
        for (self.ledger.items) |entry| if (entry.generation == identity.invocation_generation and entry.runtime.taskId() == identity.task_id and entry.active.load(.acquire)) {
            found = entry.retain();
            break;
        };
        self.mutex.unlock(self.lease.value.io);
        const entry = found orelse return error.StaleTaskInvocation;
        defer if (!admitted) entry.release();
        if (entry.dispatch_phase.cmpxchgStrong(.pending, .active, .acq_rel, .acquire) != null) return error.StaleTaskInvocation;
        defer if (!admitted) {
            entry.dispatch_phase.store(.done, .release);
            entry.runtime.endOwnerDispatch();
            entry.finishReply(null);
        };
        if (identity.owner_generation != self.generation or self.closed) return error.StaleTaskOwner;
        // One broker drain can serve consecutive phases before the outer pump
        // runs again. Refresh at this boundary before admitting an old token.
        try self.refreshRegistry();
        if (self.closed) return error.StaleTaskOwner;
        const token = self.definitions.items[entry.definition].token;
        const task_record = try json.required(payload, "record");
        const kind = try sdk.text(self.engine, try json.asString(try json.required(task_record, "kind")));
        defer self.engine.freeValue(kind);
        const current = try sdk.invoke(self.engine, self.snapshot, "task", &.{kind});
        defer self.engine.freeValue(current);
        if (!c.JS_IsStrictEqual(self.engine.context, token, current)) {
            try entry.runtime.requeueForRegistryChange();
            return json.Owned.empty(self.engine.gpa);
        }
        const definition = try sdk.get(self.engine, token, "definition");
        defer self.engine.freeValue(definition);
        const abort_mode = (try json.required(payload, "abort")).bool;
        var function: c.JSValue = undefined;
        if (abort_mode) function = try sdk.get(self.engine, definition, "abort") else {
            const phases = try sdk.get(self.engine, definition, "phases");
            defer self.engine.freeValue(phases);
            const phase = try json.asString(try json.required(try json.required(try json.required(task_record, "state"), "checkpoint"), "phase"));
            const name = try self.engine.gpa.dupeZ(u8, phase);
            defer self.engine.gpa.free(name);
            function = try sdk.get(self.engine, phases, name);
        }
        defer self.engine.freeValue(function);
        const runtime = try runtimeObject(self, entry, task_record);
        defer self.engine.freeValue(runtime);
        const runtime_state = runtimeState(self.engine, runtime).?;
        const context = runtime_state.context;
        const record = try durable.jsValue(self.engine, task_record);
        defer self.engine.freeValue(record);
        const phase = try self.engine.gpa.create(PendingPhase);
        errdefer self.engine.gpa.destroy(phase);
        var acknowledgment = try json.Owned.empty(self.engine.gpa);
        errdefer acknowledgment.deinit();
        const allocation_generation = self.engine.native_allocation_generation;
        var args = [_]c.JSValue{ record, runtime, context };
        const returned = try self.engine.checked(c.JS_Call(self.engine.context, function, c.pi_js_undefined(), args.len, &args));
        defer self.engine.freeValue(returned);
        // Native promises are observed directly, without reading a mutable
        // global Promise, an own .then property, or Symbol.species. Only an
        // actual thenable needs intrinsic capability resolution/assimilation.
        const promise = if (c.JS_IsPromise(returned)) c.JS_DupValue(self.engine.context, returned) else try sdk.promise(self.engine, returned);
        c.JS_PromiseMarkAsHandled(self.engine.context, promise);
        phase.* = .{ .entry = entry, .promise = promise, .runtime_value = c.JS_DupValue(self.engine.context, runtime), .context = c.JS_DupValue(self.engine.context, context), .allocation_generation = allocation_generation };
        if (self.last_phase) |last| last.next = phase else self.first_phase = phase;
        self.last_phase = phase;
        admitted = true;
        return acknowledgment;
    }
    fn finishPhase(self: *Manager, phase: *PendingPhase, failure: ?anyerror) void {
        phase.entry.dispatch_phase.store(.done, .release);
        phase.entry.runtime.endOwnerDispatch();
        self.active_dispatches -= 1;
        phase.entry.finishReply(failure);
        self.engine.freeValue(phase.promise);
        self.engine.freeValue(phase.runtime_value);
        self.engine.freeValue(phase.context);
        phase.entry.release();
        self.engine.gpa.destroy(phase);
    }
    fn pollPhases(self: *Manager) !bool {
        var worked = false;
        var previous: ?*PendingPhase = null;
        var current = self.first_phase;
        while (current) |phase| {
            const status = c.JS_PromiseState(self.engine.context, phase.promise);
            if (status == c.JS_PROMISE_PENDING) {
                previous = phase;
                current = phase.next;
                continue;
            }
            const next = phase.next;
            if (previous) |slot| slot.next = next else self.first_phase = next;
            if (self.last_phase == phase) self.last_phase = previous;
            phase.next = null;
            var failure: ?anyerror = null;
            if (status == c.JS_PROMISE_REJECTED) {
                const reason = c.JS_PromiseResult(self.engine.context, phase.promise);
                defer self.engine.freeValue(reason);
                _ = self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason))) catch {};
                failure = self.engine.nativeAllocationError(error.JavaScriptException, phase.allocation_generation);
            }
            self.finishPhase(phase, failure);
            worked = true;
            current = self.first_phase;
            previous = null;
        }
        return worked;
    }
    fn discardPhases(self: *Manager) void {
        // Engine teardown only. Public close continues polling real promises.
        while (self.first_phase) |phase| {
            self.first_phase = phase.next;
            if (self.first_phase == null) self.last_phase = null;
            phase.next = null;
            self.finishPhase(phase, error.OwnerBrokerClosed);
        }
    }
    pub fn retire(self: *Manager) void {
        if (self.closed) return;
        self.closed = true;
        self.clearLiveTaskRecords();
        if (durable.state(self.engine, self.session)) |native| {
            // Source's failed promise ends an already-observing abort join at
            // failure admission, before cleanup can finish the held run.
            if (native.failure_reason != null) _ = self.task_aborts.pump(self) catch false;
        } else |_| {}
        self.rejectClosingWaiters() catch {};
        const control_reason = schedulerClosedError(self) catch null;
        if (control_reason) |reason| {
            defer self.engine.freeValue(reason);
            self.abort_controls.close(self.engine, reason) catch {};
        }
        if (self.vm_owner) |value| {
            self.vm_owner = null;
            self.engine.freeValue(value);
        }
        var contexts = self.contexts.valueIterator();
        while (contexts.next()) |slot| if (slot.*) |cached| self.engine.freeValue(cached.view);
        self.contexts.clearRetainingCapacity();
        for (self.watches.items) |watch| {
            if (sdk.invoke(self.engine, watch.value, "stop", &.{})) |stopped| self.engine.freeValue(stopped) else |_| {}
            self.engine.freeValue(watch.value);
            watch.entry.release();
        }
        self.watches.clearRetainingCapacity();
        self.scheduler.close();
        self.broker.close();
        self.mutex.lockUncancelable(self.lease.value.io);
        for (self.ledger.items) |entry| entry.finishReply(error.OwnerBrokerClosed);
        self.mutex.unlock(self.lease.value.io);
    }
    /// Final native teardown runs after owner callbacks have unwound. Public
    /// Session close uses retire plus an owner-pumped join promise instead.
    pub fn close(self: *Manager) void {
        self.retire();
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
        self.settleJoins() catch {};
    }
    fn joinPromise(self: *Manager) !c.JSValue {
        if (self.closed and self.thread == null and self.active_dispatches == 0) return sdk.promise(self.engine, c.pi_js_undefined());
        var functions: [2]c.JSValue = undefined;
        const pending = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &functions));
        errdefer self.engine.freeValue(pending);
        defer for (functions) |function| self.engine.freeValue(function);
        try self.join_waiters.ensureUnusedCapacity(self.engine.gpa, 1);
        self.join_waiters.appendAssumeCapacity(c.JS_DupValue(self.engine.context, functions[0]));
        return pending;
    }
    fn settleJoins(self: *Manager) !void {
        if (!self.closed or self.thread != null or self.active_dispatches != 0) return;
        while (self.join_waiters.items.len > 0) {
            const resolve = self.join_waiters.orderedRemove(0);
            defer self.engine.freeValue(resolve);
            const ignored = try self.engine.checked(c.JS_Call(self.engine.context, resolve, c.pi_js_undefined(), 0, null));
            self.engine.freeValue(ignored);
        }
    }
    fn rejectClosingWaiters(self: *Manager) !void {
        if (self.waiters.items.len == 0) return;
        const failure = try schedulerClosedError(self);
        defer self.engine.freeValue(failure);
        var arguments = [_]c.JSValue{failure};
        for (self.waiters.items) |waiter| {
            const result = try self.engine.checked(c.JS_Call(self.engine.context, waiter.reject, c.pi_js_undefined(), arguments.len, &arguments));
            self.engine.freeValue(result);
        }
    }
};
const SchedulerOwner = struct { manager: *Manager, session: c.JSValue };
const SchedulerMethod = enum(c_int) { open, @"resume", join, abort, waitForTask, waitForIdle, abortConversation, inspect };
fn schedulerOwnerFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const owner: *SchedulerOwner = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_scheduler_class) orelse return));
    c.JS_FreeValueRT(runtime, owner.session);
    owner.manager.release();
    engine.gpa.destroy(owner);
}
fn schedulerOwnerMark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const owner: *SchedulerOwner = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_scheduler_class) orelse return));
    c.JS_MarkValue(runtime, owner.session, marker);
}
fn schedulerConstruct(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return durable.reject(Engine.fromContext(context.?), error.NativeTaskSchedulerDirectConstructionUnavailable);
}
fn registerSchedulerOwner(engine: *Engine) !void {
    if (engine.native_durable_scheduler_class != 0) return;
    var class_id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class_id);
    const definition: c.JSClassDef = .{ .class_name = "TaskScheduler", .finalizer = schedulerOwnerFinalizer, .gc_mark = schedulerOwnerMark, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    const prototype = try sdk.object(engine);
    errdefer engine.freeValue(prototype);
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, schedulerConstruct, "TaskScheduler", 1, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(constructor);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return @import("native_js_values.zig").capture(engine);
    inline for (std.meta.fields(SchedulerMethod)) |field| {
        const operation: SchedulerMethod = @enumFromInt(field.value);
        const arity: c_int = switch (operation) {
            .@"resume", .join => 0,
            .open, .inspect => 1,
            .abort, .waitForTask, .waitForIdle => 2,
            .abortConversation => 3,
        };
        const method = try engine.checked(c.pi_js_function_magic(engine.context, schedulerMethod, field.name, arity, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, method, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    }
    c.JS_SetClassProto(engine.context, class_id, prototype);
    engine.native_durable_scheduler_class = class_id;
}
fn schedulerOwner(self: *Manager) !c.JSValue {
    if (self.vm_owner) |value| return c.JS_DupValue(self.engine.context, value);
    const engine = self.engine;
    try registerSchedulerOwner(engine);
    const value = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_scheduler_class));
    errdefer engine.freeValue(value);
    const owner = try engine.gpa.create(SchedulerOwner);
    owner.* = .{ .manager = self.retain(), .session = c.JS_DupValue(engine.context, self.session) };
    _ = c.JS_SetOpaque(value, owner);
    self.vm_owner = value;
    return c.JS_DupValue(engine.context, value);
}
fn schedulerMethod(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return schedulerMethodOwned(engine, receiver, @enumFromInt(magic), argv[0..@intCast(argc)]) catch |err| if (magic == @intFromEnum(SchedulerMethod.@"resume") or magic == @intFromEnum(SchedulerMethod.waitForIdle)) durable.reject(engine, err) else durable.rejectedPromise(engine, err);
}
fn schedulerMethodOwned(engine: *Engine, receiver: c.JSValue, operation: SchedulerMethod, args: []const c.JSValue) !c.JSValue {
    const owner: *SchedulerOwner = @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, receiver, engine.native_durable_scheduler_class) orelse return error.JavaScriptException));
    const manager = owner.manager;
    if (!c.JS_IsStrictEqual(engine.context, owner.session, manager.session)) return error.InvalidTaskSchedulerSession;
    switch (operation) {
        .@"resume" => {
            try manager.@"resume"();
            return c.pi_js_undefined();
        },
        .waitForTask => return wait(manager, try durable.number(engine, if (args.len > 0) args[0] else c.pi_js_undefined()), null, if (args.len > 1) args[1] else c.pi_js_undefined()),
        .waitForIdle => return wait(manager, null, if (args.len > 0 and !c.JS_IsUndefined(args[0])) try durable.number(engine, args[0]) else null, if (args.len > 1) args[1] else c.pi_js_undefined()),
        .abortConversation => return @import("native_durable_abort_control.zig").abortConversation(manager, try durable.number(engine, if (args.len > 0) args[0] else c.pi_js_undefined()), args.len > 1 and c.JS_ToBool(engine.context, args[1]) != 0, if (args.len > 2) args[2] else c.pi_js_undefined()),
        .open, .join, .abort, .inspect => return error.NativeTaskSchedulerMethodUnavailable,
    }
}
const Hub = struct {
    engine: *Engine,
    managers: std.ArrayList(*Manager) = .empty,
    next_generation: u64 = 1,
    fn pump(engine: *Engine) !bool {
        const self: *Hub = @ptrCast(@alignCast(engine.native_durable_control_context.?));
        var worked = false;
        for (self.managers.items) |manager| {
            if (!manager.closed) try manager.refreshRegistry();
            if (try manager.pollPhases()) worked = true;
            try Manager.deliver(manager);
            if (try manager.abort_controls.pump(manager)) worked = true;
            if (try manager.task_aborts.pump(manager)) worked = true;
            try Manager.deliver(manager);
            try manager.pollSignals();
            try manager.pollSleepers();
            if (try manager.broker.drain(Manager.dispatch, manager)) worked = true;
            if (manager.thread != null and manager.finished.load(.acquire)) {
                manager.thread.?.join();
                manager.thread = null;
                worked = true;
            }
            while (true) {
                manager.mutex.lockUncancelable(manager.lease.value.io);
                if (manager.events.items.len == 0) {
                    manager.adoptIndex(&manager.pending_index);
                    manager.mutex.unlock(manager.lease.value.io);
                    break;
                }
                if (!manager.events.items[0].ready) {
                    manager.mutex.unlock(manager.lease.value.io);
                    break;
                }
                var event = manager.events.orderedRemove(0);
                manager.mutex.unlock(manager.lease.value.io);
                defer event.deinit();
                manager.adoptIndex(&event.index);
                try manager.cachePublication(event.changes.value);
                const parent = try durable.state(engine, manager.session);
                try durable.deliverPublication(parent, &.{ .seq = event.seq, .changes = event.changes.value });
                worked = true;
            }
            manager.mutex.lockUncancelable(manager.lease.value.io);
            var index = manager.ledger.items.len;
            while (index > 0) {
                index -= 1;
                const entry = manager.ledger.items[index];
                if (!entry.active.load(.acquire)) {
                    _ = manager.ledger.orderedRemove(index);
                    entry.release();
                }
            }
            manager.mutex.unlock(manager.lease.value.io);
            try manager.settleJoins();
            try manager.drainReads();
            try settleWaiters(manager);
            if (!manager.closed and manager.thread == null and manager.enabled and (manager.drive_requested or manager.last_count > 0)) try manager.start();
        }
        return worked;
    }
    fn deinit(engine: *Engine) void {
        const self: *Hub = @ptrCast(@alignCast(engine.native_durable_control_context.?));
        for (self.managers.items) |manager| {
            manager.close();
            manager.mutex.lockUncancelable(manager.lease.value.io);
            for (manager.ledger.items) |entry| entry.release();
            manager.ledger.clearRetainingCapacity();
            manager.mutex.unlock(manager.lease.value.io);
            manager.discardPhases();
            const session = durable.state(engine, manager.session) catch unreachable;
            session.foreign_publication = null;
            session.foreign_publication_context = null;
            session.after_commit = null;
            session.session.?.source_clock = null;
            session.session.?.source_clock_context = null;
            for (manager.signals.items) |signal| {
                engine.freeValue(signal.value);
                engine.freeValue(signal.context);
                signal.entry.release();
            }
            manager.signals.clearRetainingCapacity();
            for (manager.definitions.items) |*definition| {
                engine.freeValue(definition.token);
                definition.token = c.pi_js_undefined();
            }
            engine.freeValue(manager.snapshot);
            engine.freeValue(manager.registry);
            engine.freeValue(manager.options);
            engine.freeValue(manager.context);
            engine.freeValue(manager.session);
            engine.freeValue(manager.clock_callback);
            for (manager.waiters.items) |waiter| {
                engine.freeValue(waiter.resolve);
                engine.freeValue(waiter.reject);
                engine.freeValue(waiter.context);
            }
            manager.waiters.clearRetainingCapacity();
            for (manager.sleepers.items) |sleeper| {
                runtimeState(engine, sleeper.runtime).?.entry.runtime.resumeWait();
                engine.freeValue(sleeper.runtime);
                engine.freeValue(sleeper.context);
                engine.freeValue(sleeper.resolve);
                engine.freeValue(sleeper.reject);
            }
            manager.sleepers.clearRetainingCapacity();
            manager.release();
        }
        self.managers.deinit(engine.gpa);
        engine.gpa.destroy(self);
    }
};
test "native durable VM observed guest dispatch remains joined after native workers exit on close" {
    const Fixture = struct {
        fn workerExited(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const engine = Engine.fromContext(context.?);
            const raw = engine.native_durable_control_context orelse return c.pi_js_bool(context, 0);
            const owner: *Hub = @ptrCast(@alignCast(raw));
            for (owner.managers.items) |manager| if (manager.closed and manager.finished.load(.acquire) and manager.active_dispatches > 0) return c.pi_js_bool(context, 1);
            return c.pi_js_bool(context, 0);
        }
    };
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    try @import("timers.zig").install(engine, std.testing.io);
    try engine.bindFunction("nativeGuestWorkerExited", Fixture.workerExited, 0);
    const output = engine.evalModule(@embedFile("../durable/fixtures/durable-custom-storage-source42-program.txt"), "actual-guest-dispatch-close-join") catch |err| {
        std.debug.print("Actual Source42 guest dispatch {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        if (engine.native_durable_control_context) |raw| {
            const owner: *Hub = @ptrCast(@alignCast(raw));
            for (owner.managers.items) |manager| {
                std.debug.print("Source42 manager closed={} workerFinished={} joined={} guestDispatches={d}\n", .{ manager.closed, manager.finished.load(.acquire), manager.thread == null, manager.active_dispatches });
                var pending = manager.first_phase;
                while (pending) |phase| : (pending = phase.next) std.debug.print("Source42 task={d} phasePromiseState={d} workerEntryActive={}\n", .{ phase.entry.runtime.taskId(), c.JS_PromiseState(engine.context, phase.promise), phase.entry.active.load(.acquire) });
            }
        }
        return err;
    };
    engine.freeValue(output);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "taskAbortTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("../durable/fixtures/durable-custom-storage-source42.json"));
    defer expected.deinit();
    if (!json.equal(expected.value, actual.value)) {
        const text = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(text);
        std.debug.print("Actual observed guest dispatch join: {s}\n", .{text});
        return error.SourceGuestDispatchJoinMismatch;
    }
}
fn hub(engine: *Engine) !*Hub {
    if (engine.native_durable_control_context) |pointer| return @ptrCast(@alignCast(pointer));
    const self = try engine.gpa.create(Hub);
    self.* = .{ .engine = engine };
    engine.native_durable_control_context = self;
    engine.native_durable_control_pump = Hub.pump;
    engine.native_durable_control_deinit = Hub.deinit;
    return self;
}
pub fn getManager(engine: *Engine, session: c.JSValue) !*Manager {
    const owner = try hub(engine);
    for (owner.managers.items) |item| if (c.JS_IsStrictEqual(engine.context, item.session, session)) return item;
    return error.TaskManagerUnavailable;
}
/// Close admission retires the scheduler before the storage queue is drained.
/// A session without a task manager has nothing to retire.
pub fn retireSession(engine: *Engine, session: c.JSValue) void {
    if (engine.native_durable_control_context == null) return;
    const owner: *Hub = @ptrCast(@alignCast(engine.native_durable_control_context.?));
    for (owner.managers.items) |manager| {
        if (c.JS_IsStrictEqual(engine.context, manager.session, session)) manager.retire();
    }
}
/// Allocated before close seals admission, so a host allocation failure cannot
/// abandon mandatory cleanup after the Session is already closing.
pub fn retirementPromise(engine: *Engine, session: c.JSValue) !c.JSValue {
    if (engine.native_durable_control_context == null) return c.pi_js_undefined();
    const owner: *Hub = @ptrCast(@alignCast(engine.native_durable_control_context.?));
    for (owner.managers.items) |manager| if (c.JS_IsStrictEqual(engine.context, manager.session, session)) return manager.joinPromise();
    return c.pi_js_undefined();
}
pub fn attach(engine: *Engine, session: c.JSValue, options: c.JSValue, context: c.JSValue) !void {
    if (!engine.abort_signals_ready) try aborts.install(engine);
    try registerRuntimeClass(engine);
    const owner = try hub(engine);
    const native = try durable.state(engine, session);
    if (native.session_lease.?.adapter) |adapter| adapter.setBackgroundContext(context);
    const self = try engine.gpa.create(Manager);
    errdefer engine.gpa.destroy(self);
    const registry = try sdk.get(engine, options, "registry");
    errdefer engine.freeValue(registry);
    const snapshot = try sdk.invoke(engine, registry, "snapshot", &.{});
    errdefer engine.freeValue(snapshot);
    const clock_callback = try sdk.get(engine, options, "now");
    errdefer engine.freeValue(clock_callback);
    const scheduler_context = try @import("native_durable_context.zig").withoutAbortSignal(engine, context);
    var context_admitted = false;
    errdefer if (!context_admitted) engine.freeValue(scheduler_context);
    self.* = .{ .engine = engine, .hub = owner, .lease = native.session_lease.?.retain(), .session = c.JS_DupValue(engine.context, session), .options = c.JS_DupValue(engine.context, options), .context = scheduler_context, .registry = registry, .snapshot = snapshot, .generation = owner.next_generation, .clock_callback = clock_callback, .custom_clock = !c.JS_IsUndefined(clock_callback), .scheduler = try scheduling.Scheduler.init(engine.gpa, native.session.?.io, native.session.?, .{ .callback_context = self, .poll_reads = Manager.pollReads, .index_changed = Manager.forwardIndex, .after_recover = Manager.recoveredContext, .withdraw_inputs = if (native.creation_owner != null) @import("../durable/harness/inbox_native.zig").withdraw else null }), .broker = broker_mod.Broker.init(engine.gpa, native.session.?.io, owner.next_generation, .{ .context = engine.host_owner_notify_context, .call = engine.host_owner_notify }) };
    owner.next_generation += 1;
    context_admitted = true;
    errdefer {
        self.closed = true;
        self.clearLiveTaskRecords();
        self.live_task_records.deinit(engine.gpa);
        if (self.published_index) |*index| index.deinit();
        if (self.pending_index) |*index| index.deinit();
        if (self.prepared_publication_index) |*index| index.deinit();
        for (self.events.items) |*event| event.deinit();
        self.events.deinit(std.heap.page_allocator);
        self.scheduler.deinit();
        for (self.definitions.items) |definition| {
            engine.freeValue(definition.token);
            engine.gpa.destroy(definition.native);
        }
        self.definitions.deinit(engine.gpa);
        self.broker.deinit();
        self.lease.release();
        engine.freeValue(self.session);
        engine.freeValue(self.options);
        engine.freeValue(self.context);
    }
    try loadDefinitions(self);
    try self.updateClock();
    try owner.managers.ensureUnusedCapacity(engine.gpa, 1);
    native.foreign_publication = Manager.forward;
    native.foreign_publication_context = self;
    native.after_commit = Manager.deliver;
    native.session.?.source_clock = Manager.nativeClock;
    native.session.?.source_clock_context = self;
    errdefer {
        native.foreign_publication = null;
        native.foreign_publication_context = null;
        native.after_commit = null;
        native.session.?.source_clock = null;
        native.session.?.source_clock_context = null;
    }
    if (native.session_lease.?.adapter) |adapter| try adapter.loadSchedulerRecords(false);
    try self.scheduler.open();
    const initial = try self.lease.value.storage.snapshot(engine.gpa);
    defer initial.destroy(engine.gpa);
    if (self.published_index) |*index| index.deinit();
    self.published_index = try self.scheduler.ownership_index.duplicate(engine.gpa);
    if (self.pending_index) |*index| index.deinit();
    self.pending_index = null;
    var rows = initial.rows.iterator();
    while (rows.next()) |row| {
        const table = row.value_ptr.table;
        if (table != .task and table != .conversation) continue;
        if (table == .task) try self.cacheLiveTaskRecord(row.value_ptr.record);
    }
    owner.managers.appendAssumeCapacity(self);
}
fn loadDefinitions(self: *Manager) !void {
    const engine = self.engine;
    const tasks = try sdk.invoke(engine, self.snapshot, "tasks", &.{});
    defer engine.freeValue(tasks);
    for (0..try sdk.length(engine, tasks)) |index| {
        const token = try engine.checked(c.JS_GetPropertyUint32(engine.context, tasks, @intCast(index)));
        var known = false;
        for (self.definitions.items) |existing| if (c.JS_IsStrictEqual(engine.context, existing.token, token)) {
            known = true;
            break;
        };
        if (known) {
            engine.freeValue(token);
            continue;
        }
        errdefer engine.freeValue(token);
        const definition = try sdk.get(engine, token, "definition");
        defer engine.freeValue(definition);
        const name_value = try sdk.get(engine, definition, "name");
        defer engine.freeValue(name_value);
        const name = try engine.toString(name_value);
        defer engine.gpa.free(name);
        const version_value = try sdk.get(engine, definition, "version");
        defer engine.freeValue(version_value);
        const version = try durable.number(engine, version_value);
        const phases = try sdk.get(engine, definition, "phases");
        defer engine.freeValue(phases);
        var properties: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, phases, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(engine.context, properties, count);
        var native_phases: std.ArrayList(scheduling.Phase) = .empty;
        defer {
            for (native_phases.items) |phase| engine.gpa.free(phase.name);
            native_phases.deinit(engine.gpa);
        }
        for (0..count) |property| {
            const string = c.JS_AtomToCString(engine.context, properties[property].atom) orelse return error.OutOfMemory;
            defer c.JS_FreeCString(engine.context, string);
            const owned_name = try engine.gpa.dupe(u8, std.mem.span(string));
            errdefer engine.gpa.free(owned_name);
            try native_phases.append(engine.gpa, .{ .name = owned_name, .run = Manager.run });
        }
        const context = try engine.gpa.create(NativeDefinition);
        errdefer engine.gpa.destroy(context);
        context.* = .{ .manager = self, .id = self.definitions.items.len };
        try self.definitions.ensureUnusedCapacity(engine.gpa, 1);
        const migration = try sdk.get(engine, definition, "migrate");
        defer engine.freeValue(migration);
        try self.scheduler.register(.{ .name = name, .version = version, .phases = native_phases.items, .abort = Manager.abort, .migrate = if (c.JS_IsFunction(engine.context, migration)) Manager.migrate else null, .context = context });
        self.definitions.appendAssumeCapacity(.{ .native = context, .token = token });
    }
}
pub fn createTask(engine: *Engine, _: c.JSValue, transaction: c.JSValue, args: []const c.JSValue) !c.JSValue {
    if (args.len < 3) return error.InvalidCreateTaskArguments;
    const tx = try durable.state(engine, transaction);
    const token = args[0];
    const definition = try sdk.get(engine, token, "definition");
    defer engine.freeValue(definition);
    const options_value = try durable.owned(engine, args[2]);
    defer {
        var value = options_value;
        value.deinit();
    }
    const ownership = try json.required(options_value.value, "ownership");
    const ownership_kind = try json.asString(try json.required(ownership, "kind"));
    const task_options: session_mod.TaskOptions = .{ .conversationId = if (json.get(options_value.value, "conversationId")) |id| try json.asInteger(id) else null, .ownerTaskId = if (std.mem.eql(u8, ownership_kind, "task")) try json.asInteger(try json.required(ownership, "taskId")) else null, .background = if (json.get(options_value.value, "background")) |value| value.bool else false, .abandonOnRestart = if (json.get(options_value.value, "abandonOnRestart")) |value| value == .bool and value.bool else false };
    _ = try tx.transaction.?.taskConversation(task_options);
    const initial = try sdk.get(engine, definition, "initial");
    defer engine.freeValue(initial);
    var inputs = [_]c.JSValue{args[1]};
    const checkpoint = try engine.checked(c.JS_Call(engine.context, initial, definition, 1, &inputs));
    defer engine.freeValue(checkpoint);
    var input = try durable.owned(engine, args[1]);
    defer input.deinit();
    var state = try durable.owned(engine, checkpoint);
    defer state.deinit();
    const name_value = try sdk.get(engine, definition, "name");
    defer engine.freeValue(name_value);
    const name = try engine.toString(name_value);
    defer engine.gpa.free(name);
    const version_value = try sdk.get(engine, definition, "version");
    defer engine.freeValue(version_value);
    const id = try tx.transaction.?.createTask(name, try durable.number(engine, version_value), input.value, state.value, task_options);
    const value = c.JS_NewInt64(engine.context, @intCast(id));
    return sdk.promise(engine, value);
}
fn registerRuntimeClass(engine: *Engine) !void {
    if (engine.native_durable_runtime_class != 0) return;
    _ = c.JS_NewClassID(engine.runtime, &engine.native_durable_runtime_class);
    const definition: c.JSClassDef = .{ .class_name = "Native durable TaskRuntime", .finalizer = runtimeFinalizer, .gc_mark = runtimeMark, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, engine.native_durable_runtime_class, &definition) < 0) return error.OutOfMemory;
}
fn runtimeState(engine: *Engine, value: c.JSValue) ?*Runtime {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_runtime_class)));
}
fn runtimeFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self = runtimeState(engine, value) orelse return;
    c.JS_FreeValueRT(runtime, self.session);
    c.JS_FreeValueRT(runtime, self.signal);
    c.JS_FreeValueRT(runtime, self.context);
    c.JS_FreeValueRT(runtime, self.agent);
    c.JS_FreeValueRT(runtime, self.snapshot);
    self.entry.release();
    engine.gpa.destroy(self);
}
fn runtimeMark(runtime: ?*c.JSRuntime, value: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self = runtimeState(engine, value) orelse return;
    c.JS_MarkValue(runtime, self.session, mark);
    c.JS_MarkValue(runtime, self.signal, mark);
    c.JS_MarkValue(runtime, self.context, mark);
    c.JS_MarkValue(runtime, self.agent, mark);
    c.JS_MarkValue(runtime, self.snapshot, mark);
}
fn runtimeObject(self: *Manager, entry: *Entry, record: json.Value) !c.JSValue {
    const engine = self.engine;
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_runtime_class));
    errdefer engine.freeValue(object);
    const runtime = try engine.gpa.create(Runtime);
    errdefer engine.gpa.destroy(runtime);
    var signal = c.pi_js_undefined();
    var invocation_context = c.pi_js_undefined();
    var existing = false;
    for (self.signals.items) |live| if (live.entry.runtime.invocation == entry.runtime.invocation) {
        signal = c.JS_DupValue(engine.context, live.value);
        invocation_context = c.JS_DupValue(engine.context, live.context);
        existing = true;
        break;
    };
    if (!existing) {
        signal = try aborts.create(engine);
        invocation_context = @import("native_durable_context.zig").withAbortSignal(engine, signal, self.context) catch |err| {
            engine.freeValue(signal);
            return err;
        };
    }
    errdefer engine.freeValue(signal);
    errdefer engine.freeValue(invocation_context);
    try self.signals.ensureUnusedCapacity(engine.gpa, 1);
    try sdk.put(engine, object, "signal", c.JS_DupValue(engine.context, signal));
    try sdk.put(engine, object, "taskId", c.JS_NewInt64(engine.context, @intCast(entry.runtime.taskId())));
    try sdk.put(engine, object, "conversationId", c.JS_NewInt64(engine.context, @intCast(try json.asInteger(try json.required(record, "conversationId")))));
    const registry_atom = c.JS_NewAtom(engine.context, "registry");
    defer c.JS_FreeAtom(engine.context, registry_atom);
    var registry_data = [_]c.JSValue{self.snapshot};
    const registry_getter = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeRegistryGetter, 0, 0, registry_data.len, &registry_data));
    if (c.JS_DefinePropertyGetSet(engine.context, object, registry_atom, registry_getter, c.pi_js_undefined(), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    try sdk.put(engine, object, "models", try sdk.get(engine, self.options, "models"));
    const settings_atom = c.JS_NewAtom(engine.context, "settings");
    defer c.JS_FreeAtom(engine.context, settings_atom);
    var settings_data = [_]c.JSValue{self.options};
    const settings_getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, runtimeSettingsGetter, "get settings", 0, 0, settings_data.len, &settings_data));
    var bound_data = [_]c.JSValue{object};
    if (c.JS_DefinePropertyGetSet(engine.context, object, settings_atom, settings_getter, c.pi_js_undefined(), c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
    try sdk.put(engine, object, "commit", try engine.checked(c.JS_NewCFunctionData2(engine.context, runtimeCommit, "commit", 2, 0, bound_data.len, &bound_data)));
    const hooks = try sdk.object(engine);
    defer engine.freeValue(hooks);
    var hook_data = [_]c.JSValue{object};
    try sdk.put(engine, hooks, "each", try engine.checked(c.JS_NewCFunctionData(engine.context, hooksEach, 2, 0, hook_data.len, &hook_data)));
    try sdk.put(engine, object, "hooks", c.JS_DupValue(engine.context, hooks));
    inline for (std.meta.fields(RuntimeMethod)) |operation| {
        const arity: c_int = switch (@as(RuntimeMethod, @enumFromInt(operation.value))) {
            .now, .entry, .snapshot, .snapshotAsOf, .watchDoc => 0,
            .report, .memo, .agent, .env, .ownedTasks => 1,
            .context => 3,
            else => 2,
        };
        try sdk.put(engine, object, operation.name, try engine.checked(c.JS_NewCFunctionData2(engine.context, runtimeMethod, operation.name, arity, @intCast(operation.value), bound_data.len, &bound_data)));
    }
    runtime.* = .{ .entry = entry.retain(), .session = c.JS_DupValue(engine.context, self.session), .signal = signal, .context = invocation_context, .agent = c.pi_js_undefined(), .snapshot = c.JS_DupValue(engine.context, self.snapshot) };
    _ = c.JS_SetOpaque(object, runtime);
    if (!existing) self.signals.appendAssumeCapacity(.{ .entry = entry.retain(), .value = c.JS_DupValue(engine.context, signal), .context = c.JS_DupValue(engine.context, invocation_context) });
    return object;
}
fn runtimeRegistryGetter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_DupValue(context, data[0]);
}
fn runtimeSettingsGetter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return @import("native_durable_agent.zig").runtimeSettings(engine, data[0]) catch |err| durable.reject(engine, err);
}
fn active(self: *Runtime) !void {
    if (!self.entry.runtime.isActive() or self.entry.manager.closed) {
        const engine = self.entry.manager.engine;
        const failure = try endedError(engine, self.entry.runtime.taskId());
        _ = try engine.checked(c.JS_Throw(engine.context, failure));
    }
    if (self.entry.runtime.context().aborted()) return error.Canceled;
}
fn endedError(engine: *Engine, task_id: u64) !c.JSValue {
    const message = try std.fmt.allocPrint(engine.gpa, "Task {d} invocation has ended", .{task_id});
    defer engine.gpa.free(message);
    return messageError(engine, message);
}
fn messageError(engine: *Engine, message: []const u8) !c.JSValue {
    const text = try sdk.text(engine, message);
    defer engine.freeValue(text);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Error");
    defer engine.freeValue(constructor);
    var args = [_]c.JSValue{text};
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
}
fn runtimeMethod(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return runtimeMethodOwned(engine, data[0], @enumFromInt(magic), argv[0..@intCast(argc)]) catch |err| if (magic == @intFromEnum(RuntimeMethod.now) or magic == @intFromEnum(RuntimeMethod.report)) durable.reject(engine, err) else durable.rejectedPromise(engine, err);
}
fn runtimeMethodOwned(engine: *Engine, receiver: c.JSValue, operation: RuntimeMethod, args: []const c.JSValue) !c.JSValue {
    const self = runtimeState(engine, receiver) orelse return error.InvalidTaskRuntime;
    // Source's conversation read and binding.check only test invocation end;
    // the operation's supplied context carries cancellation independently.
    const memo_read = operation == .memo and args.len == 2;
    if (operation == .conversation or operation == .abortOwned or operation == .getTask or operation == .outcomes or operation == .entry or operation == .ownedTasks or memo_read) try invocationLive(self) else try active(self);
    const owner = self.entry.manager;
    if (memo_read) {
        // Source's memo read observes its live map immediately, ignores the
        // supplied Context, and performs no Storage read or mutation.
        try Manager.deliver(owner);
        const name = try engine.toString(args[0]);
        defer engine.gpa.free(name);
        const value = if (owner.live_task_records.get(self.entry.runtime.taskId())) |record| if (json.get(record.value, "memos")) |memos| if (json.get(memos, name)) |winner| try durable.jsValue(engine, winner) else c.pi_js_undefined() else c.pi_js_undefined() else c.pi_js_undefined();
        defer engine.freeValue(value);
        return sdk.promise(engine, value);
    }
    if (operation == .ownedTasks) {
        const context = if (args.len > 0) args[0] else c.pi_js_undefined();
        var captures = [_]c.JSValue{ receiver, context };
        const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, ownedTasksRead, 0, 0, captures.len, &captures));
        defer engine.freeValue(callback);
        return durable.enqueueRead(engine, self.session, callback, context);
    }
    if (operation == .abortOwned) {
        const bound = try @import("native_durable_context.zig").withAbortSignal(engine, self.signal, if (args.len > 1) args[1] else c.pi_js_undefined());
        defer engine.freeValue(bound);
        const id = try durable.number(engine, if (args.len > 0) args[0] else c.pi_js_undefined());
        const pending = try @import("native_durable_task_abort.zig").abortOwnedRead(owner, self.entry.runtime.taskId(), id, bound);
        defer engine.freeValue(pending);
        var after_data = [_]c.JSValue{ receiver, c.JS_NewInt64(engine.context, @intCast(id)), bound };
        const after = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeAbortOwnedMarked, 1, 0, after_data.len, &after_data));
        defer engine.freeValue(after);
        const operation_pending = try sdk.invoke(engine, pending, "then", &.{after});
        defer engine.freeValue(operation_pending);
        var wait_data = [_]c.JSValue{receiver};
        const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeAbortOwnedSettled, 1, 0, wait_data.len, &wait_data));
        defer engine.freeValue(fulfilled);
        const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeAbortOwnedSettled, 1, 1, wait_data.len, &wait_data));
        defer engine.freeValue(rejected);
        // The observed run can itself depend on work waiting for a free slot.
        // Treat the whole owned-abort observation as suspended, not only its
        // final terminal wait, and balance it on either settlement path.
        self.entry.runtime.suspendWait();
        errdefer self.entry.runtime.resumeWait();
        return sdk.invoke(engine, operation_pending, "then", &.{ fulfilled, rejected });
    }
    if (operation == .conversation) {
        const native = try durable.state(engine, self.session);
        if (native.creation_owner != null) return @import("native_durable_bound_conversation.zig").acquire(engine, receiver, self.session, owner.options, if (args.len > 0) args[0] else c.pi_js_undefined(), self.signal, if (args.len > 1) args[1] else c.pi_js_undefined());
        const callback = try sdk.get(engine, owner.options, "conversation");
        defer engine.freeValue(callback);
        const binding = try sdk.object(engine);
        defer engine.freeValue(binding);
        try sdk.put(engine, binding, "signal", c.JS_DupValue(engine.context, self.signal));
        var captures = [_]c.JSValue{receiver};
        const check = try engine.checked(c.JS_NewCFunctionData(engine.context, conversationBindingCheck, 0, 0, captures.len, &captures));
        try sdk.put(engine, binding, "check", check);
        const callback_receiver = try schedulerOwner(owner);
        defer engine.freeValue(callback_receiver);
        var arguments = [_]c.JSValue{ if (args.len > 0) args[0] else c.pi_js_undefined(), binding, if (args.len > 1) args[1] else c.pi_js_undefined() };
        const value = try engine.checked(c.JS_Call(engine.context, callback, callback_receiver, arguments.len, &arguments));
        defer engine.freeValue(value);
        return sdk.promise(engine, value);
    }
    if (operation == .sleep or operation == .waitForTask) {
        const context = if (args.len > 1) args[1] else c.pi_js_undefined();
        const bound = try @import("native_durable_context.zig").withAbortSignal(engine, self.signal, context);
        defer engine.freeValue(bound);
        try durable.checkCancellation(engine, bound);
        if (operation == .waitForTask) {
            const pending = try wait(owner, try durable.number(engine, if (args.len > 0) args[0] else c.pi_js_undefined()), null, bound);
            defer engine.freeValue(pending);
            var data = [_]c.JSValue{receiver};
            const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeWaitSettled, 1, 0, data.len, &data));
            defer engine.freeValue(fulfilled);
            const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeWaitSettled, 1, 1, data.len, &data));
            defer engine.freeValue(rejected);
            self.entry.runtime.suspendWait();
            errdefer self.entry.runtime.resumeWait();
            return sdk.invoke(engine, pending, "then", &.{ fulfilled, rejected });
        }
        var until: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &until, if (args.len > 0) args[0] else c.pi_js_undefined()) < 0) return error.JavaScriptException;
        try owner.updateClock();
        if (until - @as(f64, @floatFromInt(Manager.nativeClock(owner))) <= 0) return sdk.promise(engine, c.pi_js_undefined());
        var functions: [2]c.JSValue = undefined;
        const pending = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
        errdefer {
            engine.freeValue(pending);
            engine.freeValue(functions[0]);
            engine.freeValue(functions[1]);
        }
        try owner.sleepers.append(engine.gpa, .{ .runtime = c.JS_DupValue(engine.context, receiver), .until = until, .context = c.JS_DupValue(engine.context, bound), .resolve = functions[0], .reject = functions[1] });
        self.entry.runtime.suspendWait();
        return pending;
    }
    if (operation == .env) {
        const build = try sdk.get(engine, owner.options, "env");
        defer engine.freeValue(build);
        if (c.JS_IsUndefined(build)) return sdk.promise(engine, c.pi_js_undefined());
        const id = c.JS_NewInt64(engine.context, @intCast(self.entry.runtime.invocation.conversation_id));
        defer engine.freeValue(id);
        const context = if (args.len == 0) c.pi_js_undefined() else args[0];
        const native = try durable.state(engine, self.session);
        if (native.creation_owner == null) {
            // Source TaskSchedulerOptions.env receives the conversation id,
            // with no Harness AgentDoc read or synthetic read capability.
            var arguments = [_]c.JSValue{ id, context };
            const callback_receiver = try schedulerOwner(owner);
            defer engine.freeValue(callback_receiver);
            const value = try engine.checked(c.JS_Call(engine.context, build, callback_receiver, arguments.len, &arguments));
            defer engine.freeValue(value);
            return sdk.promise(engine, value);
        }
        const harness = try @import("native_durable_harness.zig").state(engine, native.creation_owner.?);
        if (!c.JS_IsStrictEqual(engine.context, harness.session, self.session)) return error.InvalidHarnessSession;
        const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
        const token = try sdk.get(engine, exports, "AgentDoc");
        defer engine.freeValue(token);
        const pending = try @import("native_durable_documents.zig").snapshot(engine, self.session, &.{ token, id, context });
        defer engine.freeValue(pending);
        var captures = [_]c.JSValue{ receiver, build, id, context };
        const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeEnvResolved, 1, 0, captures.len, &captures));
        defer engine.freeValue(callback);
        return sdk.invoke(engine, pending, "then", &.{callback});
    }
    if (operation == .agent) {
        if (c.JS_IsUndefined(self.agent)) {
            var record = (try owner.lease.value.storage.readTableRecord(engine.gpa, .task, self.entry.runtime.taskId())) orelse return error.UnknownTask;
            defer record.deinit();
            const id = try durable.jsValue(engine, try json.required(record.value, "conversationId"));
            defer engine.freeValue(id);
            // Resolution uses the snapshot admitted for this phase, even if a
            // later registry publication refreshes the manager before first use.
            const pending = try @import("native_durable_agent.zig").resolveConversation(engine, self.session, owner.options, id, self.snapshot, self.context);
            errdefer engine.freeValue(pending);
            const ignored = try engine.checked(c.JS_NewCFunction(engine.context, ignoreAgentFailure, "observe-agent-failure", 0));
            defer engine.freeValue(ignored);
            const observed = try sdk.invoke(engine, pending, "catch", &.{ignored});
            engine.freeValue(observed);
            self.agent = pending;
        }
        return @import("native_durable_context.zig").awaitWithContext(engine, self.agent, if (args.len == 0) c.pi_js_undefined() else args[0]);
    }
    if (operation == .snapshot or operation == .snapshotAsOf or operation == .watchDoc) {
        const session = try durable.state(engine, self.session);
        const pending = try durable.sessionDispatch(session, self.session, switch (operation) {
            .snapshot => .snapshot,
            .snapshotAsOf => .snapshotAsOf,
            else => .watchDoc,
        }, args);
        if (operation != .watchDoc) return pending;
        defer engine.freeValue(pending);
        var captures = [_]c.JSValue{receiver};
        const adopted = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeWatchAdopted, 1, 0, 1, &captures));
        defer engine.freeValue(adopted);
        return sdk.invoke(engine, pending, "then", &.{adopted});
    }
    if (operation == .now) {
        try owner.updateClock();
        return engine.checked(c.JS_NewInt64(engine.context, Manager.nativeClock(owner)));
    }
    if (operation == .report) {
        const callback = try sdk.get(engine, owner.options, "onReport");
        defer engine.freeValue(callback);
        if (c.JS_IsUndefined(callback) or c.JS_IsNull(callback)) return c.pi_js_undefined();
        var values = [_]c.JSValue{if (args.len > 0) args[0] else c.pi_js_undefined()};
        return engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), 1, &values));
    }
    const arguments = try sdk.array(engine);
    defer engine.freeValue(arguments);
    for (args) |argument| try sdk.append(engine, arguments, c.JS_DupValue(engine.context, argument));
    var data = [_]c.JSValue{ receiver, arguments };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeReadQueued, 0, @intFromEnum(operation), data.len, &data));
    defer engine.freeValue(callback);
    if (operation == .getTask or operation == .outcomes or operation == .entry) {
        const context_index: usize = if (operation == .entry and args.len > 0 and !c.JS_IsNumber(args[0])) 2 else 1;
        return durable.enqueueRead(engine, self.session, callback, if (args.len > context_index) args[context_index] else c.pi_js_undefined());
    }
    return durable.enqueue(engine, self.session, callback);
}
fn runtimeAbortOwnedMarked(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return runtimeAbortOwnedMarkedValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data) catch |err| durable.reject(engine, err);
}
fn conversationBindingCheck(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = runtimeState(engine, data[0]) orelse return durable.reject(engine, error.InvalidTaskRuntime);
    invocationLive(self) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
pub fn checkInvocation(engine: *Engine, receiver: c.JSValue) !void {
    const self = runtimeState(engine, receiver) orelse return error.InvalidTaskRuntime;
    try invocationLive(self);
}
fn invocationLive(self: *Runtime) !void {
    if (self.entry.runtime.isActive()) return;
    const engine = self.entry.manager.engine;
    const failure = try endedError(engine, self.entry.runtime.taskId());
    _ = try engine.checked(c.JS_Throw(engine.context, failure));
}
fn ownedTasksRead(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return ownedTasksOnLine(engine, data[0], data[1]) catch |err| durable.reject(engine, err);
}
fn ownedTasksOnLine(engine: *Engine, receiver: c.JSValue, context: c.JSValue) !c.JSValue {
    const self = runtimeState(engine, receiver) orelse return error.InvalidTaskRuntime;
    const owner = self.entry.manager;
    // Admit publications from the commit preceding this serialized read;
    // external Storage reads never enter this committed live-record map.
    try Manager.deliver(owner);
    try invocationLive(self);
    try durable.checkCancellation(engine, context);
    // This callback owns the real Session line, so the scheduler's committed
    // downward index is stable while the VM admits its publication copies.
    const ids = try owner.scheduler.ownership_index.directOwned(engine.gpa, self.entry.runtime.taskId());
    defer engine.gpa.free(ids);
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    for (ids) |id| try sdk.append(engine, result, try durable.jsValue(engine, owner.live_task_records.get(id).?.value));
    return result;
}
fn runtimeAbortOwnedMarkedValue(engine: *Engine, terminal: c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    if (c.JS_ToBool(engine.context, terminal) != 0) return c.pi_js_undefined();
    const runtime = runtimeState(engine, data[0]) orelse return error.InvalidTaskRuntime;
    const owner = runtime.entry.manager;
    const pending = try wait(owner, try durable.number(engine, data[1]), null, data[2]);
    defer engine.freeValue(pending);
    var capture = [_]c.JSValue{data[0]};
    const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeAbortOwnedSettled, 1, 0, capture.len, &capture));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeAbortOwnedSettled, 1, 1, capture.len, &capture));
    defer engine.freeValue(rejected);
    runtime.entry.runtime.suspendWait();
    errdefer runtime.entry.runtime.resumeWait();
    return sdk.invoke(engine, pending, "then", &.{ fulfilled, rejected });
}
fn diagnoseSourceFailure(engine: *Engine, name: []const u8, cause: anyerror) void {
    std.debug.print("Actual ea {s} {s}: {s}\n", .{ name, @errorName(cause), engine.last_error orelse "no VM diagnostic" });
    const raw = engine.native_durable_control_context orelse return;
    const owner: *Hub = @ptrCast(@alignCast(raw));
    for (owner.managers.items) |manager| {
        const failure = manager.lease.value.failure();
        std.debug.print("Native Session original={s} closed={} queued={d} pending={} preparedSeq={?d} dispatches={d}\n", .{ if (failure) |err| @errorName(err) else "none", manager.closed, manager.events.items.len, manager.publicationPending(), manager.prepared_publication_seq, manager.active_dispatches });
    }
}
test "native durable VM ownedTasks actual ea direct live copies cancellation and extracted aliases" {
    const engine = try Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const result = engine.evalModule(@embedFile("../durable/fixtures/durable-ea-ownedtasks-program.txt"), "actual-ea-ownedtasks") catch |err| {
        diagnoseSourceFailure(engine, "ownedTasks", err);
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "ownedTasksTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("../durable/fixtures/durable-ea-ownedtasks.json"));
    defer expected.deinit();
    if (!json.equal(actual.value, expected.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual ea ownedTasks trace: {s}\n", .{encoded});
        return error.SourceOwnedTasksMismatch;
    }
}
test "native durable VM actual ea retention uses real Harness index sizes and late Storage owner reloads" {
    const engine = try Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    try @import("timers.zig").install(engine, std.testing.io);
    const result = engine.evalModule(@embedFile("../durable/fixtures/durable-ea-retention-program.txt"), "actual-ea-retention") catch |err| {
        diagnoseSourceFailure(engine, "retention", err);
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "retentionTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("../durable/fixtures/durable-ea-retention.json"));
    defer expected.deinit();
    if (!json.equal(actual.value, expected.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual ea retention trace: {s}\n", .{encoded});
        return error.SourceRetentionMismatch;
    }
}
test "native durable VM actual ea runtime overlay holds an outcome for work created in its existing owned conversation" {
    const engine = try Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    try @import("timers.zig").install(engine, std.testing.io);
    const result = engine.evalModule(@embedFile("../durable/fixtures/durable-ea-runtime-overlay-program.txt"), "actual-ea-runtime-overlay") catch |err| {
        diagnoseSourceFailure(engine, "runtime-overlay", err);
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "runtimeOverlayTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("../durable/fixtures/durable-ea-runtime-overlay.json"));
    defer expected.deinit();
    if (!json.equal(actual.value, expected.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual ea runtime overlay trace: {s}\n", .{encoded});
        return error.SourceRuntimeOverlayMismatch;
    }
}
test "native durable VM ownership publication index readiness preserves committed live waiter barriers" {
    const gpa = std.testing.allocator;
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const options = try engine.eval("({registry:{snapshot(){return{tasks(){return[]}}}}})", "publication-index-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    try attach(engine, session, options, c.pi_js_undefined());
    const manager = try getManager(engine, session);
    var live = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":1}},{\"type\":\"task\",\"value\":{\"id\":2,\"kind\":\"fixture.ready\",\"version\":1,\"conversationId\":1,\"input\":null,\"background\":false,\"abortRequested\":false,\"state\":{\"status\":\"running\",\"checkpoint\":{\"phase\":\"hold\"}}}}]");
    defer live.deinit();
    var original = owner_index.Index.init(gpa);
    defer original.deinit();
    try Manager.forwardIndex(manager, null, &original);
    const Check = struct {
        manager: *Manager,
        changes: json.Value,
        fn apply(raw: ?*anyopaque, _: *session_mod.Transaction, _: @import("../durable/types.zig").Context) !json.Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            // Exercise the actual reserved Session line, without changing its
            // owner word or manufacturing a ready flag in test code.
            try Manager.forward(self.manager, &.{ .seq = 77, .changes = self.changes });
            try std.testing.expect(self.manager.pending_index == null);
            try Manager.deliver(self.manager);
            try std.testing.expectEqual(@as(usize, 1), self.manager.events.items.len);
            try std.testing.expect(self.manager.publicationPending());
            try std.testing.expect(!self.manager.live_task_records.contains(2));
            var tracked = owner_index.Index.init(self.manager.engine.gpa);
            defer tracked.deinit();
            try tracked.observe(&.{.{ .id = 1 }}, &.{.{ .id = 2, .link = .{ .conversation = 1 }, .status = .running }});
            try Manager.forwardIndex(self.manager, 77, &tracked);
            try Manager.deliver(self.manager);
            try std.testing.expectEqual(@as(usize, 0), self.manager.events.items.len);
            try std.testing.expect(!self.manager.publicationPending());
            try std.testing.expect(self.manager.live_task_records.contains(2));
            try std.testing.expect(!try self.manager.publishedIdle(null));
            // Production ordering: the internal observer finishes before the
            // external subscriber forwards the same committed sequence.
            try Manager.forwardIndex(self.manager, 78, &tracked);
            try std.testing.expectEqual(@as(?u64, 78), self.manager.prepared_publication_seq);
            try Manager.deliver(self.manager);
            try std.testing.expectEqual(@as(usize, 0), self.manager.events.items.len);
            try Manager.forward(self.manager, &.{ .seq = 78, .changes = self.changes });
            try std.testing.expect(self.manager.prepared_publication_index == null);
            try Manager.deliver(self.manager);
            try std.testing.expect(!self.manager.publicationPending());
            try std.testing.expect(self.manager.live_task_records.contains(2));
            return .null;
        }
    };
    var check: Check = .{ .manager = manager, .changes = live.value };
    var completed = try manager.lease.value.commit(Check.apply, &check, .{}, .{});
    completed.deinit();
    // The earlier load-only snapshot must not undo the newer publication.
    try Manager.deliver(manager);
    try std.testing.expectEqual(@as(usize, 1), manager.published_index.?.sizes().live);
    const promise = try appendTestWaiter(manager, 2, c.pi_js_undefined());
    defer engine.freeValue(promise);
    try settleWaiters(manager);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, promise));
}
test "native durable VM failed ownership observer keeps original Session failure and does not join an unready queue" {
    const gpa = std.testing.allocator;
    const engine = try Engine.init(gpa, .{ .host_await_timeout_ms = 1000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const options = try engine.eval("({registry:{snapshot(){return{tasks(){return[]}}}}})", "failed-index-observer-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    try attach(engine, session, options, c.pi_js_undefined());
    const manager = try getManager(engine, session);
    const Failure = struct {
        fn observe(_: ?*anyopaque, _: ?u64, _: *const owner_index.Index) !void {
            return error.OriginalOwnershipObserverFailure;
        }
        fn root(_: ?*anyopaque, tx: *session_mod.Transaction, _: @import("../durable/types.zig").Context) !json.Value {
            return tx.createRootConversation();
        }
    };
    manager.scheduler.options.index_changed = Failure.observe;
    // A real committed publication reaches foreign forwarding first, then the
    // internal index observer fails. Its event must stay unready, never become
    // a successful publication and never become a guest close dependency.
    var committed = try manager.lease.value.commit(Failure.root, null, .{}, .{});
    committed.deinit();
    try std.testing.expectEqual(@as(?anyerror, error.OriginalOwnershipObserverFailure), manager.lease.value.failure());
    try std.testing.expect(!manager.lease.value.fail(error.LaterFailureMustNotReplaceOriginal));
    try std.testing.expectEqual(@as(usize, 1), manager.events.items.len);
    try std.testing.expect(manager.publicationPending());
    try Manager.deliver(manager);
    try std.testing.expectEqual(@as(usize, 1), manager.events.items.len);
    manager.retire();
    const joined = try manager.joinPromise();
    defer engine.freeValue(joined);
    const settled = try engine.awaitValue(joined);
    defer engine.freeValue(settled);
    try std.testing.expect(c.JS_IsUndefined(settled));
    try std.testing.expect(manager.closed and manager.thread == null and manager.active_dispatches == 0);
    try std.testing.expect(manager.publicationPending());
    try std.testing.expectEqual(@as(?anyerror, error.OriginalOwnershipObserverFailure), manager.lease.value.failure());
}
fn partialOwnerReplay(program: []const u8, golden: []const u8, name: [:0]const u8) !void {
    const engine = try Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const result = engine.evalModule(program, name) catch |err| {
        diagnoseSourceFailure(engine, name, err);
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "ownershipStorageTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, golden);
    defer expected.deinit();
    if (!json.equal(actual.value, expected.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual ea partial owner {s}: {s}\n", .{ name, encoded });
        return error.SourcePartialOwnerMismatch;
    }
}
test "native durable VM actual ea partial owner Source23 missing owner keeps unknown scope and original keyed context" {
    try partialOwnerReplay(@embedFile("../durable/fixtures/durable-ea-partial-owner-source23-program.txt"), @embedFile("../durable/fixtures/durable-ea-partial-owner-source23.json"), "Source23-missing-owner");
}
test "native durable VM actual ea partial owner Source24 missing conversation ends chain without inventing a row" {
    try partialOwnerReplay(@embedFile("../durable/fixtures/durable-ea-partial-owner-source24-program.txt"), @embedFile("../durable/fixtures/durable-ea-partial-owner-source24.json"), "Source24-missing-conversation");
}
test "native durable VM actual ea partial owner Source25 loads terminal links with unabortable scheduler context" {
    try partialOwnerReplay(@embedFile("../durable/fixtures/durable-ea-partial-owner-source25-program.txt"), @embedFile("../durable/fixtures/durable-ea-partial-owner-source25.json"), "Source25-owned-context");
}
test "native durable VM actual ea partial owner Source26 recovers opaque null checkpoint before loading owner scopes" {
    try partialOwnerReplay(@embedFile("../durable/fixtures/durable-ea-partial-owner-source26-program.txt"), @embedFile("../durable/fixtures/durable-ea-partial-owner-source26.json"), "Source26-opaque-checkpoint-recovery");
}
fn ignoreAgentFailure(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn runtimeWaitSettled(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, rejected: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const runtime = runtimeState(engine, data[0]) orelse return durable.reject(engine, error.InvalidTaskRuntime);
    runtime.entry.runtime.resumeWait();
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    if (rejected != 0) return c.JS_Throw(context, c.JS_DupValue(context, value));
    return c.JS_DupValue(context, value);
}
fn runtimeEnvResolved(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return runtimeEnvResolvedOwned(engine, if (argc == 0) c.pi_js_undefined() else argv[0], data) catch |err| durable.reject(engine, err);
}
fn runtimeEnvResolvedOwned(engine: *Engine, state: c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const runtime = runtimeState(engine, data[0]) orelse return error.InvalidTaskRuntime;
    try active(runtime);
    try durable.checkCancellation(engine, data[3]);
    const request = try sdk.object(engine);
    defer engine.freeValue(request);
    try sdk.put(engine, request, "conversationId", c.JS_DupValue(engine.context, data[2]));
    if (!c.JS_IsUndefined(state)) {
        const cwd = try sdk.get(engine, state, "cwd");
        defer engine.freeValue(cwd);
        if (!c.JS_IsUndefined(cwd)) try sdk.put(engine, request, "cwd", c.JS_DupValue(engine.context, cwd));
    }
    const native = try durable.state(engine, runtime.session);
    const read = native.creation_owner orelse return error.NativeHarnessEnvironmentUnavailable;
    const harness = try @import("native_durable_harness.zig").state(engine, read);
    if (!c.JS_IsStrictEqual(engine.context, harness.session, runtime.session)) return error.InvalidHarnessSession;
    try sdk.put(engine, request, "read", c.JS_DupValue(engine.context, read));
    var arguments = [_]c.JSValue{ request, data[3] };
    return engine.checked(c.JS_Call(engine.context, data[1], c.pi_js_undefined(), arguments.len, &arguments));
}
fn hooksEach(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return hooksEachOwned(engine, data[0], argv[0..@intCast(argc)]) catch |err| durable.rejectedPromise(engine, err);
}
fn hooksEachOwned(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const runtime = runtimeState(engine, receiver) orelse return error.InvalidTaskRuntime;
    const agent = try runtimeMethodOwned(engine, receiver, .agent, &.{runtime.context});
    defer engine.freeValue(agent);
    var captures = [_]c.JSValue{ receiver, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined() };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, hooksSelected, 1, 0, captures.len, &captures));
    defer engine.freeValue(callback);
    return sdk.invoke(engine, agent, "then", &.{callback});
}
fn hooksSelected(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return hooksSelectedOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data) catch |err| durable.reject(engine, err);
}
fn hooksSelectedOwned(engine: *Engine, agent: c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const runtime = runtimeState(engine, data[0]) orelse return error.InvalidTaskRuntime;
    const definition = try sdk.get(engine, runtime.entry.manager.definitions.items[runtime.entry.definition].token, "definition");
    defer engine.freeValue(definition);
    const task_name = try sdk.get(engine, definition, "name");
    defer engine.freeValue(task_name);
    const handlers = try sdk.array(engine);
    defer engine.freeValue(handlers);
    const extensions = try sdk.get(engine, agent, "extensions");
    defer engine.freeValue(extensions);
    for (0..try sdk.length(engine, extensions)) |index| {
        const extension = try engine.checked(c.JS_GetPropertyUint32(engine.context, extensions, @intCast(index)));
        defer engine.freeValue(extension);
        const hooks = try sdk.get(engine, extension, "hooks");
        defer engine.freeValue(hooks);
        if (c.JS_IsUndefined(hooks)) continue;
        for (0..try sdk.length(engine, hooks)) |hook_index| {
            const hook = try engine.checked(c.JS_GetPropertyUint32(engine.context, hooks, @intCast(hook_index)));
            defer engine.freeValue(hook);
            const name = try sdk.get(engine, hook, "task");
            defer engine.freeValue(name);
            if (c.JS_IsStrictEqual(engine.context, name, task_name)) try sdk.append(engine, handlers, try sdk.get(engine, hook, "handlers"));
        }
    }
    return hooksNext(engine, data[0], data[1], data[2], handlers, 0);
}
fn hooksNext(engine: *Engine, receiver: c.JSValue, name: c.JSValue, invoke: c.JSValue, handlers: c.JSValue, start: usize) anyerror!c.JSValue {
    var index = start;
    while (index < try sdk.length(engine, handlers)) : (index += 1) {
        const handler = try engine.checked(c.JS_GetPropertyUint32(engine.context, handlers, @intCast(index)));
        defer engine.freeValue(handler);
        const key = try engine.toString(name);
        defer engine.gpa.free(key);
        const atom = c.JS_NewAtomLen(engine.context, key.ptr, key.len);
        defer c.JS_FreeAtom(engine.context, atom);
        const callback = try engine.checked(c.JS_GetProperty(engine.context, handler, atom));
        defer engine.freeValue(callback);
        if (!c.JS_IsFunction(engine.context, callback)) continue;
        const bound = try sdk.invoke(engine, callback, "bind", &.{handler});
        defer engine.freeValue(bound);
        var arguments = [_]c.JSValue{bound};
        const raw = c.JS_Call(engine.context, invoke, c.pi_js_undefined(), 1, &arguments);
        const pending = if (c.JS_IsException(raw)) blk: {
            _ = engine.checked(raw) catch {};
            break :blk durable.rejectedPromise(engine, error.JavaScriptException);
        } else blk: {
            defer engine.freeValue(raw);
            break :blk try sdk.promise(engine, raw);
        };
        defer engine.freeValue(pending);
        var captures = [_]c.JSValue{ receiver, name, invoke, handlers, c.JS_NewInt64(engine.context, @intCast(index + 1)) };
        const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, hooksSettled, 1, 0, captures.len, &captures));
        defer engine.freeValue(fulfilled);
        const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, hooksSettled, 1, 1, captures.len, &captures));
        defer engine.freeValue(rejected);
        return sdk.invoke(engine, pending, "then", &.{ fulfilled, rejected });
    }
    return c.pi_js_undefined();
}
fn hooksSettled(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, rejected: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return hooksSettledOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), rejected != 0, data) catch |err| durable.reject(engine, err);
}
fn hooksSettledOwned(engine: *Engine, failure: c.JSValue, rejected: bool, data: [*c]c.JSValue) !c.JSValue {
    if (rejected) {
        const runtime = runtimeState(engine, data[0]) orelse return error.InvalidTaskRuntime;
        const aborted = try sdk.get(engine, runtime.signal, "aborted");
        defer engine.freeValue(aborted);
        if (c.JS_ToBool(engine.context, aborted) != 0) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure)));
        const report = try sdk.get(engine, runtime.entry.manager.options, "onReport");
        defer engine.freeValue(report);
        if (!c.JS_IsUndefined(report) and !c.JS_IsNull(report)) {
            var args = [_]c.JSValue{failure};
            const ignored = try engine.checked(c.JS_Call(engine.context, report, c.pi_js_undefined(), 1, &args));
            engine.freeValue(ignored);
        }
    }
    return hooksNext(engine, data[0], data[1], data[2], data[3], @intCast(try durable.number(engine, data[4])));
}
fn runtimeWatchAdopted(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return runtimeWatchAdoptedOwned(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
fn runtimeWatchAdoptedOwned(engine: *Engine, receiver: c.JSValue, watch: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(watch)) return c.pi_js_undefined();
    var admitted = false;
    errdefer if (!admitted) {
        if (sdk.invoke(engine, watch, "stop", &.{})) |stopped| engine.freeValue(stopped) else |_| {}
    };
    const self = runtimeState(engine, receiver) orelse return error.InvalidTaskRuntime;
    try active(self);
    const manager = self.entry.manager;
    try manager.watches.ensureUnusedCapacity(engine.gpa, 1);
    manager.watches.appendAssumeCapacity(.{ .entry = self.entry.retain(), .value = c.JS_DupValue(engine.context, watch) });
    admitted = true;
    return c.JS_DupValue(engine.context, watch);
}
fn runtimeReadQueued(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return runtimeReadOwned(engine, data[0], data[1], @enumFromInt(magic)) catch |err| durable.reject(engine, err);
}
fn runtimeReadOwned(engine: *Engine, receiver: c.JSValue, args: c.JSValue, operation: RuntimeMethod) !c.JSValue {
    const self = runtimeState(engine, receiver) orelse return error.InvalidTaskRuntime;
    try active(self);
    const owner = self.entry.manager;
    const length = try sdk.length(engine, args);
    if (operation == .memo and length < 2) return error.InvalidMemoArguments;
    const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, args, 0));
    defer engine.freeValue(first);
    const context_index: u32 = if (operation == .memo) @intCast(length - 1) else if (operation == .entry and !c.JS_IsNumber(first)) 2 else 1;
    const context = try engine.checked(c.JS_GetPropertyUint32(engine.context, args, context_index));
    defer engine.freeValue(context);
    if (operation != .abortOwned) try durable.checkCancellation(engine, context);
    if (operation == .context) {
        const options = try engine.checked(c.JS_GetPropertyUint32(engine.context, args, 2));
        defer engine.freeValue(options);
        const at = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "at");
        defer engine.freeValue(at);
        const slot = try owner.contexts.getOrPut(engine.gpa, try durable.number(engine, first));
        if (!slot.found_existing) slot.value_ptr.* = null;
        return @import("native_durable_context_view.zig").read(engine, self.session, first, context, at, slot.value_ptr);
    }
    const store = &owner.lease.value.storage;
    if (operation == .abortOwned) {
        const bound = try @import("native_durable_context.zig").withAbortSignal(engine, self.signal, context);
        defer engine.freeValue(bound);
        const id = try durable.number(engine, first);
        // Source first reads and validates the owner. Its in-memory read can
        // succeed despite caller cancellation, and a terminal child is a noop.
        var record = try store.readTableRecord(engine.gpa, .task, id);
        defer if (record) |*value| value.deinit();
        const owned = if (record) |value| if (json.get(value.value, "owner")) |owner_id| try json.asInteger(owner_id) == self.entry.runtime.taskId() else false else false;
        if (!owned) {
            const message = try std.fmt.allocPrint(engine.gpa, "Task {d} is not owned by task {d}", .{ id, self.entry.runtime.taskId() });
            defer engine.gpa.free(message);
            return engine.checked(c.JS_Throw(engine.context, try messageError(engine, message)));
        }
        if (std.mem.eql(u8, try json.asString(try json.required(try json.required(record.?.value, "state"), "status")), "terminal")) return c.pi_js_bool(engine.context, 1);
        try durable.checkCancellation(engine, bound);
        const terminal = owner.scheduler.abortOwned(self.entry.runtime.taskId(), id) catch |err| {
            if (err != error.TaskNotOwned) return err;
            const message = try std.fmt.allocPrint(engine.gpa, "Task {d} is not owned by task {d}", .{ id, self.entry.runtime.taskId() });
            defer engine.gpa.free(message);
            return engine.checked(c.JS_Throw(engine.context, try messageError(engine, message)));
        };
        try Manager.deliver(owner);
        return c.pi_js_bool(engine.context, if (terminal) 1 else 0);
    }
    if (operation == .getTask) {
        var record = (try store.readTableRecord(engine.gpa, .task, try durable.number(engine, first))) orelse return c.pi_js_undefined();
        defer record.deinit();
        return durable.jsValue(engine, record.value);
    }
    if (operation == .outcomes) {
        const result = try sdk.array(engine);
        errdefer engine.freeValue(result);
        for (0..try sdk.length(engine, first)) |index| {
            const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, first, @intCast(index)));
            defer engine.freeValue(item);
            var record = (try store.readTableRecord(engine.gpa, .task, try durable.number(engine, item))) orelse return error.UnknownTask;
            defer record.deinit();
            const state = try json.required(record.value, "state");
            if (!std.mem.eql(u8, try json.asString(try json.required(state, "status")), "terminal")) return error.TaskNotTerminal;
            try sdk.append(engine, result, try durable.jsValue(engine, try json.required(state, "outcome")));
        }
        return result;
    }
    if (operation == .entry) {
        const typed = !c.JS_IsNumber(first);
        const id = if (typed) try engine.checked(c.JS_GetPropertyUint32(engine.context, args, 1)) else c.JS_DupValue(engine.context, first);
        defer engine.freeValue(id);
        var record = (try store.readTableRecord(engine.gpa, .task, self.entry.runtime.taskId())) orelse return error.UnknownTask;
        defer record.deinit();
        const conversation = try json.asInteger(try json.required(record.value, "conversationId"));
        var found = (try store.readEntry(engine.gpa, try durable.number(engine, id), conversation)) orelse return c.pi_js_undefined();
        defer found.deinit();
        const entry = try json.required(found.value, "entry");
        if (typed) {
            const kind_value = try sdk.get(engine, first, "kind");
            defer engine.freeValue(kind_value);
            const kind = try engine.toString(kind_value);
            defer engine.gpa.free(kind);
            if (!std.mem.eql(u8, kind, try json.asString(try json.required(entry, "kind")))) return c.pi_js_undefined();
        }
        return durable.jsValue(engine, entry);
    }
    if (operation == .memo) {
        const name = try engine.toString(first);
        defer engine.gpa.free(name);
        var record = (try store.readTableRecord(engine.gpa, .task, self.entry.runtime.taskId())) orelse return error.UnknownTask;
        defer record.deinit();
        const memos = json.get(record.value, "memos") orelse json.Value{ .object = .empty };
        if (json.get(memos, name)) |winner| return durable.jsValue(engine, winner);
        if (length == 2) return c.pi_js_undefined();
        const candidate = try engine.checked(c.JS_GetPropertyUint32(engine.context, args, 1));
        defer engine.freeValue(candidate);
        var value = try durable.owned(engine, candidate);
        defer value.deinit();
        const Memo = struct {
            name: []const u8,
            value: json.Value,
            winner: ?json.Owned = null,
            fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, current: json.Value) !?json.Value {
                const change: *@This() = @ptrCast(@alignCast(raw.?));
                const a = tx.owned.arena.allocator();
                var next = try json.clone(a, current);
                var map = json.get(next, "memos") orelse json.Value{ .object = .empty };
                if (json.get(map, change.name)) |winner| {
                    var copied = try json.Owned.empty(tx.gpa);
                    errdefer copied.deinit();
                    copied.value = try json.clone(copied.arena.allocator(), winner);
                    change.winner = copied;
                    return null;
                }
                try map.object.put(a, try a.dupe(u8, change.name), try json.clone(a, change.value));
                try next.object.put(a, "memos", map);
                try tx.setTask(next);
                return null;
            }
        };
        var change: Memo = .{ .name = name, .value = value.value };
        defer if (change.winner) |*winner| winner.deinit();
        if (!try self.entry.runtime.tryCommit(Memo.apply, &change)) {
            var captures = [_]c.JSValue{ receiver, args, c.pi_js_undefined(), self.session, c.pi_js_undefined() };
            return @import("native_durable_storage.zig").deferRuntimeMemo(engine, &captures);
        }
        try Manager.deliver(owner);
        if (change.winner) |winner| return durable.jsValue(engine, winner.value);
        return durable.jsValue(engine, value.value);
    }
    return error.UnknownRuntimeOperation;
}
fn runtimeAbortOwnedSettled(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, rejected: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const runtime = runtimeState(engine, data[0]) orelse return durable.reject(engine, error.InvalidTaskRuntime);
    runtime.entry.runtime.resumeWait();
    if (rejected != 0) return c.JS_Throw(context, c.JS_DupValue(context, if (argc > 0) argv[0] else c.pi_js_undefined()));
    return c.pi_js_undefined();
}
fn runtimeCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const receiver = captures[0];
    const self = runtimeState(engine, receiver) orelse return durable.rejectedPromise(engine, error.InvalidTaskRuntime);
    active(self) catch |err| return durable.rejectedPromise(engine, err);
    var data = [_]c.JSValue{ receiver, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined() };
    const callback = engine.checked(c.JS_NewCFunctionData(engine.context, runtimeCommitQueued, 0, 0, data.len, &data)) catch |err| return durable.rejectedPromise(engine, err);
    defer engine.freeValue(callback);
    return durable.enqueue(engine, self.session, callback) catch |err| durable.rejectedPromise(engine, err);
}
const Change = struct {
    runtime: *Runtime,
    callback: c.JSValue,
    context: c.JSValue,
    returned: ?json.Owned = null,
    documents: ?*@import("native_durable_documents.zig").Drafts = null,
    transaction_value: ?c.JSValue = null,
    fn run(raw: ?*anyopaque, native: *session_mod.Transaction, current: json.Value) !?json.Value {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const manager_pointer = self.runtime.entry.manager;
        const engine = manager_pointer.engine;
        try active(self.runtime);
        try durable.checkCancellation(engine, self.context);
        try manager_pointer.updateClock();
        const tx = try durable.transactionObject(engine, native, self.runtime.session);
        defer engine.freeValue(tx);
        const record = try durable.jsValue(engine, current);
        defer engine.freeValue(record);
        var args = [_]c.JSValue{ tx, record };
        const promise = try engine.checked(c.JS_Call(engine.context, self.callback, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(promise);
        const result = try engine.awaitValue(promise);
        defer engine.freeValue(result);
        if ((try durable.state(engine, tx)).documents) |documents| try documents.finish();
        self.documents = (try durable.state(engine, tx)).documents;
        self.transaction_value = c.JS_DupValue(engine.context, tx);
        const parent = try durable.state(engine, self.runtime.session);
        if (parent.finish_hook) |finish| try finish(engine, parent.creation_owner.?, tx);
        if (c.JS_IsUndefined(result)) return null;
        self.returned = try durable.owned(engine, result);
        return self.returned.?.value;
    }
};
fn runtimeCommitQueued(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = runtimeState(engine, data[0]) orelse return durable.reject(engine, error.InvalidTaskRuntime);
    active(self) catch |err| return durable.reject(engine, err);
    var call: Change = .{ .runtime = self, .callback = data[1], .context = data[2] };
    defer if (call.transaction_value) |value| engine.freeValue(value);
    defer if (call.returned) |*value| value.deinit();
    const native = durable.state(engine, self.session) catch |err| return durable.reject(engine, err);
    const storage_context = @import("native_durable_storage.zig").withContext(native, data[2]);
    defer storage_context.restore();
    const admitted = self.entry.runtime.tryCommit(Change.run, &call) catch |err| {
        return durable.reject(engine, err);
    };
    if (!admitted) {
        var captures = [_]c.JSValue{ data[0], data[1], data[2], self.session, c.pi_js_undefined() };
        return @import("native_durable_storage.zig").deferRuntimeCommit(engine, &captures) catch |err| durable.reject(engine, err);
    }
    if (call.documents) |documents| documents.adopt(self.session) catch |err| return durable.reject(engine, err);
    Manager.deliver(self.entry.manager) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
pub fn retryRuntimeCommit(engine: *Engine, captures: []const c.JSValue) c.JSValue {
    return runtimeCommitQueued(engine.context, c.pi_js_undefined(), 0, null, 0, @constCast(captures.ptr));
}
pub fn retryRuntimeMemo(engine: *Engine, captures: []const c.JSValue) c.JSValue {
    return runtimeReadQueued(engine.context, c.pi_js_undefined(), 0, null, @intFromEnum(RuntimeMethod.memo), @constCast(captures.ptr));
}
pub fn wait(self: *Manager, id: ?u64, conversation: ?u64, context: c.JSValue) !c.JSValue {
    if (self.closed) return self.engine.checked(c.JS_Throw(self.engine.context, try schedulerClosedError(self)));
    // Source's idle fast path never registers a waiter or observes its context.
    // Public Harness waits resume scheduling before reaching this check.
    if (id == null and try self.publishedIdle(conversation)) {
        try self.@"resume"();
        return sdk.promise(self.engine, c.pi_js_undefined());
    }
    try durable.checkCancellation(self.engine, context);
    var functions: [2]c.JSValue = undefined;
    const promise = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &functions));
    errdefer self.engine.freeValue(promise);
    defer for (functions) |function| self.engine.freeValue(function);
    var cancellation = try waiterCancellation(self.engine, promise, functions[1], context);
    defer if (cancellation) |*hook| hook.deinit();
    errdefer {
        for (self.waiters.items, 0..) |waiter, index| if (c.JS_IsStrictEqual(self.engine.context, waiter.resolve, functions[0])) {
            const retired = self.waiters.orderedRemove(index);
            self.engine.freeValue(retired.resolve);
            self.engine.freeValue(retired.reject);
            self.engine.freeValue(retired.context);
            break;
        };
        if (cancellation) |*hook| hook.detach() catch {};
    }
    try self.waiters.ensureUnusedCapacity(self.engine.gpa, 1);
    self.waiters.appendAssumeCapacity(.{ .id = id, .conversation = conversation, .resolve = c.JS_DupValue(self.engine.context, functions[0]), .reject = c.JS_DupValue(self.engine.context, functions[1]), .context = c.JS_DupValue(self.engine.context, context) });
    try self.@"resume"();
    return promise;
}
/// Real committed ownership structures admitted on the VM owner. The mirror
/// contains live work and only the ended links that still connect it; it never
/// counts historical Storage rows or invents values for an absent scheduler.
pub fn indexSizes(engine: *Engine, session: c.JSValue) !c.JSValue {
    const manager = try getManager(engine, session);
    const index = if (manager.published_index) |*current| current else return error.TaskPublicationIndexUnavailable;
    const sizes = index.sizes();
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    inline for (std.meta.fields(owner_index.Sizes)) |field| try sdk.put(engine, result, field.name, c.JS_NewInt64(engine.context, @intCast(@field(sizes, field.name))));
    return result;
}
pub fn schedulerClosedError(self: *Manager) !c.JSValue {
    const native = try durable.state(self.engine, self.session);
    if (native.failure_reason) |cause| return @import("native_durable_errors.zig").sessionFailed(self.engine, cause);
    return messageError(self.engine, "Harness is closed");
}
const WaitCancellation = struct {
    engine: *Engine,
    signal: c.JSValue,
    listener: c.JSValue,
    fn detach(self: *WaitCancellation) !void {
        const abort = try sdk.text(self.engine, "abort");
        defer self.engine.freeValue(abort);
        const result = try sdk.invoke(self.engine, self.signal, "removeEventListener", &.{ abort, self.listener });
        self.engine.freeValue(result);
    }
    fn deinit(self: *WaitCancellation) void {
        self.engine.freeValue(self.signal);
        self.engine.freeValue(self.listener);
    }
};
fn waiterCancellation(engine: *Engine, promise: c.JSValue, reject: c.JSValue, context: c.JSValue) !?WaitCancellation {
    if (c.JS_IsUndefined(context) or c.JS_IsNull(context)) return null;
    const signal = try sdk.get(engine, context, "abortSignal");
    errdefer engine.freeValue(signal);
    if (c.JS_IsUndefined(signal) or c.JS_IsNull(signal)) {
        engine.freeValue(signal);
        return null;
    }
    var data = [_]c.JSValue{ signal, reject };
    const listener = try engine.checked(c.JS_NewCFunctionData(engine.context, waiterAborted, 0, 0, data.len, &data));
    errdefer engine.freeValue(listener);
    var hook: WaitCancellation = .{ .engine = engine, .signal = signal, .listener = listener };
    const abort = try sdk.text(engine, "abort");
    defer engine.freeValue(abort);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "once", c.pi_js_bool(engine.context, 1));
    const installed = try sdk.invoke(engine, signal, "addEventListener", &.{ abort, listener, options });
    engine.freeValue(installed);
    errdefer hook.detach() catch {};
    var detach_data = [_]c.JSValue{ signal, listener };
    const detach = try engine.checked(c.JS_NewCFunctionData(engine.context, waiterDetached, 0, 0, detach_data.len, &detach_data));
    defer engine.freeValue(detach);
    const observed = try sdk.invoke(engine, promise, "then", &.{ detach, detach });
    engine.freeValue(observed);
    return hook;
}
fn waiterAborted(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const reason = sdk.get(engine, data[0], "reason") catch |err| return durable.reject(engine, err);
    defer engine.freeValue(reason);
    var arguments = [_]c.JSValue{reason};
    return engine.checked(c.JS_Call(engine.context, data[1], c.pi_js_undefined(), arguments.len, &arguments)) catch |err| durable.reject(engine, err);
}
fn waiterDetached(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const abort = sdk.text(engine, "abort") catch |err| return durable.reject(engine, err);
    defer engine.freeValue(abort);
    return sdk.invoke(engine, data[0], "removeEventListener", &.{ abort, data[1] }) catch |err| durable.reject(engine, err);
}
fn settleWaiters(self: *Manager) !void {
    return settlePublishedWaiters(self, true);
}
fn settlePublishedWaiters(self: *Manager, expire_contexts: bool) !void {
    // Scheduler.idle acquires the native Session line. A worker can be waiting
    // for the owner to finish a transaction, so inspect only after it exits.
    if (expire_contexts and self.thread == null and !self.closed and self.contexts.count() != 0) {
        try self.updateClock();
        const now = Manager.nativeClock(self);
        const settings = try @import("native_durable_agent.zig").runtimeSettings(self.engine, self.options);
        defer self.engine.freeValue(settings);
        const retention_value = try sdk.get(self.engine, settings, "contextRetentionMs");
        defer self.engine.freeValue(retention_value);
        var retention: f64 = 0;
        if (c.JS_ToFloat64(self.engine.context, &retention, retention_value) < 0) return error.JavaScriptException;
        var contexts = self.contexts.iterator();
        while (contexts.next()) |entry| if (entry.value_ptr.*) |*cached| {
            const expired = if (cached.idle_since) |since| @as(f64, @floatFromInt(now - since)) >= retention else false;
            if (expired or (retention <= 0 and try self.scheduler.idle(entry.key_ptr.*))) {
                self.engine.freeValue(cached.view);
                entry.value_ptr.* = null;
            } else if (!try self.scheduler.idle(entry.key_ptr.*)) {
                cached.idle_since = null;
            } else if (cached.idle_since == null) {
                cached.idle_since = now;
            }
        };
    }
    var index = self.waiters.items.len;
    while (index > 0) {
        index -= 1;
        const waiter = self.waiters.items[index];
        var value = c.pi_js_undefined();
        var rejected = false;
        const signal = if (c.JS_IsUndefined(waiter.context) or c.JS_IsNull(waiter.context)) c.pi_js_undefined() else try sdk.get(self.engine, waiter.context, "abortSignal");
        defer self.engine.freeValue(signal);
        const aborted = if (c.JS_IsUndefined(signal) or c.JS_IsNull(signal)) c.pi_js_bool(self.engine.context, 0) else try sdk.get(self.engine, signal, "aborted");
        defer self.engine.freeValue(aborted);
        if (c.JS_ToBool(self.engine.context, aborted) != 0) {
            value = try sdk.get(self.engine, signal, "reason");
            rejected = true;
        } else if (self.closed) {
            value = try schedulerClosedError(self);
            rejected = true;
        } else if (waiter.id) |id| {
            // Source registers live-task waits against #live and resolves them
            // only at publication admission. A native storage swap can become
            // visible between waiter iterations, before its queued VM event.
            if (self.live_task_records.contains(id)) continue;
            // A scheduler commit can swap and free the Memory backend state.
            // The owner must not block on the Session line: a worker holding it
            // can itself be awaiting an owner-VM transaction callback.
            var record = if (self.missing_tasks.contains(id)) @as(?json.Owned, null) else if (self.terminal_tasks.get(id)) |cached| blk: {
                var copy = try json.Owned.empty(self.engine.gpa);
                errdefer copy.deinit();
                copy.value = try json.clone(copy.arena.allocator(), cached.value);
                break :blk @as(?json.Owned, copy);
            } else switch (try readWaiterTask(&self.lease.value, self.engine.gpa, id)) {
                .busy => {
                    try self.requestWaiterRead(id);
                    continue;
                },
                .record => |item| item,
            };
            defer if (record) |*item| item.deinit();
            if (record) |item| {
                const state = try json.required(item.value, "state");
                if (!std.mem.eql(u8, try json.asString(try json.required(state, "status")), "terminal")) continue;
                value = try durable.jsValue(self.engine, item.value);
            } else {
                const message = try std.fmt.allocPrint(self.engine.gpa, "Task {d} does not exist", .{id});
                defer self.engine.gpa.free(message);
                value = try messageError(self.engine, message);
                rejected = true;
            }
        } else if (!try self.publishedIdle(waiter.conversation)) continue;
        defer self.engine.freeValue(value);
        var args = [_]c.JSValue{value};
        const result = try self.engine.checked(c.JS_Call(self.engine.context, if (rejected) waiter.reject else waiter.resolve, c.pi_js_undefined(), 1, &args));
        self.engine.freeValue(result);
        self.engine.freeValue(waiter.resolve);
        self.engine.freeValue(waiter.reject);
        self.engine.freeValue(waiter.context);
        _ = self.waiters.orderedRemove(index);
        if (waiter.id) |id| {
            var waiting = false;
            for (self.waiters.items) |remaining| if (remaining.id == id) {
                waiting = true;
                break;
            };
            if (!waiting) if (self.terminal_tasks.fetchRemove(id)) |removed| {
                var retired = removed.value;
                retired.deinit();
            };
            if (!waiting) {
                _ = self.missing_tasks.remove(id);
                self.retireRead(id);
            }
        }
    }
}
const WaiterRecord = union(enum) { busy, record: ?json.Owned };
fn readWaiterTask(session: *session_mod.Session, gpa: std.mem.Allocator, id: u64) !WaiterRecord {
    const thread = std.Thread.getCurrentId();
    const on_owner = session.ownerThread.load(.acquire) == thread;
    if (!on_owner) {
        // Reserve the same logical line as commits. The subscription mutex is
        // only probed for a pre-existing native barrier, never held over a
        // custom Storage callback or VM work.
        if (session.ownerThread.cmpxchgStrong(0, thread, .acq_rel, .acquire) != null) return .busy;
        if (!session.mutex.tryLock()) {
            session.ownerThread.store(0, .release);
            session.wakeLine();
            return .busy;
        }
        session.mutex.unlock(session.io);
    }
    defer if (!on_owner) {
        session.ownerThread.store(0, .release);
        session.wakeLine();
    };
    return .{ .record = try session.storage.readTableRecord(gpa, .task, id) };
}

test "native durable VM waiter snapshot skips a worker barrier and detaches before later commits or owner callbacks" {
    const gpa = std.testing.allocator;
    var store = try backend.memory.Memory.init(gpa);
    defer store.deinit();
    var session = session_mod.Session.init(gpa, std.testing.io, .{ .memory = &store });
    defer session.deinit();
    var first = try json.Owned.parse(gpa, "[{\"type\":\"task\",\"value\":{\"id\":1,\"state\":{\"status\":\"terminal\",\"result\":{\"version\":1}}}}]");
    defer first.deinit();
    _ = try store.commit(first.value);
    const Barrier = struct {
        session: *session_mod.Session,
        locked: std.atomic.Value(bool) = .init(false),
        release: std.atomic.Value(bool) = .init(false),
        fn worker(self: *@This()) void {
            self.session.mutex.lockUncancelable(self.session.io);
            self.locked.store(true, .release);
            while (!self.release.load(.acquire)) std.atomic.spinLoopHint();
            self.session.mutex.unlock(self.session.io);
        }
    };
    var barrier: Barrier = .{ .session = &session };
    const thread = try std.Thread.spawn(.{}, Barrier.worker, .{&barrier});
    var joined = false;
    defer if (!joined) {
        barrier.release.store(true, .release);
        thread.join();
    };
    while (!barrier.locked.load(.acquire)) std.atomic.spinLoopHint();
    try std.testing.expectEqual(.busy, std.meta.activeTag(try readWaiterTask(&session, gpa, 1)));
    barrier.release.store(true, .release);
    thread.join();
    joined = true;
    var snapshot = (try readWaiterTask(&session, gpa, 1)).record.?;
    defer snapshot.deinit();
    try std.testing.expect(session.mutex.tryLock());
    session.ownerThread.store(std.Thread.getCurrentId(), .release);
    var owner = try readWaiterTask(&session, gpa, 1);
    owner.record.?.deinit();
    session.ownerThread.store(0, .release);
    session.mutex.unlock(session.io);
    for (0..128) |version| {
        first.value.array.items[0].object.getPtr("value").?.object.getPtr("state").?.object.getPtr("result").?.object.getPtr("version").?.* = .{ .integer = @intCast(version + 2) };
        _ = try store.commit(first.value);
    }
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(try json.required(try json.required(try json.required(snapshot.value, "state"), "result"), "version")));
}
pub fn defineTask(engine: *Engine, exports: c.JSValue) !void {
    try sdk.put(engine, exports, "defineTask", try engine.checked(c.JS_NewCFunction(engine.context, define, "defineTask", 1)));
}

fn environmentExercise(gpa: std.mem.Allocator, with_harness: bool) !void {
    const engine = try Engine.init(gpa, .{ .host_await_timeout_ms = 3000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const builtins = try sdk.array(engine);
    defer engine.freeValue(builtins);
    const registry = try @import("native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "registry", c.JS_DupValue(engine.context, registry));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "envSession", c.JS_DupValue(engine.context, session));
    try sdk.put(engine, global, "envRegistry", c.JS_DupValue(engine.context, registry));
    try sdk.put(engine, global, "envMode", try sdk.text(engine, if (with_harness) "harness" else "scheduler"));
    const source = @embedFile("../durable/fixtures/durable-scheduler-env-eba.json");
    try sdk.put(engine, global, "envSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-eba-environment")));
    const Probe = struct {
        fn read(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = Engine.fromContext(context.?);
            return snapshot(owner) catch |err| durable.reject(owner, err);
        }
        fn snapshot(owner: *Engine) !c.JSValue {
            const root = c.JS_GetGlobalObject(owner.context);
            defer owner.freeValue(root);
            const result = try sdk.object(owner);
            errdefer owner.freeValue(result);
            inline for (.{ "envOwnerWait", "envOwnerIdle", "envOwnerCanceled", "envPublicationWait", "envLate" }) |name| {
                const value = try sdk.get(owner, root, name);
                defer owner.freeValue(value);
                try sdk.put(owner, result, name, c.JS_NewInt32(owner.context, if (c.JS_IsObject(value)) c.JS_PromiseState(owner.context, value) else -1));
            }
            const runtime = try sdk.get(owner, root, "envOriginalRuntime");
            defer owner.freeValue(runtime);
            if (runtimeState(owner, runtime)) |private| {
                try sdk.put(owner, result, "active", c.pi_js_bool(owner.context, @intFromBool(private.entry.runtime.isActive())));
                try sdk.put(owner, result, "phaseAborted", try sdk.get(owner, private.signal, "aborted"));
            }
            return result;
        }
    };
    try sdk.put(engine, global, "envPromiseStates", try engine.checked(c.JS_NewCFunction(engine.context, Probe.read, "fixtureEnvPromiseStates", 0)));
    const setup = try engine.evalModule(
        \\import{defineTask}from'@earendil-works/pi-durable';
        \\globalThis.envRows=[];globalThis.envCalls=[];globalThis.envOrdinal=0;globalThis.envCancelObserved=false;globalThis.envValue=Object.freeze({owned:envMode});globalThis.envCause=Object.freeze({cause:envMode});
        \\globalThis.envBuild=function(first,callContext){let receiver;if(envMode==='scheduler'){const proto=Object.getPrototypeOf(this);let forged=false;try{this.resume.call({})}catch(error){forged=error.name==='TypeError'}receiver={same:this===envScheduler,name:this.constructor.name,ownKeys:Reflect.ownKeys(this),prototypeKeys:Reflect.ownKeys(proto),prototypeEnumerable:Object.keys(proto),baseObject:Object.getPrototypeOf(proto)===Object.prototype,methods:Object.getOwnPropertyNames(proto).filter(name=>name!=='constructor').map(name=>({name,length:proto[name].length,writable:Object.getOwnPropertyDescriptor(proto,name).writable,enumerable:Object.getOwnPropertyDescriptor(proto,name).enumerable,configurable:Object.getOwnPropertyDescriptor(proto,name).configurable})),resumeUndefined:this.resume()===undefined,forged};}
        \\ envCalls.push({first:envMode==='scheduler'?first:{keys:Object.keys(first),conversationId:first.conversationId,readSame:first.read===envHarness,cwd:first.cwd},conversationMatches:(envMode==='scheduler'?first:first.conversationId)===1,sameContext:callContext===envSavedContext,undefinedReceiver:this===undefined,...(receiver?{receiver}:{})});envOrdinal++;if(envOrdinal===1){if(envMode==='scheduler'){globalThis.envOwnerWait=this.waitForTask(envTaskId,callContext);globalThis.envOwnerIdle=this.waitForIdle(undefined,callContext);const cancel=new AbortController();globalThis.envOwnerCanceled=this.waitForIdle(undefined,{abortSignal:cancel.signal}).then(()=>false,error=>{envCancelObserved=error===envCause;return error===envCause});cancel.abort(envCause);globalThis.envPublicationController=new AbortController();globalThis.envPublicationWait=this.waitForTask(envTaskId,{abortSignal:envPublicationController.signal});}return envValue;}if(envOrdinal===2)throw envCause;return new Promise(resolve=>globalThis.envRelease=resolve)};
        \\const Parent=defineTask({name:'fixture.env.'+envMode,version:1,initial:()=>({phase:'work'}),phases:{work:async(_,runtime,ctx)=>{try{
        \\ runtime.conversationId=999999;globalThis.envOriginalRuntime=runtime;globalThis.envSaved=runtime.env;globalThis.envSavedContext=ctx;const first=runtime.env(ctx),isPromise=first instanceof Promise,value=await first;let rawCause=false;try{await envSaved.call({},ctx)}catch(error){rawCause=error===envCause}globalThis.envLate=envSaved(ctx);envLate.catch(()=>{});envRows.push({name:envMode,isPromise,originalValue:value===envValue,...(envMode==='scheduler'?{cancellationObserved:envCancelObserved}:{}),rawCause,alias:runtime.env===envSaved});await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:null}}),ctx);
        \\}catch(error){globalThis.envOriginalError=String(error?.stack??error);throw error}}}});
        \\envRegistry.install({name:'actual-env-fixture',tasks:[Parent]});await envSession.commit(tx=>tx.createRootConversation(),{});globalThis.envTaskId=await envSession.commit(tx=>tx.createTask(Parent,null,{conversationId:1,ownership:{kind:'conversation'}}),{});
    , "actual-env-setup.mjs");
    engine.freeValue(setup);
    try sdk.put(engine, options, "env", try sdk.get(engine, global, "envBuild"));
    if (with_harness) {
        // Exercise the real native Harness adapter class independently from
        // public Harness.open, which also requires all builtin task drivers.
        const harness = try @import("native_durable_harness.zig").object(engine, session, options, null);
        defer engine.freeValue(harness);
        const native = try durable.state(engine, session);
        native.creation_owner = c.JS_DupValue(engine.context, harness);
        try sdk.put(engine, global, "envHarness", c.JS_DupValue(engine.context, harness));
    }
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    try attach(engine, session, options, context);
    const manager = try getManager(engine, session);
    if (!with_harness) try sdk.put(engine, global, "envScheduler", try schedulerOwner(manager));
    const id = try sdk.get(engine, global, "envTaskId");
    defer engine.freeValue(id);
    const pending = try wait(manager, try durable.number(engine, id), null, context);
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    defer engine.freeValue(settled);
    var record = try durable.owned(engine, settled);
    defer record.deinit();
    const outcome = try json.required(try json.required(record.value, "state"), "outcome");
    if (!std.mem.eql(u8, try json.asString(try json.required(outcome, "status")), "completed")) {
        const failure = try sdk.get(engine, global, "envOriginalError");
        defer engine.freeValue(failure);
        const text = try engine.toString(failure);
        defer gpa.free(text);
        std.debug.print("Source environment original failure: {s}\n", .{text});
        return error.EnvironmentTaskDidNotComplete;
    }
    // Abort immediately after the outer task waiter returns. Waiting for phase
    // retirement first would conceal a waiter which bypassed publication.
    const abort = try engine.eval("globalThis.envBeforeAbort=envPromiseStates();if(envMode==='scheduler')envPublicationController.abort(envCause);", "env-publication-abort-order", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(abort);
    // The actual Source capture then observes stale methods after five event
    // turns. Observe the genuine native lease retirement before that check.
    const retirement_deadline = std.Io.Clock.awake.now(engine.native_io.?).toMilliseconds() + 3000;
    while (manager.thread != null) {
        _ = try engine.pumpControls();
        if (std.Io.Clock.awake.now(engine.native_io.?).toMilliseconds() >= retirement_deadline) return error.EnvironmentPhaseDidNotRetire;
        if (manager.thread != null) try engine.native_io.?.sleep(.fromMilliseconds(1), .awake);
    }
    const compare = engine.evalModule(
        \\const observed=async(name,pending)=>{try{return await pending}catch(error){throw Error(JSON.stringify({await:name,mode:envMode,originalCause:error===envCause,errorName:error?.name,message:error?.message,beforeAbort:envBeforeAbort,now:envPromiseStates()}))}};envRelease(envValue);const lateValue=await observed('late-environment',envLate);let ended;try{await envSaved({})}catch(error){ended=error.message.replaceAll(String(envTaskId),'$TASK')};
        \\envRows.push({name:envMode+'-settled',lateOriginal:lateValue===envValue,ended,...(envMode==='scheduler'?{ownerWaitMatches:(await observed('owner-task',envOwnerWait)).id===envTaskId,ownerIdleUndefined:(await observed('owner-idle',envOwnerIdle))===undefined,ownerCanceledOriginal:await observed('owner-canceled',envOwnerCanceled),ownerPublicationWins:(await observed('publication-wins',envPublicationWait)).id===envTaskId}:{}),calls:envCalls.map(call=>({...call,first:envMode==='scheduler'?'$CONVERSATION':{...call.first,conversationId:'$CONVERSATION'}}))});
        \\const expected=envSource.cases.filter(row=>row.name===envMode||row.name===envMode+'-settled');if(JSON.stringify(envRows)!==JSON.stringify(expected))throw Error(JSON.stringify({actual:envRows,expected}));export const proof=true;
    , "actual-env-compare.mjs") catch |err| {
        std.debug.print("Source environment comparison: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(compare);
}
test "native durable VM actual scheduler env and genuine Harness env adapter preserve Source original arguments receiver causes and admitted promises" {
    try environmentExercise(std.testing.allocator, false);
    try environmentExercise(std.testing.allocator, true);
}
test "native durable VM runtime conversation callback preserves actual Source receiver binding causes and admitted promises" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const builtins = try sdk.array(engine);
    defer engine.freeValue(builtins);
    const registry = try @import("native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "registry", c.JS_DupValue(engine.context, registry));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "conversationSession", c.JS_DupValue(engine.context, session));
    try sdk.put(engine, global, "conversationRegistry", c.JS_DupValue(engine.context, registry));
    const source = @embedFile("../durable/fixtures/durable-runtime-conversation-source.json");
    try sdk.put(engine, global, "conversationSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-runtime-conversation")));
    const setup = try engine.evalModule(
        \\import{defineTask}from'@earendil-works/pi-durable';
        \\globalThis.conversationRows=[];globalThis.conversationCalls=[];globalThis.conversationOriginal=Object.freeze({conversation:true});globalThis.conversationCause=Object.freeze({cause:true});globalThis.conversationOrdinal=0;
        \\globalThis.conversationBuild=function(id,binding,ctx){globalThis.conversationBinding=binding;conversationCalls.push({id,receiver:this===conversationScheduler,context:ctx===conversationContext,signal:binding.signal===conversationSignal,keys:Object.keys(binding),checkLength:binding.check.length,checkUndefined:binding.check.call({})===undefined});conversationOrdinal++;if(conversationOrdinal===1)return conversationOriginal;if(conversationOrdinal===2)throw conversationCause;return new Promise(resolve=>{globalThis.conversationRelease=resolve})};
        \\const Parent=defineTask({name:'fixture.runtime-conversation',version:1,initial:()=>({phase:'work'}),phases:{work:async(_,runtime,ctx)=>{globalThis.conversationSaved=runtime.conversation;globalThis.conversationContext=ctx;globalThis.conversationSignal=runtime.signal;const first=conversationSaved.call({},777,ctx),value=await first;let rawCause=false;try{await conversationSaved(888,ctx)}catch(error){rawCause=error===conversationCause}globalThis.conversationLate=conversationSaved(999,ctx);conversationLate.catch(()=>{});conversationRows.push({name:'direct',length:conversationSaved.length,isPromise:first instanceof Promise,original:value===conversationOriginal,rawCause});await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:null}}),ctx)}}});
        \\conversationRegistry.install({name:'conversation-fixture',tasks:[Parent]});await conversationSession.commit(tx=>tx.createRootConversation(),{});globalThis.conversationTaskId=await conversationSession.commit(tx=>tx.createTask(Parent,null,{conversationId:1,ownership:{kind:'conversation'}}),{});
    , "runtime-conversation-setup.mjs");
    engine.freeValue(setup);
    try sdk.put(engine, options, "conversation", try sdk.get(engine, global, "conversationBuild"));
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    try attach(engine, session, options, context);
    const manager = try getManager(engine, session);
    try sdk.put(engine, global, "conversationScheduler", try schedulerOwner(manager));
    const id = try sdk.get(engine, global, "conversationTaskId");
    defer engine.freeValue(id);
    const pending = try wait(manager, try durable.number(engine, id), null, context);
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    defer engine.freeValue(settled);
    var record = try durable.owned(engine, settled);
    defer record.deinit();
    try std.testing.expectEqualStrings("completed", try json.asString(try json.required(try json.required(try json.required(record.value, "state"), "outcome"), "status")));
    // The actual Source1 oracle waits five event turns before stale-method
    // checks. Publication settles the task waiter before its phase lease ends.
    // Observe real native retirement here without delaying that public waiter.
    const retirement_deadline = std.Io.Clock.awake.now(engine.native_io.?).toMilliseconds() + 3000;
    while (manager.thread != null) {
        _ = try engine.pumpControls();
        if (std.Io.Clock.awake.now(engine.native_io.?).toMilliseconds() >= retirement_deadline) return error.ConversationPhaseDidNotRetire;
        if (manager.thread != null) try engine.native_io.?.sleep(.fromMilliseconds(1), .awake);
    }
    const compare = engine.evalModule(
        \\globalThis.conversationStage='late-promise';conversationRelease(conversationOriginal);const lateValue=await conversationLate;let ended,checkEnded;globalThis.conversationStage='stale-call';try{await conversationSaved(777,{})}catch(error){ended=error.message.replaceAll(String(conversationTaskId),'$TASK')}globalThis.conversationStage='binding-check';try{conversationBinding.check.call({})}catch(error){checkEnded=error.message.replaceAll(String(conversationTaskId),'$TASK')}conversationRows.push({name:'direct-settled',lateOriginal:lateValue===conversationOriginal,ended,checkEnded,calls:conversationCalls});if(JSON.stringify(conversationRows)!==JSON.stringify(conversationSource.cases))throw Error(JSON.stringify({actual:conversationRows,expected:conversationSource.cases}));export const proof=true;
    , "runtime-conversation-compare.mjs") catch |err| {
        std.debug.print("Source runtime conversation comparison {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no diagnostic" });
        const diagnostic = engine.eval("JSON.stringify({stage:conversationStage,ordinal:conversationOrdinal,signalAborted:conversationSignal.aborted,rows:conversationRows,calls:conversationCalls.map(call=>({id:call.id}))})", "conversation-exact-diagnostic", c.JS_EVAL_TYPE_GLOBAL) catch c.pi_js_undefined();
        defer engine.freeValue(diagnostic);
        const text = engine.toString(diagnostic) catch "no diagnostic value";
        defer if (!std.mem.eql(u8, text, "no diagnostic value")) engine.gpa.free(text);
        std.debug.print("Conversation diagnostic: {s}\n", .{text});
        return err;
    };
    engine.freeValue(compare);
}
test "native durable VM terminal publication precedes a held phase end while admitted conversation promises remain original like Source" {
    const engine = try Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 3000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const builtins = try sdk.array(engine);
    defer engine.freeValue(builtins);
    const registry = try @import("native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "registry", c.JS_DupValue(engine.context, registry));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "heldConversationSession", c.JS_DupValue(engine.context, session));
    try sdk.put(engine, global, "heldConversationRegistry", c.JS_DupValue(engine.context, registry));
    const source = @embedFile("../durable/fixtures/durable-runtime-conversation-source16.json");
    try sdk.put(engine, global, "heldConversationSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-held-phase-source")));
    const setup = try engine.evalModule(
        \\import{defineTask}from'@earendil-works/pi-durable';
        \\globalThis.heldConversationOriginal=Object.freeze({original:true});globalThis.heldConversationCalls=[];globalThis.heldPhaseGate=new Promise(resolve=>globalThis.heldPhaseRelease=resolve);
        \\globalThis.heldConversationBuild=function(id,binding,ctx){globalThis.heldConversationBinding=binding;heldConversationCalls.push({id,receiver:this===heldConversationScheduler,originalContext:ctx===heldConversationContext});return id===999?new Promise(resolve=>globalThis.heldConversationRelease=resolve):heldConversationOriginal};
        \\const Task=defineTask({name:'fixture.held-terminal-phase',version:1,initial:()=>({phase:'run'}),phases:{run:async(_,runtime,ctx)=>{globalThis.heldConversationSaved=runtime.conversation;globalThis.heldConversationContext=ctx;globalThis.heldConversationLate=heldConversationSaved(999,ctx);await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:null}}),ctx);await heldPhaseGate}}});
        \\heldConversationRegistry.install({name:'held-terminal-fixture',tasks:[Task]});await heldConversationSession.commit(tx=>tx.createRootConversation(),{});globalThis.heldConversationTask=await heldConversationSession.commit(tx=>tx.createTask(Task,null,{conversationId:1,ownership:{kind:'conversation'}}),{});
    , "actual-held-phase-setup.mjs");
    engine.freeValue(setup);
    try sdk.put(engine, options, "conversation", try sdk.get(engine, global, "heldConversationBuild"));
    const context_exports = engine.native_module_values.get("@earendil-works/chord/context").?;
    const context = try sdk.get(engine, context_exports, "BACKGROUND_CONTEXT");
    defer engine.freeValue(context);
    try attach(engine, session, options, context);
    const manager = try getManager(engine, session);
    try sdk.put(engine, global, "heldConversationScheduler", try schedulerOwner(manager));
    const during = engine.evalModule(
        \\const task=await heldConversationScheduler.waitForTask(heldConversationTask,{});if(!globalThis.heldConversationSaved)throw Error(JSON.stringify({task,taskId:heldConversationTask}));const value=await heldConversationSaved(444,heldConversationContext),duringCheck=heldConversationBinding.check.call({})===undefined;
        \\heldPhaseRelease();heldConversationRelease(heldConversationOriginal);const late=await heldConversationLate;globalThis.heldConversationObserved={source:'eba849739511223c51a62bbd7e3f1c00f99fb1d0',terminalBeforePhaseEnded:task.state.status==='terminal',duringOriginal:value===heldConversationOriginal,duringCheck,lateOriginal:late===heldConversationOriginal};
    , "actual-held-phase-during.mjs") catch |err| {
        std.debug.print("Held phase during {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no diagnostic" });
        return err;
    };
    engine.freeValue(during);
    const deadline = std.Io.Clock.awake.now(engine.native_io.?).toMilliseconds() + 3000;
    while (manager.thread != null) {
        _ = try engine.pumpControls();
        if (std.Io.Clock.awake.now(engine.native_io.?).toMilliseconds() >= deadline) return error.HeldPhaseDidNotRetire;
        if (manager.thread != null) try engine.native_io.?.sleep(.fromMilliseconds(1), .awake);
    }
    const after = try engine.evalModule(
        \\let ended,checkEnded;try{await heldConversationSaved(777,{})}catch(error){ended=error.message.replaceAll(String(heldConversationTask),'$TASK')}try{heldConversationBinding.check.call({})}catch(error){checkEnded=error.message.replaceAll(String(heldConversationTask),'$TASK')}
        \\const actual={...heldConversationObserved,ended,checkEnded,calls:heldConversationCalls};if(JSON.stringify(actual)!==JSON.stringify(heldConversationSource))throw Error(JSON.stringify({actual,expected:heldConversationSource}));export const proof=true;
    , "actual-held-phase-after.mjs");
    engine.freeValue(after);
}
test "native durable VM genuine scheduler abortConversation matches Source ordinary background and owned conversation traversal" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const builtins = try sdk.array(engine);
    defer engine.freeValue(builtins);
    const registry = try @import("native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "registry", c.JS_DupValue(engine.context, registry));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "abortSession", c.JS_DupValue(engine.context, session));
    try sdk.put(engine, global, "abortRegistry", c.JS_DupValue(engine.context, registry));
    const source = @embedFile("../durable/fixtures/durable-abort-conversation-source.json");
    try sdk.put(engine, global, "abortSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-abort-conversation")));
    const setup = try engine.evalModule(
        \\import{defineTask}from'@earendil-works/pi-durable';
        \\globalThis.abortStarted=0;globalThis.abortRows=[];globalThis.abortStartedPromise=new Promise(resolve=>{globalThis.abortNotifyStarted=resolve});
        \\const Waiting=defineTask({name:'fixture.abort-conversation',version:1,initial:()=>({phase:'work'}),phases:{work:async(_,runtime)=>{abortStarted++;if(abortStarted===3)abortNotifyStarted();await new Promise((_,reject)=>{if(runtime.signal.aborted)reject(runtime.signal.reason);else runtime.signal.addEventListener('abort',()=>reject(runtime.signal.reason),{once:true})})}},abort:async(_,runtime,ctx)=>{await runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),ctx)}});
        \\abortRegistry.install({name:'abort-conversation-fixture',tasks:[Waiting]});await abortSession.commit(tx=>tx.createRootConversation(),{});globalThis.abortOwner=await abortSession.commit(tx=>tx.createTask(Waiting,null,{conversationId:1,ownership:{kind:'conversation'}}),{});globalThis.abortBackground=await abortSession.commit(tx=>tx.createTask(Waiting,null,{conversationId:1,ownership:{kind:'conversation'},background:true}),{});const nested=await abortSession.commit(tx=>tx.createConversation({ownership:{kind:'task',taskId:abortOwner}}),{});globalThis.abortLeaf=await abortSession.commit(tx=>tx.createTask(Waiting,null,{conversationId:nested.id,ownership:{kind:'conversation'}}),{});
    , "abort-conversation-setup.mjs");
    engine.freeValue(setup);
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    try attach(engine, session, options, context);
    const manager = try getManager(engine, session);
    try sdk.put(engine, global, "abortScheduler", try schedulerOwner(manager));
    try manager.@"resume"();
    const proof = engine.evalModule(
        \\await abortStartedPromise;await abortScheduler.abortConversation(1,false,{});const rows=await Promise.all([abortOwner,abortBackground,abortLeaf].map(id=>abortSession.commit(tx=>tx.task(id),{})));abortRows.push({name:'ordinary',statuses:rows.map(row=>row.state.status),outcomes:rows.map(row=>row.state.status==='terminal'?row.state.outcome.status:null),idleUndefined:await abortScheduler.waitForIdle(1,{})===undefined});await abortScheduler.abortConversation(1,true,{});const backgroundDone=await abortSession.commit(tx=>tx.task(abortBackground),{});abortRows.push({name:'background',status:backgroundDone.state.status,outcome:backgroundDone.state.outcome.status});const expected=abortSource.cases.filter(row=>row.name!=='withdraw');if(JSON.stringify(abortRows)!==JSON.stringify(expected))throw Error(JSON.stringify({actual:abortRows,expected}));export const proof=true;
    , "abort-conversation-compare.mjs") catch |err| {
        std.debug.print("Source abort conversation comparison: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(proof);
}
test "native durable VM genuine Harness runtime conversation and submission handles match actual Source invocation gates" {
    const engine = try Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 3000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("../durable/fixtures/durable-runtime-bound-conversation-source.json");
    try sdk.put(engine, global, "boundConversationSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-bound-conversation")));
    var functions: [2]c.JSValue = undefined;
    const retired = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    defer engine.freeValue(retired);
    defer for (functions) |function| engine.freeValue(function);
    try sdk.put(engine, global, "boundConversationRetired", c.JS_DupValue(engine.context, retired));
    const Retirement = struct {
        resolve: c.JSValue,
        settled: bool = false,
        fn pump(owner: *Engine) !bool {
            const self: *@This() = @ptrCast(@alignCast(owner.host_control_context.?));
            if (self.settled) return false;
            const root = c.JS_GetGlobalObject(owner.context);
            defer owner.freeValue(root);
            const runtime = try sdk.get(owner, root, "boundConversationRuntime");
            defer owner.freeValue(runtime);
            const private = runtimeState(owner, runtime) orelse return false;
            if (private.entry.runtime.isActive()) return false;
            const ignored = try owner.checked(c.JS_Call(owner.context, self.resolve, c.pi_js_undefined(), 0, null));
            owner.freeValue(ignored);
            self.settled = true;
            return true;
        }
    };
    var retirement: Retirement = .{ .resolve = functions[0] };
    engine.host_control_context = &retirement;
    engine.host_control_pump = Retirement.pump;
    defer {
        engine.host_control_context = null;
        engine.host_control_pump = null;
    }
    const proof = engine.evalModule(
        \\import{Harness,MemoryStorage,createRegistry,defineExtension,defineTask}from'@earendil-works/pi-durable';
        \\const cases=[];let task,conversation,handle,receipt,idle,savedRuntimeConversation;
        \\const Parent=defineTask({name:'fixture.bound-conversation',version:1,initial:()=>({phase:'work'}),phases:{work:async(_,runtime,ctx)=>{globalThis.boundConversationRuntime=runtime;savedRuntimeConversation=runtime.conversation;globalThis.boundConversationStage='conversation';handle=await runtime.conversation(conversation,ctx);globalThis.boundConversationStage='absent';const absent=await runtime.conversation(999999,ctx);const shape={keys:Object.keys(handle),prototype:Object.getPrototypeOf(handle)===Object.prototype,methods:['submit','abort','waitForIdle'].map(name=>({name,length:handle[name].length,prototype:Object.hasOwn(handle[name],'prototype')}))};handle.id=999999;globalThis.boundConversationStage='submit';receipt=await handle.submit.call({},{type:'write',entry:{kind:'fixture.bound-write',model:[]}},ctx);const receiptShape={keys:Object.keys(receipt),prototype:Object.getPrototypeOf(receipt)===Object.prototype,methods:['status','wait','abort'].map(name=>({name,length:receipt[name].length,prototype:Object.hasOwn(receipt[name],'prototype')}))};globalThis.boundConversationStage='status';const status=await receipt.status.call({},ctx);const receiptId=receipt.id;receipt.id=999999;globalThis.boundConversationStage='wait';const waited=await receipt.wait.call({},ctx);const controller=new AbortController(),cause=Object.freeze({canceled:true});controller.abort(cause);let canceledOriginal=false;try{await handle.submit({type:'write',entry:{kind:'fixture.canceled-write'}},{abortSignal:controller.signal,value:ctx.value.bind(ctx)})}catch(error){canceledOriginal=error===cause}globalThis.boundConversationStage='idle';idle=handle.waitForIdle.call({},ctx);idle.catch(()=>{});cases.push({name:'bound',absent:absent===undefined,shape,receiptShape,status:status.status,waited:waited.status,originalReceipt:status.id===receiptId&&waited.id===receiptId,canceledOriginal});globalThis.boundConversationStage='commit';await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:null}}),ctx)}}});
        \\const registry=createRegistry();registry.install(defineExtension({name:'bound-conversation-fixture',tasks:[Parent]}));const harness=await Harness.open(new MemoryStorage(),{models:{},registry},{});try{const root=await harness.root({});conversation=root.id;task=await root.commit(tx=>tx.createTask(Parent,null,{ownership:{kind:'conversation'}}),{});harness.resume();globalThis.boundConversationStage='outer-wait';const settled=await harness.waitForTask(task,{});if(settled.state.outcome.status!=='completed')throw Error(JSON.stringify(settled));await boundConversationRetired;const ended=[];for(const[name,call]of[['runtime',()=>savedRuntimeConversation(conversation,{})],['submit',()=>handle.submit({type:'write',entry:{kind:'fixture.late-write'}},{})],['abort',()=>handle.abort({})],['idle',()=>handle.waitForIdle({})],['status',()=>receipt.status({})],['wait',()=>receipt.wait({})],['receipt-abort',()=>receipt.abort({})]]){try{await call();ended.push({name,resolved:true})}catch(error){ended.push({name,error:error.message.replaceAll(String(task),'$TASK')})}}const entries=await root.entries({},256,undefined,{});cases.push({name:'bound-settled',idleUndefined:await idle===undefined,ended,writeKinds:entries.items.map(entry=>entry.kind)});}finally{await harness.close({})}if(JSON.stringify(cases)!==JSON.stringify(boundConversationSource.cases))throw Error(JSON.stringify({actual:cases,expected:boundConversationSource.cases}));export const proof=true;
    , "genuine-runtime-bound-conversation.mjs") catch |err| {
        const stage = try sdk.get(engine, global, "boundConversationStage");
        defer engine.freeValue(stage);
        const stage_text = try engine.toString(stage);
        defer engine.gpa.free(stage_text);
        std.debug.print("Bound conversation stage: {s}\n", .{stage_text});
        std.debug.print("Source bound conversation comparison: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(proof);
}
test "native durable VM native inbox withdrawal adopts cached snapshots before genuine Harness publications like Source" {
    const engine = try Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 3000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const Fixture = struct {
        fn owner(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
            const guest = Engine.fromContext(context.?);
            if (argc == 0) return durable.reject(guest, error.InvalidFixtureHarness);
            const harness = @import("native_durable_harness.zig").state(guest, argv[0]) catch |err| return durable.reject(guest, err);
            const manager = getManager(guest, harness.session) catch |err| return durable.reject(guest, err);
            return schedulerOwner(manager) catch |err| durable.reject(guest, err);
        }
    };
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("../durable/fixtures/durable-withdraw-inbox-cache-source.json");
    try sdk.put(engine, global, "withdrawCacheSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-withdraw-cache")));
    try sdk.put(engine, global, "withdrawActualScheduler", try engine.checked(c.JS_NewCFunction(engine.context, Fixture.owner, "fixtureActualScheduler", 1)));
    const proof = engine.evalModule(
        \\import{Harness,MemoryStorage,InboxDoc,createRegistry}from'@earendil-works/pi-durable';const cases=[];
        \\for(const keepWrite of[true,false]){const store=new MemoryStorage(),harness=await Harness.open(store,{models:{},registry:createRegistry()},{});try{const root=await harness.root({});const ids=await root.commit(async tx=>{const first=await tx.createSubmission({conversationId:root.id,type:'input',status:'queued'}),write=keepWrite?await tx.createSubmission({conversationId:root.id,type:'write',status:'queued'}):undefined,second=await tx.createSubmission({conversationId:root.id,type:'input',status:'queued'});(await tx.doc(InboxDoc,root.id)).items.push({id:first.id,mode:'steer',content:'one'},...(write?[{id:write.id,mode:'write',entry:{kind:'fixture.queued-write'}}]:[]),{id:second.id,mode:'followUp',content:'two'});return[first.id,...(write?[write.id]:[]),second.id]},{});const before=await harness.snapshot(InboxDoc,root.id,{});let published;harness.subscribeCommits(publication=>{const change=publication.changes.find(change=>change.type==='document'&&change.record.kind==='pi.inbox');if(change)published=change.value});const scheduler=withdrawActualScheduler(harness);const controller=new AbortController(),cause={cancel:true};controller.abort(cause);let canceledOriginal=false;try{await scheduler.abortConversation(root.id,false,{abortSignal:controller.signal})}catch(error){canceledOriginal=error===cause}if(!canceledOriginal||(await Promise.all(ids.map(id=>store.submission(id,{})))).some(row=>row.status!=='queued'))throw Error('canceled withdrawal changed durable inputs');harness.resume();await scheduler.abortConversation(root.id,false,{});const after=await harness.snapshot(InboxDoc,root.id,{});const cache={beforeCount:before.items.length,afterCount:after.items.length,replaced:before!==after,publishedCanonical:published===after};cases.push({keepWrite,cache});const rows=await Promise.all(ids.map(id=>store.submission(id,{})));if(rows.some((row,index)=>row.status!==(keepWrite&&index===1?'queued':'unanswered')))throw Error('withdrawal settlement');}finally{await harness.close({})}}const expected=withdrawCacheSource.cases.map(({keepWrite,cache})=>({keepWrite,cache}));if(JSON.stringify(cases)!==JSON.stringify(expected))throw Error(JSON.stringify({actual:cases,expected}));export const proof=true;
    , "native-inbox-cache-adoption.mjs") catch |err| {
        std.debug.print("Source native inbox cache comparison: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(proof);
}
test "native durable VM genuine Harness already idle waits ignore preaborted contexts like actual Source" {
    const engine = try Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 3000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("../durable/fixtures/durable-wait-admission-source.json");
    try sdk.put(engine, global, "idleAdmissionSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-idle-admission")));
    const proof = engine.evalModule(
        \\import{Harness,MemoryStorage,createRegistry}from'@earendil-works/pi-durable';const cases=[],controller=new AbortController(),cause={cause:true};controller.abort(cause);const canceled={abortSignal:controller.signal},harness=await Harness.open(new MemoryStorage(),{models:{},registry:createRegistry()},{});try{const root=await harness.root({});for(const[name,call]of[['root-idle',()=>root.waitForIdle(canceled)],['all-idle',()=>harness.waitForIdle(canceled)]]){try{cases.push({name,undefined:await call()===undefined})}catch(error){cases.push({name,original:error===cause,message:error.message})}}await harness.close({});try{await root.waitForIdle(canceled);cases.push({name:'closed-idle',resolved:true})}catch(error){cases.push({name:'closed-idle',original:error===cause,message:error.message})}}finally{await harness.close({})}const expected=idleAdmissionSource.cases.filter(row=>['root-idle','all-idle','closed-idle'].includes(row.name));if(JSON.stringify(cases)!==JSON.stringify(expected))throw Error(JSON.stringify({actual:cases,expected}));export const proof=true;
    , "actual-idle-wait-admission.mjs") catch |err| {
        std.debug.print("Source idle admission comparison: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(proof);
}
test "native durable VM accepted abort writes and conversation reads survive close admission behind the owner line like Source" {
    const engine = try Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 3000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const Fixture = struct {
        fn owner(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
            const guest = Engine.fromContext(context.?);
            if (argc == 0) return durable.reject(guest, error.InvalidFixtureHarness);
            const harness = @import("native_durable_harness.zig").state(guest, argv[0]) catch |err| return durable.reject(guest, err);
            const manager = getManager(guest, harness.session) catch |err| return durable.reject(guest, err);
            return schedulerOwner(manager) catch |err| durable.reject(guest, err);
        }
    };
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "fixtureActualScheduler", try engine.checked(c.JS_NewCFunction(engine.context, Fixture.owner, "fixtureActualScheduler", 1)));
    const source = @embedFile("../durable/fixtures/durable-controls-close-source.json");
    try sdk.put(engine, global, "controlCloseSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-close-controls")));
    const result = engine.evalModule(@embedFile("../durable/fixtures/durable-controls-close-runtime.txt"), "actual-controls-close-admission.mjs") catch |err| {
        std.debug.print("Source close controls {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no diagnostic" });
        return err;
    };
    engine.freeValue(result);
    const compare = engine.evalModule(
        \\if(JSON.stringify(controlCloseCases)!==JSON.stringify(controlCloseSource.cases))throw Error(JSON.stringify({actual:controlCloseCases,expected:controlCloseSource.cases}));export const proof=true;
    , "actual-controls-close-compare.mjs") catch |err| {
        std.debug.print("Source close controls comparison: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(compare);
}
fn schedulerOwnerExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const builtins = try sdk.array(engine);
    defer engine.freeValue(builtins);
    const registry = try @import("native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "registry", c.JS_DupValue(engine.context, registry));
    try attach(engine, session, options, c.pi_js_undefined());
    const manager = try getManager(engine, session);
    const owner = try schedulerOwner(manager);
    defer engine.freeValue(owner);
    const again = try schedulerOwner(manager);
    defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, owner, again));
    // Preserve the native allocation error union for the GPA sweep. The
    // actual Source environment fixture exercises the public C callback.
    const resumed = try schedulerMethodOwned(engine, owner, .@"resume", &.{});
    defer engine.freeValue(resumed);
    try std.testing.expect(c.JS_IsUndefined(resumed));
    try std.testing.expect(manager.scheduler.enabled.load(.acquire));
    manager.close();
    const value = try sdk.invoke(engine, owner, "resume", &.{});
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsUndefined(value));
}
test "native durable VM actual TaskScheduler receiver owner retires every host allocation without a Manager VM cycle" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, schedulerOwnerExercise, .{});
}

test "native durable VM phase dispatch refreshes replacement registry without relying on another outer owner pump" {
    const gpa = std.testing.allocator;
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const options = try engine.eval(
        \\globalThis.registryBoundaryStale=false;
        \\const old={definition:{name:'fixture.boundary',version:1,phases:{next(){registryBoundaryStale=true}},abort(){}}},replacement={definition:{name:'fixture.boundary',version:1,phases:{next(){}},abort(){}}};
        \\globalThis.registryBoundaryTokens={old,replacement,current:old};
        \\({registry:{snapshot(){const token=registryBoundaryTokens.current;return{tasks(){return[token]},task(){return token},installed(){return[]},tools(){return[]},sections(){return[]}}}}});
    , "registry-boundary-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    try attach(engine, session, options, context);
    const manager = try getManager(engine, session);
    var seed = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":1}},{\"type\":\"task\",\"value\":{\"id\":7,\"kind\":\"fixture.boundary\",\"version\":1,\"conversationId\":1,\"input\":{},\"background\":false,\"abortRequested\":false,\"state\":{\"status\":\"running\",\"checkpoint\":{\"phase\":\"next\"}}}}]");
    defer seed.deinit();
    _ = try manager.lease.value.storage.commitAt(seed.value, null);
    const Invocation = std.meta.Child(@FieldType(scheduling.Runtime, "invocation"));
    const invocation = try gpa.create(Invocation);
    invocation.* = .{ .scheduler = &manager.scheduler, .task_id = 7, .conversation_id = 1, .definition = manager.scheduler.definitions.items[0], .mode = .run };
    manager.scheduler.invocations.append(gpa, invocation) catch |err| {
        gpa.destroy(invocation);
        return err;
    };
    const entry = try gpa.create(Entry);
    entry.* = .{ .manager = manager.retain(), .runtime = (scheduling.Runtime{ .invocation = invocation }).retain(), .generation = 1, .definition = 0, .refs = .init(1) };
    manager.ledger.append(std.heap.page_allocator, entry) catch |err| {
        entry.release();
        return err;
    };
    // This synthetic admission bypasses Manager.invoke, which normally owns
    // the dispatch lease before publishing its broker request.
    entry.runtime.beginOwnerDispatch();
    // Simulate the next request arriving in the same Broker.drain call after
    // the prior phase replaced the registry. No Hub.pump refresh occurs here.
    const changed = try engine.eval("registryBoundaryTokens.current=registryBoundaryTokens.replacement", "registry-boundary-replacement", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(changed);
    var payload = try json.Owned.parse(gpa, "{\"record\":{\"id\":7,\"kind\":\"fixture.boundary\",\"version\":1,\"conversationId\":1,\"input\":{},\"background\":false,\"abortRequested\":false,\"state\":{\"status\":\"running\",\"checkpoint\":{\"phase\":\"next\"}}},\"abort\":false}");
    defer payload.deinit();
    const canceled = std.atomic.Value(bool).init(false);
    var reply = try Manager.dispatch(manager, .{ .owner_generation = manager.generation, .task_id = 7, .invocation_generation = 1 }, payload.value, &canceled);
    reply.deinit();
    const stale = try engine.eval("registryBoundaryStale", "registry-boundary-stale-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(stale);
    try std.testing.expect(c.JS_ToBool(engine.context, stale) == 0);
    try std.testing.expect(!invocation.active.load(.acquire));
    var record = (try manager.lease.value.storage.readTableRecord(gpa, .task, 7)).?;
    defer record.deinit();
    try std.testing.expectEqualStrings("pending", try json.asString(try json.required(try json.required(record.value, "state"), "status")));
}
fn publicationAdmissionExercise(gpa: std.mem.Allocator, retiring_signal: bool) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const builtins = try sdk.array(engine);
    defer engine.freeValue(builtins);
    const registry = try @import("native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "publicationAdmissionRegistry", c.JS_DupValue(engine.context, registry));
    const installed = try engine.evalModule(
        \\import{defineTask}from'@earendil-works/pi-durable';const Task=defineTask({name:'fixture.publication-admission',version:1,initial:()=>({phase:'work'}),phases:{work(){}}});publicationAdmissionRegistry.install({name:'publication-admission-fixture',tasks:[Task]});
    , "publication-admission-definition.mjs");
    engine.freeValue(installed);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "registry", c.JS_DupValue(engine.context, registry));
    try attach(engine, session, options, c.pi_js_undefined());
    const manager = try getManager(engine, session);
    var live = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":1}},{\"type\":\"task\",\"value\":{\"id\":2,\"kind\":\"fixture.publication-admission\",\"version\":1,\"conversationId\":1,\"input\":null,\"background\":false,\"abortRequested\":false,\"state\":{\"status\":\"running\",\"checkpoint\":{\"phase\":\"work\"}}}}]");
    defer live.deinit();
    _ = try manager.lease.value.storage.commitAt(live.value, null);
    try manager.cachePublication(live.value);
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    const signal = try aborts.create(engine);
    defer engine.freeValue(signal);
    if (retiring_signal) try sdk.put(engine, context, "abortSignal", c.JS_DupValue(engine.context, signal));
    var promises: [2]c.JSValue = .{ c.pi_js_undefined(), c.pi_js_undefined() };
    defer for (promises) |promise| engine.freeValue(promise);
    for (&promises) |*promise| promise.* = try appendTestWaiter(manager, 2, context);
    var terminal = try json.Owned.parse(gpa, "[{\"type\":\"task\",\"value\":{\"id\":2,\"kind\":\"fixture.publication-admission\",\"version\":1,\"conversationId\":1,\"input\":null,\"background\":false,\"abortRequested\":false,\"state\":{\"status\":\"terminal\",\"outcome\":{\"status\":\"completed\",\"result\":42}}}}]");
    defer terminal.deinit();
    const seq = try manager.lease.value.storage.commitAt(terminal.value, null);
    if (retiring_signal) {
        // The acquire of inactive observes the worker's prior queued event.
        const Invocation = @typeInfo(@TypeOf(@as(scheduling.Runtime, undefined).invocation)).pointer.child;
        const invocation = try gpa.create(Invocation);
        invocation.* = .{ .scheduler = &manager.scheduler, .task_id = 2, .conversation_id = 1, .definition = manager.scheduler.definitions.items[0], .mode = .run, .active = .init(false), .canceled = .init(true) };
        defer invocation.release();
        const entry = try gpa.create(Entry);
        entry.* = .{ .manager = manager.retain(), .runtime = (scheduling.Runtime{ .invocation = invocation }).retain(), .generation = 1, .definition = 0, .refs = .init(1) };
        defer entry.release();
        try manager.signals.ensureUnusedCapacity(gpa, 1);
        manager.signals.appendAssumeCapacity(.{ .entry = entry.retain(), .value = c.JS_DupValue(engine.context, signal), .context = c.JS_DupValue(engine.context, context) });
        const Reenter = struct {
            fn poll(callback_context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
                const owner = Engine.fromContext(callback_context.?);
                const current = getManager(owner, data[0]) catch |err| return durable.reject(owner, err);
                current.pollSignals() catch |err| return durable.reject(owner, err);
                return c.pi_js_undefined();
            }
        };
        var captured = [_]c.JSValue{session};
        const listener = try engine.checked(c.JS_NewCFunctionData(engine.context, Reenter.poll, 0, 0, captured.len, &captured));
        defer engine.freeValue(listener);
        const unsubscribe = try sdk.invoke(engine, session, "subscribeCommits", &.{listener});
        defer engine.freeValue(unsubscribe);
        try Manager.forward(manager, &.{ .seq = seq, .changes = terminal.value });
        // Deliberately skip the normal outer drain. pollSignals must admit the
        // publication which raced that drain before it aborts the phase signal.
        try manager.pollSignals();
        try std.testing.expectEqual(@as(usize, 0), manager.signals.items.len);
        const aborted = try sdk.get(engine, signal, "aborted");
        defer engine.freeValue(aborted);
        try std.testing.expect(c.JS_ToBool(engine.context, aborted) != 0);
    } else {
        // Storage already contains the terminal record, but Source's committed
        // publication has not reached the owner yet. Neither waiter may win.
        try settleWaiters(manager);
        for (promises) |promise| try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, promise));
        try manager.cachePublication(terminal.value);
    }
    for (promises) |promise| {
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, promise));
        const record = c.JS_PromiseResult(engine.context, promise);
        defer engine.freeValue(record);
        const id = try sdk.get(engine, record, "id");
        defer engine.freeValue(id);
        try std.testing.expectEqual(@as(u64, 2), try durable.number(engine, id));
    }
}
test "native durable VM live task waiters cannot observe a terminal storage swap before VM publication admission" {
    try publicationAdmissionExercise(std.testing.allocator, false);
}
test "native durable VM phase signal retirement drains its already queued terminal publication before aborting context waiters" {
    try publicationAdmissionExercise(std.testing.allocator, true);
}
fn publicationWaiterExercise(gpa: std.mem.Allocator, with_worker: bool) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session_value = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session_value);
    const options = try engine.eval("({registry:{snapshot(){return{tasks(){return[]}}}}})", "publication-waiter-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    try attach(engine, session_value, options, c.pi_js_undefined());
    const manager = try getManager(engine, session_value);
    var first = try json.Owned.parse(gpa, "[{\"type\":\"task\",\"value\":{\"id\":1,\"kind\":\"fixture\",\"conversationId\":2,\"background\":false,\"version\":1,\"state\":{\"status\":\"terminal\",\"outcome\":{\"status\":\"completed\",\"result\":42}}}}]");
    defer first.deinit();
    _ = try manager.lease.value.storage.commitAt(first.value, null);
    var promises: [2]c.JSValue = .{ c.pi_js_undefined(), c.pi_js_undefined() };
    defer for (promises) |promise| engine.freeValue(promise);
    for (&promises) |*promise| {
        var functions: [2]c.JSValue = undefined;
        promise.* = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
        manager.waiters.append(gpa, .{ .id = 1, .conversation = null, .resolve = functions[0], .reject = functions[1], .context = c.pi_js_undefined() }) catch |err| {
            engine.freeValue(functions[0]);
            engine.freeValue(functions[1]);
            return err;
        };
    }

    const Barrier = struct {
        session: *session_mod.Session,
        locked: std.atomic.Value(bool) = .init(false),
        release: std.atomic.Value(bool) = .init(false),
        fn run(self: *@This()) void {
            self.session.mutex.lockUncancelable(self.session.io);
            self.locked.store(true, .release);
            while (!self.release.load(.acquire)) std.atomic.spinLoopHint();
            self.session.mutex.unlock(self.session.io);
        }
    };
    var barrier: Barrier = .{ .session = &manager.lease.value };
    var thread: ?std.Thread = null;
    defer if (thread) |worker_thread| {
        barrier.release.store(true, .release);
        worker_thread.join();
    };
    if (with_worker) {
        thread = try std.Thread.spawn(.{}, Barrier.run, .{&barrier});
        while (!barrier.locked.load(.acquire)) std.atomic.spinLoopHint();
    }
    // Admit the publication while the worker line is held: Source settles
    // these promises here, before a later owner poll or invocation abort.
    try manager.cachePublication(first.value);
    try std.testing.expectEqual(@as(usize, 0), manager.terminal_tasks.count());
    // The fulfilled VM result owns its contents independently of the event.
    first.value.array.items[0].object.getPtr("value").?.object.getPtr("version").?.* = .{ .integer = 99 };
    try settleWaiters(manager);
    try std.testing.expectEqual(@as(usize, 0), manager.waiters.items.len);
    try std.testing.expectEqual(@as(usize, 0), manager.terminal_tasks.count());
    for (promises) |promise| {
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, promise));
        const result = c.JS_PromiseResult(engine.context, promise);
        defer engine.freeValue(result);
        const version = try sdk.get(engine, result, "version");
        defer engine.freeValue(version);
        var number: i64 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt64(engine.context, &number, version));
        try std.testing.expectEqual(@as(i64, 1), number);
    }
}
test "native durable VM committed terminal publications settle all joins behind a held worker line and retire owned snapshots" {
    try publicationWaiterExercise(std.testing.allocator, true);
}
test "native durable VM committed terminal publication DTO cache and multiple waiter settlement unwind every GPA failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, publicationWaiterExercise, .{false});
}
fn appendTestWaiter(manager: *Manager, id: u64, context: c.JSValue) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const promise = try manager.engine.checked(c.JS_NewPromiseCapability(manager.engine.context, &functions));
    errdefer {
        manager.engine.freeValue(promise);
        manager.engine.freeValue(functions[0]);
        manager.engine.freeValue(functions[1]);
    }
    const owned_context = c.JS_DupValue(manager.engine.context, context);
    errdefer manager.engine.freeValue(owned_context);
    try manager.waiters.append(manager.engine.gpa, .{ .id = id, .conversation = null, .resolve = functions[0], .reject = functions[1], .context = owned_context });
    return promise;
}
fn lateWaiterExercise(gpa: std.mem.Allocator, with_worker: bool) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session_value = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session_value);
    const options = try engine.eval("({registry:{snapshot(){return{tasks(){return[]}}}}})", "late-waiter-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    try attach(engine, session_value, options, c.pi_js_undefined());
    const manager = try getManager(engine, session_value);
    var first = try json.Owned.parse(gpa, "[{\"type\":\"task\",\"value\":{\"id\":1,\"kind\":\"fixture\",\"conversationId\":2,\"background\":false,\"version\":1,\"state\":{\"status\":\"terminal\",\"outcome\":{\"status\":\"completed\",\"result\":42}}}}]");
    defer first.deinit();
    _ = try manager.lease.value.storage.commitAt(first.value, null);
    try manager.cachePublication(first.value);
    try std.testing.expectEqual(@as(usize, 0), manager.terminal_tasks.count());
    const signal = try sdk.object(engine);
    defer engine.freeValue(signal);
    try sdk.put(engine, signal, "aborted", c.pi_js_bool(engine.context, 0));
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    try sdk.put(engine, context, "abortSignal", c.JS_DupValue(engine.context, signal));
    const canceled = try appendTestWaiter(manager, 1, context);
    defer engine.freeValue(canceled);
    const Service = struct {
        manager: *Manager,
        locked: std.atomic.Value(bool) = .init(false),
        command: std.atomic.Value(u32) = .init(0),
        processed: std.atomic.Value(u32) = .init(0),
        release: std.atomic.Value(bool) = .init(false),
        failure: ?anyerror = null,
        fn callback(raw: ?*anyopaque, tx: *session_mod.Transaction, _: @import("../durable/types.zig").Context) !json.Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.locked.store(true, .release);
            while (!self.release.load(.acquire)) {
                const next = self.command.load(.acquire);
                if (next != self.processed.load(.acquire)) {
                    try Manager.pollReads(self.manager, tx.session);
                    self.processed.store(next, .release);
                } else std.atomic.spinLoopHint();
            }
            return .null;
        }
        fn run(self: *@This()) void {
            var result = self.manager.lease.value.commit(callback, self, .{}, .{}) catch |err| {
                self.failure = err;
                self.locked.store(true, .release);
                return;
            };
            result.deinit();
        }
        fn service(self: *@This(), number: u32, worker: bool) !void {
            if (worker) {
                self.command.store(number, .release);
                while (self.processed.load(.acquire) != number) std.atomic.spinLoopHint();
            } else try Manager.pollReads(self.manager, &self.manager.lease.value);
        }
    };
    var service: Service = .{ .manager = manager };
    var thread: ?std.Thread = null;
    defer if (thread) |worker| {
        service.release.store(true, .release);
        worker.join();
    };
    if (with_worker) {
        thread = try std.Thread.spawn(.{}, Service.run, .{&service});
        while (!service.locked.load(.acquire)) std.atomic.spinLoopHint();
    } else manager.lease.value.mutex.lockUncancelable(manager.lease.value.io);
    defer if (!with_worker) manager.lease.value.mutex.unlock(manager.lease.value.io);
    try settleWaiters(manager);
    try std.testing.expectEqual(@as(usize, 1), manager.pending_reads.count());
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, canceled));
    try service.service(1, with_worker);
    if (with_worker) {
        // Another Session can reuse the same task id and local read generation.
        // A reply from this owner must still be rejected by that owner.
        const other_storage = try durable.memoryObject(engine);
        defer engine.freeValue(other_storage);
        const other_session = try durable.sessionObject(engine, other_storage);
        defer engine.freeValue(other_session);
        try attach(engine, other_session, options, c.pi_js_undefined());
        const other = try getManager(engine, other_session);
        var other_writes = try json.Owned.parse(gpa, "[{\"type\":\"task\",\"value\":{\"id\":1,\"kind\":\"fixture\",\"conversationId\":2,\"background\":false,\"version\":2,\"state\":{\"status\":\"terminal\",\"outcome\":{\"status\":\"completed\",\"result\":84}}}}]");
        defer other_writes.deinit();
        _ = try other.lease.value.storage.commitAt(other_writes.value, null);
        const foreign_wait = try appendTestWaiter(other, 1, c.pi_js_undefined());
        defer engine.freeValue(foreign_wait);
        try other.requestWaiterRead(1);
        var foreign_copy = try json.Owned.empty(std.heap.page_allocator);
        var foreign_consumed = false;
        errdefer if (!foreign_consumed) foreign_copy.deinit();
        foreign_copy.value = try json.clone(foreign_copy.arena.allocator(), first.value.array.items[0].object.get("value").?);
        try other.read_replies.append(std.heap.page_allocator, .{ .query = .{ .id = 1, .generation = 1, .owner_generation = manager.generation }, .record = foreign_copy });
        foreign_consumed = true;
        try other.drainReads();
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, foreign_wait));
        other.lease.value.mutex.lockUncancelable(other.lease.value.io);
        defer other.lease.value.mutex.unlock(other.lease.value.io);
        try Manager.pollReads(other, &other.lease.value);
        try other.drainReads();
        try settleWaiters(other);
        const result = c.JS_PromiseResult(engine.context, foreign_wait);
        defer engine.freeValue(result);
        const version = try sdk.get(engine, result, "version");
        defer engine.freeValue(version);
        var number: i64 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt64(engine.context, &number, version));
        try std.testing.expectEqual(@as(i64, 2), number);
    }
    try sdk.put(engine, signal, "aborted", c.pi_js_bool(engine.context, 1));
    try settleWaiters(manager);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, canceled));
    const current = try appendTestWaiter(manager, 1, c.pi_js_undefined());
    defer engine.freeValue(current);
    try settleWaiters(manager);
    // The previous generation's already-owned reply must not settle a newly
    // registered waiter, even for the same task in the same Session.
    try manager.drainReads();
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, current));
    try std.testing.expectEqual(@as(usize, 1), manager.pending_reads.count());
    try service.service(2, with_worker);
    try manager.drainReads();
    try settleWaiters(manager);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, current));
    try std.testing.expectEqual(@as(usize, 0), manager.pending_reads.count());
    try std.testing.expectEqual(@as(usize, 0), manager.terminal_tasks.count());
    try std.testing.expectEqual(@as(usize, 0), manager.missing_tasks.count());
    const missing = try appendTestWaiter(manager, 99999, c.pi_js_undefined());
    defer engine.freeValue(missing);
    try settleWaiters(manager);
    try service.service(3, with_worker);
    try manager.drainReads();
    try settleWaiters(manager);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, missing));
    try std.testing.expectEqual(@as(usize, 0), manager.pending_reads.count());
    try std.testing.expectEqual(@as(usize, 0), manager.missing_tasks.count());
}
test "native durable VM late terminal waiters progress behind worker line and reject retired read generations" {
    try lateWaiterExercise(std.testing.allocator, true);
}
test "native durable VM late waiter read queries replies and cancellation unwind every GPA failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, lateWaiterExercise, .{false});
}

test "native durable VM runtime abortOwned uses real fixture task handlers and matches actual Source direct ownership and terminal cleanup" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const builtins = try sdk.array(engine);
    defer engine.freeValue(builtins);
    // This kernel fixture runs genuine custom task handlers. It does not claim
    // native Harness builtin-task availability or synthesize builtin tokens.
    const registry = try @import("native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "registry", c.JS_DupValue(engine.context, registry));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "ownedKernelSession", c.JS_DupValue(engine.context, session));
    try sdk.put(engine, global, "ownedKernelRegistry", c.JS_DupValue(engine.context, registry));
    const source = @embedFile("../durable/fixtures/durable-abort-owned-eba.json");
    try sdk.put(engine, global, "ownedKernelSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-abort-owned")));
    const setup = try engine.evalModule(
        \\import{defineTask}from'@earendil-works/pi-durable';
        \\globalThis.ownedKernelRows=[];
        \\const Child=defineTask({name:'fixture.owned-child',version:1,initial:()=>({phase:'work'}),phases:{work:async(_,runtime)=>{await new Promise((_,reject)=>{if(runtime.signal.aborted)reject(runtime.signal.reason);else runtime.signal.addEventListener('abort',()=>reject(runtime.signal.reason),{once:true})})}},abort:async(_,runtime,ctx)=>{await runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),ctx)}});
        \\const Parent=defineTask({name:'fixture.owner',version:1,initial:()=>({phase:'work'}),phases:{work:async(_,runtime,ctx)=>{try{
        \\ globalThis.ownedParentRuntime=runtime;
        \\ for(const[name,id]of[['foreign',ownedForeignId],['missing',999]]){try{await runtime.abortOwned(id,ctx);ownedKernelRows.push({name,unexpected:true})}catch(error){ownedKernelRows.push({name,message:error.message})}}
        \\ let child;await runtime.commit(async tx=>{child=await tx.createTask(Child,null,{ownership:{kind:'task',taskId:runtime.taskId}})},ctx);globalThis.ownedChildId=child;
        \\ const result=await runtime.abortOwned(child,ctx),record=await runtime.getTask(child,ctx);
        \\ ownedKernelRows.push({name:'owned-live',undefinedResult:result===undefined,status:record.state.status,outcome:record.state.outcome.status,owner:record.owner===runtime.taskId});
        \\ ownedKernelRows.push({name:'owned-terminal',undefinedResult:await runtime.abortOwned(child,ctx)===undefined});
        \\ const controller=new AbortController();controller.abort({canceled:true});const ignored=await runtime.abortOwned(child,{...ctx,abortSignal:controller.signal});ownedKernelRows.push({name:'canceled-terminal-read',undefinedResult:ignored===undefined});
        \\ await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:null}}),ctx);
        \\}catch(error){globalThis.ownedParentFailure=String(error?.stack??error);throw error}}}});
        \\ownedKernelRegistry.install({name:'actual-fixture-tasks',tasks:[Parent,Child]});
        \\await ownedKernelSession.commit(tx=>tx.createRootConversation(),{});
        \\globalThis.ownedForeignId=await ownedKernelSession.commit(tx=>tx.createTask(Child,null,{conversationId:1,ownership:{kind:'conversation'}}),{});
        \\globalThis.ownedParentId=await ownedKernelSession.commit(tx=>tx.createTask(Parent,null,{conversationId:1,ownership:{kind:'conversation'}}),{});
    , "actual-owned-kernel-setup.mjs");
    engine.freeValue(setup);
    const fixture_context = try sdk.object(engine);
    defer engine.freeValue(fixture_context);
    try attach(engine, session, options, fixture_context);
    const manager = try getManager(engine, session);
    const id = try sdk.get(engine, global, "ownedParentId");
    defer engine.freeValue(id);
    const pending = try wait(manager, try durable.number(engine, id), null, fixture_context);
    defer engine.freeValue(pending);
    const settled = engine.awaitValue(pending) catch |err| {
        std.debug.print("Actual Source abortOwned: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(settled);
    const inspected = try durable.owned(engine, settled);
    defer {
        var data = inspected;
        data.deinit();
    }
    const outcome = try json.required(try json.required(inspected.value, "state"), "outcome");
    if (!std.mem.eql(u8, try json.asString(try json.required(outcome, "status")), "completed")) {
        const encoded = try engine.stringify(settled);
        defer engine.gpa.free(encoded);
        std.debug.print("Owned task settled without completion: {s}\n", .{encoded});
        const phase_error = try sdk.get(engine, global, "ownedParentFailure");
        defer engine.freeValue(phase_error);
        const text = try engine.toString(phase_error);
        defer engine.gpa.free(text);
        std.debug.print("Owned task original VM failure: {s}; native diagnostic: {s}\n", .{ text, engine.last_error orelse "none" });
        return error.OwnedTaskDidNotComplete;
    }
    const compare = engine.evalModule(
        \\for(const row of ownedKernelRows)if(row.message)row.message=row.message.replaceAll(String(ownedForeignId),'$FOREIGN').replaceAll(String(ownedParentId),'$PARENT');
        \\const source=ownedKernelSource.cases.filter(row=>!['retired-runtime','reports'].includes(row.name));
        \\if(JSON.stringify(ownedKernelRows)!==JSON.stringify(source))throw Error(JSON.stringify({actual:ownedKernelRows,source}));
    , "actual-owned-kernel-compare.mjs") catch |err| {
        std.debug.print("Actual Source abortOwned comparison: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(compare);
}
test "native durable VM runtime methods retain original invocation through extracted aliases and fake receivers as Source closures" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const builtins = try sdk.array(engine);
    defer engine.freeValue(builtins);
    const registry = try @import("native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "registry", c.JS_DupValue(engine.context, registry));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "boundSession", c.JS_DupValue(engine.context, session));
    try sdk.put(engine, global, "boundRegistry", c.JS_DupValue(engine.context, registry));
    const source = @embedFile("../durable/fixtures/durable-runtime-bound-eba.json");
    try sdk.put(engine, global, "boundSource", try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-eba-runtime-closures")));
    const setup = try engine.evalModule(
        \\import{defineTask}from'@earendil-works/pi-durable';
        \\globalThis.boundRows=[];globalThis.boundReports=[];globalThis.boundReport=error=>boundReports.push(error);globalThis.boundClock=()=>123;
        \\globalThis.boundNames=['getTask','outcomes','entry','now','report','memo','snapshot','snapshotAsOf','watchDoc','agent','env','context','sleep','waitForTask','abortOwned','commit'];
        \\const Parent=defineTask({name:'fixture.runtime-bound',version:1,initial:()=>({phase:'work'}),phases:{work:async(_,runtime,ctx)=>{try{
        \\ globalThis.boundSaved={runtime,methods:Object.fromEntries(boundNames.map(name=>[name,runtime[name]])),settings:Object.getOwnPropertyDescriptor(runtime,'settings').get,registry:Object.getOwnPropertyDescriptor(runtime,'registry').get};
        \\ const fake=new Proxy({},{get(){throw Error('must not inspect fake receiver')}}),methods=boundSaved.methods;
        \\ const record=await methods.getTask.call(fake,runtime.taskId,ctx),candidate={owned:true},memo=await methods.memo.call(fake,'bound',candidate,ctx),reread=await methods.memo.call(fake,'bound',ctx);
        \\ const entry=await methods.entry.call(fake,999,ctx),env=await methods.env.call(fake,ctx);await methods.sleep.call(fake,123,ctx);await methods.commit.call(fake,()=>undefined,ctx);
        \\ globalThis.boundMarker=Object.freeze({report:true});methods.report.call(fake,boundMarker);
        \\ boundRows.push({name:'active',recordMatches:record.id===runtime.taskId,memoValue:memo,memoRetained:reread,entryUndefined:entry===undefined,envUndefined:env===undefined,now:methods.now.call(fake),aliases:boundNames.every(name=>methods[name]===runtime[name]),settingsEqual:JSON.stringify(boundSaved.settings.call(fake))===JSON.stringify(runtime.settings),registrySame:boundSaved.registry.call(fake)===runtime.registry,functions:boundNames.map(name=>({name,length:methods[name].length,hasPrototype:Object.hasOwn(methods[name],'prototype')}))});
        \\ await methods.commit.call(fake,()=>({status:'terminal',outcome:{status:'completed',result:null}}),ctx);
        \\}catch(error){globalThis.boundOriginalError=String(error?.stack??error);throw error}}}});
        \\boundRegistry.install({name:'actual-runtime-closures',tasks:[Parent]});
        \\await boundSession.commit(tx=>tx.createRootConversation(),{});
        \\globalThis.boundTaskId=await boundSession.commit(tx=>tx.createTask(Parent,null,{conversationId:1,ownership:{kind:'conversation'}}),{});
    , "actual-runtime-bound-setup");
    engine.freeValue(setup);
    try sdk.put(engine, options, "now", try sdk.get(engine, global, "boundClock"));
    try sdk.put(engine, options, "onReport", try sdk.get(engine, global, "boundReport"));
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    try attach(engine, session, options, context);
    const manager = try getManager(engine, session);
    const id = try sdk.get(engine, global, "boundTaskId");
    defer engine.freeValue(id);
    const pending = try wait(manager, try durable.number(engine, id), null, context);
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    defer engine.freeValue(settled);
    var record = try durable.owned(engine, settled);
    defer record.deinit();
    const outcome = try json.required(try json.required(record.value, "state"), "outcome");
    if (!std.mem.eql(u8, try json.asString(try json.required(outcome, "status")), "completed")) {
        const failure = try sdk.get(engine, global, "boundOriginalError");
        defer engine.freeValue(failure);
        const message = try engine.toString(failure);
        defer engine.gpa.free(message);
        std.debug.print("Source bound runtime original error: {s}\n", .{message});
        return error.BoundRuntimeTaskDidNotComplete;
    }
    const saved = try sdk.get(engine, global, "boundSaved");
    defer engine.freeValue(saved);
    const saved_runtime = try sdk.get(engine, saved, "runtime");
    defer engine.freeValue(saved_runtime);
    for (0..200) |_| {
        if (!runtimeState(engine, saved_runtime).?.entry.runtime.isActive()) break;
        _ = try engine.pumpControls();
        _ = try engine.drainReadyJobs();
        try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    }
    try std.testing.expect(!runtimeState(engine, saved_runtime).?.entry.runtime.isActive());
    const compared = engine.evalModule(
        \\const fake={},errors=[];for(const name of boundNames){try{await boundSaved.methods[name].call(fake);errors.push({name,unexpected:true})}catch(error){errors.push({name,message:error.message.replaceAll(String(boundTaskId),'$TASK')})}}
        \\boundRows.push({name:'retired',errors,settingsEqual:JSON.stringify(boundSaved.settings.call(fake))===JSON.stringify(boundSaved.runtime.settings),registrySame:boundSaved.registry.call(fake)===boundSaved.runtime.registry,reportedOriginal:boundReports.length===1&&boundReports[0]===boundMarker});
        \\if(JSON.stringify(boundRows)!==JSON.stringify(boundSource.cases))throw Error(JSON.stringify({actual:boundRows,source:boundSource.cases}));
    , "actual-runtime-bound-compare") catch |err| {
        std.debug.print("Source bound runtime comparison: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(compared);
}
fn migrationKey(allocator: std.mem.Allocator, input: json.Value, checkpoint: json.Value, from: u64) ![]u8 {
    var values = [_]json.Value{ input, checkpoint, .{ .integer = @intCast(from) } };
    return json.stringify(allocator, .{ .array = std.array_list.Managed(json.Value).fromOwnedSlice(allocator, &values) });
}
fn define(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const object = sdk.object(engine) catch |err| return durable.reject(engine, err);
    sdk.put(engine, object, "definition", c.JS_DupValue(engine.context, if (argc > 0) argv[0] else c.pi_js_undefined())) catch |err| {
        engine.freeValue(object);
        return durable.reject(engine, err);
    };
    return object;
}

fn definitionAllocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    const options = try engine.eval("(()=>{const task={definition:{name:'gpa-task',version:1,initial(){return{phase:'one'}},phases:{one(){},two(){}},abort(){}}};return{registry:{snapshot(){return{tasks(){return[task]}}}}}})()", "owned-task-definition-user-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    try attach(engine, session, options, c.pi_js_undefined());
}
test "native durable VM task definitions scheduler subscriptions and Session leases roll back every GPA failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, definitionAllocationExercise, .{});
}
