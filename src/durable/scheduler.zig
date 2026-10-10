//! Native durable phase scheduler. Dispatch is explicitly driven in bounded batches.
//! Every reservation, runtime write, and step is fenced on the Session line.
const std = @import("std");
const backend = @import("backend/root.zig");
const session_mod = @import("session.zig");
const model = @import("task_state.zig");
const types = @import("types.zig");
const ownership = @import("ownership_index.zig");
const json = backend.json;
const Value = json.Value;
const Transaction = session_mod.Transaction;
test {
    _ = @import("restart_test.zig");
    _ = @import("harness/inbox_native.zig");
}
pub const Handler = *const fn (?*anyopaque, *Runtime, Value, types.Context) anyerror!void;
pub const Initial = *const fn (?*anyopaque, std.mem.Allocator, Value) anyerror!Value;
pub const Migrated = struct { input: Value, checkpoint: Value };
pub const Migration = *const fn (?*anyopaque, std.mem.Allocator, Value, Value, u64) anyerror!Migrated;
pub const Phase = struct { name: []const u8, run: Handler };
pub const Definition = struct {
    name: []const u8,
    version: u64,
    phases: []const Phase,
    abort: Handler,
    initial: ?Initial = null,
    migrate: ?Migration = null,
    context: ?*anyopaque = null,
    retain: ?*const fn (?*anyopaque) void = null,
    release: ?*const fn (?*anyopaque) void = null,
};
const DefinitionNode = struct { definition: Definition, arena: std.heap.ArenaAllocator, generation: u64, available: std.atomic.Value(bool) = .init(true) };
pub const Options = struct {
    max_workers: usize = 4,
    max_phase_steps: usize = 1024,
    callback_context: ?*anyopaque = null,
    settle_outcome: ?*const fn (?*anyopaque, *Transaction, Value, Value) anyerror!void = null,
    withdraw_inputs: ?*const fn (?*anyopaque, *Transaction, u64) anyerror!void = null,
    poll_reads: ?*const fn (?*anyopaque, *session_mod.Session) anyerror!void = null,
    index_changed: ?*const fn (?*anyopaque, ?u64, *const ownership.Index) anyerror!void = null,
};
pub const Report = struct { task_id: u64, cause: anyerror };
pub const Blocked = enum { missing_task, task_too_old, migration_failed };
const Mode = enum { run, abort };
const Invocation = struct {
    scheduler: *Scheduler,
    task_id: u64,
    conversation_id: u64,
    definition: *DefinitionNode,
    mode: Mode,
    active: std.atomic.Value(bool) = .init(true),
    finished: std.atomic.Value(bool) = .init(false),
    owner_dispatches: std.atomic.Value(usize) = .init(0),
    canceled: std.atomic.Value(bool) = .init(false),
    suspended_waits: std.atomic.Value(usize) = .init(0),
    refs: std.atomic.Value(usize) = .init(1),
    cause: ?anyerror = null,
    diagnostic_cause: ?anyerror = null,
    diagnostic: [512]u8 = undefined,
    diagnostic_len: usize = 0,
    fn diagnose(self: *Invocation, cause: anyerror, comptime format: []const u8, args: anytype) anyerror {
        self.diagnostic_cause = cause;
        const message = std.fmt.bufPrint(&self.diagnostic, format, args) catch {
            self.diagnostic_len = 0;
            return cause;
        };
        self.diagnostic_len = message.len;
        return cause;
    }
    fn end(self: *Invocation) void {
        self.active.store(false, .release);
        self.canceled.store(true, .release);
    }
    pub fn retain(self: *Invocation) void {
        _ = self.refs.fetchAdd(1, .monotonic);
    }
    pub fn release(self: *Invocation) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) self.scheduler.gpa.destroy(self);
    }
};
pub const Runtime = struct {
    invocation: *Invocation,
    pub fn retain(self: Runtime) Runtime {
        self.invocation.retain();
        return self;
    }
    pub fn release(self: Runtime) void {
        self.invocation.release();
    }
    pub fn taskId(self: Runtime) u64 {
        return self.invocation.task_id;
    }
    /// Public facades retain one invocation across all its running phases.
    pub fn isActive(self: Runtime) bool {
        return self.invocation.active.load(.acquire);
    }
    pub fn isFinished(self: Runtime) bool {
        return self.invocation.finished.load(.acquire) and self.invocation.owner_dispatches.load(.acquire) == 0;
    }
    pub fn beginOwnerDispatch(self: Runtime) void {
        _ = self.invocation.owner_dispatches.fetchAdd(1, .acq_rel);
    }
    pub fn endOwnerDispatch(self: Runtime) void {
        std.debug.assert(self.invocation.owner_dispatches.fetchSub(1, .acq_rel) > 0);
    }
    pub fn suspendWait(self: Runtime) void {
        _ = self.invocation.suspended_waits.fetchAdd(1, .acq_rel);
    }
    pub fn resumeWait(self: Runtime) void {
        const previous = self.invocation.suspended_waits.fetchSub(1, .acq_rel);
        std.debug.assert(previous > 0);
    }
    /// An owner broker detected a registry boundary before invoking a phase.
    pub fn requeueForRegistryChange(self: Runtime) !void {
        const Call = struct {
            runtime: Runtime,
            fn apply(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
                const self_call: *@This() = @ptrCast(@alignCast(raw.?));
                const current = (try tx.currentRecord(self_call.runtime.taskId(), .task)) orelse return error.UnknownTask;
                if (try model.status(current) == .running) try tx.setTask(try model.withState(tx.owned.arena.allocator(), current, try model.checkpointState(tx.owned.arena.allocator(), "pending", try model.field(try model.field(current, "state"), "checkpoint"))));
                self_call.runtime.invocation.end();
                return .null;
            }
        };
        var call: Call = .{ .runtime = self };
        var result = try self.invocation.scheduler.session.commit(Call.apply, &call, .{}, .{});
        result.deinit();
    }
    pub fn context(self: Runtime) types.Context {
        return .{ .abort_flag = &self.invocation.canceled };
    }
    pub fn commit(self: Runtime, change: Change, userdata: ?*anyopaque) !void {
        if (!self.invocation.active.load(.acquire)) return error.InvocationEnded;
        var call: RuntimeCommit = .{ .runtime = self, .change = change, .userdata = userdata };
        var result = try self.invocation.scheduler.session.commit(RuntimeCommit.apply, &call, .{ .conversationId = self.invocation.conversation_id, .taskId = self.taskId() }, .{});
        result.deinit();
    }
    /// A VM owner must not wait for a worker which may await VM Storage.
    /// A busy line invokes no change callback and is retried by its owner pump.
    pub fn tryCommit(self: Runtime, change: Change, userdata: ?*anyopaque) !bool {
        if (!self.invocation.active.load(.acquire)) return error.InvocationEnded;
        var call: RuntimeCommit = .{ .runtime = self, .change = change, .userdata = userdata };
        var result = (try self.invocation.scheduler.session.tryCommit(RuntimeCommit.apply, &call, .{ .conversationId = self.invocation.conversation_id, .taskId = self.taskId() }, .{})) orelse return false;
        result.deinit();
        return true;
    }
    /// Return null to commit only transaction side effects; return a running/waiting/terminal state to transition.
    pub const Change = *const fn (?*anyopaque, *Transaction, Value) anyerror!?Value;
};
const RuntimeCommit = struct {
    runtime: Runtime,
    change: Runtime.Change,
    userdata: ?*anyopaque,
    fn apply(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const invocation = self.runtime.invocation;
        const scheduler = invocation.scheduler;
        if (!invocation.active.load(.acquire)) return error.InvocationEnded;
        if (scheduler.closing.load(.acquire)) return error.SchedulerClosed;
        const record = (try tx.currentRecord(invocation.task_id, .task)) orelse return error.UnknownTask;
        if (try model.status(record) != .running) return error.TaskNotRunning;
        if (invocation.mode == .run and try model.flag(record, "abortRequested")) return error.TaskAbortMarked;
        if (try self.change(self.userdata, tx, record)) |next_state| {
            const name = try model.text(next_state, "status");
            var state = next_state;
            if (std.mem.eql(u8, name, "waiting")) {
                if (invocation.mode == .abort) return invocation.diagnose(error.AbortHandlerCannotWait, "Abort handler of task {d} cannot wait", .{invocation.task_id});
                const view = try overlay(scheduler.gpa, tx);
                defer view.destroy(scheduler.gpa);
                try validateWait(.{ .state = view }, record, next_state, invocation);
            } else if (std.mem.eql(u8, name, "terminal")) {
                const view = try overlay(scheduler.gpa, tx);
                defer view.destroy(scheduler.gpa);
                if (try (model.Graph{ .state = view }).hasOwnedLive(invocation.task_id)) state = try model.outcomeState(tx.owned.arena.allocator(), "completing", try model.field(state, "outcome"));
            } else if (!std.mem.eql(u8, name, "running")) return error.InvalidRuntimeState;
            try tx.setTask(try model.withState(tx.owned.arena.allocator(), record, state));
        }
        return .null;
    }
};
fn overlay(gpa: std.mem.Allocator, tx: *Transaction) !*backend.memory.State {
    var predicted: backend.memory.Memory = .{ .gpa = gpa, .state = try tx.session.storage.snapshot(gpa) };
    defer predicted.deinit();
    var prepared = try predicted.prepare(tx.writes, null);
    defer prepared.deinit();
    const state = prepared.state.?;
    prepared.state = null;
    return state;
}
fn queuedConversations(view: *backend.memory.State) ![]const u64 {
    const a = view.arena.allocator();
    var ids: std.ArrayList(u64) = .empty;
    var rows = view.rows.iterator();
    while (rows.next()) |item| if (item.value_ptr.table == .submission and std.mem.eql(u8, try model.text(item.value_ptr.record, "status"), "queued")) try ids.append(a, item.key_ptr.*);
    std.mem.sort(u64, ids.items, {}, std.sort.asc(u64));
    var conversations: std.ArrayList(u64) = .empty;
    for (ids.items) |id| {
        const conversation = try model.number(view.rows.get(id).?.record, "conversationId");
        if (std.mem.indexOfScalar(u64, conversations.items, conversation) == null) try conversations.append(a, conversation);
    }
    return conversations.items;
}
fn validateWait(graph: model.Graph, record: Value, state: Value, invocation: *Invocation) !void {
    const members = try model.field(state, "on");
    if (members != .array) return error.InvalidTaskWait;
    for (members.array.items) |member| {
        const id = try json.asInteger(member);
        const task_id = try model.number(record, "id");
        if (id == task_id or try graph.reaches(try model.parent(record), .{ .task = id }, true)) return invocation.diagnose(error.TaskCannotWaitOnOwner, "Task {d} cannot wait on itself or its owner {d}", .{ task_id, id });
        const child = graph.task(id) catch |err| return invocation.diagnose(err, "Task {d} does not exist", .{id});
        if (std.mem.eql(u8, try model.text(state, "policy"), "failFast")) {
            const owner = json.get(child, "owner");
            if (owner == null or try json.asInteger(owner.?) != task_id) return invocation.diagnose(error.FailFastRequiresChild, "Task {d} can wait failFast only on tasks it owns; {d} is not one", .{ task_id, id });
        }
    }
}
pub const Scheduler = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    session: *session_mod.Session,
    options: Options,
    mutex: std.Io.Mutex = .init,
    driving: std.atomic.Value(bool) = .init(false),
    closing: std.atomic.Value(bool) = .init(false),
    enabled: std.atomic.Value(bool) = .init(false),
    definitions: std.ArrayList(*DefinitionNode) = .empty,
    invocations: std.ArrayList(*Invocation) = .empty,
    reports: std.ArrayList(Report) = .empty,
    migration_failures: std.AutoHashMap(u64, u64),
    abandoned: std.AutoHashMapUnmanaged(u64, void) = .empty,
    subscription: ?u64 = null,
    close_subscription: ?u64 = null,
    generation: u64 = 1,
    ownership_index: ownership.Index,
    live_records: std.AutoHashMapUnmanaged(u64, json.Owned) = .{},
    maintenance_subscription: ?u64 = null,
    fail_fast_checks: std.AutoArrayHashMapUnmanaged(u64, void) = .empty,
    index_dirty: bool = false,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, session: *session_mod.Session, options: Options) !Scheduler {
        if (options.max_workers == 0 or options.max_workers > 64 or options.max_phase_steps == 0) return error.InvalidSchedulerBounds;
        return .{ .gpa = gpa, .io = io, .session = session, .options = options, .migration_failures = .init(gpa), .ownership_index = .init(gpa) };
    }
    /// Caller joins all drive calls and releases retained runtimes before deinit.
    pub fn deinit(self: *Scheduler) void {
        std.debug.assert(!self.driving.load(.acquire));
        self.close();
        if (self.subscription) |id| self.session.unsubscribe(id);
        if (self.close_subscription) |id| self.session.unsubscribeClose(id);
        if (self.maintenance_subscription) |id| self.session.unsubscribeMaintenance(id);
        var records = self.live_records.valueIterator();
        while (records.next()) |record| record.deinit();
        self.live_records.deinit(self.gpa);
        self.ownership_index.deinit();
        self.fail_fast_checks.deinit(self.gpa);
        for (self.invocations.items) |invocation| {
            std.debug.assert(invocation.refs.load(.acquire) == 1);
            invocation.release();
        }
        self.invocations.deinit(self.gpa);
        for (self.definitions.items) |node| {
            if (node.definition.release) |release| release(node.definition.context);
            node.arena.deinit();
            self.gpa.destroy(node);
        }
        self.definitions.deinit(self.gpa);
        self.reports.deinit(self.gpa);
        self.migration_failures.deinit();
        self.abandoned.deinit(self.gpa);
    }
    pub fn register(self: *Scheduler, definition: Definition) !void {
        if (definition.name.len == 0 or definition.version == 0 or definition.version > backend.memory.max_integer) return error.InvalidTaskDefinition;
        if ((definition.retain == null) != (definition.release == null)) return error.InvalidTaskResource;
        const node = try self.gpa.create(DefinitionNode);
        errdefer self.gpa.destroy(node);
        node.arena = .init(self.gpa);
        node.available = .init(true);
        errdefer node.arena.deinit();
        const a = node.arena.allocator();
        node.definition = definition;
        node.definition.name = try a.dupe(u8, definition.name);
        const phases = try a.dupe(Phase, definition.phases);
        for (phases, 0..) |*phase, index| {
            phase.name = try a.dupe(u8, phase.name);
            for (phases[0..index]) |prior| if (std.mem.eql(u8, prior.name, phase.name)) return error.DuplicateTaskPhase;
        }
        node.definition.phases = phases;
        if (definition.retain) |retain| retain(definition.context);
        errdefer if (definition.release) |release| release(definition.context);
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closing.load(.acquire)) return error.SchedulerClosed;
        node.generation = self.generation;
        try self.definitions.append(self.gpa, node);
        self.generation += 1;
    }
    fn lookupDefinition(self: *Scheduler, name: []const u8) ?*DefinitionNode {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        var i = self.definitions.items.len;
        while (i > 0) {
            i -= 1;
            if (self.definitions.items[i].available.load(.acquire) and std.mem.eql(u8, self.definitions.items[i].definition.name, name)) return self.definitions.items[i];
        }
        return null;
    }
    pub fn open(self: *Scheduler) !void {
        if (self.subscription != null) return error.SchedulerAlreadyOpen;
        errdefer self.abandoned.clearRetainingCapacity();
        self.maintenance_subscription = try self.session.subscribeMaintenance(sweepLine, self);
        errdefer {
            self.session.unsubscribeMaintenance(self.maintenance_subscription.?);
            self.maintenance_subscription = null;
        }
        self.subscription = try self.session.observeCommits(observe, self);
        errdefer {
            self.session.unsubscribe(self.subscription.?);
            self.subscription = null;
        }
        self.close_subscription = try self.session.subscribeClose(onSessionClose, self);
        errdefer {
            self.session.unsubscribeClose(self.close_subscription.?);
            self.close_subscription = null;
        }
        var result = try self.session.commit(recover, self, .{}, .{});
        result.deinit();
        try self.reconcile();
    }
    pub fn removeDefinition(self: *Scheduler, name: []const u8) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.definitions.items) |node| if (std.mem.eql(u8, node.definition.name, name)) node.available.store(false, .release);
    }
    pub fn enable(self: *Scheduler) void {
        self.enabled.store(true, .release);
    }
    pub fn createTask(self: *Scheduler, tx: *Transaction, name: []const u8, input: Value, options: session_mod.TaskOptions) !u64 {
        const node = self.lookupDefinition(name) orelse return error.MissingTaskDefinition;
        const initial = node.definition.initial orelse return error.MissingTaskInitial;
        _ = try tx.taskConversation(options);
        const checkpoint = try initial(node.definition.context, tx.owned.arena.allocator(), input);
        return tx.createTask(node.definition.name, node.definition.version, input, checkpoint, options);
    }
    pub fn close(self: *Scheduler) void {
        self.closing.store(true, .release);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.invocations.items) |invocation| invocation.canceled.store(true, .release);
    }
    fn onSessionClose(raw: ?*anyopaque) void {
        const self: *Scheduler = @ptrCast(@alignCast(raw.?));
        self.close();
    }
    fn observe(raw: ?*anyopaque, event: *const session_mod.Publication, _: types.Context) !void {
        const self: *Scheduler = @ptrCast(@alignCast(raw.?));
        // Conversation edges are observed before task links from the same
        // publication; no sweep may drop a chain halfway through admission.
        for (event.changes.array.items) |change| {
            if (!std.mem.eql(u8, try model.text(change, "type"), "conversation")) continue;
            const record = try model.field(change, "value");
            const id = try model.number(record, "id");
            if (!self.ownership_index.edges.contains(id)) try self.ownership_index.setEdge(id, if (json.get(record, "owner")) |owner| try model.number(owner, "taskId") else null);
        }
        for (event.changes.array.items) |change| {
            if (!std.mem.eql(u8, try model.text(change, "type"), "task")) continue;
            try self.trackRecord(try model.field(change, "value"));
        }
        try self.ownership_index.sweep();
        if (self.options.index_changed) |changed| try changed(self.options.callback_context, event.seq, &self.ownership_index);
        self.index_dirty = false;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (event.changes.array.items) |change| {
            if (!std.mem.eql(u8, try model.text(change, "type"), "task")) continue;
            const record = try model.field(change, "value");
            const id = try model.number(record, "id");
            for (self.invocations.items) |invocation| if (invocation.task_id == id and invocation.active.load(.acquire)) {
                if (invocation.mode == .run and try model.flag(record, "abortRequested")) invocation.canceled.store(true, .release);
            };
        }
    }
    fn sweepLine(raw: ?*anyopaque) !void {
        const self: *Scheduler = @ptrCast(@alignCast(raw.?));
        if (!self.index_dirty and !self.ownership_index.needsSweep()) return;
        try self.ownership_index.sweep();
        if (self.options.index_changed) |changed| try changed(self.options.callback_context, null, &self.ownership_index);
        self.index_dirty = false;
    }
    fn recordLink(record: Value) !ownership.Link {
        return .{ .conversation = try model.number(record, "conversationId"), .owner = if (json.get(record, "owner")) |owner| try json.asInteger(owner) else null, .background = try model.flag(record, "background") };
    }
    fn trackRecord(self: *Scheduler, record: Value) !void {
        // An allocation failure after part of a committed publication has
        // entered an index is fatal to this Session; it cannot keep scheduling
        // from partial derived state. Internal observers enforce that fence.
        errdefer |err| _ = self.session.fail(err);
        const id = try model.number(record, "id");
        const status = try model.status(record);
        const prior_record = self.live_records.get(id);
        if (try model.failed(record) and (prior_record == null or !try model.failed(prior_record.?.value))) {
            if (self.ownership_index.waiters.get(id)) |waiters| for (waiters.keys()) |waiter| try self.fail_fast_checks.put(self.gpa, waiter, {});
        }
        if (status == .terminal) {
            _ = self.fail_fast_checks.orderedRemove(id);
        } else if (status == .waiting and (prior_record == null or try model.status(prior_record.?.value) != .waiting) and std.mem.eql(u8, try model.text(try model.field(record, "state"), "policy"), "failFast")) try self.fail_fast_checks.put(self.gpa, id, {});
        try indexRecord(self.gpa, &self.ownership_index, record);
        self.index_dirty = true;
        if (status == .terminal) {
            if (self.live_records.fetchRemove(id)) |removed| {
                var previous = removed.value;
                previous.deinit();
            }
            return;
        }
        var copied = try json.Owned.empty(self.gpa);
        errdefer copied.deinit();
        copied.value = try json.clone(copied.arena.allocator(), record);
        const slot = try self.live_records.getOrPut(self.gpa, id);
        if (slot.found_existing) slot.value_ptr.deinit();
        slot.value_ptr.* = copied;
    }
    fn indexRecord(gpa: std.mem.Allocator, index: *ownership.Index, record: Value) !void {
        const status = try model.status(record);
        var members: std.ArrayList(u64) = .empty;
        defer members.deinit(gpa);
        if (status == .waiting) for ((try model.field(try model.field(record, "state"), "on")).array.items) |member| try members.append(gpa, try json.asInteger(member));
        try index.track(.{ .id = try model.number(record, "id"), .link = try recordLink(record), .status = @enumFromInt(@intFromEnum(status)), .abort_requested = try model.flag(record, "abortRequested"), .failed_outcome = try model.failed(record), .wait_on = members.items });
    }
    /// Real Storage reads on the Session line, only for unknown owner links.
    /// A missing task leaves the chain unresolved, as in upstream; a missing
    /// conversation ends at an ownerless root. Terminal nodes retain only the
    /// fields required to pass through them while live work exists below.
    fn loadChain(self: *Scheduler, start: ownership.Node) !void {
        errdefer |err| if (!self.ownership_index.usable) {
            _ = self.session.fail(err);
        };
        var passed: std.ArrayList(u64) = .empty;
        defer passed.deinit(self.gpa);
        var visited: std.AutoHashMapUnmanaged(ownership.Node, void) = .{};
        defer visited.deinit(self.gpa);
        var at = start;
        while (true) {
            if (visited.contains(at)) return error.TaskOwnershipCycle;
            try visited.put(self.gpa, at, {});
            if (at.kind == .task) {
                var fields = self.ownership_index.link(at.id);
                if (fields != null and !self.ownership_index.unloaded.contains(at.id)) break;
                if (fields == null) {
                    var fetched = (try self.session.storage.readTableRecord(self.gpa, .task, at.id)) orelse return;
                    defer fetched.deinit();
                    fields = try recordLink(fetched.value);
                    if (try model.status(fetched.value) == .terminal) {
                        try self.ownership_index.settleLoaded(at.id, fields.?);
                        self.index_dirty = true;
                    }
                }
                try passed.append(self.gpa, at.id);
                at = fields.?.parent();
            } else {
                var edge = self.ownership_index.edge(at.id);
                if (edge == .unknown) {
                    var fetched = try self.session.storage.readTableRecord(self.gpa, .conversation, at.id);
                    defer if (fetched) |*record| record.deinit();
                    const owner = if (fetched) |record| if (json.get(record.value, "owner")) |fields| try model.number(fields, "taskId") else null else null;
                    try self.ownership_index.setEdge(at.id, owner);
                    self.index_dirty = true;
                    edge = self.ownership_index.edge(at.id);
                }
                switch (edge) {
                    .unknown => unreachable,
                    .root => break,
                    .owned => |owner| at = ownership.Node.task(owner),
                }
            }
        }
        try self.ownership_index.markChainLoaded(passed.items);
        if (passed.items.len != 0) self.index_dirty = true;
    }
    fn loadScopes(self: *Scheduler) !void {
        const unloaded = try self.gpa.dupe(u64, self.ownership_index.unloaded.keys());
        defer self.gpa.free(unloaded);
        for (unloaded) |id| if (self.ownership_index.unloaded.contains(id)) try self.loadChain(ownership.Node.task(id));
    }
    fn recover(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
        const self: *Scheduler = @ptrCast(@alignCast(raw.?));
        const view = try self.session.storage.snapshot(self.gpa);
        defer view.destroy(self.gpa);
        var rows = view.rows.iterator();
        while (rows.next()) |item| {
            if (item.value_ptr.table != .task) continue;
            const record = item.value_ptr.record;
            if (try model.live(record)) try self.trackRecord(record);
            if (try model.live(record)) if (json.get(record, "abandonOnRestart")) |flag| {
                if (flag == .bool and flag.bool) try self.abandoned.put(self.gpa, item.key_ptr.*, {});
            };
            if (try model.status(record) == .running) try tx.setTask(try model.withState(tx.owned.arena.allocator(), record, try model.checkpointState(tx.owned.arena.allocator(), "pending", try model.field(try model.field(record, "state"), "checkpoint"))));
        }
        return .null;
    }
    pub fn reconcile(self: *Scheduler) !void {
        var result = self.session.commit(reconcileLine, self, .{}, .{}) catch |err| {
            if (err != error.SessionClosed) _ = self.session.fail(err);
            return err;
        };
        result.deinit();
    }
    fn anyFailed(self: *Scheduler, members: Value) !bool {
        for (members.array.items) |member| {
            const id = try json.asInteger(member);
            if (self.live_records.get(id)) |record| {
                if (try model.failed(record.value)) return true;
            } else {
                var fetched = try self.session.storage.readTableRecord(self.gpa, .task, id);
                defer if (fetched) |*record| record.deinit();
                if (fetched) |record| if (try model.failed(record.value)) return true;
            }
        }
        return false;
    }
    fn queueMark(self: *Scheduler, marks: *std.AutoArrayHashMapUnmanaged(u64, model.Cancellation), record: Value, reason: model.Cancellation) !void {
        const id = try model.number(record, "id");
        if (marks.get(id)) |prior| if (prior == .request) return;
        if (try model.flag(record, "abortRequested") and (json.get(record, "abortReason") == null or reason == .restart)) return;
        try marks.put(self.gpa, id, reason);
    }
    fn queuedInputs(self: *Scheduler, gpa: std.mem.Allocator) ![]u64 {
        var filters: Value = .{ .object = .empty };
        try filters.object.put(gpa, "status", .{ .string = "queued" });
        defer filters.object.deinit(gpa);
        var conversations: std.AutoArrayHashMapUnmanaged(u64, void) = .empty;
        defer conversations.deinit(gpa);
        var cursor: ?json.Owned = null;
        defer if (cursor) |*value| value.deinit();
        while (true) {
            var page = try self.session.storage.sourceScan(self.gpa, .submission, filters, 100, if (cursor) |value| value.value else null);
            defer page.deinit();
            for ((try model.field(page.value, "items")).array.items) |submission| {
                if (!std.mem.eql(u8, try model.text(submission, "type"), "input")) continue;
                try conversations.put(gpa, try model.number(submission, "conversationId"), {});
            }
            const next = json.get(page.value, "next") orelse break;
            var owned = try json.Owned.empty(self.gpa);
            errdefer owned.deinit();
            owned.value = try json.clone(owned.arena.allocator(), next);
            if (cursor) |*value| value.deinit();
            cursor = owned;
        }
        for (conversations.keys()) |id| try self.loadChain(ownership.Node.conversation(id));
        return gpa.dupe(u64, conversations.keys());
    }
    fn reconcileLine(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
        const self: *Scheduler = @ptrCast(@alignCast(raw.?));
        if (self.closing.load(.acquire)) return .null;
        try self.loadScopes();
        if (self.options.poll_reads) |poll| try poll(self.options.callback_context, tx.session);
        const a = tx.owned.arena.allocator();
        const queued = if (self.options.withdraw_inputs != null and self.ownership_index.intents.count() != 0) try self.queuedInputs(a) else &.{};
        // Collect every mark before staging any, so an explicit request wins
        // over restart propagation in the same pass. Cascades stop at another
        // intent, whose own walk supplies the nearest inherited reason.
        var marks: std.AutoArrayHashMapUnmanaged(u64, model.Cancellation) = .empty;
        defer marks.deinit(self.gpa);
        for (self.ownership_index.intents.keys()) |owner_id| {
            const owner = self.live_records.get(owner_id).?.value;
            const reason: model.Cancellation = if (json.get(owner, "abortReason")) |value| if (value == .string and std.mem.eql(u8, value.string, "restart") and !try model.failed(owner)) .restart else .request else .request;
            const children = try self.ownership_index.cascadeOwned(self.gpa, owner_id);
            defer self.gpa.free(children);
            for (children) |id| try self.queueMark(&marks, self.live_records.get(id).?.value, reason);
        }
        const checks = try self.gpa.dupe(u64, self.fail_fast_checks.keys());
        defer self.gpa.free(checks);
        self.fail_fast_checks.clearRetainingCapacity();
        for (checks) |id| {
            const waiter = (self.live_records.get(id) orelse continue).value;
            if (try model.status(waiter) != .waiting) continue;
            const state = try model.field(waiter, "state");
            if (!std.mem.eql(u8, try model.text(state, "policy"), "failFast") or !try self.anyFailed(try model.field(state, "on"))) continue;
            for ((try model.field(state, "on")).array.items) |member| {
                const record = (self.live_records.get(try json.asInteger(member)) orelse continue).value;
                if (!try model.failed(record)) try self.queueMark(&marks, record, .request);
            }
        }
        var working = try self.ownership_index.duplicate(self.gpa);
        defer working.deinit();
        var candidates: std.AutoHashMapUnmanaged(u64, Value) = .{};
        defer candidates.deinit(self.gpa);
        var marked = marks.iterator();
        while (marked.next()) |item| {
            const record = try model.abortMark(a, self.live_records.get(item.key_ptr.*).?.value, item.value_ptr.*);
            try candidates.put(self.gpa, item.key_ptr.*, record);
            try tx.setTask(record);
            try indexRecord(self.gpa, &working, record);
        }
        if (self.options.withdraw_inputs) |withdraw| for (queued) |id| if (try self.ownership_index.cancellingOwner(ownership.Node.conversation(id)) != null) try withdraw(self.options.callback_context, tx, id);
        // Each terminal candidate removes its live metadata in the local
        // overlay and enqueues its nearest held owner. In rounds, many siblings
        // finishing together cause one check of their holder in the next round.
        self.ownership_index.finalize_checks.clearRetainingCapacity();
        while (working.finalize_checks.count() != 0) {
            const round = try self.gpa.dupe(u64, working.finalize_checks.keys());
            defer self.gpa.free(round);
            working.finalize_checks.clearRetainingCapacity();
            for (round) |id| {
                const metadata = working.live.get(id) orelse continue;
                if (metadata.status != .completing or try working.hasOrdinaryBelow(self.gpa, ownership.Node.task(id))) continue;
                const record = candidates.get(id) orelse self.live_records.get(id).?.value;
                const terminal = try model.withState(a, record, try model.outcomeState(a, "terminal", try model.field(try model.field(record, "state"), "outcome")));
                try candidates.put(self.gpa, id, terminal);
                try tx.setTask(terminal);
                try indexRecord(self.gpa, &working, terminal);
                try self.settle(tx, terminal);
            }
        }
        return .null;
    }
    fn settle(self: *Scheduler, tx: *Transaction, record: Value) !void {
        const result = try model.field(try model.field(record, "state"), "outcome");
        const kind = try model.text(result, "status");
        if (!std.mem.eql(u8, kind, "faulted") and !std.mem.eql(u8, kind, "orphaned")) return;
        if (self.options.settle_outcome) |callback| try callback(self.options.callback_context, tx, record, result);
    }
    pub fn abortConversation(self: *Scheduler, conversation: u64, cross_background: bool) !void {
        var call: ScopeAbort = .{ .scheduler = self, .conversation = conversation, .cross_background = cross_background };
        var result = try self.session.commit(ScopeAbort.apply, &call, .{}, .{});
        result.deinit();
        try self.reconcile();
    }
    /// Nonblocking owner admission. The returned reached IDs are owned by gpa;
    /// background traversal waits for these tasks as well as ordinary idle.
    pub fn tryAbortConversation(self: *Scheduler, gpa: std.mem.Allocator, conversation: u64, cross_background: bool, context: types.Context) !?[]u64 {
        var reached: std.ArrayList(u64) = .empty;
        defer reached.deinit(gpa);
        var call: ScopeAbort = .{ .scheduler = self, .conversation = conversation, .cross_background = cross_background, .reached = &reached, .reached_gpa = gpa };
        var result = (try self.session.tryCommit(ScopeAbort.apply, &call, .{}, context)) orelse return null;
        defer result.deinit();
        // The refill driver observes the committed marks. Do not synchronously
        // reconcile here: a worker can acquire the Session line after release.
        return try reached.toOwnedSlice(gpa);
    }
    const ScopeAbort = struct {
        scheduler: *Scheduler,
        conversation: u64,
        cross_background: bool,
        reached: ?*std.ArrayList(u64) = null,
        reached_gpa: std.mem.Allocator = std.heap.page_allocator,
        fn apply(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const view = try self.scheduler.session.storage.snapshot(self.scheduler.gpa);
            defer view.destroy(self.scheduler.gpa);
            const graph: model.Graph = .{ .state = view };
            var rows = view.rows.iterator();
            while (rows.next()) |item| {
                const row = item.value_ptr.*;
                if (row.table != .task or !try model.live(row.record) or (try model.flag(row.record, "background") and !self.cross_background)) continue;
                if (!try graph.reaches(try model.parent(row.record), .{ .conversation = self.conversation }, self.cross_background)) continue;
                if (self.reached) |reached| try reached.append(self.reached_gpa, item.key_ptr.*);
                const marked = try model.abortMark(tx.owned.arena.allocator(), row.record, .request);
                try tx.setTask(marked);
            }
            if (self.scheduler.options.withdraw_inputs) |withdraw| {
                const queued = try queuedConversations(view);
                for (queued) |id| if (try graph.reaches(.{ .conversation = id }, .{ .conversation = self.conversation }, self.cross_background)) try withdraw(self.scheduler.options.callback_context, tx, id);
            }
            return .null;
        }
    };
    pub fn idle(self: *Scheduler, conversation: ?u64) !bool {
        var call: IdleCall = .{ .scheduler = self, .conversation = conversation };
        var result = try self.session.commit(IdleCall.apply, &call, .{}, .{});
        defer result.deinit();
        return result.value.value.bool;
    }
    const IdleCall = struct {
        scheduler: *Scheduler,
        conversation: ?u64,
        fn apply(raw: ?*anyopaque, _: *Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return .{ .bool = try self.scheduler.ownership_index.idle(self.scheduler.gpa, self.conversation) };
        }
    };
    pub fn abort(self: *Scheduler, id: u64) !void {
        var call: AbortCall = .{ .scheduler = self, .id = id };
        var result = try self.session.commit(AbortCall.apply, &call, .{}, .{});
        result.deinit();
        try self.reconcile();
    }
    pub const TaskAbortMark = struct {
        terminal: bool,
        run: ?Runtime = null,
        pub fn deinit(self: *TaskAbortMark) void {
            if (self.run) |runtime| runtime.release();
            self.run = null;
        }
    };
    /// Caller already owns the Session line. Only the observed run is retained;
    /// joining it belongs outside the line so its final step can still commit.
    pub fn abortTaskOnLine(self: *Scheduler, tx: *Transaction, id: u64, keep_restart: bool) !TaskAbortMark {
        const record = (try tx.currentRecord(id, .task)) orelse return error.UnknownTask;
        if (try model.status(record) == .terminal) return .{ .terminal = true };
        if (keep_restart) if (json.get(record, "abortReason")) |reason| {
            if (reason == .string and std.mem.eql(u8, reason.string, "restart")) return .{ .terminal = false };
        };
        var mark: TaskAbortMark = .{ .terminal = false };
        errdefer mark.deinit();
        self.mutex.lockUncancelable(self.io);
        for (self.invocations.items) |invocation| if (invocation.task_id == id and invocation.mode == .run and invocation.active.load(.acquire)) {
            mark.run = (Runtime{ .invocation = invocation }).retain();
            break;
        };
        self.mutex.unlock(self.io);
        var call: AbortCall = .{ .scheduler = self, .id = id, .keep_restart = keep_restart, .record = record };
        _ = try AbortCall.apply(&call, tx, .{});
        return mark;
    }
    /// Validate direct task ownership on the mutation line. A nested caller's
    /// cleanup preserves a restart mark and then waits for actual settlement.
    pub fn abortOwned(self: *Scheduler, owner_id: u64, id: u64) !bool {
        const Owned = struct {
            scheduler: *Scheduler,
            owner_id: u64,
            id: u64,
            fn apply(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
                const call: *@This() = @ptrCast(@alignCast(raw.?));
                const record = (try tx.currentRecord(call.id, .task)) orelse return error.TaskNotOwned;
                const owner = json.get(record, "owner") orelse return error.TaskNotOwned;
                if (try json.asInteger(owner) != call.owner_id) return error.TaskNotOwned;
                if (try model.status(record) == .terminal) return .{ .bool = true };
                var abort_call: AbortCall = .{ .scheduler = call.scheduler, .id = call.id, .keep_restart = true };
                _ = try AbortCall.apply(&abort_call, tx, .{});
                return .{ .bool = false };
            }
        };
        var call: Owned = .{ .scheduler = self, .owner_id = owner_id, .id = id };
        var result = try self.session.commit(Owned.apply, &call, .{}, .{});
        defer result.deinit();
        const terminal = result.value.value.bool;
        if (!terminal) try self.reconcile();
        return terminal;
    }
    const AbortCall = struct {
        scheduler: *Scheduler,
        id: u64,
        keep_restart: bool = false,
        record: ?Value = null,
        fn apply(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var record = self.record orelse (try tx.currentRecord(self.id, .task)) orelse return error.UnknownTask;
            if (try model.status(record) == .terminal) return .null;
            if (self.keep_restart) if (json.get(record, "abortReason")) |reason| {
                if (reason == .string and std.mem.eql(u8, reason.string, "restart")) return .null;
            };
            var active = false;
            self.scheduler.mutex.lockUncancelable(self.scheduler.io);
            for (self.scheduler.invocations.items) |invocation| if (invocation.task_id == self.id and invocation.active.load(.acquire)) {
                active = true;
                break;
            };
            self.scheduler.mutex.unlock(self.scheduler.io);
            if (!active and try model.status(record) != .completing) {
                const view = try overlay(self.scheduler.gpa, tx);
                defer view.destroy(self.scheduler.gpa);
                if (!try (model.Graph{ .state = view }).hasOwnedLive(self.id)) {
                    const node = self.scheduler.lookupDefinition(try model.text(record, "kind"));
                    var blocked: ?Blocked = null;
                    if (node == null) blocked = .missing_task else {
                        const version = try model.number(record, "version");
                        if (node.?.definition.version < version) blocked = .task_too_old;
                        if (node.?.definition.version > version) {
                            if (node.?.definition.migrate) |migration| {
                                if (self.scheduler.migration_failures.get(self.id) == node.?.generation) blocked = .migration_failed else {
                                    _ = migration(node.?.definition.context, tx.owned.arena.allocator(), try model.field(record, "input"), try model.field(try model.field(record, "state"), "checkpoint"), version) catch {
                                        try self.scheduler.migration_failures.put(self.id, node.?.generation);
                                        blocked = .migration_failed;
                                    };
                                }
                            } else blocked = .migration_failed;
                        }
                    }
                    if (blocked) |reason| {
                        record = try model.withState(tx.owned.arena.allocator(), record, try model.outcomeState(tx.owned.arena.allocator(), "terminal", try model.makeOutcome(tx.owned.arena.allocator(), "orphaned", .{ .string = @tagName(reason) })));
                        try tx.setTask(record);
                        try self.scheduler.settle(tx, record);
                        return .null;
                    }
                }
            }
            if (!try model.flag(record, "abortRequested") or json.get(record, "abortReason") != null)
                try tx.setTask(try model.abortMark(tx.owned.arena.allocator(), record, .request));
            return .null;
        }
    };
    /// Reserve up to max_workers on the Session line, then run real native worker threads and join them.
    /// Handlers must cooperate with Runtime.context() for bounded close/abort latency.
    pub fn drive(self: *Scheduler) !usize {
        if (self.driving.swap(true, .acq_rel)) return error.ConcurrentSchedulerDrive;
        defer self.driving.store(false, .release);
        if (!self.enabled.load(.acquire)) return 0;
        if (self.closing.load(.acquire)) return error.SchedulerClosed;
        try self.reconcile();
        self.mutex.lockUncancelable(self.io);
        var index = self.invocations.items.len;
        while (index > 0) {
            index -= 1;
            const invocation = self.invocations.items[index];
            if (!invocation.active.load(.acquire) and invocation.refs.load(.acquire) == 1) {
                _ = self.invocations.orderedRemove(index);
                invocation.release();
            }
        }
        self.mutex.unlock(self.io);
        self.mutex.lockUncancelable(self.io);
        const registry = self.gpa.dupe(*DefinitionNode, self.definitions.items) catch |err| {
            self.mutex.unlock(self.io);
            return err;
        };
        self.mutex.unlock(self.io);
        defer self.gpa.free(registry);
        var batch: Batch = .{ .scheduler = self, .registry = registry };
        defer batch.list.deinit(self.gpa);
        try batch.list.ensureTotalCapacity(self.gpa, self.options.max_workers);
        var threads: std.ArrayList(std.Thread) = .empty;
        defer threads.deinit(self.gpa);
        try threads.ensureTotalCapacity(self.gpa, self.options.max_workers);
        try self.reports.ensureUnusedCapacity(self.gpa, self.options.max_workers);
        var result = self.session.commit(Batch.reserve, &batch, .{}, .{}) catch |err| {
            for (batch.list.items) |invocation| {
                invocation.end();
                invocation.finished.store(true, .release);
            }
            return err;
        };
        result.deinit();
        if (batch.marked_abandoned) {
            self.abandoned.clearRetainingCapacity();
            try self.reconcile();
            return 0;
        }
        for (batch.list.items) |invocation| {
            const thread = std.Thread.spawn(.{}, worker, .{invocation}) catch |err| {
                // A durable reservation survives failed OS admission and is recovered at reopen.
                invocation.end();
                invocation.finished.store(true, .release);
                invocation.cause = err;
                continue;
            };
            threads.appendAssumeCapacity(thread);
        }
        for (threads.items) |thread| thread.join();
        for (batch.list.items) |invocation| if (invocation.cause) |cause| try self.reports.append(self.gpa, .{ .task_id = invocation.task_id, .cause = cause });
        try self.reconcile();
        return batch.list.items.len;
    }
    pub fn runUntilBlocked(self: *Scheduler, max_batches: usize) !usize {
        var count: usize = 0;
        for (0..max_batches) |_| {
            const batch = try self.drive();
            if (batch == 0) return count;
            count += batch;
        }
        return error.SchedulerBatchLimit;
    }
    /// The VM owner can suspend one handler while it admits other work. Refill
    /// free worker slots so children created by a running handler can execute.
    /// The original bounded drive() keeps its one-batch semantics for callers.
    pub fn driveRefilling(self: *Scheduler) !usize {
        if (self.driving.swap(true, .acq_rel)) return error.ConcurrentSchedulerDrive;
        defer self.driving.store(false, .release);
        if (!self.enabled.load(.acquire)) return 0;
        if (self.closing.load(.acquire)) return error.SchedulerClosed;
        const ActiveWorker = struct { thread: std.Thread, invocation: *Invocation };
        var workers: std.ArrayList(ActiveWorker) = .empty;
        defer workers.deinit(self.gpa);
        try workers.ensureTotalCapacity(self.gpa, self.options.max_workers);
        errdefer {
            for (workers.items) |worker_entry| worker_entry.invocation.canceled.store(true, .release);
            for (workers.items) |worker_entry| worker_entry.thread.join();
        }
        var failed: std.AutoHashMapUnmanaged(u64, void) = .empty;
        defer failed.deinit(self.gpa);
        var count: usize = 0;
        while (true) {
            var index = workers.items.len;
            while (index > 0) {
                index -= 1;
                const worker_entry = workers.items[index];
                if (worker_entry.invocation.active.load(.acquire)) continue;
                worker_entry.thread.join();
                _ = workers.orderedRemove(index);
                if (worker_entry.invocation.cause) |cause| {
                    try failed.put(self.gpa, worker_entry.invocation.task_id, {});
                    try self.reports.append(self.gpa, .{ .task_id = worker_entry.invocation.task_id, .cause = cause });
                }
            }
            try self.reconcile();
            var executing: usize = 0;
            for (workers.items) |worker_entry| if (worker_entry.invocation.suspended_waits.load(.acquire) == 0) {
                executing += 1;
            };
            if (!self.closing.load(.acquire) and executing < self.options.max_workers) {
                self.mutex.lockUncancelable(self.io);
                const registry = self.gpa.dupe(*DefinitionNode, self.definitions.items) catch |err| {
                    self.mutex.unlock(self.io);
                    return err;
                };
                self.mutex.unlock(self.io);
                defer self.gpa.free(registry);
                const in_flight = try self.gpa.alloc(u64, workers.items.len);
                defer self.gpa.free(in_flight);
                for (workers.items, in_flight) |worker_entry, *id| id.* = worker_entry.invocation.task_id;
                var batch: Batch = .{ .scheduler = self, .registry = registry, .limit = self.options.max_workers - executing, .excluded = &failed, .in_flight = in_flight };
                defer batch.list.deinit(self.gpa);
                try batch.list.ensureTotalCapacity(self.gpa, batch.limit);
                try workers.ensureUnusedCapacity(self.gpa, batch.limit);
                var result = self.session.commit(Batch.reserve, &batch, .{}, .{}) catch |err| {
                    for (batch.list.items) |invocation| {
                        invocation.end();
                        invocation.finished.store(true, .release);
                    }
                    return err;
                };
                const published = result.seq != null;
                result.deinit();
                if (batch.marked_abandoned) {
                    self.abandoned.clearRetainingCapacity();
                    continue;
                }
                for (batch.list.items) |invocation| {
                    const thread = std.Thread.spawn(.{}, worker, .{invocation}) catch |err| {
                        invocation.end();
                        invocation.finished.store(true, .release);
                        invocation.cause = err;
                        try failed.put(self.gpa, invocation.task_id, {});
                        try self.reports.append(self.gpa, .{ .task_id = invocation.task_id, .cause = err });
                        continue;
                    };
                    workers.appendAssumeCapacity(.{ .thread = thread, .invocation = invocation });
                    count += 1;
                }
                // Orphaning a blocked child can unblock its owner's abort
                // without admitting a worker in this pass. Observe that
                // committed progress before deciding the driver is idle.
                if (published and batch.list.items.len == 0) continue;
            }
            if (workers.items.len == 0) return count;
            try self.io.sleep(.fromMilliseconds(5), .awake);
        }
    }
    const Batch = struct {
        scheduler: *Scheduler,
        registry: []const *DefinitionNode,
        list: std.ArrayList(*Invocation) = .empty,
        limit: usize = 0,
        excluded: ?*const std.AutoHashMapUnmanaged(u64, void) = null,
        in_flight: []const u64 = &.{},
        marked_abandoned: bool = false,
        fn lookup(self: *const @This(), name: []const u8) ?*DefinitionNode {
            var index = self.registry.len;
            while (index > 0) {
                index -= 1;
                if (self.registry[index].available.load(.acquire) and std.mem.eql(u8, self.registry[index].definition.name, name)) return self.registry[index];
            }
            return null;
        }
        fn reserve(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const scheduler = self.scheduler;
            if (scheduler.abandoned.count() != 0) {
                var pending = scheduler.abandoned.keyIterator();
                while (pending.next()) |id| {
                    const record = (try tx.currentRecord(id.*, .task)) orelse continue;
                    if (try model.live(record) and !try model.flag(record, "abortRequested"))
                        try tx.setTask(try model.abortMark(tx.owned.arena.allocator(), record, .restart));
                }
                self.marked_abandoned = true;
                return .null;
            }
            try scheduler.loadScopes();
            // Committed candidates keep Source's insertion order. Historical
            // tasks and Storage snapshots do not participate in reservation.
            const ids = try scheduler.gpa.dupe(u64, scheduler.ownership_index.runnable.keys());
            defer scheduler.gpa.free(ids);
            for (ids) |id| {
                if (self.list.items.len == (if (self.limit == 0) scheduler.options.max_workers else self.limit) or scheduler.closing.load(.acquire)) break;
                if (self.excluded) |excluded| if (excluded.contains(id)) continue;
                // end() may run before the old worker leaves its final Step;
                // never readmit that task until its owned thread is joined.
                if (std.mem.indexOfScalar(u64, self.in_flight, id) != null) continue;
                scheduler.mutex.lockUncancelable(scheduler.io);
                var already_active = false;
                for (scheduler.invocations.items) |invocation| if (invocation.task_id == id and invocation.active.load(.acquire)) {
                    already_active = true;
                    break;
                };
                scheduler.mutex.unlock(scheduler.io);
                if (already_active) continue;
                var record = (scheduler.live_records.get(id) orelse continue).value;
                const s = try model.status(record);
                if (s == .completing) continue;
                const mode: Mode = if (try model.flag(record, "abortRequested")) .abort else .run;
                if (mode == .run and !try model.flag(record, "background") and try scheduler.ownership_index.cancellingOwner((try recordLink(record)).parent()) != null) continue;
                if (mode == .abort and try scheduler.ownership_index.hasOrdinaryBelow(scheduler.gpa, ownership.Node.task(id))) {
                    _ = scheduler.ownership_index.runnable.orderedRemove(id);
                    continue;
                }
                if (mode == .run and s == .waiting) {
                    var blocked = false;
                    for ((try model.field(try model.field(record, "state"), "on")).array.items) |member| if (scheduler.ownership_index.live.contains(try json.asInteger(member))) {
                        blocked = true;
                        break;
                    };
                    if (blocked) {
                        _ = scheduler.ownership_index.runnable.orderedRemove(id);
                        continue;
                    }
                }
                const node = self.lookup(try model.text(record, "kind"));
                var blocked: ?Blocked = null;
                if (node == null) blocked = .missing_task else {
                    const version = try model.number(record, "version");
                    if (node.?.definition.version < version) blocked = .task_too_old;
                    if (node.?.definition.version > version) {
                        if (scheduler.migration_failures.get(id) == node.?.generation) blocked = .migration_failed else if (node.?.definition.migrate) |migration| {
                            const migrated = migration(node.?.definition.context, tx.owned.arena.allocator(), try model.field(record, "input"), try model.field(try model.field(record, "state"), "checkpoint"), version) catch {
                                try scheduler.migration_failures.put(id, node.?.generation);
                                blocked = .migration_failed;
                                continue;
                            };
                            record = try json.clone(tx.owned.arena.allocator(), record);
                            try record.object.put(tx.owned.arena.allocator(), "input", migrated.input);
                            try record.object.put(tx.owned.arena.allocator(), "version", .{ .integer = @intCast(node.?.definition.version) });
                            record = try model.withState(tx.owned.arena.allocator(), record, try model.checkpointState(tx.owned.arena.allocator(), "pending", migrated.checkpoint));
                        } else blocked = .migration_failed;
                    }
                }
                if (blocked) |reason| {
                    if (mode == .abort and json.get(record, "abortReason") == null) {
                        const terminal = try model.withState(tx.owned.arena.allocator(), record, try model.outcomeState(tx.owned.arena.allocator(), "terminal", try model.makeOutcome(tx.owned.arena.allocator(), "orphaned", .{ .string = @tagName(reason) })));
                        try tx.setTask(terminal);
                        try scheduler.settle(tx, terminal);
                    }
                    continue;
                }
                record = try model.withState(tx.owned.arena.allocator(), record, try model.checkpointState(tx.owned.arena.allocator(), "running", try model.field(try model.field(record, "state"), "checkpoint")));
                try tx.setTask(record);
                const invocation = try scheduler.gpa.create(Invocation);
                errdefer scheduler.gpa.destroy(invocation);
                invocation.* = .{ .scheduler = scheduler, .task_id = id, .conversation_id = try model.number(record, "conversationId"), .definition = node.?, .mode = mode };
                scheduler.mutex.lockUncancelable(scheduler.io);
                defer scheduler.mutex.unlock(scheduler.io);
                try scheduler.invocations.append(scheduler.gpa, invocation);
                self.list.appendAssumeCapacity(invocation);
            }
            return .null;
        }
    };
    fn worker(invocation: *Invocation) void {
        defer invocation.finished.store(true, .release);
        invocation.scheduler.execute(invocation) catch |err| {
            invocation.cause = err;
        };
        invocation.end();
    }
    fn execute(self: *Scheduler, invocation: *Invocation) !void {
        var previous: ?json.Owned = null;
        defer if (previous) |*value| value.deinit();
        var failure: ?anyerror = null;
        var abort_returned = false;
        for (0..self.options.max_phase_steps) |_| {
            var call: Step = .{ .invocation = invocation, .previous = if (previous) |value| value.value else null, .failure = failure, .abort_returned = abort_returned };
            var result = try self.session.commit(Step.apply, &call, .{ .conversationId = invocation.conversation_id, .taskId = invocation.task_id }, .{});
            defer result.deinit();
            if (result.value.value == .null) return;
            const record = result.value.value;
            const checkpoint = try model.field(try model.field(record, "state"), "checkpoint");
            if (previous) |*value| value.deinit();
            previous = try json.Owned.empty(self.gpa);
            previous.?.value = try json.clone(previous.?.arena.allocator(), checkpoint);
            var runtime: Runtime = .{ .invocation = invocation };
            if (invocation.mode == .abort) {
                invocation.definition.definition.abort(invocation.definition.definition.context, &runtime, record, runtime.context()) catch |err| {
                    failure = err;
                };
                abort_returned = true;
            } else {
                var handler: ?Handler = null;
                for (invocation.definition.definition.phases) |phase| if (std.mem.eql(u8, phase.name, try model.text(checkpoint, "phase"))) {
                    handler = phase.run;
                    break;
                };
                if (handler) |run| run(invocation.definition.definition.context, &runtime, record, runtime.context()) catch |err| {
                    failure = err;
                } else failure = error.UnknownTaskPhase;
            }
        }
        // Leave the durable running checkpoint intact for a later recovery; a bound is not a task failure.
        return error.SchedulerPhaseLimit;
    }
    const Step = struct {
        invocation: *Invocation,
        previous: ?Value,
        failure: ?anyerror,
        abort_returned: bool,
        fn apply(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const invocation = self.invocation;
            const scheduler = invocation.scheduler;
            const record = (try tx.currentRecord(invocation.task_id, .task)) orelse return error.UnknownTask;
            if (try model.status(record) != .running or scheduler.closing.load(.acquire) or (invocation.mode == .run and try model.flag(record, "abortRequested"))) {
                invocation.end();
                return .null;
            }
            if (invocation.mode == .run and !try model.flag(record, "background")) {
                const view = try scheduler.session.storage.snapshot(scheduler.gpa);
                defer view.destroy(scheduler.gpa);
                const canceled = (model.Graph{ .state = view }).belowCancelled(try model.parent(record)) catch |err| switch (err) {
                    // Source's walk ends at an unknown owner edge. Loading
                    // that chain remains the reconciliation pass's work.
                    error.UnknownTask, error.UnknownConversation => false,
                    else => return err,
                };
                // ea gives inherited cancellation precedence over a phase
                // failure or another phase, even before its cascade marks us.
                if (canceled) {
                    invocation.end();
                    return .null;
                }
            }
            const checkpoint = try model.field(try model.field(record, "state"), "checkpoint");
            var fault: ?Value = null;
            if (self.failure) |err| fault = .{ .string = if (invocation.diagnostic_cause != null and invocation.diagnostic_cause.? == err and invocation.diagnostic_len > 0) invocation.diagnostic[0..invocation.diagnostic_len] else @errorName(err) } else if (self.abort_returned) fault = .{ .string = try std.fmt.allocPrint(tx.owned.arena.allocator(), "Abort handler of task {d} returned without a terminal outcome", .{invocation.task_id}) } else if (self.previous) |previous| {
                if (json.equal(previous, checkpoint)) fault = .{ .string = try std.fmt.allocPrint(tx.owned.arena.allocator(), "Task {s} phase {s} returned without durable progress", .{ try model.text(record, "kind"), try model.text(previous, "phase") }) } else {
                    const replacement = scheduler.lookupDefinition(try model.text(record, "kind"));
                    if (replacement == null or (replacement.? != invocation.definition and (replacement.?.definition.version == invocation.definition.definition.version or (replacement.?.definition.version > invocation.definition.definition.version and replacement.?.definition.migrate != null)))) {
                        invocation.end();
                        try tx.setTask(try model.withState(tx.owned.arena.allocator(), record, try model.checkpointState(tx.owned.arena.allocator(), "pending", checkpoint)));
                        return .null;
                    }
                }
            }
            if (fault) |value| {
                invocation.end();
                const view = try overlay(scheduler.gpa, tx);
                defer view.destroy(scheduler.gpa);
                var failure_object = model.object(tx.owned.arena.allocator());
                try failure_object.object.put(tx.owned.arena.allocator(), "message", value);
                const state = try model.outcomeState(tx.owned.arena.allocator(), if (try (model.Graph{ .state = view }).hasOwnedLive(invocation.task_id)) "completing" else "terminal", try model.makeOutcome(tx.owned.arena.allocator(), "faulted", failure_object));
                try tx.setTask(try model.withState(tx.owned.arena.allocator(), record, state));
                if (std.mem.eql(u8, try model.text(state, "status"), "terminal")) try scheduler.settle(tx, try model.withState(tx.owned.arena.allocator(), record, state));
                return .null;
            }
            return record;
        }
    };
};

/// Ownership traversal over an immutable committed-state view. A VM owner can
/// apply the same rule to its publication mirror without taking the Session line.
pub fn idleState(view: *const backend.memory.State, conversation: ?u64) !bool {
    var rows = view.rows.iterator();
    while (rows.next()) |item| {
        const row = item.value_ptr.*;
        if (row.table != .task or !try model.live(row.record) or try model.flag(row.record, "background")) continue;
        if (try ordinaryInIdleScope(view, try model.parent(row.record), conversation)) return false;
    }
    return true;
}

test "durable.scheduler ea actual Storage owner line retention reload and separate sweep match Source" {
    const Probe = struct {
        memory: *backend.memory.Memory,
        scheduler: *Scheduler,
        operation: enum { root, seed, end_link, reload_empty, reload_reject, leaf, end_leaf, end_parent, reserve_without_history, hold_parent } = .root,
        parent: u64 = 0,
        link: u64 = 0,
        conversation: u64 = 0,
        leaf: u64 = 0,
        read_conversation: bool = false,
        read_terminal: bool = false,
        forbid_snapshot: bool = false,
        fn own(raw: ?*anyopaque) *@This() {
            return @ptrCast(@alignCast(raw.?));
        }
        fn base(self: *@This()) backend.Backend {
            return .{ .memory = self.memory };
        }
        fn mint(raw: ?*anyopaque) !u64 {
            return own(raw).base().mintId();
        }
        fn commit(raw: ?*anyopaque, writes: Value, seq: ?u64) !u64 {
            return own(raw).base().commitAt(writes, seq);
        }
        fn snapshot(raw: ?*anyopaque, gpa: std.mem.Allocator) !*backend.memory.State {
            const self = own(raw);
            if (self.forbid_snapshot) return error.ReservationReadHistoricalSnapshot;
            return self.base().snapshot(gpa);
        }
        fn record(raw: ?*anyopaque, gpa: std.mem.Allocator, id: u64) !?json.Owned {
            return own(raw).base().readRecord(gpa, id);
        }
        fn table(raw: ?*anyopaque, gpa: std.mem.Allocator, kind: backend.memory.Table, id: u64) !?json.Owned {
            const self = own(raw);
            if (kind == .conversation and id == self.conversation) self.read_conversation = true;
            if (kind == .task and id == self.link) self.read_terminal = true;
            return self.base().readTableRecord(gpa, kind, id);
        }
        fn entry(raw: ?*anyopaque, gpa: std.mem.Allocator, id: u64, conversation: ?u64) !?json.Owned {
            return own(raw).base().readEntry(gpa, id, conversation);
        }
        fn document(raw: ?*anyopaque, gpa: std.mem.Allocator, id: u64, point: backend.memory.Point) !?json.Owned {
            return own(raw).base().readDocument(gpa, id, point);
        }
        fn scan(raw: ?*anyopaque, gpa: std.mem.Allocator, query: backend.query.Query) !json.Owned {
            return own(raw).base().scan(gpa, query);
        }
        const vtable: backend.Custom.VTable = .{ .mintId = mint, .commitAt = commit, .snapshot = snapshot, .readRecord = record, .readTableRecord = table, .readEntry = entry, .readDocument = document, .scan = scan };
        fn finish(self: *@This(), tx: *Transaction, id: u64) !void {
            var current = (try tx.session.storage.readTableRecord(tx.gpa, .task, id)).?;
            defer current.deinit();
            const arena = tx.owned.arena.allocator();
            try tx.setTask(try model.withState(arena, current.value, try model.outcomeState(arena, "terminal", try model.makeOutcome(arena, "completed", .null))));
            _ = self;
        }
        fn apply(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            const self = own(raw);
            const checkpoint = try json.Owned.parse(tx.gpa, "{\"phase\":\"hold\"}");
            var owned_checkpoint = checkpoint;
            defer owned_checkpoint.deinit();
            switch (self.operation) {
                .root => _ = try tx.createRootConversation(),
                .seed => {
                    self.parent = try tx.createTask("fixture.ea-retention", 1, .null, checkpoint.value, .{ .conversationId = 1 });
                    self.link = try tx.createTask("fixture.ea-retention", 1, .null, checkpoint.value, .{ .ownerTaskId = self.parent });
                    self.conversation = try model.number(try tx.createConversation(null, self.link), "id");
                },
                .end_link => try self.finish(tx, self.link),
                .end_leaf => try self.finish(tx, self.leaf),
                .end_parent => try self.finish(tx, self.parent),
                .hold_parent => {
                    var current = (try tx.session.storage.readTableRecord(tx.gpa, .task, self.parent)).?;
                    defer current.deinit();
                    const arena = tx.owned.arena.allocator();
                    try tx.setTask(try model.withState(arena, current.value, try model.outcomeState(arena, "completing", try model.makeOutcome(arena, "completed", .null))));
                },
                .reserve_without_history => {
                    self.forbid_snapshot = true;
                    defer self.forbid_snapshot = false;
                    var batch: Scheduler.Batch = .{ .scheduler = self.scheduler, .registry = &.{} };
                    defer batch.list.deinit(tx.gpa);
                    try batch.list.ensureTotalCapacity(tx.gpa, self.scheduler.options.max_workers);
                    _ = try Scheduler.Batch.reserve(&batch, tx, .{});
                    // Missing definitions stay blocked without creating any
                    // invocation or reading historical storage records.
                    try std.testing.expectEqual(@as(usize, 0), batch.list.items.len);
                },
                .reload_empty, .reload_reject, .leaf => {
                    try self.scheduler.loadChain(ownership.Node.conversation(self.conversation));
                    // The operation may still create work beneath these nodes.
                    try std.testing.expect(self.scheduler.ownership_index.edges.contains(self.conversation));
                    try std.testing.expect(self.scheduler.ownership_index.settled.contains(self.link));
                    if (self.operation == .reload_reject) return error.OriginalReadRejection;
                    if (self.operation == .leaf) self.leaf = try tx.createTask("fixture.ea-retention", 1, .null, checkpoint.value, .{ .conversationId = self.conversation });
                },
            }
            return .null;
        }
        fn run(self: *@This(), operation: @FieldType(@This(), "operation")) !void {
            self.operation = operation;
            var result = try self.scheduler.session.commit(apply, self, .{}, .{});
            result.deinit();
            if (operation == .seed or operation == .leaf or operation == .reserve_without_history) self.forbid_snapshot = true;
            defer self.forbid_snapshot = false;
            try self.scheduler.reconcile();
        }
        fn expect(self: *@This(), golden: Value) !void {
            const actual = self.scheduler.ownership_index.sizes();
            inline for (std.meta.fields(ownership.Sizes)) |field| try std.testing.expectEqual(try model.number(try model.field(golden, "sizes"), field.name), @field(actual, field.name));
            try std.testing.expectEqual(actual.live, self.scheduler.live_records.count());
        }
    };
    const gpa = std.testing.allocator;
    var golden = try json.Owned.parse(gpa, @embedFile("fixtures/durable-ea-retention.json"));
    defer golden.deinit();
    const rows = (try model.field(golden.value, "rows")).array.items;
    var memory = try backend.memory.Memory.init(gpa);
    defer memory.deinit();
    var probe: Probe = .{ .memory = &memory, .scheduler = undefined };
    var session = session_mod.Session.init(gpa, std.testing.io, .{ .custom = .{ .context = &probe, .vtable = &Probe.vtable } });
    defer session.deinit();
    var scheduler = try Scheduler.init(gpa, std.testing.io, &session, .{});
    defer scheduler.deinit();
    probe.scheduler = &scheduler;
    try scheduler.open();
    try probe.run(.root);
    try probe.expect(rows[0]);
    try probe.run(.seed);
    try probe.expect(rows[1]);
    try probe.run(.reserve_without_history);
    try probe.expect(rows[1]);
    try probe.run(.end_link);
    try probe.expect(rows[2]);
    // Neither rejected nor empty reads publish. Their loaded ended chain is
    // swept by a separate maintenance job only after the callback has ended.
    probe.operation = .reload_reject;
    try std.testing.expectError(error.OriginalReadRejection, session.commit(Probe.apply, &probe, .{}, .{}));
    try std.testing.expect(session.failure() == null);
    try probe.expect(rows[2]);
    try probe.run(.reload_empty);
    try probe.expect(rows[2]);
    probe.read_conversation = false;
    probe.read_terminal = false;
    try probe.run(.leaf);
    try probe.expect(rows[3]);
    const reloaded = try model.field(rows[3], "reloaded");
    try std.testing.expectEqual(try model.flag(reloaded, "conversation"), probe.read_conversation);
    try std.testing.expectEqual(try model.flag(reloaded, "terminalTask"), probe.read_terminal);
    const below = try scheduler.ownership_index.ordinaryOwned(gpa, probe.parent);
    defer gpa.free(below);
    try std.testing.expectEqualSlices(u64, &.{probe.leaf}, below);
    try probe.run(.end_leaf);
    try probe.expect(rows[4]);
    try probe.run(.end_parent);
    try probe.expect(rows[5]);
    // A held owner is checked again only after its last live child ends. The
    // local index sees the child's terminal candidate before considering the
    // owner, and the authoritative live copies disappear on publication.
    try probe.run(.seed);
    try probe.run(.hold_parent);
    try probe.expect(rows[1]);
    try probe.run(.end_link);
    try probe.expect(rows[5]);
    var held_owner = (try session.storage.readTableRecord(gpa, .task, probe.parent)).?;
    defer held_owner.deinit();
    try std.testing.expectEqual(model.Status.terminal, try model.status(held_owner.value));
}
fn ordinaryInIdleScope(view: *const backend.memory.State, start: model.Up, conversation: ?u64) !bool {
    var at = start;
    var remaining = view.rows.count() + 1;
    while (remaining > 0) : (remaining -= 1) switch (at) {
        .task => |id| {
            // Source treats an edge not loaded yet as inside until resolved.
            const row = view.rows.get(id) orelse return true;
            if (row.table != .task) return true;
            if (try model.flag(row.record, "background")) return false;
            at = try model.parent(row.record);
        },
        .conversation => |id| {
            if (conversation == id) return true;
            const row = view.rows.get(id) orelse return true;
            if (row.table != .conversation) return true;
            const owner = json.get(row.record, "owner") orelse return conversation == null;
            at = .{ .task = try json.asInteger(try json.required(owner, "taskId")) };
        },
    };
    return error.TaskOwnershipCycle;
}
test "durable.scheduler idle publication views conservatively retain unknown ownership edges and stop at background owners" {
    const gpa = std.testing.allocator;
    const view = try backend.memory.State.create(gpa);
    defer view.destroy(gpa);
    var records = try json.Owned.parse(gpa, "[{\"id\":1},{\"id\":2},{\"id\":3,\"conversationId\":1,\"background\":false,\"state\":{\"status\":\"running\"}},{\"id\":1,\"owner\":{\"taskId\":9}},{\"id\":9,\"conversationId\":2,\"background\":true,\"state\":{\"status\":\"terminal\"}}]");
    defer records.deinit();
    for (records.value.array.items[0..3], 0..) |record, index| try view.rows.put(try json.asInteger(try json.required(record, "id")), .{ .table = if (index == 2) .task else .conversation, .record = record, .commitSeq = 0 });
    try std.testing.expect(!try idleState(view, null));
    try std.testing.expect(!try idleState(view, 1));
    try std.testing.expect(try idleState(view, 2));
    _ = view.rows.remove(1);
    try std.testing.expect(!try idleState(view, null));
    try std.testing.expect(!try idleState(view, 2));
    try view.rows.put(1, .{ .table = .conversation, .record = records.value.array.items[3], .commitSeq = 0 });
    try std.testing.expect(!try idleState(view, null));
    try view.rows.put(9, .{ .table = .task, .record = records.value.array.items[4], .commitSeq = 0 });
    try std.testing.expect(try idleState(view, null));
    try std.testing.expect(try idleState(view, 2));
    try std.testing.expect(!try idleState(view, 1));
}

test "durable.scheduler ea owner cancellation ends a run before its cascade without faulting or marking the child" {
    const Fixture = struct {
        fn phase(_: ?*anyopaque, _: *Runtime, _: Value, _: types.Context) anyerror!void {}
    };
    const gpa = std.testing.allocator;
    for ([_]bool{ false, true }) |background| {
        var memory = try backend.memory.Memory.init(gpa);
        defer memory.deinit();
        var seeded = try json.Owned.parse(gpa,
            \\[{"type":"conversation","value":{"id":1}},{"type":"task","value":{"id":2,"conversationId":1,"kind":"owner","version":1,"input":null,"background":false,"abortRequested":true,"state":{"status":"running","checkpoint":{"phase":"one"}}}},{"type":"task","value":{"id":3,"conversationId":1,"owner":2,"kind":"child","version":1,"input":null,"background":false,"abortRequested":false,"state":{"status":"running","checkpoint":{"phase":"one"}}}}]
        );
        defer seeded.deinit();
        if (background) {
            // A background task hangs directly from its conversation, so make
            // that conversation owned by the canceled task for this boundary.
            const a = seeded.arena.allocator();
            const child = seeded.value.array.items[2].object.getPtr("value").?;
            _ = child.object.orderedRemove("owner");
            try child.object.put(a, "background", .{ .bool = true });
            var owner: Value = .{ .object = .empty };
            try owner.object.put(a, "taskId", .{ .integer = 2 });
            try owner.object.put(a, "conversationId", .{ .integer = 4 });
            try seeded.value.array.items[0].object.getPtr("value").?.object.put(a, "owner", owner);
            // The owner's ordinary root is a different conversation.
            try seeded.value.array.items[1].object.getPtr("value").?.object.put(a, "conversationId", .{ .integer = 4 });
            var root: Value = .{ .object = .empty };
            try root.object.put(a, "id", .{ .integer = 4 });
            var write: Value = .{ .object = .empty };
            try write.object.put(a, "type", .{ .string = "conversation" });
            try write.object.put(a, "value", root);
            try seeded.value.array.append(write);
        }
        _ = try memory.commit(seeded.value);
        var session = session_mod.Session.init(gpa, std.testing.io, .{ .memory = &memory });
        defer session.deinit();
        var scheduler = try Scheduler.init(gpa, std.testing.io, &session, .{});
        defer scheduler.deinit();
        const phases = [_]Phase{.{ .name = "one", .run = Fixture.phase }};
        try scheduler.register(.{ .name = "child", .version = 1, .phases = &phases, .abort = Fixture.phase });
        var invocation: Invocation = .{ .scheduler = &scheduler, .task_id = 3, .conversation_id = 1, .definition = scheduler.definitions.items[0], .mode = .run };
        var step: Scheduler.Step = .{ .invocation = &invocation, .previous = null, .failure = null, .abort_returned = false };
        var result = try session.commit(Scheduler.Step.apply, &step, .{}, .{});
        defer result.deinit();
        try std.testing.expectEqual(background, invocation.active.load(.acquire));
        try std.testing.expectEqual(background, result.value.value != .null);
        var child = (try memory.readRecord(gpa, 3)).?;
        defer child.deinit();
        try std.testing.expectEqual(.running, try model.status(child.value));
        try std.testing.expect(!try model.flag(child.value, "abortRequested"));
        try std.testing.expectEqual(@as(?u64, null), result.seq);
    }
}
