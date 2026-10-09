//! Source ScrollView ordinary state, follow policy, layout hook and transient scrollbar timers.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const arithmetic = @import("native_tui_value_arithmetic.zig");
const Method = enum(c_int) { scrollTop, isFollowingEnd, viewportHeight, scrollbar, isScrollbarVisible, isScrollbarActive, setScrollbar, getContentWidth, markScrollbarActivity, hideTransientScrollbar, setScrollbarActive, scrollTo, scrollBy, scrollToStart, scrollToEnd, updateLayout, addChild, removeChild, clear, render, layout };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native ScrollView: %s", @as([*:0]const u8, @errorName(err)));
}
fn equalText(engine: *js.Engine, value: c.JSValue, expected: []const u8) !bool {
    const text = try v.text(engine, expected);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
fn fieldTruthy(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8) !bool {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn fieldEqual(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !bool {
    const current = try js.get(engine, object, name);
    defer engine.freeValue(current);
    return c.JS_IsStrictEqual(engine.context, current, value);
}
fn invokeVoid(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const value = try js.invoke(engine, object, name, args);
    engine.freeValue(value);
}
fn notify(engine: *js.Engine, object: c.JSValue) !void {
    const callback = try js.get(engine, object, "requestRenderCallback");
    defer engine.freeValue(callback);
    if (!c.JS_IsNull(callback) and !c.JS_IsUndefined(callback)) {
        const result = try js.call(engine, callback, object, &.{});
        engine.freeValue(result);
    }
}
fn maxScroll(engine: *js.Engine, object: c.JSValue) !f64 {
    const height = try v.numberField(engine, object, "contentHeight");
    return v.maximum(0, height - try v.numberField(engine, object, "currentViewportHeight"));
}
fn finite(engine: *js.Engine, value: c.JSValue) !bool {
    return c.JS_IsNumber(value) and std.math.isFinite(try v.number(engine, value));
}
fn follow(engine: *js.Engine, object: c.JSValue, condition: bool) !c.JSValue {
    const enabled = try js.get(engine, object, "followEnd");
    if (!v.truthy(engine, enabled)) return enabled;
    engine.freeValue(enabled);
    return c.pi_js_bool(engine.context, @intFromBool(condition));
}
fn followHeight(engine: *js.Engine, object: c.JSValue) !c.JSValue {
    const enabled = try js.get(engine, object, "followEnd");
    if (!v.truthy(engine, enabled)) return enabled;
    defer engine.freeValue(enabled);
    const content = try v.numberField(engine, object, "contentHeight");
    return c.pi_js_bool(engine.context, @intFromBool(content <= try v.numberField(engine, object, "currentViewportHeight")));
}
fn cancelHide(engine: *js.Engine, object: c.JSValue) !void {
    const function = try js.global(engine, "clearTimeout");
    defer engine.freeValue(function);
    const timer = try js.get(engine, object, "scrollbarHideTimer");
    defer engine.freeValue(timer);
    const result = try js.call(engine, function, c.pi_js_undefined(), &.{timer});
    engine.freeValue(result);
    try v.set(engine, object, "scrollbarHideTimer", c.pi_js_undefined());
}
fn hideTick(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    hideTickOperation(engine, data[0]) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn hideTickOperation(engine: *js.Engine, object: c.JSValue) !void {
    try v.set(engine, object, "scrollbarHideTimer", c.pi_js_undefined());
    try v.set(engine, object, "transientScrollbarVisible", c.pi_js_bool(engine.context, 0));
    try notify(engine, object);
}
fn suffix(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const space = v.text(engine, " ") catch |err| return fail(engine, err);
    defer engine.freeValue(space);
    return v.concat(engine, &.{ if (argc > 0) argv[0] else c.pi_js_undefined(), space }) catch |err| fail(engine, err);
}
fn style(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const before = v.text(engine, if (magic == 0) "\x1b[90m" else "\x1b[37m") catch |err| return fail(engine, err);
    defer engine.freeValue(before);
    const after = v.text(engine, "\x1b[39m") catch |err| return fail(engine, err);
    defer engine.freeValue(after);
    return v.concat(engine, &.{ before, if (argc > 0) argv[0] else c.pi_js_undefined(), after }) catch |err| fail(engine, err);
}
fn throwError(engine: *js.Engine, message: []const u8) anyerror {
    const text = try v.text(engine, message);
    defer engine.freeValue(text);
    const exception = try js.builtin(engine, "Error", &.{text});
    _ = engine.checked(c.JS_Throw(engine.context, exception)) catch |err| return err;
    unreachable;
}
fn operation(engine: *js.Engine, object: c.JSValue, method: Method, args: []const c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    switch (method) {
        .scrollTop => return js.get(engine, object, "currentScrollTop"),
        .isFollowingEnd => return js.get(engine, object, "followingEnd"),
        .viewportHeight => return js.get(engine, object, "currentViewportHeight"),
        .scrollbar => return js.get(engine, object, "currentScrollbar"),
        .isScrollbarActive => return js.get(engine, object, "scrollbarActive"),
        .isScrollbarVisible => {
            const mode = try js.get(engine, object, "scrollbar");
            defer engine.freeValue(mode);
            if (try equalText(engine, mode, "always")) return c.pi_js_bool(engine.context, @intFromBool(try v.numberField(engine, object, "currentViewportHeight") > 0));
            const current = try js.get(engine, object, "scrollbar");
            defer engine.freeValue(current);
            if (!try equalText(engine, current, "auto")) return c.pi_js_bool(engine.context, 0);
            const height = try v.numberField(engine, object, "contentHeight");
            if (!(height > try v.numberField(engine, object, "currentViewportHeight"))) return c.pi_js_bool(engine.context, 0);
            return js.get(engine, object, "transientScrollbarVisible");
        },
        .setScrollbar => {
            if (try fieldEqual(engine, object, "currentScrollbar", first)) return c.pi_js_undefined();
            try v.set(engine, object, "currentScrollbar", c.JS_DupValue(engine.context, first));
            if (!try equalText(engine, first, "auto")) try invokeVoid(engine, object, "hideTransientScrollbar", &.{}) else if (try fieldTruthy(engine, object, "scrollbarActive")) try invokeVoid(engine, object, "markScrollbarActivity", &.{});
            try notify(engine, object);
        },
        .getContentWidth => {
            const mode = try js.get(engine, object, "scrollbar");
            defer engine.freeValue(mode);
            if (try equalText(engine, mode, "always") and try v.number(engine, first) > 1) return v.numeric(engine, try v.number(engine, first) - 1);
            return c.JS_DupValue(engine.context, first);
        },
        .markScrollbarActivity => {
            const mode = try js.get(engine, object, "scrollbar");
            defer engine.freeValue(mode);
            if (!try equalText(engine, mode, "auto")) return c.pi_js_undefined();
            const height = try v.numberField(engine, object, "contentHeight");
            if (height <= try v.numberField(engine, object, "currentViewportHeight")) return c.pi_js_undefined();
            try v.set(engine, object, "transientScrollbarVisible", c.pi_js_bool(engine.context, 1));
            if (try fieldTruthy(engine, object, "scrollbarHideTimer")) try cancelHide(engine, object);
            if (try fieldTruthy(engine, object, "scrollbarActive")) return c.pi_js_undefined();
            const set_timeout = try js.global(engine, "setTimeout");
            defer engine.freeValue(set_timeout);
            var captured = [_]c.JSValue{object};
            const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, hideTick, "", 0, 0, captured.len, &captured));
            defer engine.freeValue(function);
            const delay = try js.get(engine, object, "scrollbarHideDelayMs");
            defer engine.freeValue(delay);
            try v.set(engine, object, "scrollbarHideTimer", try js.call(engine, set_timeout, c.pi_js_undefined(), &.{ function, delay }));
            const timer = try js.get(engine, object, "scrollbarHideTimer");
            defer engine.freeValue(timer);
            try invokeVoid(engine, timer, "unref", &.{});
        },
        .hideTransientScrollbar => {
            try v.set(engine, object, "transientScrollbarVisible", c.pi_js_bool(engine.context, 0));
            if (!try fieldTruthy(engine, object, "scrollbarHideTimer")) return c.pi_js_undefined();
            try cancelHide(engine, object);
        },
        .setScrollbarActive => {
            if (try fieldEqual(engine, object, "scrollbarActive", first)) return c.pi_js_undefined();
            try v.set(engine, object, "scrollbarActive", c.JS_DupValue(engine.context, first));
            try invokeVoid(engine, object, "markScrollbarActivity", &.{});
            try notify(engine, object);
        },
        .scrollTo => {
            const supplied = v.arg(args, 1);
            const options = if (c.JS_IsUndefined(supplied)) try js.object(engine) else c.JS_DupValue(engine.context, supplied);
            defer engine.freeValue(options);
            const requested = if (try finite(engine, first)) v.numeric(engine, @trunc(try v.number(engine, first))) else try js.get(engine, object, "currentScrollTop");
            defer engine.freeValue(requested);
            const maximum = try maxScroll(engine, object);
            const next = v.maximum(0, v.minimum(maximum, try v.number(engine, requested)));
            const disable = try js.get(engine, options, "disableFollow");
            defer engine.freeValue(disable);
            const suppressed = c.JS_IsStrictEqual(engine.context, disable, c.pi_js_bool(engine.context, 1)) and next == maximum;
            const next_follow = if (suppressed) c.pi_js_bool(engine.context, 0) else try follow(engine, object, next == maximum);
            defer engine.freeValue(next_follow);
            if (try fieldEqual(engine, object, "currentScrollTop", v.numeric(engine, next)) and try fieldEqual(engine, object, "followingEnd", next_follow) and try fieldEqual(engine, object, "followSuppressedAtEnd", c.pi_js_bool(engine.context, @intFromBool(suppressed)))) return c.pi_js_undefined();
            const moved = !(try fieldEqual(engine, object, "currentScrollTop", v.numeric(engine, next)));
            try v.set(engine, object, "currentScrollTop", v.numeric(engine, next));
            try v.set(engine, object, "followingEnd", c.JS_DupValue(engine.context, next_follow));
            try v.set(engine, object, "followSuppressedAtEnd", c.pi_js_bool(engine.context, @intFromBool(suppressed)));
            if (moved) try invokeVoid(engine, object, "markScrollbarActivity", &.{});
            try notify(engine, object);
        },
        .scrollBy => {
            const requested = if (try finite(engine, first)) @trunc(try v.number(engine, first)) else 0;
            if (requested == 0) return c.JS_NewInt32(engine.context, 0);
            const maximum = try maxScroll(engine, object);
            const start = if (try fieldTruthy(engine, object, "followingEnd")) v.numeric(engine, maximum) else try js.get(engine, object, "currentScrollTop");
            defer engine.freeValue(start);
            const sum = try arithmetic.add(engine, start, v.numeric(engine, requested), data[2]);
            defer engine.freeValue(sum);
            const next = v.maximum(0, v.minimum(maximum, try v.number(engine, sum)));
            const moved = next - try v.number(engine, start);
            const previous = try js.get(engine, object, "followingEnd");
            defer engine.freeValue(previous);
            try v.set(engine, object, "currentScrollTop", v.numeric(engine, next));
            try v.set(engine, object, "followingEnd", try follow(engine, object, next == maximum));
            try v.set(engine, object, "followSuppressedAtEnd", c.pi_js_bool(engine.context, 0));
            if (moved != 0) try invokeVoid(engine, object, "markScrollbarActivity", &.{});
            if (moved != 0 or !(try fieldEqual(engine, object, "followingEnd", previous))) try notify(engine, object);
            return v.numeric(engine, requested - moved);
        },
        .scrollToStart => {
            var changed = !(try fieldEqual(engine, object, "currentScrollTop", c.JS_NewInt32(engine.context, 0)));
            if (!changed) {
                const current = try js.get(engine, object, "followingEnd");
                defer engine.freeValue(current);
                const comparison = try followHeight(engine, object);
                defer engine.freeValue(comparison);
                changed = !c.JS_IsStrictEqual(engine.context, current, comparison);
            }
            try v.set(engine, object, "currentScrollTop", c.JS_NewInt32(engine.context, 0));
            try v.set(engine, object, "followingEnd", try followHeight(engine, object));
            try v.set(engine, object, "followSuppressedAtEnd", c.pi_js_bool(engine.context, 0));
            if (changed) {
                try invokeVoid(engine, object, "markScrollbarActivity", &.{});
                try notify(engine, object);
            }
        },
        .scrollToEnd => {
            const next = try maxScroll(engine, object);
            var changed = !(try fieldEqual(engine, object, "currentScrollTop", v.numeric(engine, next)));
            if (!changed) {
                const current = try js.get(engine, object, "followingEnd");
                defer engine.freeValue(current);
                const enabled = try js.get(engine, object, "followEnd");
                defer engine.freeValue(enabled);
                changed = !c.JS_IsStrictEqual(engine.context, current, enabled);
            }
            try v.set(engine, object, "currentScrollTop", v.numeric(engine, next));
            try v.set(engine, object, "followingEnd", try js.get(engine, object, "followEnd"));
            try v.set(engine, object, "followSuppressedAtEnd", c.pi_js_bool(engine.context, 0));
            if (changed) {
                try invokeVoid(engine, object, "markScrollbarActivity", &.{});
                try notify(engine, object);
            }
        },
        .updateLayout => {
            try v.set(engine, object, "contentHeight", v.numeric(engine, v.maximum(0, @floor(try v.number(engine, first)))));
            try v.set(engine, object, "currentViewportHeight", v.numeric(engine, v.maximum(0, @floor(try v.number(engine, v.arg(args, 1))))));
            try v.set(engine, object, "requestRenderCallback", c.JS_DupValue(engine.context, v.arg(args, 2)));
            const maximum = try maxScroll(engine, object);
            if (try fieldTruthy(engine, object, "followingEnd")) try v.set(engine, object, "currentScrollTop", v.numeric(engine, maximum)) else try v.set(engine, object, "currentScrollTop", v.numeric(engine, v.maximum(0, v.minimum(try v.numberField(engine, object, "currentScrollTop"), maximum))));
            if (try v.numberField(engine, object, "currentScrollTop") < maximum) try v.set(engine, object, "followSuppressedAtEnd", c.pi_js_bool(engine.context, 0));
            if (try fieldTruthy(engine, object, "followEnd") and try fieldEqual(engine, object, "currentScrollTop", v.numeric(engine, maximum)) and !try fieldTruthy(engine, object, "followSuppressedAtEnd")) try v.set(engine, object, "followingEnd", c.pi_js_bool(engine.context, 1));
            const content = try v.numberField(engine, object, "contentHeight");
            if (content <= try v.numberField(engine, object, "currentViewportHeight")) try invokeVoid(engine, object, "hideTransientScrollbar", &.{});
        },
        .addChild => return throwError(engine, "ScrollView has exactly one child"),
        .removeChild => return throwError(engine, "ScrollView child cannot be removed"),
        .clear => return throwError(engine, "ScrollView child cannot be cleared"),
        .render => {
            const width = try js.invoke(engine, object, "getContentWidth", &.{first});
            defer engine.freeValue(width);
            const child = try js.get(engine, object, "child");
            defer engine.freeValue(child);
            const lines = try js.invoke(engine, child, "render", &.{width});
            if (c.JS_IsStrictEqual(engine.context, width, first)) return lines;
            defer engine.freeValue(lines);
            const function = try engine.checked(c.JS_NewCFunction(engine.context, suffix, "", 1));
            defer engine.freeValue(function);
            return js.invoke(engine, lines, "map", &.{function});
        },
        .layout => {
            const result = try js.object(engine);
            errdefer engine.freeValue(result);
            try js.define(engine, result, "type", try v.text(engine, "scroll"));
            try js.define(engine, result, "component", try js.get(engine, object, "child"));
            try js.define(engine, result, "state", c.JS_DupValue(engine.context, object));
            return result;
        },
    }
    return c.pi_js_undefined();
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return operation(engine, object, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, data) catch |err| fail(engine, err);
}
fn option(engine: *js.Engine, options: c.JSValue, name: [*:0]const u8, fallback: c.JSValue) !c.JSValue {
    defer engine.freeValue(fallback);
    const value = try js.get(engine, options, name);
    if (!c.JS_IsNull(value) and !c.JS_IsUndefined(value)) return value;
    engine.freeValue(value);
    return c.JS_DupValue(engine.context, fallback);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const self = try js.get(engine, data[0], "ScrollView");
    defer engine.freeValue(self);
    const base = try engine.checked(c.JS_GetPrototype(engine.context, self));
    defer engine.freeValue(base);
    const object = try engine.checked(c.JS_CallConstructor2(engine.context, base, target, 0, null));
    errdefer engine.freeValue(object);
    inline for (.{ "child", "followEnd", "primary", "overscroll", "scrollbarTrackStyle", "scrollbarThumbStyle", "currentScrollbar", "scrollbarHideDelayMs" }) |name| try js.define(engine, object, name, c.pi_js_undefined());
    inline for (.{ "currentScrollTop", "contentHeight", "currentViewportHeight" }) |name| try js.define(engine, object, name, c.JS_NewInt32(engine.context, 0));
    try js.define(engine, object, "followingEnd", c.pi_js_undefined());
    try js.define(engine, object, "followSuppressedAtEnd", c.pi_js_bool(engine.context, 0));
    try js.define(engine, object, "requestRenderCallback", c.pi_js_undefined());
    try js.define(engine, object, "transientScrollbarVisible", c.pi_js_bool(engine.context, 0));
    try js.define(engine, object, "scrollbarActive", c.pi_js_bool(engine.context, 0));
    try js.define(engine, object, "scrollbarHideTimer", c.pi_js_undefined());
    const supplied = v.arg(args, 1);
    const options = if (c.JS_IsUndefined(supplied)) try js.object(engine) else c.JS_DupValue(engine.context, supplied);
    defer engine.freeValue(options);
    const axis = try js.get(engine, options, "axis");
    defer engine.freeValue(axis);
    if (!c.JS_IsUndefined(axis)) {
        const current_axis = try js.get(engine, options, "axis");
        defer engine.freeValue(current_axis);
        if (!try equalText(engine, current_axis, "vertical")) {
            const current = try js.get(engine, options, "axis");
            defer engine.freeValue(current);
            const prefix = try v.text(engine, "Unsupported ScrollView axis: ");
            defer engine.freeValue(prefix);
            const message = try v.concat(engine, &.{ prefix, current });
            defer engine.freeValue(message);
            const exception = try js.builtin(engine, "Error", &.{message});
            _ = try engine.checked(c.JS_Throw(engine.context, exception));
            unreachable;
        }
    }
    try v.set(engine, object, "child", c.JS_DupValue(engine.context, v.arg(args, 0)));
    const children = try js.get(engine, object, "children");
    defer engine.freeValue(children);
    try js.push(engine, children, v.arg(args, 0));
    const follow_mode = try option(engine, options, "follow", try v.text(engine, "none"));
    defer engine.freeValue(follow_mode);
    try v.set(engine, object, "followEnd", c.pi_js_bool(engine.context, @intFromBool(try equalText(engine, follow_mode, "end"))));
    try v.set(engine, object, "followingEnd", try js.get(engine, object, "followEnd"));
    try v.set(engine, object, "primary", try option(engine, options, "primary", c.pi_js_bool(engine.context, 0)));
    try v.set(engine, object, "overscroll", try option(engine, options, "overscroll", try v.text(engine, "chain")));
    try v.set(engine, object, "currentScrollbar", try option(engine, options, "scrollbar", try v.text(engine, "hidden")));
    inline for (.{ .{ "scrollbarTrackStyle", 0 }, .{ "scrollbarThumbStyle", 1 } }) |field| {
        const provided = try js.get(engine, options, field[0]);
        defer engine.freeValue(provided);
        try v.set(engine, object, field[0], if (c.JS_IsNull(provided) or c.JS_IsUndefined(provided)) try engine.checked(c.pi_js_function_magic(engine.context, style, "", 1, field[1])) else c.JS_DupValue(engine.context, provided));
    }
    const delay = try option(engine, options, "scrollbarHideDelayMs", c.JS_NewInt32(engine.context, 1000));
    defer engine.freeValue(delay);
    try v.set(engine, object, "scrollbarHideDelayMs", v.numeric(engine, v.maximum(0, @floor(try v.number(engine, delay)))));
    return object;
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    const container = try js.get(engine, exports, "Container");
    defer engine.freeValue(container);
    const container_prototype = try js.get(engine, container, "prototype");
    defer engine.freeValue(container_prototype);
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const key = try v.text(engine, "@earendil-works/pi-tui/layout-node");
    defer engine.freeValue(key);
    const layout_symbol = try js.invoke(engine, symbol, "for", &.{key});
    defer engine.freeValue(layout_symbol);
    const primitive_symbol = try js.get(engine, symbol, "toPrimitive");
    defer engine.freeValue(primitive_symbol);
    const record = try js.object(engine);
    defer engine.freeValue(record);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, container_prototype));
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    var data = [_]c.JSValue{ record, layout_symbol, primitive_symbol };
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const getter = field.value <= @intFromEnum(Method.isScrollbarActive);
        const name: [:0]const u8 = field.name;
        const function_name: [:0]const u8 = if (getter) "get " ++ field.name else if (method == .layout) "[@earendil-works/pi-tui/layout-node]" else field.name;
        const length: c_int = switch (method) {
            .setScrollbar, .getContentWidth, .setScrollbarActive, .scrollTo, .scrollBy, .addChild, .removeChild, .render => 1,
            .updateLayout => 3,
            else => 0,
        };
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, function_name.ptr, length, @intCast(field.value), data.len, &data));
        if (method == .layout) {
            const atom = try js.atom(engine, layout_symbol);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyValue(engine.context, prototype, atom, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
        } else if (getter) {
            defer engine.freeValue(function);
            const atom = c.JS_NewAtom(engine.context, name.ptr);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        } else if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const constructor = try @import("native_class.zig").constructor(engine, "ScrollView", 1, prototype, construct, &.{record});
    defer engine.freeValue(constructor);
    if (c.JS_SetPrototype(engine.context, constructor, container) < 0) return js.capture(engine);
    try js.define(engine, record, "ScrollView", c.JS_DupValue(engine.context, constructor));
    try js.define(engine, exports, "ScrollView", c.JS_DupValue(engine.context, constructor));
}
