//! ReadableStream's actual custom async iterator, distinct from async generators.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const core = @import("native_readable_byte_stream.zig");
const async_value = @import("native_agent_async.zig");
const h = @import("native_stream_helpers.zig");
const c = js.c;
const Stage = enum(c_int) { next, returned, read, cancelled };
fn packet(scope: *Scope, value: c.JSValue, done: bool) !c.JSValue {
    const object = try scope.object();
    // Node's next close/return packets insert done before value, while chunks
    // insert value before done. Both preserve the actual supplied value.
    if (done) try scope.put(object, "done", c.pi_js_bool(scope.engine.context, 1));
    try scope.put(object, "value", value);
    if (!done) try scope.put(object, "done", c.pi_js_bool(scope.engine.context, 0));
    return object;
}
fn begin(scope: *Scope, owner: c.JSValue, stage: Stage) !void {
    const data = try scope.get(owner, "agent");
    const value = try scope.get(owner, "value");
    if (scope.truthy(try scope.get(data, "done"))) return async_value.settle(scope.engine, owner, false, try packet(scope, if (stage == .returned) value else c.pi_js_undefined(), true));
    const bindings = try scope.get(data, "bindings");
    const reader = try scope.get(data, "reader");
    if (stage == .next) {
        const reading = try core.readNative(scope, bindings, reader, &.{});
        return async_value.wait(continued, scope.engine, owner, reading, @intFromEnum(Stage.read));
    }
    try scope.put(data, "done", c.pi_js_bool(scope.engine.context, 1));
    if (!scope.truthy(try scope.get(data, "preventCancel"))) {
        const cancelled = core.cancelNative(scope, bindings, try scope.get(data, "stream"), value) catch |err| {
            try core.releaseReaderNative(scope, bindings, reader);
            return async_value.rejectError(scope.engine, owner, err);
        };
        try core.releaseReaderNative(scope, bindings, reader);
        return async_value.wait(continued, scope.engine, owner, cancelled, @intFromEnum(Stage.cancelled));
    }
    try core.releaseReaderNative(scope, bindings, reader);
    try async_value.settle(scope.engine, owner, false, try packet(scope, value, true));
}
fn continued(engine: *js.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (stage == .next or stage == .returned) return begin(&scope, owner, stage);
    const data = try scope.get(owner, "agent");
    if (stage == .cancelled) return async_value.settle(engine, owner, rejected, if (rejected) value else try packet(&scope, try scope.get(owner, "value"), true));
    try scope.put(data, "current", c.pi_js_undefined());
    const done = rejected or scope.truthy(try scope.get(value, "done"));
    if (done) {
        try scope.put(data, "done", c.pi_js_bool(engine.context, 1));
        try core.releaseReaderNative(&scope, try scope.get(data, "bindings"), try scope.get(data, "reader"));
    }
    try async_value.settle(engine, owner, rejected, if (rejected) value else try packet(&scope, if (done) c.pi_js_undefined() else try scope.get(value, "value"), done));
}
fn advance(scope: *Scope, data: c.JSValue, value: c.JSValue, returned: bool) !c.JSValue {
    const pending = try async_value.create(scope.engine, data);
    defer scope.engine.freeValue(pending.owner);
    var offered = false;
    errdefer if (!offered) scope.engine.freeValue(pending.promise);
    try scope.put(pending.owner, "value", value);
    const current = try scope.get(data, "current");
    const first = !scope.truthy(try scope.get(data, "started"));
    try scope.put(data, "started", c.pi_js_bool(scope.engine.context, 1));
    try scope.put(data, "current", pending.promise);
    const stage: Stage = if (returned) .returned else .next;
    if (!c.JS_IsUndefined(current) or (first and !returned)) {
        // Each queued operation runs after either outcome of the preceding
        // operation. The first next has Node's actual initial microtask delay.
        async_value.wait(continued, scope.engine, pending.owner, current, @intFromEnum(stage)) catch |err| try async_value.rejectError(scope.engine, pending.owner, err);
    } else begin(scope, pending.owner, stage) catch |err| try async_value.rejectError(scope.engine, pending.owner, err);
    offered = true;
    return scope.own(pending.promise);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (raw == 2) return c.JS_DupValue(context, receiver);
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const returned = advance(&scope, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), raw == 1) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    return c.JS_DupValue(context, returned);
}
fn callback(scope: *Scope, data: c.JSValue, name: [*:0]const u8, length: c_int, raw: c_int) !c.JSValue {
    var roots = [_]c.JSValue{data};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, raw, roots.len, &roots)));
}
pub fn create(scope: *Scope, bindings: c.JSValue, stream: c.JSValue, options: c.JSValue) !c.JSValue {
    if (!h.nullish(options) and !c.JS_IsObject(options)) return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"options\" argument must be of type object");
    const prevent = scope.truthy(try h.optional(scope, options, "preventCancel"));
    const reader = try core.getReaderNative(scope, bindings, stream, c.pi_js_undefined());
    var offered = false;
    errdefer if (!offered) core.releaseReaderNative(scope, bindings, reader) catch {};
    const data = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
    try scope.put(data, "bindings", bindings);
    try scope.put(data, "stream", stream);
    try scope.put(data, "reader", reader);
    try scope.put(data, "preventCancel", c.pi_js_bool(scope.engine.context, @intFromBool(prevent)));
    const prototype = try scope.own(try scope.engine.checked(c.JS_GetAsyncIteratorPrototype(scope.engine.context)));
    const iterator = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, prototype)));
    try scope.put(iterator, "next", try callback(scope, data, "next", 0, 0));
    try scope.put(iterator, "return", try callback(scope, data, "return", 1, 1));
    const symbol = try scope.own(try scope.engine.checked(c.JS_GetAsyncIteratorSymbol(scope.engine.context)));
    const atom = c.JS_ValueToAtom(scope.engine.context, symbol);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, iterator, atom, c.JS_DupValue(scope.engine.context, try callback(scope, data, "[Symbol.asyncIterator]", 0, 2)), c.JS_PROP_C_W_E) < 0) return js.capture(scope.engine);
    offered = true;
    return iterator;
}
