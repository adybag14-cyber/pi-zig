//! Native durable phase scheduler. Dispatch is explicitly driven in bounded batches.
//! Every reservation, runtime write, and step is fenced on the Session line.
const std = @import("std");
const backend = @import("backend/root.zig");
const session_mod = @import("session.zig");
const model = @import("task_state.zig");
const types = @import("types.zig");
const json = backend.json;
const Value = json.Value;
const Transaction = session_mod.Transaction;
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
    subscription: ?u64 = null,
    close_subscription: ?u64 = null,
    generation: u64 = 1,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, session: *session_mod.Session, options: Options) !Scheduler {
        if (options.max_workers == 0 or options.max_workers > 64 or options.max_phase_steps == 0) return error.InvalidSchedulerBounds;
        return .{ .gpa = gpa, .io = io, .session = session, .options = options, .migration_failures = .init(gpa) };
    }
    /// Caller joins all drive calls and releases retained runtimes before deinit.
    pub fn deinit(self: *Scheduler) void {
        std.debug.assert(!self.driving.load(.acquire));
        self.close();
        if (self.subscription) |id| self.session.unsubscribe(id);
        if (self.close_subscription) |id| self.session.unsubscribeClose(id);
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
        self.subscription = try self.session.subscribe(observe, self);
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
    fn recover(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
        const self: *Scheduler = @ptrCast(@alignCast(raw.?));
        const view = try self.session.storage.snapshot(self.gpa);
        defer view.destroy(self.gpa);
        var rows = view.rows.iterator();
        while (rows.next()) |item| {
            if (item.value_ptr.table != .task) continue;
            const record = item.value_ptr.record;
            if (try model.status(record) == .running) try tx.setTask(try model.withState(tx.owned.arena.allocator(), record, try model.checkpointState(tx.owned.arena.allocator(), "pending", try model.field(try model.field(record, "state"), "checkpoint"))));
        }
        return .null;
    }
    pub fn reconcile(self: *Scheduler) !void {
        var result = try self.session.commit(reconcileLine, self, .{}, .{});
        result.deinit();
    }
    fn reconcileLine(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
        const self: *Scheduler = @ptrCast(@alignCast(raw.?));
        if (self.options.poll_reads) |poll| try poll(self.options.callback_context, tx.session);
        const view = try self.session.storage.snapshot(self.gpa);
        defer view.destroy(self.gpa);
        const a = view.arena.allocator();
        const graph: model.Graph = .{ .state = view };
        // Repeat until held outcomes and inherited abort marks reach a fixed point.
        var changed = true;
        while (changed) {
            changed = false;
            var rows = view.rows.iterator();
            while (rows.next()) |item| {
                if (item.value_ptr.table != .task) continue;
                var record = item.value_ptr.record;
                if (!try model.live(record)) continue;
                var mark = !try model.flag(record, "background") and try graph.belowCancelled(try model.parent(record));
                if (try model.status(record) == .waiting) {
                    const state = try model.field(record, "state");
                    if (std.mem.eql(u8, try model.text(state, "policy"), "failFast")) {
                        var any_failed = false;
                        for ((try model.field(state, "on")).array.items) |member| if (try model.failed(try graph.task(try json.asInteger(member)))) {
                            any_failed = true;
                            break;
                        };
                        if (any_failed) for ((try model.field(state, "on")).array.items) |member| {
                            const id = try json.asInteger(member);
                            const child = try graph.task(id);
                            if (try model.live(child) and !try model.failed(child) and !try model.flag(child, "abortRequested")) {
                                var child_mark = try json.clone(a, child);
                                try child_mark.object.put(a, "abortRequested", .{ .bool = true });
                                view.rows.getPtr(id).?.record = child_mark;
                                try tx.setTask(child_mark);
                                changed = true;
                            }
                        };
                    }
                }
                mark = mark and !try model.flag(record, "abortRequested");
                if (mark) {
                    record = try json.clone(a, record);
                    try record.object.put(a, "abortRequested", .{ .bool = true });
                }
                var finalize = false;
                if (try model.status(record) == .completing and !try graph.hasOwnedLive(item.key_ptr.*)) {
                    record = try model.withState(a, record, try model.outcomeState(a, "terminal", try model.field(try model.field(record, "state"), "outcome")));
                    finalize = true;
                }
                if (mark or finalize) {
                    item.value_ptr.record = record;
                    try tx.setTask(record);
                    changed = true;
                }
                if (finalize) try self.settle(tx, record);
            }
        }
        if (self.options.withdraw_inputs) |withdraw| {
            const queued = try queuedConversations(view);
            for (queued) |id| if (try graph.belowCancelled(.{ .conversation = id })) try withdraw(self.options.callback_context, tx, id);
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
    const ScopeAbort = struct {
        scheduler: *Scheduler,
        conversation: u64,
        cross_background: bool,
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
                var marked = try json.clone(tx.owned.arena.allocator(), row.record);
                try marked.object.put(tx.owned.arena.allocator(), "abortRequested", .{ .bool = true });
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
            const view = try self.scheduler.session.storage.snapshot(self.scheduler.gpa);
            defer view.destroy(self.scheduler.gpa);
            const graph: model.Graph = .{ .state = view };
            var rows = view.rows.iterator();
            while (rows.next()) |item| {
                const row = item.value_ptr.*;
                if (row.table != .task or !try model.live(row.record) or try model.flag(row.record, "background")) continue;
                if (self.conversation) |id| {
                    if (try graph.reaches(try model.parent(row.record), .{ .conversation = id }, false)) return .{ .bool = false };
                } else {
                    // Root-wide idle excludes descendants hidden behind a background owner.
                    var conversations = view.rows.iterator();
                    while (conversations.next()) |root_row| if (root_row.value_ptr.table == .conversation and json.get(root_row.value_ptr.record, "owner") == null and try graph.reaches(try model.parent(row.record), .{ .conversation = root_row.key_ptr.* }, false)) return .{ .bool = false };
                }
            }
            return .{ .bool = true };
        }
    };
    pub fn abort(self: *Scheduler, id: u64) !void {
        var call: AbortCall = .{ .scheduler = self, .id = id };
        var result = try self.session.commit(AbortCall.apply, &call, .{}, .{});
        result.deinit();
        try self.reconcile();
    }
    const AbortCall = struct {
        scheduler: *Scheduler,
        id: u64,
        fn apply(raw: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var record = (try tx.currentRecord(self.id, .task)) orelse return error.UnknownTask;
            if (try model.status(record) == .terminal) return .null;
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
            record = try json.clone(tx.owned.arena.allocator(), record);
            try record.object.put(tx.owned.arena.allocator(), "abortRequested", .{ .bool = true });
            try tx.setTask(record);
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
            for (batch.list.items) |invocation| invocation.end();
            return err;
        };
        result.deinit();
        for (batch.list.items) |invocation| {
            const thread = std.Thread.spawn(.{}, worker, .{invocation}) catch |err| {
                // A durable reservation survives failed OS admission and is recovered at reopen.
                invocation.end();
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
                    for (batch.list.items) |invocation| invocation.end();
                    return err;
                };
                result.deinit();
                for (batch.list.items) |invocation| {
                    const thread = std.Thread.spawn(.{}, worker, .{invocation}) catch |err| {
                        invocation.end();
                        invocation.cause = err;
                        try failed.put(self.gpa, invocation.task_id, {});
                        try self.reports.append(self.gpa, .{ .task_id = invocation.task_id, .cause = err });
                        continue;
                    };
                    workers.appendAssumeCapacity(.{ .thread = thread, .invocation = invocation });
                    count += 1;
                }
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
            const view = try scheduler.session.storage.snapshot(scheduler.gpa);
            defer view.destroy(scheduler.gpa);
            const graph: model.Graph = .{ .state = view };
            var ids: std.ArrayList(u64) = .empty;
            defer ids.deinit(scheduler.gpa);
            var rows = view.rows.iterator();
            while (rows.next()) |item| if (item.value_ptr.table == .task and try model.live(item.value_ptr.record)) try ids.append(scheduler.gpa, item.key_ptr.*);
            std.mem.sort(u64, ids.items, {}, std.sort.asc(u64));
            for (ids.items) |id| {
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
                var record = try graph.task(id);
                const s = try model.status(record);
                if (s == .completing) continue;
                const mode: Mode = if (try model.flag(record, "abortRequested")) .abort else .run;
                if (mode == .abort and try graph.hasOwnedLive(id)) continue;
                if (mode == .run and try graph.waitingOn(record)) continue;
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
                    if (mode == .abort) {
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
