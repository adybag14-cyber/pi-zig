//! Source public Image component with observable fields and shared bounded PNG conversion cache.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const Method = enum(c_int) { getImageId, invalidate, render, setImageTranscoder };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Image: %s", @as([*:0]const u8, @errorName(err)));
}
fn invokeVoid(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const result = try js.invoke(engine, object, name, args);
    engine.freeValue(result);
}
fn equalText(engine: *js.Engine, value: c.JSValue, expected: []const u8) !bool {
    const text = try v.text(engine, expected);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
fn kitty(engine: *js.Engine, capabilities: c.JSValue) !bool {
    const protocol = try js.get(engine, capabilities, "images");
    defer engine.freeValue(protocol);
    return equalText(engine, protocol, "kitty");
}
fn toPng(engine: *js.Engine, state: c.JSValue, source: c.JSValue, mime: c.JSValue) !c.JSValue {
    const transcoder = try js.get(engine, state, "transcoder");
    defer engine.freeValue(transcoder);
    if (!v.truthy(engine, transcoder)) return c.pi_js_null();
    const cache = try js.get(engine, state, "cache");
    defer engine.freeValue(cache);
    const cached = try js.invoke(engine, cache, "get", &.{source});
    defer engine.freeValue(cached);
    const png = if (c.JS_IsUndefined(cached)) try js.call(engine, transcoder, c.pi_js_undefined(), &.{ source, mime }) else c.JS_DupValue(engine.context, cached);
    errdefer engine.freeValue(png);
    try invokeVoid(engine, cache, "delete", &.{source});
    try invokeVoid(engine, cache, "set", &.{ source, png });
    if (try v.numberField(engine, cache, "size") > 32) {
        const keys = try js.invoke(engine, cache, "keys", &.{});
        defer engine.freeValue(keys);
        const step = try js.invoke(engine, keys, "next", &.{});
        defer engine.freeValue(step);
        const oldest = try js.get(engine, step, "value");
        defer engine.freeValue(oldest);
        try invokeVoid(engine, cache, "delete", &.{oldest});
    }
    return png;
}
fn fallback(engine: *js.Engine, exports: c.JSValue, object: c.JSValue, width: c.JSValue) !c.JSValue {
    const function = try js.get(engine, exports, "imageFallback");
    defer engine.freeValue(function);
    const mime = try js.get(engine, object, "mimeType");
    defer engine.freeValue(mime);
    const dimensions = try js.get(engine, object, "dimensions");
    defer engine.freeValue(dimensions);
    const options = try js.get(engine, object, "options");
    defer engine.freeValue(options);
    const filename = try js.get(engine, options, "filename");
    defer engine.freeValue(filename);
    const text = try js.call(engine, function, c.pi_js_undefined(), &.{ mime, dimensions, filename });
    defer engine.freeValue(text);
    const truncate = try js.get(engine, exports, "truncateToWidth");
    defer engine.freeValue(truncate);
    const theme = try js.get(engine, object, "theme");
    defer engine.freeValue(theme);
    const colored = try js.invoke(engine, theme, "fallbackColor", &.{text});
    defer engine.freeValue(colored);
    const line = try js.call(engine, truncate, c.pi_js_undefined(), &.{ colored, width });
    defer engine.freeValue(line);
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    if (c.JS_DefinePropertyValueUint32(engine.context, result, 0, c.JS_DupValue(engine.context, line), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    return result;
}
fn render(engine: *js.Engine, object: c.JSValue, width: c.JSValue, exports: c.JSValue, state: c.JSValue) !c.JSValue {
    const cached = try js.get(engine, object, "cachedLines");
    defer engine.freeValue(cached);
    if (v.truthy(engine, cached)) {
        const cached_width = try js.get(engine, object, "cachedWidth");
        defer engine.freeValue(cached_width);
        if (c.JS_IsStrictEqual(engine.context, cached_width, width)) return js.get(engine, object, "cachedLines");
    }
    const base_width = try v.number(engine, width) - 2;
    const options = try js.get(engine, object, "options");
    defer engine.freeValue(options);
    const configured_width = try js.get(engine, options, "maxWidthCells");
    defer engine.freeValue(configured_width);
    const max_width = v.maximum(1, v.minimum(base_width, if (c.JS_IsNull(configured_width) or c.JS_IsUndefined(configured_width)) 60 else try v.number(engine, configured_width)));
    const cells = try js.invoke(engine, exports, "getCellDimensions", &.{});
    defer engine.freeValue(cells);
    const cell_width = try v.numberField(engine, cells, "widthPx");
    const cell_height = try v.numberField(engine, cells, "heightPx");
    const default_height = v.maximum(1, @ceil(max_width * cell_width / cell_height));
    const current_options = try js.get(engine, object, "options");
    defer engine.freeValue(current_options);
    const configured_height = try js.get(engine, current_options, "maxHeightCells");
    defer engine.freeValue(configured_height);
    const max_height = if (c.JS_IsNull(configured_height) or c.JS_IsUndefined(configured_height)) v.numeric(engine, default_height) else c.JS_DupValue(engine.context, configured_height);
    defer engine.freeValue(max_height);
    const capabilities = try js.invoke(engine, exports, "getCapabilities", &.{});
    defer engine.freeValue(capabilities);
    var data = try js.get(engine, object, "base64Data");
    defer engine.freeValue(data);
    var dimensions = try js.get(engine, object, "dimensions");
    defer engine.freeValue(dimensions);
    if (try kitty(engine, capabilities)) {
        const mime = try js.get(engine, object, "mimeType");
        defer engine.freeValue(mime);
        if (!try equalText(engine, mime, "image/png")) {
            const existing = try js.get(engine, object, "pngData");
            defer engine.freeValue(existing);
            if (c.JS_IsNull(existing) or c.JS_IsUndefined(existing)) {
                const source = try js.get(engine, object, "base64Data");
                defer engine.freeValue(source);
                const current_mime = try js.get(engine, object, "mimeType");
                defer engine.freeValue(current_mime);
                const converted = try toPng(engine, state, source, current_mime);
                defer engine.freeValue(converted);
                try v.set(engine, object, "pngData", if (c.JS_IsNull(converted) or c.JS_IsUndefined(converted)) c.pi_js_undefined() else c.JS_DupValue(engine.context, converted));
            }
            const png = try js.get(engine, object, "pngData");
            engine.freeValue(data);
            data = if (c.JS_IsNull(png) or c.JS_IsUndefined(png)) c.pi_js_null() else c.JS_DupValue(engine.context, png);
            engine.freeValue(png);
            if (v.truthy(engine, data)) {
                const detected = try js.invoke(engine, exports, "getPngDimensions", &.{data});
                defer engine.freeValue(detected);
                if (!c.JS_IsNull(detected) and !c.JS_IsUndefined(detected)) {
                    engine.freeValue(dimensions);
                    dimensions = c.JS_DupValue(engine.context, detected);
                }
            }
        }
    }
    const protocol = try js.get(engine, capabilities, "images");
    defer engine.freeValue(protocol);
    var lines: ?c.JSValue = null;
    errdefer if (lines) |value| engine.freeValue(value);
    if (v.truthy(engine, protocol) and v.truthy(engine, data)) {
        if (try kitty(engine, capabilities)) {
            const image_id = try js.get(engine, object, "imageId");
            defer engine.freeValue(image_id);
            if (c.JS_IsUndefined(image_id)) try v.set(engine, object, "imageId", try js.invoke(engine, exports, "allocateImageId", &.{}));
        }
        const function = try js.get(engine, exports, "renderImage");
        defer engine.freeValue(function);
        const render_options = try js.object(engine);
        defer engine.freeValue(render_options);
        try js.define(engine, render_options, "maxWidthCells", v.numeric(engine, max_width));
        try js.define(engine, render_options, "maxHeightCells", c.JS_DupValue(engine.context, max_height));
        try js.define(engine, render_options, "imageId", try js.get(engine, object, "imageId"));
        try js.define(engine, render_options, "moveCursor", c.pi_js_bool(engine.context, 0));
        const result = try js.call(engine, function, c.pi_js_undefined(), &.{ data, dimensions, render_options });
        defer engine.freeValue(result);
        if (v.truthy(engine, result)) {
            const image_id = try js.get(engine, result, "imageId");
            defer engine.freeValue(image_id);
            if (v.truthy(engine, image_id)) try v.set(engine, object, "imageId", try js.get(engine, result, "imageId"));
            const output = try js.array(engine);
            lines = output;
            const is_kitty = try kitty(engine, capabilities);
            if (is_kitty) {
                const sequence = try js.get(engine, result, "sequence");
                if (c.JS_DefinePropertyValueUint32(engine.context, output, 0, sequence, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
            }
            const empty = try v.text(engine, "");
            defer engine.freeValue(empty);
            var row: f64 = 0;
            while (row < try v.numberField(engine, result, "rows") - 1) : (row += 1) {
                if (row >= 4096) {
                    _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum component frame size exceeded"));
                    unreachable;
                }
                try js.push(engine, output, empty);
            }
            if (!is_kitty) {
                const offset = try v.numberField(engine, result, "rows") - 1;
                const up = if (offset > 0) blk: {
                    const prefix = try v.text(engine, "\x1b[");
                    defer engine.freeValue(prefix);
                    const suffix = try v.text(engine, "A");
                    defer engine.freeValue(suffix);
                    break :blk try v.concat(engine, &.{ prefix, v.numeric(engine, offset), suffix });
                } else try v.text(engine, "");
                defer engine.freeValue(up);
                const sequence = try js.get(engine, result, "sequence");
                defer engine.freeValue(sequence);
                const line = try v.concat(engine, &.{ up, sequence });
                defer engine.freeValue(line);
                try js.push(engine, output, line);
            }
        }
    }
    if (lines == null) lines = try fallback(engine, exports, object, width);
    const output = lines.?;
    try v.set(engine, object, "cachedLines", c.JS_DupValue(engine.context, output));
    try v.set(engine, object, "cachedWidth", c.JS_DupValue(engine.context, width));
    return output;
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return operation(engine, object, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, data) catch |err| fail(engine, err);
}
fn operation(engine: *js.Engine, object: c.JSValue, method: Method, args: []const c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    switch (method) {
        .getImageId => return js.get(engine, object, "imageId"),
        .invalidate => {
            try v.set(engine, object, "cachedLines", c.pi_js_undefined());
            try v.set(engine, object, "cachedWidth", c.pi_js_undefined());
        },
        .render => return render(engine, object, v.arg(args, 0), data[0], data[1]),
        .setImageTranscoder => {
            try v.set(engine, data[1], "transcoder", c.JS_DupValue(engine.context, v.arg(args, 0)));
            const cache = try js.get(engine, data[1], "cache");
            defer engine.freeValue(cache);
            try invokeVoid(engine, cache, "clear", &.{});
        },
    }
    return c.pi_js_undefined();
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    inline for (.{ "base64Data", "mimeType", "dimensions", "theme", "options", "imageId", "pngData", "cachedLines", "cachedWidth" }) |name| try js.define(engine, object, name, c.pi_js_undefined());
    inline for (.{ .{ "base64Data", 0 }, .{ "mimeType", 1 }, .{ "theme", 2 } }) |field| try v.set(engine, object, field[0], c.JS_DupValue(engine.context, v.arg(args, field[1])));
    const supplied_options = v.arg(args, 3);
    const options = if (c.JS_IsUndefined(supplied_options)) try js.object(engine) else c.JS_DupValue(engine.context, supplied_options);
    defer engine.freeValue(options);
    try v.set(engine, object, "options", c.JS_DupValue(engine.context, options));
    var dimensions = c.JS_DupValue(engine.context, v.arg(args, 4));
    defer engine.freeValue(dimensions);
    if (!v.truthy(engine, dimensions)) {
        const detected = try js.invoke(engine, data[0], "getImageDimensions", &.{ v.arg(args, 0), v.arg(args, 1) });
        engine.freeValue(dimensions);
        dimensions = detected;
        if (!v.truthy(engine, dimensions)) {
            const fallback_dimensions = try js.object(engine);
            errdefer engine.freeValue(fallback_dimensions);
            try js.define(engine, fallback_dimensions, "widthPx", c.JS_NewInt32(engine.context, 800));
            try js.define(engine, fallback_dimensions, "heightPx", c.JS_NewInt32(engine.context, 600));
            engine.freeValue(dimensions);
            dimensions = fallback_dimensions;
        }
    }
    try v.set(engine, object, "dimensions", c.JS_DupValue(engine.context, dimensions));
    try v.set(engine, object, "imageId", try js.get(engine, options, "imageId"));
    return object;
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    const state = try js.object(engine);
    defer engine.freeValue(state);
    try js.define(engine, state, "transcoder", c.pi_js_undefined());
    try js.define(engine, state, "cache", try js.builtin(engine, "Map", &.{}));
    var data = [_]c.JSValue{ exports, state };
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, if (field.value == @intFromEnum(Method.render) or field.value == @intFromEnum(Method.setImageTranscoder)) 1 else 0, @intCast(field.value), data.len, &data));
        if (field.value == @intFromEnum(Method.setImageTranscoder)) try js.define(engine, exports, name.ptr, function) else if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try js.define(engine, exports, "Image", try @import("native_class.zig").constructor(engine, "Image", 3, prototype, construct, &data));
}
