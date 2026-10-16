//! The original legacy Stream pipe contract, distinct from Readable.pipe.
const core = @import("native_node_stream.zig");
const c = core.c; const em = core.em; const js = core.js; const Scope = core.Scope;
const fnc = @import("native_node_function.zig");
const Op = enum(c_int) { data, drain, end, close, error_event, cleanup };
fn handler(scope: *Scope, record: c.JSValue, op: Op, name: [*:0]const u8, length: c_int) !c.JSValue {
    return scope.own(try fnc.create(scope.engine, name, length, event, &.{ record, c.JS_NewInt32(scope.engine.context, @intFromEnum(op)) }));
}
fn cleanup(scope: *Scope, record: c.JSValue) !void {
    const source = try scope.get(record, "source"); const dest = try scope.get(record, "destination");
    inline for (.{ "data", "end", "close", "error", "end", "close" }, .{ "ondata", "onend", "onclose", "onerror", "cleanup", "cleanup" }) |name, key| _ = try scope.invoke(source, "removeListener", &.{ try scope.text(name), try scope.get(record, key) });
    inline for (.{ "drain", "error", "close" }, .{ "ondrain", "onerror", "cleanup" }) |name, key| _ = try scope.invoke(dest, "removeListener", &.{ try scope.text(name), try scope.get(record, key) });
}
fn pipe(engine: *em.Engine, source: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const dest = core.arg(args, 0); const options = core.arg(args, 1);
    const record = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(record, "source", source); try scope.put(record, "destination", dest); try scope.put(record, "didOnEnd", c.pi_js_bool(engine.context, 0));
    inline for (.{ "ondata", "ondrain", "onend", "onclose", "onerror", "cleanup" }, .{ Op.data, Op.drain, Op.end, Op.close, Op.error_event, Op.cleanup }, .{ 1, 0, 0, 0, 1, 0 }) |name, op, length| try scope.put(record, name, try handler(&scope, record, op, name, length));
    _ = try scope.invoke(source, "on", &.{ try scope.text("data"), try scope.get(record, "ondata") });
    _ = try scope.invoke(dest, "on", &.{ try scope.text("drain"), try scope.get(record, "ondrain") });
    if (!scope.truthy(try scope.get(dest, "_isStdio")) and (!scope.truthy(options) or !scope.equal(try scope.get(options, "end"), c.pi_js_bool(engine.context, 0)))) {
        _ = try scope.invoke(source, "on", &.{ try scope.text("end"), try scope.get(record, "onend") });
        _ = try scope.invoke(source, "on", &.{ try scope.text("close"), try scope.get(record, "onclose") });
    }
    _ = try scope.invoke(source, "prependListener", &.{ try scope.text("error"), try scope.get(record, "onerror") });
    _ = try scope.invoke(dest, "prependListener", &.{ try scope.text("error"), try scope.get(record, "onerror") });
    _ = try scope.invoke(source, "on", &.{ try scope.text("end"), try scope.get(record, "cleanup") });
    _ = try scope.invoke(source, "on", &.{ try scope.text("close"), try scope.get(record, "cleanup") });
    _ = try scope.invoke(dest, "on", &.{ try scope.text("close"), try scope.get(record, "cleanup") });
    try core.emit(&scope, dest, "pipe", &.{source}); return c.JS_DupValue(engine.context, dest);
}
fn event(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const record = roots[0]; var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return js.capture(engine);
    const source = try scope.get(record, "source"); const dest = try scope.get(record, "destination");
    const op: Op = @enumFromInt(raw);
    switch (op) {
        .data => if (scope.truthy(try scope.get(dest, "writable")) and scope.equal(try scope.invoke(dest, "write", &.{core.arg(args, 0)}), c.pi_js_bool(engine.context, 0)) and scope.truthy(try scope.get(source, "pause"))) { _ = try scope.invoke(source, "pause", &.{}); },
        .drain => if (scope.truthy(try scope.get(source, "readable")) and scope.truthy(try scope.get(source, "resume"))) { _ = try scope.invoke(source, "resume", &.{}); },
        .end, .close => {
            if (!scope.truthy(try scope.get(record, "didOnEnd"))) {
                try scope.put(record, "didOnEnd", c.pi_js_bool(engine.context, 1));
                if (op == .end) _ = try scope.invoke(dest, "end", &.{}) else if (c.JS_IsFunction(engine.context, try scope.get(dest, "destroy"))) { _ = try scope.invoke(dest, "destroy", &.{}); }
            }
        },
        .error_event => {
            try cleanup(&scope, record); const count = try scope.get(receiver, "listenerCount");
            if (!core.nullish(count) and scope.equal(try scope.call(count, receiver, &.{try scope.text("error")}), c.JS_NewInt32(engine.context, 0))) try core.emit(&scope, receiver, "error", &.{core.arg(args, 0)});
        },
        .cleanup => try cleanup(&scope, record),
    }
    return c.pi_js_undefined();
}
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); try scope.put(prototype, "pipe", try scope.own(try fnc.create(engine, "", 2, pipe, &.{})));
}
