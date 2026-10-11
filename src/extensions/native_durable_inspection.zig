//! Complete public inspection on the actual Session read line and Storage API.
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const tasks = @import("native_durable_tasks.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_durable_view_mount.zig").Scope;
const c = engine_mod.c;
const Engine = engine_mod.Engine;

fn put(engine: *Engine, value: c.JSValue, key: [:0]const u8, field: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, value, key, c.JS_DupValue(engine.context, field));
}
pub fn missingMigration(engine: *Engine, kind: c.JSValue, version: c.JSValue, from: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.own(try js.global(engine, "Error"));
    const message = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.text("Task "), kind, try scope.text(" version "), version, try scope.text(" has no migration from "), from }));
    var args = [_]c.JSValue{message};
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
}
pub fn inspect(engine: *Engine, harness: c.JSValue, session: c.JSValue, options: c.JSValue, context: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{ harness, session, options, context };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, queued, 0, 0, data.len, &data));
    defer engine.freeValue(callback);
    return durable.enqueueRead(engine, session, callback, context);
}
fn queued(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return read(engine, data[0], data[1], data[2], data[3]) catch |err| durable.reject(engine, err);
}
fn read(engine: *Engine, harness: c.JSValue, session: c.JSValue, options: c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const manager = (try tasks.getManager(engine, session)).retain();
    defer manager.release();
    // Capture before the real loadScopes await, as Source does. Registry edits
    // during a Storage await cannot substitute a different fit snapshot.
    const registry = try scope.get(options, "registry");
    const snapshot = try scope.invoke(registry, "snapshot", &.{});
    var native = try manager.inspectionSnapshot();
    defer native.deinit();
    const result = try scope.own(try durable.jsValue(engine, native.value));
    const live = try scope.get(result, "tasks");
    for (0..try vm.length(engine, live)) |index| {
        const item = try scope.item(live, index);
        const state = try scope.get(item, "state");
        if (!c.JS_IsStrictEqual(engine.context, try scope.get(state, "kind"), try scope.text("_fit"))) continue;
        const record = try scope.get(item, "record");
        try put(engine, item, "state", try scope.own(try fit(engine, manager, snapshot, record)));
    }
    const submissions = try scope.array(&.{});
    for ([_][]const u8{ "queued", "placed" }) |status| {
        var cursor = c.pi_js_undefined();
        while (true) {
            // Source uses the public, observable Storage receiver, caller
            // context and opaque cursor, not a privileged native snapshot.
            const storage = try scope.get(harness, "storage");
            const filter = try scope.own(try vm.object(engine));
            try put(engine, filter, "status", try scope.text(status));
            const pending = try scope.invoke(storage, "scanSubmissions", &.{ filter, c.JS_NewInt32(engine.context, 256), cursor, context });
            const page = try scope.own(try awaitBoundary(engine, pending));
            const values = try scope.get(page, "items");
            for (0..try vm.length(engine, values)) |index| try js.push(engine, submissions, try scope.item(values, index));
            cursor = try scope.get(page, "next");
            if (c.JS_IsUndefined(cursor)) break;
        }
    }
    const compare = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, compareSubmissions, "", 2)));
    _ = try scope.invoke(submissions, "sort", &.{compare});
    try put(engine, result, "submissions", submissions);
    return c.JS_DupValue(engine.context, result);
}
fn fit(engine: *Engine, manager: *tasks.Manager, snapshot: c.JSValue, record: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try vm.object(engine);
    errdefer engine.freeValue(state);
    const kind = try scope.get(record, "kind");
    const token = try scope.invoke(snapshot, "task", &.{kind});
    try put(engine, state, "kind", try scope.text("blocked"));
    if (c.JS_IsUndefined(token)) {
        try put(engine, state, "reason", try scope.text("missing_task"));
        return state;
    }
    const definition = try scope.get(token, "definition");
    const version = try scope.get(definition, "version");
    const from = try scope.get(record, "version");
    if (c.JS_IsStrictEqual(engine.context, version, from)) {
        try put(engine, state, "kind", try scope.text("ready"));
        try put(engine, state, "migrates", c.pi_js_bool(engine.context, 0));
        return state;
    }
    const older = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 4, version, from)));
    if (c.JS_ToBool(engine.context, older) != 0) {
        try put(engine, state, "reason", try scope.text("task_too_old"));
        return state;
    }
    if (manager.inspectionMigrationError(try durable.number(engine, try scope.get(record, "id")), token)) |reason| {
        try put(engine, state, "reason", try scope.text("migration_failed"));
        try put(engine, state, "error", reason);
        return state;
    }
    if (c.JS_IsUndefined(try scope.get(definition, "migrate"))) {
        try put(engine, state, "reason", try scope.text("migration_failed"));
        try put(engine, state, "error", try scope.own(try missingMigration(engine, kind, version, from)));
        return state;
    }
    try put(engine, state, "kind", try scope.text("ready"));
    try put(engine, state, "migrates", c.pi_js_bool(engine.context, 1));
    return state;
}
fn awaitBoundary(engine: *Engine, value: c.JSValue) !c.JSValue {
    const ready = try engine.checked(c.JS_PiPromiseResolve(engine.context, value));
    defer engine.freeValue(ready);
    const pending = try engine.checked(c.JS_PromiseThen(engine.context, ready, c.pi_js_undefined(), c.pi_js_undefined()));
    defer engine.freeValue(pending);
    return engine.awaitValue(pending);
}
fn compareSubmissions(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (argc < 2) return c.JS_NewInt32(context, 0);
    return compareIds(engine, argv[0], argv[1]) catch |err| durable.reject(engine, err);
}
fn compareIds(engine: *Engine, left: c.JSValue, right: c.JSValue) !c.JSValue {
    const lhs = try vm.get(engine, left, "id");
    defer engine.freeValue(lhs);
    const rhs = try vm.get(engine, right, "id");
    defer engine.freeValue(rhs);
    return engine.checked(c.JS_PiBinaryOperator(engine.context, 1, lhs, rhs));
}
