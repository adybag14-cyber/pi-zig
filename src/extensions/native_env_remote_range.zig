//! Source readRange: eight positional requests in flight, short-read restart, and post-read abort checks.
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const Scope = h.Scope;
const c = js.c;
const Stage = enum(c_int) { payload, range };
fn binary(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, operation, left, right)));
}
fn ignore(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
pub fn swallowed(scope: *Scope, promise: c.JSValue) !void {
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, ignore, "", 1)));
    _ = try scope.invoke(promise, "catch", &.{callback});
}
pub fn pread(scope: *Scope, captures: c.JSValue, at: ?c.JSValue, length: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.get(captures, "handle"), "pread", &.{ at orelse c.pi_js_undefined(), length });
}
pub fn aborted(scope: *Scope, captures: c.JSValue) !bool {
    const signal = try scope.get(try scope.get(captures, "context"), "abortSignal");
    return !h.nullish(signal) and scope.equal(try scope.get(signal, "aborted"), c.pi_js_bool(scope.engine.context, 1));
}
fn completed(scope: *Scope, captures: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "chunks", try scope.get(captures, "chunks"));
    try scope.put(result, "total", try scope.get(captures, "total"));
    return result;
}
fn pump(scope: *Scope, captures: c.JSValue) !c.JSValue {
    const length = try scope.get(captures, "length");
    const total = try scope.get(captures, "total");
    if (!scope.truthy(try binary(scope, 4, total, length))) return completed(scope, captures);
    const flight = try scope.get(captures, "flight");
    const end = try binary(scope, 0, try scope.get(captures, "offset"), length);
    while (scope.truthy(try binary(scope, 4, try scope.get(flight, "length"), c.JS_NewInt32(scope.engine.context, 8))) and scope.truthy(try binary(scope, 4, try scope.get(captures, "next"), end))) {
        const at = try scope.get(captures, "next");
        const remaining = try binary(scope, 1, end, at);
        const count = try scope.invoke(try scope.global("Math"), "min", &.{ remaining, try scope.get(captures, "chunk") });
        const pending = try pread(scope, captures, at, count);
        try swallowed(scope, pending);
        const head = try scope.object();
        try scope.put(head, "length", count);
        try scope.put(head, "bytes", pending);
        _ = try scope.invoke(flight, "push", &.{head});
        try scope.put(captures, "next", try binary(scope, 0, at, count));
    }
    const head = try scope.invoke(flight, "shift", &.{});
    try scope.put(captures, "head", head);
    return h.wait(next, scope, captures, try scope.get(head, "bytes"), Stage.range);
}
fn next(engine: *js.Engine, captures: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return h.throw(&scope, value);
    if (@as(Stage, @enumFromInt(raw)) == .payload) return c.JS_DupValue(engine.context, try scope.get(value, "payload"));
    if (try aborted(&scope, captures)) return c.pi_js_undefined();
    const size = try scope.get(value, "length");
    if (scope.equal(size, c.JS_NewInt32(engine.context, 0))) return c.JS_DupValue(engine.context, try completed(&scope, captures));
    _ = try scope.invoke(try scope.get(captures, "chunks"), "push", &.{value});
    const total = try binary(&scope, 0, try scope.get(captures, "total"), size);
    try scope.put(captures, "total", total);
    if (scope.truthy(try binary(&scope, 4, size, try scope.get(try scope.get(captures, "head"), "length")))) {
        try scope.set(try scope.get(captures, "flight"), "length", c.JS_NewInt32(engine.context, 0));
        try scope.put(captures, "next", try binary(&scope, 0, try scope.get(captures, "offset"), total));
    }
    return c.JS_DupValue(engine.context, try pump(&scope, captures));
}
pub fn start(scope: *Scope, caller: c.JSValue, retained: c.JSValue, offset: c.JSValue, length: c.JSValue, chunk: usize) !c.JSValue {
    const captures = try scope.object();
    inline for (.{ "bindings", "context" }) |key| try scope.put(captures, key, try scope.get(caller, key));
    try scope.put(captures, "handle", retained);
    try scope.put(captures, "offset", offset);
    try scope.put(captures, "length", length);
    try scope.put(captures, "next", offset);
    try scope.put(captures, "chunk", c.JS_NewInt64(scope.engine.context, @intCast(chunk)));
    try scope.put(captures, "total", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(captures, "flight", try scope.array());
    try scope.put(captures, "chunks", try scope.array());
    return h.resolved(scope, try pump(scope, captures));
}
pub fn concat(scope: *Scope, result: c.JSValue, buffer: bool) !c.JSValue {
    const chunks = try scope.get(result, "chunks");
    const total = try scope.get(result, "total");
    if (buffer) return scope.invoke(try scope.global("Buffer"), "concat", &.{ chunks, total });
    if (scope.equal(try scope.get(chunks, "length"), c.JS_NewInt32(scope.engine.context, 1))) return scope.own(try js.getKey(scope.engine, chunks, c.JS_NewInt32(scope.engine.context, 0)));
    const bytes = try scope.own(try js.builtin(scope.engine, "Uint8Array", &.{total}));
    var iterator = try js.Iterator.init(scope.engine, chunks, try scope.get(try scope.global("Symbol"), "iterator"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var position = c.JS_NewInt32(scope.engine.context, 0);
    while (try iterator.next()) |chunk| {
        _ = try scope.own(chunk);
        _ = try scope.invoke(bytes, "set", &.{ chunk, position });
        position = try binary(scope, 0, position, try scope.get(chunk, "length"));
    }
    return bytes;
}
