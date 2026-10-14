//! Source errors.runAll: await each action and preserve one error or aggregate every failure.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
pub fn run(s: *Scope, steps: c.JSValue, message: c.JSValue) anyerror!c.JSValue {
    const pending = begin(s, steps, message) catch |err| return @import("native_durable.zig").rejectedPromise(s.engine, err);
    defer s.engine.freeValue(pending);
    return @import("native_durable.zig").resolvedPromise(s.engine, pending);
}
fn begin(s: *Scope, steps: c.JSValue, message: c.JSValue) anyerror!c.JSValue {
    const work = try s.record();
    try h.field(s, work, "steps", try h.invoke(s, steps, "values", &.{}));
    try h.field(s, work, "message", message);
    try h.field(s, work, "errors", try s.list());
    return next(s.engine, work, c.pi_js_undefined(), false, 0);
}
fn next(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const errors = try s.get(work, "errors");
    if (rejected) try js.push(engine, errors, value);
    while (try r.next(&s, try s.get(work, "steps"))) |action| {
        const pending = js.call(engine, action, c.pi_js_undefined(), &.{}) catch |err| {
            if (err != error.JavaScriptException) return err;
            try js.push(engine, errors, engine.captured_exception orelse return err);
            continue;
        };
        defer engine.freeValue(pending);
        return h.wait(next, engine, work, pending, 0);
    }
    const count = try h.length(&s, errors);
    if (count == 1) return h.throwValue(&s, try s.at(errors, 0));
    if (count > 1) return h.throwValue(&s, try s.keep(try js.builtin(engine, "AggregateError", &.{ errors, try s.get(work, "message") })));
    return c.pi_js_undefined();
}
