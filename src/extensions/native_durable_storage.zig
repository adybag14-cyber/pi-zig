//! Actual guest Storage methods execute on the VM owner. Native workers transfer
//! only detached JSON through a private broker; no user-visible routing token exists.
const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const backend = @import("../durable/backend/root.zig");
const broker_mod = @import("native_durable_broker.zig");
const json = backend.json;
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Op = enum { mintId, commit, conversation, task, submission, entry, document, findDocument, findLatestHeadMarker, submissionByRequest, scanConversations, scanTasks, scanSubmissions, scanEntries, scanDocuments };
pub const Adapter = struct {
    engine: *Engine,
    owner: std.Thread.Id,
    raw: c.JSValue,
    session: ?*durable.State = null,
    session_value: c.JSValue = undefined,
    owner_context: ?c.JSValue = null,
    background_context: c.JSValue,
    broker: broker_mod.Broker,
    mirror: backend.memory.Memory,
    mutex: std.Io.Mutex = .init,
    pub fn create(engine: *Engine, raw: c.JSValue) !*Adapter {
        const io = engine.native_io orelse return error.DurableIOUnavailable;
        const self = try engine.gpa.create(Adapter);
        errdefer engine.gpa.destroy(self);
        const context_exports = engine.native_module_values.get("@earendil-works/chord/context") orelse return error.DurableContextUnavailable;
        const background = try sdk.get(engine, context_exports, "BACKGROUND_CONTEXT");
        errdefer engine.freeValue(background);
        const mirror = try backend.memory.Memory.init(engine.gpa);
        self.* = .{ .engine = engine, .owner = std.Thread.getCurrentId(), .raw = c.JS_DupValue(engine.context, raw), .background_context = background, .broker = broker_mod.Broker.init(engine.gpa, io, 1, .{}), .mirror = mirror };
        errdefer {
            self.mirror.deinit();
            self.broker.deinit();
            engine.freeValue(self.raw);
        }
        try (try hub(engine)).adapters.append(engine.gpa, self);
        return self;
    }
    pub fn destroy(self: *Adapter) void {
        const engine = self.engine;
        const owner_hub: *Hub = @ptrCast(@alignCast(engine.native_durable_storage_context.?));
        for (owner_hub.adapters.items, 0..) |item, index| if (item == self) {
            _ = owner_hub.adapters.orderedRemove(index);
            break;
        };
        self.broker.deinit();
        self.mirror.deinit();
        c.JS_FreeValueRT(engine.runtime, self.raw);
        c.JS_FreeValueRT(engine.runtime, self.background_context);
        engine.gpa.destroy(self);
    }
    pub fn mark(self: *Adapter, runtime: ?*c.JSRuntime, marker: ?*const c.JS_MarkFunc) void {
        c.JS_MarkValue(runtime, self.raw, marker);
        c.JS_MarkValue(runtime, self.background_context, marker);
        // owner_context borrows the active VM argument/callback capture.
        // It owns no reference and must not report another GC edge.
    }
    pub fn capability(self: *Adapter) backend.Backend {
        return .{ .custom = .{ .context = self, .vtable = &vtable, .callbacks_on_owner = true } };
    }
    pub fn setBackgroundContext(self: *Adapter, context: c.JSValue) void {
        const copied = c.JS_DupValue(self.engine.context, context);
        self.engine.freeValue(self.background_context);
        self.background_context = copied;
    }
    pub fn loadSchedulerRecords(self: *Adapter, queued: bool) !void {
        var input = try json.Owned.empty(self.engine.gpa);
        defer input.deinit();
        const a = input.arena.allocator();
        const statuses: []const []const u8 = if (queued) &[_][]const u8{"queued"} else &[_][]const u8{ "pending", "running", "waiting", "completing" };
        for (statuses) |status| {
            input.value = .{ .object = .empty };
            try input.value.object.put(a, "status", .{ .string = status });
            var cursor: ?json.Owned = null;
            defer if (cursor) |*value| value.deinit();
            while (true) {
                var page = try sourceScan(self, self.engine.gpa, if (queued) .submission else .task, input.value, 256, if (cursor) |value| value.value else null);
                defer page.deinit();
                const next = json.get(page.value, "next") orelse break;
                var copied = try json.Owned.empty(self.engine.gpa);
                errdefer copied.deinit();
                copied.value = try json.clone(copied.arena.allocator(), next);
                if (cursor) |*value| value.deinit();
                cursor = copied;
            }
        }
    }
    fn from(raw: ?*anyopaque) *Adapter {
        return @ptrCast(@alignCast(raw.?));
    }
    const vtable: backend.Custom.VTable = .{ .mintId = mintId, .commitAt = commitAt, .snapshot = snapshot, .readRecord = readRecord, .readTableRecord = readTableRecord, .readEntry = readEntry, .readDocument = readDocument, .scan = scan, .findDocument = findDocument, .sourceScan = sourceScan, .latestHeadMarker = latestHeadMarker, .submissionByRequest = submissionByRequest };
    fn request(self: *Adapter, gpa: std.mem.Allocator, op: Op, args: []const json.Value) !json.Owned {
        var payload = try json.Owned.empty(gpa);
        defer payload.deinit();
        const a = payload.arena.allocator();
        var list: std.array_list.Managed(json.Value) = .init(a);
        for (args) |arg| try list.append(try json.clone(a, arg));
        payload.value = .{ .object = .empty };
        try payload.value.object.put(a, "op", .{ .string = @tagName(op) });
        try payload.value.object.put(a, "args", .{ .array = list });
        if (std.Thread.getCurrentId() == self.owner) return self.dispatch(payload.value, self.owner_context orelse self.background_context);
        return self.broker.call(gpa, .{ .owner_generation = 1, .task_id = 0, .invocation_generation = 0 }, payload.value, null);
    }
    fn brokerDispatch(raw: ?*anyopaque, _: broker_mod.Identity, payload: json.Value, _: *const std.atomic.Value(bool)) !json.Owned {
        const self = from(raw);
        return self.dispatch(payload, self.background_context);
    }
    fn dispatch(self: *Adapter, payload: json.Value, context: c.JSValue) !json.Owned {
        std.debug.assert(std.Thread.getCurrentId() == self.owner);
        const op = std.meta.stringToEnum(Op, try json.asString(try json.required(payload, "op"))) orelse return error.InvalidStorageOperation;
        const encoded = try json.required(payload, "args");
        const args = try self.engine.gpa.alloc(c.JSValue, encoded.array.items.len + 1);
        defer self.engine.gpa.free(args);
        var count: usize = 0;
        defer for (args[0..count]) |value| self.engine.freeValue(value);
        for (encoded.array.items) |value| {
            args[count] = if (value == .null) c.pi_js_undefined() else try durable.jsValue(self.engine, value);
            count += 1;
        }
        if (op != .mintId) {
            args[count] = if (op == .commit) try @import("native_durable_context.zig").withoutAbortSignal(self.engine, context) else c.JS_DupValue(self.engine.context, context);
            count += 1;
        }
        const returned = self.invoke(op, args[0..count]) catch |err| return self.storageError(op, context, err);
        defer self.engine.freeValue(returned);
        var result = try json.Owned.empty(self.engine.gpa);
        errdefer result.deinit();
        if (!c.JS_IsUndefined(returned)) {
            var converted = try durable.owned(self.engine, returned);
            defer converted.deinit();
            result.value = try json.clone(result.arena.allocator(), converted.value);
        }
        if (op == .conversation or op == .task or op == .submission) try self.adoptRecord(switch (op) {
            .conversation => .conversation,
            .task => .task,
            else => .submission,
        }, result.value, 0);
        if (op == .entry and result.value != .null) try self.adoptRecord(.entry, try json.required(result.value, "entry"), try json.asInteger(try json.required(result.value, "commitSeq")));
        if (op == .findDocument and result.value != .null) try self.adoptDocument(result.value, null);
        if (op == .document and result.value != .null and encoded.array.items[1] == .string) try self.adoptDocument(try json.required(result.value, "record"), result.value);
        if (op == .submissionByRequest and result.value != .null) try self.adoptRecord(.submission, result.value, 0);
        if (op == .findLatestHeadMarker and result.value != .null) try self.adoptRecord(.entry, result.value, 0);
        if (op == .scanConversations or op == .scanTasks or op == .scanSubmissions or op == .scanEntries or op == .scanDocuments) {
            const table: backend.memory.Table = switch (op) {
                .scanConversations => .conversation,
                .scanTasks => .task,
                .scanSubmissions => .submission,
                .scanEntries => .entry,
                .scanDocuments => .document,
                else => unreachable,
            };
            for ((try json.required(result.value, "items")).array.items) |record| if (table == .document) {
                try self.adoptDocument(record, null);
            } else {
                try self.adoptRecord(table, record, 0);
            };
        }
        return result;
    }
    fn invoke(self: *Adapter, op: Op, args: []const c.JSValue) !c.JSValue {
        const engine = self.engine;
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        const generation = engine.native_allocation_generation;
        const pending = sdk.invoke(engine, self.raw, @tagName(op), args) catch |err| return engine.nativeAllocationError(err, generation);
        defer engine.freeValue(pending);
        return engine.awaitValue(pending) catch |err| return engine.nativeAllocationError(err, generation);
    }
    fn storageError(self: *Adapter, op: Op, context: c.JSValue, err: anyerror) anyerror {
        if (err == error.OutOfMemory) return err;
        const engine = self.engine;
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        _ = durable.reject(engine, err);
        const reason = c.JS_GetException(engine.context);
        defer engine.freeValue(reason);
        const read = op != .mintId and op != .commit;
        const request_error = read and (@import("native_durable_errors.zig").isRequestError(engine, reason) catch false);
        var canceled = false;
        if (read) durable.checkCancellation(engine, context) catch {
            canceled = true;
        };
        if (!request_error and !canceled) if (self.session) |session| durable.captureStorageFailure(session, self.session_value, reason);
        _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch {};
        return if (request_error) error.OwnerStorageRequestError else if (canceled) error.OwnerStorageCanceledRead else error.JavaScriptException;
    }
    fn adoptRecord(self: *Adapter, table: backend.memory.Table, record: json.Value, seq: u64) !void {
        if (record == .null) return;
        self.mutex.lockUncancelable(self.broker.io);
        defer self.mutex.unlock(self.broker.io);
        const a = self.mirror.state.arena.allocator();
        try self.mirror.state.rows.put(try backend.memory.idOf(record), .{ .table = table, .record = try json.clone(a, record), .commitSeq = seq });
    }
    fn adoptDocument(self: *Adapter, record: json.Value, contents: ?json.Value) !void {
        self.mutex.lockUncancelable(self.broker.io);
        defer self.mutex.unlock(self.broker.io);
        const state = self.mirror.state;
        const a = state.arena.allocator();
        const id = try backend.memory.idOf(record);
        const seq = try json.asInteger(try json.required(record, "createdAt"));
        var document: backend.memory.Document = .{ .record = try json.clone(a, record), .revisions = .init(a) };
        if (contents) |stored| {
            var base: json.Value = .{ .object = .empty };
            try base.object.put(a, "kind", .{ .string = "base" });
            try base.object.put(a, "version", try json.clone(a, try json.required(stored, "version")));
            try base.object.put(a, "value", try json.clone(a, try json.required(stored, "value")));
            try document.revisions.append(.{ .seq = @max(seq, state.nextSeq - 1), .content = base });
        } else if (state.documents.get(id)) |prior| document.revisions = prior.revisions;
        try state.documents.put(id, document);
        try state.rows.put(id, .{ .table = .document, .record = document.record, .commitSeq = seq });
        state.nextSeq = @max(state.nextSeq, seq + 1);
    }
    fn mintId(raw: ?*anyopaque) !u64 {
        const self = from(raw);
        var value = try self.request(std.heap.page_allocator, .mintId, &.{});
        defer value.deinit();
        return json.asInteger(value.value);
    }
    fn commitAt(raw: ?*anyopaque, writes: json.Value, hint: ?u64) !u64 {
        _ = hint;
        const self = from(raw);
        // Prepare all native adoption state before allowing the guest commit.
        self.mutex.lockUncancelable(self.broker.io);
        var prepared = self.mirror.prepare(writes, null) catch |err| {
            self.mutex.unlock(self.broker.io);
            return err;
        };
        self.mutex.unlock(self.broker.io);
        defer prepared.deinit();
        var value = try self.request(std.heap.page_allocator, .commit, &.{writes});
        defer value.deinit();
        const seq = try json.asInteger(value.value);
        self.mutex.lockUncancelable(self.broker.io);
        defer self.mutex.unlock(self.broker.io);
        resequence(prepared.state.?, prepared.seq, seq);
        prepared.seq = seq;
        _ = try prepared.apply();
        return seq;
    }
    fn snapshot(raw: ?*anyopaque, gpa: std.mem.Allocator) !*backend.memory.State {
        const self = from(raw);
        self.mutex.lockUncancelable(self.broker.io);
        defer self.mutex.unlock(self.broker.io);
        return self.mirror.state.duplicate(gpa);
    }
    fn readRecord(raw: ?*anyopaque, gpa: std.mem.Allocator, id: u64) !?json.Owned {
        const self = from(raw);
        self.mutex.lockUncancelable(self.broker.io);
        const table = if (self.mirror.state.rows.get(id)) |row| row.table else null;
        self.mutex.unlock(self.broker.io);
        return if (table) |known| readTableRecord(raw, gpa, known, id) else error.StorageRecordKindUnavailable;
    }
    fn optional(value: json.Owned) ?json.Owned {
        var result = value;
        if (result.value == .null) {
            result.deinit();
            return null;
        }
        return result;
    }
    fn readTableRecord(raw: ?*anyopaque, gpa: std.mem.Allocator, table: backend.memory.Table, id: u64) !?json.Owned {
        if (table == .entry or table == .document) {
            var record = (if (table == .entry) try readEntry(raw, gpa, id, null) else try readDocument(raw, gpa, id, .current)) orelse return null;
            defer record.deinit();
            var value = try json.Owned.empty(gpa);
            errdefer value.deinit();
            value.value = try json.clone(value.arena.allocator(), try json.required(record.value, if (table == .entry) "entry" else "record"));
            return value;
        }
        const op: Op = switch (table) {
            .conversation => .conversation,
            .task => .task,
            .submission => .submission,
            .entry, .document => unreachable,
        };
        return optional(try from(raw).request(gpa, op, &.{.{ .integer = @intCast(id) }}));
    }
    fn readEntry(raw: ?*anyopaque, gpa: std.mem.Allocator, id: u64, conversation: ?u64) !?json.Owned {
        const self = from(raw);
        return optional(if (conversation) |owner| try self.request(gpa, .entry, &.{ .{ .integer = @intCast(owner) }, .{ .integer = @intCast(id) } }) else try self.request(gpa, .entry, &.{.{ .integer = @intCast(id) }}));
    }
    fn readDocument(raw: ?*anyopaque, gpa: std.mem.Allocator, id: u64, at: backend.memory.Point) !?json.Owned {
        return optional(try from(raw).request(gpa, .document, &.{ .{ .integer = @intCast(id) }, switch (at) {
            .current => .{ .string = "current" },
            .seq => |seq| .{ .integer = @intCast(seq) },
        } }));
    }
    fn findDocument(raw: ?*anyopaque, gpa: std.mem.Allocator, address: json.Value, at: backend.memory.Point) !?json.Owned {
        return optional(try from(raw).request(gpa, .findDocument, &.{ address, switch (at) {
            .current => .{ .string = "current" },
            .seq => |seq| .{ .integer = @intCast(seq) },
        } }));
    }
    fn sourceScan(raw: ?*anyopaque, gpa: std.mem.Allocator, table: backend.memory.Table, filters: json.Value, limit: u64, cursor: ?json.Value) !json.Owned {
        const op: Op = switch (table) {
            .conversation => .scanConversations,
            .task => .scanTasks,
            .submission => .scanSubmissions,
            .entry => .scanEntries,
            .document => .scanDocuments,
        };
        return from(raw).request(gpa, op, &.{ filters, .{ .integer = @intCast(limit) }, cursor orelse .null });
    }
    fn latestHeadMarker(raw: ?*anyopaque, gpa: std.mem.Allocator, conversation: u64, before: ?u64) !?json.Owned {
        return optional(try from(raw).request(gpa, .findLatestHeadMarker, &.{ .{ .integer = @intCast(conversation) }, if (before) |id| .{ .integer = @intCast(id) } else .null }));
    }
    fn submissionByRequest(raw: ?*anyopaque, gpa: std.mem.Allocator, conversation: u64, request_id: []const u8) !?json.Owned {
        return optional(try from(raw).request(gpa, .submissionByRequest, &.{ .{ .integer = @intCast(conversation) }, .{ .string = request_id } }));
    }
    fn scan(raw: ?*anyopaque, gpa: std.mem.Allocator, query: backend.query.Query) !json.Owned {
        var payload = try json.Owned.empty(gpa);
        defer payload.deinit();
        const a = payload.arena.allocator();
        payload.value = try json.clone(a, query.filters);
        if (query.conversationId) |id| try payload.value.object.put(a, "conversationId", .{ .integer = @intCast(id) });
        if (query.minEntryId) |id| try payload.value.object.put(a, "minEntryId", .{ .integer = @intCast(id) });
        if (query.maxEntryId) |id| try payload.value.object.put(a, "maxEntryId", .{ .integer = @intCast(id) });
        var cursor: json.Value = .null;
        if (query.after) |id| {
            cursor = .{ .object = .empty };
            try cursor.object.put(a, "after", .{ .integer = @intCast(id) });
        }
        const op: Op = switch (query.table) {
            .conversation => .scanConversations,
            .task => .scanTasks,
            .submission => .scanSubmissions,
            .entry => .scanEntries,
            .document => .scanDocuments,
        };
        return from(raw).request(gpa, op, &.{ payload.value, .{ .integer = @intCast(query.limit) }, cursor });
    }
};
fn resequence(state: *backend.memory.State, predicted: u64, actual: u64) void {
    state.nextSeq = actual + 1;
    var rows = state.rows.valueIterator();
    while (rows.next()) |row| if (row.commitSeq == predicted) {
        row.commitSeq = actual;
    };
    var docs = state.documents.valueIterator();
    while (docs.next()) |doc| {
        for ([_][]const u8{ "createdAt", "retiredAt" }) |name| if (doc.record.object.getPtr(name)) |value| if (value.* == .integer and value.integer == predicted) {
            value.* = .{ .integer = @intCast(actual) };
        };
        for (doc.revisions.items) |*revision| if (revision.seq == predicted) {
            revision.seq = actual;
        };
    }
}
const Hub = struct {
    adapters: std.ArrayList(*Adapter) = .empty,
    commits: std.ArrayList(PendingCommit) = .empty,
    first_close: ?*Drain = null,
    last_close: ?*Drain = null,
    fn pump(engine: *Engine) !bool {
        const self: *Hub = @ptrCast(@alignCast(engine.native_durable_storage_context.?));
        var worked = false;
        var index: usize = 0;
        while (index < self.adapters.items.len) : (index += 1) if (try self.adapters.items[index].broker.drain(Adapter.brokerDispatch, self.adapters.items[index])) {
            worked = true;
        };
        index = 0;
        while (index < self.commits.items.len) {
            const native = try durable.state(engine, self.commits.items[index].captures[0]);
            if (native.session.?.ownerThread.load(.acquire) != 0) {
                index += 1;
                continue;
            }
            const request = self.commits.orderedRemove(index);
            defer request.release(engine);
            const value = if (request.read) durable.retryQueuedRead(engine, &request.captures) else durable.retryQueuedCommit(engine, &request.captures);
            defer engine.freeValue(value);
            const rejected = c.JS_IsException(value);
            const returned = if (rejected) c.JS_GetException(engine.context) else c.JS_DupValue(engine.context, value);
            defer engine.freeValue(returned);
            var arguments = [_]c.JSValue{returned};
            const ignored = try engine.checked(c.JS_Call(engine.context, if (rejected) request.reject else request.resolve, c.pi_js_undefined(), 1, &arguments));
            engine.freeValue(ignored);
            worked = true;
        }
        while (true) {
            var previous: ?*Drain = null;
            var current = self.first_close;
            while (current) |slot| {
                if (slot.owner.session.?.storage.underway.load(.acquire) == 0) break;
                previous = slot;
                current = slot.next;
            }
            const request = current orelse break;
            if (previous) |slot| slot.next = request.next else self.first_close = request.next;
            if (self.last_close == request) self.last_close = previous;
            request.next = null;
            request.active = false;
            const retained = request.session;
            request.session = c.pi_js_undefined();
            defer engine.freeValue(retained);
            const value = durable.finishPendingBackendClose(request.owner, retained, request.context);
            defer engine.freeValue(value);
            const rejected = c.JS_IsException(value);
            const returned = if (rejected) c.JS_GetException(engine.context) else c.JS_DupValue(engine.context, value);
            defer engine.freeValue(returned);
            var args = [_]c.JSValue{returned};
            const ignored = try engine.checked(c.JS_Call(engine.context, if (rejected) request.reject else request.resolve, c.pi_js_undefined(), 1, &args));
            engine.freeValue(ignored);
            worked = true;
        }
        return worked;
    }
    fn close(engine: *Engine) void {
        const self: *Hub = @ptrCast(@alignCast(engine.native_durable_storage_context.?));
        for (self.adapters.items) |adapter| adapter.broker.close();
        for (self.commits.items) |request| request.release(engine);
        self.commits.clearRetainingCapacity();
        while (self.first_close) |slot| {
            self.first_close = slot.next;
            slot.next = null;
            slot.active = false;
            const retained = slot.session;
            slot.session = c.pi_js_undefined();
            engine.freeValue(retained);
        }
        self.last_close = null;
    }
};
fn hub(engine: *Engine) !*Hub {
    if (engine.native_durable_storage_context) |raw| return @ptrCast(@alignCast(raw));
    const self = try engine.gpa.create(Hub);
    self.* = .{};
    engine.native_durable_storage_context = self;
    engine.native_durable_storage_pump = Hub.pump;
    engine.native_durable_storage_close = Hub.close;
    return self;
}
pub fn deinit(engine: *Engine) void {
    if (engine.native_durable_storage_context) |raw| {
        const self: *Hub = @ptrCast(@alignCast(raw));
        std.debug.assert(self.adapters.items.len == 0);
        self.adapters.deinit(engine.gpa);
        self.commits.deinit(engine.gpa);
        std.debug.assert(self.first_close == null);
        engine.gpa.destroy(self);
    }
    engine.native_durable_storage_context = null;
    engine.native_durable_storage_pump = null;
    engine.native_durable_storage_close = null;
}
const PendingCommit = struct {
    read: bool = false,
    captures: [5]c.JSValue,
    resolve: c.JSValue,
    reject: c.JSValue,
    fn release(self: PendingCommit, engine: *Engine) void {
        for (self.captures) |value| engine.freeValue(value);
        engine.freeValue(self.resolve);
        engine.freeValue(self.reject);
    }
};
pub fn deferCommit(engine: *Engine, captures: []const c.JSValue) !c.JSValue {
    return admitPending(engine, captures, false);
}
pub fn deferRead(engine: *Engine, captures: []const c.JSValue) !c.JSValue {
    return admitPending(engine, captures, true);
}
pub const Drain = struct {
    owner: *durable.State,
    hub: *Hub,
    next: ?*Drain = null,
    active: bool = false,
    session: c.JSValue,
    context: c.JSValue,
    promise: c.JSValue,
    resolve: c.JSValue,
    reject: c.JSValue,
    pub fn destroy(self: *Drain, runtime: ?*c.JSRuntime) void {
        std.debug.assert(!self.active);
        c.JS_FreeValueRT(runtime, self.context);
        c.JS_FreeValueRT(runtime, self.promise);
        c.JS_FreeValueRT(runtime, self.resolve);
        c.JS_FreeValueRT(runtime, self.reject);
        self.owner.engine.gpa.destroy(self);
    }
    pub fn mark(self: *Drain, runtime: ?*c.JSRuntime, marker: ?*const c.JS_MarkFunc) void {
        inline for (.{ "context", "promise", "resolve", "reject" }) |name| c.JS_MarkValue(runtime, @field(self, name), marker);
        // session is the Hub's external root only while active, not a State edge.
    }
    pub fn start(self: *Drain, session: c.JSValue) c.JSValue {
        const engine = self.owner.engine;
        if (!self.active) {
            self.session = c.JS_DupValue(engine.context, session);
            self.active = true;
            if (self.hub.last_close) |last| last.next = self else self.hub.first_close = self;
            self.hub.last_close = self;
            self.owner.session.?.storage.closing.store(true, .release);
        }
        return c.JS_DupValue(engine.context, self.promise);
    }
};
pub fn prepareDrain(owner: *durable.State, context: c.JSValue) !void {
    const engine = owner.engine;
    if (owner.storage_drain) |slot| {
        const retained = c.JS_DupValue(engine.context, context);
        engine.freeValue(slot.context);
        slot.context = retained;
        return;
    }
    const owner_hub = try hub(engine);
    const slot = try engine.gpa.create(Drain);
    errdefer engine.gpa.destroy(slot);
    var functions: [2]c.JSValue = undefined;
    const pending = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    slot.* = .{ .owner = owner, .hub = owner_hub, .session = c.pi_js_undefined(), .context = c.JS_DupValue(engine.context, context), .promise = pending, .resolve = functions[0], .reject = functions[1] };
    owner.storage_drain = slot;
}
fn admitPending(engine: *Engine, captures: []const c.JSValue, read: bool) !c.JSValue {
    const owner_hub = try hub(engine);
    try owner_hub.commits.ensureUnusedCapacity(engine.gpa, 1);
    var functions: [2]c.JSValue = undefined;
    const pending = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    var request: PendingCommit = .{ .captures = undefined, .resolve = functions[0], .reject = functions[1], .read = read };
    for (captures, &request.captures) |input, *output| output.* = c.JS_DupValue(engine.context, input);
    owner_hub.commits.appendAssumeCapacity(request);
    return pending;
}
pub const ContextScope = struct {
    adapter: ?*Adapter,
    previous: ?c.JSValue,
    pub fn restore(self: ContextScope) void {
        if (self.adapter) |adapter| adapter.owner_context = self.previous;
    }
};
pub fn withContext(native: *durable.State, context: c.JSValue) ContextScope {
    const adapter = native.session_lease.?.adapter;
    const scope: ContextScope = .{ .adapter = adapter, .previous = if (adapter) |value| value.owner_context else null };
    if (adapter) |value| value.owner_context = context;
    return scope;
}

test "native durable VM actual Storage subclass duck getter failure and request error preserve Source causes and mandatory close" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const source = @embedFile("../durable/fixtures/durable-custom-storage-eba.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-eba-custom-storage"));
    defer engine.freeValue(fixture);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "customStorageFixture", c.JS_DupValue(engine.context, fixture));
    const output = engine.evalModule(
        \\import{createSession,MemoryStorage,SessionFailed,StorageRequestError}from'@earendil-works/pi-durable';
        \\import{BACKGROUND_CONTEXT as context}from'@earendil-works/chord/context';
        \\const cases=[];
        \\for(const representation of ['subclass','duck'])for(const operation of ['conversation','mintId','commit']){
        \\ const cause=Object.freeze({representation,operation}),calls=[];let storage;
        \\ if(representation==='subclass')storage=new(class extends MemoryStorage{[operation](){calls.push(operation);throw cause}async close(ctx){calls.push('close');return super.close(ctx)}})();
        \\ else{const backing=new MemoryStorage();storage={};for(const name of ['conversation','mintId','commit','close'])storage[name]=function(...args){if(this!==storage)throw Error('wrong receiver');calls.push(name);if(name===operation)throw cause;return backing[name](...args)}}
        \\ const session=createSession(storage);let first;try{await session.commit(tx=>operation==='conversation'?tx.conversation(1):operation==='mintId'?tx.createConversation({ownership:{kind:'ownerless'}}):tx.createRootConversation(),context)}catch(error){first=error}
        \\ let later;try{await session.commit(()=>true,context)}catch(error){later=error}const end=await session.closed;
        \\ cases.push({representation,operation,firstOriginal:first===cause,laterFailed:later instanceof SessionFailed,laterCause:later?.cause===cause,endReason:end.reason,endCause:end.error===cause,calls});
        \\}
        \\for(const representation of ['getter','request-read','close']){
        \\ const cause=representation==='request-read'?new StorageRequestError('invalid read'):Object.freeze({representation}),calls=[];const backing=new MemoryStorage(),storage={close:async()=>{calls.push('close');if(representation==='close')throw cause;return backing.close(context)},commit:(...args)=>backing.commit(...args),mintId:()=>backing.mintId()};
        \\ if(representation==='getter')Object.defineProperty(storage,'conversation',{get(){calls.push('get-conversation');throw cause}});else storage.conversation=()=>{calls.push('conversation');throw cause};
        \\ const session=createSession(storage),beforeCalls=[...calls];let first,later;
        \\ if(representation==='close'){try{await session.close(context)}catch(error){first=error}}else{try{await session.commit(tx=>tx.conversation(1),context)}catch(error){first=error}}
        \\ try{await session.commit(()=>true,context)}catch(error){later=error}if(representation==='request-read')await session.close(context);const end=await session.closed;
        \\ cases.push({representation,beforeCalls,firstOriginal:first===cause,laterFailed:later instanceof SessionFailed,laterCause:later?.cause===cause,endReason:end.reason,endCause:end.error===cause,calls});
        \\}
        \\if(JSON.stringify(cases)!==JSON.stringify(customStorageFixture.cases))throw Error(JSON.stringify({actual:cases,expected:customStorageFixture.cases}));
    , "actual-eba-custom-storage") catch |err| {
        std.debug.print("Actual Storage facade: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(output);
}

test "native durable VM actual asynchronous Storage calls retain original receiver context arity returned sequence and nested queue" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const source = @embedFile("../durable/fixtures/durable-custom-storage-source10.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-eba-storage-context"));
    defer engine.freeValue(fixture);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "customStorageFixture", c.JS_DupValue(engine.context, fixture));
    const output = engine.evalModule(
        \\import{createSession,MemoryStorage}from'@earendil-works/pi-durable';
        \\import{BACKGROUND_CONTEXT,createContextKey,withContextValue}from'@earendil-works/chord/context';
        \\const cases=[];
        \\for(const representation of ['subclass','duck']){
        \\ const calls=[],key=createContextKey('storage original context'),context=withContextValue(key,{original:true},BACKGROUND_CONTEXT);
        \\ const backing=new MemoryStorage();for(let i=0;i<34;i++)await backing.commit([],context);let storage;
        \\ if(representation==='duck'){
        \\  storage={};for(const name of ['conversation','mintId','commit','close'])storage[name]=async function(...args){if(this!==storage)throw Error('wrong receiver');calls.push({name,argc:args.length,context:name==='mintId'?true:name==='close'?args[0].value(key)===context.value(key):args.at(-1)===context});await Promise.resolve();return backing[name](...args)};
        \\ }else storage=new(class extends MemoryStorage{
        \\  async mintId(...args){calls.push({name:'mintId',argc:args.length,context:true});await Promise.resolve();return super.mintId(...args)}
        \\  async conversation(...args){calls.push({name:'conversation',argc:args.length,context:args.at(-1)===context});await Promise.resolve();return super.conversation(...args)}
        \\  async commit(...args){calls.push({name:'commit',argc:args.length,context:args.at(-1)===context});await Promise.resolve();return super.commit(...args)}
        \\  async close(...args){calls.push({name:'close',argc:args.length,context:args[0].value(key)===context.value(key)});await Promise.resolve();return super.close(...args)}
        \\ })();
        \\ const session=createSession(storage),before=[...calls],publications=[];session.subscribeCommits(publication=>publications.push(publication));
        \\ let nested;const root=await session.commit(tx=>{nested=session.commit(()=> 'nested',context);return tx.createRootConversation()},context);
        \\ const nestedValue=await nested,found=await session.commit(tx=>tx.conversation(root.id),context),child=await session.commit(tx=>tx.createConversation({ownership:{kind:'ownerless'}}),context);
        \\ await session.close(context);const end=await session.closed;
        \\ cases.push({representation,before,root,found,child,nestedValue,endReason:end.reason,calls,publications});
        \\}
        \\if(JSON.stringify(cases)!==JSON.stringify(customStorageFixture.cases))throw Error(JSON.stringify({actual:cases,expected:customStorageFixture.cases}));
    , "actual-eba-storage-context") catch |err| {
        std.debug.print("Actual Storage context: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(output);
}

test "native durable VM queued commit leaves the owner free while a real worker awaits a guest Storage read" {
    const engine = try Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const setup = try engine.evalModule(
        \\import{createSession}from'@earendil-works/pi-durable';
        \\globalThis.storageOrder=[];
        \\const storage={async conversation(id,ctx){storageOrder.push('storage');await Promise.resolve();return{id}},async close(){storageOrder.push('close')}};
        \\globalThis.storageWorkerSession=createSession(storage);
        \\globalThis.storageQueuedChange=()=>{storageOrder.push('queued');return'owner remained free'};
    , "actual-storage-worker-setup");
    engine.freeValue(setup);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const session = try sdk.get(engine, global, "storageWorkerSession");
    defer engine.freeValue(session);
    const native = try durable.state(engine, session);
    const adapter = native.session_lease.?.adapter.?;
    const Worker = struct {
        session: *@import("../durable/session.zig").Session,
        failure: ?anyerror = null,
        done: std.atomic.Value(bool) = .init(false),
        fn read(_: ?*anyopaque, tx: *@import("../durable/session.zig").Transaction, _: @import("../durable/types.zig").Context) !json.Value {
            return (try tx.readRecord(.conversation, 1)) orelse error.MissingWorkerConversation;
        }
        fn run(self: *@This()) void {
            defer self.done.store(true, .release);
            var result = self.session.commit(read, null, .{}, .{}) catch |err| {
                self.failure = err;
                return;
            };
            result.deinit();
        }
    };
    var worker: Worker = .{ .session = native.session.? };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    var joined = false;
    defer if (!joined) {
        adapter.broker.close();
        thread.join();
    };
    while (adapter.broker.pending() == 0 and !worker.done.load(.acquire)) try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    if (worker.failure) |failure| return failure;
    const change = try sdk.get(engine, global, "storageQueuedChange");
    defer engine.freeValue(change);
    const pending = try durable.sessionDispatch(native, session, .commit, &.{ change, c.pi_js_undefined() });
    defer engine.freeValue(pending);
    // Microtasks alone reach the queued commit while the native worker owns
    // the line. This must return without waiting for that worker's VM callback.
    _ = try engine.drainReadyJobs();
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    try std.testing.expectEqual(@as(usize, 1), adapter.broker.pending());
    const value = try engine.awaitValue(pending);
    defer engine.freeValue(value);
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("owner remained free", text);
    thread.join();
    joined = true;
    if (worker.failure) |failure| return failure;
    const checked = try engine.evalModule("if(storageOrder.join(',')!=='storage,queued')throw Error(JSON.stringify(storageOrder));await storageWorkerSession.close({});", "actual-storage-worker-finished");
    engine.freeValue(checked);
}

test "native durable VM actual Storage preseeded document requested reads canonical snapshots and authoritative metadata match Source" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const source = @embedFile("../durable/fixtures/durable-custom-storage-source11.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-eba-storage-document"));
    defer engine.freeValue(fixture);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "customStorageFixture", c.JS_DupValue(engine.context, fixture));
    const output = engine.evalModule(
        \\import{createSession,MemoryStorage,defineDoc}from'@earendil-works/pi-durable';
        \\import{BACKGROUND_CONTEXT as context}from'@earendil-works/chord/context';
        \\const calls=[],backing=new MemoryStorage();for(let i=0;i<34;i++)await backing.commit([],context);
        \\const id=await backing.mintId(),record={id,kind:'storage.preseed',scope:{kind:'session'}};
        \\await backing.commit([{type:'document.create',record,content:{kind:'base',version:1,value:{count:41}}}],context);
        \\const raw={};for(const name of ['mintId','commit','conversation','task','submission','entry','findDocument','document','scanDocuments','scanConversations','scanTasks','scanEntries','scanSubmissions','submissionByRequest','findLatestHeadMarker','close'])raw[name]=async function(...args){if(this!==raw)throw Error('wrong receiver');calls.push({name,args:args.slice(0,name==='mintId'?0:-1)});await Promise.resolve();return backing[name](...args)};
        \\let initial=0;const token=defineDoc({kind:'storage.preseed',scope:'session',version:1,initial:()=>{initial++;return{count:0}}});
        \\const session=createSession(raw),before=[...calls],publications=[];session.subscribeCommits(publication=>publications.push(publication));
        \\const first=await session.snapshot(token,context),again=await session.snapshot(token,context);
        \\await session.commit(async tx=>{const doc=await tx.doc(token);doc.count++},context);
        \\const after=await session.snapshot(token,context);await session.close(context);
        \\const result={source:'eba849739511223c51a62bbd7e3f1c00f99fb1d0',before,initial,first,again,after,sameFirst:first===again,sameAfter:first===after,calls,publications};
        \\if(JSON.stringify(result)!==JSON.stringify(customStorageFixture))throw Error(JSON.stringify({actual:result,expected:customStorageFixture}));
    , "actual-eba-storage-document") catch |err| {
        std.debug.print("Actual Storage document: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(output);
}

test "native durable VM actual Storage canceled reads fatal mint and commit request errors and secondary cleanup failure match Source" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const executed = engine.evalModule(@embedFile("../durable/fixtures/durable-custom-storage-source12-program.txt"), "actual-eba-storage-causes") catch |err| {
        std.debug.print("Actual Storage causes: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(executed);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const actual = try sdk.get(engine, global, "actualStorageCauseTrace");
    defer engine.freeValue(actual);
    var converted = try durable.owned(engine, actual);
    defer converted.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("../durable/fixtures/durable-custom-storage-source12.json"));
    defer expected.deinit();
    try std.testing.expect(json.equal(expected.value, converted.value));
}

test "native durable VM actual Storage Harness empty and seeded bootstrap request exact Source scans and document probes" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const source = @embedFile("../durable/fixtures/durable-custom-storage-source13.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-eba-storage-bootstrap"));
    defer engine.freeValue(fixture);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "customStorageFixture", c.JS_DupValue(engine.context, fixture));
    const output = engine.evalModule(
        \\import{Harness,MemoryStorage,createRegistry}from'@earendil-works/pi-durable';
        \\import{BACKGROUND_CONTEXT as context}from'@earendil-works/chord/context';
        \\const cases=[];
        \\for(const seeded of [false,true]){
        \\ const calls=[],backing=new MemoryStorage();if(seeded)await backing.commit([{type:'conversation',value:{id:1}},{type:'conversation',value:{id:5}}],context);
        \\ const raw={};for(const name of ['mintId','commit','conversation','task','submission','entry','findDocument','document','scanDocuments','scanConversations','scanTasks','scanEntries','scanSubmissions','submissionByRequest','findLatestHeadMarker','close'])raw[name]=async function(...args){if(this!==raw)throw Error('wrong receiver');calls.push({name,args:args.slice(0,name==='mintId'?0:-1)});await Promise.resolve();return backing[name](...args)};
        \\ const harness=await Harness.open(raw,{models:{},registry:createRegistry()},context),root=await harness.root(context);await harness.close(context);cases.push({seeded,rootId:root.id,calls});
        \\}
        \\const normalize=rows=>{const copied=JSON.parse(JSON.stringify(rows));for(const row of copied)for(const call of row.calls)if(call.name==='commit')for(const write of call.args[0])if(write.type==='document.create'&&write.record.kind==='pi.provider'){if(!/^[a-f0-9]{8}-[a-f0-9]{4}-7[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(write.content.value.sessionId))throw Error('invalid random provider session UUIDv7');write.content.value.sessionId='$UUID'}return copied};
        \\const actual=normalize(cases),expected=normalize(customStorageFixture.cases);if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));
    , "actual-eba-storage-bootstrap") catch |err| {
        std.debug.print("Actual Storage bootstrap: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(output);
}

test {
    _ = @import("native_durable_storage_lifetime_test.zig");
}
