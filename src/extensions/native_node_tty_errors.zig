//! Actual registered Node error classes consumed by tty.js/internal/tty.
//! Message/inspect/util dependencies are genuine internal module functions;
//! no ordinary Error+name/code relabeling or executable JS implementation.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const f = @import("native_node_module_callable.zig");
const classes = @import("native_node_error_class.zig");
const shared = @import("native_node_system_errors.zig");
pub const Inputs = struct {
    /// Actual retained internal/errors message functions (not prebuilt strings).
    invalid_fd_message: c.JSValue,
    invalid_arg_type_message: c.JSValue,
    out_of_range_message: c.JSValue,
    /// Actual internal require used by lazy ErrnoException util lookup.
    require: c.JSValue,
};
pub const Exports = struct {
    invalid_fd: c.JSValue, invalid_arg_type: c.JSValue,
    out_of_range: c.JSValue, tty_init_failed: c.JSValue, errno_exception: c.JSValue,
    pub fn deinit(self: Exports, engine: *v.em.Engine) void {
        inline for (.{ "invalid_fd", "invalid_arg_type", "out_of_range", "tty_init_failed", "errno_exception" }) |name| engine.freeValue(@field(self, name));
    }
};
fn define(s: *v.Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue, flags: c_int) !void {
    if (c.JS_DefinePropertyValueStr(s.engine.context, object, name, c.JS_DupValue(s.engine.context, value), flags | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
    try h.pending(s.engine);
}
fn getter(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return c.JS_DupValue(engine.context, roots[0]); }
fn accessor(s: *v.Scope, prototype: c.JSValue, name: c.JSValue, label: [*:0]const u8, returned: c.JSValue) !void {
    const atom = try v.js.atom(s.engine, name); defer c.JS_FreeAtom(s.engine.context, atom);
    const method = try s.own(try f.create(s.engine, label, 0, false, getter, &.{returned}));
    if (c.JS_DefinePropertyGetSet(s.engine.context, prototype, atom, c.JS_DupValue(s.engine.context, method), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
}
fn stringify(s: *v.Scope, value: c.JSValue) !c.JSValue { return s.own(try h.success(s.engine, try s.engine.checked(c.JS_ToString(s.engine.context, value)))); }
fn concat(s: *v.Scope, left: c.JSValue, right: c.JSValue) !c.JSValue { return h.binary(s, .add, left, right); }
fn nodeString(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var message = try concat(&s, try stringify(&s, try h.get(&s, receiver, "name")), try s.text(" ["));
    message = try concat(&s, message, roots[0]); message = try concat(&s, message, try s.text("]: "));
    message = try concat(&s, message, try stringify(&s, try h.get(&s, receiver, "message")));
    return c.JS_DupValue(engine.context, message);
}
fn nodeConstruct(engine: *v.em.Engine, callee: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var value: c.JSValue = undefined;
    if (s.truthy(roots[2])) {
        // Static %s registration formats BEFORE super(message), exactly as
        // makeNodeErrorWithCode's expectedLength>0 constructor branch.
        const message = try h.call(&s, roots[1], c.pi_js_undefined(), args);
        value = try classes.superConstruct(&s, callee, target, &.{message});
        try define(&s, value, "code", roots[0], c.JS_PROP_C_W_E);
    } else {
        // Function message registration: super(), class field code=key, then
        // message function/DefineProperty. Code is an own class field, so an
        // inherited setter must NOT intercept this branch (unlike SystemError).
        value = try classes.superConstruct(&s, callee, target, &.{});
        try define(&s, value, "code", roots[0], c.JS_PROP_C_W_E);
        const message = try h.call(&s, roots[1], value, args);
        try define(&s, value, "message", message, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    }
    return c.JS_DupValue(engine.context, value);
}
fn make(s: *v.Scope, base: c.JSValue, key: []const u8, message: c.JSValue, static_message: bool, marker: c.JSValue) !c.JSValue {
    const prototype = try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, try h.get(s, base, "prototype"))));
    const node = try s.own(try classes.create(s.engine, "NodeError", 0, prototype, base, nodeConstruct, &.{ try s.text(key), message, c.pi_js_bool(s.engine.context, @intFromBool(static_message)) }));
    // Source's constructor getter intentionally reports the original Base.
    try accessor(s, prototype, try s.text("constructor"), "get constructor", base);
    try accessor(s, prototype, marker, "get [kIsNodeError]", c.pi_js_bool(s.engine.context, 1));
    try define(s, prototype, "toString", try s.own(try f.create(s.engine, "toString", 0, false, nodeString, &.{try s.text(key)})), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    return node;
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    inline for (.{ inputs.invalid_fd_message, inputs.invalid_arg_type_message, inputs.out_of_range_message, inputs.require }) |function| if (!c.JS_IsFunction(engine.context, function)) return error.RequiredGenuineTtyErrorMessageDependency;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const core = try @import("native_node_stream.zig").owner(engine);
    const error_type = try h.get(&s, core, "Error"); const range_type = try h.get(&s, core, "RangeError"); const type_type = try h.get(&s, core, "TypeError");
    const marker = try h.get(&s, try shared.registry(engine), "marker");
    const invalid_fd = try make(&s, range_type, "ERR_INVALID_FD", inputs.invalid_fd_message, true, marker);
    const invalid_arg = try make(&s, type_type, "ERR_INVALID_ARG_TYPE", inputs.invalid_arg_type_message, false, marker);
    const out_of_range = try make(&s, range_type, "ERR_OUT_OF_RANGE", inputs.out_of_range_message, false, marker);
    const lexical = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try h.put(engine, lexical, "util", c.pi_js_undefined());
    const errno_proto = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, try h.get(&s, error_type, "prototype"))));
    const errno = try s.own(try classes.create(engine, "ErrnoException", 3, errno_proto, error_type, errnoConstruct, &.{ lexical, inputs.require }));
    try accessor(&s, errno_proto, try s.text("constructor"), "get constructor", error_type);
    const init = try s.own(try shared.constructor(engine, "ERR_TTY_INIT_FAILED"));
    return .{ .invalid_fd = c.JS_DupValue(engine.context, invalid_fd), .invalid_arg_type = c.JS_DupValue(engine.context, invalid_arg), .out_of_range = c.JS_DupValue(engine.context, out_of_range), .tty_init_failed = c.JS_DupValue(engine.context, init), .errno_exception = c.JS_DupValue(engine.context, errno) };
}
fn errnoConstruct(engine: *v.em.Engine, callee: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var util = try h.get(&s, roots[0], "util");
    if (v.nullish(util)) {
        util = try h.call(&s, roots[1], c.pi_js_undefined(), &.{try s.text("util")});
        try h.put(engine, roots[0], "util", util);
    }
    const function = try h.get(&s, util, "getSystemErrorName");
    const code = try h.call(&s, function, util, &.{h.arg(args, 0)});
    var message = try concat(&s, try stringify(&s, h.arg(args, 1)), try s.text(" "));
    message = try concat(&s, message, try stringify(&s, code));
    if (s.truthy(h.arg(args, 2))) { message = try concat(&s, message, try s.text(" ")); message = try concat(&s, message, try stringify(&s, h.arg(args, 2))); }
    const value = try classes.superConstruct(&s, callee, target, &.{message});
    try h.set(&s, value, "errno", h.arg(args, 0));
    try h.set(&s, value, "code", code);
    try h.set(&s, value, "syscall", h.arg(args, 1));
    return c.JS_DupValue(engine.context, value);
}
