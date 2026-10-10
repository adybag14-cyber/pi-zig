//! Source Spacer has an observable lines field and creates a fresh array per render.
const std = @import("std");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const v = @import("native_select_list.zig");
const Method = enum(c_int) { setLines, invalidate, render };
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Spacer: %s", @as([*:0]const u8, @errorName(err)));
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return method(engine, object, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn method(engine: *Engine, object: c.JSValue, operation: Method, args: []const c.JSValue) !c.JSValue {
    switch (operation) {
        .setLines => try v.set(engine, object, "lines", c.JS_DupValue(engine.context, v.arg(args, 0))),
        .invalidate => {},
        .render => {
            const result = try js.array(engine);
            errdefer engine.freeValue(result);
            const empty = try v.text(engine, "");
            defer engine.freeValue(empty);
            var index: f64 = 0;
            while (index < try v.numberField(engine, object, "lines")) : (index += 1) {
                if (index >= 4096) return error.NativeComponentFrameLimit;
                try js.push(engine, result, empty);
            }
            return result;
        },
    }
    return c.pi_js_undefined();
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    try js.define(engine, object, "lines", if (c.JS_IsUndefined(v.arg(args, 0))) v.numeric(engine, 1) else c.JS_DupValue(engine.context, v.arg(args, 0)));
    return object;
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const function = try engine.checked(c.pi_js_function_magic(engine.context, methodCall, name.ptr, if (std.mem.eql(u8, field.name, "invalidate")) 0 else 1, @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try js.define(engine, exports, "Spacer", try @import("native_class.zig").constructor(engine, "Spacer", 0, prototype, construct, &.{}));
}
test "Source6fb public Text Spacer preserves signed fractional values fresh render identity fields and methods" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/spacer-component-original-6fb.json");
    try js.define(engine, root, "spacerFixture", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "spacer-component-original-6fb.json")));
    const result = try engine.evalModule(
        \\import{Spacer}from'pi-tui';for(const item of spacerFixture.cases){const spacer=new Spacer(new Function('return '+item.expression)()),first=spacer.render(5),actual={lines:first,same:first===spacer.render(5)},expected={lines:item.lines,same:item.same};if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({item,actual}));}for(const item of spacerFixture.structural){const actual=new Function('Spacer',item.script)(Spacer);if(JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({item,actual}));}
    , "spacer-original.mjs");
    engine.freeValue(result);
}
