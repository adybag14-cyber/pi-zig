//! Durable public VM objects over native numeric storage and transaction kernels.
const std = @import("std");
const engine_module = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const backend = @import("../durable/backend/root.zig");
const scans = @import("../durable/backend/source_scan.zig");
const session_module = @import("../durable/session.zig");
const context_module = @import("../durable/types.zig");
const filesystem_module = @import("../durable/filesystem.zig");
const json = backend.json;
const c = engine_module.c;
const Engine = engine_module.Engine;
pub const SessionLease = struct {
    gpa: std.mem.Allocator,
    value: session_module.Session,
    refs: std.atomic.Value(usize) = .init(1),
    pub fn retain(self: *SessionLease) *SessionLease {
        _ = self.refs.fetchAdd(1, .monotonic);
        return self;
    }
    pub fn release(self: *SessionLease) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) {
            self.value.deinit();
            self.gpa.destroy(self);
        }
    }
};
const Kind = enum { memory, jsonl, sqlite, sqlite_source, session, transaction };
pub const Method = enum(c_int) { mintId, commit, close, conversation, entry, task, submission, submissionByRequest, document, findDocument, findLatestHeadMarker, scanConversations, scanEntries, scanTasks, scanSubmissions, scanDocuments, createRootConversation, createConversation, forkConversation, appendEntry, subscribeCommits, subscribeClose, createTask, doc, snapshot, retireDoc, snapshotAsOf, unloadDocuments, watchDoc, documentState, latestHeadMarker, createSubmission, placeSubmission, settleSubmission };
pub const State = struct {
    engine: *Engine,
    kind: Kind,
    memory: backend.memory.Memory,
    session: ?*session_module.Session = null,
    session_lease: ?*SessionLease = null,
    owner_thread: std.Thread.Id = 0,
    foreign_publication: ?*const fn (?*anyopaque, *const session_module.Publication) anyerror!void = null,
    foreign_publication_context: ?*anyopaque = null,
    after_commit: ?*const fn (?*anyopaque) anyerror!void = null,
    transaction: ?*session_module.Transaction = null,
    parent: c.JSValue,
    tail: c.JSValue,
    closed_promise: ?c.JSValue = null,
    closed_resolve: ?c.JSValue = null,
    close_pending: ?c.JSValue = null,
    failure_reason: ?c.JSValue = null,
    closing: bool = false,
    sqlite: ?*backend.sqlite.Sqlite = null,
    sqlite_source: ?*backend.sqlite_source.Sqlite = null,
    jsonl: ?*backend.jsonl.Jsonl = null,
    filesystem: ?*filesystem_module.FileSystem = null,
    storage_closed: bool = false,
    commit_listeners: std.ArrayList(c.JSValue) = .empty,
    close_listeners: std.ArrayList(c.JSValue) = .empty,
    publication_context: ?c.JSValue = null,
    creation_owner: ?c.JSValue = null,
    creation_hook: ?*const fn (*Engine, c.JSValue, c.JSValue, json.Value) anyerror!void = null,
    finish_hook: ?*const fn (*Engine, c.JSValue, c.JSValue) anyerror!void = null,
    task_creator: ?*const fn (*Engine, c.JSValue, c.JSValue, []const c.JSValue) anyerror!c.JSValue = null,
    plans: std.ArrayList(json.Owned) = .empty,
    documents: ?*@import("native_durable_documents.zig").Drafts = null,
    document_cache: ?*@import("native_durable_documents.zig").Cache = null,
    fn storage(self: *State) !backend.Backend {
        if (self.storage_closed) return error.StorageClosed;
        return switch (self.kind) {
            .memory => .{ .memory = &self.memory },
            .jsonl => .{ .jsonl = self.jsonl.? },
            .sqlite => .{ .sqlite = self.sqlite.? },
            .sqlite_source => .{ .sqlite_source = self.sqlite_source.? },
            else => error.InvalidDurableStorage,
        };
    }
    fn closeStorage(self: *State) void {
        if (self.storage_closed) return;
        self.storage_closed = true;
        switch (self.kind) {
            .memory => self.memory.close(),
            .jsonl => self.jsonl.?.close(),
            .sqlite => {
                self.sqlite.?.deinit();
                self.sqlite = null;
            },
            .sqlite_source => {
                self.sqlite_source.?.deinit();
                self.sqlite_source = null;
            },
            else => {},
        }
    }
};
pub fn state(engine: *Engine, value: c.JSValue) !*State {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, value, engine.native_durable_class) orelse return error.InvalidDurableReceiver));
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_class) orelse return));
    switch (self.kind) {
        .memory => self.memory.deinit(),
        .sqlite => if (self.sqlite) |store| store.deinit(),
        .sqlite_source => if (self.sqlite_source) |store| store.deinit(),
        .jsonl => {
            self.jsonl.?.deinit();
            engine.gpa.destroy(self.jsonl.?);
            self.filesystem.?.deinit();
            engine.gpa.destroy(self.filesystem.?);
        },
        .session => {
            self.session_lease.?.release();
        },
        .transaction => self.transaction.?.release(),
    }
    c.JS_FreeValueRT(runtime, self.parent);
    c.JS_FreeValueRT(runtime, self.tail);
    if (self.closed_promise) |promise| c.JS_FreeValueRT(runtime, promise);
    if (self.closed_resolve) |resolve| c.JS_FreeValueRT(runtime, resolve);
    if (self.close_pending) |promise| c.JS_FreeValueRT(runtime, promise);
    if (self.failure_reason) |reason| c.JS_FreeValueRT(runtime, reason);
    if (self.creation_owner) |owner| c.JS_FreeValueRT(runtime, owner);
    if (self.documents) |documents| documents.deinit(runtime);
    if (self.document_cache) |cache| cache.deinit(runtime);
    for (self.plans.items) |*plan| plan.deinit();
    self.plans.deinit(engine.gpa);
    for (self.commit_listeners.items) |listener| c.JS_FreeValueRT(runtime, listener);
    for (self.close_listeners.items) |listener| c.JS_FreeValueRT(runtime, listener);
    self.commit_listeners.deinit(engine.gpa);
    self.close_listeners.deinit(engine.gpa);
    engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, input: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(input, engine.native_durable_class) orelse return));
    c.JS_MarkValue(runtime, self.parent, marker);
    c.JS_MarkValue(runtime, self.tail, marker);
    if (self.closed_promise) |promise| c.JS_MarkValue(runtime, promise, marker);
    if (self.closed_resolve) |resolve| c.JS_MarkValue(runtime, resolve, marker);
    if (self.close_pending) |promise| c.JS_MarkValue(runtime, promise, marker);
    if (self.failure_reason) |reason| c.JS_MarkValue(runtime, reason, marker);
    if (self.creation_owner) |owner| c.JS_MarkValue(runtime, owner, marker);
    if (self.documents) |documents| documents.mark(runtime, marker);
    if (self.document_cache) |cache| cache.mark(runtime, marker);
    for (self.commit_listeners.items) |listener| c.JS_MarkValue(runtime, listener, marker);
    for (self.close_listeners.items) |listener| c.JS_MarkValue(runtime, listener, marker);
}
pub fn owned(engine: *Engine, value: c.JSValue) !json.Owned {
    const encoded = try engine.stringify(value);
    defer engine.gpa.free(encoded);
    return json.Owned.parse(engine.gpa, encoded);
}
pub fn jsValue(engine: *Engine, source: json.Value) !c.JSValue {
    const encoded = try json.stringify(engine.gpa, source);
    defer engine.gpa.free(encoded);
    const terminated = try engine.gpa.dupeZ(u8, encoded);
    defer engine.gpa.free(terminated);
    return engine.checked(c.JS_ParseJSON(engine.context, terminated, encoded.len, "native-durable"));
}
fn result(engine: *Engine, output: ?json.Owned) !c.JSValue {
    var record = output orelse return c.pi_js_undefined();
    defer record.deinit();
    return jsValue(engine, record.value);
}
pub fn number(engine: *Engine, input: c.JSValue) !u64 {
    var output: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &output, input) < 0) return error.JavaScriptException;
    if (!std.math.isFinite(output) or output != @trunc(output) or output < 0 or output > backend.memory.max_integer) return error.InvalidDurableId;
    return @intFromFloat(output);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn point(engine: *Engine, input: c.JSValue) !backend.memory.Point {
    if (c.JS_IsUndefined(input)) return .current;
    if (c.JS_IsString(input)) {
        const text = try engine.toString(input);
        defer engine.gpa.free(text);
        if (std.mem.eql(u8, text, "current")) return .current;
    }
    return .{ .seq = try number(engine, input) };
}
pub fn reject(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowTypeError(engine.context, "Native durable: %s", @as([*:0]const u8, @errorName(err)));
}
pub fn rejectedPromise(engine: *Engine, err: anyerror) c.JSValue {
    _ = reject(engine, err);
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    var functions: [2]c.JSValue = undefined;
    const promise = c.JS_NewPromiseCapability(engine.context, &functions);
    if (c.JS_IsException(promise)) return promise;
    defer for (functions) |function| engine.freeValue(function);
    var args = [_]c.JSValue{reason};
    const ignored = c.JS_Call(engine.context, functions[1], c.pi_js_undefined(), 1, &args);
    if (c.JS_IsException(ignored)) {
        engine.freeValue(promise);
        return ignored;
    }
    engine.freeValue(ignored);
    return promise;
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = state(engine, receiver) catch |err| return rejectedPromise(engine, err);
    const operation: Method = @enumFromInt(magic);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    if (operation == .subscribeCommits or operation == .subscribeClose) return subscribe(self, receiver, operation, argument(args, 0)) catch |err| reject(engine, err);
    return dispatch(self, receiver, operation, args) catch |err| rejectedPromise(engine, err);
}
fn dispatch(self: *State, receiver: c.JSValue, operation: Method, args: []const c.JSValue) !c.JSValue {
    const engine = self.engine;
    if (self.kind == .session) return sessionDispatch(self, receiver, operation, args);
    if (self.kind == .transaction) return transactionDispatch(self, receiver, operation, args) catch |err| {
        if (err == error.ReadAfterWrite) {
            const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return err;
            const error_constructor = try sdk.get(engine, exports, "ReadAfterWrite");
            defer engine.freeValue(error_constructor);
            const name = try sdk.text(engine, @tagName(operation));
            defer engine.freeValue(name);
            var arguments = [_]c.JSValue{name};
            const exception = try engine.checked(c.JS_CallConstructor(engine.context, error_constructor, 1, &arguments));
            return engine.checked(c.JS_Throw(engine.context, exception));
        }
        if (err == error.TransactionClosed) return sdk.sourceError(engine, "Transaction has settled");
        return err;
    };
    if (operation == .close) {
        self.closeStorage();
        return sdk.promise(engine, c.pi_js_undefined());
    }
    const store = try self.storage();
    const output = switch (operation) {
        .mintId => try engine.checked(c.JS_NewInt64(engine.context, @intCast(try store.mintId()))),
        .close => blk: {
            self.closeStorage();
            break :blk c.pi_js_undefined();
        },
        .commit => blk: {
            var writes = try owned(engine, argument(args, 0));
            defer writes.deinit();
            const sequence = try store.commitAt(writes.value, null);
            break :blk try engine.checked(c.JS_NewInt64(engine.context, @intCast(sequence)));
        },
        .conversation, .task, .submission => blk: {
            const table: backend.memory.Table = if (operation == .conversation) .conversation else if (operation == .task) .task else .submission;
            const id = try number(engine, argument(args, 0));
            break :blk try result(engine, try store.readTableRecord(engine.gpa, table, id));
        },
        .entry => blk: {
            const contextual = args.len >= 3;
            break :blk try result(engine, try store.readEntry(engine.gpa, try number(engine, argument(args, if (contextual) 1 else 0)), if (contextual) try number(engine, args[0]) else null));
        },
        .document => try result(engine, try store.readDocument(engine.gpa, try number(engine, argument(args, 0)), try point(engine, argument(args, 1)))),
        .findDocument => blk: {
            var address = try owned(engine, argument(args, 0));
            defer address.deinit();
            var snapshot: backend.memory.Memory = .{ .gpa = engine.gpa, .state = try store.snapshot(engine.gpa) };
            defer snapshot.deinit();
            break :blk try result(engine, try backend.query.findDocument(engine.gpa, &snapshot, address.value, try point(engine, argument(args, 1))));
        },
        .findLatestHeadMarker => blk: {
            var snapshot: backend.memory.Memory = .{ .gpa = engine.gpa, .state = try store.snapshot(engine.gpa) };
            defer snapshot.deinit();
            break :blk try result(engine, try scans.latestHead(engine.gpa, &snapshot, try number(engine, argument(args, 0)), if (c.JS_IsUndefined(argument(args, 1))) null else try number(engine, args[1])));
        },
        .submissionByRequest => blk: {
            var snapshot: backend.memory.Memory = .{ .gpa = engine.gpa, .state = try store.snapshot(engine.gpa) };
            defer snapshot.deinit();
            const tuple = [_]json.Value{ .{ .integer = @intCast(try number(engine, argument(args, 0))) }, .{ .string = try engine.toString(argument(args, 1)) } };
            defer engine.gpa.free(tuple[1].string);
            const key = try backend.memory.requestKey(engine.gpa, tuple[0], tuple[1]);
            defer engine.gpa.free(key);
            var id: ?u64 = null;
            if (self.kind == .sqlite or self.kind == .sqlite_source) {
                // Source SQLite's nonunique request index selects the lowest ID.
                // Memory/JSONL instead maintain arrival order, including moves.
                var rows = snapshot.state.rows.iterator();
                while (rows.next()) |row| {
                    if (row.value_ptr.table != .submission) continue;
                    const record = row.value_ptr.record;
                    if (!json.equal(json.get(record, "conversationId") orelse .null, tuple[0]) or !json.equal(json.get(record, "requestId") orelse .null, tuple[1])) continue;
                    if (id == null or row.key_ptr.* < id.?) id = row.key_ptr.*;
                }
            } else id = snapshot.state.submissionRequests.get(key);
            break :blk try result(engine, if (id) |found| try store.readRecord(engine.gpa, found) else null);
        },
        .scanConversations, .scanEntries, .scanTasks, .scanSubmissions, .scanDocuments => blk: {
            var filters = try owned(engine, argument(args, 0));
            defer filters.deinit();
            var cursor: ?json.Owned = if (c.JS_IsUndefined(argument(args, 2))) null else try owned(engine, args[2]);
            defer if (cursor) |*continuation| continuation.deinit();
            const table: backend.memory.Table = switch (operation) {
                .scanConversations => .conversation,
                .scanEntries => .entry,
                .scanTasks => .task,
                .scanSubmissions => .submission,
                .scanDocuments => .document,
                else => unreachable,
            };
            var snapshot: backend.memory.Memory = .{ .gpa = engine.gpa, .state = try store.snapshot(engine.gpa) };
            defer snapshot.deinit();
            var page = try scans.scan(engine.gpa, &snapshot, table, filters.value, try number(engine, argument(args, 1)), if (cursor) |continuation| continuation.value else null);
            defer page.deinit();
            break :blk try jsValue(engine, page.value);
        },
        else => return error.InvalidDurableStorageMethod,
    };
    defer engine.freeValue(output);
    return sdk.promise(engine, output);
}
fn constructor(context: ?*c.JSContext, new_target: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return constructedMemory(engine, new_target) catch |err| reject(engine, err);
}
fn constructedMemory(engine: *Engine, new_target: c.JSValue) !c.JSValue {
    const object = try memoryObjectWithMethods(engine, false);
    errdefer engine.freeValue(object);
    const prototype = try sdk.get(engine, new_target, "prototype");
    defer engine.freeValue(prototype);
    if (c.JS_IsObject(prototype) and c.JS_SetPrototype(engine.context, object, prototype) < 0) return error.JavaScriptException;
    return object;
}
pub fn memoryObject(engine: *Engine) !c.JSValue {
    return memoryObjectWithMethods(engine, true);
}
fn memoryObjectWithMethods(engine: *Engine, own_methods: bool) !c.JSValue {
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_class));
    errdefer engine.freeValue(object);
    const self = try engine.gpa.create(State);
    errdefer engine.gpa.destroy(self);
    self.* = .{ .engine = engine, .kind = .memory, .memory = try backend.memory.Memory.init(engine.gpa), .parent = c.pi_js_undefined(), .tail = c.pi_js_undefined() };
    errdefer self.memory.deinit();
    if (own_methods) inline for (std.meta.fields(Method)[0..16]) |field| try sdk.put(engine, object, field.name, try engine.checked(c.pi_js_function_magic(engine.context, method, field.name, 1, @intCast(field.value))));
    _ = c.JS_SetOpaque(object, self);
    return object;
}
pub fn install(engine: *Engine) !void {
    try @import("native_durable_context.zig").install(engine);
    if (engine.native_durable_class == 0) _ = c.JS_NewClassID(engine.runtime, &engine.native_durable_class);
    const definition: c.JSClassDef = .{ .class_name = "Native durable object", .finalizer = finalizer, .gc_mark = mark, .call = null, .exotic = null };
    if (!c.JS_IsRegisteredClass(engine.runtime, engine.native_durable_class) and c.JS_NewClass(engine.runtime, engine.native_durable_class, &definition) < 0) return error.OutOfMemory;
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try @import("native_durable_errors.zig").install(engine, exports);
    const ctor = try engine.checked(c.JS_NewCFunction2(engine.context, constructor, "MemoryStorage", 0, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(ctor);
    const prototype = try sdk.object(engine);
    defer engine.freeValue(prototype);
    try sdk.put(engine, prototype, "constructor", c.JS_DupValue(engine.context, ctor));
    inline for (std.meta.fields(Method)[0..16]) |field| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, method, field.name, 1, @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    }
    try sdk.put(engine, ctor, "prototype", c.JS_DupValue(engine.context, prototype));
    try sdk.put(engine, exports, "MemoryStorage", c.JS_DupValue(engine.context, ctor));
    try sdk.put(engine, exports, "createSession", try engine.checked(c.JS_NewCFunction(engine.context, createSession, "createSession", 1)));
    try @import("native_durable_errors.zig").install(engine, exports);
    try @import("native_durable_harness.zig").install(engine, exports);
    try @import("native_durable_registry.zig").installHelpers(engine, exports);
    try @import("native_durable_agent.zig").install(engine, exports);
    try @import("native_durable_tasks.zig").defineTask(engine, exports);
    try @import("native_durable_entries.zig").install(engine, exports);
    try @import("native_durable_builtin_documents.zig").install(engine, exports);
    try @import("native_durable_compaction_builtin.zig").install(engine, exports);
    try @import("native_durable_documents.zig").install(engine, exports);
    try @import("native_durable_tool_builtin.zig").install(engine, exports);
    try @import("native_durable_generation_builtin.zig").install(engine, exports);
    const builtins = try sdk.array(engine);
    defer engine.freeValue(builtins);
    inline for (.{ "GenerationTask", "ToolTask", "CompactionTask" }) |name| try sdk.append(engine, builtins, try sdk.get(engine, exports, name));
    try @import("native_durable_registry.zig").install(engine, exports, builtins);
    if (!engine.native_module_names.contains("@earendil-works/pi-durable")) try engine.registerValueModule("@earendil-works/pi-durable", exports);
    inline for (.{ .{ "jsonl", "openNodeJsonlStorage", 0 }, .{ "sqlite", "openNodeSqliteStorage", 1 } }) |item| {
        const storage_exports = try sdk.object(engine);
        defer engine.freeValue(storage_exports);
        try sdk.put(engine, storage_exports, item[1], try engine.checked(c.pi_js_function_magic(engine.context, openStorage, item[1], 1, item[2])));
        const name = "@earendil-works/pi-durable/storage/" ++ item[0] ++ "/node";
        if (!engine.native_module_names.contains(name)) try engine.registerValueModule(name, storage_exports);
    }
}

fn openStorage(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, storage_kind: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const object = persistentObject(engine, storage_kind == 0, argv[0..@intCast(argc)]) catch |err| return rejectedPromise(engine, err);
    defer engine.freeValue(object);
    return sdk.promise(engine, object) catch |err| rejectedPromise(engine, err);
}
fn persistentObject(engine: *Engine, is_jsonl: bool, args: []const c.JSValue) !c.JSValue {
    const io = engine.native_io orelse return error.DurableIOUnavailable;
    const path = try engine.toString(argument(args, 0));
    defer engine.gpa.free(path);
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_class));
    errdefer engine.freeValue(object);
    // Allocate the receiver and all C functions before opening durable state.
    const self = try engine.gpa.create(State);
    errdefer engine.gpa.destroy(self);
    inline for (std.meta.fields(Method)[0..16]) |field| try sdk.put(engine, object, field.name, try engine.checked(c.pi_js_function_magic(engine.context, method, field.name, 1, @intCast(field.value))));
    self.* = .{ .engine = engine, .kind = if (is_jsonl) .jsonl else .sqlite_source, .memory = undefined, .parent = c.pi_js_undefined(), .tail = c.pi_js_undefined() };
    if (is_jsonl) {
        const filesystem = try engine.gpa.create(filesystem_module.FileSystem);
        errdefer engine.gpa.destroy(filesystem);
        const process_cwd = try std.process.currentPathAlloc(io, engine.gpa);
        defer engine.gpa.free(process_cwd);
        filesystem.* = try filesystem_module.FileSystem.init(engine.gpa, io, process_cwd, null);
        errdefer filesystem.deinit();
        const native = try engine.gpa.create(backend.jsonl.Jsonl);
        errdefer engine.gpa.destroy(native);
        const options = argument(args, 2);
        const fsync_value = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "fsync");
        defer engine.freeValue(fsync_value);
        try checkCancellation(engine, argument(args, 1));
        native.* = try backend.jsonl.Jsonl.open(engine.gpa, path, filesystem, .{}, .{ .fsync = c.JS_ToBool(engine.context, fsync_value) > 0 });
        self.filesystem = filesystem;
        self.jsonl = native;
    } else {
        var busy_timeout: u64 = 5000;
        var checkpoint_pages: u64 = 1000;
        if (!c.JS_IsUndefined(argument(args, 1))) {
            const option = try sdk.get(engine, args[1], "busyTimeoutMs");
            defer engine.freeValue(option);
            if (!c.JS_IsUndefined(option)) busy_timeout = try number(engine, option);
            const checkpoint = try sdk.get(engine, args[1], "walAutoCheckpointPages");
            defer engine.freeValue(checkpoint);
            if (!c.JS_IsUndefined(checkpoint)) checkpoint_pages = try number(engine, checkpoint);
        }
        if (busy_timeout > std.math.maxInt(c_int)) return error.InvalidBusyTimeout;
        if (checkpoint_pages > std.math.maxInt(c_int)) return error.InvalidWalAutoCheckpoint;
        const native = try backend.sqlite_source.Sqlite.open(engine.gpa, io, path, .{ .busy_timeout_ms = @intCast(busy_timeout), .wal_auto_checkpoint_pages = @intCast(checkpoint_pages) });
        errdefer native.deinit();
        try native.db.busyTimeout(@intCast(busy_timeout));
        self.sqlite_source = native;
    }
    _ = c.JS_SetOpaque(object, self);
    return object;
}
pub fn checkCancellation(engine: *Engine, context: c.JSValue) !void {
    if (c.JS_IsUndefined(context) or c.JS_IsNull(context)) return;
    const signal = try sdk.get(engine, context, "abortSignal");
    defer engine.freeValue(signal);
    if (c.JS_IsUndefined(signal) or c.JS_IsNull(signal)) return;
    const aborted = try sdk.get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    if (c.JS_ToBool(engine.context, aborted) > 0) {
        const reason = try sdk.get(engine, signal, "reason");
        _ = c.JS_Throw(engine.context, reason);
        return error.JavaScriptException;
    }
}

fn methods(engine: *Engine, target: c.JSValue, operations: []const Method) !void {
    for (operations) |operation| {
        const name = try engine.gpa.dupeZ(u8, @tagName(operation));
        defer engine.gpa.free(name);
        const arity: c_int = switch (operation) {
            .submissionByRequest, .placeSubmission, .settleSubmission => 2,
            .scanEntries, .scanTasks, .scanConversations => 3,
            else => 1,
        };
        try sdk.put(engine, target, name, try engine.checked(c.pi_js_function_magic(engine.context, method, name, arity, @intFromEnum(operation))));
    }
}
fn createSession(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return sessionObject(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| reject(engine, err);
}
pub fn sessionObject(engine: *Engine, storage: c.JSValue) !c.JSValue {
    const owner = try state(engine, storage);
    const store = try owner.storage();
    const io = engine.native_io orelse return error.DurableIOUnavailable;
    const result_object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_class));
    errdefer engine.freeValue(result_object);
    const self = try engine.gpa.create(State);
    errdefer engine.gpa.destroy(self);
    const lease = try engine.gpa.create(SessionLease);
    errdefer engine.gpa.destroy(lease);
    const native = &lease.value;
    const tail = try sdk.promise(engine, c.pi_js_undefined());
    errdefer engine.freeValue(tail);
    var closed_functions: [2]c.JSValue = undefined;
    const closed_promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &closed_functions));
    errdefer engine.freeValue(closed_promise);
    errdefer engine.freeValue(closed_functions[0]);
    defer engine.freeValue(closed_functions[1]);
    lease.* = .{ .gpa = engine.gpa, .value = session_module.Session.init(engine.gpa, io, store) };
    errdefer native.deinit();
    self.* = .{ .engine = engine, .kind = .session, .memory = undefined, .session = native, .session_lease = lease, .owner_thread = std.Thread.getCurrentId(), .parent = c.JS_DupValue(engine.context, storage), .tail = tail, .task_creator = @import("native_durable_tasks.zig").createTask, .closed_promise = closed_promise, .closed_resolve = closed_functions[0] };
    errdefer engine.freeValue(self.parent);
    _ = try native.subscribe(publication, self);
    try methods(engine, result_object, &.{ .commit, .close, .subscribeCommits, .subscribeClose, .snapshot, .snapshotAsOf, .unloadDocuments, .watchDoc, .documentState });
    if (c.JS_DefinePropertyValueStr(engine.context, result_object, "closed", c.JS_DupValue(engine.context, closed_promise), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    _ = c.JS_SetOpaque(result_object, self);
    return result_object;
}
pub fn transactionObject(engine: *Engine, native: *session_module.Transaction, parent: c.JSValue) !c.JSValue {
    const result_object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_class));
    errdefer engine.freeValue(result_object);
    const self = try engine.gpa.create(State);
    errdefer engine.gpa.destroy(self);
    try methods(engine, result_object, &.{ .createRootConversation, .createConversation, .forkConversation, .appendEntry, .conversation, .entry, .task, .submission, .submissionByRequest, .latestHeadMarker, .scanEntries, .scanTasks, .scanConversations, .createSubmission, .placeSubmission, .settleSubmission, .createTask, .doc, .retireDoc });
    self.* = .{ .engine = engine, .kind = .transaction, .memory = undefined, .transaction = native.retain(), .parent = c.JS_DupValue(engine.context, parent), .tail = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(result_object, self);
    return result_object;
}
const CommitCall = struct {
    engine: *Engine,
    change: c.JSValue,
    receiver: c.JSValue,
    returned: c.JSValue,
    context: c.JSValue,
    drafts: ?*@import("native_durable_documents.zig").Drafts = null,
    transaction_value: ?c.JSValue = null,
    fn run(raw: ?*anyopaque, native: *session_module.Transaction, _: context_module.Context) !json.Value {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const transaction_object = try transactionObject(self.engine, native, self.receiver);
        defer self.engine.freeValue(transaction_object);
        var args = [_]c.JSValue{transaction_object};
        const pending = try self.engine.checked(c.JS_Call(self.engine.context, self.change, c.pi_js_undefined(), 1, &args));
        defer self.engine.freeValue(pending);
        self.returned = try self.engine.awaitValue(pending);
        if ((try state(self.engine, transaction_object)).documents) |documents| try documents.finish();
        self.drafts = (try state(self.engine, transaction_object)).documents;
        self.transaction_value = c.JS_DupValue(self.engine.context, transaction_object);
        const parent = try state(self.engine, self.receiver);
        if (parent.finish_hook) |finish| try finish(self.engine, parent.creation_owner.?, transaction_object);
        return .null;
    }
};
fn ignore(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    _ = context;
    return c.pi_js_undefined();
}
fn queuedContinuation(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = state(engine, data[0]) catch |err| return reject(engine, err);
    if (operation == 1) {
        self.session.?.close();
        for (self.commit_listeners.items) |listener| engine.freeValue(listener);
        self.commit_listeners.clearRetainingCapacity();
        self.session.?.storage.drain();
        return closeBackend(self, data[0], data[2]) catch |err| {
            _ = reject(engine, err);
            const reason = c.JS_GetException(engine.context);
            defer engine.freeValue(reason);
            recordFailure(self, reason);
            settleClosed(self) catch |settle_error| return reject(engine, settle_error);
            return c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
        };
    }
    checkCancellation(engine, data[2]) catch |err| return reject(engine, err);
    self.publication_context = data[2];
    defer self.publication_context = null;
    var call: CommitCall = .{ .engine = engine, .change = data[1], .receiver = data[0], .returned = c.pi_js_undefined(), .context = data[2] };
    defer if (call.transaction_value) |value| engine.freeValue(value);
    const scope = if (c.JS_IsUndefined(data[3])) session_module.Scope{} else session_module.Scope{ .conversationId = number(engine, data[3]) catch |err| return reject(engine, err) };
    var native_result = self.session.?.commit(CommitCall.run, &call, scope, .{}) catch |err| {
        engine.freeValue(call.returned);
        return reject(engine, err);
    };
    native_result.deinit();
    if (call.drafts) |drafts| drafts.adopt(data[0]) catch |err| {
        engine.freeValue(call.returned);
        return reject(engine, err);
    };
    if (self.after_commit) |flush| flush(self.foreign_publication_context) catch |err| {
        engine.freeValue(call.returned);
        return reject(engine, err);
    };
    return call.returned;
}
fn recordFailure(self: *State, reason: c.JSValue) void {
    if (self.failure_reason == null) {
        self.failure_reason = c.JS_DupValue(self.engine.context, reason);
        _ = self.session.?.fail(error.JavaScriptException);
    }
}
fn assertVMHealthy(self: *State) !void {
    if (self.failure_reason) |reason| {
        const value = try @import("native_durable_errors.zig").sessionFailed(self.engine, reason);
        _ = try self.engine.checked(c.JS_Throw(self.engine.context, value));
    }
    try self.session.?.assertHealthy();
}
fn settleClosed(self: *State) !void {
    const resolve = self.closed_resolve orelse return;
    const engine = self.engine;
    const end = try sdk.object(engine);
    defer engine.freeValue(end);
    try sdk.put(engine, end, "reason", try sdk.text(engine, if (self.failure_reason != null) "failed" else "closed"));
    if (self.failure_reason) |reason| try sdk.put(engine, end, "error", c.JS_DupValue(engine.context, reason));
    var args = [_]c.JSValue{end};
    const ignored = try engine.checked(c.JS_Call(engine.context, resolve, c.pi_js_undefined(), 1, &args));
    engine.freeValue(ignored);
    engine.freeValue(resolve);
    self.closed_resolve = null;
}
fn closeBackend(self: *State, receiver: c.JSValue, context: c.JSValue) !c.JSValue {
    const engine = self.engine;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const cleanup = try @import("native_durable_context.zig").withoutAbortSignal(engine, context);
    defer engine.freeValue(cleanup);
    const value = try sdk.invoke(engine, self.parent, "close", &.{cleanup});
    defer engine.freeValue(value);
    const pending = try sdk.promise(engine, value);
    defer engine.freeValue(pending);
    var data = [_]c.JSValue{receiver};
    const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, closeSettled, 1, 0, data.len, &data));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, closeSettled, 1, 1, data.len, &data));
    defer engine.freeValue(rejected);
    return sdk.invoke(engine, pending, "then", &.{ fulfilled, rejected });
}
fn closeSettled(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, rejected: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = state(engine, data[0]) catch |err| return reject(engine, err);
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    if (rejected != 0) recordFailure(self, value);
    settleClosed(self) catch |err| return reject(engine, err);
    if (rejected != 0) return c.JS_Throw(context, c.JS_DupValue(context, value));
    return c.pi_js_undefined();
}
pub fn sessionDispatch(self: *State, receiver: c.JSValue, operation: Method, args: []const c.JSValue) !c.JSValue {
    if (operation != .close) try assertVMHealthy(self);
    if (operation == .documentState) return @import("native_durable_state.zig").acquire(self.engine, receiver, args);
    if (operation == .watchDoc) return @import("native_durable_observation.zig").acquire(self.engine, receiver, args);
    if (operation == .unloadDocuments) return @import("native_durable_documents.zig").unload(self.engine, receiver);
    if (operation == .snapshot) return @import("native_durable_documents.zig").snapshot(self.engine, receiver, args);
    if (operation == .snapshotAsOf) return @import("native_durable_documents.zig").snapshotAsOf(self.engine, receiver, args);
    return sessionDispatchScoped(self, receiver, operation, args, null);
}
pub fn sessionDispatchScoped(self: *State, receiver: c.JSValue, operation: Method, args: []const c.JSValue, conversation: ?u64) !c.JSValue {
    const engine = self.engine;
    if (operation != .commit and operation != .close) return error.InvalidDurableSessionMethod;
    if (operation == .commit) try assertVMHealthy(self);
    if (self.closing and operation == .commit) return error.SessionClosed;
    if (operation == .commit and !c.JS_IsFunction(engine.context, argument(args, 0))) return error.ExpectedDurableCommitCallback;
    if (self.closing and operation == .close) return @import("native_durable_context.zig").awaitWithContext(engine, self.close_pending orelse self.tail, argument(args, 0));
    const close_snapshot = if (operation == .close) try duplicateListeners(engine, self.close_listeners.items) else null;
    defer if (close_snapshot) |listeners| freeListeners(engine, listeners);
    const scope = if (conversation) |id| try engine.checked(c.JS_NewInt64(engine.context, @intCast(id))) else c.pi_js_undefined();
    defer engine.freeValue(scope);
    var data = [_]c.JSValue{ receiver, argument(args, 0), argument(args, if (operation == .close) 0 else 1), scope };
    // Allocate the normalization callback before admitting the queue callback.
    const ignored = try engine.checked(c.JS_NewCFunction(engine.context, ignore, "durable-line-settled", 0));
    defer engine.freeValue(ignored);
    const run = try engine.checked(c.JS_NewCFunctionData(engine.context, queuedContinuation, 1, if (operation == .close) 1 else 0, data.len, &data));
    defer engine.freeValue(run);
    const queued = try sdk.invoke(engine, self.tail, "then", &.{run});
    errdefer engine.freeValue(queued);
    const next = try sdk.invoke(engine, queued, "then", &.{ ignored, ignored });
    engine.freeValue(self.tail);
    self.tail = next;
    if (operation == .close) {
        self.closing = true;
        self.close_pending = c.JS_DupValue(engine.context, queued);
        @import("native_durable_tasks.zig").retireSession(engine, receiver);
    }
    if (close_snapshot) |listeners| {
        for (self.close_listeners.items) |listener| engine.freeValue(listener);
        self.close_listeners.clearRetainingCapacity();
        for (listeners) |listener| {
            contained(engine, listener, &.{});
        }
    }
    if (operation == .close) {
        const observed = try @import("native_durable_context.zig").awaitWithContext(engine, queued, argument(args, 0));
        engine.freeValue(queued);
        return observed;
    }
    return queued;
}
fn contained(engine: *Engine, callback: c.JSValue, arguments: []const c.JSValue) void {
    const returned = c.JS_Call(engine.context, callback, c.pi_js_undefined(), @intCast(arguments.len), if (arguments.len == 0) null else @constCast(arguments.ptr));
    if (c.JS_IsException(returned)) {
        engine.freeValue(c.JS_GetException(engine.context));
        return;
    }
    defer engine.freeValue(returned);
    const pending = sdk.promise(engine, returned) catch return;
    defer engine.freeValue(pending);
    const ignored = engine.checked(c.JS_NewCFunction(engine.context, ignore, "contained-listener-error", 0)) catch return;
    defer engine.freeValue(ignored);
    const observed = sdk.invoke(engine, pending, "then", &.{ ignored, ignored }) catch return;
    engine.freeValue(observed);
}

fn duplicateListeners(engine: *Engine, listeners: []const c.JSValue) ![]c.JSValue {
    const snapshot = try engine.gpa.alloc(c.JSValue, listeners.len);
    for (listeners, snapshot) |listener, *copy| copy.* = c.JS_DupValue(engine.context, listener);
    return snapshot;
}
fn freeListeners(engine: *Engine, listeners: []c.JSValue) void {
    for (listeners) |listener| engine.freeValue(listener);
    engine.gpa.free(listeners);
}
pub fn subscribe(self: *State, receiver: c.JSValue, operation: Method, listener: c.JSValue) !c.JSValue {
    const engine = self.engine;
    if (self.kind != .session) return error.SessionClosed;
    try assertVMHealthy(self);
    if (self.closing) return error.SessionClosed;
    if (!c.JS_IsFunction(engine.context, listener)) return error.ExpectedDurableListener;
    var data = [_]c.JSValue{ receiver, listener };
    const cancel = try engine.checked(c.JS_NewCFunctionData(engine.context, unsubscribe, 0, if (operation == .subscribeClose) 1 else 0, data.len, &data));
    errdefer engine.freeValue(cancel);
    const list = if (operation == .subscribeClose) &self.close_listeners else &self.commit_listeners;
    for (list.items) |previous| if (c.JS_IsStrictEqual(engine.context, previous, listener)) return cancel;
    try list.ensureUnusedCapacity(engine.gpa, 1);
    list.appendAssumeCapacity(c.JS_DupValue(engine.context, listener));
    return cancel;
}
fn unsubscribe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, close_listener: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = state(engine, data[0]) catch |err| return reject(engine, err);
    const list = if (close_listener == 1) &self.close_listeners else &self.commit_listeners;
    for (list.items, 0..) |listener, index| if (c.JS_IsStrictEqual(engine.context, listener, data[1])) {
        engine.freeValue(list.orderedRemove(index));
        break;
    };
    return c.pi_js_undefined();
}
fn publication(raw: ?*anyopaque, event: *const session_module.Publication, _: context_module.Context) !void {
    const self: *State = @ptrCast(@alignCast(raw.?));
    if (self.foreign_publication) |forward| return forward(self.foreign_publication_context, event);
    if (std.Thread.getCurrentId() != self.owner_thread) {
        return error.VMCallbackOnWorker;
    }
    return deliverPublication(self, event);
}
pub fn deliverPublication(self: *State, event: *const session_module.Publication) !void {
    const engine = self.engine;
    if (self.commit_listeners.items.len == 0) return;
    const listeners = try duplicateListeners(engine, self.commit_listeners.items);
    defer freeListeners(engine, listeners);
    const value = try sdk.object(engine);
    defer engine.freeValue(value);
    try sdk.put(engine, value, "seq", c.JS_NewInt64(engine.context, @intCast(event.seq)));
    const changes = try jsValue(engine, event.changes);
    defer engine.freeValue(changes);
    for (event.changes.array.items, 0..) |change, index| {
        const kind = json.get(change, "type") orelse continue;
        if (kind != .string or !std.mem.eql(u8, kind.string, "document")) continue;
        const record = json.get(change, "record") orelse continue;
        const version = json.get(change, "version") orelse continue;
        const canonical = @import("native_durable_documents.zig").publicationValue(self, record, try json.asInteger(version)) orelse continue;
        const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, changes, @intCast(index)));
        defer engine.freeValue(item);
        try sdk.put(engine, item, "value", c.JS_DupValue(engine.context, canonical));
    }
    try sdk.put(engine, value, "changes", c.JS_DupValue(engine.context, changes));
    var args = [_]c.JSValue{ value, self.publication_context orelse c.pi_js_undefined() };
    for (listeners) |listener| {
        contained(engine, listener, &args);
    }
}
fn transactionDispatch(self: *State, receiver: c.JSValue, operation: Method, args: []const c.JSValue) !c.JSValue {
    const engine = self.engine;
    const native = self.transaction.?;
    if (operation == .doc) return @import("native_durable_documents.zig").acquire(engine, receiver, args);
    if (operation == .retireDoc) return @import("native_durable_documents.zig").retire(engine, receiver, args);
    if (operation == .createTask) {
        if (!native.active) return error.TransactionClosed;
        const parent = try state(engine, self.parent);
        const create = parent.task_creator orelse return error.TaskCreatorUnavailable;
        return create(engine, parent.creation_owner orelse c.pi_js_undefined(), receiver, args);
    }
    const output: json.Value = switch (operation) {
        .scanEntries, .scanTasks, .scanConversations => blk: {
            var query = try owned(engine, argument(args, 0));
            defer query.deinit();
            const limit = if (c.JS_IsUndefined(argument(args, 1))) 100 else try number(engine, argument(args, 1));
            var cursor = if (c.JS_IsUndefined(argument(args, 2))) null else try owned(engine, argument(args, 2));
            defer if (cursor) |*value| value.deinit();
            break :blk try native.sourceScan(switch (operation) {
                .scanEntries => .entry,
                .scanTasks => .task,
                .scanConversations => .conversation,
                else => unreachable,
            }, query.value, limit, if (cursor) |value| value.value else null);
        },
        .submission => (try native.readRecord(.submission, try number(engine, argument(args, 0)))) orelse return sdk.promise(engine, c.pi_js_undefined()),
        .submissionByRequest => blk: {
            const request = try engine.toString(argument(args, 1));
            defer engine.gpa.free(request);
            break :blk (try native.submissionByRequest(try number(engine, argument(args, 0)), request)) orelse return sdk.promise(engine, c.pi_js_undefined());
        },
        .latestHeadMarker => (try native.latestHeadMarker(try number(engine, argument(args, 0)))) orelse return sdk.promise(engine, c.pi_js_undefined()),
        .createSubmission => blk: {
            const options = try sdk.object(engine);
            defer engine.freeValue(options);
            try sdk.put(engine, options, "omitUndefinedProperties", c.pi_js_bool(engine.context, 1));
            const copied = try @import("native_chord_json.zig").copyJson(engine, argument(args, 0), options);
            defer engine.freeValue(copied);
            var input = try owned(engine, copied);
            defer input.deinit();
            break :blk try native.createSubmission(input.value);
        },
        .placeSubmission, .settleSubmission => {
            var change = if (operation == .placeSubmission) try json.Owned.empty(engine.gpa) else try owned(engine, argument(args, 1));
            defer change.deinit();
            if (operation == .placeSubmission) {
                change.value = .{ .object = .empty };
                try change.value.object.put(change.arena.allocator(), "status", .{ .string = "placed" });
                try change.value.object.put(change.arena.allocator(), "entry", .{ .integer = @intCast(try number(engine, argument(args, 1))) });
            }
            try native.changeSubmission(try number(engine, argument(args, 0)), change.value);
            return c.pi_js_undefined();
        },
        .createRootConversation => try native.createRootConversation(),
        .createConversation => try native.createConversation(null, try ownerTask(engine, argument(args, 0))),
        .forkConversation => blk: {
            var parent = try json.Owned.empty(engine.gpa);
            defer parent.deinit();
            parent.value = .{ .object = .empty };
            try parent.value.object.put(parent.arena.allocator(), "conversationId", .{ .integer = @intCast(try number(engine, argument(args, 0))) });
            try parent.value.object.put(parent.arena.allocator(), "at", .{ .integer = @intCast(try number(engine, argument(args, 1))) });
            break :blk try native.createConversation(parent.value, try ownerTask(engine, argument(args, 2)));
        },
        .appendEntry => blk: {
            const typed = !c.JS_IsNumber(argument(args, 0));
            const value = argument(args, if (typed) 2 else 1);
            const copied = if (typed) try sdk.object(engine) else c.JS_DupValue(engine.context, value);
            defer engine.freeValue(copied);
            if (typed) {
                const global = c.JS_GetGlobalObject(engine.context);
                defer engine.freeValue(global);
                const object = try sdk.get(engine, global, "Object");
                defer engine.freeValue(object);
                const assigned = try sdk.invoke(engine, object, "assign", &.{ copied, value });
                engine.freeValue(assigned);
                try sdk.put(engine, copied, "kind", try sdk.get(engine, args[0], "kind"));
            }
            var draft = try owned(engine, copied);
            defer draft.deinit();
            break :blk try native.appendEntry(try number(engine, argument(args, if (typed) 1 else 0)), draft.value);
        },
        .entry => blk: {
            const typed = !c.JS_IsNumber(argument(args, 0));
            const entry = (try native.readRecord(.entry, try number(engine, argument(args, if (typed) 1 else 0)))) orelse return sdk.promise(engine, c.pi_js_undefined());
            if (typed) {
                const token_kind = try sdk.get(engine, args[0], "kind");
                defer engine.freeValue(token_kind);
                const kind = try engine.toString(token_kind);
                defer engine.gpa.free(kind);
                if (!std.mem.eql(u8, kind, try json.asString(try json.required(entry, "kind")))) return sdk.promise(engine, c.pi_js_undefined());
            }
            break :blk entry;
        },
        .conversation, .task => (try native.readRecord(if (operation == .conversation) .conversation else .task, try number(engine, argument(args, 0)))) orelse return sdk.promise(engine, c.pi_js_undefined()),
        else => return error.InvalidDurableTransactionMethod,
    };
    if (operation == .createRootConversation or operation == .createConversation or operation == .forkConversation) {
        const parent = try state(engine, self.parent);
        if (parent.creation_hook) |hook| try hook(engine, parent.creation_owner.?, receiver, output);
    }
    const resolved = try jsValue(engine, output);
    defer engine.freeValue(resolved);
    return sdk.promise(engine, resolved);
}
/// Queues a native owner continuation on the same line as Session commits.
pub fn enqueue(engine: *Engine, session: c.JSValue, callback: c.JSValue) !c.JSValue {
    const self = try state(engine, session);
    try assertVMHealthy(self);
    if (self.closing) return error.SessionClosed;
    const ignored = try engine.checked(c.JS_NewCFunction(engine.context, ignore, "durable-line-settled", 0));
    defer engine.freeValue(ignored);
    const queued = try sdk.invoke(engine, self.tail, "then", &.{callback});
    errdefer engine.freeValue(queued);
    const next = try sdk.invoke(engine, queued, "then", &.{ ignored, ignored });
    engine.freeValue(self.tail);
    self.tail = next;
    return queued;
}
fn ownerTask(engine: *Engine, options: c.JSValue) !?u64 {
    const ownership = try sdk.get(engine, options, "ownership");
    defer engine.freeValue(ownership);
    const kind = try sdk.get(engine, ownership, "kind");
    defer engine.freeValue(kind);
    const name = try engine.toString(kind);
    defer engine.gpa.free(name);
    if (std.mem.eql(u8, name, "ownerless")) return null;
    if (!std.mem.eql(u8, name, "task")) return error.InvalidConversationOwnership;
    const task = try sdk.get(engine, ownership, "taskId");
    defer engine.freeValue(task);
    return try number(engine, task);
}

fn constructorAllocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try install(engine);
    const storage = try memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try sessionObject(engine, storage);
    defer engine.freeValue(session);
}

test "native durable VM eba independent concurrent and unawaited nested commits retain Source queue order" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try install(engine);
    const source = @embedFile("../durable/fixtures/durable-storage-failure-eba.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-eba-storage"));
    defer engine.freeValue(fixture);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "storageFailureFixture", c.JS_DupValue(engine.context, fixture));
    const queue_output = engine.evalModule(
        \\import {MemoryStorage,createSession} from '@earendil-works/pi-durable';
        \\const expected=name=>storageFailureFixture.cases.find(c=>c.name===name);
        \\const equal=(a,b)=>{if(JSON.stringify(a)!==JSON.stringify(b))throw Error(JSON.stringify({a,b}));};
        \\{
        \\ const session=createSession(new MemoryStorage()),events=[];let release;
        \\ const admitted=new Promise(resolve=>release=resolve);
        \\ const first=session.commit(async()=>{events.push('first-begin');await admitted;events.push('first-end');return 1;},{});
        \\ const second=session.commit(()=>{events.push('second');return 2;},{});
        \\ await Promise.resolve();await Promise.resolve();const before=[...events];release();
        \\ const values=await Promise.all([first,second]);await session.close({});events.push('close');
        \\ const source=expected('concurrent-commit-order');equal({before,events,values},{before:source.before,events:source.events,values:source.values});
        \\}
        \\{
        \\ const session=createSession(new MemoryStorage()),events=[];let nested;
        \\ const first=await session.commit(()=>{events.push('outer-begin');nested=session.commit(()=>{events.push('nested');return 2;},{});events.push('outer-end');return 1;},{});
        \\ const second=await nested;await session.close({});events.push('close');
        \\ const source=expected('nested-unawaited-commit');equal({events,values:[first,second]},{events:source.events,values:source.values});
        \\}
    , "actual-eba-commit-queue") catch |err| {
        std.debug.print("Actual Source commit queue: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(queue_output);
}

test "native durable VM backend close overrides settle closed only after cleanup and preserve raw close failure identity" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try install(engine);
    const source = @embedFile("../durable/fixtures/durable-close-facade-eba.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "actual-eba-close"));
    defer engine.freeValue(fixture);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "closeFixture", c.JS_DupValue(engine.context, fixture));
    const output = engine.evalModule(
        \\import{MemoryStorage,createSession,SessionFailed}from'@earendil-works/pi-durable';
        \\import{BACKGROUND_CONTEXT,withAbortSignal}from'@earendil-works/chord/context';
        \\const equal=(a,b)=>{if(JSON.stringify(a)!==JSON.stringify(b))throw Error(JSON.stringify({a,b}));};
        \\for(const cancelCaller of [false,true]){
        \\ const calls=[];let release;const gate=new Promise(resolve=>release=resolve);
        \\ class Held extends MemoryStorage{async close(ctx){calls.push('backend');if(ctx.abortSignal!==undefined)throw Error('cleanup retained caller signal');await gate;calls.push('settled');await super.close(ctx)}}
        \\ const session=createSession(new Held());let ended=false;session.closed.then(()=>ended=true);
        \\ session.subscribeClose(()=>{calls.push('first');throw{listener:true}});session.subscribeClose(()=>calls.push('second'));session.subscribeClose(()=>Promise.reject({asyncListener:true}));
        \\ const controller=new AbortController(),reason=new Error('caller stop');if(cancelCaller)controller.abort(reason);
        \\ const closing=session.close(cancelCaller?withAbortSignal(controller.signal,BACKGROUND_CONTEXT):BACKGROUND_CONTEXT);
        \\ const synchronous=[...calls];let callerError;const observed=closing.catch(error=>callerError=error);
        \\ await Promise.resolve();await Promise.resolve();const beforeBackendSettled=ended;release();await observed;
        \\ const end=await session.closed;await session.close(BACKGROUND_CONTEXT);
        \\ const row={name:cancelCaller?'canceled-caller':'ordinary',synchronous,beforeBackendSettled,calls,endReason:end.reason,callerOriginal:callerError===reason};
        \\ equal(row,closeFixture.cases.find(item=>item.name===row.name));
        \\}
        \\{
        \\ const calls=[];let release;const gate=new Promise(resolve=>release=resolve);
        \\ class Held extends MemoryStorage{async close(ctx){calls.push('backend');if(ctx.abortSignal!==undefined)throw Error('cleanup retained caller signal');await gate;calls.push('settled');await super.close(ctx)}}
        \\ const session=createSession(new Held());let ended=false;session.closed.then(()=>ended=true);
        \\ session.subscribeClose(()=>{calls.push('first');throw {listener:true}});session.subscribeClose(()=>calls.push('second'));session.subscribeClose(()=>Promise.reject({asyncListener:true}));
        \\ const closing=session.close({});if(calls.join(',')!=='first,second')throw Error('synchronous listener isolation');
        \\ await Promise.resolve();await Promise.resolve();if(ended)throw Error('closed before backend cleanup');release();await closing;
        \\ const end=await session.closed;if(end.reason!=='closed'||calls.join(',')!=='first,second,backend,settled')throw Error('close settlement');await session.close({});
        \\}
        \\{
        \\ const raw=Object.create(null);raw.toString=()=>{throw Error('must not coerce cause')};let calls=0;
        \\ class Broken extends MemoryStorage{close(){calls++;throw raw}}
        \\ const session=createSession(new Broken());let first;try{await session.close({})}catch(error){first=error}
        \\ const end=await session.closed;if(first!==raw||end.reason!=='failed'||end.error!==raw||calls!==1)throw Error('raw close failure');
        \\ let later;try{await session.commit(()=>true,{})}catch(error){later=error}
        \\ if(!(later instanceof SessionFailed)||later.cause!==raw)throw Error('failed admission');
        \\ let repeated;try{await session.close({})}catch(error){repeated=error}if(repeated!==raw||calls!==1)throw Error('close once');
        \\}
    , "actual-eba-close-override") catch |err| {
        std.debug.print("Durable close facade: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(output);
}
test "native durable VM constructor and module allocations roll back on every GPA failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, constructorAllocationExercise, .{});
}
