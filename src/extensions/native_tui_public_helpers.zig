//! Public Source TUI guards, status reports, color-scheme reports and LaTeX entry point.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const Method = enum(c_int) { isFocusable, isViewportTUI, isAppleTerminalSession, parseTerminalColorSchemeReport, formatProgramStatus, renderLatex };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TUI helper: %s", @as([*:0]const u8, @errorName(err)));
}
fn equalText(engine: *js.Engine, value: c.JSValue, expected: []const u8) !bool {
    const text = try v.text(engine, expected);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
fn pair(engine: *js.Engine, pairs: c.JSValue, prefix: []const u8, value: c.JSValue) !void {
    const key = try v.text(engine, prefix);
    defer engine.freeValue(key);
    const combined = try v.concat(engine, &.{ key, value });
    defer engine.freeValue(combined);
    try js.push(engine, pairs, combined);
}
fn utf8Length(engine: *js.Engine, text: c.JSValue, encoding: c.JSValue) !f64 {
    const buffer = try js.global(engine, "Buffer");
    defer engine.freeValue(buffer);
    const length = try js.invoke(engine, buffer, "byteLength", &.{ text, encoding });
    defer engine.freeValue(length);
    return v.number(engine, length);
}
fn truncateUtf8(engine: *js.Engine, text: c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    const encoding = try v.text(engine, "utf8");
    defer engine.freeValue(encoding);
    if (try utf8Length(engine, text, encoding) <= 2048) return c.JS_DupValue(engine.context, text);
    var bytes: f64 = 0;
    var end: f64 = 0;
    var iterator = try js.Iterator.init(engine, text, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |character| {
        defer engine.freeValue(character);
        const size = try utf8Length(engine, character, encoding);
        if (bytes + size > 2048) {
            try iterator.close();
            break;
        }
        bytes += size;
        end += try v.numberField(engine, character, "length");
    }
    return js.invoke(engine, text, "slice", &.{ c.JS_NewInt32(engine.context, 0), v.numeric(engine, end) });
}
fn formatStatus(engine: *js.Engine, status: c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const pairs = try js.array(engine);
    defer engine.freeValue(pairs);
    const state = try js.get(engine, status, "state");
    defer engine.freeValue(state);
    const state_prefix = try v.text(engine, "state=");
    defer engine.freeValue(state_prefix);
    const state_pair = try v.concat(engine, &.{ state_prefix, state });
    if (c.JS_DefinePropertyValueUint32(engine.context, pairs, 0, state_pair, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    const app = try js.get(engine, status, "app");
    defer engine.freeValue(app);
    if (!c.JS_IsUndefined(app)) {
        const current = try js.get(engine, status, "app");
        defer engine.freeValue(current);
        const matched = try js.invoke(engine, data[2], "test", &.{current});
        defer engine.freeValue(matched);
        if (v.truthy(engine, matched)) {
            const value = try js.get(engine, status, "app");
            defer engine.freeValue(value);
            try pair(engine, pairs, "app=", value);
        }
    }
    const current_state = try js.get(engine, status, "state");
    defer engine.freeValue(current_state);
    if (try equalText(engine, current_state, "blocked")) {
        const kind = try js.get(engine, status, "kind");
        defer engine.freeValue(kind);
        if (v.truthy(engine, kind)) {
            const current = try js.get(engine, status, "kind");
            defer engine.freeValue(current);
            try pair(engine, pairs, "kind=", current);
        }
    }
    const raw_message = try js.get(engine, status, "message");
    defer engine.freeValue(raw_message);
    const message = if (c.JS_IsNull(raw_message) or c.JS_IsUndefined(raw_message)) try v.text(engine, "") else c.JS_DupValue(engine.context, raw_message);
    defer engine.freeValue(message);
    const space = try v.text(engine, " ");
    defer engine.freeValue(space);
    const replaced = try js.invoke(engine, message, "replace", &.{ data[3], space });
    defer engine.freeValue(replaced);
    const trimmed = try js.invoke(engine, replaced, "trim", &.{});
    defer engine.freeValue(trimmed);
    const truncated = try truncateUtf8(engine, trimmed, data[4]);
    defer engine.freeValue(truncated);
    if (v.truthy(engine, truncated)) {
        const buffer = try js.global(engine, "Buffer");
        defer engine.freeValue(buffer);
        const encoding = try v.text(engine, "utf8");
        defer engine.freeValue(encoding);
        const raw = try js.invoke(engine, buffer, "from", &.{ truncated, encoding });
        defer engine.freeValue(raw);
        const base64 = try v.text(engine, "base64");
        defer engine.freeValue(base64);
        const encoded = try js.invoke(engine, raw, "toString", &.{base64});
        defer engine.freeValue(encoded);
        try pair(engine, pairs, "msg=", encoded);
    }
    const separator = try v.text(engine, ":");
    defer engine.freeValue(separator);
    const body = try js.invoke(engine, pairs, "join", &.{separator});
    defer engine.freeValue(body);
    const prefix = try v.text(engine, "\x1b]7501;");
    defer engine.freeValue(prefix);
    const suffix = try v.text(engine, "\x1b\\");
    defer engine.freeValue(suffix);
    return v.concat(engine, &.{ prefix, body, suffix });
}
fn operation(engine: *js.Engine, method: Method, args: []const c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    switch (method) {
        .isFocusable => {
            if (c.JS_IsNull(first)) return c.pi_js_bool(engine.context, 0);
            const name = try v.text(engine, "focused");
            defer engine.freeValue(name);
            return c.pi_js_bool(engine.context, @intFromBool(try js.hasKey(engine, first, name)));
        },
        .isViewportTUI => {
            const value = try js.getKey(engine, first, data[0]);
            defer engine.freeValue(value);
            return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, value, c.pi_js_bool(engine.context, 1))));
        },
        .isAppleTerminalSession => {
            const process = try js.global(engine, "process");
            defer engine.freeValue(process);
            const platform = try js.get(engine, process, "platform");
            defer engine.freeValue(platform);
            if (!try equalText(engine, platform, "darwin")) return c.pi_js_bool(engine.context, 0);
            const environment = try js.get(engine, process, "env");
            defer engine.freeValue(environment);
            const program = try js.get(engine, environment, "TERM_PROGRAM");
            defer engine.freeValue(program);
            return c.pi_js_bool(engine.context, @intFromBool(try equalText(engine, program, "Apple_Terminal")));
        },
        .parseTerminalColorSchemeReport => {
            const match = try js.invoke(engine, first, "match", &.{data[1]});
            defer engine.freeValue(match);
            if (!v.truthy(engine, match)) return c.pi_js_undefined();
            const scheme = try engine.checked(c.JS_GetPropertyUint32(engine.context, match, 1));
            defer engine.freeValue(scheme);
            return v.text(engine, if (try equalText(engine, scheme, "2")) "light" else "dark");
        },
        .formatProgramStatus => return formatStatus(engine, first, data),
        .renderLatex => {
            const provided = v.arg(args, 1);
            const options = if (c.JS_IsUndefined(provided)) try js.object(engine) else c.JS_DupValue(engine.context, provided);
            defer engine.freeValue(options);
            const display = try js.get(engine, options, "display");
            defer engine.freeValue(display);
            const length = try js.get(engine, first, "length");
            defer engine.freeValue(length);
            if (c.JS_IsUndefined(length)) return c.pi_js_undefined();
            const source = try engine.toString(first);
            defer engine.gpa.free(source);
            if (try @import("../tui/latex.zig").renderLatex(engine.gpa, source, .{ .display = c.JS_IsStrictEqual(engine.context, display, c.pi_js_bool(engine.context, 1)) })) |text| {
                defer engine.gpa.free(text);
                return v.text(engine, text);
            }
            return c.pi_js_undefined();
        },
    }
}
fn methodCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return operation(engine, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, data) catch |err| fail(engine, err);
}
fn regex(engine: *js.Engine, pattern: []const u8, flags: []const u8) !c.JSValue {
    const text = try v.text(engine, pattern);
    defer engine.freeValue(text);
    const flag_text = try v.text(engine, flags);
    defer engine.freeValue(flag_text);
    var arguments = [_]c.JSValue{ text, flag_text };
    return engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, arguments.len, &arguments));
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const key = try v.text(engine, "@earendil-works/pi-tui/viewport");
    defer engine.freeValue(key);
    const viewport = try js.invoke(engine, symbol, "for", &.{key});
    defer engine.freeValue(viewport);
    const scheme = try regex(engine, "^(?:\\x1b\\[\\?997;(1|2)n)+$", "");
    defer engine.freeValue(scheme);
    const app = try regex(engine, "^[A-Za-z0-9_.+-]{1,32}$", "");
    defer engine.freeValue(app);
    const controls = try regex(engine, "[\\u0000-\\u001f\\u007f-\\u009f]+", "g");
    defer engine.freeValue(controls);
    const iterator = try js.get(engine, symbol, "iterator");
    defer engine.freeValue(iterator);
    var data = [_]c.JSValue{ viewport, scheme, app, controls, iterator };
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        try js.define(engine, exports, name.ptr, try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, if (field.value == @intFromEnum(Method.isAppleTerminalSession)) 0 else 1, @intCast(field.value), data.len, &data)));
    }
}
