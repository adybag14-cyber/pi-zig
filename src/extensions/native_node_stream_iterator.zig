//! Readable consumption on the genuine VM AsyncGenerator queue and Await path.
//! The readable listener and EOS callback mirror Node24 createAsyncIterator;
//! return/throw enter its real finally branch, never a hand-built iterator.
const core = @import("native_node_stream.zig");
const life = @import("native_node_stream_lifecycle.zig");
const gen = @import("native_async_generator.zig");
const fnc = @import("native_node_function.zig");
const em = core.em; const c = core.c; const js = core.js; const Scope = core.Scope;
const Event = enum(c_int) { wake, ended };
fn record(scope: *Scope) !c.JSValue { return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null()))); }
fn handler(scope: *Scope, data: c.JSValue, op: Event) !c.JSValue {
    const roots = [_]c.JSValue{ data, c.JS_NewInt32(scope.engine.context, @intFromEnum(op)) };
    return scope.own(if (op == .wake) try fnc.create(scope.engine, "next", 1, event, &roots) else try fnc.createArrow(scope.engine, "", 1, event, &roots));
}
pub fn aggregate(scope: *Scope, inner: c.JSValue, outer: c.JSValue) !c.JSValue {
    if (scope.truthy(inner) and scope.truthy(outer) and !scope.equal(inner, outer)) {
        const errors = try scope.get(outer, "errors");
        if (c.JS_IsArray(errors)) {
            _ = try scope.call(try scope.get(try core.owner(scope.engine), "arrayPush"), try scope.get(outer, "errors"), &.{inner});
            return c.JS_DupValue(scope.engine.context, outer);
        }
        const items = try scope.array(); try scope.index(items, 0, outer); try scope.index(items, 1, inner);
        // The original aggregate preserves error ordering, outer message/code,
        // and identity on an existing AggregateError. Stack formatting remains
        // a separate reflection/diagnostic gate; no invented source is attached.
        var args = [_]c.JSValue{ items, try scope.get(outer, "message") };
        const combined = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(try core.owner(scope.engine), "AggregateError"), args.len, &args)));
        try scope.set(combined, "code", try scope.get(outer, "code")); return c.JS_DupValue(scope.engine.context, combined);
    }
    return c.JS_DupValue(scope.engine.context, if (scope.truthy(inner)) inner else outer);
}
fn event(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const data = roots[0]; var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return js.capture(engine);
    const nop = try scope.get(try core.owner(engine), "nop");
    switch (@as(Event, @enumFromInt(raw))) {
        .wake => {
            if (scope.equal(receiver, try scope.get(data, "stream"))) {
                _ = try scope.call(try scope.get(data, "callback"), c.pi_js_undefined(), &.{}); try scope.put(data, "callback", nop);
            } else try scope.put(data, "callback", core.arg(args, 0));
        },
        .ended => {
            const err = core.arg(args, 0);
            const reason = if (scope.truthy(err)) try scope.own(try aggregate(&scope, try scope.get(data, "error"), err)) else c.pi_js_null();
            try scope.put(data, "error", reason);
            _ = try scope.call(try scope.get(data, "callback"), c.pi_js_undefined(), &.{}); try scope.put(data, "callback", nop);
        },
    }
    return c.pi_js_undefined();
}
fn begin(scope: *Scope, data: c.JSValue) !void {
    const stream = try scope.get(data, "stream"); try scope.put(data, "callback", try scope.get(try core.owner(scope.engine), "nop"));
    const next = try handler(scope, data, .wake); try scope.put(data, "next", next);
    _ = try scope.invoke(stream, "on", &.{ try scope.text("readable"), next });
    try scope.put(data, "error", c.pi_js_undefined()); const options = try record(scope); try scope.put(options, "writable", c.pi_js_bool(scope.engine.context, 0));
    const cleanup = try scope.own(try life.eos(scope.engine, stream, options, try handler(scope, data, .ended))); try scope.put(data, "cleanup", cleanup);
}
fn finish(scope: *Scope, data: c.JSValue, value: c.JSValue, throwing: bool) !gen.Action {
    const reason = try scope.get(data, "error"); const options = try scope.get(data, "options"); const stream = try scope.get(data, "stream");
    if ((scope.truthy(reason) or !scope.equal(try core.optional(scope, options, "destroyOnReturn"), c.pi_js_bool(scope.engine.context, 0))) and
        (c.JS_IsUndefined(reason) or scope.truthy(try scope.get(try scope.get(stream, "_readableState"), "autoDestroy"))))
    {
        try life.destroyer(scope.engine, stream, c.pi_js_null());
    } else {
        _ = try scope.invoke(stream, "off", &.{ try scope.text("readable"), try scope.get(data, "next") });
        _ = try scope.call(try scope.get(data, "cleanup"), c.pi_js_undefined(), &.{});
    }
    return if (throwing) .{ .thrown = c.JS_DupValue(scope.engine.context, value) } else .{ .complete = c.JS_DupValue(scope.engine.context, value) };
}
fn caught(scope: *Scope, data: c.JSValue, reason: c.JSValue) !gen.Action {
    const combined = aggregate(scope, try scope.get(data, "error"), reason) catch |err| {
        if (err != error.JavaScriptException) return err;
        // A guest error.errors/message getter can throw inside Source's catch.
        // Its finally still runs once using the previous lexical error value.
        const replacement = try scope.own(c.JS_DupValue(scope.engine.context, scope.engine.captured_exception.?));
        return finish(scope, data, replacement, true);
    };
    _ = try scope.own(combined); try scope.put(data, "error", combined);
    // Source rethrows its caught value; the aggregate only controls finally.
    return finish(scope, data, reason, true);
}
fn step(scope: *Scope, data: c.JSValue) !gen.Action {
    const stream = try scope.get(data, "stream");
    const chunk = if (scope.truthy(try scope.get(stream, "destroyed"))) c.pi_js_null() else try scope.invoke(stream, "read", &.{});
    if (!c.JS_IsNull(chunk)) return .{ .yielded = c.JS_DupValue(scope.engine.context, chunk) };
    const reason = try scope.get(data, "error");
    if (scope.truthy(reason)) return .{ .thrown = c.JS_DupValue(scope.engine.context, reason) };
    if (c.JS_IsNull(reason)) return .{ .complete = c.pi_js_undefined() };
    var functions: [2]c.JSValue = undefined;
    const promise = try scope.own(try scope.engine.checked(c.JS_NewPromiseCapability(scope.engine.context, &functions))); defer for (functions) |value| scope.engine.freeValue(value);
    _ = try scope.call(try scope.get(data, "next"), c.pi_js_undefined(), &functions);
    return .{ .awaited = c.JS_DupValue(scope.engine.context, promise) };
}
fn advance(engine: *em.Engine, data: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    // Source installs listeners outside its try block on first execution only.
    // The VM itself handles unstarted return/throw without entering this body.
    if (completion == .start) try begin(&scope, data);
    if (completion == .returned) return finish(&scope, data, input, false);
    if (completion == .thrown or completion == .rejected) return caught(&scope, data, input);
    const action = step(&scope, data) catch |err| blk: {
        if (err != error.JavaScriptException) return err;
        break :blk gen.Action{ .thrown = c.JS_DupValue(engine.context, engine.captured_exception.?) };
    };
    // Finally is outside the loop's catch. A destroyOnReturn getter, off,
    // cleanup, or destroy exception replaces completion without reentering it.
    return switch (action) {
        .complete => |value| blk: { defer engine.freeValue(value); break :blk try finish(&scope, data, value, false); },
        .thrown => |value| blk: { defer engine.freeValue(value); break :blk try caught(&scope, data, value); },
        else => action,
    };
}
fn iterator(engine: *em.Engine, stream: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const options = if (scope.truthy(roots[0])) core.arg(args, 0) else c.pi_js_undefined();
    if (!c.JS_IsUndefined(options) and (!c.JS_IsObject(options) or c.JS_IsArray(options) or c.JS_IsFunction(engine.context, options))) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"options\" argument must be of type object");
    if (!c.JS_IsFunction(engine.context, try scope.get(stream, "read"))) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "Native Readable async consumption requires a readable stream");
    const data = try record(&scope); try scope.put(data, "stream", stream); try scope.put(data, "options", options);
    const result = try scope.own(try gen.create(engine, data, advance, try scope.get(try core.owner(engine), "readableIteratorPrototype"))); try scope.set(result, "stream", stream);
    return c.JS_DupValue(engine.context, result);
}
pub fn install(engine: *em.Engine, module: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const prototype = try scope.get(try scope.get(module, "Readable"), "prototype");
    // Async-generator declarations each own a shared instance prototype above
    // the realm's intrinsic AsyncGeneratorPrototype. The instance itself is
    // the genuine VM AsyncGenerator created by gen.create, not a JS facade.
    try scope.put(module, "readableIteratorPrototype", try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, try scope.own(try gen.prototype(engine))))));
    const symbol = try scope.get(module, "asyncIteratorSymbol"); const atom = try js.atom(engine, symbol); defer c.JS_FreeAtom(engine.context, atom);
    const method = try scope.own(try fnc.create(engine, "", 0, iterator, &.{c.pi_js_bool(engine.context, 0)}));
    if (c.JS_DefinePropertyValue(engine.context, prototype, atom, c.JS_DupValue(engine.context, method), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    try scope.put(prototype, "iterator", try scope.own(try fnc.create(engine, "", 1, iterator, &.{c.pi_js_bool(engine.context, 1)})));
}
