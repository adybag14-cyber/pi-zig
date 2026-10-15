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
fn flush(scope: *Scope, state: c.JSValue, output: c.JSValue) !void {
    if (!scope.truthy(try scope.get(state, "event")) and try v.length(scope, try scope.get(state, "data")) == 0) return;
    const event = try scope.object();
    try scope.put(event, "event", try scope.get(state, "event"));
    try scope.put(event, "data", try scope.invoke(try scope.get(state, "data"), "join", &.{try scope.text("\n")}));
    try scope.put(event, "raw", try scope.invoke(try scope.get(state, "raw"), "slice", &.{}));
    try scope.set(state, "event", c.pi_js_null());
    try scope.set(state, "data", try scope.array());
    try scope.set(state, "raw", try scope.array());
    _ = try scope.invoke(output, "push", &.{event});
}
fn line(scope: *Scope, state: c.JSValue, input: c.JSValue, output: c.JSValue) !void {
    if (try v.eq(scope, input, "")) return flush(scope, state, output);
    _ = try scope.invoke(try scope.get(state, "raw"), "push", &.{input});
    if (scope.truthy(try scope.invoke(input, "startsWith", &.{try scope.text(":")}))) return;
    const colon = try scope.invoke(input, "indexOf", &.{try scope.text(":")});
    const absent = scope.equal(colon, c.JS_NewInt32(scope.engine.context, -1));
    const field = if (absent) input else try scope.invoke(input, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), colon });
    var value = if (absent) try scope.text("") else try scope.invoke(input, "slice", &.{try scope.concat(colon, c.JS_NewInt32(scope.engine.context, 1))});
    if (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text(" ")}))) value = try scope.invoke(value, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)});
    if (try v.eq(scope, field, "event")) try scope.set(state, "event", value) else if (try v.eq(scope, field, "data")) _ = try scope.invoke(try scope.get(state, "data"), "push", &.{value});
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
        try line(scope, state, current, output);
    }
    if (eof) {
        if (try v.length(scope, buffer) > 0) try line(scope, state, buffer, output);
        try flush(scope, state, output);
        buffer = try scope.text("");
    }
    try scope.set(state, "buffer", buffer);
    return output;
}
pub fn decode(scope: *Scope, sse: c.JSValue, json: c.JSValue) !c.JSValue {
    const kind = try scope.get(sse, "event");
    const data = try scope.get(sse, "data");
    if (try v.eq(scope, kind, "error")) return v.errorText(scope, data);
    var known = false;
    inline for (.{ "message_start", "message_delta", "message_stop", "content_block_start", "content_block_delta", "content_block_stop" }) |candidate| if (try v.eq(scope, kind, candidate)) {
        known = true;
    };
    if (!known) return c.pi_js_undefined();
    return scope.invoke(json, "parseJsonWithRepair", &.{data}) catch |err| {
        const reason = @import("native_agent_async.zig").reason(scope.engine, err);
        defer scope.engine.freeValue(reason);
        const instance = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
        if (instance < 0) return v.js.capture(scope.engine);
        const description = if (instance == 1) try scope.get(reason, "message") else try scope.stringify(reason);
        var text = try scope.concat(try scope.concat(try scope.text("Could not parse Anthropic SSE event "), try scope.stringify(kind)), try scope.text(": "));
        text = try scope.concat(try scope.concat(text, description), try scope.text("; data="));
        text = try scope.concat(try scope.concat(text, data), try scope.text("; raw="));
        text = try scope.concat(text, try scope.invoke(try scope.get(sse, "raw"), "join", &.{try scope.text("\n")}));
        return v.errorText(scope, text);
    };
}
