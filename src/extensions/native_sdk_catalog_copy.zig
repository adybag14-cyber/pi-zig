//! Source object spread: own-descriptor/get operations remain interleaved and
//! descriptor/temporary roots retire before the next Source property access.
const x = @import("native_sdk_catalog_values.zig");
const c = x.c;
pub fn into(o: *x.Ops, target: c.JSValue, source: c.JSValue) !void {
    if (x.nullish(source)) return;
    var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, body(&local, target, source));
}
fn body(o: *x.Ops, target: c.JSValue, source: c.JSValue) !void {
    const e = o.s.engine;
    const boxed = try x.guest.toObject(o.s, source);
    var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
    var boundary: x.guest.Boundary = .{ .engine = e }; try boundary.begin();
    const status = c.JS_GetOwnPropertyNames(e.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK);
    defer if (names != null) c.JS_FreePropertyEnum(e.context, names, count);
    try boundary.finishStatus(status);
    for (names[0..count]) |entry| {
        if (!try enumerable(o, boxed, entry.atom)) continue;
        var s: x.Scope = .{ .engine = e }; var local: x.Ops = .{ .s = &s };
        try x.owned.finishVoid(&s, property(&local, target, boxed, entry.atom));
    }
}
fn enumerable(o: *x.Ops, source: c.JSValue, atom: c.JSAtom) !bool {
    const e = o.s.engine;
    var descriptor: c.JSPropertyDescriptor = undefined;
    var boundary: x.guest.Boundary = .{ .engine = e }; try boundary.begin();
    const raw = c.JS_GetOwnProperty(e.context, &descriptor, source, atom);
    const outcome: anyerror!c.JSValue = if (boundary.finishStatus(raw)) |_|
        c.pi_js_bool(e.context, @intFromBool(raw != 0 and descriptor.flags & c.JS_PROP_ENUMERABLE != 0))
    else |err| err;
    var completion = x.owned.Completion.initValue(e, outcome);
    if (raw > 0) { completion.release(descriptor.value); completion.release(descriptor.getter); completion.release(descriptor.setter); }
    return o.truthy(try completion.finishValue());
}
fn property(o: *x.Ops, target: c.JSValue, source: c.JSValue, atom: c.JSAtom) !void {
    const e = o.s.engine;
    const value = try x.guest.getAtom(o.s, source, atom);
    var boundary: x.guest.Boundary = .{ .engine = e }; try boundary.begin();
    return boundary.finishStatus(c.JS_DefinePropertyValue(e.context, target, atom, c.JS_DupValue(e.context, value), c.JS_PROP_C_W_E));
}
pub fn object(o: *x.Ops, source: c.JSValue) !c.JSValue { const value = try o.object(); try into(o, value, source); return value; }
