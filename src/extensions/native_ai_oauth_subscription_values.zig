//! Owner-thread operations shared by the three subscription OAuth bodies.
pub const v = @import("native_ai_provider_values.zig");
pub const Scope = v.Scope;
pub const c = v.c;
pub const flow = @import("native_agent_async.zig");
pub const functions = @import("native_node_function.zig");
pub const helpers = @import("native_ai_auth_helpers.zig");
pub const http = @import("native_ai_oauth_http.zig");
pub const device = @import("native_ai_oauth_device_code.zig");
const arithmetic = @import("native_image_arithmetic.zig");
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
pub fn binary(s: *Scope, op: arithmetic.Operation, a: c.JSValue, b: c.JSValue) !c.JSValue {
    return s.own(try arithmetic.binary(s.engine, op, a, b));
}
pub fn number(s: *Scope, n: f64) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_NewFloat64(s.engine.context, n)));
}
pub fn now(s: *Scope) !c.JSValue {
    return s.invoke(try s.global("Date"), "now", &.{});
}
pub fn positive(s: *Scope, value: c.JSValue) !bool {
    return c.JS_IsNumber(value) and s.truthy(try s.invoke(try s.global("Number"), "isFinite", &.{value})) and try arithmetic.compare(s.engine, .greater, value, c.JS_NewInt32(s.engine.context, 0));
}
pub fn record(s: *Scope, value: c.JSValue) bool {
    return s.truthy(value) and c.JS_IsObject(value) and !c.JS_IsFunction(s.engine.context, value);
}
pub fn json(s: *Scope, value: c.JSValue) !c.JSValue {
    return s.invoke(try s.global("JSON"), "stringify", &.{value});
}
pub fn errorMessage(s: *Scope, value: c.JSValue) !c.JSValue {
    const error_constructor = try s.global("Error");
    const instance = c.JS_IsInstanceOf(s.engine.context, value, error_constructor);
    if (instance < 0) return v.js.capture(s.engine);
    return if (instance != 0) s.get(value, "message") else s.call(try s.global("String"), c.pi_js_undefined(), &.{value});
}
pub fn trusted(s: *Scope, raw: c.JSValue, https_only: bool, message: []const u8) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    const url = s.own(v.js.builtin(s.engine, "URL", &.{raw}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
        return v.errorText(s, try s.text(message));
    }) catch |err| return err;
    const protocol = try s.get(url, "protocol");
    if (!try v.eq(s, protocol, "https:") and (https_only or !try v.eq(s, protocol, "http:"))) return v.errorText(s, try s.text(message));
    return s.get(url, "href");
}
pub fn form(s: *Scope, fields: c.JSValue, string: bool) !c.JSValue {
    const result = try s.own(try v.js.builtin(s.engine, "URLSearchParams", &.{fields}));
    return if (string) s.invoke(result, "toString", &.{}) else result;
}
pub fn signal(s: *Scope, input: c.JSValue, timeout: ?i32) !c.JSValue {
    if (timeout) |ms| {
        const abort = try s.global("AbortSignal");
        const any = try s.get(abort, "any");
        const values = try s.array();
        try s.index(values, 0, try s.invoke(abort, "timeout", &.{c.JS_NewInt32(s.engine.context, ms)}));
        try s.index(values, 1, input);
        return s.call(any, abort, &.{values});
    }
    return input;
}
pub fn initForm(s: *Scope, body: c.JSValue, input_signal: c.JSValue, timeout: ?i32, accept_first: bool) !c.JSValue {
    const init = try s.object();
    try s.put(init, "method", try s.text("POST"));
    const headers = try s.object();
    if (accept_first) try s.put(headers, "Accept", try s.text("application/json"));
    try s.put(headers, "Content-Type", try s.text("application/x-www-form-urlencoded"));
    if (!accept_first) try s.put(headers, "Accept", try s.text("application/json"));
    try s.put(init, "headers", headers);
    try s.put(init, "body", body);
    try s.put(init, "signal", try signal(s, input_signal, timeout));
    return init;
}
pub fn pollResult(s: *Scope, status: []const u8, key: ?[*:0]const u8, value: c.JSValue) !c.JSValue {
    const result = try s.object();
    try s.put(result, "status", try s.text(status));
    if (key) |name| try s.put(result, name, value);
    return result;
}
pub fn credential(s: *Scope, access: c.JSValue, refresh: c.JSValue, expires: c.JSValue) !c.JSValue {
    const result = try s.object();
    try s.put(result, "type", try s.text("oauth"));
    try s.put(result, "access", access);
    try s.put(result, "refresh", refresh);
    try s.put(result, "expires", expires);
    return result;
}
/// The Source ordinary producer is shared with the genuine OAuth bodies.
pub fn sleep(engine: *v.em.Engine, ms: c.JSValue, input_signal: c.JSValue) !c.JSValue {
    return @import("native_ai_sleep.zig").sleep(engine, ms, input_signal);
}
