// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Original Node24.13 inspect.colors/styles, aliases and stylizeWithColor.
//! The actual inspect function is one retained lexical import; every public
//! styles/colors/index lookup remains live. This does not implement other
//! inspector layouts or replace its actual primitive formatter.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
const inspect_ops = @import("native_node_inspect_operations.zig");
const sync = @import("native_sync_arguments.zig");
const Frame = a.frames.Frame(enum { style, color });

pub const Inputs = struct {
    inspect: c.JSValue,
    object_assign: c.JSValue,
    object_define_property: c.JSValue,
};
fn dup(s: *Scope, value: c.JSValue) c.JSValue {
    return a.duplicate(s.engine, value);
}
fn expression(s: *Scope, comptime body: anytype, args: anytype) !c.JSValue {
    return s.own(try a.expression(s.engine, body, args));
}

// Arrays and table fields are the actual literal own data definitions. The
// numeric code pairs remain separate mutable Arrays with ordinary prototypes.
fn pairBody(s: *Scope, first: i32, last: i32) !c.JSValue {
    const pair = try a.array(s);
    try a.index(s, pair, 0, c.JS_NewInt32(s.engine.context, first));
    try a.index(s, pair, 1, c.JS_NewInt32(s.engine.context, last));
    return dup(s, pair);
}
fn colorsBody(s: *Scope) !c.JSValue {
    const colors = try s.objectProto(c.pi_js_null());
    inline for (.{
        .{ "reset", 0, 0 }, .{ "bold", 1, 22 }, .{ "dim", 2, 22 },
        .{ "italic", 3, 23 }, .{ "underline", 4, 24 }, .{ "blink", 5, 25 },
        .{ "inverse", 7, 27 }, .{ "hidden", 8, 28 }, .{ "strikethrough", 9, 29 },
        .{ "doubleunderline", 21, 24 },
        .{ "black", 30, 39 }, .{ "red", 31, 39 }, .{ "green", 32, 39 },
        .{ "yellow", 33, 39 }, .{ "blue", 34, 39 }, .{ "magenta", 35, 39 },
        .{ "cyan", 36, 39 }, .{ "white", 37, 39 },
        .{ "bgBlack", 40, 49 }, .{ "bgRed", 41, 49 }, .{ "bgGreen", 42, 49 },
        .{ "bgYellow", 43, 49 }, .{ "bgBlue", 44, 49 }, .{ "bgMagenta", 45, 49 },
        .{ "bgCyan", 46, 49 }, .{ "bgWhite", 47, 49 },
        .{ "framed", 51, 54 }, .{ "overlined", 53, 55 },
        .{ "gray", 90, 39 }, .{ "redBright", 91, 39 }, .{ "greenBright", 92, 39 },
        .{ "yellowBright", 93, 39 }, .{ "blueBright", 94, 39 },
        .{ "magentaBright", 95, 39 }, .{ "cyanBright", 96, 39 }, .{ "whiteBright", 97, 39 },
        .{ "bgGray", 100, 49 }, .{ "bgRedBright", 101, 49 }, .{ "bgGreenBright", 102, 49 },
        .{ "bgYellowBright", 103, 49 }, .{ "bgBlueBright", 104, 49 },
        .{ "bgMagentaBright", 105, 49 }, .{ "bgCyanBright", 106, 49 }, .{ "bgWhiteBright", 107, 49 },
    }) |row| {
        const pair = try expression(s, pairBody, .{ row[1], row[2] });
        try s.define(colors, row[0], pair, c.JS_PROP_C_W_E);
    }
    return dup(s, colors);
}
fn publishColors(s: *Scope, inspect: c.JSValue) !c.JSValue {
    const colors = try expression(s, colorsBody, .{});
    try s.put(inspect, "colors", colors);
    return c.pi_js_undefined();
}

fn aliasGetBody(s: *Scope, receiver: c.JSValue, target: c.JSValue) !c.JSValue {
    const name = try sync.read(&s.values, target);
    return dup(s, try s.getKey(receiver, name));
}
fn aliasGet(engine: *a.v.em.Engine, receiver: c.JSValue,
    _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, aliasGetBody, .{ receiver, roots[0] });
}
fn aliasSetBody(s: *Scope, receiver: c.JSValue, args: *sync.Arguments,
    target: c.JSValue) !c.JSValue
{
    const name = try sync.read(&s.values, target);
    try inspect_ops.setKey(&s.values, receiver, name, args.get(0));
    return c.pi_js_undefined();
}
fn aliasSet(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, aliasSetBody, .{ receiver, args, roots[0] });
}
fn aliasDescriptor(s: *Scope, args: *sync.Arguments) !c.JSValue {
    const descriptor = try s.objectProto(c.pi_js_null());
    const target = try args.capture(&s.values, 0);
    const getter = try s.own(try functions.createWithArguments(s.engine, "get", 0, false,
        .{ .formal_count = 0, .callback = aliasGet }, &.{target}));
    try s.define(descriptor, "get", getter, c.JS_PROP_C_W_E);
    const setter = try s.own(try functions.createWithArguments(s.engine, "set", 1, false,
        .{ .formal_count = 1, .callback = aliasSet }, &.{target}));
    try s.define(descriptor, "set", setter, c.JS_PROP_C_W_E);
    try s.define(descriptor, "configurable", a.boolean(s, true), c.JS_PROP_C_W_E);
    try s.define(descriptor, "enumerable", a.boolean(s, false), c.JS_PROP_C_W_E);
    return dup(s, descriptor);
}
fn aliasBody(s: *Scope, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    // Original primordial callee precedes the live inspect.colors receiver,
    // alias argument and completed accessor-descriptor expression.
    const define = roots[1];
    const colors = try s.get(roots[0], "colors");
    const alias = args.get(1);
    const descriptor = try expression(s, aliasDescriptor, .{args});
    _ = try s.call(define, c.pi_js_undefined(), &.{ colors, alias, descriptor });
    return c.pi_js_undefined();
}
fn aliasCall(engine: *a.v.em.Engine, _: c.JSValue,
    args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, aliasBody, .{ args, roots });
}
fn applyAlias(s: *Scope, function: c.JSValue, target: []const u8,
    alias: []const u8) !c.JSValue
{
    _ = try s.call(function, c.pi_js_undefined(), &.{ try s.text(target), try s.text(alias) });
    return c.pi_js_undefined();
}
fn styleLiteral(s: *Scope) !c.JSValue {
    const result = try s.object();
    inline for (.{
        .{ "special", "cyan" }, .{ "number", "yellow" }, .{ "bigint", "yellow" },
        .{ "boolean", "yellow" }, .{ "undefined", "grey" }, .{ "null", "bold" },
        .{ "string", "green" }, .{ "symbol", "green" }, .{ "date", "magenta" },
        .{ "regexp", "red" }, .{ "module", "underline" },
    }) |row| try s.define(result, row[0], try s.text(row[1]), c.JS_PROP_C_W_E);
    return dup(s, result);
}
fn stylesBody(s: *Scope, assign: c.JSValue) !c.JSValue {
    const target = try s.objectProto(c.pi_js_null());
    const literal = try expression(s, styleLiteral, .{});
    return dup(s, try s.call(assign, c.pi_js_undefined(), &.{ target, literal }));
}
fn publishStyles(s: *Scope, input: Inputs) !c.JSValue {
    const styles = try expression(s, stylesBody, .{input.object_assign});
    try s.put(input.inspect, "styles", styles);
    return c.pi_js_undefined();
}
fn styleValue(s: *Scope, inspect: c.JSValue, kind: c.JSValue) !c.JSValue {
    const styles = try s.get(inspect, "styles");
    return dup(s, try s.getKey(styles, kind));
}
fn colorValue(s: *Scope, inspect: c.JSValue, style: c.JSValue) !c.JSValue {
    const colors = try s.get(inspect, "colors");
    return dup(s, try s.getKey(colors, style));
}
fn codeText(s: *Scope, color: c.JSValue, index: u32) !c.JSValue {
    const value = try s.getKey(color, c.JS_NewUint32(s.engine.context, index));
    return dup(s, try s.toString(value));
}
fn inputText(s: *Scope, input: c.JSValue) !c.JSValue {
    return dup(s, try s.toString(input));
}
fn templateBody(s: *Scope, color: c.JSValue, input: c.JSValue) !c.JSValue {
    // Each substitution completes ToString and operand retirement before the
    // next substitution. All following additions are intrinsic string +.
    var result = try a.add(s, try s.text("\x1b["), try expression(s, codeText, .{ color, @as(u32, 0) }));
    result = try a.add(s, result, try s.text("m"));
    result = try a.add(s, result, try expression(s, inputText, .{input}));
    result = try a.add(s, result, try s.text("\x1b["));
    result = try a.add(s, result, try expression(s, codeText, .{ color, @as(u32, 1) }));
    return dup(s, try a.add(s, result, try s.text("m")));
}
fn stylizeBody(s: *Scope, args: *sync.Arguments, frame: *Frame,
    inspect: c.JSValue) !c.JSValue
{
    try frame.take(.style, a.expression(s.engine, styleValue, .{ inspect, args.get(1) }));
    if (!c.JS_IsUndefined(frame.get(.style))) {
        try frame.take(.color, a.expression(s.engine, colorValue, .{ inspect, frame.get(.style) }));
        if (!c.JS_IsUndefined(frame.get(.color)))
            return a.expression(s.engine, templateBody, .{ frame.get(.color), args.get(0) });
    }
    return dup(s, args.get(0));
}
fn stylizeCall(engine: *a.v.em.Engine, _: c.JSValue,
    args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue
{
    var s = Scope.init(engine);
    const frame = args.createFrame(&s.values, Frame) catch |err|
        return s.finish(@as(anyerror!c.JSValue, err));
    // Original arguments retire at actual C terminal before these two locals.
    return s.finish(stylizeBody(&s, args, frame, roots[0]));
}
pub fn create(engine: *a.v.em.Engine, input: Inputs) !c.JSValue {
    return a.expression(engine, createBody, .{input});
}
fn createBody(s: *Scope, input: Inputs) !c.JSValue {
    const stylize = try s.own(try functions.createWithArguments(s.engine, "stylizeWithColor", 2, true,
        .{ .formal_count = 2, .callback = stylizeCall, .hooks = sync.frameHooks(Frame) },
        &.{input.inspect}));
    const define_alias = try s.own(try functions.createWithArguments(s.engine, "defineColorAlias", 2, true,
        .{ .formal_count = 2, .callback = aliasCall },
        &.{ input.inspect, input.object_define_property }));
    _ = try a.expression(s.engine, publishColors, .{input.inspect});
    inline for (.{
        .{ "gray", "grey" }, .{ "gray", "blackBright" },
        .{ "bgGray", "bgGrey" }, .{ "bgGray", "bgBlackBright" },
        .{ "dim", "faint" }, .{ "strikethrough", "crossedout" },
        .{ "strikethrough", "strikeThrough" }, .{ "strikethrough", "crossedOut" },
        .{ "hidden", "conceal" }, .{ "inverse", "swapColors" },
        .{ "inverse", "swapcolors" }, .{ "doubleunderline", "doubleUnderline" },
    }) |row| _ = try a.expression(s.engine, applyAlias, .{ define_alias, row[0], row[1] });
    _ = try a.expression(s.engine, publishStyles, .{input});
    return dup(s, stylize);
}
