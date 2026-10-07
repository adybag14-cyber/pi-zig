//! Serialized native Session transactions   and   committed table/document events.
const std = @import("std");
const backend = @import("backend/root.zig");
const json = backend.json;
const types = @import("types.zig");
const Value = json.Value;
const tasks = @import("task_state.zig");
pub const TaskOptions = struct { conversationId: ?u64 = null, ownerTaskId: ?u64 = null, background: bool = false };
pub const Scope = struct { conversationId: ?u64 = null, taskId: ?u64 = null };
pub const Publication = struct { seq: u64, changes: Value };
pub const Listener = *const fn (?*anyopaque, *const Publication, types.Context) anyerror!void;
pub const CloseListener = *const fn (?*anyopaque) void;
pub const CommitFn = *const fn (?*anyopaque, *Transaction, types.Context) anyerror!Value;
pub const Result = struct {
    value: json.Owned,
    seq: ?u64 = null,
    pub fn deinit(self: *Result) void {
        self.value.deinit();
    }
};
const Subscription = struct { id: u64, callback: Listener, context: ?*anyopaque };
const CloseSubscription = struct { id: u64, callback: CloseListener, context: ?*anyopaque };
pub const Session = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    storage: backend.Backend,
    mutex: std.Io.Mutex = .init,
    listeners: std.ArrayList(Subscription) = .empty,
    nextSubscription: u64 = 1,
    closed: bool = false,
    poison: ?anyerror = null,
    ownerThread: std.atomic.Value(std.Thread.Id) = .init(0),
    closeListeners: std.ArrayList(CloseSubscription) = .empty,
    closeMutex: std.Io.Mutex = .init,
    closeOwnerThread: std.atomic.Value(std.Thread.Id) = .init(0),
    closeNotified: bool = false,
    source_clock: ?*const fn (?*anyopaque) i64 = null,
    source_clock_context: ?*anyopaque = null,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, storage: backend.Backend) Session {
        return .{ .gpa = gpa, .io = io, .storage = storage };
    }
    pub fn deinit(self: *Session) void {
        self.close();
        self.closeListeners.deinit(self.gpa);
        self.listeners.deinit(self.gpa);
        self.* = undefined;
    }
    fn healthy(self: *const Session) !void {
        if (self.closed) return error.SessionClosed;
        if (self.poison) |err| return err;
    }
    pub fn subscribe(self: *Session, callback: Listener, context: ?*anyopaque) !u64 {
        const on_owner = self.ownerThread.load(.acquire) == std.Thread.getCurrentId();
        if (!on_owner) try self.mutex.lock(self.io);
        defer if (!on_owner) self.mutex.unlock(self.io);
        try self.healthy();
        const id = self.nextSubscription;
        try self.listeners.append(self.gpa, .{ .id = id, .callback = callback, .context = context });
        self.nextSubscription += 1;
        return id;
    }
    pub fn unsubscribe(self: *Session, id: u64) void {
        const on_owner = self.ownerThread.load(.acquire) == std.Thread.getCurrentId();
        if (!on_owner) self.mutex.lockUncancelable(self.io);
        defer if (!on_owner) self.mutex.unlock(self.io);
        for (self.listeners.items, 0..) |item, index| if (item.id == id) {
            _ = self.listeners.orderedRemove(index);
            return;
        };
    }
    pub fn subscribeClose(self: *Session, callback: CloseListener, context: ?*anyopaque) !u64 {
        const on_owner = self.ownerThread.load(.acquire) == std.Thread.getCurrentId();
        if (!on_owner) try self.mutex.lock(self.io);
        defer if (!on_owner) self.mutex.unlock(self.io);
        try self.healthy();
        const id = self.nextSubscription;
        try self.closeListeners.append(self.gpa, .{ .id = id, .callback = callback, .context = context });
        self.nextSubscription += 1;
        return id;
    }
    /// Off-line unsubscribe waits for any in-flight close callback. A callback can remove later callbacks.
    pub fn unsubscribeClose(self: *Session, id: u64) void {
        const on_owner = self.ownerThread.load(.acquire) == std.Thread.getCurrentId();
        const on_close = self.closeOwnerThread.load(.acquire) == std.Thread.getCurrentId();
        if (!on_owner and !on_close) self.closeMutex.lockUncancelable(self.io);
        defer if (!on_owner and !on_close) self.closeMutex.unlock(self.io);
        if (!on_owner) self.mutex.lockUncancelable(self.io);
        defer if (!on_owner) self.mutex.unlock(self.io);
        for (self.closeListeners.items, 0..) |item, index| if (item.id == id) {
            _ = self.closeListeners.orderedRemove(index);
            return;
        };
    }
    pub fn commit(self: *Session, callback: CommitFn, callback_context: ?*anyopaque, scope: Scope, context: types.Context) !Result {
        if (self.ownerThread.load(.acquire) == std.Thread.getCurrentId()) return error.ReentrantSessionCommit;
        if (context.aborted()) return error.Canceled;
        try self.mutex.lock(self.io);
        defer {
            self.mutex.unlock(self.io);
            self.notifyClose();
        }
        self.ownerThread.store(std.Thread.getCurrentId(), .release);
        defer self.ownerThread.store(0, .release);
        try self.healthy();
        if (context.aborted()) return error.Canceled;
        const tx = try Transaction.create(self, scope);
        defer tx.release();
        defer tx.active = false;
        const returned = try callback(callback_context, tx, context);
        if (context.aborted()) return error.Canceled;
        var result: Result = .{ .value = try json.Owned.empty(self.gpa) };
        errdefer result.deinit();
        result.value.value = try json.clone(result.value.arena.allocator(), returned);
        tx.active = false;
        if (tx.writes.array.items.len == 0) return result;
        // Stage both durable state   and   publication before admitting storage.
        var predicted: backend.memory.Memory = .{ .gpa = self.gpa, .state = try self.storage.snapshot(self.gpa) };
        defer predicted.deinit();
        try tx.assembleTasks(&predicted);
        var prepared = try predicted.prepare(tx.writes, null);
        defer prepared.deinit();
        var publication = try buildPublication(self.gpa, prepared.state.?, prepared.seq, tx.writes, &tx.preparedDocumentOps);
        defer publication.deinit();
        const listeners = try self.gpa.dupe(Subscription, self.listeners.items);
        defer self.gpa.free(listeners);
        const seq = self.storage.commitAt(tx.writes, prepared.seq) catch |err| {
            if (err != error.StorageRejected and err != error.OutOfMemory) self.poison = err;
            return err;
        };
        result.seq = seq;
        if (tx.after_storage) |adopt| try adopt(tx.after_storage_context);
        const event: Publication = .{ .seq = seq, .changes = publication.value };
        for (listeners) |listener| try listener.callback(listener.context, &event, context);
        return result;
    }
    pub fn close(self: *Session) void {
        if (self.ownerThread.load(.acquire) == std.Thread.getCurrentId()) {
            self.closed = true;
            return;
        }
        self.mutex.lockUncancelable(self.io);
        self.closed = true;
        self.mutex.unlock(self.io);
        self.notifyClose();
    }
    fn notifyClose(self: *Session) void {
        if (self.closeOwnerThread.load(.acquire) == std.Thread.getCurrentId()) return;
        self.closeMutex.lockUncancelable(self.io);
        defer self.closeMutex.unlock(self.io);
        self.closeOwnerThread.store(std.Thread.getCurrentId(), .release);
        defer self.closeOwnerThread.store(0, .release);
        self.mutex.lockUncancelable(self.io);
        if (!self.closed or self.closeNotified) {
            self.mutex.unlock(self.io);
            return;
        }
        self.closeNotified = true;
        while (self.closeListeners.items.len > 0) {
            const listener = self.closeListeners.orderedRemove(0);
            self.mutex.unlock(self.io);
            listener.callback(listener.context);
            self.mutex.lockUncancelable(self.io);
        }
        self.closeListeners.deinit(self.gpa);
        self.closeListeners = .empty;
        self.mutex.unlock(self.io);
    }
};
pub const Transaction = struct {
    gpa: std.mem.Allocator,
    session: *Session,
    owned: json.Owned,
    writes: Value,
    scope: Scope,
    active: bool = true,
    tableWritten: bool = false,
    refs: std.atomic.Value(usize) = .init(1),
    ownerThread: std.Thread.Id,
    createdTasks: std.ArrayList(u64) = .empty,
    preparedDocumentOps: std.AutoHashMapUnmanaged(u64, Value) = .empty,
    after_storage: ?*const fn (?*anyopaque) anyerror!void = null,
    after_storage_context: ?*anyopaque = null,
    fn create(session: *Session, scope: Scope) !*Transaction {
        const self = try session.gpa.create(Transaction);
        errdefer session.gpa.destroy(self);
        const owned = try json.Owned.empty(session.gpa);
        self.* = .{ .gpa = session.gpa, .session = session, .owned = owned, .scope = scope, .writes = .{ .array = .init(owned.arena.allocator()) }, .ownerThread = std.Thread.getCurrentId() };
        return self;
    }
    pub fn retain(self: *Transaction) *Transaction {
        _ = self.refs.fetchAdd(1, .monotonic);
        return self;
    }
    pub fn release(self: *Transaction) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) {
            const gpa = self.gpa;
            self.owned.deinit();
            gpa.destroy(self);
        }
    }
    fn ensureActive(self: *Transaction) !void {
        if (self.ownerThread != std.Thread.getCurrentId()) return error.WrongTransactionThread;
        if (!self.active) return error.TransactionClosed;
    }
    fn reading(self: *Transaction) !void {
        try self.ensureActive();
        if (self.tableWritten) return error.ReadAfterWrite;
    }
    fn allocator(self: *Transaction) std.mem.Allocator {
        return self.owned.arena.allocator();
    }
    pub fn readRecord(self: *Transaction, table: backend.memory.Table, id: u64) !?Value {
        try self.reading();
        var record = (try self.session.storage.readTableRecord(self.gpa, table, id)) orelse return null;
        defer record.deinit();
        return try json.clone(self.allocator(), record.value);
    }
    pub fn scan(self: *Transaction, query: backend.query.Query) !Value {
        try self.reading();
        var page = try self.session.storage.scan(self.gpa, query);
        defer page.deinit();
        return json.clone(self.allocator(), page.value);
    }
    fn stage(self: *Transaction, write: Value) !void {
        try self.ensureActive();
        try self.writes.array.append(try json.clone(self.allocator(), write));
    }
    pub fn writeRecord(self: *Transaction, table: backend.memory.Table, record: Value) !void {
        try self.ensureActive();
        if (table == .document) return error.UseDocumentCommand;
        if (table == .task) return self.setTask(record);
        self.tableWritten = true;
        var write: Value = .{ .object = .empty };
        try write.object.put(self.allocator(), "type", .{ .string = @tagName(table) });
        try write.object.put(self.allocator(), "value", record);
        try self.stage(write);
    }
    pub fn currentRecord(self: *Transaction, id: u64, table: backend.memory.Table) !?Value {
        try self.ensureActive();
        var index = self.writes.array.items.len;
        while (index > 0) {
            index -= 1;
            const write = self.writes.array.items[index];
            if (json.get(write, "value")) |value| if (try backend.memory.idOf(value) == id) {
                if (!std.mem.eql(u8, try json.asString(try backend.memory.field(write, "type")), @tagName(table))) return null;
                return value;
            };
        }
        var record = (try self.session.storage.readTableRecord(self.gpa, table, id)) orelse return null;
        defer record.deinit();
        return try json.clone(self.allocator(), record.value);
    }
    pub fn createRootConversation(self: *Transaction) !Value {
        var record: Value = .{ .object = .empty };
        try record.object.put(self.allocator(), "id", .{ .integer = 1 });
        try self.writeRecord(.conversation, record);
        return json.clone(self.allocator(), record);
    }
    pub fn createConversation(self: *Transaction, parent: ?Value, ownerTask: ?u64) !Value {
        try self.ensureActive();
        self.tableWritten = true;
        const id = try self.session.storage.mintId();
        var record: Value = .{ .object = .empty };
        try record.object.put(self.allocator(), "id", .{ .integer = @intCast(id) });
        if (parent) |value| {
            const conversation = try json.asInteger(try backend.memory.field(value, "conversationId"));
            const at = try json.asInteger(try backend.memory.field(value, "at"));
            var visible = (try self.session.storage.readEntry(self.gpa, at, conversation)) orelse return error.InvalidForkPoint;
            defer visible.deinit();
            try self.stageForkCopies(conversation, id, visible.value);
            try record.object.put(self.allocator(), "parent", try json.clone(self.allocator(), value));
        }
        if (ownerTask) |taskId| {
            const task = (try self.currentRecord(taskId, .task)) orelse return error.UnknownConversationOwner;
            var owner: Value = .{ .object = .empty };
            try owner.object.put(self.allocator(), "taskId", .{ .integer = @intCast(taskId) });
            try owner.object.put(self.allocator(), "conversationId", try backend.memory.field(task, "conversationId"));
            try record.object.put(self.allocator(), "owner", owner);
        }
        try self.writeRecord(.conversation, record);
        return json.clone(self.allocator(), record);
    }
    fn stageForkCopies(self: *Transaction, parent: u64, child: u64, visible: Value) !void {
        const source_entry = try backend.memory.field(visible, "entry");
        const source_conversation = try json.asInteger(try backend.memory.field(source_entry, "conversationId"));
        const cutoff = try json.asInteger(try backend.memory.field(visible, "commitSeq"));
        const state = try self.session.storage.snapshot(self.gpa);
        defer state.destroy(self.gpa);
        var copied: std.ArrayList(Value) = .empty;
        defer copied.deinit(self.gpa);
        const selections = [_]struct { scope: u64, point: backend.memory.Point, policy: []const u8 }{ .{ .scope = source_conversation, .point = .{ .seq = cutoff }, .policy = "asOf" }, .{ .scope = parent, .point = .current, .policy = "current" } };
        for (selections) |selection| {
            var ids: std.ArrayList(u64) = .empty;
            defer ids.deinit(self.gpa);
            var iterator = state.documents.iterator();
            while (iterator.next()) |item| {
                const record = item.value_ptr.record;
                const scope = try backend.memory.field(record, "scope");
                if (!std.mem.eql(u8, try json.asString(try backend.memory.field(scope, "kind")), "conversation")) continue;
                if (try json.asInteger(try backend.memory.field(scope, "conversationId")) != selection.scope or !std.mem.eql(u8, try json.asString(try backend.memory.field(record, "fork")), selection.policy) or !try backend.memory.alive(record, selection.point)) continue;
                try ids.append(self.gpa, item.key_ptr.*);
            }
            std.mem.sort(u64, ids.items, {}, struct {
                fn less(_: void, a: u64, b: u64) bool {
                    return a < b;
                }
            }.less);
            for (ids.items) |source_id| {
                var record = try json.clone(self.allocator(), state.documents.get(source_id).?.record);
                _ = record.object.orderedRemove("createdAt");
                _ = record.object.orderedRemove("retiredAt");
                const id = try self.session.storage.mintId();
                try record.object.put(self.allocator(), "id", .{ .integer = @intCast(id) });
                var scope: Value = .{ .object = .empty };
                try scope.object.put(self.allocator(), "kind", .{ .string = "conversation" });
                try scope.object.put(self.allocator(), "conversationId", .{ .integer = @intCast(child) });
                try record.object.put(self.allocator(), "scope", scope);
                for (copied.items) |earlier| if (try backend.memory.sameAddress(record, earlier)) return error.ForkSelectsDuplicateDocumentAddress;
                try copied.append(self.gpa, record);
                var source: Value = .{ .object = .empty };
                try source.object.put(self.allocator(), "id", .{ .integer = @intCast(source_id) });
                try source.object.put(self.allocator(), "at", switch (selection.point) {
                    .current => .{ .string = "current" },
                    .seq => |seq| .{ .integer = @intCast(seq) },
                });
                var write: Value = .{ .object = .empty };
                try write.object.put(self.allocator(), "type", .{ .string = "document.copy" });
                try write.object.put(self.allocator(), "record", record);
                try write.object.put(self.allocator(), "source", source);
                try self.documentCommand(write);
            }
        }
    }
    pub fn appendEntry(self: *Transaction, conversation: u64, draft: Value) !Value {
        try self.ensureActive();
        self.tableWritten = true;
        if ((try self.currentRecord(conversation, .conversation)) == null) return error.UnknownConversation;
        const id = try self.session.storage.mintId();
        var record = try json.clone(self.allocator(), draft);
        if (record != .object) return error.InvalidEntryDraft;
        try record.object.put(self.allocator(), "id", .{ .integer = @intCast(id) });
        try record.object.put(self.allocator(), "conversationId", .{ .integer = @intCast(conversation) });
        if (json.get(record, "head")) |head| if (head == .string and std.mem.eql(u8, head.string, "self")) try record.object.put(self.allocator(), "head", .{ .integer = @intCast(id) });
        if (self.scope.taskId) |task| try record.object.put(self.allocator(), "byTaskId", .{ .integer = @intCast(task) }) else _ = record.object.orderedRemove("byTaskId");
        try self.writeRecord(.entry, record);
        return json.clone(self.allocator(), record);
    }
    pub fn documentCommand(self: *Transaction, write: Value) !void {
        try self.stage(write);
    }
    /// Prepared operations remain independent of storage checkpoint selection.
    /// Called by an owner facade before sealing and storage admission.
    pub fn documentPublicationOps(self: *Transaction, id: u64, operations: Value) !void {
        try self.ensureActive();
        const value = try json.clone(self.allocator(), operations);
        try self.preparedDocumentOps.put(self.allocator(), id, value);
    }
    /// Native definitions compute their initial checkpoint before calling this method.
    pub fn createTask(self: *Transaction, kind: []const u8, version: u64, input: Value, checkpoint: Value, options: TaskOptions) !u64 {
        const conversation_id = try self.taskConversation(options);
        const id = try self.session.storage.mintId();
        const a = self.allocator();
        var record = tasks.object(a);
        try record.object.put(a, "id", .{ .integer = @intCast(id) });
        try record.object.put(a, "conversationId", .{ .integer = @intCast(conversation_id) });
        try record.object.put(a, "kind", .{ .string = kind });
        try record.object.put(a, "version", .{ .integer = @intCast(version) });
        try record.object.put(a, "input", input);
        if (options.ownerTaskId) |owner| try record.object.put(a, "owner", .{ .integer = @intCast(owner) });
        try record.object.put(a, "background", .{ .bool = options.background });
        try record.object.put(a, "abortRequested", .{ .bool = false });
        try record.object.put(a, "state", try tasks.checkpointState(a, "pending", checkpoint));
        try tasks.validate(record);
        try self.createdTasks.append(a, id);
        try self.setTask(record);
        return id;
    }
    /// Admission checks precede invoking a definition's initial callback.
    pub fn taskConversation(self: *Transaction, options: TaskOptions) !u64 {
        try self.ensureActive();
        var conversation = options.conversationId orelse self.scope.conversationId;
        if (options.ownerTaskId) |owner| {
            const record = (try self.currentRecord(owner, .task)) orelse return error.UnknownTaskOwner;
            if (options.background) return error.BackgroundChildTask;
            const owner_conversation = try tasks.number(record, "conversationId");
            if (options.conversationId) |explicit| if (explicit != owner_conversation) return error.ChildTaskConversationMismatch;
            conversation = owner_conversation;
        }
        const conversation_id = conversation orelse return error.TaskConversationRequired;
        if ((try self.currentRecord(conversation_id, .conversation)) == null) return error.UnknownConversation;
        return conversation_id;
    }
    pub fn setTask(self: *Transaction, input_record: Value) !void {
        var record = input_record;
        try self.ensureActive();
        try tasks.validate(record);
        const id = try tasks.number(record, "id");
        const a = self.allocator();
        if (self.session.source_clock) |clock| {
            const state = try tasks.status(record);
            const prior = try self.currentRecord(id, .task);
            inline for (.{ "startedAt", "endedAt" }) |name| {
                const inherited = if (prior) |value| json.get(value, name) else null;
                const stamp = inherited orelse json.get(record, name);
                const needed = if (comptime std.mem.eql(u8, name, "startedAt")) state == .running else state == .terminal;
                if (stamp != null or needed) {
                    record = try json.clone(a, record);
                    try record.object.put(a, name, stamp orelse Value{ .integer = clock(self.session.source_clock_context) });
                }
            }
        }
        var index = self.writes.array.items.len;
        while (index > 0) {
            index -= 1;
            const write = self.writes.array.items[index];
            if (!std.mem.eql(u8, try tasks.text(write, "type"), "task")) continue;
            const prior = try tasks.field(write, "value");
            if (try tasks.number(prior, "id") != id) continue;
            if (try tasks.status(prior) == .terminal) return error.TerminalTaskCandidate;
            if (try tasks.number(prior, "conversationId") != try tasks.number(record, "conversationId")) return error.TaskConversationChanged;
            var replacement = tasks.object(a);
            try replacement.object.put(a, "type", .{ .string = "task" });
            try replacement.object.put(a, "value", try json.clone(a, record));
            self.writes.array.items[index] = replacement;
            self.tableWritten = true;
            return;
        }
        var write = tasks.object(a);
        try write.object.put(a, "type", .{ .string = "task" });
        try write.object.put(a, "value", record);
        try self.stage(write);
        self.tableWritten = true;
    }
    fn assembleTasks(self: *Transaction, predicted: *backend.memory.Memory) !void {
        for (self.writes.array.items) |write| {
            if (!std.mem.eql(u8, try tasks.text(write, "type"), "task")) continue;
            const record = try tasks.field(write, "value");
            const id = try tasks.number(record, "id");
            if (std.mem.indexOfScalar(u64, self.createdTasks.items, id) != null) continue;
            const prior = predicted.state.rows.get(id) orelse return error.UnknownTask;
            if (prior.table != .task) return error.UnknownTask;
            if (try tasks.status(prior.record) == .terminal) return error.TaskAlreadyTerminal;
            if (try tasks.number(prior.record, "conversationId") != try tasks.number(record, "conversationId")) return error.TaskConversationChanged;
        }
        var candidate = try predicted.prepare(self.writes, null);
        defer candidate.deinit();
        const state = candidate.state.?;
        for (self.writes.array.items) |write| {
            const tag = try tasks.text(write, "type");
            var owner: ?u64 = null;
            if (std.mem.eql(u8, tag, "conversation")) {
                if (json.get(try tasks.field(write, "value"), "owner")) |edge| owner = try tasks.number(edge, "taskId");
            } else if (std.mem.eql(u8, tag, "task")) {
                const record = try tasks.field(write, "value");
                if (std.mem.indexOfScalar(u64, self.createdTasks.items, try tasks.number(record, "id")) != null) {
                    if (json.get(record, "owner")) |edge| owner = try json.asInteger(edge);
                }
            }
            if (owner) |id| {
                const record = try (tasks.Graph{ .state = state }).task(id);
                const s = try tasks.status(record);
                if (s == .completing or s == .terminal) return error.TaskOwnerSettling;
                if (try tasks.flag(record, "abortRequested")) return error.TaskOwnerAbortMarked;
            }
        }
        // Retirement is part of the same durable commit, including newly created documents.
        var documents = state.documents.iterator();
        while (documents.next()) |item| {
            const record = item.value_ptr.record;
            if (json.get(record, "retiredAt") != null) continue;
            const scope = try tasks.field(record, "scope");
            if (!std.mem.eql(u8, try tasks.text(scope, "kind"), "task")) continue;
            const owner = try (tasks.Graph{ .state = state }).task(try tasks.number(scope, "taskId"));
            if (try tasks.status(owner) != .terminal) continue;
            var retirement = tasks.object(self.allocator());
            try retirement.object.put(self.allocator(), "type", .{ .string = "document.retire" });
            try retirement.object.put(self.allocator(), "id", .{ .integer = @intCast(item.key_ptr.*) });
            // active is already sealed; assembly is private and cannot expose the transaction.
            try self.writes.array.append(retirement);
        }
    }
};
fn buildPublication(gpa: std.mem.Allocator, state: *const backend.memory.State, seq: u64, writes: Value, prepared_ops: *const std.AutoHashMapUnmanaged(u64, Value)) !json.Owned {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const allocator = result.arena.allocator();
    var changes: std.array_list.Managed(Value) = .init(allocator);
    var published: std.AutoHashMap(u64, void) = .init(allocator);
    for (writes.array.items) |write| {
        const tag = try json.asString(try backend.memory.field(write, "type"));
        if (!std.mem.startsWith(u8, tag, "document.")) {
            try changes.append(try json.clone(allocator, write));
            continue;
        }
        const id = if (json.get(write, "record")) |record| try backend.memory.idOf(record) else try json.asInteger(try backend.memory.field(write, "id"));
        if (published.contains(id)) continue;
        try published.put(id, {});
        const doc = state.documents.get(id) orelse return error.MissingPublicationDocument;
        var change: Value = .{ .object = .empty };
        const copied = std.mem.eql(u8, tag, "document.copy");
        try change.object.put(allocator, "type", .{ .string = if (copied) "document.copy" else "document" });
        try change.object.put(allocator, "record", try json.clone(allocator, doc.record));
        const scope = try backend.memory.field(doc.record, "scope");
        const scope_kind = try json.asString(try backend.memory.field(scope, "kind"));
        if (std.mem.eql(u8, scope_kind, "conversation")) try change.object.put(allocator, "conversationId", try backend.memory.field(scope, "conversationId")) else if (std.mem.eql(u8, scope_kind, "task")) {
            const task_id = try json.asInteger(try backend.memory.field(scope, "taskId"));
            const task = state.rows.get(task_id) orelse return error.UnknownDocumentTask;
            try change.object.put(allocator, "conversationId", try backend.memory.field(task.record, "conversationId"));
        }
        if (copied) {
            try change.object.put(allocator, "source", try json.clone(allocator, try backend.memory.field(write, "source")));
        } else {
            var ops: Value = .{ .array = .init(allocator) };
            if (json.get(doc.record, "retiredAt") != null) {
                try change.object.put(allocator, "value", .null);
                var replacement: std.array_list.Managed(Value) = .init(allocator);
                try replacement.append(.{ .string = "r" });
                try replacement.append(.null);
                try ops.array.append(.{ .array = replacement });
            } else {
                const contents = (try backend.memory.materialize(allocator, state, id, .current)).?;
                try change.object.put(allocator, "version", .{ .integer = @intCast(contents.version) });
                try change.object.put(allocator, "value", contents.value);
                if (json.get(write, "content")) |content| if (std.mem.eql(u8, tag, "document.change")) {
                    if (std.mem.eql(u8, try json.asString(try backend.memory.field(content, "kind")), "delta")) ops = try json.clone(allocator, try backend.memory.field(content, "ops")) else {
                        var replacement: std.array_list.Managed(Value) = .init(allocator);
                        try replacement.append(.{ .string = "r" });
                        try replacement.append(contents.value);
                        try ops.array.append(.{ .array = replacement });
                    }
                };
                if (prepared_ops.get(id)) |original| ops = try json.clone(allocator, original);
            }
            try change.object.put(allocator, "ops", ops);
        }
        try changes.append(change);
    }
    _ = seq;
    result.value = .{ .array = changes };
    return result;
}

test "durable Session validates transaction lifetime read ordering callback rollback  and  publications" {
    const gpa = std.testing.allocator;
    var store = try backend.memory.Memory.init(gpa);
    defer store.deinit();
    var session = Session.init(gpa, std.testing.io, .{ .memory = &store });
    defer session.deinit();
    const Capture = struct {
        seq: u64 = 0,
        count: usize = 0,
        retained: ?*Transaction = null,
        fn receive(state: ?*anyopaque, event: *const Publication, _: types.Context) !void {
            const self: *@This() = @ptrCast(@alignCast(state.?));
            self.seq = event.seq;
            self.count += 1;
            try std.testing.expect(event.changes.array.items.len > 0);
        }
        fn root(_: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            return tx.createRootConversation();
        }
        fn failed(_: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            _ = try tx.appendEntry(1, .{ .object = .empty });
            return error.OriginalCallback;
        }
        fn ordering(_: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            _ = try tx.appendEntry(1, .{ .object = .empty });
            _ = try tx.readRecord(.conversation, 1);
            return .null;
        }
        fn append(state: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(state.?));
            _ = try tx.readRecord(.conversation, 1);
            self.retained = tx.retain();
            var draft: Value = .{ .object = .empty };
            try draft.object.put(tx.allocator(), "kind", .{ .string = "user" });
            try draft.object.put(tx.allocator(), "head", .{ .string = "self" });
            return tx.appendEntry(1, draft);
        }
    };
    var capture: Capture = .{};
    _ = try session.subscribe(Capture.receive, &capture);
    var root = try session.commit(Capture.root, null, .{}, .{});
    defer root.deinit();
    try std.testing.expectEqual(@as(?u64, 1), root.seq);
    try std.testing.expectEqual(@as(u64, 1), capture.seq);
    try std.testing.expectError(error.OriginalCallback, session.commit(Capture.failed, null, .{}, .{}));
    try std.testing.expect(store.state.rows.get(2) == null);
    try std.testing.expectEqual(@as(usize, 1), capture.count);
    try std.testing.expectError(error.ReadAfterWrite, session.commit(Capture.ordering, null, .{}, .{}));
    try std.testing.expect(store.state.rows.get(3) == null);
    var result = try session.commit(Capture.append, &capture, .{ .taskId = 99 }, .{});
    defer result.deinit();
    defer capture.retained.?.release();
    try std.testing.expectEqual(@as(?u64, 2), result.seq);
    const record = result.value.value;
    try std.testing.expectEqual(@as(u64, 4), try backend.memory.idOf(record));
    try std.testing.expectEqual(@as(u64, 4), try json.asInteger(try backend.memory.field(record, "head")));
    try std.testing.expectEqual(@as(u64, 99), try json.asInteger(try backend.memory.field(record, "byTaskId")));
    try std.testing.expectError(error.TransactionClosed, capture.retained.?.appendEntry(1, .{ .object = .empty }));
    try std.testing.expectEqual(@as(usize, 2), capture.count);
}

test "durable Session stages document publication before admission  and  runs over real SQLite" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "session.sqlite" });
    defer gpa.free(path);
    var store = try backend.sqlite.Sqlite.open(gpa, io, path, .{});
    defer store.deinit();
    var session = Session.init(gpa, io, .{ .sqlite = store });
    defer session.deinit();
    const Handler = struct {
        fn execute(_: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            _ = try tx.createRootConversation();
            var input = try json.Owned.parse(tx.gpa, "{\"type\":\"document.create\",\"record\":{\"id\":2,\"kind\":\"state\",\"scope\":{\"kind\":\"conversation\",\"conversationId\":1},\"history\":\"rewindable\",\"fork\":\"asOf\"},\"content\":{\"kind\":\"base\",\"version\":1,\"value\":{\"n\":1}}}");
            defer input.deinit();
            try tx.documentCommand(input.value);
            return .{ .string = "committed" };
        }
        fn receive(_: ?*anyopaque, event: *const Publication, _: types.Context) !void {
            try std.testing.expectEqual(@as(u64, 1), event.seq);
            try std.testing.expectEqual(@as(usize, 2), event.changes.array.items.len);
            const document = event.changes.array.items[1];
            try std.testing.expectEqualStrings("document", try json.asString(try backend.memory.field(document, "type")));
            try std.testing.expectEqual(@as(u64, 1), try json.asInteger(try backend.memory.field(try backend.memory.field(document, "record"), "createdAt")));
        }
    };
    _ = try session.subscribe(Handler.receive, null);
    var result = try session.commit(Handler.execute, null, .{}, .{});
    defer result.deinit();
    try std.testing.expectEqualStrings("committed", result.value.value.string);
    var document = (try store.readDocument(gpa, 2, .current)).?;
    defer document.deinit();
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(try backend.memory.field(try backend.memory.field(document.value, "value"), "n")));
}

test "durable Session admission allocates before publish and survives callback failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(gpa: std.mem.Allocator) !void {
            var store = try backend.memory.Memory.init(gpa);
            defer store.deinit();
            var session = Session.init(gpa, std.testing.io, .{ .memory = &store });
            defer session.deinit();
            const Handler = struct {
                fn create(_: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
                    return tx.createRootConversation();
                }
                fn reentrant(state: ?*anyopaque, _: *Transaction, _: types.Context) !Value {
                    const current: *Session = @ptrCast(@alignCast(state.?));
                    try std.testing.expectError(error.ReentrantSessionCommit, current.commit(create, null, .{}, .{}));
                    return error.OriginalSessionCallback;
                }
            };
            var result = session.commit(Handler.create, null, .{}, .{}) catch |err| {
                try std.testing.expect(store.state.rows.count() == 0);
                try std.testing.expectEqual(@as(u64, 1), store.state.nextSeq);
                return err;
            };
            defer result.deinit();
            if (session.commit(Handler.reentrant, &session, .{}, .{})) |unexpected| {
                var owned = unexpected;
                owned.deinit();
                return error.ExpectedCallbackFailure;
            } else |err| {
                if (err == error.OutOfMemory) return err;
                try std.testing.expectEqual(error.OriginalSessionCallback, err);
            }
            try std.testing.expect(session.poison == null);
        }
    }.run, .{});
}

test "durable Session committed records and publications match actual b7df callback execution" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/session_harness_b7df.json"));
    defer fixture.deinit();
    const expected = try json.required(fixture.value, "session");
    var store = try backend.memory.Memory.init(gpa);
    defer store.deinit();
    var session = Session.init(gpa, std.testing.io, .{ .memory = &store });
    defer session.deinit();
    const Handler = struct {
        allocator: std.mem.Allocator,
        events: std.array_list.Managed(Value),
        retained: ?*Transaction = null,
        fn receive(state: ?*anyopaque, event: *const Publication, _: types.Context) !void {
            const self: *@This() = @ptrCast(@alignCast(state.?));
            var value: Value = .{ .object = .empty };
            try value.object.put(self.allocator, "seq", .{ .integer = @intCast(event.seq) });
            try value.object.put(self.allocator, "changes", try json.clone(self.allocator, event.changes));
            try self.events.append(value);
        }
        fn root(_: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            return tx.createRootConversation();
        }
        fn fail(_: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            var draft: Value = .{ .object = .empty };
            try draft.object.put(tx.allocator(), "kind", .{ .string = "discarded" });
            _ = try tx.appendEntry(1, draft);
            return error.OriginalCallback;
        }
        fn readAfter(_: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            var draft: Value = .{ .object = .empty };
            try draft.object.put(tx.allocator(), "kind", .{ .string = "discarded" });
            _ = try tx.appendEntry(1, draft);
            _ = try tx.readRecord(.conversation, 1);
            return .null;
        }
        fn append(state: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(state.?));
            self.retained = tx.retain();
            _ = try tx.readRecord(.conversation, 1);
            const draft = try json.parseLeaky(tx.allocator(), "{\"kind\":\"user\",\"head\":\"self\",\"data\":{\"v\":1}}");
            return tx.appendEntry(1, draft);
        }
    };
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var handler: Handler = .{ .allocator = arena.allocator(), .events = .init(arena.allocator()) };
    _ = try session.subscribe(Handler.receive, &handler);
    var root = try session.commit(Handler.root, null, .{}, .{});
    defer root.deinit();
    try std.testing.expect(json.equal(try json.required(expected, "root"), root.value.value));
    try std.testing.expectError(error.OriginalCallback, session.commit(Handler.fail, null, .{}, .{}));
    try std.testing.expectError(error.ReadAfterWrite, session.commit(Handler.readAfter, null, .{}, .{}));
    var entry = try session.commit(Handler.append, &handler, .{}, .{});
    defer entry.deinit();
    defer handler.retained.?.release();
    try std.testing.expect(json.equal(try json.required(expected, "entry"), entry.value.value));
    try std.testing.expectError(error.TransactionClosed, handler.retained.?.readRecord(.conversation, 1));
    try std.testing.expect(json.equal(try json.required(expected, "publications"), .{ .array = handler.events }));
}

test "durable Session fork selects definition free asOf current and initial policies like b7df" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/fork_b7df.json"));
    defer fixture.deinit();
    var store = try backend.memory.Memory.init(gpa);
    defer store.deinit();
    for ([_][]const u8{ "writes", "initial", "changes" }) |name| _ = try store.commit(try json.required(fixture.value, name));
    var session = Session.init(gpa, std.testing.io, .{ .memory = &store });
    defer session.deinit();
    const Handler = struct {
        fn fork(_: ?*anyopaque, tx: *Transaction, _: types.Context) !Value {
            var parent: Value = .{ .object = .empty };
            try parent.object.put(tx.allocator(), "conversationId", .{ .integer = 1 });
            try parent.object.put(tx.allocator(), "at", .{ .integer = 2 });
            return tx.createConversation(parent, null);
        }
    };
    var child = try session.commit(Handler.fork, null, .{}, .{});
    defer child.deinit();
    try std.testing.expect(json.equal(try json.required(fixture.value, "child"), child.value.value));
    var scope: Value = .{ .object = .empty };
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    try scope.object.put(arena.allocator(), "kind", .{ .string = "conversation" });
    try scope.object.put(arena.allocator(), "conversationId", try json.required(child.value.value, "id"));
    var filters: Value = .{ .object = .empty };
    try filters.object.put(arena.allocator(), "scope", scope);
    var docs = try backend.query.scan(gpa, &store, .{ .table = .document, .filters = filters });
    defer docs.deinit();
    try std.testing.expect(json.equal(try json.required(fixture.value, "docs"), docs.value));
    const expected = (try json.required(fixture.value, "values")).array.items;
    for ((try json.required(docs.value, "items")).array.items, expected) |record, value| {
        var actual = (try store.readDocument(gpa, try backend.memory.idOf(record), .current)).?;
        defer actual.deinit();
        try std.testing.expect(json.equal(value, actual.value));
    }
}
