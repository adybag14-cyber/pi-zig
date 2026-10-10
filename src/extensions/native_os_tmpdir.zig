//! Narrow native os.tmpdir behavior for Source TUI crash-log fallback.
//! Node24.14.0 lib/os.js behavior: Copyright Joyent, Inc. and other Node
//! contributors, MIT license. The full Node license is retained in evidence.
//! This private object does not claim the complete node:os namespace.
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native temporary directory: %s", @as([*:0]const u8, @errorName(err)));
}
fn fromEnvironment(engine: *js.Engine, process: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const environment = try js.get(engine, process, "env");
    defer engine.freeValue(environment);
    return js.get(engine, environment, name);
}
fn windows(engine: *js.Engine, values: []const c.JSValue) !c.JSValue {
    const process = values[0];
    var path = try fromEnvironment(engine, process, "TEMP");
    defer engine.freeValue(path);
    if (!v.truthy(engine, path)) {
        const temporary = try fromEnvironment(engine, process, "TMP");
        engine.freeValue(path);
        path = temporary;
    }
    if (!v.truthy(engine, path)) {
        var root = try fromEnvironment(engine, process, "SystemRoot");
        defer engine.freeValue(root);
        if (!v.truthy(engine, root)) {
            const fallback = try fromEnvironment(engine, process, "windir");
            engine.freeValue(root);
            root = fallback;
        }
        const suffix = try v.text(engine, "\\temp");
        defer engine.freeValue(suffix);
        const appended = try @import("native_tui_value_arithmetic.zig").add(engine, root, suffix, values[3]);
        engine.freeValue(path);
        path = appended;
    }
    const length = try js.get(engine, path, "length");
    defer engine.freeValue(length);
    if (try v.number(engine, length) > 1) {
        const last = try js.get(engine, path, "length");
        defer engine.freeValue(last);
        const ending = try js.getKey(engine, path, v.numeric(engine, try v.number(engine, last) - 1));
        defer engine.freeValue(ending);
        const slash = try v.text(engine, "\\");
        defer engine.freeValue(slash);
        if (c.JS_IsStrictEqual(engine.context, ending, slash)) {
            const current_length = try js.get(engine, path, "length");
            defer engine.freeValue(current_length);
            const previous = try js.getKey(engine, path, v.numeric(engine, try v.number(engine, current_length) - 2));
            defer engine.freeValue(previous);
            const colon = try v.text(engine, ":");
            defer engine.freeValue(colon);
            if (!c.JS_IsStrictEqual(engine.context, previous, colon)) return js.call(engine, values[2], path, &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, -1) });
        }
    }
    return c.JS_DupValue(engine.context, path);
}
fn posix(engine: *js.Engine, values: []const c.JSValue) !c.JSValue {
    // Native process setup provides the original string environment store.
    // Retain it independently of later replacement of process.env/globalThis.
    inline for (.{ "TMPDIR", "TMP", "TEMP" }) |name| {
        const value = try js.get(engine, values[1], name);
        defer engine.freeValue(value);
        if (!v.truthy(engine, value)) continue;
        const units = try utf16.unitsAlloc(engine, value);
        defer engine.gpa.free(units);
        return utf16.string(engine, if (units.len > 1 and units[units.len - 1] == '/') units[0 .. units.len - 1] else units);
    }
    return v.text(engine, "/tmp");
}
fn body(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return if (builtin.os.tag == .windows) windows(engine, values) else posix(engine, values);
}
fn primitive(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return js.call(engine, data[0], c.pi_js_undefined(), &.{}) catch |err| fail(engine, err);
}
pub fn create(engine: *js.Engine) !c.JSValue {
    const module = engine.native_module_values.get("node:process") orelse return error.NativeProcessUnavailable;
    const process = try js.get(engine, module, "default");
    defer engine.freeValue(process);
    const environment = try js.get(engine, process, "env");
    defer engine.freeValue(environment);
    const string = try js.global(engine, "String");
    defer engine.freeValue(string);
    const prototype = try js.get(engine, string, "prototype");
    defer engine.freeValue(prototype);
    const slice = try js.get(engine, prototype, "slice");
    defer engine.freeValue(slice);
    const symbols = try js.global(engine, "Symbol");
    defer engine.freeValue(symbols);
    const symbol = try js.get(engine, symbols, "toPrimitive");
    defer engine.freeValue(symbol);
    const function = try @import("native_node_function.zig").create(engine, "tmpdir", 0, body, &.{ process, environment, slice, symbol });
    defer engine.freeValue(function);
    const atom = try js.atom(engine, symbol);
    defer c.JS_FreeAtom(engine.context, atom);
    var data = [_]c.JSValue{function};
    const convert = try engine.checked(c.JS_NewCFunctionData2(engine.context, primitive, "", 0, 0, 1, &data));
    if (c.JS_DefinePropertyValue(engine.context, function, atom, convert, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    const object = try js.object(engine);
    errdefer engine.freeValue(object);
    try js.define(engine, object, "tmpdir", c.JS_DupValue(engine.context, function));
    return object;
}
