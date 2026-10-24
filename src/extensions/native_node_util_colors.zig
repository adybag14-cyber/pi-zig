// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete internal/util/colors.js module body. The genuine Module assembler
//! supplies its actual process, module and require owners. Internal TTY remains
//! a real lazy require; no terminal depth or FORCE_COLOR policy is synthesized.
const a = @import("native_node_argument_values.zig");
const functions = @import("native_node_module_callable.zig");
const sync = @import("native_sync_arguments.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = a.c;
const Scope = a.Scope;

pub const Inputs = struct {
    process: c.JSValue,
    module: c.JSValue,
    require: c.JSValue,
};

/// Execute the original module body and return its owned undefined completion.
/// The actual module.exports Set and final refresh call are observable. Inputs
/// are borrowed for this call; method closures retain their actual JS owners.
pub fn execute(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    return a.expression(engine, executeBody, .{inputs});
}
fn executeBody(s: *Scope, inputs: Inputs) !c.JSValue {
    const owner = try s.objectProto(c.pi_js_null());
    try s.define(owner, "process", inputs.process, 0);
    try s.define(owner, "module", inputs.module, 0);
    try s.define(owner, "require", inputs.require, 0);
    try s.define(owner, "internalTTY", c.pi_js_undefined(), c.JS_PROP_WRITABLE);
    _ = try a.expression(s.engine, assignExports, .{owner, inputs.module});
    // Re-read the actual module.exports after the ordinary assignment. Its
    // setter may have selected a different record or a different refresh.
    _ = try a.expression(s.engine, invokeRefresh, .{owner});
    return c.pi_js_undefined();
}
fn assignExports(s: *Scope, owner: c.JSValue, module: c.JSValue) !c.JSValue {
    const exports = try s.object();
    inline for (.{ "blue", "green", "white", "red", "gray", "clear", "reset" }) |name|
        try s.define(exports, name, try s.text(""), c.JS_PROP_C_W_E);
    try s.define(exports, "hasColors", a.boolean(s, false), c.JS_PROP_C_W_E);
    const should = try s.own(try functions.createWithArguments(s.engine,
        "shouldColorize", 1, false, .{ .formal_count = 1, .callback = shouldColorizeCallback }, &.{owner}));
    const refresh = try s.own(try functions.createWithArguments(s.engine,
        "refresh", 0, false, .{ .formal_count = 0, .callback = refreshCallback }, &.{owner}));
    try s.define(exports, "shouldColorize", should, c.JS_PROP_C_W_E);
    try s.define(exports, "refresh", refresh, c.JS_PROP_C_W_E);
    try s.put(module, "exports", exports);
    return c.pi_js_undefined();
}
fn invokeRefresh(s: *Scope, owner: c.JSValue) !c.JSValue {
    const module = try s.get(owner, "module");
    const target = try s.get(module, "exports");
    const function = try s.get(target, "refresh");
    _ = try s.call(function, target, &.{});
    return c.pi_js_undefined();
}
fn lazyInternalTTY(s: *Scope, owner: c.JSValue) !c.JSValue {
    const known = try s.get(owner, "internalTTY");
    if (c.JS_IsNull(known) or c.JS_IsUndefined(known)) {
        const require = try s.get(owner, "require");
        const actual = try s.call(require, c.pi_js_undefined(), &.{try s.text("internal/tty")});
        // Null/undefined results remain retryable, as in original ??=. Nested
        // require reentry does not suppress this outer assignment.
        try s.put(owner, "internalTTY", actual);
    }
    return a.duplicate(s.engine, try s.get(owner, "internalTTY"));
}
fn forceColorPresent(s: *Scope, owner: c.JSValue) !c.JSValue {
    const process = try s.get(owner, "process");
    const environment = try s.get(process, "env");
    const forced = try s.get(environment, "FORCE_COLOR");
    return a.boolean(s, !c.JS_IsUndefined(forced));
}
fn forcedDepthValue(s: *Scope, owner: c.JSValue) !c.JSValue {
    const tty = try s.own(try a.expression(s.engine, lazyInternalTTY, .{owner}));
    const method = try s.get(tty, "getColorDepth");
    return a.duplicate(s.engine, try s.call(method, tty, &.{}));
}
fn forcedDepth(s: *Scope, owner: c.JSValue) !c.JSValue {
    // The method/reference temporaries retire before relational coercion.
    const depth = try s.own(try a.expression(s.engine, forcedDepthValue, .{owner}));
    return a.duplicate(s.engine, try s.binary(@intFromEnum(arithmetic.Operation.greater),
        depth, c.JS_NewInt32(s.engine.context, 2)));
}
fn streamTTY(s: *Scope, stream: c.JSValue) !c.JSValue {
    if (c.JS_IsNull(stream) or c.JS_IsUndefined(stream)) return c.pi_js_undefined();
    return a.duplicate(s.engine, try s.get(stream, "isTTY"));
}
fn hasDepthMethod(s: *Scope, stream: c.JSValue) !c.JSValue {
    const selected = try s.get(stream, "getColorDepth");
    return a.boolean(s, c.JS_IsFunction(s.engine.context, selected));
}
fn streamDepthValue(s: *Scope, stream: c.JSValue) !c.JSValue {
    // The typeof check's earlier method has already retired before this read.
    const method = try s.get(stream, "getColorDepth");
    return a.duplicate(s.engine, try s.call(method, stream, &.{}));
}
fn streamColor(s: *Scope, stream: c.JSValue) !c.JSValue {
    // Optional access and && preserve undefined/null/raw falsy property values.
    const tty = try a.expression(s.engine, streamTTY, .{stream});
    if (!s.truthy(tty)) return tty;
    // A truthy left operand is discarded before the right operand starts.
    var completion = a.owned.Completion.initVoid(s.engine, {});
    completion.release(tty);
    try completion.finishVoid();
    if (!try a.condition(s.engine, hasDepthMethod, .{stream})) return a.boolean(s, true);
    // typeof stream.getColorDepth and stream.getColorDepth() are TWO reads.
    const depth = try s.own(try a.expression(s.engine, streamDepthValue, .{stream}));
    return a.duplicate(s.engine, try s.binary(@intFromEnum(arithmetic.Operation.greater),
        depth, c.JS_NewInt32(s.engine.context, 2)));
}
fn shouldColorize(s: *Scope, owner: c.JSValue, stream: c.JSValue) !c.JSValue {
    if (try a.condition(s.engine, forceColorPresent, .{owner}))
        return a.expression(s.engine, forcedDepth, .{owner});
    return a.expression(s.engine, streamColor, .{stream});
}
fn shouldColorizeCallback(engine: *a.v.em.Engine, _: c.JSValue,
    args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, shouldColorize, .{roots[0], args.get(0)});
}
fn refreshCondition(s: *Scope, owner: c.JSValue) !c.JSValue {
    const module = try s.get(owner, "module");
    const target = try s.get(module, "exports");
    const method = try s.get(target, "shouldColorize");
    const process = try s.get(owner, "process");
    const stream = try s.get(process, "stderr");
    return a.boolean(s, s.truthy(try s.call(method, target, &.{stream})));
}
fn setColor(s: *Scope, owner: c.JSValue, name: [*:0]const u8, bytes: []const u8) !c.JSValue {
    // Every original assignment resolves module.exports anew before its RHS.
    const target = try s.get(try s.get(owner, "module"), "exports");
    const text = try s.text(bytes);
    try s.put(target, name, text);
    return c.pi_js_undefined();
}
fn setHasColors(s: *Scope, owner: c.JSValue, enabled: bool) !c.JSValue {
    const target = try s.get(try s.get(owner, "module"), "exports");
    try s.put(target, "hasColors", a.boolean(s, enabled));
    return c.pi_js_undefined();
}
fn refreshBody(s: *Scope, owner: c.JSValue) !c.JSValue {
    const enabled = try a.condition(s.engine, refreshCondition, .{owner});
    inline for (.{
        .{ "blue", "\x1b[34m" }, .{ "green", "\x1b[32m" },
        .{ "white", "\x1b[39m" }, .{ "yellow", "\x1b[33m" },
        .{ "red", "\x1b[31m" }, .{ "gray", "\x1b[90m" },
        .{ "clear", "\x1bc" }, .{ "reset", "\x1b[0m" },
    }) |entry| {
        _ = try a.expression(s.engine, setColor, .{
            owner, @as([*:0]const u8, entry[0]), @as([]const u8, if (enabled) entry[1] else ""),
        });
    }
    _ = try a.expression(s.engine, setHasColors, .{owner, enabled});
    return c.pi_js_undefined();
}
fn refreshCallback(engine: *a.v.em.Engine, _: c.JSValue,
    _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, refreshBody, .{roots[0]});
}
