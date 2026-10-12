//! CodeMode's durable transaction boundaries. These compiled continuations use
//! the real ToolExecutionApi and document drafts; no VM is started here.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const vm = @import("native_values.zig");
const awaiting = @import("native_durable_await.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const strict_json = @import("native_chord_json.zig");
const Engine = em.Engine;
const c = em.c;
const Operation = enum(c_int) { initialize, fingerprint, batch, decide, complete, directory_read, directory_set };
const Stage = enum(c_int) { run, initial_store, initial_journal, batch_journal, complete_store };

fn initial(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = scope.object() catch |err| return @import("native_durable.zig").reject(engine, err);
    if (magic == 1) scope.put(result, "entries", scope.array() catch |err| return @import("native_durable.zig").reject(engine, err)) catch |err| return @import("native_durable.zig").reject(engine, err);
    if (magic == 2) scope.put(result, "values", scope.object() catch |err| return @import("native_durable.zig").reject(engine, err)) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.JS_DupValue(context, result);
}

/// Owned private bundle. Capture Promise intrinsics once, alongside the actual
/// document tokens, so later replacement of global Promise cannot alter await.
pub fn createDocuments(engine: *Engine, durable_exports: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bundle = try scope.object();
    inline for (.{ .{ "run", "pi.codemode.run" }, .{ "journal", "pi.codemode.journal" }, .{ "store", "pi.codemode.store" } }, 0..) |spec, index| {
        const definition = try scope.object();
        try scope.put(definition, "kind", try scope.text(spec[1]));
        try scope.put(definition, "version", c.JS_NewInt32(engine.context, 1));
        try scope.put(definition, "scope", try scope.text(if (index == 2) "conversation" else "task"));
        try scope.put(definition, "initial", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, initial, "initial", 0, @intCast(index), 0, null))));
        if (index == 2) {
            try scope.put(definition, "history", try scope.text("rewindable"));
            try scope.put(definition, "fork", try scope.text("asOf"));
        }
        try scope.put(bundle, spec[0], try scope.invoke(durable_exports, "defineDoc", &.{definition}));
    }
    var captured = try awaiting.Intrinsics.init(engine);
    defer captured.deinit(engine);
    try scope.put(bundle, "promiseConstructor", captured.constructor);
    try scope.put(bundle, "promiseResolve", captured.resolve);
    try scope.put(bundle, "promiseThen", captured.then_function);
    return c.JS_DupValue(engine.context, bundle);
}

fn copy(scope: *Scope, value: c.JSValue, omit: bool) !c.JSValue {
    const options = try scope.object();
    if (omit) try scope.put(options, "omitUndefinedProperties", c.pi_js_bool(scope.engine.context, 1));
    return scope.own(try strict_json.copyJson(scope.engine, value, options));
}
fn intrinsic(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    const docs = try scope.get(state, "documents");
    return .{ .constructor = try scope.get(docs, "promiseConstructor"), .resolve = try scope.get(docs, "promiseResolve"), .then_function = try scope.get(docs, "promiseThen") };
}
fn wait(scope: *Scope, state: c.JSValue, promise: c.JSValue, stage: Stage) !c.JSValue {
    var captured = try intrinsic(scope, state);
    return awaiting.continueWith(advance, scope.engine, &captured, state, promise, @intFromEnum(stage));
}
fn document(scope: *Scope, state: c.JSValue, name: [*:0]const u8, conversation: bool, stage: Stage) !c.JSValue {
    const api = try scope.get(state, "api");
    const token = try scope.get(try scope.get(state, "documents"), name);
    const id = try scope.get(api, if (conversation) "conversationId" else "taskId");
    return wait(scope, state, try scope.invoke(try scope.get(state, "transaction"), "doc", &.{ token, id }), stage);
}
fn commit(engine: *Engine, docs: c.JSValue, api: c.JSValue, context: c.JSValue, operation: Operation, payload: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    inline for (.{ .{ "documents", docs }, .{ "api", api }, .{ "context", context }, .{ "payload", payload } }) |field| try scope.put(state, field[0], field[1]);
    try scope.put(state, "operation", c.JS_NewInt32(engine.context, @intFromEnum(operation)));
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, transaction, "", 1, @intFromEnum(operation), data.len, &data)));
    return c.JS_DupValue(engine.context, try scope.invoke(api, "commit", &.{ callback, context }));
}
pub fn initialize(engine: *Engine, docs: c.JSValue, api: c.JSValue, context: c.JSValue, start: c.JSValue) !c.JSValue {
    return commit(engine, docs, api, context, .initialize, start);
}
pub fn fingerprint(engine: *Engine, docs: c.JSValue, api: c.JSValue, context: c.JSValue, value: c.JSValue) !c.JSValue {
    return commit(engine, docs, api, context, .fingerprint, value);
}
/// payload = { acks: [[seq, issued], ...], entries: [{id, at, global?}, ...] }.
pub fn batch(engine: *Engine, docs: c.JSValue, api: c.JSValue, context: c.JSValue, payload: c.JSValue) !c.JSValue {
    return commit(engine, docs, api, context, .batch, payload);
}
pub fn decide(engine: *Engine, docs: c.JSValue, api: c.JSValue, context: c.JSValue, result: c.JSValue) !c.JSValue {
    return commit(engine, docs, api, context, .decide, result);
}
/// payload = { result, writes? }. The outcome and all successful store writes
/// are assembled in this one real transaction; an existing outcome wins.
pub fn complete(engine: *Engine, docs: c.JSValue, api: c.JSValue, context: c.JSValue, payload: c.JSValue) !c.JSValue {
    return commit(engine, docs, api, context, .complete, payload);
}
pub fn outputDirectory(engine: *Engine, docs: c.JSValue, api: c.JSValue, context: c.JSValue, created: ?c.JSValue) !c.JSValue {
    return commit(engine, docs, api, context, if (created != null) .directory_set else .directory_read, created orelse c.pi_js_undefined());
}
fn transaction(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    scope.put(data[0], "transaction", if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| return @import("native_durable.zig").reject(engine, err);
    const op = readOperation(&scope, data[0]) catch |err| return @import("native_durable.zig").reject(engine, err);
    return document(&scope, data[0], if (op == .batch) "journal" else "run", false, if (op == .batch) .batch_journal else .run) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn readOperation(scope: *Scope, state: c.JSValue) !Operation {
    var raw: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &raw, try scope.get(state, "operation")) < 0) return js.capture(scope.engine);
    return @enumFromInt(raw);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw_stage: c_int) anyerror!c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const op = try readOperation(&scope, state);
    const payload = try scope.get(state, "payload");
    switch (@as(Stage, @enumFromInt(raw_stage))) {
        .run => {
            try scope.put(state, "run", value);
            const recorded = try scope.get(value, "result");
            if (op == .initialize) {
                if (!c.JS_IsUndefined(recorded)) {
                    const done = try scope.object();
                    try scope.put(done, "done", try copy(&scope, recorded, false));
                    return c.JS_DupValue(engine.context, done);
                }
                const start = try scope.get(value, "start");
                try scope.put(state, "rerun", c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(start))));
                if (c.JS_IsUndefined(start)) return document(&scope, state, "store", true, .initial_store);
                return document(&scope, state, "journal", false, .initial_journal);
            }
            if (op == .fingerprint) {
                const start = try scope.get(value, "start");
                if (!c.JS_IsUndefined(start)) try scope.set(start, "fingerprint", payload);
            } else if (op == .decide) {
                if (c.JS_IsUndefined(recorded) or c.JS_IsNull(recorded)) try scope.set(value, "result", try copy(&scope, payload, true));
                return c.JS_DupValue(engine.context, payload);
            } else if (op == .complete) {
                if (!c.JS_IsUndefined(recorded)) return c.JS_DupValue(engine.context, recorded);
                try scope.set(value, "result", try copy(&scope, try scope.get(payload, "result"), true));
                const writes = try scope.get(payload, "writes");
                if (!c.JS_IsUndefined(writes)) {
                    const keys = try scope.invoke(try scope.global("Object"), "keys", &.{try scope.get(writes, "set")});
                    if (try vm.length(engine, keys) > 0 or try vm.length(engine, try scope.get(writes, "delete")) > 0) return document(&scope, state, "store", true, .complete_store);
                }
                return c.JS_DupValue(engine.context, try scope.get(payload, "result"));
            } else if (op == .directory_read or op == .directory_set) {
                const directory = try scope.get(value, "outputDir");
                if (op == .directory_set and (c.JS_IsUndefined(directory) or c.JS_IsNull(directory))) {
                    try scope.set(value, "outputDir", payload);
                    return c.JS_DupValue(engine.context, payload);
                }
                return c.JS_DupValue(engine.context, directory);
            }
        },
        .initial_store => {
            const start = try copy(&scope, payload, false);
            try scope.set(start, "store", try copy(&scope, try scope.get(value, "values"), false));
            try scope.set(try scope.get(state, "run"), "start", start);
            return document(&scope, state, "journal", false, .initial_journal);
        },
        .initial_journal => {
            const found = try scope.object();
            try scope.put(found, "start", try copy(&scope, try scope.get(try scope.get(state, "run"), "start"), false));
            try scope.put(found, "journal", try copy(&scope, try scope.get(value, "entries"), false));
            try scope.put(found, "firstIssued", try scope.get(value, "firstIssued"));
            try scope.put(found, "rerun", try scope.get(state, "rerun"));
            return c.JS_DupValue(engine.context, found);
        },
        .batch_journal => {
            const entries = try scope.get(value, "entries");
            const acks = try scope.get(payload, "acks");
            for (0..try vm.length(engine, acks)) |index| {
                const ack = try item(&scope, acks, index);
                var seq: u32 = 0;
                if (c.JS_ToUint32(engine.context, &seq, try item(&scope, ack, 0)) < 0) return js.capture(engine);
                const issued = try item(&scope, ack, 1);
                if (seq == 0) {
                    const first = try scope.get(value, "firstIssued");
                    if (c.JS_IsUndefined(first) or c.JS_IsNull(first)) try scope.set(value, "firstIssued", issued);
                } else {
                    const entry = try item(&scope, entries, seq - 1);
                    if (!c.JS_IsUndefined(entry) and c.JS_IsUndefined(try scope.get(entry, "issuedAfter"))) try scope.set(entry, "issuedAfter", issued);
                }
            }
            const pending = try scope.get(payload, "entries");
            for (0..try vm.length(engine, pending)) |index| {
                const item_value = try item(&scope, pending, index);
                const entry = try scope.object();
                try scope.put(entry, "id", try scope.get(item_value, "id"));
                try scope.put(entry, "at", try scope.get(item_value, "at"));
                const global = try scope.get(item_value, "global");
                if (!c.JS_IsUndefined(global)) try scope.put(entry, "global", global);
                _ = try scope.invoke(entries, "push", &.{try copy(&scope, entry, true)});
            }
        },
        .complete_store => {
            const values = try scope.get(value, "values");
            const writes = try scope.get(payload, "writes");
            const deleted = try scope.get(writes, "delete");
            for (0..try vm.length(engine, deleted)) |index| {
                const key = c.JS_ValueToAtom(engine.context, try item(&scope, deleted, index));
                if (key == c.JS_ATOM_NULL) return js.capture(engine);
                defer c.JS_FreeAtom(engine.context, key);
                if (c.JS_DeleteProperty(engine.context, values, key, c.JS_PROP_THROW) < 0) return js.capture(engine);
            }
            const pairs = try scope.invoke(try scope.global("Object"), "entries", &.{try scope.get(writes, "set")});
            for (0..try vm.length(engine, pairs)) |index| {
                const pair = try item(&scope, pairs, index);
                const key = c.JS_ValueToAtom(engine.context, try item(&scope, pair, 0));
                if (key == c.JS_ATOM_NULL) return js.capture(engine);
                defer c.JS_FreeAtom(engine.context, key);
                if (c.JS_SetProperty(engine.context, values, key, c.JS_DupValue(engine.context, try item(&scope, pair, 1))) < 0) return js.capture(engine);
            }
            return c.JS_DupValue(engine.context, try scope.get(payload, "result"));
        },
    }
    return c.pi_js_undefined();
}
fn item(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
