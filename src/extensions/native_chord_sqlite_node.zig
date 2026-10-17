//! Actual c268 Chord sqlite/node adapter. Imported functions are genuine inputs.
const std = @import("std");
const em = @import("engine.zig");
const v = @import("native_chord_sqlite_node_values.zig");
const c = v.c;
const af = v.af;
const functions = @import("native_node_function.zig");
const classes = @import("native_class.zig");
const js = @import("native_js_values.zig");
const queue = @import("native_chord_sqlite_node_queue.zig");
pub const Inputs = struct { database_sync: c.JSValue, mkdir: c.JSValue, dirname: c.JSValue };
const cache_key = "\x00native-chord-sqlite-node-module";
fn method(s: *v.Scope, proto: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { if (c.JS_DefinePropertyValueStr(s.engine.context, proto, name, c.JS_DupValue(s.engine.context, value), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(s.engine); }
pub fn create(engine: *em.Engine, inputs: Inputs) !c.JSValue {
    try v.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
    if (engine.native_module_values.get(cache_key)) |graph| {
        if (!s.equal(try s.get(graph, "DatabaseSync"), inputs.database_sync) or !s.equal(try s.get(graph, "mkdir"), inputs.mkdir) or !s.equal(try s.get(graph, "dirname"), inputs.dirname)) return error.ChordSqliteNodeImportIdentityChanged;
        return c.JS_DupValue(engine.context, try s.get(graph, "exports"));
    }
    const graph = try s.own(try v.checked(engine, c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try s.put(graph, "DatabaseSync", inputs.database_sync); try s.put(graph, "mkdir", inputs.mkdir); try s.put(graph, "dirname", inputs.dirname);
    const ignore = try s.own(try functions.createArrow(engine, "ignore", 0, v.callback(noop), &.{}));
    const queue_proto = try s.own(try queue.prototype(engine, ignore));
    try s.put(graph, "Queue", try s.own(try classes.constructor(engine, "SerialOperationQueue", 0, queue_proto, v.callback(queueConstructor), &.{})));
    const executor_proto = try s.object();
    const executor = try s.own(try classes.constructor(engine, "NodeSqliteExecutor", 2, executor_proto, v.callback(executorConstructor), &.{}));
    inline for (.{ "exec", "run", "get", "all" }) |name| {
        const Adapter = struct { fn call(host: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return executorMethod(host, name, receiver, args); } };
        try method(&s, executor_proto, name, try s.own(try functions.createMethod(engine, name, 1, v.callback(Adapter.call), &.{})));
    }
    try method(&s, executor_proto, "statement", try s.own(try functions.createMethod(engine, "statement", 1, v.callback(cachedStatement), &.{})));
    const transaction_proto = try s.own(try v.checked(engine, c.JS_NewObjectProto(engine.context, executor_proto)));
    const transaction_ctor = try s.own(try classes.constructor(engine, "NodeSqliteTransaction", 3, transaction_proto, v.callback(transactionConstructor), &.{graph}));
    if (c.JS_SetPrototype(engine.context, transaction_ctor, executor) < 0) return js.capture(engine);
    try s.put(graph, "Transaction", transaction_ctor);
    try method(&s, transaction_proto, "runOperation", try s.own(try af.createResumable(engine, "runOperation", 1, transactionOperation, &.{})));
    const db_proto = try s.own(try v.checked(engine, c.JS_NewObjectProto(engine.context, executor_proto)));
    const db_ctor = try s.own(try classes.constructor(engine, "NodeSqliteDatabase", 1, db_proto, v.callback(databaseConstructor), &.{graph}));
    if (c.JS_SetPrototype(engine.context, db_ctor, executor) < 0) return js.capture(engine);
    try s.put(graph, "NodeSqliteDatabase", db_ctor);
    try method(&s, db_proto, "runOperation", try s.own(try functions.createMethod(engine, "runOperation", 1, v.callback(databaseOperation), &.{})));
    try method(&s, db_proto, "transaction", try s.own(try functions.createMethod(engine, "transaction", 1, v.callback(transaction), &.{graph})));
    try method(&s, db_proto, "close", try s.own(try functions.createMethod(engine, "close", 0, v.callback(close), &.{})));
    const exports = try s.object(); try s.put(exports, "NodeSqliteDatabase", db_ctor);
    try s.put(exports, "openNodeSqliteDatabase", try s.own(try af.createResumable(engine, "openNodeSqliteDatabase", 1, open, &.{graph})));
    try s.put(graph, "exports", exports);
    const retained = c.JS_DupValue(engine.context, graph); engine.native_module_values.put(engine.gpa, cache_key, retained) catch |err| { engine.freeValue(retained); return err; };
    return c.JS_DupValue(engine.context, exports);
}
fn queueConstructor(engine: *em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); return c.JS_DupValue(engine.context, try queue.create(&s, try v.objectFor(&s, target))); }
fn executorConstructor(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); const object = try v.objectFor(&s, target);
    try s.put(object, "database", v.at(args, 0)); try s.put(object, "statements", v.at(args, 1)); return c.JS_DupValue(engine.context, object);
}
fn superConstruct(s: *v.Scope, graph: c.JSValue, home: [*:0]const u8, target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const constructor = try s.own(try v.checked(s.engine, c.JS_GetPrototype(s.engine.context, try s.get(graph, home))));
    const generation = s.engine.native_allocation_generation;
    return s.own(try v.guard(s.engine, generation, v.checked(s.engine, c.JS_CallConstructor2(s.engine.context, constructor, target, @intCast(args.len), @constCast(args.ptr)))));
}
fn databaseConstructor(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); const graph = roots[0];
    const selected_super = try s.own(try v.checked(engine, c.JS_GetPrototype(engine.context, try s.get(graph, "NodeSqliteDatabase"))));
    const map = try v.construct(&s, try v.global(&s, "Map"), &.{});
    const generation = engine.native_allocation_generation;
    const super_args = [_]c.JSValue{v.at(args, 0), map};
    const object = try s.own(try v.guard(engine, generation, v.checked(engine, c.JS_CallConstructor2(engine.context, selected_super, target, 2, @constCast(&super_args)))));
    try s.put(object, "access", try v.construct(&s, try s.get(graph, "Queue"), &.{})); try s.put(object, "closed", c.pi_js_bool(engine.context, 0));
    return c.JS_DupValue(engine.context, object);
}
fn transactionConstructor(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); const object = try superConstruct(&s, roots[0], "Transaction", target, &.{v.at(args, 0), v.at(args, 1)});
    try s.put(object, "scope", v.at(args, 2)); return c.JS_DupValue(engine.context, object);
}
fn cachedStatement(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); const sql = v.at(args, 0);
    var statement = try v.invoke(&s, try v.get(&s, receiver, "statements"), "get", &.{sql});
    if (c.JS_IsUndefined(statement)) { statement = try v.invoke(&s, try v.get(&s, receiver, "database"), "prepare", &.{sql}); _ = try v.invoke(&s, try v.get(&s, receiver, "statements"), "set", &.{sql, statement}); }
    return c.JS_DupValue(engine.context, statement);
}
fn executorMethod(engine: *em.Engine, comptime name: []const u8, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); const params = try s.array();
    if (args.len > 1) for (args[1..], 0..) |value, index| try s.index(params, @intCast(index), value);
    const run_operation = try v.get(&s, receiver, "runOperation");
    const Adapter = struct { fn call(host: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return sqlOperation(host, name, roots); } };
    const operation = try s.own(try functions.createArrow(engine, "", 0, v.callback(Adapter.call), &.{ receiver, v.at(args, 0), params }));
    return c.JS_DupValue(engine.context, try v.call(&s, run_operation, receiver, &.{operation}));
}
fn sqlOperation(engine: *em.Engine, comptime name: []const u8, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
    if (comptime std.mem.eql(u8, name, "exec")) { _ = try v.invoke(&s, try v.get(&s, roots[0], "database"), "exec", &.{roots[1]}); return c.pi_js_undefined(); }
    const statement = try v.invoke(&s, roots[0], "statement", &.{roots[1]});
    const function = try v.get(&s, statement, name); const result = try callSpread(&s, function, statement, roots[2]);
    return if (comptime std.mem.eql(u8, name, "run")) c.pi_js_undefined() else c.JS_DupValue(engine.context, result);
}
fn callSpread(s: *v.Scope, function: c.JSValue, receiver: c.JSValue, iterable: c.JSValue) !c.JSValue {
    const symbol = try s.own(try v.checked(s.engine, c.JS_GetIteratorSymbol(s.engine.context))); const generation = s.engine.native_allocation_generation;
    const iterator_method = try s.own(try v.guard(s.engine, generation, js.getKey(s.engine, iterable, symbol)));
    const iterator = try v.call(s, iterator_method, iterable, &.{}); if (!c.JS_IsObject(iterator)) return js.typeError(s.engine, "Iterator is not an object");
    const next = try v.get(s, iterator, "next"); var arguments: std.ArrayList(c.JSValue) = .empty; defer arguments.deinit(s.engine.gpa);
    var steps: u64 = 0;
    while (true) {
        steps +|= 1;
        if (s.engine.cancelled.load(.acquire) or (steps % 256 == 0 and blk: { s.engine.interrupts +|= 1; break :blk s.engine.interrupts > s.engine.options.interrupt_budget; })) { _ = c.JS_ThrowInternalError(s.engine.context, "interrupted"); const reason = c.JS_GetException(s.engine.context); c.JS_SetUncatchableError(s.engine.context, reason); _ = try v.checked(s.engine, c.JS_Throw(s.engine.context, reason)); unreachable; }
        const step = try v.call(s, next, iterator, &.{}); if (!c.JS_IsObject(step)) return js.typeError(s.engine, "Iterator result is not an object");
        if (s.truthy(try v.get(s, step, "done"))) break;
        try arguments.append(s.engine.gpa, try v.get(s, step, "value"));
    }
    return v.call(s, function, receiver, arguments.items);
}
fn databaseOperation(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); return c.JS_DupValue(engine.context, try v.invoke(&s, try v.get(&s, receiver, "access"), "run", &.{v.at(args, 0)})); }
fn transactionOperation(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, completion: af.Completion, _: c.JSValue) anyerror!af.Action {
    try v.pending(engine);
    if (completion != .start) return error.UnexpectedSqliteTransactionOperationResume;
    return transactionOperationBody(engine, receiver, v.at(args, 0)) catch |err| v.failure(engine, err);
}
fn transactionOperationBody(engine: *em.Engine, receiver: c.JSValue, operation: c.JSValue) !af.Action {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
    if (!s.truthy(try v.get(&s, try v.get(&s, receiver, "scope"), "active"))) { const reason = try v.construct(&s, try v.global(&s, "Error"), &.{try s.text("SQLite transaction handle is no longer active")}); return .{ .thrown = c.JS_DupValue(engine.context, reason) }; }
    return .{ .returned = c.JS_DupValue(engine.context, try v.call(&s, operation, c.pi_js_undefined(), &.{})) };
}
fn transaction(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); const access = try v.get(&s, receiver, "access"); const run_async = try v.get(&s, access, "runAsync");
    const operation = try s.own(try af.createResumableArrow(engine, "", 0, transactionBody, &.{ receiver, v.at(args, 0), roots[0] }, c.pi_js_undefined()));
    return c.JS_DupValue(engine.context, try v.call(&s, run_async, access, &.{operation}));
}
fn transactionBody(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    try v.pending(engine);
    return transactionRun(engine, roots, state, completion, input) catch |err| {
        const reason = try v.caught(engine, err); defer engine.freeValue(reason);
        var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
        if (!c.JS_IsObject(state.*) or !s.truthy(try s.get(state.*, "catchActive"))) return .{ .thrown = c.JS_DupValue(engine.context, reason) };
        try s.put(state.*, "catchActive", c.pi_js_bool(engine.context, 0)); return rollback(&s, roots[0], state.*, reason);
    };
}
fn transactionRun(engine: *em.Engine, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
    if (completion != .start) {
        if (completion == .rejected) { try v.rejected(&s, state.*, input); try s.put(state.*, "catchActive", c.pi_js_bool(engine.context, 0)); return rollback(&s, roots[0], state.*, input); }
        try v.set(&s, try s.get(state.*, "scope"), "active", c.pi_js_bool(engine.context, 0));
        _ = try v.invoke(&s, try v.get(&s, roots[0], "database"), "exec", &.{try s.text("COMMIT")});
        return .{ .returned = c.JS_DupValue(engine.context, input) };
    }
    const owner = try v.init(&s, state);
    _ = try v.invoke(&s, try v.get(&s, roots[0], "database"), "exec", &.{try s.text("BEGIN IMMEDIATE")});
    const scope = try s.object(); try s.put(scope, "active", c.pi_js_bool(engine.context, 1)); try s.put(owner, "scope", scope); try s.put(owner, "catchActive", c.pi_js_bool(engine.context, 1));
    const tx = try v.construct(&s, try s.get(roots[2], "Transaction"), &.{ try v.get(&s, roots[0], "database"), try v.get(&s, roots[0], "statements"), scope });
    return v.wait(&s, owner, roots[1], c.pi_js_undefined(), &.{tx}, 0);
}
fn rollback(s: *v.Scope, adapter: c.JSValue, owner: c.JSValue, reason: c.JSValue) !af.Action {
    try v.set(s, try s.get(owner, "scope"), "active", c.pi_js_bool(s.engine.context, 0));
    rollbackAttempt(s, adapter) catch |err| {
        const second = try s.own(try v.caught(s.engine, err)); const errors = try s.array(); try s.index(errors, 0, reason); try s.index(errors, 1, second);
        return .{ .thrown = c.JS_DupValue(s.engine.context, try v.construct(s, try v.global(s, "AggregateError"), &.{ errors, try s.text("SQLite transaction failed and rollback failed") })) };
    };
    return .{ .thrown = c.JS_DupValue(s.engine.context, reason) };
}
fn rollbackAttempt(s: *v.Scope, adapter: c.JSValue) !void { _ = try v.invoke(s, try v.get(s, adapter, "database"), "exec", &.{try s.text("ROLLBACK")}); }
fn checkpointAttempt(s: *v.Scope, adapter: c.JSValue) !void { _ = try v.invoke(s, try v.get(s, adapter, "database"), "exec", &.{try s.text("PRAGMA wal_checkpoint(TRUNCATE)")}); }
fn close(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); const access = try v.get(&s, receiver, "access"); const run_operation = try v.get(&s, access, "run");
    const operation = try s.own(try functions.createArrow(engine, "", 0, v.callback(closeOperation), &.{receiver}));
    return c.JS_DupValue(engine.context, try v.call(&s, run_operation, access, &.{operation}));
}
fn closeOperation(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); const adapter = roots[0];
    if (s.truthy(try v.get(&s, adapter, "closed"))) return c.pi_js_undefined();
    try v.set(&s, adapter, "closed", c.pi_js_bool(engine.context, 1)); _ = try v.invoke(&s, try v.get(&s, adapter, "statements"), "clear", &.{});
    const failed: ?c.JSValue = blk: { checkpointAttempt(&s, adapter) catch |err| break :blk try s.own(try v.caught(engine, err)); break :blk null; };
    _ = try v.invoke(&s, try v.get(&s, adapter, "database"), "close", &.{});
    if (failed) |reason| return v.checked(engine, c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
    return c.pi_js_undefined();
}
fn open(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    try v.pending(engine);
    return openRun(engine, args, roots[0], state, completion, input) catch |err| {
        const reason = try v.caught(engine, err); defer engine.freeValue(reason); var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
        if (c.JS_IsObject(state.*) and s.truthy(try s.get(state.*, "configurationActive"))) return configurationFailed(&s, state.*, reason);
        return .{ .thrown = c.JS_DupValue(engine.context, reason) };
    };
}
fn openRun(engine: *em.Engine, args: []const c.JSValue, graph: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
    if (completion != .start) {
        const stage = try v.stage(&s, state.*);
        if (completion == .rejected) {
            try v.rejected(&s, state.*, input);
            if (stage == 4) return .{ .thrown = c.JS_DupValue(engine.context, try s.get(state.*, "configurationError")) };
            if (s.truthy(try s.get(state.*, "configurationActive"))) return configurationFailed(&s, state.*, input);
            return .{ .thrown = c.JS_DupValue(engine.context, input) };
        }
        return switch (stage) { 0 => openConnection(&s, state.*, graph), 1 => configure(&s, state.*, 2), 2 => configure(&s, state.*, 3), 3 => .{ .returned = c.JS_DupValue(engine.context, try s.get(state.*, "adapter")) }, 4 => .{ .thrown = c.JS_DupValue(engine.context, try s.get(state.*, "configurationError")) }, else => error.UnexpectedChordOpenStage };
    }
    const owner = try v.init(&s, state); const path = v.at(args, 0); const options = if (c.JS_IsUndefined(v.at(args, 1))) try s.object() else args[1];
    const checkpoint = try v.get(&s, options, "walAutoCheckpointPages"); try s.put(owner, "checkpoint", if (v.nullish(checkpoint)) c.JS_NewInt32(engine.context, 1000) else checkpoint);
    const timeout = try v.get(&s, options, "busyTimeoutMs"); try s.put(owner, "timeout", if (v.nullish(timeout)) c.JS_NewInt32(engine.context, 5000) else timeout); try s.put(owner, "path", path);
    if (s.equal(path, try s.text(":memory:"))) return openConnection(&s, owner, graph);
    const dirname = try s.get(graph, "dirname"); const directory = try v.call(&s, dirname, c.pi_js_undefined(), &.{path});
    const recursive = try s.object(); try s.put(recursive, "recursive", c.pi_js_bool(engine.context, 1));
    return v.wait(&s, owner, try s.get(graph, "mkdir"), c.pi_js_undefined(), &.{directory, recursive}, 0);
}
fn openConnection(s: *v.Scope, owner: c.JSValue, graph: c.JSValue) !af.Action {
    const options = try s.object(); try s.put(options, "timeout", try s.get(owner, "timeout"));
    const database_value = try v.construct(s, try s.get(graph, "DatabaseSync"), &.{try s.get(owner, "path"), options});
    try s.put(owner, "adapter", try v.construct(s, try s.get(graph, "NodeSqliteDatabase"), &.{database_value}));
    try s.put(owner, "configurationActive", c.pi_js_bool(s.engine.context, 1)); return configure(s, owner, 1);
}
fn configure(s: *v.Scope, owner: c.JSValue, next_stage: i32) !af.Action {
    const adapter = try s.get(owner, "adapter"); const exec = try v.get(s, adapter, "exec");
    const sql = switch (next_stage) { 1 => try s.text("PRAGMA journal_mode = WAL"), 2 => try s.text("PRAGMA synchronous = NORMAL"), else => try s.concat(try s.text("PRAGMA wal_autocheckpoint = "), try s.stringify(try s.get(owner, "checkpoint"))) };
    return v.wait(s, owner, exec, adapter, &.{sql}, next_stage);
}
fn configurationFailed(s: *v.Scope, owner: c.JSValue, reason: c.JSValue) !af.Action {
    try s.put(owner, "configurationActive", c.pi_js_bool(s.engine.context, 0)); try s.put(owner, "configurationError", reason);
    return closeAfterConfiguration(s, owner) catch |err| { const ignored = try v.caught(s.engine, err); s.engine.freeValue(ignored); return .{ .thrown = c.JS_DupValue(s.engine.context, reason) }; };
}
fn closeAfterConfiguration(s: *v.Scope, owner: c.JSValue) !af.Action { const adapter = try s.get(owner, "adapter"); return v.wait(s, owner, try v.get(s, adapter, "close"), adapter, &.{}, 4); }
fn noop(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_undefined(); }
