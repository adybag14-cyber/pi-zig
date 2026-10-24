// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete original internal/util/debuglog formatTime and pad bodies.
//! Arithmetic and formatting run through the original captured VM operations;
//! this is not a host floating-point approximation of Source coercion.
const a = @import("native_node_argument_values.zig");
const functions = @import("native_node_module_callable.zig");
const sync = @import("native_sync_arguments.zig");
const c = a.c;
const Scope = a.Scope;
const Frame = a.frames.Frame(enum { hours, minutes, seconds, result });
fn number(s: *Scope, value: i32) c.JSValue { return c.JS_NewInt32(s.engine.context, value); }
fn intrinsic(s: *Scope, name: [*:0]const u8) !c.JSValue { return s.get(s.engine.intrinsic_clone_operations, name); }
pub fn create(engine: *a.v.em.Engine) !c.JSValue {
    return functions.createWithArguments(engine, "formatTime", 1, true,
        .{ .formal_count = 1, .callback = callback, .hooks = sync.frameHooks(Frame) }, &.{});
}
fn callback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    _: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, body, .{args});
}
fn atLeast(s: *Scope, value: c.JSValue, threshold: i32) !c.JSValue {
    return a.boolean(s, s.truthy(try s.binary(7, value, number(s, threshold))));
}
fn quotient(s: *Scope, value: c.JSValue, divisor: i32, floor: bool) !c.JSValue {
    const method = if (floor) try intrinsic(s, "Math.floor") else c.pi_js_undefined();
    const result = try s.binary(3, value, number(s, divisor));
    return a.duplicate(s.engine, if (floor) try s.call(method, c.pi_js_undefined(), &.{result}) else result);
}
fn remainder(s: *Scope, value: c.JSValue, divisor: i32) !c.JSValue {
    return a.duplicate(s.engine, try s.binary(8, value, number(s, divisor)));
}
fn pad(s: *Scope, value: c.JSValue) !c.JSValue {
    const method = try intrinsic(s, "String.padStart");
    const text = try s.toString(value);
    return a.duplicate(s.engine, try s.call(method, text, &.{number(s, 2), try s.text("0")}));
}
fn fixed(s: *Scope, value: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try intrinsic(s, "Number.toFixed"), value, &.{number(s, 3)}));
}
fn splitAssignment(s: *Scope, args: *sync.Arguments, frame: *Frame) !c.JSValue {
    // Original object-pattern assignment reads index0, assigns seconds, then
    // reads index1 and assigns ms. String.prototype[Symbol.split] can reenter.
    const split = try intrinsic(s, "String.split");
    const text = try s.own(try a.expression(s.engine, fixed, .{frame.get(.seconds)}));
    const raw_parts = try s.call(split, text, &.{try s.text("."), number(s, 2)});
    // Original object destructuring converts once before either indexed Get.
    const parts = try @import("native_sdk_guest_operation.zig").toObject(&s.values, raw_parts);
    try frame.copy(.seconds, try s.getKey(parts, number(s, 0)));
    try args.copy(0, try s.getKey(parts, number(s, 1)));
    return c.pi_js_undefined();
}
fn prefix(s: *Scope, frame: *Frame) !c.JSValue {
    if (s.equal(frame.get(.hours), number(s, 0)))
        return a.duplicate(s.engine, frame.get(.minutes));
    const hours = try s.toString(frame.get(.hours));
    const start = try a.add(s, hours, try s.text(":"));
    const minutes = try s.own(try a.expression(s.engine, pad, .{frame.get(.minutes)}));
    return a.duplicate(s.engine, try a.add(s, start, try s.toString(minutes)));
}
fn longResult(s: *Scope, args: *sync.Arguments, frame: *Frame) !c.JSValue {
    const begin = try s.toString(frame.get(.result));
    const first = try a.add(s, begin, try s.text(":"));
    const seconds = try s.own(try a.expression(s.engine, pad, .{frame.get(.seconds)}));
    const second = try a.add(s, first, try s.toString(seconds));
    const third = try a.add(s, second, try s.text("."));
    const fourth = try a.add(s, third, try s.toString(args.get(0)));
    const fifth = try a.add(s, fourth, try s.text(" ("));
    const unit = try s.text(if (!s.equal(frame.get(.hours), number(s, 0))) "h:m" else "");
    const sixth = try a.add(s, fifth, unit);
    return a.duplicate(s.engine, try a.add(s, sixth, try s.text("m:ss.mmm)")));
}
fn secondsResult(s: *Scope, value: c.JSValue) !c.JSValue {
    const text = try s.own(try a.expression(s.engine, fixed, .{value}));
    return a.duplicate(s.engine, try a.add(s, try s.toString(text), try s.text("s")));
}
fn millisecondsResult(s: *Scope, value: c.JSValue) !c.JSValue {
    const constructor = try intrinsic(s, "Number");
    const text = try s.own(try a.expression(s.engine, fixed, .{value}));
    const result = try s.call(constructor, c.pi_js_undefined(), &.{text});
    return a.duplicate(s.engine, try a.add(s, try s.toString(result), try s.text("ms")));
}
fn body(s: *Scope, args: *sync.Arguments) anyerror!c.JSValue {
    const frame = try args.createFrame(&s.values, Frame);
    try frame.copy(.hours, number(s, 0));
    try frame.copy(.minutes, number(s, 0));
    try frame.copy(.seconds, number(s, 0));
    if (try a.condition(s.engine, atLeast, .{args.get(0), @as(i32, 1000)})) {
        if (try a.condition(s.engine, atLeast, .{args.get(0), @as(i32, 60000)})) {
            if (try a.condition(s.engine, atLeast, .{args.get(0), @as(i32, 3600000)})) {
                try frame.take(.hours, a.expression(s.engine, quotient, .{args.get(0), @as(i32, 3600000), true}));
                try args.take(0, a.expression(s.engine, remainder, .{args.get(0), @as(i32, 3600000)}));
            }
            try frame.take(.minutes, a.expression(s.engine, quotient, .{args.get(0), @as(i32, 60000), true}));
            try args.take(0, a.expression(s.engine, remainder, .{args.get(0), @as(i32, 60000)}));
        }
        try frame.take(.seconds, a.expression(s.engine, quotient, .{args.get(0), @as(i32, 1000), false}));
    }
    if (!s.equal(frame.get(.hours), number(s, 0)) or !s.equal(frame.get(.minutes), number(s, 0))) {
        _ = try a.expression(s.engine, splitAssignment, .{args, frame});
        try frame.take(.result, a.expression(s.engine, prefix, .{frame}));
        return a.expression(s.engine, longResult, .{args, frame});
    }
    if (!s.equal(frame.get(.seconds), number(s, 0)))
        return a.expression(s.engine, secondsResult, .{frame.get(.seconds)});
    return a.expression(s.engine, millisecondsResult, .{args.get(0)});
}
