//! Public task runtime. Scheduler threads carry native leases and owned JSON only.
const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const scheduling = @import("../durable/scheduler.zig");
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
const Event = struct { seq: u64, changes: json.Owned };
const Entry = struct {
    manager: *Manager,
    runtime: scheduling.Runtime,
    generation: u64,
    definition: usize,
    active: std.atomic.Value(bool) = .init(true),
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
};
const Runtime = struct { entry: *Entry, session: c.JSValue, signal: c.JSValue, context: c.JSValue, agent: c.JSValue, snapshot: c.JSValue };
const RuntimeMethod = enum(c_int) { getTask, outcomes, entry, now, report, memo, snapshot, snapshotAsOf, watchDoc, agent, env, context, sleep, waitForTask };
const Waiter = struct { id: ?u64, conversation: ?u64, resolve: c.JSValue, reject: c.JSValue, context: c.JSValue };
const Signal = struct { entry: *Entry, value: c.JSValue, context: c.JSValue };
const Sleeper = struct { runtime: c.JSValue, until: f64, context: c.JSValue, resolve: c.JSValue, reject: c.JSValue };
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
    last_count: usize = 0,
    driver_failure: ?anyerror = null,
    clock_value: std.atomic.Value(i64) = .init(0),
    custom_clock: bool = false,
    clock_callback: c.JSValue,
    fn nativeClock(raw: ?*anyopaque) i64 {
        const self: *Manager = @ptrCast(@alignCast(raw.?));
        return if (self.custom_clock) self.clock_value.load(.acquire) else std.Io.Clock.real.now(self.lease.value.io).toMilliseconds();
    }
    fn updateClock(self: *Manager) !void {
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
        std.debug.assert(self.closed and self.thread == null and self.ledger.items.len == 0);
        self.scheduler.deinit();
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
        for (self.events.items) |*event| event.changes.deinit();
        self.events.deinit(std.heap.page_allocator);
        self.ledger.deinit(std.heap.page_allocator);
        self.waiters.deinit(self.engine.gpa);
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
        self.events.append(std.heap.page_allocator, .{ .seq = event.seq, .changes = changes }) catch |err| {
            self.mutex.unlock(self.lease.value.io);
            return err;
        };
        self.mutex.unlock(self.lease.value.io);
        if (self.broker.notify.call) |notify| notify(self.broker.notify.context);
    }
    fn deliver(raw: ?*anyopaque) !void {
        const self: *Manager = @ptrCast(@alignCast(raw.?));
        while (true) {
            self.mutex.lockUncancelable(self.lease.value.io);
            if (self.events.items.len == 0) {
                self.mutex.unlock(self.lease.value.io);
                return;
            }
            var event = self.events.orderedRemove(0);
            self.mutex.unlock(self.lease.value.io);
            defer event.changes.deinit();
            const parent = try durable.state(self.engine, self.session);
            try durable.deliverPublication(parent, &.{ .seq = event.seq, .changes = event.changes.value });
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
            const signal = self.signals.items[index];
            if (signal.entry.runtime.isActive() and !signal.entry.runtime.context().aborted() and !self.closed) continue;
            const aborted = try sdk.get(self.engine, signal.value, "aborted");
            defer self.engine.freeValue(aborted);
            if (c.JS_ToBool(self.engine.context, aborted) == 0) {
                const failure = try endedError(self.engine, signal.entry.runtime.taskId());
                defer self.engine.freeValue(failure);
                try aborts.abort(self.engine, signal.value, failure);
            }
            if (!signal.entry.runtime.isActive()) {
                _ = self.signals.orderedRemove(index);
                self.engine.freeValue(signal.value);
                self.engine.freeValue(signal.context);
                signal.entry.release();
            }
        }
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
        defer {
            entry.active.store(false, .release);
            entry.release();
            if (self.broker.notify.call) |notify| notify(self.broker.notify.context);
        }
        var payload = try json.Owned.empty(std.heap.page_allocator);
        defer payload.deinit();
        payload.value = .{ .object = .empty };
        try payload.value.object.put(payload.arena.allocator(), "record", try json.clone(payload.arena.allocator(), record));
        try payload.value.object.put(payload.arena.allocator(), "abort", .{ .bool = is_abort });
        var result = try self.broker.call(std.heap.page_allocator, .{ .owner_generation = self.generation, .task_id = runtime.taskId(), .invocation_generation = generation }, payload.value, runtime.context().abort_flag);
        result.deinit();
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
        self.mutex.lockUncancelable(self.lease.value.io);
        var found: ?*Entry = null;
        for (self.ledger.items) |entry| if (entry.generation == identity.invocation_generation and entry.runtime.taskId() == identity.task_id and entry.active.load(.acquire)) {
            found = entry.retain();
            break;
        };
        self.mutex.unlock(self.lease.value.io);
        const entry = found orelse return error.StaleTaskInvocation;
        defer entry.release();
        if (identity.owner_generation != self.generation or self.closed) return error.StaleTaskOwner;
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
        var args = [_]c.JSValue{ record, runtime, context };
        const promise = try self.engine.checked(c.JS_Call(self.engine.context, function, c.pi_js_undefined(), args.len, &args));
        defer self.engine.freeValue(promise);
        const settled = try self.engine.awaitValue(promise);
        self.engine.freeValue(settled);
        return json.Owned.empty(self.engine.gpa);
    }
    pub fn close(self: *Manager) void {
        if (self.closed) return;
        self.closed = true;
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
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }
};
const Hub = struct {
    engine: *Engine,
    managers: std.ArrayList(*Manager) = .empty,
    next_generation: u64 = 1,
    fn pump(engine: *Engine) !bool {
        const self: *Hub = @ptrCast(@alignCast(engine.native_durable_control_context.?));
        var worked = false;
        for (self.managers.items) |manager| {
            if (!manager.closed) try manager.refreshRegistry();
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
                    manager.mutex.unlock(manager.lease.value.io);
                    break;
                }
                var event = manager.events.orderedRemove(0);
                manager.mutex.unlock(manager.lease.value.io);
                defer event.changes.deinit();
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
            try settleWaiters(manager);
            if (!manager.closed and manager.thread == null and manager.enabled and manager.last_count > 0) try manager.start();
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
pub fn attach(engine: *Engine, session: c.JSValue, options: c.JSValue, context: c.JSValue) !void {
    if (!engine.abort_signals_ready) try aborts.install(engine);
    try registerRuntimeClass(engine);
    const owner = try hub(engine);
    const native = try durable.state(engine, session);
    const self = try engine.gpa.create(Manager);
    errdefer engine.gpa.destroy(self);
    const registry = try sdk.get(engine, options, "registry");
    errdefer engine.freeValue(registry);
    const snapshot = try sdk.invoke(engine, registry, "snapshot", &.{});
    errdefer engine.freeValue(snapshot);
    const clock_callback = try sdk.get(engine, options, "now");
    errdefer engine.freeValue(clock_callback);
    self.* = .{ .engine = engine, .hub = owner, .lease = native.session_lease.?.retain(), .session = c.JS_DupValue(engine.context, session), .options = c.JS_DupValue(engine.context, options), .context = c.JS_DupValue(engine.context, context), .registry = registry, .snapshot = snapshot, .generation = owner.next_generation, .clock_callback = clock_callback, .custom_clock = !c.JS_IsUndefined(clock_callback), .scheduler = try scheduling.Scheduler.init(engine.gpa, native.session.?.io, native.session.?, .{}), .broker = broker_mod.Broker.init(engine.gpa, native.session.?.io, owner.next_generation, .{ .context = engine.host_owner_notify_context, .call = engine.host_owner_notify }) };
    owner.next_generation += 1;
    errdefer {
        self.closed = true;
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
    try self.scheduler.open();
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
    const task_options: session_mod.TaskOptions = .{ .conversationId = if (json.get(options_value.value, "conversationId")) |id| try json.asInteger(id) else null, .ownerTaskId = if (std.mem.eql(u8, ownership_kind, "task")) try json.asInteger(try json.required(ownership, "taskId")) else null, .background = if (json.get(options_value.value, "background")) |value| value.bool else false };
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
    const settings_getter = try engine.checked(c.JS_NewCFunction(engine.context, runtimeSettingsGetter, "get settings", 0));
    if (c.JS_DefinePropertyGetSet(engine.context, object, settings_atom, settings_getter, c.pi_js_undefined(), c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
    try sdk.put(engine, object, "commit", try engine.checked(c.JS_NewCFunction(engine.context, runtimeCommit, "commit", 2)));
    const hooks = try sdk.object(engine);
    defer engine.freeValue(hooks);
    var hook_data = [_]c.JSValue{object};
    try sdk.put(engine, hooks, "each", try engine.checked(c.JS_NewCFunctionData(engine.context, hooksEach, 2, 0, hook_data.len, &hook_data)));
    try sdk.put(engine, object, "hooks", c.JS_DupValue(engine.context, hooks));
    inline for (std.meta.fields(RuntimeMethod)) |operation| try sdk.put(engine, object, operation.name, try engine.checked(c.pi_js_function_magic(engine.context, runtimeMethod, operation.name, 2, @intCast(operation.value))));
    runtime.* = .{ .entry = entry.retain(), .session = c.JS_DupValue(engine.context, self.session), .signal = signal, .context = invocation_context, .agent = c.pi_js_undefined(), .snapshot = c.JS_DupValue(engine.context, self.snapshot) };
    _ = c.JS_SetOpaque(object, runtime);
    if (!existing) self.signals.appendAssumeCapacity(.{ .entry = entry.retain(), .value = c.JS_DupValue(engine.context, signal), .context = c.JS_DupValue(engine.context, invocation_context) });
    return object;
}
fn runtimeRegistryGetter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_DupValue(context, data[0]);
}
fn runtimeSettingsGetter(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = runtimeState(engine, receiver) orelse return durable.reject(engine, error.InvalidTaskRuntime);
    return @import("native_durable_agent.zig").runtimeSettings(engine, self.entry.manager.options) catch |err| durable.reject(engine, err);
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
fn runtimeMethod(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return runtimeMethodOwned(engine, receiver, @enumFromInt(magic), argv[0..@intCast(argc)]) catch |err| if (magic == @intFromEnum(RuntimeMethod.now) or magic == @intFromEnum(RuntimeMethod.report)) durable.reject(engine, err) else durable.rejectedPromise(engine, err);
}
fn runtimeMethodOwned(engine: *Engine, receiver: c.JSValue, operation: RuntimeMethod, args: []const c.JSValue) !c.JSValue {
    const self = runtimeState(engine, receiver) orelse return error.InvalidTaskRuntime;
    try active(self);
    const owner = self.entry.manager;
    if (operation == .sleep or operation == .waitForTask) {
        const context = if (args.len > 1) args[1] else c.pi_js_undefined();
        const bound = try @import("native_durable_context.zig").withAbortSignal(engine, self.signal, context);
        defer engine.freeValue(bound);
        try durable.checkCancellation(engine, bound);
        if (operation == .waitForTask) {
            const pending = try wait(owner, try durable.number(engine, args[0]), null, bound);
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
        const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
        const token = try sdk.get(engine, exports, "AgentDoc");
        defer engine.freeValue(token);
        const id = c.JS_NewInt64(engine.context, @intCast(try runtimeConversation(engine, self)));
        defer engine.freeValue(id);
        const context = if (args.len == 0) c.pi_js_undefined() else args[0];
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
        if (c.JS_IsUndefined(callback)) return c.pi_js_undefined();
        var values = [_]c.JSValue{args[0]};
        return engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), 1, &values));
    }
    const arguments = try sdk.array(engine);
    defer engine.freeValue(arguments);
    for (args) |argument| try sdk.append(engine, arguments, c.JS_DupValue(engine.context, argument));
    var data = [_]c.JSValue{ receiver, arguments };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, runtimeReadQueued, 0, @intFromEnum(operation), data.len, &data));
    defer engine.freeValue(callback);
    return durable.enqueue(engine, self.session, callback);
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
fn runtimeConversation(engine: *Engine, runtime: *Runtime) !u64 {
    var record = (try runtime.entry.manager.lease.value.storage.readTableRecord(engine.gpa, .task, runtime.entry.runtime.taskId())) orelse return error.UnknownTask;
    defer record.deinit();
    return @intCast(try json.asInteger(try json.required(record.value, "conversationId")));
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
    try sdk.put(engine, request, "read", c.JS_DupValue(engine.context, native.creation_owner.?));
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
        if (!c.JS_IsUndefined(report)) {
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
    const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, args, 0));
    defer engine.freeValue(first);
    const context_index: u32 = if (operation == .memo) @intCast(length - 1) else if (operation == .entry and !c.JS_IsNumber(first)) 2 else 1;
    const context = try engine.checked(c.JS_GetPropertyUint32(engine.context, args, context_index));
    defer engine.freeValue(context);
    try durable.checkCancellation(engine, context);
    if (operation == .context) {
        const options = try engine.checked(c.JS_GetPropertyUint32(engine.context, args, 2));
        defer engine.freeValue(options);
        const at = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "at");
        defer engine.freeValue(at);
        const slot = try owner.contexts.getOrPut(engine.gpa, try durable.number(engine, first));
        if (!slot.found_existing) slot.value_ptr.* = null;
        return @import("native_durable_context_view.zig").read(engine, self.session, first, context, at, slot.value_ptr);
    }
    const store = owner.lease.value.storage;
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
            fn apply(raw: ?*anyopaque, tx: *session_mod.Transaction, current: json.Value) !?json.Value {
                const change: *@This() = @ptrCast(@alignCast(raw.?));
                const a = tx.owned.arena.allocator();
                var next = try json.clone(a, current);
                var map = json.get(next, "memos") orelse json.Value{ .object = .empty };
                if (json.get(map, change.name) != null) return null;
                try map.object.put(a, try a.dupe(u8, change.name), try json.clone(a, change.value));
                try next.object.put(a, "memos", map);
                try tx.setTask(next);
                return null;
            }
        };
        var change: Memo = .{ .name = name, .value = value.value };
        try self.entry.runtime.commit(Memo.apply, &change);
        try Manager.deliver(owner);
        return durable.jsValue(engine, value.value);
    }
    return error.UnknownRuntimeOperation;
}
fn runtimeCommit(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
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
    self.entry.manager.updateClock() catch |err| return durable.reject(engine, err);
    self.entry.runtime.commit(Change.run, &call) catch |err| return durable.reject(engine, err);
    if (call.documents) |documents| documents.adopt(self.session) catch |err| return durable.reject(engine, err);
    Manager.deliver(self.entry.manager) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
pub fn wait(self: *Manager, id: ?u64, conversation: ?u64, context: c.JSValue) !c.JSValue {
    if (self.closed) return self.engine.checked(c.JS_Throw(self.engine.context, try messageError(self.engine, "Harness is closed")));
    try durable.checkCancellation(self.engine, context);
    var functions: [2]c.JSValue = undefined;
    const promise = try self.engine.checked(c.JS_NewPromiseCapability(self.engine.context, &functions));
    errdefer {
        self.engine.freeValue(promise);
        self.engine.freeValue(functions[0]);
        self.engine.freeValue(functions[1]);
    }
    try self.waiters.append(self.engine.gpa, .{ .id = id, .conversation = conversation, .resolve = functions[0], .reject = functions[1], .context = c.JS_DupValue(self.engine.context, context) });
    try self.@"resume"();
    return promise;
}
fn settleWaiters(self: *Manager) !void {
    // Scheduler.idle acquires the native Session line. A worker can be waiting
    // for the owner to finish a transaction, so inspect only after it exits.
    if (self.thread == null and !self.closed and self.contexts.count() != 0) {
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
            value = try messageError(self.engine, "Harness is closed");
            rejected = true;
        } else if (waiter.id) |id| {
            var record = try self.lease.value.storage.readTableRecord(self.engine.gpa, .task, id);
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
        } else if (self.thread != null or !try self.scheduler.idle(waiter.conversation)) continue;
        defer self.engine.freeValue(value);
        var args = [_]c.JSValue{value};
        const result = try self.engine.checked(c.JS_Call(self.engine.context, if (rejected) waiter.reject else waiter.resolve, c.pi_js_undefined(), 1, &args));
        self.engine.freeValue(result);
        self.engine.freeValue(waiter.resolve);
        self.engine.freeValue(waiter.reject);
        self.engine.freeValue(waiter.context);
        _ = self.waiters.orderedRemove(index);
    }
}
pub fn defineTask(engine: *Engine, exports: c.JSValue) !void {
    try sdk.put(engine, exports, "defineTask", try engine.checked(c.JS_NewCFunction(engine.context, define, "defineTask", 1)));
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
