//! Persistent projection of live tasks, excluding checkpoint and outcome payloads.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const mount_mod = @import("native_durable_view_mount.zig");
const Scope = mount_mod.Scope;
const c = engine_mod.c;
const Engine = engine_mod.Engine;
fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, object, key, c.JS_DupValue(engine.context, value));
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return c.JS_IsStrictEqual(scope.engine.context, value, try scope.text(text));
}
fn node(scope: *Scope, record: c.JSValue, conversations: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const result = try scope.own(try vm.object(engine));
    inline for (.{ "id", "kind", "conversationId", "background", "abortRequested" }) |key| try put(engine, result, key, try scope.get(record, key));
    const owner = try scope.get(record, "owner");
    if (!c.JS_IsUndefined(owner)) try put(engine, result, "owner", owner);
    const original = try scope.get(record, "state");
    const status = try scope.get(original, "status");
    const state = try scope.own(try vm.object(engine));
    if (try is(scope, status, "pending") or try is(scope, status, "running") or try is(scope, status, "waiting")) {
        try put(engine, state, "status", status);
        try put(engine, state, "phase", try scope.get(try scope.get(original, "checkpoint"), "phase"));
        if (try is(scope, status, "waiting")) {
            try put(engine, state, "on", try scope.invoke(try scope.get(original, "on"), "slice", &.{}));
            try put(engine, state, "policy", try scope.get(original, "policy"));
        }
    } else {
        try put(engine, state, "status", try scope.text("completing"));
        try put(engine, state, "outcome", try scope.get(try scope.get(original, "outcome"), "status"));
    }
    try put(engine, result, "state", state);
    try put(engine, result, "conversations", conversations);
    return result;
}
fn keyOf(scope: *Scope, record: c.JSValue) !c.JSValue {
    const id = try scope.get(record, "id");
    const string = try scope.own(try js.global(scope.engine, "String"));
    return scope.own(try js.call(scope.engine, string, c.pi_js_undefined(), &.{id}));
}
fn lookup(scope: *Scope, tasks: c.JSValue, changed: c.JSValue, key: c.JSValue) !c.JSValue {
    if (c.JS_ToBool(scope.engine.context, try scope.invoke(changed, "has", &.{key})) != 0) return scope.invoke(changed, "get", &.{key});
    return scope.own(try js.getKey(scope.engine, tasks, key));
}
fn compare(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    var left: f64 = 0;
    var right: f64 = 0;
    if (argc < 2 or c.JS_ToFloat64(context, &left, argv[0]) < 0 or c.JS_ToFloat64(context, &right, argv[1]) < 0) return c.JS_ThrowInternalError(context, "Invalid task graph conversation ID");
    return c.JS_NewFloat64(context, left - right);
}
pub fn build(engine: *Engine, session: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const durable = @import("native_durable.zig");
    const backend = @import("../durable/backend/root.zig");
    const json = backend.json;
    const native = try durable.state(engine, session);
    const snapshot = try native.session_lease.?.value.storage.snapshot(engine.gpa);
    defer snapshot.destroy(engine.gpa);
    var ids: std.ArrayList(u64) = .empty;
    defer ids.deinit(engine.gpa);
    var iterator = snapshot.rows.iterator();
    while (iterator.next()) |row| {
        if (row.value_ptr.table != .task) continue;
        const status = try json.asString(try json.required(try json.required(row.value_ptr.record, "state"), "status"));
        if (std.mem.eql(u8, status, "terminal")) continue;
        try ids.append(engine.gpa, row.key_ptr.*);
    }
    std.mem.sort(u64, ids.items, {}, std.sort.asc(u64));
    const tasks = try scope.own(try vm.object(engine));
    for (ids.items) |id| {
        const record = try scope.own(try durable.jsValue(engine, snapshot.rows.get(id).?.record));
        var owned: std.ArrayList(u64) = .empty;
        defer owned.deinit(engine.gpa);
        iterator = snapshot.rows.iterator();
        while (iterator.next()) |row| {
            if (row.value_ptr.table != .conversation) continue;
            const owner = json.get(row.value_ptr.record, "owner") orelse continue;
            const task = json.get(owner, "taskId") orelse continue;
            if (try json.asInteger(task) == id) try owned.append(engine.gpa, row.key_ptr.*);
        }
        std.mem.sort(u64, owned.items, {}, std.sort.asc(u64));
        const conversations = try scope.array(&.{});
        for (owned.items) |conversation| try js.push(engine, conversations, c.JS_NewInt64(engine.context, @intCast(conversation)));
        try js.setKey(engine, tasks, try keyOf(&scope, record), try node(&scope, record, conversations));
    }
    const value = try scope.own(try vm.object(engine));
    try put(engine, value, "tasks", tasks);
    const mount = try vm.object(engine);
    errdefer engine.freeValue(mount);
    try put(engine, mount, "value", value);
    try put(engine, mount, "observers", try scope.own(try js.builtin(engine, "Set", &.{})));
    return mount;
}
pub fn advance(engine: *Engine, mount: c.JSValue, publication: c.JSValue, context: c.JSValue, report: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const before = try scope.get(mount, "value");
    const tasks = try scope.get(before, "tasks");
    const changes = try scope.get(publication, "changes");
    const changed = try scope.own(try js.builtin(engine, "Map", &.{}));
    const operations = try scope.array(&.{});
    for (0..try vm.length(engine, changes)) |index| {
        const change = try scope.item(changes, index);
        if (!try is(&scope, try scope.get(change, "type"), "task")) continue;
        const record = try scope.get(change, "value");
        const key = try keyOf(&scope, record);
        const previous = try lookup(&scope, tasks, changed, key);
        const path = try scope.array(&.{ try scope.text("tasks"), key });
        if (try is(&scope, try scope.get(try scope.get(record, "state"), "status"), "terminal")) {
            if (c.JS_IsUndefined(previous)) continue;
            try js.push(engine, operations, try scope.array(&.{ try scope.text("d"), path }));
            _ = try scope.invoke(changed, "set", &.{ key, c.pi_js_undefined() });
            continue;
        }
        const next = try node(&scope, record, if (c.JS_IsUndefined(previous)) try scope.array(&.{}) else try scope.get(previous, "conversations"));
        if (!c.JS_IsUndefined(previous)) {
            const next_text = try engine.stringify(next);
            defer engine.gpa.free(next_text);
            const previous_text = try engine.stringify(previous);
            defer engine.gpa.free(previous_text);
            if (std.mem.eql(u8, next_text, previous_text)) continue;
        }
        try js.push(engine, operations, try scope.array(&.{ try scope.text("s"), path, next }));
        _ = try scope.invoke(changed, "set", &.{ key, next });
    }
    const created = try scope.own(try js.builtin(engine, "Map", &.{}));
    const string = try scope.own(try js.global(engine, "String"));
    for (0..try vm.length(engine, changes)) |index| {
        const change = try scope.item(changes, index);
        if (!try is(&scope, try scope.get(change, "type"), "conversation")) continue;
        const record = try scope.get(change, "value");
        const owner = try scope.get(record, "owner");
        if (c.JS_IsUndefined(owner)) continue;
        const key = try scope.own(try js.call(engine, string, c.pi_js_undefined(), &.{try scope.get(owner, "taskId")}));
        if (c.JS_IsUndefined(try lookup(&scope, tasks, changed, key))) continue;
        const previous = try scope.invoke(created, "get", &.{key});
        const ids = if (c.JS_IsUndefined(previous)) try scope.array(&.{}) else previous;
        try js.push(engine, ids, try scope.get(record, "id"));
        _ = try scope.invoke(created, "set", &.{ key, ids });
    }
    const entries = try scope.invoke(created, "entries", &.{});
    const symbol = try scope.get(try scope.own(try js.global(engine, "Symbol")), "iterator");
    const rows = try scope.own(try js.collect(engine, entries, symbol));
    const comparator = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, compare, "", 2)));
    for (0..try vm.length(engine, rows)) |index| {
        const pair = try scope.item(rows, index);
        const key = try scope.item(pair, 0);
        const current = try lookup(&scope, tasks, changed, key);
        const ids = try scope.invoke(try scope.get(current, "conversations"), "concat", &.{try scope.item(pair, 1)});
        _ = try scope.invoke(ids, "sort", &.{comparator});
        try js.push(engine, operations, try scope.array(&.{ try scope.text("s"), try scope.array(&.{ try scope.text("tasks"), key, try scope.text("conversations") }), ids }));
    }
    if (try vm.length(engine, operations) == 0) return;
    const after = try scope.own(try @import("native_durable_view_delta.zig").apply(engine, before, operations));
    try put(engine, mount, "value", after);
    const frame_context = try scope.own(try @import("native_durable_context.zig").withoutAbortSignal(engine, context));
    try mount_mod.notify(&scope, try scope.get(mount, "observers"), "advance", &.{ after, operations, frame_context }, report);
}
