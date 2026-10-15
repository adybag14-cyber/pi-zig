//! Source5ab SSE line/event state, including EOF flush and exact raw diagnostics.
//! Input strings come from the native streaming TextDecoder on the owner thread.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn create(scope: *Scope) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "event", c.pi_js_null());
    try scope.put(result, "data", try scope.array());
    try scope.put(result, "raw", try scope.array());
    try scope.put(result, "buffer", try scope.text(""));
    return result;
}
fn flush(scope: *Scope, state: c.JSValue) !c.JSValue {
    if (!scope.truthy(try scope.get(state, "event")) and try v.length(scope, try scope.get(state, "data")) == 0) return c.pi_js_null();
    const event = try scope.object();
    try scope.put(event, "event", try scope.get(state, "event"));
    try scope.put(event, "data", try scope.invoke(try scope.get(state, "data"), "join", &.{try scope.text("\n")}));
    const raw = try scope.array();
    var rows = try v.iterator(scope, try scope.get(state, "raw"));
    defer rows.deinit();
    errdefer rows.closePreserving();
    var index: u32 = 0;
    while (try rows.next()) |value| : (index += 1) {
        defer scope.engine.freeValue(value);
        try scope.index(raw, index, value);
    }
    try scope.put(event, "raw", raw);
    try scope.set(state, "event", c.pi_js_null());
    try scope.set(state, "data", try scope.array());
    try scope.set(state, "raw", try scope.array());
    return event;
}
fn line(scope: *Scope, state: c.JSValue, input: c.JSValue) !c.JSValue {
    if (try v.eq(scope, input, "")) return flush(scope, state);
    _ = try scope.invoke(try scope.get(state, "raw"), "push", &.{input});
    if (scope.truthy(try scope.invoke(input, "startsWith", &.{try scope.text(":")}))) return c.pi_js_null();
    const colon = try scope.invoke(input, "indexOf", &.{try scope.text(":")});
    const absent = scope.equal(colon, c.JS_NewInt32(scope.engine.context, -1));
    const field = if (absent) input else try scope.invoke(input, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), colon });
    var value = if (absent) try scope.text("") else try scope.invoke(input, "slice", &.{try scope.concat(colon, c.JS_NewInt32(scope.engine.context, 1))});
    if (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text(" ")}))) value = try scope.invoke(value, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)});
    if (try v.eq(scope, field, "event")) try scope.set(state, "event", value) else if (try v.eq(scope, field, "data")) _ = try scope.invoke(try scope.get(state, "data"), "push", &.{value});
    return c.pi_js_null();
}
pub fn feed(scope: *Scope, state: c.JSValue, input: c.JSValue, eof: bool) !c.JSValue {
    const output = try scope.array();
    var buffer = try scope.concat(try scope.get(state, "buffer"), input);
    while (true) {
        const cr = try scope.invoke(buffer, "indexOf", &.{try scope.text("\r")});
        const lf = try scope.invoke(buffer, "indexOf", &.{try scope.text("\n")});
        const no_cr = scope.equal(cr, c.JS_NewInt32(scope.engine.context, -1));
        const no_lf = scope.equal(lf, c.JS_NewInt32(scope.engine.context, -1));
        if (no_cr and no_lf) break;
        const index = if (no_cr) lf else if (no_lf) cr else try scope.invoke(try scope.global("Math"), "min", &.{ cr, lf });
        var next = try scope.concat(index, c.JS_NewInt32(scope.engine.context, 1));
        const at = try scope.invoke(buffer, "charAt", &.{index});
        if (try v.eq(scope, at, "\r") and try v.eq(scope, try scope.invoke(buffer, "charAt", &.{next}), "\n")) next = try scope.concat(next, c.JS_NewInt32(scope.engine.context, 1));
        const current = try scope.invoke(buffer, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), index });
        buffer = try scope.invoke(buffer, "slice", &.{next});
        const event = try line(scope, state, current);
        if (!c.JS_IsNull(event)) _ = try scope.invoke(output, "push", &.{event});
    }
    if (eof) {
        if (try v.length(scope, buffer) > 0) {
            const event = try line(scope, state, buffer);
            if (!c.JS_IsNull(event)) _ = try scope.invoke(output, "push", &.{event});
        }
        const event = try flush(scope, state);
        if (!c.JS_IsNull(event)) _ = try scope.invoke(output, "push", &.{event});
        buffer = try scope.text("");
    }
    try scope.set(state, "buffer", buffer);
    return output;
}
pub fn append(scope: *Scope, state: c.JSValue, input: c.JSValue) !void {
    try scope.set(state, "buffer", try scope.concat(try scope.get(state, "buffer"), input));
}
/// One Source yield boundary at a time. Later buffered lines remain unconsumed
/// until the real SSE async generator receives its next request.
pub fn take(engine: *v.em.Engine, state: c.JSValue, eof: bool) !?c.JSValue {
    var steps: usize = 0;
    while (true) {
        try @import("native_ai_budget.zig").step(engine, &steps);
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const buffer = try scope.get(state, "buffer");
        const cr = try scope.invoke(buffer, "indexOf", &.{try scope.text("\r")});
        const lf = try scope.invoke(buffer, "indexOf", &.{try scope.text("\n")});
        const no_cr = scope.equal(cr, c.JS_NewInt32(engine.context, -1));
        const no_lf = scope.equal(lf, c.JS_NewInt32(engine.context, -1));
        if (no_cr and no_lf) {
            if (!eof) return null;
            try scope.set(state, "buffer", try scope.text(""));
            if (try v.length(&scope, buffer) > 0) {
                const event = try line(&scope, state, buffer);
                if (!c.JS_IsNull(event)) return c.JS_DupValue(engine.context, event);
            }
            const event = try flush(&scope, state);
            if (!c.JS_IsNull(event)) return c.JS_DupValue(engine.context, event);
            return null;
        }
        const index = if (no_cr) lf else if (no_lf) cr else try scope.invoke(try scope.global("Math"), "min", &.{ cr, lf });
        var following = try scope.concat(index, c.JS_NewInt32(engine.context, 1));
        if (try v.eq(&scope, try scope.invoke(buffer, "charAt", &.{index}), "\r") and try v.eq(&scope, try scope.invoke(buffer, "charAt", &.{following}), "\n")) following = try scope.concat(following, c.JS_NewInt32(engine.context, 1));
        const current = try scope.invoke(buffer, "slice", &.{ c.JS_NewInt32(engine.context, 0), index });
        try scope.set(state, "buffer", try scope.invoke(buffer, "slice", &.{following}));
        const event = try line(&scope, state, current);
        if (!c.JS_IsNull(event)) return c.JS_DupValue(engine.context, event);
    }
}
pub fn parseFailure(scope: *Scope, sse: c.JSValue, reason: c.JSValue) !c.JSValue {
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (instance < 0) return v.js.capture(scope.engine);
    const description = if (instance == 1) try scope.get(reason, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason});
    var text = try scope.concat(try scope.concat(try scope.text("Could not parse Anthropic SSE event "), try scope.stringify(try scope.get(sse, "event"))), try scope.text(": "));
    text = try scope.concat(try scope.concat(text, description), try scope.text("; data="));
    text = try scope.concat(try scope.concat(text, try scope.get(sse, "data")), try scope.text("; raw="));
    text = try scope.concat(text, try scope.invoke(try scope.get(sse, "raw"), "join", &.{try scope.text("\\n")}));
    return scope.own(try v.js.builtin(scope.engine, "Error", &.{text}));
}
pub fn known(scope: *Scope, kind: c.JSValue) !bool {
    inline for (.{ "message_start", "message_delta", "message_stop", "content_block_start", "content_block_delta", "content_block_stop" }) |candidate| if (try v.eq(scope, kind, candidate)) {
        return true;
    };
    return false;
}
pub fn decode(scope: *Scope, sse: c.JSValue, json: c.JSValue) !c.JSValue {
    const kind = try scope.get(sse, "event");
    const data = try scope.get(sse, "data");
    if (try v.eq(scope, kind, "error")) return v.errorText(scope, data);
    if (!try known(scope, kind)) return c.pi_js_undefined();
    const generation = scope.engine.native_allocation_generation;
    return scope.invoke(json, "parseJsonWithRepair", &.{data}) catch |err| {
        const classified = scope.engine.nativeAllocationError(err, generation);
        if (classified == error.OutOfMemory) return classified;
        const reason = @import("native_agent_async.zig").reason(scope.engine, err);
        defer scope.engine.freeValue(reason);
        const failure = try parseFailure(scope, sse, reason);
        return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, failure)));
    };
}
