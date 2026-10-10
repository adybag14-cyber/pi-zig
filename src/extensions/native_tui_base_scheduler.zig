//! Source screen render coalescing and throttling with genuine public timers.
//! Bindings retain the real performance object and TuiBase constructor; class
//! installation must provide them before this draft is exposed to callers.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub const Method = enum { renderNow, requestRender, requestImmediateRender, cancelRenderTimer, scheduleRender };
const Callback = enum(c_int) { schedule, immediate, timer };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TuiBase scheduler: %s", @as([*:0]const u8, @errorName(err)));
}
fn field(engine: *js.Engine, screen: c.JSValue, name: [*:0]const u8) !bool {
    const value = try js.get(engine, screen, name);
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn now(engine: *js.Engine, bindings: c.JSValue) !c.JSValue {
    const performance = try js.get(engine, bindings, "performance");
    defer engine.freeValue(performance);
    return js.invoke(engine, performance, "now", &.{});
}
fn render(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue) !void {
    try v.set(engine, screen, "renderRequested", c.pi_js_bool(engine.context, 0));
    try v.set(engine, screen, "lastRenderAt", try now(engine, bindings));
    try v.invokeVoid(engine, screen, "doRender", &.{});
}
fn callback(engine: *js.Engine, kind: Callback, screen: c.JSValue, bindings: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{ screen, bindings };
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callbackCall, "", 0, @intFromEnum(kind), 2, &data));
}
fn callbackCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return callbackBody(engine, @enumFromInt(magic), data[0], data[1]) catch |err| fail(engine, err);
}
fn callbackBody(engine: *js.Engine, kind: Callback, screen: c.JSValue, bindings: c.JSValue) !c.JSValue {
    switch (kind) {
        .schedule => return js.invoke(engine, screen, "scheduleRender", &.{}),
        .immediate => {
            try v.set(engine, screen, "immediateRenderScheduled", c.pi_js_bool(engine.context, 0));
            if (try field(engine, screen, "stopped") or !try field(engine, screen, "renderRequested")) return c.pi_js_undefined();
            try v.invokeVoid(engine, screen, "cancelRenderTimer", &.{});
            try render(engine, screen, bindings);
        },
        .timer => {
            try v.set(engine, screen, "renderTimer", c.pi_js_undefined());
            if (try field(engine, screen, "stopped") or !try field(engine, screen, "renderRequested")) return c.pi_js_undefined();
            try render(engine, screen, bindings);
            if (try field(engine, screen, "renderRequested")) try v.invokeVoid(engine, screen, "scheduleRender", &.{});
        },
    }
    return c.pi_js_undefined();
}
fn nextTick(engine: *js.Engine, kind: Callback, screen: c.JSValue, bindings: c.JSValue) !void {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const enqueue = try js.get(engine, process, "nextTick");
    defer engine.freeValue(enqueue);
    const continuation = try callback(engine, kind, screen, bindings);
    defer engine.freeValue(continuation);
    const result = try js.call(engine, enqueue, process, &.{continuation});
    engine.freeValue(result);
}
pub fn invoke(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .renderNow => {
            if (v.truthy(engine, v.arg(args, 0))) try v.invokeVoid(engine, screen, "resetRenderState", &.{});
            try v.set(engine, screen, "renderRequested", c.pi_js_bool(engine.context, 0));
            try v.invokeVoid(engine, screen, "cancelRenderTimer", &.{});
            try v.set(engine, screen, "lastRenderAt", try now(engine, bindings));
            try v.invokeVoid(engine, screen, "doRender", &.{});
        },
        .requestRender => {
            if (v.truthy(engine, v.arg(args, 0))) {
                try v.invokeVoid(engine, screen, "resetRenderState", &.{});
                try v.invokeVoid(engine, screen, "requestImmediateRender", &.{});
                return c.pi_js_undefined();
            }
            if (try field(engine, screen, "renderRequested")) return c.pi_js_undefined();
            try v.set(engine, screen, "renderRequested", c.pi_js_bool(engine.context, 1));
            try nextTick(engine, .schedule, screen, bindings);
        },
        .requestImmediateRender => {
            try v.invokeVoid(engine, screen, "cancelRenderTimer", &.{});
            try v.set(engine, screen, "renderRequested", c.pi_js_bool(engine.context, 1));
            if (try field(engine, screen, "immediateRenderScheduled")) return c.pi_js_undefined();
            try v.set(engine, screen, "immediateRenderScheduled", c.pi_js_bool(engine.context, 1));
            try nextTick(engine, .immediate, screen, bindings);
        },
        .cancelRenderTimer => {
            if (!try field(engine, screen, "renderTimer")) return c.pi_js_undefined();
            const clear = try js.global(engine, "clearTimeout");
            defer engine.freeValue(clear);
            const timer = try js.get(engine, screen, "renderTimer");
            defer engine.freeValue(timer);
            const result = try js.call(engine, clear, c.pi_js_undefined(), &.{timer});
            engine.freeValue(result);
            try v.set(engine, screen, "renderTimer", c.pi_js_undefined());
        },
        .scheduleRender => {
            if (try field(engine, screen, "stopped") or try field(engine, screen, "renderTimer") or !try field(engine, screen, "renderRequested")) return c.pi_js_undefined();
            const current = try now(engine, bindings);
            defer engine.freeValue(current);
            const previous = try js.get(engine, screen, "lastRenderAt");
            defer engine.freeValue(previous);
            const elapsed = try v.number(engine, current) - try v.number(engine, previous);
            const math = try js.global(engine, "Math");
            defer engine.freeValue(math);
            const maximum = try js.get(engine, math, "max");
            defer engine.freeValue(maximum);
            const base = try js.get(engine, bindings, "TuiBase");
            defer engine.freeValue(base);
            const interval = try js.get(engine, base, "MIN_RENDER_INTERVAL_MS");
            defer engine.freeValue(interval);
            const delay = try js.call(engine, maximum, math, &.{ c.JS_NewInt32(engine.context, 0), v.numeric(engine, try v.number(engine, interval) - elapsed) });
            defer engine.freeValue(delay);
            const schedule = try js.global(engine, "setTimeout");
            defer engine.freeValue(schedule);
            const continuation = try callback(engine, .timer, screen, bindings);
            defer engine.freeValue(continuation);
            const timer = try js.call(engine, schedule, c.pi_js_undefined(), &.{ continuation, delay });
            try v.set(engine, screen, "renderTimer", timer);
        },
    }
    return c.pi_js_undefined();
}
