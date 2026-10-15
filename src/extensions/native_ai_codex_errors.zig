//! Actual private Error subclasses used by Codex transport decisions. The
//! constructor/prototype graph and instanceof checks are native VM values.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub const Kind = enum { api, protocol, callback, close };
fn name(comptime kind: Kind) [:0]const u8 {
    return switch (kind) {
        .api => "CodexApiError",
        .protocol => "CodexProtocolError",
        .callback => "ProviderStreamEventCallbackError",
        .close => "WebSocketCloseError",
    };
}
pub fn instance(scope: *Scope, value: c.JSValue, constructor: c.JSValue) !bool {
    const result = c.JS_IsInstanceOf(scope.engine.context, value, constructor);
    if (result < 0) return v.js.capture(scope.engine);
    return result != 0;
}
pub fn thrownText(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (try instance(scope, value, try scope.global("Error"))) {
        const message = try scope.get(value, "message");
        return if (scope.truthy(message)) message else scope.get(value, "name");
    }
    if (c.JS_IsString(value)) return value;
    return scope.call(try scope.global("String"), c.pi_js_undefined(), &.{value});
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const classes = try scope.object();
    const base = try scope.global("Error");
    inline for (@typeInfo(Kind).@"enum".fields) |field| {
        const kind: Kind = @enumFromInt(field.value);
        const prototype = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, try scope.get(base, "prototype"))));
        const Construct = struct {
            fn call(host: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = host };
                defer row.deinit();
                const first = if (args.len > 0) args[0] else c.pi_js_undefined();
                const options = if (args.len > 1) args[1] else c.pi_js_undefined();
                var arguments = [_]c.JSValue{if (kind == .callback) try thrownText(&row, first) else first};
                const result = try row.own(try host.checked(c.JS_CallConstructor2(host.context, roots[0], target, arguments.len, &arguments)));
                try row.put(result, "name", try row.text(name(kind)));
                switch (kind) {
                    .api => {
                        inline for (.{ "code", "payload", "cause" }) |key| try row.put(result, key, try v.optional(&row, options, key));
                    },
                    .protocol => {
                        inline for (.{ "payload", "cause" }) |key| try row.put(result, key, try v.optional(&row, options, key));
                    },
                    .callback => try row.put(result, "cause", first),
                    .close => {
                        inline for (.{ "code", "reason", "wasClean" }) |key| try row.put(result, key, try v.optional(&row, options, key));
                    },
                }
                return c.JS_DupValue(host.context, result);
            }
        };
        const constructor = try scope.own(try @import("native_class.zig").constructor(engine, name(kind), if (kind == .callback) 1 else 2, prototype, Construct.call, &.{base}));
        if (c.JS_SetPrototype(engine.context, constructor, base) < 0) return v.js.capture(engine);
        try scope.put(classes, @tagName(kind), constructor);
    }
    return c.JS_DupValue(engine.context, classes);
}
pub fn construct(scope: *Scope, classes: c.JSValue, comptime kind: Kind, message: c.JSValue, options: c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{ message, options };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(classes, @tagName(kind)), if (kind == .callback) 1 else args.len, &args)));
}
pub fn raise(scope: *Scope, reason: c.JSValue) anyerror {
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason))) catch |err| return err;
    unreachable;
}
pub fn nonTransport(scope: *Scope, classes: c.JSValue, error_value: c.JSValue) !bool {
    inline for (.{ Kind.api, Kind.protocol, Kind.callback }) |kind| if (try instance(scope, error_value, try scope.get(classes, @tagName(kind)))) return true;
    return false;
}
pub fn apiCode(scope: *Scope, classes: c.JSValue, value: c.JSValue, code: []const u8) !bool {
    return try instance(scope, value, try scope.get(classes, "api")) and try v.eq(scope, try scope.get(value, "code"), code);
}
pub fn socketError(scope: *Scope, event: c.JSValue) !c.JSValue {
    if (scope.truthy(event) and c.JS_IsObject(event) and !c.JS_IsFunction(scope.engine.context, event)) {
        const message = if (try v.js.hasKey(scope.engine, event, try scope.text("message"))) try scope.get(event, "message") else c.pi_js_undefined();
        if (c.JS_IsString(message) and try v.length(scope, message) > 0) return scope.own(try v.js.builtin(scope.engine, "Error", &.{message}));
        const nested = if (try v.js.hasKey(scope.engine, event, try scope.text("error"))) try scope.get(event, "error") else c.pi_js_undefined();
        if (try instance(scope, nested, try scope.global("Error")) and try v.length(scope, try scope.get(nested, "message")) > 0) return nested;
        if (scope.truthy(nested) and c.JS_IsObject(nested) and !c.JS_IsFunction(scope.engine.context, nested) and try v.js.hasKey(scope.engine, nested, try scope.text("message"))) {
            const value = try scope.get(nested, "message");
            if (c.JS_IsString(value) and try v.length(scope, value) > 0) return scope.own(try v.js.builtin(scope.engine, "Error", &.{value}));
        }
    }
    return scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("WebSocket error")}));
}
pub fn socketClose(scope: *Scope, classes: c.JSValue, event: c.JSValue) !c.JSValue {
    if (!scope.truthy(event) or !c.JS_IsObject(event) or c.JS_IsFunction(scope.engine.context, event)) return scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("WebSocket closed")}));
    const code = if (try v.js.hasKey(scope.engine, event, try scope.text("code"))) try scope.get(event, "code") else c.pi_js_undefined();
    const reason = if (try v.js.hasKey(scope.engine, event, try scope.text("reason"))) try scope.get(event, "reason") else c.pi_js_undefined();
    const clean = if (try v.js.hasKey(scope.engine, event, try scope.text("wasClean"))) try scope.get(event, "wasClean") else c.pi_js_undefined();
    const has_reason = c.JS_IsString(reason) and try v.length(scope, reason) > 0;
    var message = try scope.text("WebSocket closed");
    if (c.JS_IsNumber(code)) message = try scope.concat(try scope.concat(message, try scope.text(" ")), try scope.stringify(code));
    if (has_reason) message = try scope.concat(try scope.concat(message, try scope.text(" ")), reason) else if (scope.equal(code, c.JS_NewInt32(scope.engine.context, 1009))) message = try scope.concat(message, try scope.text(" message too big"));
    const options = try scope.object();
    try scope.put(options, "code", if (c.JS_IsNumber(code)) code else c.pi_js_undefined());
    try scope.put(options, "reason", if (has_reason) reason else c.pi_js_undefined());
    try scope.put(options, "wasClean", if (c.JS_IsBool(clean)) clean else c.pi_js_undefined());
    return construct(scope, classes, .close, try scope.invoke(message, "trim", &.{}), options);
}
