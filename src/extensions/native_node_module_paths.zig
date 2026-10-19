// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node v24.14 loader.js _nodeModulePaths. The live path.resolve call
//! precedes the retained UTF-16 primordials and the actual reverse scan.
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const Frame = a.frames.Frame(enum { from, paths, index, last, code });
const nm_len: i32 = 12;
fn number(s: *Scope, value: i32) c.JSValue { return c.JS_NewInt32(s.engine.context, value); }
fn equalNumber(s: *Scope, value: c.JSValue, expected: i32) bool { return s.equal(value, number(s, expected)); }
fn resolve(s: *Scope, owner: c.JSValue, from: c.JSValue) !c.JSValue {
    const paths = try s.get(owner, "paths");
    const function = try s.get(paths, "resolve");
    return a.duplicate(s.engine, try s.call(function, paths, &.{from}));
}
fn code(s: *Scope, owner: c.JSValue, from: c.JSValue, index: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try s.get(owner, "charCodeAt"), from, &.{index}));
}
fn indexFromLength(s: *Scope, from: c.JSValue, subtract: i32) !c.JSValue {
    return a.duplicate(s.engine, try s.binary(1, try s.get(from, "length"), number(s, subtract)));
}
fn drivePart(s: *Scope, owner: c.JSValue, from: c.JSValue, subtract: i32, expected: i32) !c.JSValue {
    const function = try s.get(owner, "charCodeAt");
    const index = try s.own(try a.expression(s.engine, indexFromLength, .{ from, subtract }));
    return a.boolean(s, equalNumber(s, try s.call(function, from, &.{index}), expected));
}
fn singleton(s: *Scope, value: c.JSValue) !c.JSValue {
    const result = try a.array(s);
    try a.index(s, result, 0, value);
    return a.duplicate(s.engine, result);
}
fn rootWindows(s: *Scope, owner: c.JSValue, from: c.JSValue) !c.JSValue {
    const value = try s.binary(0, from, try s.get(owner, "bareNodeModules"));
    return singleton(s, value);
}
fn rootPosix(s: *Scope, owner: c.JSValue) !c.JSValue {
    return singleton(s, try s.get(owner, "rootNodeModules"));
}
fn within(s: *Scope, index: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.binary(7, index, number(s, 0))));
}
fn suffixBody(s: *Scope, owner: c.JSValue, from: c.JSValue, last: c.JSValue, windows: bool) !c.JSValue {
    const function = try s.get(owner, "stringSlice");
    const prefix = try s.own(try a.call(s.engine, function, from, &.{ number(s, 0), last }));
    return a.duplicate(s.engine, try s.binary(0, prefix,
        try s.get(owner, if (windows) "windowsNodeModules" else "posixNodeModules")));
}
fn pushPath(s: *Scope, owner: c.JSValue, frame: *Frame, windows: bool) !c.JSValue {
    // The captured push callee is selected before the sliced suffix argument.
    const function = try s.get(owner, "arrayPush");
    const value = try s.own(try a.expression(s.engine, suffixBody,
        .{ owner, frame.get(.from), frame.get(.last), windows }));
    _ = try s.call(function, frame.get(.paths), &.{value});
    return c.pi_js_undefined();
}
fn pushRoot(s: *Scope, owner: c.JSValue, paths: c.JSValue) !c.JSValue {
    _ = try s.call(try s.get(owner, "arrayPush"), paths, &.{try s.get(owner, "rootNodeModules")});
    return c.pi_js_undefined();
}
fn decrement(s: *Scope, value: c.JSValue) !c.JSValue {
    try s.pending();
    return a.duplicate(s.engine, try s.checked(c.JS_PiDecrement(s.engine.context, value)));
}
fn matches(s: *Scope, owner: c.JSValue, matched: i32, current: c.JSValue) !c.JSValue {
    const chars = try s.get(owner, "nmChars");
    const expected = try s.getKey(chars, number(s, matched));
    return a.boolean(s, s.equal(expected, current));
}
fn newPaths(s: *Scope) !c.JSValue { return a.duplicate(s.engine, try a.array(s)); }
pub fn invoke(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = Frame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, body(&s, frame, roots[0], a.arg(args, 0)));
}
fn body(s: *Scope, frame: *Frame, owner: c.JSValue, original: c.JSValue) !c.JSValue {
    try frame.take(.from, a.expression(s.engine, resolve, .{ owner, original }));
    const windows = s.truthy(try s.get(owner, "windows"));
    if (windows) {
        if (try a.condition(s.engine, drivePart, .{ owner, frame.get(.from), @as(i32, 1), @as(i32, 92) }) and
            try a.condition(s.engine, drivePart, .{ owner, frame.get(.from), @as(i32, 2), @as(i32, 58) }))
            return a.expression(s.engine, rootWindows, .{ owner, frame.get(.from) });
    } else if (s.equal(frame.get(.from), try s.get(owner, "rootSlash"))) {
        return a.expression(s.engine, rootPosix, .{owner});
    }
    try frame.take(.paths, a.expression(s.engine, newPaths, .{}));
    try frame.take(.index, a.expression(s.engine, indexFromLength, .{ frame.get(.from), @as(i32, 1) }));
    var matched: i32 = 0;
    try frame.take(.last, a.field(s.engine, frame.get(.from), "length"));
    var steps: usize = 0;
    while (try a.condition(s.engine, within, .{frame.get(.index)})) {
        try @import("native_node_commonjs_interrupt.zig").step(s.engine, &steps);
        // This const belongs to the for body. Its previous original slot
        // survives the update/condition; true body entry resets it first.
        try frame.clear(.code);
        try frame.take(.code, a.expression(s.engine, code,
            .{ owner, frame.get(.from), frame.get(.index) }));
        const current = frame.get(.code);
        const separator = if (windows)
            equalNumber(s, current, 92) or equalNumber(s, current, 47) or equalNumber(s, current, 58)
        else
            equalNumber(s, current, 47);
        if (separator) {
            if (matched != nm_len) _ = try a.expression(s.engine, pushPath, .{ owner, frame, windows });
            // Source last = i stores the new value before retiring the old.
            try frame.copy(.last, frame.get(.index));
            matched = 0;
        } else if (matched != -1) {
            if (try a.condition(s.engine, matches, .{ owner, matched, current }))
                matched += 1
            else
                matched = -1;
        }
        try frame.take(.index, a.expression(s.engine, decrement, .{frame.get(.index)}));
    }
    if (!windows) _ = try a.expression(s.engine, pushRoot, .{ owner, frame.get(.paths) });
    return a.duplicate(s.engine, frame.get(.paths));
}
