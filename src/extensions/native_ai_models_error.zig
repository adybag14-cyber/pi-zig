//! Actual utils/models-error.ts class with Source diagnostic coercion order.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const classes = @import("native_class.zig");
fn arg(args: []const c.JSValue, n: usize) c.JSValue {
    return if (n < args.len) args[n] else c.pi_js_undefined();
}
pub fn formatted(s: *Scope, value: c.JSValue) !c.JSValue {
    const is_error = c.JS_IsInstanceOf(s.engine.context, value, try s.global("Error"));
    if (is_error < 0) return v.js.capture(s.engine);
    if (is_error != 0) {
        const message = try s.get(value, "message");
        return if (s.truthy(message)) message else s.get(value, "name");
    }
    if (c.JS_IsString(value)) return value;
    return s.call(try s.global("String"), c.pi_js_undefined(), &.{value});
}
fn detail(s: *Scope, message: c.JSValue, cause: c.JSValue) !c.JSValue {
    if (v.nullish(cause)) return message;
    const text = try s.invoke(try formatted(s, cause), "trim", &.{});
    if (!s.truthy(text)) return message;
    if (s.truthy(try s.invoke(message, "includes", &.{text}))) return message;
    return s.concat(try s.concat(try s.stringify(message), try s.text(": ")), try s.stringify(text));
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const base = try s.global("Error");
    const prototype = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, try s.get(base, "prototype"))));
    const state = try s.object();
    const Constructor = struct {
        fn call(host: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            const constructor = try local.get(roots[0], "constructor");
            const super = try local.own(try host.checked(c.JS_GetPrototype(host.context, constructor)));
            const options = arg(args, 2);
            const cause = if (v.nullish(options)) c.pi_js_undefined() else try local.get(options, "cause");
            var values = [_]c.JSValue{ try detail(&local, arg(args, 1), cause), options };
            const result = try local.own(try host.checked(c.JS_CallConstructor2(host.context, super, target, values.len, &values)));
            // The declared public TS field initializes after super(), before
            // the constructor's name/code assignments.
            try local.put(result, "code", c.pi_js_undefined());
            // Assignment follows super(), including inherited setters.
            try local.set(result, "name", try local.text("ModelsError"));
            try local.set(result, "code", arg(args, 0));
            return c.JS_DupValue(host.context, result);
        }
    };
    const constructor = try s.own(try classes.constructor(engine, "ModelsError", 3, prototype, Constructor.call, &.{state}));
    try s.put(state, "constructor", constructor);
    if (c.JS_SetPrototype(engine.context, constructor, base) < 0) return v.js.capture(engine);
    return c.JS_DupValue(engine.context, constructor);
}
