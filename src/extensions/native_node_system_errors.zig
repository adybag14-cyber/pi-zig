//! One genuine SystemError parent/marker for registered native Node codes.
//! Node24 internal/errors actual context algorithm. Stack/custom inspection
//! expansion remains separately unqualified, as in the existing fs producer.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const f = @import("native_node_module_callable.zig");
const classes = @import("native_node_error_class.zig");
const key = "pi-native:private/internal-system-errors";
fn define(s: *v.Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue, flags: c_int) !void {
    if (c.JS_DefinePropertyValueStr(s.engine.context, object, name, c.JS_DupValue(s.engine.context, value), flags | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
    try h.pending(s.engine);
}
fn accessor(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const name = try engine.toString(roots[1]); defer engine.gpa.free(name);
    const terminated = try engine.gpa.dupeZ(u8, name); defer engine.gpa.free(terminated);
    const context = roots[0];
    if (s.truthy(roots[2])) {
        var value = h.arg(args, 0);
        if (s.truthy(roots[3])) {
            if (s.truthy(value)) {
                const module = engine.native_module_values.get("node:buffer") orelse return error.RequiredActualNodeBuffer;
                const buffer = try h.get(&s, module, "Buffer");
                const from = try h.get(&s, buffer, "from");
                value = try h.call(&s, from, buffer, &.{try h.invoke(&s, value, "toString", &.{})});
            } else value = c.pi_js_undefined();
        }
        try h.set(&s, context, terminated, value); return c.pi_js_undefined();
    }
    if (s.truthy(roots[3])) {
        const present = !v.nullish(try h.get(&s, context, terminated));
        // Source reloads for either branch, then calls the selected value's
        // live toString only on the nonnullish branch.
        const selected = try h.get(&s, context, terminated);
        return c.JS_DupValue(engine.context, if (present) try h.invoke(&s, selected, "toString", &.{}) else selected);
    }
    return c.JS_DupValue(engine.context, try h.get(&s, context, terminated));
}
fn addAccessor(s: *v.Scope, object: c.JSValue, context: c.JSValue, name: [*:0]const u8, path: bool) !void {
    const atom = c.JS_NewAtom(s.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return v.js.capture(s.engine);
    defer c.JS_FreeAtom(s.engine.context, atom);
    const roots = [_]c.JSValue{ context, try s.text(@import("std").mem.span(name)), c.pi_js_bool(s.engine.context, 0), c.pi_js_bool(s.engine.context, @intFromBool(path)) };
    const getter = try s.own(try f.create(s.engine, "get", 0, false, accessor, &roots));
    var setter_roots = roots; setter_roots[2] = c.pi_js_bool(s.engine.context, 1);
    const setter = try s.own(try f.create(s.engine, "set", 1, false, accessor, &setter_roots));
    if (c.JS_DefinePropertyGetSet(s.engine.context, object, atom, c.JS_DupValue(s.engine.context, getter), c.JS_DupValue(s.engine.context, setter), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
}
fn string(s: *v.Scope, value: c.JSValue) !c.JSValue { return s.own(try h.success(s.engine, try s.engine.checked(c.JS_ToString(s.engine.context, value)))); }
fn plus(s: *v.Scope, left: c.JSValue, right: c.JSValue) !c.JSValue { return h.binary(s, .add, left, right); }
fn systemConstruct(engine: *v.em.Engine, callee: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const error_key = h.arg(args, 0); const context = h.arg(args, 1);
    const value = try classes.superConstruct(&s, callee, target, &.{});
    const prefix = if (try h.same(&s, error_key, "ERR_SYSTEM_ERROR")) "A system error occurred" else if (try h.same(&s, error_key, "ERR_TTY_INIT_FAILED")) "TTY initialization failed" else return error.RequiredRegisteredNodeSystemError;
    var message = try plus(&s, try s.text(prefix), try s.text(": "));
    message = try plus(&s, message, try string(&s, try h.get(&s, context, "syscall")));
    message = try plus(&s, message, try s.text(" returned "));
    message = try plus(&s, message, try string(&s, try h.get(&s, context, "code")));
    message = try plus(&s, message, try s.text(" ("));
    message = try plus(&s, message, try string(&s, try h.get(&s, context, "message")));
    message = try plus(&s, message, try s.text(")"));
    inline for (.{ "path", "dest" }, .{ " ", " => " }) |name, separator| if (!c.JS_IsUndefined(try h.get(&s, context, name))) {
        message = try plus(&s, message, try s.text(separator));
        message = try plus(&s, message, try string(&s, try h.get(&s, context, name)));
    };
    try h.set(&s, value, "code", error_key);
    const atom = try v.js.atom(engine, roots[0]); defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, value, atom, c.pi_js_bool(engine.context, 1), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    try define(&s, value, "name", try s.text("SystemError"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    try define(&s, value, "message", message, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    try define(&s, value, "info", context, c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE);
    try addAccessor(&s, value, context, "errno", false);
    try addAccessor(&s, value, context, "syscall", false);
    inline for (.{ "path", "dest" }) |name| if (!c.JS_IsUndefined(try h.get(&s, context, name))) try addAccessor(&s, value, context, name, true);
    return c.JS_DupValue(engine.context, value);
}
fn nodeConstruct(engine: *v.em.Engine, callee: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const value = try classes.superConstruct(&s, callee, target, &.{ roots[0], h.arg(args, 0) });
    return c.JS_DupValue(engine.context, value);
}
fn toString(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var text = try plus(&s, try string(&s, try h.get(&s, receiver, "name")), try s.text(" ["));
    text = try plus(&s, text, try string(&s, try h.get(&s, receiver, "code")));
    text = try plus(&s, text, try s.text("]: "));
    text = try plus(&s, text, try string(&s, try h.get(&s, receiver, "message")));
    return c.JS_DupValue(engine.context, text);
}
/// This private cache is UNREGISTERED, so the Engine registered-name guard
/// cannot expose/mutate it through CommonJS. Constant key has no GPA ownership.
pub fn registry(engine: *v.em.Engine) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    if (engine.native_module_values.get(key)) |record| return record;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const core = try @import("native_node_stream.zig").owner(engine);
    const base_error = try h.get(&s, core, "Error");
    const marker = try s.own(try engine.checked(c.JS_NewSymbol(engine.context, "kIsNodeError", false)));
    const prototype = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, try h.get(&s, base_error, "prototype"))));
    const base = try s.own(try classes.create(engine, "SystemError", 2, prototype, base_error, systemConstruct, &.{marker}));
    try define(&s, prototype, "toString", try s.own(try f.create(engine, "toString", 0, false, toString, &.{})), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    const record = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try h.put(engine, record, "SystemError", base);
    try h.put(engine, record, "marker", marker);
    inline for (.{ "ERR_SYSTEM_ERROR", "ERR_TTY_INIT_FAILED" }) |name| {
        const node_proto = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, prototype)));
        const node = try s.own(try classes.create(engine, "NodeError", 1, node_proto, base, nodeConstruct, &.{try s.text(name)}));
        try h.put(engine, record, name, node);
    }
    const retained = c.JS_DupValue(engine.context, record); errdefer engine.freeValue(retained);
    try engine.native_module_values.put(engine.gpa, key, retained);
    return retained;
}
pub fn constructor(engine: *v.em.Engine, name: [*:0]const u8) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return h.success(engine, try v.js.get(engine, try registry(engine), name));
}
pub fn fromContext(engine: *v.em.Engine, name: [*:0]const u8, context: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const function = try s.own(try constructor(engine, name));
    return c.JS_DupValue(engine.context, try h.construct(&s, function, &.{context}));
}
