//! Codex's direct HTTP rules. These are distinct from OpenAI SDK retries.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const math = @import("native_image_arithmetic.zig");
fn binary(scope: *Scope, operation: math.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try math.binary(scope.engine, operation, left, right));
}
fn regex(scope: *Scope, pattern: []const u8, value: c.JSValue) !bool {
    const expression = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{ try scope.text(pattern), try scope.text("i") }));
    return scope.truthy(try scope.invoke(expression, "test", &.{value}));
}
fn string(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.call(try scope.global("String"), c.pi_js_undefined(), &.{value});
}
pub fn timeout(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(value)) return value;
    if (!scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{value})) or try math.compare(scope.engine, .less, value, c.JS_NewInt32(scope.engine.context, 0))) return v.errorText(scope, try scope.concat(try scope.text("Invalid timeoutMs: "), try string(scope, value)));
    return scope.invoke(try scope.global("Math"), "floor", &.{value});
}
pub fn retryable(scope: *Scope, status: c.JSValue, text: c.JSValue) !bool {
    if (scope.equal(status, c.JS_NewInt32(scope.engine.context, 429)) and try regex(scope, "GoUsageLimitError|FreeUsageLimitError|Monthly usage limit reached|available balance|insufficient_quota|out of budget|quota exceeded|billing", text)) return false;
    inline for (.{ 429, 500, 502, 503, 504 }) |code| if (scope.equal(status, c.JS_NewInt32(scope.engine.context, code))) return true;
    return regex(scope, "rate.?limit|overloaded|service.?unavailable|upstream.?connect|connection.?refused", text);
}
pub fn retryAfter(scope: *Scope, headers: c.JSValue) !c.JSValue {
    const number = try scope.global("Number");
    const zero = c.JS_NewInt32(scope.engine.context, 0);
    // The transport head contains actual lower-case Headers entries. Missing
    // fields represent Headers.get's null; Number uses the whole string.
    const milliseconds = try v.optional(scope, headers, "retry-after-ms");
    if (!v.nullish(milliseconds)) {
        const parsed = try scope.call(number, c.pi_js_undefined(), &.{milliseconds});
        if (scope.truthy(try scope.invoke(number, "isFinite", &.{parsed}))) return scope.invoke(try scope.global("Math"), "max", &.{ zero, parsed });
    }
    const after = try v.optional(scope, headers, "retry-after");
    if (!scope.truthy(after)) return c.pi_js_undefined();
    const seconds = try scope.call(number, c.pi_js_undefined(), &.{after});
    if (scope.truthy(try scope.invoke(number, "isFinite", &.{seconds}))) return scope.invoke(try scope.global("Math"), "max", &.{ zero, try binary(scope, .multiply, seconds, c.JS_NewInt32(scope.engine.context, 1000)) });
    const date = try scope.invoke(try scope.global("Date"), "parse", &.{after});
    if (!scope.truthy(try scope.invoke(number, "isNaN", &.{date}))) return scope.invoke(try scope.global("Math"), "max", &.{ zero, try binary(scope, .subtract, date, try scope.invoke(try scope.global("Date"), "now", &.{})) });
    return c.pi_js_undefined();
}
pub fn validateDelay(scope: *Scope, delay: c.JSValue, options: c.JSValue) !c.JSValue {
    const configured = try v.optional(scope, options, "maxRetryDelayMs");
    const maximum = if (v.nullish(configured)) c.JS_NewInt32(scope.engine.context, 60000) else configured;
    const zero = c.JS_NewInt32(scope.engine.context, 0);
    if (try math.compare(scope.engine, .greater, maximum, zero) and try math.compare(scope.engine, .greater, delay, maximum)) {
        const seconds = try scope.invoke(try scope.global("Math"), "ceil", &.{try binary(scope, .divide, delay, c.JS_NewInt32(scope.engine.context, 1000))});
        const limit = try scope.invoke(try scope.global("Math"), "ceil", &.{try binary(scope, .divide, maximum, c.JS_NewInt32(scope.engine.context, 1000))});
        const prefix = try scope.concat(try scope.concat(try scope.text("Server requested "), try scope.stringify(seconds)), try scope.text("s retry delay (max: "));
        return v.errorText(scope, try scope.concat(try scope.concat(prefix, try scope.stringify(limit)), try scope.text("s)")));
    }
    return delay;
}
pub fn backoff(scope: *Scope, attempt: c.JSValue) !c.JSValue {
    return binary(scope, .multiply, c.JS_NewInt32(scope.engine.context, 1000), try binary(scope, .power, c.JS_NewInt32(scope.engine.context, 2), attempt));
}
pub fn abortReason(scope: *Scope) !c.JSValue {
    return scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("Request was aborted")}));
}
pub fn caught(scope: *Scope, reason: c.JSValue) !c.JSValue {
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (instance < 0) return v.js.capture(scope.engine);
    if (instance != 0) return reason;
    return scope.own(try v.js.builtin(scope.engine, "Error", &.{try string(scope, reason)}));
}
pub fn isAbort(scope: *Scope, reason: c.JSValue) !bool {
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (instance < 0) return v.js.capture(scope.engine);
    return instance != 0 and (try v.eq(scope, try scope.get(reason, "name"), "AbortError") or try v.eq(scope, try scope.get(reason, "message"), "Request was aborted"));
}
pub fn caughtRetryable(scope: *Scope, reason: c.JSValue) !bool {
    return !scope.truthy(try scope.invoke(try scope.get(reason, "message"), "includes", &.{try scope.text("usage limit")}));
}
fn parseFields(scope: *Scope, state: c.JSValue, status: c.JSValue, raw: c.JSValue) !void {
    const parsed = try scope.invoke(try scope.global("JSON"), "parse", &.{raw});
    const err = try v.optional(scope, parsed, "error");
    if (!scope.truthy(err)) return;
    var code = try scope.get(err, "code");
    if (!scope.truthy(code)) code = try scope.get(err, "type");
    if (!scope.truthy(code)) code = try scope.text("");
    if (try regex(scope, "usage_limit_reached|usage_not_included|rate_limit_exceeded", code) or scope.equal(status, c.JS_NewInt32(scope.engine.context, 429))) {
        const plan_type = try scope.get(err, "plan_type");
        const plan = if (scope.truthy(plan_type)) try scope.concat(try scope.concat(try scope.text(" ("), try scope.invoke(plan_type, "toLowerCase", &.{})), try scope.text(" plan)")) else try scope.text("");
        var when = try scope.text("");
        const reset = try scope.get(err, "resets_at");
        if (scope.truthy(reset)) {
            const duration = try binary(scope, .divide, try binary(scope, .subtract, try binary(scope, .multiply, reset, c.JS_NewInt32(scope.engine.context, 1000)), try scope.invoke(try scope.global("Date"), "now", &.{})), c.JS_NewInt32(scope.engine.context, 60000));
            const minutes = try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 0), try scope.invoke(try scope.global("Math"), "round", &.{duration}) });
            when = try scope.concat(try scope.concat(try scope.text(" Try again in ~"), try scope.stringify(minutes)), try scope.text(" min."));
        }
        const message = try scope.concat(try scope.concat(try scope.concat(try scope.text("You have hit your ChatGPT usage limit"), plan), try scope.text(".")), when);
        try scope.put(state, "friendlyMessage", try scope.invoke(message, "trim", &.{}));
    }
    const message = try scope.get(err, "message");
    if (scope.truthy(message)) try scope.put(state, "message", message) else {
        const friendly = try scope.get(state, "friendlyMessage");
        if (scope.truthy(friendly)) try scope.put(state, "message", friendly);
    }
}
pub fn responseError(scope: *Scope, status: c.JSValue, status_text: c.JSValue, raw: c.JSValue) !c.JSValue {
    const state = try scope.object();
    try scope.put(state, "message", if (scope.truthy(raw)) raw else if (scope.truthy(status_text)) status_text else try scope.text("Request failed"));
    try scope.put(state, "friendlyMessage", c.pi_js_undefined());
    const generation = scope.engine.native_allocation_generation;
    parseFields(scope, state, status, raw) catch |err| try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
    const friendly = try scope.get(state, "friendlyMessage");
    return scope.own(try v.js.builtin(scope.engine, "Error", &.{if (scope.truthy(friendly)) friendly else try scope.get(state, "message")}));
}
