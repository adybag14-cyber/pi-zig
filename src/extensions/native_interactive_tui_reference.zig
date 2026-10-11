//! Source createInteractiveTuiReference: genuine mutable renderer Proxy.
//! Internal composition API; live frontend integration requires its own gates.
const a = @import("native_tui_alt_frame.zig");
const js = a.js;
const c = a.c;
const Frame = a.Frame;
const Trap = enum(c_int) { get, set, has, getPrototypeOf, invoke };

fn call(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var f: Frame = .{ .engine = engine, .object = data[0], .bindings = data[0] };
    defer f.deinit();
    const result = body(&f, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| return a.fail(engine, err);
    return f.result(result);
}
fn closure(f: *Frame, trap: Trap, name: [*:0]const u8, length: c_int, state: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{state};
    return f.own(try f.engine.checked(c.JS_NewCFunctionData2(f.engine.context, call, name, length, @intFromEnum(trap), 1, &data)));
}
fn current(f: *Frame) !c.JSValue {
    return f.own(try js.call(f.engine, try f.field("getTui"), c.pi_js_undefined(), &.{}));
}
fn reflect(f: *Frame, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return f.method(try f.global("Reflect"), name, args);
}
fn body(f: *Frame, trap: Trap, args: []const c.JSValue) anyerror!c.JSValue {
    const tui = try current(f);
    if (trap == .getPrototypeOf) return reflect(f, "getPrototypeOf", &.{tui});
    const property = if (trap == .invoke) try f.field("property") else a.v.arg(args, 1);
    switch (trap) {
        .get => {
            const value = try reflect(f, "get", &.{ tui, property, tui });
            if (!c.JS_IsFunction(f.engine.context, value)) return value;
            const capture = try f.record();
            try f.define(capture, "getTui", try f.field("getTui"));
            try f.define(capture, "property", property);
            try f.define(capture, "methodTui", tui);
            try f.define(capture, "method", value);
            return closure(f, .invoke, "", 0, capture);
        },
        .set => return reflect(f, "set", &.{ tui, property, a.v.arg(args, 2), tui }),
        .has => return reflect(f, "has", &.{ tui, property }),
        .getPrototypeOf => unreachable,
        .invoke => {
            if (!c.JS_IsStrictEqual(f.engine.context, tui, try f.field("methodTui"))) {
                const method = try reflect(f, "get", &.{ tui, property, tui });
                if (!c.JS_IsFunction(f.engine.context, method)) {
                    const text = try f.own(try js.call(f.engine, try f.global("String"), c.pi_js_undefined(), &.{property}));
                    const message = try f.concat(&.{ try f.text("TUI property "), text, try f.text(" is not callable") });
                    const exception = try f.construct(try f.global("TypeError"), &.{message});
                    _ = try f.engine.checked(c.JS_Throw(f.engine.context, c.JS_DupValue(f.engine.context, exception)));
                    unreachable;
                }
                try f.put("methodTui", tui);
                try f.put("method", method);
            }
            return reflect(f, "apply", &.{ try f.field("method"), try f.field("methodTui"), try f.literal(args) });
        },
    }
}
fn reference(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    var f: Frame = .{ .engine = engine, .object = c.pi_js_undefined(), .bindings = c.pi_js_undefined() };
    defer f.deinit();
    const capture = try f.record();
    try f.define(capture, "getTui", a.v.arg(args, 0));
    const handler = try f.record();
    inline for (.{ .{ Trap.get, "get", 2 }, .{ Trap.set, "set", 3 }, .{ Trap.has, "has", 2 }, .{ Trap.getPrototypeOf, "getPrototypeOf", 0 } }) |item| {
        try f.define(handler, item[1], try closure(&f, item[0], item[1], item[2], capture));
    }
    return f.result(try f.construct(try f.global("Proxy"), &.{ try f.record(), handler }));
}
pub fn create(engine: *js.Engine) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "createInteractiveTuiReference", 1, reference, &.{});
}
