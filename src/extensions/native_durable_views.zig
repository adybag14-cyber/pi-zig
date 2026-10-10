//! Atomic conversation mounts shared by public states and exact-frame watches.
const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Scope = struct {
    engine: *Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    fn deinit(self: *Scope) void {
        for (self.values.items) |value| self.engine.freeValue(value);
        self.values.deinit(self.engine.gpa);
    }
    fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        self.values.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    fn get(self: *Scope, object: c.JSValue, key: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, object, key));
    }
    fn invoke(self: *Scope, object: c.JSValue, key: [:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.own(try vm.invoke(self.engine, object, key, args));
    }
};
fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, object, key, c.JS_DupValue(engine.context, value));
}
const Action = enum(c_int) { publication, close, release, advance, report };
fn callback(engine: *Engine, data: c.JSValue, action: Action, arity: c_int) !c.JSValue {
    var captures = [_]c.JSValue{data};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "", arity, @intFromEnum(action), captures.len, &captures));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, action: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return act(engine, data[0], @enumFromInt(action), (if (argc > 0) argv[0..@intCast(argc)] else &.{})) catch |err| durable.reject(engine, err);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn collect(scope: *Scope, iterable: c.JSValue) !c.JSValue {
    const symbol = try scope.get(try scope.own(try js.global(scope.engine, "Symbol")), "iterator");
    return scope.own(try js.collect(scope.engine, iterable, symbol));
}
fn item(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
fn invokeFunction(scope: *Scope, function: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return scope.own(try js.call(scope.engine, function, c.pi_js_undefined(), args));
}
fn act(engine: *Engine, owner: c.JSValue, action: Action, args: []const c.JSValue) !c.JSValue {
    if (action == .release) return releaseObserver(engine, owner);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (action == .report) {
        const report = try scope.get(owner, "onReport");
        if (c.JS_IsUndefined(report)) return c.pi_js_undefined();
        durable.contained(engine, report, &.{arg(args, 0)});
        return c.pi_js_undefined();
    }
    if (action == .advance) {
        if (c.JS_ToBool(engine.context, try scope.get(owner, "released")) != 0) return c.pi_js_undefined();
        const object = try scope.get(owner, "object");
        if (c.JS_ToBool(engine.context, try scope.get(owner, "watch")) != 0) {
            try @import("native_durable_observation.zig").advanceProjection(engine, object, arg(args, 0), arg(args, 1), arg(args, 2));
        } else try @import("native_durable_state.zig").advanceProjection(engine, object, arg(args, 0), arg(args, 2));
        return c.pi_js_undefined();
    }
    const mounts = try scope.get(owner, "mounts");
    if (action == .publication) {
        if (c.JS_ToBool(engine.context, try scope.get(owner, "closed")) != 0) return c.pi_js_undefined();
        const entries = try scope.invoke(mounts, "entries", &.{});
        const rows = try collect(&scope, entries);
        const report = try scope.get(owner, "report");
        for (0..try vm.length(engine, rows)) |index| {
            const pair = try item(&scope, rows, index);
            const id = try item(&scope, pair, 0);
            if (c.JS_IsUndefined(id)) {
                try @import("native_durable_task_graph.zig").advance(engine, try item(&scope, pair, 1), arg(args, 0), arg(args, 1), report);
            } else try @import("native_durable_view_mount.zig").advance(engine, id, try item(&scope, pair, 1), arg(args, 0), arg(args, 1), report);
        }
        return c.pi_js_undefined();
    }
    if (action == .close) {
        if (c.JS_ToBool(engine.context, try scope.get(owner, "closed")) != 0) return c.pi_js_undefined();
        try put(engine, owner, "closed", c.pi_js_bool(engine.context, 1));
        const session = try scope.get(owner, "session");
        const native = try durable.state(engine, session);
        const rows = try collect(&scope, try scope.invoke(mounts, "values", &.{}));
        for (0..try vm.length(engine, rows)) |index| {
            const mount = try item(&scope, rows, index);
            const observers = try collect(&scope, try scope.get(mount, "observers"));
            for (0..try vm.length(engine, observers)) |observer_index| {
                const observer = try item(&scope, observers, observer_index);
                const object = try scope.get(observer, "object");
                if (c.JS_ToBool(engine.context, try scope.get(observer, "watch")) != 0) {
                    try @import("native_durable_observation.zig").closeProjection(engine, object, native.failure_reason);
                } else try @import("native_durable_state.zig").disposeProjection(engine, object);
            }
        }
        _ = try scope.invoke(mounts, "clear", &.{});
        const release = try scope.get(owner, "unsubscribeCommits");
        if (c.JS_IsFunction(engine.context, release)) _ = try invokeFunction(&scope, release, &.{});
        return c.pi_js_undefined();
    }
    return error.InvalidConversationViewAction;
}
fn releaseObserver(engine: *Engine, owner: c.JSValue) !c.JSValue {
    // Detaching a successful observer must not require a host allocation,
    // particularly while unwinding an earlier failed allocation.
    const released = try vm.get(engine, owner, "released");
    defer engine.freeValue(released);
    if (c.JS_ToBool(engine.context, released) != 0) return c.pi_js_undefined();
    const mount = try vm.get(engine, owner, "mount");
    defer engine.freeValue(mount);
    const observers = try vm.get(engine, mount, "observers");
    defer engine.freeValue(observers);
    const removed = try vm.invoke(engine, observers, "delete", &.{owner});
    engine.freeValue(removed);
    const size = try vm.get(engine, observers, "size");
    defer engine.freeValue(size);
    if (try durable.number(engine, size) == 0) {
        const owner_store = try vm.get(engine, owner, "store");
        defer engine.freeValue(owner_store);
        const mounts = try vm.get(engine, owner_store, "mounts");
        defer engine.freeValue(mounts);
        const id = try vm.get(engine, owner, "id");
        defer engine.freeValue(id);
        const current = try vm.invoke(engine, mounts, "get", &.{id});
        defer engine.freeValue(current);
        if (c.JS_IsStrictEqual(engine.context, current, mount)) {
            const deleted = try vm.invoke(engine, mounts, "delete", &.{id});
            engine.freeValue(deleted);
        }
    }
    try put(engine, owner, "released", c.pi_js_bool(engine.context, 1));
    return c.pi_js_undefined();
}
fn store(engine: *Engine, session: c.JSValue, options: c.JSValue) !c.JSValue {
    const native = try durable.state(engine, session);
    if (native.conversation_views) |views| return c.JS_DupValue(engine.context, views);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "session", session);
    try put(engine, result, "mounts", try scope.own(try js.builtin(engine, "Map", &.{})));
    try put(engine, result, "onReport", try scope.get(options, "onReport"));
    try @import("native_tool_info.zig").putData(engine, result, "report", try callback(engine, result, .report, 1));
    const publication = try scope.own(try callback(engine, result, .publication, 2));
    const close = try scope.own(try callback(engine, result, .close, 0));
    const release = try scope.own(try durable.observeCommitted(native, session, publication));
    errdefer _ = invokeFunction(&scope, release, &.{}) catch {};
    try put(engine, result, "unsubscribeCommits", release);
    try put(engine, result, "unsubscribeClose", try scope.own(try durable.subscribe(native, session, .subscribeClose, close)));
    native.conversation_views = c.JS_DupValue(engine.context, result);
    return result;
}
pub fn acquire(engine: *Engine, session: c.JSValue, options: c.JSValue, id: c.JSValue, context: c.JSValue, watch: bool) !c.JSValue {
    return acquireMode(engine, session, options, id, context, @intFromBool(watch));
}
pub fn acquireEvents(engine: *Engine, session: c.JSValue, options: c.JSValue, id: c.JSValue, context: c.JSValue) !c.JSValue {
    return acquireMode(engine, session, options, id, context, 2);
}
fn acquireMode(engine: *Engine, session: c.JSValue, options: c.JSValue, id: c.JSValue, context: c.JSValue, mode: c_int) !c.JSValue {
    const owner = try store(engine, session, options);
    defer engine.freeValue(owner);
    var data = [_]c.JSValue{ owner, id, context };
    const queued = try engine.checked(c.JS_NewCFunctionData2(engine.context, attach, "", 0, mode, data.len, &data));
    defer engine.freeValue(queued);
    return durable.enqueue(engine, session, queued);
}
fn attach(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, watch: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return attachOwned(engine, data[0], data[1], data[2], watch) catch |err| durable.reject(engine, err);
}
fn attachOwned(engine: *Engine, owner: c.JSValue, id: c.JSValue, context: c.JSValue, mode: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try durable.checkCancellation(engine, context);
    const session = try scope.get(owner, "session");
    if (c.JS_ToBool(engine.context, try scope.get(owner, "closed")) != 0) return @import("native_sdk.zig").sourceError(engine, "Harness is closed");
    const mounts = try scope.get(owner, "mounts");
    var mount = try scope.invoke(mounts, "get", &.{id});
    if (c.JS_IsUndefined(mount)) mount = try scope.own(if (c.JS_IsUndefined(id)) try @import("native_durable_task_graph.zig").build(engine, session) else try build(engine, session, id, context));
    const observer = try scope.own(try vm.object(engine));
    inline for (.{ .{ "store", owner }, .{ "mount", mount }, .{ "id", id } }) |field| try put(engine, observer, field[0], field[1]);
    try put(engine, observer, "watch", c.pi_js_bool(engine.context, @intFromBool(mode != 0)));
    const release = try scope.own(try callback(engine, observer, .release, 0));
    const report = try scope.get(owner, "report");
    const value = try scope.get(mount, "value");
    var events: ?@import("native_durable_events.zig").Projection = null;
    defer if (events) |projection| {
        engine.freeValue(projection.watch);
        engine.freeValue(projection.publication);
    };
    const object = if (mode == 2) blk: {
        events = try @import("native_durable_events.zig").create(engine, session, id, value, context, release, report);
        break :blk events.?.public;
    } else if (mode == 1) try @import("native_durable_observation.zig").createProjection(engine, session, value, context, release, report) else try @import("native_durable_state.zig").createProjection(engine, session, value, release, report);
    errdefer engine.freeValue(object);
    errdefer _ = invokeFunction(&scope, release, &.{}) catch {};
    try put(engine, observer, "object", if (events) |projection| projection.watch else object);
    if (events) |projection| {
        try put(engine, observer, "publication", projection.publication);
    } else try @import("native_tool_info.zig").putData(engine, observer, "advance", try callback(engine, observer, .advance, 3));
    try durable.checkCancellation(engine, context);
    if (c.JS_ToBool(engine.context, try scope.get(owner, "closed")) != 0) return @import("native_sdk.zig").sourceError(engine, "Harness is closed");
    _ = try scope.invoke(mounts, "set", &.{ id, mount });
    _ = try scope.invoke(try scope.get(mount, "observers"), "add", &.{observer});
    return object;
}
fn build(engine: *Engine, session: c.JSValue, id: c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const native = try durable.state(engine, session);
    var record = (try native.session_lease.?.value.storage.readTableRecord(engine.gpa, .conversation, try durable.number(engine, id))) orelse {
        const number = try engine.toString(id);
        defer engine.gpa.free(number);
        const message = try std.fmt.allocPrint(engine.gpa, "Conversation {s} does not exist", .{number});
        defer engine.gpa.free(message);
        return @import("native_sdk.zig").sourceError(engine, message);
    };
    defer record.deinit();
    const value = try scope.own(try vm.object(engine));
    try @import("native_tool_info.zig").putData(engine, value, "conversation", try durable.jsValue(engine, record.value));
    const view = try scope.own(try @import("native_durable_context_view.zig").read(engine, session, id, context, c.pi_js_undefined(), null));
    try put(engine, value, "entries", try scope.get(view, "entries"));
    const docs = try scope.own(try vm.object(engine));
    const incarnations = try scope.own(try js.builtin(engine, "Map", &.{}));
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    for ([_][:0]const u8{ "AgentDoc", "LiveDoc", "InboxDoc", "ProviderDoc", "UsageDoc" }) |key| {
        const token = try scope.get(exports, key);
        var observed = (try @import("native_durable_documents.zig").observeState(engine, session, &.{ token, id, context })) orelse continue;
        defer observed.record.deinit();
        defer engine.freeValue(observed.value);
        defer engine.freeValue(observed.context);
        const definition = try scope.get(token, "definition");
        const kind = try scope.get(definition, "kind");
        try js.setKey(engine, docs, kind, observed.value);
        const incarnation = try scope.own(try vm.object(engine));
        try @import("native_tool_info.zig").putData(engine, incarnation, "id", c.JS_NewInt64(engine.context, @intCast(try @import("../durable/backend/json.zig").asInteger(try @import("../durable/backend/json.zig").required(observed.record.value, "id")))));
        try put(engine, incarnation, "version", c.JS_NewInt64(engine.context, @intCast(observed.version)));
        _ = try scope.invoke(incarnations, "set", &.{ kind, incarnation });
    }
    try put(engine, value, "docs", docs);
    const mount = try vm.object(engine);
    errdefer engine.freeValue(mount);
    try put(engine, mount, "value", value);
    try put(engine, mount, "docs", incarnations);
    try put(engine, mount, "observers", try scope.own(try js.builtin(engine, "Set", &.{})));
    return mount;
}
