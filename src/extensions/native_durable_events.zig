//! Public event stream lifecycle over the shared atomic conversation mount.
const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const translate = @import("native_durable_event_translate.zig");
const observation = @import("native_durable_observation.zig");
const Scope = @import("native_durable_view_mount.zig").Scope;
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Projection = struct { public: c.JSValue, watch: c.JSValue, publication: c.JSValue };
const Action = enum(c_int) { publication, replacement, start, stop, deliver };
fn put(scope: *Scope, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(scope.engine, object, key, c.JS_DupValue(scope.engine.context, value));
}
fn callback(engine: *Engine, data: c.JSValue, action: Action, name: [:0]const u8, arity: c_int) !c.JSValue {
    var captures = [_]c.JSValue{data};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, name, arity, @intFromEnum(action), 1, &captures));
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return act(engine, data[0], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| durable.reject(engine, err);
}
fn act(engine: *Engine, owner: c.JSValue, action: Action, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (action == .deliver) return js.call(engine, owner, c.pi_js_undefined(), &.{ argument(args, 0), argument(args, 2) });
    if (action == .replacement) {
        const snapshot = try scope.own(try translate.snapshotOf(engine, try scope.get(owner, "current")));
        return c.JS_DupValue(engine.context, try scope.array(&.{snapshot}));
    }
    const watch = try scope.get(owner, "watch");
    if (action == .stop) return vm.invoke(engine, watch, "stop", &.{});
    if (action == .start) {
        const listener = try scope.own(try callback(engine, argument(args, 0), .deliver, "", 3));
        return vm.invoke(engine, watch, "start", &.{listener});
    }
    try put(&scope, owner, "current", argument(args, 1));
    const events = try scope.own(try translate.translate(engine, try scope.get(owner, "conversation"), argument(args, 0), argument(args, 1), argument(args, 2), argument(args, 3), try scope.get(owner, "held")));
    if (try vm.length(engine, events) > 0) try observation.advanceProjection(engine, watch, events, try scope.array(&.{}), argument(args, 4));
    return c.pi_js_undefined();
}
pub fn create(engine: *Engine, session: c.JSValue, conversation: c.JSValue, initial: c.JSValue, context: c.JSValue, release: c.JSValue, report: c.JSValue) !Projection {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.own(try vm.object(engine));
    try put(&scope, owner, "conversation", conversation);
    try put(&scope, owner, "current", initial);
    const held = try scope.own(try js.builtin(engine, "Set", &.{}));
    try put(&scope, owner, "held", held);
    const native = try durable.state(engine, session);
    const snapshot = try native.session_lease.?.value.storage.snapshot(engine.gpa);
    defer snapshot.destroy(engine.gpa);
    const json = @import("../durable/backend/json.zig");
    const id = try durable.number(engine, conversation);
    var rows = snapshot.rows.iterator();
    while (rows.next()) |row| {
        if (row.value_ptr.table != .task) continue;
        const record = row.value_ptr.record;
        if (try json.asInteger(try json.required(record, "conversationId")) != id or !std.mem.eql(u8, try json.asString(try json.required(record, "kind")), "pi.generation") or !std.mem.eql(u8, try json.asString(try json.required(try json.required(record, "state"), "status")), "completing")) continue;
        _ = try scope.invoke(held, "add", &.{c.JS_NewInt64(engine.context, @intCast(row.key_ptr.*))});
    }
    const watch = try observation.createProjection(engine, session, try scope.array(&.{}), context, release, report);
    errdefer engine.freeValue(watch);
    try put(&scope, owner, "watch", watch);
    const replace = try scope.own(try callback(engine, owner, .replacement, "", 0));
    try observation.replaceProjectionOverflow(engine, watch, replace);
    const publication = try callback(engine, owner, .publication, "", 5);
    errdefer engine.freeValue(publication);
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try put(&scope, result, "snapshot", try scope.own(try translate.snapshotOf(engine, initial)));
    try @import("native_tool_info.zig").putData(engine, result, "start", try callback(engine, owner, .start, "start", 1));
    try @import("native_tool_info.zig").putData(engine, result, "stop", try callback(engine, owner, .stop, "stop", 0));
    try put(&scope, result, "closed", try scope.get(watch, "closed"));
    return .{ .public = result, .watch = watch, .publication = publication };
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, exports, "watchEvents", try engine.checked(c.JS_NewCFunction(engine.context, acquire, "watchEvents", 3)));
}
fn acquire(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return acquireOwned(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| durable.rejectedPromise(engine, err);
}
fn acquireOwned(engine: *Engine, args: []const c.JSValue) !c.JSValue {
    const owner = @import("native_durable_harness.zig").state(engine, argument(args, 0)) catch {
        const pending = c.JS_GetException(engine.context);
        engine.freeValue(pending);
        return @import("native_sdk.zig").sourceError(engine, "Not a Harness");
    };
    if (owner.conversation != null) return @import("native_sdk.zig").sourceError(engine, "Not a Harness");
    return @import("native_durable_views.zig").acquireEvents(engine, owner.session, owner.options, argument(args, 1), argument(args, 2));
}
