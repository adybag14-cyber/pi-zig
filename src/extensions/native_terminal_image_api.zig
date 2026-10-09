//! Source terminal image strings, sizing, metadata and placement values.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
const Method = enum(c_int) { allocateImageId, encodeKitty, deleteKittyImage, deleteAllKittyImages, deleteAllKittyPlacements, encodeITerm2, registerKittyImageMetadata, getKittyImageMetadata, getKittyImagePlacementRows, getKittyImagePlacement, cropKittyImageLine, calculateImageCellSize, calculateImageRows, getPngDimensions, getJpegDimensions, getGifDimensions, getWebpDimensions, getImageDimensions, renderImage, imageFallback };
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native terminal image: %s", @as([*:0]const u8, @errorName(err)));
}
fn append(engine: *Engine, array: c.JSValue, value: c.JSValue) !void {
    defer engine.freeValue(value);
    try js.push(engine, array, value);
}
fn concat(engine: *Engine, parts: []const c.JSValue) !c.JSValue {
    return v.concat(engine, parts);
}
fn surrounding(engine: *Engine, prefix: []const u8, value: c.JSValue, suffix: []const u8) !c.JSValue {
    const before = try v.text(engine, prefix);
    defer engine.freeValue(before);
    const after = try v.text(engine, suffix);
    defer engine.freeValue(after);
    return concat(engine, &.{ before, value, after });
}
fn equalText(engine: *Engine, value: c.JSValue, text: []const u8) !bool {
    const expected = try v.text(engine, text);
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
fn options(engine: *Engine, value: c.JSValue) !c.JSValue {
    return if (c.JS_IsUndefined(value)) js.object(engine) else c.JS_DupValue(engine.context, value);
}
fn joined(engine: *Engine, array: c.JSValue, separator: []const u8) !c.JSValue {
    const text = try v.text(engine, separator);
    defer engine.freeValue(text);
    return js.invoke(engine, array, "join", &.{text});
}
fn pushOption(engine: *Engine, params: c.JSValue, object: c.JSValue, name: [*:0]const u8, prefix: []const u8, truthy: bool) !void {
    const check = try js.get(engine, object, name);
    defer engine.freeValue(check);
    if (if (truthy) v.truthy(engine, check) else !c.JS_IsUndefined(check)) {
        const value = try js.get(engine, object, name);
        defer engine.freeValue(value);
        try append(engine, params, try surrounding(engine, prefix, value, ""));
    }
}
fn encodeKitty(engine: *Engine, data: c.JSValue, supplied: c.JSValue) !c.JSValue {
    const settings = try options(engine, supplied);
    defer engine.freeValue(settings);
    const params = try js.array(engine);
    defer engine.freeValue(params);
    for ([_][]const u8{ "a=T", "f=100", "q=2" }) |text| try append(engine, params, try v.text(engine, text));
    const move = try js.get(engine, settings, "moveCursor");
    defer engine.freeValue(move);
    if (c.JS_IsStrictEqual(engine.context, move, c.pi_js_bool(engine.context, 0))) try append(engine, params, try v.text(engine, "C=1"));
    try pushOption(engine, params, settings, "columns", "c=", true);
    try pushOption(engine, params, settings, "rows", "r=", true);
    try pushOption(engine, params, settings, "imageId", "i=", true);
    const length = try v.numberField(engine, data, "length");
    const prefix = try v.text(engine, "\x1b_G");
    defer engine.freeValue(prefix);
    const separator = try v.text(engine, ";");
    defer engine.freeValue(separator);
    const end = try v.text(engine, "\x1b\\");
    defer engine.freeValue(end);
    if (length <= 4096) {
        const controls = try joined(engine, params, ",");
        defer engine.freeValue(controls);
        return concat(engine, &.{ prefix, controls, separator, data, end });
    }
    const chunks = try js.array(engine);
    defer engine.freeValue(chunks);
    var offset: f64 = 0;
    var first = true;
    while (offset < try v.numberField(engine, data, "length")) : (offset += 4096) {
        const chunk = try js.invoke(engine, data, "slice", &.{ v.numeric(engine, offset), v.numeric(engine, offset + 4096) });
        defer engine.freeValue(chunk);
        const last = offset + 4096 >= try v.numberField(engine, data, "length");
        if (first) {
            const controls = try joined(engine, params, ",");
            defer engine.freeValue(controls);
            const more = try v.text(engine, ",m=1;");
            defer engine.freeValue(more);
            try append(engine, chunks, try concat(engine, &.{ prefix, controls, more, chunk, end }));
            first = false;
        } else {
            const controls = try v.text(engine, if (last) "m=0;" else "m=1;");
            defer engine.freeValue(controls);
            try append(engine, chunks, try concat(engine, &.{ prefix, controls, chunk, end }));
        }
    }
    return joined(engine, chunks, "");
}
fn encodeITerm(engine: *Engine, data: c.JSValue, supplied: c.JSValue) !c.JSValue {
    const settings = try options(engine, supplied);
    defer engine.freeValue(settings);
    const params = try js.array(engine);
    defer engine.freeValue(params);
    const in_line = try js.get(engine, settings, "inline");
    defer engine.freeValue(in_line);
    try append(engine, params, try v.text(engine, if (c.JS_IsStrictEqual(engine.context, in_line, c.pi_js_bool(engine.context, 0))) "inline=0" else "inline=1"));
    const buffer = try js.global(engine, "Buffer");
    defer engine.freeValue(buffer);
    const encoding = try v.text(engine, "base64");
    defer engine.freeValue(encoding);
    const length = try js.invoke(engine, buffer, "byteLength", &.{ data, encoding });
    defer engine.freeValue(length);
    try append(engine, params, try surrounding(engine, "size=", length, ""));
    try pushOption(engine, params, settings, "width", "width=", false);
    try pushOption(engine, params, settings, "height", "height=", false);
    const check_name = try js.get(engine, settings, "name");
    defer engine.freeValue(check_name);
    if (v.truthy(engine, check_name)) {
        const name = try js.get(engine, settings, "name");
        defer engine.freeValue(name);
        const bytes = try js.invoke(engine, buffer, "from", &.{name});
        defer engine.freeValue(bytes);
        const encoded = try js.invoke(engine, bytes, "toString", &.{encoding});
        defer engine.freeValue(encoded);
        try append(engine, params, try surrounding(engine, "name=", encoded, ""));
    }
    const aspect = try js.get(engine, settings, "preserveAspectRatio");
    defer engine.freeValue(aspect);
    if (c.JS_IsStrictEqual(engine.context, aspect, c.pi_js_bool(engine.context, 0))) try append(engine, params, try v.text(engine, "preserveAspectRatio=0"));
    const controls = try joined(engine, params, ";");
    defer engine.freeValue(controls);
    const prefix = try v.text(engine, "\x1b]1337;File=");
    defer engine.freeValue(prefix);
    const colon = try v.text(engine, ":");
    defer engine.freeValue(colon);
    const end = try v.text(engine, "\x07");
    defer engine.freeValue(end);
    return concat(engine, &.{ prefix, controls, colon, data, end });
}
fn lessDistorted(upper: f64, ideal: f64) f64 {
    if (upper <= 1) return upper;
    const lower = upper - 1;
    const upper_distortion = v.maximum(upper / ideal, ideal / upper);
    const lower_distortion = v.maximum(lower / ideal, ideal / lower);
    return if (lower_distortion < upper_distortion) lower else upper;
}
fn defaultDimensions(engine: *Engine, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsUndefined(value)) return c.JS_DupValue(engine.context, value);
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "widthPx", v.numeric(engine, 9));
    try js.define(engine, result, "heightPx", v.numeric(engine, 18));
    return result;
}
fn cellSize(engine: *Engine, image: c.JSValue, width: c.JSValue, height: c.JSValue, supplied_cells: c.JSValue, optimize: c.JSValue) !c.JSValue {
    const cells = try defaultDimensions(engine, supplied_cells);
    defer engine.freeValue(cells);
    const max_width = v.maximum(1, @floor(try v.number(engine, width)));
    const max_height: ?f64 = if (c.JS_IsUndefined(height)) null else v.maximum(1, @floor(try v.number(engine, height)));
    const image_width = v.maximum(1, try v.numberField(engine, image, "widthPx"));
    const image_height = v.maximum(1, try v.numberField(engine, image, "heightPx"));
    const width_scale = max_width * try v.numberField(engine, cells, "widthPx") / image_width;
    const height_scale = if (max_height) |max| max * try v.numberField(engine, cells, "heightPx") / image_height else width_scale;
    const scale = v.minimum(width_scale, height_scale);
    var columns = v.maximum(1, v.minimum(max_width, @ceil(image_width * scale / try v.numberField(engine, cells, "widthPx"))));
    var rows = v.maximum(1, @ceil(image_height * scale / try v.numberField(engine, cells, "heightPx")));
    if (max_height) |max| rows = v.minimum(max, rows);
    if (v.truthy(engine, optimize)) {
        if (width_scale <= height_scale) {
            const ideal = columns * try v.numberField(engine, cells, "widthPx") * image_height / (image_width * try v.numberField(engine, cells, "heightPx"));
            rows = lessDistorted(rows, ideal);
        } else {
            const ideal = rows * try v.numberField(engine, cells, "heightPx") * image_width / (image_height * try v.numberField(engine, cells, "widthPx"));
            columns = lessDistorted(columns, ideal);
        }
    }
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "columns", v.numeric(engine, columns));
    try js.define(engine, result, "rows", v.numeric(engine, rows));
    return result;
}
fn register(engine: *Engine, state: c.JSValue, metadata: c.JSValue) !void {
    const generation = try v.numberField(engine, state, "kittyTransmissionGeneration") + 1;
    try v.set(engine, state, "kittyTransmissionGeneration", v.numeric(engine, generation));
    const map = try js.get(engine, state, "kittyImageMetadata");
    defer engine.freeValue(map);
    const old_id = try js.get(engine, metadata, "imageId");
    defer engine.freeValue(old_id);
    try v.invokeVoid(engine, map, "delete", &.{old_id});
    const id = try js.get(engine, metadata, "imageId");
    defer engine.freeValue(id);
    const copied = try js.spread(engine, metadata);
    defer engine.freeValue(copied);
    try v.set(engine, copied, "transmissionGeneration", v.numeric(engine, generation));
    try v.invokeVoid(engine, map, "set", &.{ id, copied });
    if (try v.numberField(engine, map, "size") > 1000) {
        const keys = try js.invoke(engine, map, "keys", &.{});
        defer engine.freeValue(keys);
        const entry = try js.invoke(engine, keys, "next", &.{});
        defer engine.freeValue(entry);
        const first = try js.get(engine, entry, "value");
        defer engine.freeValue(first);
        if (!c.JS_IsUndefined(first)) try v.invokeVoid(engine, map, "delete", &.{first});
    }
}
const Controls = struct {
    engine: *Engine,
    units: []u16,
    start: usize,
    end: usize,
    fn deinit(self: Controls) void {
        self.engine.gpa.free(self.units);
    }
    fn text(self: Controls) []const u16 {
        return self.units[self.start + 3 .. self.end - 1];
    }
};
fn parseControls(engine: *Engine, line: c.JSValue) !?Controls {
    const units = try utf16.unitsAlloc(engine, line);
    var transferred = false;
    defer if (!transferred) engine.gpa.free(units);
    const start = std.mem.indexOf(u16, units, &.{ 0x1b, '_', 'G' }) orelse return null;
    const end = std.mem.indexOfScalarPos(u16, units, start + 3, ';') orelse return null;
    transferred = true;
    return .{ .engine = engine, .units = units, .start = start, .end = end + 1 };
}
fn controlNumber(engine: *Engine, source: []const u16, key: u16) !c.JSValue {
    var fields = std.mem.splitScalar(u16, source, ',');
    while (fields.next()) |field| {
        if (field.len < 3 or field[0] != key or field[1] != '=') continue;
        var digits = true;
        for (field[2..]) |unit| if (unit < '0' or unit > '9') {
            digits = false;
            break;
        };
        if (!digits) continue;
        const text = try utf16.string(engine, field[2..]);
        defer engine.freeValue(text);
        const number = try js.global(engine, "Number");
        defer engine.freeValue(number);
        return js.invoke(engine, number, "parseInt", &.{ text, v.numeric(engine, 10) });
    }
    return c.pi_js_undefined();
}
fn registered(engine: *Engine, state: c.JSValue, source: []const u16) !c.JSValue {
    const id = try controlNumber(engine, source, 'i');
    defer engine.freeValue(id);
    if (c.JS_IsUndefined(id)) return c.pi_js_undefined();
    const map = try js.get(engine, state, "kittyImageMetadata");
    defer engine.freeValue(map);
    return js.invoke(engine, map, "get", &.{id});
}
fn lookupMetadata(engine: *Engine, state: c.JSValue, line: c.JSValue) !c.JSValue {
    const parsed = (try parseControls(engine, line)) orelse return c.pi_js_undefined();
    defer parsed.deinit();
    const source = try registered(engine, state, parsed.text());
    defer engine.freeValue(source);
    if (!v.truthy(engine, source)) return c.pi_js_undefined();
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ "imageId", "columns", "rows", "widthPx", "heightPx" }) |name| try js.define(engine, result, name, try js.get(engine, source, name));
    return result;
}
fn explicitRows(engine: *Engine, source: []const u16) !c.JSValue {
    const rows = try controlNumber(engine, source, 'r');
    errdefer engine.freeValue(rows);
    if (!c.JS_IsUndefined(rows) and try v.number(engine, rows) > 0) return rows;
    engine.freeValue(rows);
    return c.pi_js_undefined();
}
fn placementRows(engine: *Engine, state: c.JSValue, line: c.JSValue) !c.JSValue {
    const parsed = (try parseControls(engine, line)) orelse return c.pi_js_undefined();
    defer parsed.deinit();
    const rows = try explicitRows(engine, parsed.text());
    if (!c.JS_IsUndefined(rows)) return rows;
    engine.freeValue(rows);
    const source = try registered(engine, state, parsed.text());
    defer engine.freeValue(source);
    return if (c.JS_IsNull(source) or c.JS_IsUndefined(source)) c.pi_js_undefined() else js.get(engine, source, "rows");
}
fn fieldEquals(source: []const u16, wanted: []const u16) bool {
    var fields = std.mem.splitScalar(u16, source, ',');
    while (fields.next()) |field| if (std.mem.eql(u16, field, wanted)) return true;
    return false;
}
fn placement(engine: *Engine, state: c.JSValue, line: c.JSValue) !c.JSValue {
    const parsed = (try parseControls(engine, line)) orelse return c.pi_js_undefined();
    defer parsed.deinit();
    const source = try registered(engine, state, parsed.text());
    defer engine.freeValue(source);
    if (!v.truthy(engine, source)) return c.pi_js_undefined();
    var command_start = parsed.start;
    var command_controls = parsed.text();
    var transmission_end: usize = 0;
    while (true) {
        const end = std.mem.indexOfPos(u16, parsed.units, command_start + 3, &.{ 0x1b, '\\' }) orelse return c.pi_js_undefined();
        transmission_end = end + 2;
        if (!fieldEquals(command_controls, std.unicode.utf8ToUtf16LeStringLiteral("m=1"))) break;
        command_start = transmission_end;
        if (!std.mem.startsWith(u16, parsed.units[command_start..], &.{ 0x1b, '_', 'G' })) return c.pi_js_undefined();
        const controls_end = std.mem.indexOfScalarPos(u16, parsed.units, command_start + 3, ';') orelse return c.pi_js_undefined();
        command_controls = parsed.units[command_start + 3 .. controls_end];
    }
    var kept: std.ArrayList(u16) = .empty;
    defer kept.deinit(engine.gpa);
    var fields = std.mem.splitScalar(u16, parsed.text(), ',');
    var first = true;
    const allowed = std.unicode.utf8ToUtf16LeStringLiteral("ipxywhXYcrCUzPQHV");
    while (fields.next()) |field| {
        const key = field[0 .. std.mem.indexOfScalar(u16, field, '=') orelse field.len];
        if (key.len != 1 or std.mem.indexOfScalar(u16, allowed, key[0]) == null) continue;
        if (!first) try kept.append(engine.gpa, ',');
        first = false;
        try kept.appendSlice(engine.gpa, field);
    }
    const kept_value = try utf16.string(engine, kept.items);
    defer engine.freeValue(kept_value);
    const sequence = try surrounding(engine, "\x1b_Ga=p,q=2,", kept_value, "\x1b\\");
    defer engine.freeValue(sequence);
    const before = try utf16.string(engine, parsed.units[0..parsed.start]);
    defer engine.freeValue(before);
    const after = try utf16.string(engine, parsed.units[transmission_end..]);
    defer engine.freeValue(after);
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "imageId", try js.get(engine, source, "imageId"));
    try js.define(engine, result, "transmissionGeneration", try js.get(engine, source, "transmissionGeneration"));
    try js.define(engine, result, "transmissionBytes", v.numeric(engine, @floatFromInt(transmission_end - parsed.start)));
    try js.define(engine, result, "estimatedDecodedBytes", v.numeric(engine, try v.numberField(engine, source, "widthPx") * try v.numberField(engine, source, "heightPx") * 4));
    const explicit = try explicitRows(engine, parsed.text());
    defer engine.freeValue(explicit);
    try js.define(engine, result, "rows", if (c.JS_IsNull(explicit) or c.JS_IsUndefined(explicit)) try js.get(engine, source, "rows") else c.JS_DupValue(engine.context, explicit));
    try js.define(engine, result, "sequence", c.JS_DupValue(engine.context, sequence));
    try js.define(engine, result, "replacementLine", try concat(engine, &.{ before, sequence, after }));
    return result;
}
fn cropEndRows(engine: *Engine, state: c.JSValue, hidden: c.JSValue, rows: f64) !f64 {
    var primitive = c.JS_DupValue(engine.context, hidden);
    defer engine.freeValue(primitive);
    if (c.JS_IsObject(hidden)) {
        const symbol = try js.get(engine, state, "imageToPrimitiveSymbol");
        defer engine.freeValue(symbol);
        const exotic = try js.getKey(engine, hidden, symbol);
        defer engine.freeValue(exotic);
        if (!c.JS_IsNull(exotic) and !c.JS_IsUndefined(exotic)) {
            const hint = try v.text(engine, "default");
            defer engine.freeValue(hint);
            engine.freeValue(primitive);
            primitive = c.pi_js_undefined();
            primitive = try js.call(engine, exotic, hidden, &.{hint});
            if (c.JS_IsObject(primitive)) return js.typeError(engine, "Cannot convert object to primitive value");
        } else {
            var converted = false;
            inline for (.{ "valueOf", "toString" }) |method_name| {
                if (!converted) {
                    const converter = try js.get(engine, hidden, method_name);
                    defer engine.freeValue(converter);
                    if (c.JS_IsFunction(engine.context, converter)) {
                        const value = try js.call(engine, converter, hidden, &.{});
                        if (!c.JS_IsObject(value)) {
                            engine.freeValue(primitive);
                            primitive = value;
                            converted = true;
                        } else engine.freeValue(value);
                    }
                }
            }
            if (!converted) return js.typeError(engine, "Cannot convert object to primitive value");
        }
    }
    if (c.JS_IsString(primitive)) {
        const combined = try concat(engine, &.{ primitive, v.numeric(engine, rows) });
        defer engine.freeValue(combined);
        return v.number(engine, combined);
    }
    return try v.number(engine, primitive) + rows;
}
fn crop(engine: *Engine, state: c.JSValue, line: c.JSValue, hidden: c.JSValue, visible: c.JSValue) !c.JSValue {
    const image = try lookupMetadata(engine, state, line);
    defer engine.freeValue(image);
    const parsed = try parseControls(engine, line);
    defer if (parsed) |value| value.deinit();
    if (!v.truthy(engine, image) or parsed == null) return c.JS_DupValue(engine.context, line);
    if (try v.number(engine, hidden) < 0 or try v.number(engine, hidden) >= try v.numberField(engine, image, "rows") or try v.number(engine, visible) <= 0) return c.JS_DupValue(engine.context, line);
    const rows = v.minimum(try v.number(engine, visible), try v.numberField(engine, image, "rows") - try v.number(engine, hidden));
    if (c.JS_IsStrictEqual(engine.context, hidden, v.numeric(engine, 0)) and rows == try v.numberField(engine, image, "rows")) return c.JS_DupValue(engine.context, line);
    const source_y = @floor(try v.numberField(engine, image, "heightPx") * try v.number(engine, hidden) / try v.numberField(engine, image, "rows"));
    const source_end = @ceil(try v.numberField(engine, image, "heightPx") * try cropEndRows(engine, state, hidden, rows) / try v.numberField(engine, image, "rows"));
    const source_height = v.maximum(1, v.minimum(try v.numberField(engine, image, "heightPx"), source_end) - source_y);
    const params = try js.array(engine);
    defer engine.freeValue(params);
    var fields = std.mem.splitScalar(u16, parsed.?.text(), ',');
    while (fields.next()) |field| {
        if (field.len >= 2 and field[1] == '=' and (field[0] == 'y' or field[0] == 'h' or field[0] == 'r')) continue;
        try append(engine, params, try utf16.string(engine, field));
    }
    try append(engine, params, try surrounding(engine, "y=", v.numeric(engine, source_y), ""));
    try append(engine, params, try surrounding(engine, "h=", v.numeric(engine, source_height), ""));
    try append(engine, params, try surrounding(engine, "r=", v.numeric(engine, rows), ""));
    const joined_params = try joined(engine, params, ",");
    defer engine.freeValue(joined_params);
    const command = try surrounding(engine, "\x1b_G", joined_params, ";");
    defer engine.freeValue(command);
    const before = try utf16.string(engine, parsed.?.units[0..parsed.?.start]);
    defer engine.freeValue(before);
    const after = try utf16.string(engine, parsed.?.units[parsed.?.end..]);
    defer engine.freeValue(after);
    return concat(engine, &.{ before, command, after });
}
fn imageDimensions(engine: *Engine, data: c.JSValue, operation: Method) !c.JSValue {
    return imageDimensionsChecked(engine, data, operation) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (err == error.JavaScriptException) {
            if (engine.captured_exception) |value| engine.freeValue(value);
            engine.captured_exception = null;
            if (engine.last_error) |value| engine.gpa.free(value);
            engine.last_error = null;
            return c.pi_js_null();
        }
        return err;
    };
}
fn dimensionResult(engine: *Engine, width: c.JSValue, height: c.JSValue) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "widthPx", c.JS_DupValue(engine.context, width));
    try js.define(engine, result, "heightPx", c.JS_DupValue(engine.context, height));
    return result;
}
fn readInteger(engine: *Engine, buffer: c.JSValue, name: [*:0]const u8, offset: f64) !c.JSValue {
    return js.invoke(engine, buffer, name, &.{v.numeric(engine, offset)});
}
fn bitValue(engine: *Engine, value: c.JSValue) !u32 {
    var result: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn prefixBytes(engine: *Engine, buffer: c.JSValue, wanted: []const u8) !bool {
    for (wanted, 0..) |byte, index| {
        const value = try v.fieldAt(engine, buffer, @floatFromInt(index));
        defer engine.freeValue(value);
        if (!c.JS_IsStrictEqual(engine.context, value, v.numeric(engine, @floatFromInt(byte)))) return false;
    }
    return true;
}
fn asciiRange(engine: *Engine, buffer: c.JSValue, start: f64, end: f64) !c.JSValue {
    const slice = try js.invoke(engine, buffer, "slice", &.{ v.numeric(engine, start), v.numeric(engine, end) });
    defer engine.freeValue(slice);
    const ascii = try v.text(engine, "ascii");
    defer engine.freeValue(ascii);
    return js.invoke(engine, slice, "toString", &.{ascii});
}
fn imageDimensionsChecked(engine: *Engine, data: c.JSValue, operation: Method) !c.JSValue {
    const constructor = try js.global(engine, "Buffer");
    defer engine.freeValue(constructor);
    const encoding = try v.text(engine, "base64");
    defer engine.freeValue(encoding);
    const buffer = try js.invoke(engine, constructor, "from", &.{ data, encoding });
    defer engine.freeValue(buffer);
    if (operation == .getPngDimensions) {
        if (try v.numberField(engine, buffer, "length") < 24 or !try prefixBytes(engine, buffer, "\x89PNG")) return c.pi_js_null();
        const width = try readInteger(engine, buffer, "readUInt32BE", 16);
        defer engine.freeValue(width);
        const height = try readInteger(engine, buffer, "readUInt32BE", 20);
        defer engine.freeValue(height);
        return dimensionResult(engine, width, height);
    }
    if (operation == .getJpegDimensions) {
        if (try v.numberField(engine, buffer, "length") < 2 or !try prefixBytes(engine, buffer, "\xff\xd8")) return c.pi_js_null();
        var offset: f64 = 2;
        while (offset < try v.numberField(engine, buffer, "length") - 9) {
            const byte = try v.fieldAt(engine, buffer, offset);
            defer engine.freeValue(byte);
            if (!c.JS_IsStrictEqual(engine.context, byte, v.numeric(engine, 255))) {
                offset += 1;
                continue;
            }
            const marker_value = try v.fieldAt(engine, buffer, offset + 1);
            defer engine.freeValue(marker_value);
            const marker = try v.number(engine, marker_value);
            if (marker >= 0xc0 and marker <= 0xc2) {
                const height = try readInteger(engine, buffer, "readUInt16BE", offset + 5);
                defer engine.freeValue(height);
                const width = try readInteger(engine, buffer, "readUInt16BE", offset + 7);
                defer engine.freeValue(width);
                return dimensionResult(engine, width, height);
            }
            if (offset + 3 >= try v.numberField(engine, buffer, "length")) return c.pi_js_null();
            const length_value = try readInteger(engine, buffer, "readUInt16BE", offset + 2);
            defer engine.freeValue(length_value);
            const length = try v.number(engine, length_value);
            if (length < 2) return c.pi_js_null();
            offset += 2 + length;
        }
        return c.pi_js_null();
    }
    if (operation == .getGifDimensions) {
        if (try v.numberField(engine, buffer, "length") < 10) return c.pi_js_null();
        const signature = try asciiRange(engine, buffer, 0, 6);
        defer engine.freeValue(signature);
        if (!try equalText(engine, signature, "GIF87a") and !try equalText(engine, signature, "GIF89a")) return c.pi_js_null();
        const width = try readInteger(engine, buffer, "readUInt16LE", 6);
        defer engine.freeValue(width);
        const height = try readInteger(engine, buffer, "readUInt16LE", 8);
        defer engine.freeValue(height);
        return dimensionResult(engine, width, height);
    }
    if (try v.numberField(engine, buffer, "length") < 30) return c.pi_js_null();
    const riff = try asciiRange(engine, buffer, 0, 4);
    defer engine.freeValue(riff);
    const webp = try asciiRange(engine, buffer, 8, 12);
    defer engine.freeValue(webp);
    if (!try equalText(engine, riff, "RIFF") or !try equalText(engine, webp, "WEBP")) return c.pi_js_null();
    const chunk = try asciiRange(engine, buffer, 12, 16);
    defer engine.freeValue(chunk);
    if (try equalText(engine, chunk, "VP8 ")) {
        const width_value = try readInteger(engine, buffer, "readUInt16LE", 26);
        defer engine.freeValue(width_value);
        const height_value = try readInteger(engine, buffer, "readUInt16LE", 28);
        defer engine.freeValue(height_value);
        return dimensionResult(engine, v.numeric(engine, @floatFromInt(try bitValue(engine, width_value) & 0x3fff)), v.numeric(engine, @floatFromInt(try bitValue(engine, height_value) & 0x3fff)));
    }
    if (try equalText(engine, chunk, "VP8L")) {
        const bits_value = try readInteger(engine, buffer, "readUInt32LE", 21);
        defer engine.freeValue(bits_value);
        const bits = try bitValue(engine, bits_value);
        return dimensionResult(engine, v.numeric(engine, @floatFromInt((bits & 0x3fff) + 1)), v.numeric(engine, @floatFromInt(((bits >> 14) & 0x3fff) + 1)));
    }
    if (try equalText(engine, chunk, "VP8X")) {
        var dimensions: [2]u32 = @splat(0);
        for (&dimensions, 0..) |*dimension, index| for (0..3) |byte| {
            const value = try v.fieldAt(engine, buffer, @floatFromInt(24 + index * 3 + byte));
            defer engine.freeValue(value);
            dimension.* |= try bitValue(engine, value) << @intCast(byte * 8);
        };
        return dimensionResult(engine, v.numeric(engine, @as(f64, @floatFromInt(@as(i32, @bitCast(dimensions[0])))) + 1), v.numeric(engine, @as(f64, @floatFromInt(@as(i32, @bitCast(dimensions[1])))) + 1));
    }
    return c.pi_js_null();
}
fn renderImage(engine: *Engine, state: c.JSValue, helpers: c.JSValue, data: c.JSValue, image: c.JSValue, supplied: c.JSValue) !c.JSValue {
    const settings = try options(engine, supplied);
    defer engine.freeValue(settings);
    const caps = try js.invoke(engine, helpers, "getCapabilities", &.{});
    defer engine.freeValue(caps);
    const images = try js.get(engine, caps, "images");
    defer engine.freeValue(images);
    if (!v.truthy(engine, images)) return c.pi_js_null();
    const width_value = try js.get(engine, settings, "maxWidthCells");
    defer engine.freeValue(width_value);
    const width = if (c.JS_IsUndefined(width_value) or c.JS_IsNull(width_value)) v.numeric(engine, 80) else width_value;
    const height = try js.get(engine, settings, "maxHeightCells");
    defer engine.freeValue(height);
    const cells = try js.invoke(engine, helpers, "getCellDimensions", &.{});
    defer engine.freeValue(cells);
    const kitty = try equalText(engine, images, "kitty");
    const size = try cellSize(engine, image, width, height, cells, c.pi_js_bool(engine.context, @intFromBool(kitty)));
    defer engine.freeValue(size);
    if (kitty) {
        const check_id = try js.get(engine, settings, "imageId");
        defer engine.freeValue(check_id);
        if (!c.JS_IsUndefined(check_id)) {
            const info = try js.object(engine);
            defer engine.freeValue(info);
            try js.define(engine, info, "imageId", try js.get(engine, settings, "imageId"));
            inline for (.{ "columns", "rows" }) |name| try js.define(engine, info, name, try js.get(engine, size, name));
            inline for (.{ "widthPx", "heightPx" }) |name| try js.define(engine, info, name, try js.get(engine, image, name));
            try register(engine, state, info);
        }
        const encode_options = try js.object(engine);
        defer engine.freeValue(encode_options);
        inline for (.{ "columns", "rows" }) |name| try js.define(engine, encode_options, name, try js.get(engine, size, name));
        inline for (.{ "imageId", "moveCursor" }) |name| try js.define(engine, encode_options, name, try js.get(engine, settings, name));
        const sequence = try encodeKitty(engine, data, encode_options);
        defer engine.freeValue(sequence);
        const result = try js.object(engine);
        errdefer engine.freeValue(result);
        try js.define(engine, result, "sequence", c.JS_DupValue(engine.context, sequence));
        inline for (.{ "columns", "rows" }) |name| try js.define(engine, result, name, try js.get(engine, size, name));
        try js.define(engine, result, "imageId", try js.get(engine, settings, "imageId"));
        return result;
    }
    if (try equalText(engine, images, "iterm2")) {
        const encode_options = try js.object(engine);
        defer engine.freeValue(encode_options);
        try js.define(engine, encode_options, "width", try js.get(engine, size, "columns"));
        try js.define(engine, encode_options, "height", try v.text(engine, "auto"));
        const aspect = try js.get(engine, settings, "preserveAspectRatio");
        defer engine.freeValue(aspect);
        try js.define(engine, encode_options, "preserveAspectRatio", if (c.JS_IsNull(aspect) or c.JS_IsUndefined(aspect)) c.pi_js_bool(engine.context, 1) else c.JS_DupValue(engine.context, aspect));
        const sequence = try encodeITerm(engine, data, encode_options);
        defer engine.freeValue(sequence);
        const result = try js.object(engine);
        errdefer engine.freeValue(result);
        try js.define(engine, result, "sequence", c.JS_DupValue(engine.context, sequence));
        inline for (.{ "columns", "rows" }) |name| try js.define(engine, result, name, try js.get(engine, size, name));
        return result;
    }
    return c.pi_js_null();
}
fn homeDirectory(engine: *Engine) !c.JSValue {
    return @import("native_home.zig").get(engine);
}
fn fallback(engine: *Engine, helpers: c.JSValue, mime: c.JSValue, dimensions: c.JSValue, filename: c.JSValue) !c.JSValue {
    const parts = try js.array(engine);
    defer engine.freeValue(parts);
    if (v.truthy(engine, filename)) {
        const home = try homeDirectory(engine);
        defer engine.freeValue(home);
        const home_units = try utf16.unitsAlloc(engine, home);
        defer engine.gpa.free(home_units);
        var short = home_units.len > 0 and c.JS_IsStrictEqual(engine.context, filename, home);
        if (home_units.len > 0 and !short) {
            inline for (.{ "/", "\\" }) |separator| {
                if (!short) {
                    const prefix = try surrounding(engine, "", home, separator);
                    defer engine.freeValue(prefix);
                    const match = try js.invoke(engine, filename, "startsWith", &.{prefix});
                    defer engine.freeValue(match);
                    short = v.truthy(engine, match);
                }
            }
        }
        const display = if (short) blk: {
            const suffix = try js.invoke(engine, filename, "slice", &.{v.numeric(engine, @floatFromInt(home_units.len))});
            defer engine.freeValue(suffix);
            break :blk try surrounding(engine, "~", suffix, "");
        } else c.JS_DupValue(engine.context, filename);
        defer engine.freeValue(display);
        const caps = try js.invoke(engine, helpers, "getCapabilities", &.{});
        defer engine.freeValue(caps);
        const hyperlinks = try js.get(engine, caps, "hyperlinks");
        defer engine.freeValue(hyperlinks);
        const absolute = if (v.truthy(engine, hyperlinks)) blk: {
            if (!c.JS_IsString(filename)) {
                const message = try v.text(engine, "The \"path\" argument must be of type string. Received an instance of Object");
                defer engine.freeValue(message);
                const exception = try js.builtin(engine, "TypeError", &.{message});
                var transferred = false;
                errdefer if (!transferred) engine.freeValue(exception);
                try js.define(engine, exception, "code", try v.text(engine, "ERR_INVALID_ARG_TYPE"));
                transferred = true;
                _ = try engine.checked(c.JS_Throw(engine.context, exception));
                unreachable;
            }
            const bytes = try engine.toString(filename);
            defer engine.gpa.free(bytes);
            break :blk if (builtin.os.tag == .windows) std.fs.path.isAbsoluteWindows(bytes) else std.fs.path.isAbsolutePosix(bytes);
        } else false;
        if (absolute) {
            const url_module = engine.native_module_values.get("node:url") orelse return error.NativeImageFileUrlUnavailable;
            const url = try js.invoke(engine, url_module, "pathToFileURL", &.{filename});
            defer engine.freeValue(url);
            const href = try js.get(engine, url, "href");
            defer engine.freeValue(href);
            try append(engine, parts, try js.invoke(engine, helpers, "hyperlink", &.{ display, href }));
        } else try js.push(engine, parts, display);
    }
    try append(engine, parts, try surrounding(engine, "[", mime, "]"));
    if (v.truthy(engine, dimensions)) {
        const width = try js.get(engine, dimensions, "widthPx");
        defer engine.freeValue(width);
        const height = try js.get(engine, dimensions, "heightPx");
        defer engine.freeValue(height);
        const separator = try v.text(engine, "x");
        defer engine.freeValue(separator);
        try append(engine, parts, try concat(engine, &.{ width, separator, height }));
    }
    const content = try joined(engine, parts, " ");
    defer engine.freeValue(content);
    return surrounding(engine, "[Image: ", content, "]");
}
fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return method(engine, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)], data[0], data[1]) catch |err| fail(engine, err);
}
fn method(engine: *Engine, operation: Method, args: []const c.JSValue, state: c.JSValue, helpers: c.JSValue) !c.JSValue {
    switch (operation) {
        .allocateImageId => {
            const math = try js.global(engine, "Math");
            defer engine.freeValue(math);
            const random = try js.invoke(engine, math, "random", &.{});
            defer engine.freeValue(random);
            return v.numeric(engine, @floor(try v.number(engine, random) * 0xfffffffe) + 1);
        },
        .encodeKitty => return encodeKitty(engine, v.arg(args, 0), v.arg(args, 1)),
        .deleteKittyImage => return surrounding(engine, "\x1b_Ga=d,d=I,i=", v.arg(args, 0), ",q=2\x1b\\"),
        .deleteAllKittyImages => return v.text(engine, "\x1b_Ga=d,d=A,q=2\x1b\\"),
        .deleteAllKittyPlacements => return v.text(engine, "\x1b_Ga=d,d=a,q=2\x1b\\"),
        .encodeITerm2 => return encodeITerm(engine, v.arg(args, 0), v.arg(args, 1)),
        .registerKittyImageMetadata => try register(engine, state, v.arg(args, 0)),
        .getKittyImageMetadata => return lookupMetadata(engine, state, v.arg(args, 0)),
        .getKittyImagePlacementRows => return placementRows(engine, state, v.arg(args, 0)),
        .getKittyImagePlacement => return placement(engine, state, v.arg(args, 0)),
        .cropKittyImageLine => return crop(engine, state, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)),
        .calculateImageCellSize => return cellSize(engine, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2), v.arg(args, 3), v.arg(args, 4)),
        .calculateImageRows => {
            const size = try cellSize(engine, v.arg(args, 0), v.arg(args, 1), c.pi_js_undefined(), v.arg(args, 2), c.pi_js_bool(engine.context, 0));
            defer engine.freeValue(size);
            return js.get(engine, size, "rows");
        },
        .getPngDimensions, .getJpegDimensions, .getGifDimensions, .getWebpDimensions => return imageDimensions(engine, v.arg(args, 0), operation),
        .getImageDimensions => {
            inline for (.{ .{ "image/png", Method.getPngDimensions }, .{ "image/jpeg", Method.getJpegDimensions }, .{ "image/gif", Method.getGifDimensions }, .{ "image/webp", Method.getWebpDimensions } }) |mapping| {
                if (try equalText(engine, v.arg(args, 1), mapping[0])) return imageDimensions(engine, v.arg(args, 0), mapping[1]);
            }
            return c.pi_js_null();
        },
        .renderImage => return renderImage(engine, state, helpers, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)),
        .imageFallback => return fallback(engine, helpers, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)),
    }
    return c.pi_js_undefined();
}
pub fn install(engine: *Engine, exports: c.JSValue, state: c.JSValue) !void {
    try @import("node_buffer.zig").install(engine);
    if (!engine.native_module_names.contains("node:url")) try @import("node_url.zig").install(engine);
    try js.define(engine, state, "kittyImageMetadata", try js.builtin(engine, "Map", &.{}));
    try js.define(engine, state, "kittyTransmissionGeneration", v.numeric(engine, 0));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    try js.define(engine, state, "imageToPrimitiveSymbol", try js.get(engine, symbol, "toPrimitive"));
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const operation: Method = @enumFromInt(field.value);
        const arity: c_int = switch (operation) {
            .allocateImageId, .deleteAllKittyImages, .deleteAllKittyPlacements => 0,
            .calculateImageCellSize, .cropKittyImageLine, .imageFallback => 3,
            .calculateImageRows, .getImageDimensions, .renderImage => 2,
            else => 1,
        };
        var data = [_]c.JSValue{ state, exports };
        try js.define(engine, exports, name.ptr, try engine.checked(c.JS_NewCFunctionData2(engine.context, call, name.ptr, arity, @intCast(field.value), 2, &data)));
    }
}
test "Source6fb terminal image API original encoders dimensions sizing placement crop registry and public arity" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"native-image"});
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/terminal-image-api-original-6fb.json");
    try js.define(engine, root, "imageFixture", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "terminal-image-api-original-6fb.json")));
    const result = engine.evalModule(
        \\import*as api from'pi-tui';for(const[index,item]of imageFixture.cases.entries()){let actual;try{actual=api[item.name](...item.args.map(a=>a?.__nativeUndefined?undefined:a))}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw Error(JSON.stringify({index,error:String(e),item}))}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item}));}for(const[index,item]of imageFixture.structural.entries()){let actual;try{actual=new Function('api','"use strict";'+item.script)(api)}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw e}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({structural:index,actual,expected:item}));}for(const[name,length]of Object.entries(imageFixture.shape))if(typeof api[name]!=='function'||api[name].length!==length)throw Error(JSON.stringify({name,length,actual:api[name]?.length}));
    , "terminal-image-api-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native terminal image API: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb terminal image API callback order raw exceptions coercion and transmission generation" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"native-image"});
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/terminal-image-callbacks-original-6fb.json");
    try js.define(engine, root, "imageCallbacks", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "terminal-image-callbacks-original-6fb.json")));
    const result = engine.evalModule(
        \\import*as api from'pi-tui';for(const[index,item]of imageCallbacks.cases.entries()){let actual;try{actual=new Function('api','"use strict";'+item.script)(api)}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw e}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item}));}
    , "terminal-image-callbacks-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native terminal image callbacks: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb terminal image API fallback home shortening absolute path URLs and platform separators" {
    if (builtin.os.tag != .windows and builtin.os.tag != .linux) return error.SkipZigTest;
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"native-image"});
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = if (builtin.os.tag == .windows) @embedFile("fixtures/terminal-image-fallback-original-win32-6fb.json") else @embedFile("fixtures/terminal-image-fallback-original-linux-6fb.json");
    try js.define(engine, root, "imageFallbackFixture", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "terminal-image-fallback-original-6fb.json")));
    const result = engine.evalModule(
        \\import*as api from'pi-tui';process.env[imageFallbackFixture.platform==='win32'?'USERPROFILE':'HOME']=imageFallbackFixture.home;for(const[index,item]of imageFallbackFixture.cases.entries()){api.setCapabilities({images:null,trueColor:true,hyperlinks:item.hyperlinks});let actual;try{actual=api.imageFallback('image/png',item.dimensions??undefined,item.filename??undefined)}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage&&e.code===item.errorCode)continue;throw e}if(item.errorName||actual!==item.result)throw Error(JSON.stringify({index,actual,expected:item}));}
    , "terminal-image-fallback-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native terminal image fallback: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"native-image"});
    const exports = try js.object(engine);
    defer engine.freeValue(exports);
    try @import("native_terminal_image.zig").install(engine, exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "api", c.JS_DupValue(engine.context, exports));
    const original_allocator = engine.gpa;
    engine.gpa = gpa;
    defer engine.gpa = original_allocator;
    defer engine.beginInvocation();
    const result = engine.eval(
        \\(()=>{api.setCapabilities({images:'kitty',trueColor:true,hyperlinks:true});api.registerKittyImageMetadata({imageId:71,columns:3,rows:7,widthPx:30,heightPx:100});const line=api.encodeKitty('YWJj'.repeat(1100),{imageId:71,columns:3,rows:7,moveCursor:false});api.getKittyImageMetadata(line);api.getKittyImagePlacementRows(line);api.getKittyImagePlacement(line);api.cropKittyImageLine(line,{[Symbol.toPrimitive](hint){return hint==='default'?'1':1}},2);api.encodeITerm2('Y W J j',{name:'界😀',width:'30%',height:'auto'});api.calculateImageCellSize({widthPx:71,heightPx:103},10,4,{widthPx:9,heightPx:18},true);api.renderImage('YWJj',{widthPx:71,heightPx:103},{imageId:72,maxWidthCells:4,maxHeightCells:3});api.imageFallback('image/png',{widthPx:71,heightPx:103},'/tmp/a b界.png');api.deleteKittyImage(71);api.deleteAllKittyImages();api.deleteAllKittyPlacements();return true})()
    , "terminal-image-owned-allocation.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return @import("native_text_component.zig").allocationError(engine, err);
    engine.freeValue(result);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "Source6fb terminal image API all allocation failures release encoders controls crop placement fallback and callbacks" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
fn installationProbe(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const exports = try js.object(engine);
    defer engine.freeValue(exports);
    @import("native_terminal_image.zig").install(engine, exports) catch |err| return @import("native_text_component.zig").allocationError(engine, err);
    c.JS_RunGC(engine.runtime);
}
test "Source6fb terminal image API all installation allocation failures release capability registry Buffer URL and callback roots" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, installationProbe, .{});
}
