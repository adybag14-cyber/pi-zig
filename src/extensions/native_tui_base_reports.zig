//! Source TuiBase terminal response handling over ordinary query fields.
//! Bindings supply actual imported parsers and the captured module RegExp.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub const Method = enum { consumeTerminalColorResponse, terminalColorQueryResult, completeTerminalColorQuery, consumeTerminalColorSchemeReport, consumeCellSizeResponse, queryTerminalColors };
const Callback = enum(c_int) { executor, timeout };
const terminal_color_query = "\x1b]10;?\x07\x1b]11;?\x07" ++ palette_query ++ "\x1b[c";
const palette_query = blk: {
    var result: []const u8 = "";
    for (0..16) |index| result = result ++ "\x1b]4;" ++ @import("std").fmt.comptimePrint("{d}", .{index}) ++ ";?\x07";
    break :blk result;
};
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TuiBase reports: %s", @as([*:0]const u8, @errorName(err)));
}
fn callback(engine: *js.Engine, kind: Callback, values: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callbackCall, "", if (kind == .executor) 1 else 0, @intFromEnum(kind), @intCast(values.len), @constCast(values.ptr)));
}
fn callbackCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return callbackBody(engine, @enumFromInt(magic), data, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn callbackBody(engine: *js.Engine, kind: Callback, data: [*c]c.JSValue, resolve: c.JSValue) !c.JSValue {
    const screen = data[0];
    if (kind == .timeout) {
        try v.set(engine, data[1], "deliver", c.JS_DupValue(engine.context, data[3]));
        const result = try js.invoke(engine, screen, "terminalColorQueryResult", &.{data[1]});
        defer engine.freeValue(result);
        const resolved = try js.call(engine, data[2], c.pi_js_undefined(), &.{result});
        engine.freeValue(resolved);
        return c.pi_js_undefined();
    }
    const query = try js.object(engine);
    defer engine.freeValue(query);
    // Array.from fills each slot with undefined and observes the current
    // global constructor and its method, as the Source executor does.
    const array = try js.global(engine, "Array");
    defer engine.freeValue(array);
    const from = try js.get(engine, array, "from");
    defer engine.freeValue(from);
    const length = try js.object(engine);
    defer engine.freeValue(length);
    try js.define(engine, length, "length", c.JS_NewInt32(engine.context, 16));
    const undefined_mapper = try engine.checked(c.JS_NewCFunction2(engine.context, undefinedCall, "", 0, c.JS_CFUNC_generic, 0));
    defer engine.freeValue(undefined_mapper);
    try js.define(engine, query, "palette", try js.call(engine, from, array, &.{ length, undefined_mapper }));
    try js.define(engine, query, "replied", try js.builtin(engine, "Set", &.{}));
    try js.define(engine, query, "deliver", c.JS_DupValue(engine.context, resolve));
    try js.define(engine, query, "timer", c.pi_js_undefined());
    const schedule = try js.global(engine, "setTimeout");
    defer engine.freeValue(schedule);
    const continuation = try callback(engine, .timeout, &.{ screen, query, resolve, data[2] });
    defer engine.freeValue(continuation);
    try v.set(engine, query, "timer", try js.call(engine, schedule, c.pi_js_undefined(), &.{ continuation, data[1] }));
    const pending = try js.get(engine, screen, "pendingTerminalColorQueries");
    defer engine.freeValue(pending);
    try v.invokeVoid(engine, pending, "push", &.{query});
    const terminal = try js.get(engine, screen, "terminal");
    defer engine.freeValue(terminal);
    const write = try js.get(engine, terminal, "write");
    defer engine.freeValue(write);
    const sequence = try v.text(engine, terminal_color_query);
    defer engine.freeValue(sequence);
    const written = try js.call(engine, write, terminal, &.{sequence});
    engine.freeValue(written);
    return c.pi_js_undefined();
}
fn undefinedCall(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn boolean(engine: *js.Engine, value: bool) c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(value));
}
fn imported(engine: *js.Engine, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try js.get(engine, bindings, name);
    defer engine.freeValue(function);
    return js.call(engine, function, c.pi_js_undefined(), args);
}
fn equalText(engine: *js.Engine, value: c.JSValue, expected: []const u8) !bool {
    const text = try v.text(engine, expected);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
fn definedCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context.?, @intFromBool(argc > 0 and !c.JS_IsUndefined(argv[0])));
}
pub fn invoke(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .queryTerminalColors => {
            const options = v.arg(args, 0);
            const timeout = try js.get(engine, options, "timeoutMs");
            defer engine.freeValue(timeout);
            const late = try js.get(engine, options, "onLateReply");
            defer engine.freeValue(late);
            const promise = try js.global(engine, "Promise");
            defer engine.freeValue(promise);
            const executor = try callback(engine, .executor, &.{ screen, timeout, late, bindings });
            defer engine.freeValue(executor);
            var constructor_args = [_]c.JSValue{executor};
            return engine.checked(c.JS_CallConstructor(engine.context, promise, 1, &constructor_args));
        },
        .consumeTerminalColorResponse => {
            const queries = try js.get(engine, screen, "pendingTerminalColorQueries");
            defer engine.freeValue(queries);
            const query = try engine.checked(c.JS_GetPropertyUint32(engine.context, queries, 0));
            defer engine.freeValue(query);
            if (!v.truthy(engine, query)) return boolean(engine, false);
            const pattern = try js.get(engine, bindings, "deviceAttributesResponsePattern");
            defer engine.freeValue(pattern);
            const matched = try js.invoke(engine, pattern, "test", &.{v.arg(args, 0)});
            defer engine.freeValue(matched);
            if (v.truthy(engine, matched)) {
                const current_queries = try js.get(engine, screen, "pendingTerminalColorQueries");
                defer engine.freeValue(current_queries);
                try v.invokeVoid(engine, current_queries, "shift", &.{});
                try v.invokeVoid(engine, screen, "completeTerminalColorQuery", &.{query});
                return boolean(engine, true);
            }
            const response = try imported(engine, bindings, "parseOscColorResponse", &.{v.arg(args, 0)});
            defer engine.freeValue(response);
            if (!v.truthy(engine, response)) return boolean(engine, false);
            const target = try js.get(engine, response, "target");
            defer engine.freeValue(target);
            const rgb = try js.get(engine, response, "rgb");
            defer engine.freeValue(rgb);
            const string = try js.global(engine, "String");
            defer engine.freeValue(string);
            const key = try js.call(engine, string, c.pi_js_undefined(), &.{target});
            defer engine.freeValue(key);
            const deliver = try js.get(engine, query, "deliver");
            defer engine.freeValue(deliver);
            if (!v.truthy(engine, deliver)) return boolean(engine, true);
            const replied = try js.get(engine, query, "replied");
            defer engine.freeValue(replied);
            const duplicate = try js.invoke(engine, replied, "has", &.{key});
            defer engine.freeValue(duplicate);
            if (v.truthy(engine, duplicate)) return boolean(engine, true);
            const current_replied = try js.get(engine, query, "replied");
            defer engine.freeValue(current_replied);
            try v.invokeVoid(engine, current_replied, "add", &.{key});
            if (try equalText(engine, target, "foreground")) {
                try v.set(engine, query, "foreground", c.JS_DupValue(engine.context, rgb));
            } else if (try equalText(engine, target, "background")) {
                try v.set(engine, query, "background", c.JS_DupValue(engine.context, rgb));
            } else if (try v.number(engine, target) < 16) {
                const palette = try js.get(engine, query, "palette");
                defer engine.freeValue(palette);
                try js.setKey(engine, palette, target, rgb);
            }
            const final_replied = try js.get(engine, query, "replied");
            defer engine.freeValue(final_replied);
            const size = try js.get(engine, final_replied, "size");
            defer engine.freeValue(size);
            if (c.JS_IsStrictEqual(engine.context, size, c.JS_NewInt32(engine.context, 18))) try v.invokeVoid(engine, screen, "completeTerminalColorQuery", &.{query});
            return boolean(engine, true);
        },
        .terminalColorQueryResult => {
            const query = v.arg(args, 0);
            const palette = try js.get(engine, query, "palette");
            defer engine.freeValue(palette);
            const every = try js.get(engine, palette, "every");
            defer engine.freeValue(every);
            const defined = try engine.checked(c.JS_NewCFunction2(engine.context, definedCall, "", 1, c.JS_CFUNC_generic, 0));
            defer engine.freeValue(defined);
            const complete = try js.call(engine, every, palette, &.{defined});
            defer engine.freeValue(complete);
            const selected = if (v.truthy(engine, complete)) try js.get(engine, query, "palette") else c.pi_js_undefined();
            defer engine.freeValue(selected);
            const result = try js.object(engine);
            errdefer engine.freeValue(result);
            try js.define(engine, result, "foreground", try js.get(engine, query, "foreground"));
            try js.define(engine, result, "background", try js.get(engine, query, "background"));
            try js.define(engine, result, "palette", c.JS_DupValue(engine.context, selected));
            return result;
        },
        .completeTerminalColorQuery => {
            const query = v.arg(args, 0);
            const deliver = try js.get(engine, query, "deliver");
            defer engine.freeValue(deliver);
            try v.set(engine, query, "deliver", c.pi_js_undefined());
            const clear = try js.global(engine, "clearTimeout");
            defer engine.freeValue(clear);
            const timer = try js.get(engine, query, "timer");
            defer engine.freeValue(timer);
            const cleared = try js.call(engine, clear, c.pi_js_undefined(), &.{timer});
            engine.freeValue(cleared);
            if (!c.JS_IsNull(deliver) and !c.JS_IsUndefined(deliver)) {
                const result = try js.invoke(engine, screen, "terminalColorQueryResult", &.{query});
                defer engine.freeValue(result);
                const delivered = try js.call(engine, deliver, c.pi_js_undefined(), &.{result});
                engine.freeValue(delivered);
            }
            return c.pi_js_undefined();
        },
        .consumeTerminalColorSchemeReport => {
            const scheme = try imported(engine, bindings, "parseTerminalColorSchemeReport", &.{v.arg(args, 0)});
            defer engine.freeValue(scheme);
            if (!v.truthy(engine, scheme)) return boolean(engine, false);
            const listeners = try js.get(engine, screen, "terminalColorSchemeListeners");
            defer engine.freeValue(listeners);
            const symbol = try js.get(engine, bindings, "iteratorSymbol");
            defer engine.freeValue(symbol);
            var iterator = try js.Iterator.init(engine, listeners, symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |listener| {
                defer engine.freeValue(listener);
                const result = try js.call(engine, listener, c.pi_js_undefined(), &.{scheme});
                engine.freeValue(result);
            }
            return boolean(engine, true);
        },
        .consumeCellSizeResponse => {
            const pattern = try js.get(engine, bindings, "cellSizeResponsePattern");
            defer engine.freeValue(pattern);
            const match = try js.invoke(engine, v.arg(args, 0), "match", &.{pattern});
            defer engine.freeValue(match);
            if (!v.truthy(engine, match)) return boolean(engine, false);
            const parse_height = try js.global(engine, "parseInt");
            defer engine.freeValue(parse_height);
            const height_text = try engine.checked(c.JS_GetPropertyUint32(engine.context, match, 1));
            defer engine.freeValue(height_text);
            const height = try js.call(engine, parse_height, c.pi_js_undefined(), &.{ height_text, c.JS_NewInt32(engine.context, 10) });
            defer engine.freeValue(height);
            const parse_width = try js.global(engine, "parseInt");
            defer engine.freeValue(parse_width);
            const width_text = try engine.checked(c.JS_GetPropertyUint32(engine.context, match, 2));
            defer engine.freeValue(width_text);
            const width = try js.call(engine, parse_width, c.pi_js_undefined(), &.{ width_text, c.JS_NewInt32(engine.context, 10) });
            defer engine.freeValue(width);
            if (try v.number(engine, height) <= 0 or try v.number(engine, width) <= 0) return boolean(engine, true);
            const setter = try js.get(engine, bindings, "setCellDimensions");
            defer engine.freeValue(setter);
            const dimensions = try js.object(engine);
            defer engine.freeValue(dimensions);
            try js.define(engine, dimensions, "widthPx", c.JS_DupValue(engine.context, width));
            try js.define(engine, dimensions, "heightPx", c.JS_DupValue(engine.context, height));
            const set = try js.call(engine, setter, c.pi_js_undefined(), &.{dimensions});
            engine.freeValue(set);
            try v.invokeVoid(engine, screen, "invalidate", &.{});
            try v.invokeVoid(engine, screen, "requestRender", &.{});
            return boolean(engine, true);
        },
    }
}
