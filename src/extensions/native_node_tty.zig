//! Node24.14 lib/tty.js, Joyent/Node contributors MIT (retained authority).
//! Ordinary actual TTY constructors over canonical net.Socket and tty_wrap.
//! No fs.WriteStream alias, dummy Duplex, fd/HANDLE cast or framed-stdout IO.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const f = @import("native_node_module_callable.zig");
const h = @import("native_node_tty_values.zig");
const colors = @import("native_node_tty_colors.zig");
const arithmetic = @import("native_image_arithmetic.zig");
pub const Inputs = struct {
    /// Actual imported net namespace, whose canonical Socket admits real TTY
    /// handles through its native, Engine-checked handle-adopter interface.
    net: c.JSValue,
    /// Real internal tty binding. TTY owns/adopts a genuine fd endpoint and
    /// populates ctx on OS failure; isTTY checks real native descriptor kind.
    /// A remote frontend must supply its authenticated fd lease, never the
    /// worker's framed stdio. This factory does not manufacture that identity.
    tty_constructor: c.JSValue,
    is_tty: c.JSValue,
    invalid_fd: c.JSValue,
    tty_init_failed: c.JSValue,
    errno_exception: c.JSValue,
    /// Actual require for lazy readline. One successful module value is cached.
    require: c.JSValue,
    number_is_integer: c.JSValue,
    colors: colors.Exports,
};
const R = enum(usize) { lexical, net, tty, is_tty, invalid_fd, init_failed, errno, require, integer };
fn root(roots: []const c.JSValue, index: R) c.JSValue { return roots[@intFromEnum(index)]; }
fn constructor(s: *v.Scope, name: [*:0]const u8, length: c_int, callback: f.Callback, roots: []const c.JSValue, net: c.JSValue) !c.JSValue {
    const function = try s.own(try f.create(s.engine, name, length, true, callback, roots));
    const prototype = try h.get(s, function, "prototype");
    const socket_prototype = try h.get(s, try h.get(s, net, "Socket"), "prototype");
    if (c.JS_SetPrototype(s.engine.context, prototype, socket_prototype) < 0) return v.js.capture(s.engine);
    if (c.JS_SetPrototype(s.engine.context, function, try h.get(s, net, "Socket")) < 0) return v.js.capture(s.engine);
    return function;
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    inline for (.{ inputs.tty_constructor, inputs.is_tty, inputs.invalid_fd, inputs.tty_init_failed, inputs.errno_exception, inputs.require, inputs.number_is_integer, inputs.colors.get_color_depth, inputs.colors.has_colors }) |function| {
        if (!c.JS_IsFunction(engine.context, function)) return error.RequiredActualNodeTtyDependency;
    }
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const lexical = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try h.put(engine, lexical, "readline", c.pi_js_undefined());
    const roots = [_]c.JSValue{ lexical, inputs.net, inputs.tty_constructor, inputs.is_tty, inputs.invalid_fd, inputs.tty_init_failed, inputs.errno_exception, inputs.require, inputs.number_is_integer };
    const read = try constructor(&s, "ReadStream", 2, readStream, &roots, inputs.net);
    // Unexposed lexical cells provide constructor identity for instanceof and
    // bare-call allocation. Both function/prototype cycles are traced by f.
    try h.put(engine, lexical, "ReadStream", read);
    const read_prototype = try h.get(&s, read, "prototype");
    try h.set(&s, read_prototype, "setRawMode", try s.own(try f.create(engine, "", 1, true, setRawMode, &roots)));
    const write = try constructor(&s, "WriteStream", 1, writeStream, &roots, inputs.net);
    try h.put(engine, lexical, "WriteStream", write);
    const write_prototype = try h.get(&s, write, "prototype");
    try h.set(&s, write_prototype, "isTTY", c.pi_js_bool(engine.context, 1));
    try h.set(&s, write_prototype, "getColorDepth", inputs.colors.get_color_depth);
    try h.set(&s, write_prototype, "hasColors", inputs.colors.has_colors);
    try h.set(&s, write_prototype, "_refreshSize", try s.own(try f.create(engine, "", 0, true, refreshSize, &roots)));
    inline for (.{ .{ "cursorTo", 3 }, .{ "moveCursor", 3 }, .{ "clearLine", 2 }, .{ "clearScreenDown", 1 } }) |entry| {
        const method_roots = roots ++ [_]c.JSValue{try s.text(entry[0])};
        try h.set(&s, write_prototype, entry[0], try s.own(try f.create(engine, "", entry[1], true, readlineMethod, &method_roots)));
    }
    try h.set(&s, write_prototype, "getWindowSize", try s.own(try f.create(engine, "", 0, true, getWindowSize, &.{})));
    const result = try s.object();
    try h.put(engine, result, "isatty", try s.own(try f.create(engine, "isatty", 1, true, isatty, &roots)));
    try h.put(engine, result, "ReadStream", read);
    try h.put(engine, result, "WriteStream", write);
    return c.JS_DupValue(engine.context, result);
}
fn instance(s: *v.Scope, receiver: c.JSValue, function: c.JSValue) !bool {
    const result = c.JS_IsInstanceOf(s.engine.context, receiver, function);
    if (result < 0) return v.js.capture(s.engine);
    try h.pending(s.engine);
    return result != 0;
}
fn fdValid(s: *v.Scope, fd: c.JSValue, roots: []const c.JSValue) !void {
    // Actual >> must run before strict comparison. This retains Symbol/BigInt
    // failures and object coercion, without coercing strings into accepted fds.
    const shifted = try h.binary(s, .shift_right, fd, c.JS_NewInt32(s.engine.context, 0));
    try h.pending(s.engine);
    if (!s.equal(shifted, fd) or try arithmetic.compare(s.engine, .less, fd, c.JS_NewInt32(s.engine.context, 0))) {
        return h.throwValue(s.engine, try h.construct(s, root(roots, .invalid_fd), &.{fd}));
    }
}
fn stream(s: *v.Scope, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, readable: bool) !c.JSValue {
    const engine = s.engine;
    const function = try h.get(s, root(roots, .lexical), if (readable) "ReadStream" else "WriteStream");
    if (!try instance(s, receiver, function)) {
        // Source bare calls retain exactly the declared parameter count.
        const parameters = [_]c.JSValue{ h.arg(args, 0), h.arg(args, 1) };
        const object = try h.construct(s, function, parameters[0..if (readable) @as(usize, 2) else 1]);
        return c.JS_DupValue(engine.context, object);
    }
    const fd = h.arg(args, 0);
    try fdValid(s, fd, roots);
    const context = try s.object();
    const tty = try h.construct(s, root(roots, .tty), &.{ fd, context });
    if (!c.JS_IsUndefined(try h.get(s, context, "code"))) return h.throwValue(engine, try h.construct(s, root(roots, .init_failed), &.{context}));
    // Socket.call is deliberately a live ordinary property lookup. Options
    // spread occurs AFTER selecting the call callee, exactly as the Source.
    const socket = try h.get(s, root(roots, .net), "Socket");
    const call_function = try h.get(s, socket, "call");
    const options = try s.object();
    try h.put(engine, options, "readableHighWaterMark", c.JS_NewInt32(engine.context, 0));
    try h.put(engine, options, "handle", tty);
    try h.put(engine, options, "manualStart", c.pi_js_bool(engine.context, 1));
    if (readable) try spread(s, options, h.arg(args, 1));
    _ = try h.call(s, call_function, socket, &.{ receiver, options });
    if (readable) {
        try h.set(s, receiver, "isRaw", c.pi_js_bool(engine.context, 0));
        try h.set(s, receiver, "isTTY", c.pi_js_bool(engine.context, 1));
    } else {
        const handle = try h.get(s, receiver, "_handle");
        _ = try h.invoke(s, handle, "setBlocking", &.{c.pi_js_bool(engine.context, 1)});
        const dimensions = try windowArray(s);
        const second_handle = try h.get(s, receiver, "_handle");
        const err = try h.invoke(s, second_handle, "getWindowSize", &.{dimensions});
        if (!s.truthy(err)) {
            try h.set(s, receiver, "columns", try index(s, dimensions, 0));
            try h.set(s, receiver, "rows", try index(s, dimensions, 1));
        }
    }
    return c.pi_js_undefined();
}
fn readStream(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    return stream(&s, receiver, args, roots, true);
}
fn writeStream(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    return stream(&s, receiver, args, roots, false);
}
fn isatty(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const fd = h.arg(args, 0);
    if (!s.truthy(try h.call(&s, root(roots, .integer), c.pi_js_undefined(), &.{fd})) or !try arithmetic.compare(engine, .greater_equal, fd, c.JS_NewInt32(engine.context, 0)) or !try arithmetic.compare(engine, .less_equal, fd, c.JS_NewInt32(engine.context, 2147483647))) return c.pi_js_bool(engine.context, 0);
    const result = try h.call(&s, root(roots, .is_tty), c.pi_js_undefined(), &.{fd});
    return c.JS_DupValue(engine.context, result);
}
fn emitError(s: *v.Scope, receiver: c.JSValue, roots: []const c.JSValue, err: c.JSValue, syscall: []const u8) !void {
    const emit = try h.get(s, receiver, "emit");
    const exception = try h.construct(s, root(roots, .errno), &.{ err, try s.text(syscall) });
    _ = try h.call(s, emit, receiver, &.{ try s.text("error"), exception });
}
fn setRawMode(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const flag = c.pi_js_bool(engine.context, @intFromBool(s.truthy(h.arg(args, 0))));
    const handle = try h.get(&s, receiver, "_handle");
    const err = if (v.nullish(handle)) c.pi_js_undefined() else try h.invoke(&s, handle, "setRawMode", &.{flag});
    if (s.truthy(err)) try emitError(&s, receiver, roots, err, "setRawMode") else try h.set(&s, receiver, "isRaw", flag);
    return c.JS_DupValue(engine.context, receiver);
}
fn index(s: *v.Scope, array: c.JSValue, position: u32) !c.JSValue {
    return s.own(try h.success(s.engine, try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, array, position))));
}
fn windowArray(s: *v.Scope) !c.JSValue {
    const array = try s.array();
    try s.index(array, 0, c.JS_NewInt32(s.engine.context, 0));
    try s.index(array, 1, c.JS_NewInt32(s.engine.context, 0));
    return array;
}
fn refreshSize(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const old_columns = try h.get(&s, receiver, "columns");
    const old_rows = try h.get(&s, receiver, "rows");
    const dimensions = try windowArray(&s);
    const handle = try h.get(&s, receiver, "_handle");
    const err = try h.invoke(&s, handle, "getWindowSize", &.{dimensions});
    if (s.truthy(err)) {
        try emitError(&s, receiver, roots, err, "getWindowSize");
        return c.pi_js_undefined();
    }
    const columns = try index(&s, dimensions, 0);
    const rows = try index(&s, dimensions, 1);
    if (!s.equal(old_columns, columns) or !s.equal(old_rows, rows)) {
        try h.set(&s, receiver, "columns", columns);
        try h.set(&s, receiver, "rows", rows);
        _ = try h.invoke(&s, receiver, "emit", &.{try s.text("resize")});
    }
    return c.pi_js_undefined();
}
fn readlineMethod(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var module = try h.get(&s, root(roots, .lexical), "readline");
    if (c.JS_IsUndefined(module)) {
        module = try h.call(&s, root(roots, .require), c.pi_js_undefined(), &.{try s.text("readline")});
        try h.put(engine, root(roots, .lexical), "readline", module);
    }
    const method = try s.own(try h.success(engine, try v.js.getKey(engine, module, roots[9])));
    const count: usize = if (try h.same(&s, roots[9], "clearScreenDown")) 1 else if (try h.same(&s, roots[9], "clearLine")) 2 else 3;
    const parameters = [_]c.JSValue{ receiver, h.arg(args, 0), h.arg(args, 1), h.arg(args, 2) };
    const result = try h.call(&s, method, module, parameters[0 .. count + 1]);
    return c.JS_DupValue(engine.context, result);
}
fn getWindowSize(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const result = try s.array();
    try s.index(result, 0, try h.get(&s, receiver, "columns"));
    try s.index(result, 1, try h.get(&s, receiver, "rows"));
    return c.JS_DupValue(engine.context, result);
}
fn spread(s: *v.Scope, target: c.JSValue, source: c.JSValue) !void {
    if (v.nullish(source)) return;
    const engine = s.engine;
    const boxed = try s.own(try h.success(engine, try engine.checked(c.JS_ToObject(engine.context, source))));
    var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return v.js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    try h.pending(engine);
    for (names[0..count]) |entry| {
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, boxed, entry.atom);
        if (present < 0) return v.js.capture(engine);
        if (present == 0) { try h.pending(engine); continue; }
        defer engine.freeValue(descriptor.value); defer engine.freeValue(descriptor.getter); defer engine.freeValue(descriptor.setter);
        try h.pending(engine);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try h.success(engine, try engine.checked(c.JS_GetProperty(engine.context, boxed, entry.atom)));
        if (c.JS_DefinePropertyValue(engine.context, target, entry.atom, value, c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
        try h.pending(engine);
    }
}
