//! Source stdin framing over ordinary UTF16 fields, EventEmitter and actual timers.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
const arithmetic = @import("native_tui_value_arithmetic.zig");
const Method = enum(c_int) { process, emitDataSequence, flush, clear, getBuffer, destroy };
const paste_start = "\x1b[200~";
const paste_end = "\x1b[201~";
threadlocal var process_depth: usize = 0;
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native StdinBuffer: %s", @as([*:0]const u8, @errorName(err)));
}
fn invokeVoid(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const value = try js.invoke(engine, object, name, args);
    engine.freeValue(value);
}
fn truthyField(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8) !bool {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn sameText(engine: *js.Engine, value: c.JSValue, text: []const u8) !bool {
    const expected = try v.text(engine, text);
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
fn clearTimer(engine: *js.Engine, object: c.JSValue) !void {
    if (!try truthyField(engine, object, "timeout")) return;
    const function = try js.global(engine, "clearTimeout");
    defer engine.freeValue(function);
    const timer = try js.get(engine, object, "timeout");
    defer engine.freeValue(timer);
    const result = try js.call(engine, function, c.pi_js_undefined(), &.{timer});
    engine.freeValue(result);
    try v.set(engine, object, "timeout", c.pi_js_null());
}
fn mousePayload(payload: []const u16) bool {
    if (payload.len < 6 or payload[0] != '<' or (payload[payload.len - 1] != 'M' and payload[payload.len - 1] != 'm')) return false;
    var groups: usize = 0;
    var digits: usize = 0;
    for (payload[1 .. payload.len - 1]) |unit| {
        if (unit == ';') {
            if (digits == 0) return false;
            groups += 1;
            digits = 0;
        } else if (unit >= '0' and unit <= '9') digits += 1 else return false;
    }
    return groups == 2 and digits > 0;
}
fn complete(sequence: []const u16) bool {
    if (sequence.len == 0 or sequence[0] != 0x1b) return true;
    if (sequence.len == 1) return false;
    switch (sequence[1]) {
        '[' => {
            if (sequence.len >= 3 and sequence[2] == 'M') return sequence.len >= 6;
            if (sequence.len < 3) return false;
            const last = sequence[sequence.len - 1];
            if (last < 0x40 or last > 0x7e) return false;
            if (sequence[2] == '<') return mousePayload(sequence[2..]);
            return true;
        },
        ']' => return sequence[sequence.len - 1] == 7 or (sequence.len >= 3 and sequence[sequence.len - 2] == 0x1b and sequence[sequence.len - 1] == '\\'),
        'P', '_' => return sequence.len >= 3 and sequence[sequence.len - 2] == 0x1b and sequence[sequence.len - 1] == '\\',
        'O' => return sequence.len >= 3,
        else => return true,
    }
}
const Extracted = struct {
    sequences: c.JSValue,
    remainder: c.JSValue,
    fn deinit(self: Extracted, engine: *js.Engine) void {
        engine.freeValue(self.sequences);
        engine.freeValue(self.remainder);
    }
};
fn extract(engine: *js.Engine, input: c.JSValue) !Extracted {
    const units = try utf16.unitsAlloc(engine, input);
    defer engine.gpa.free(units);
    const sequences = try js.array(engine);
    errdefer engine.freeValue(sequences);
    var position: usize = 0;
    while (position < units.len) {
        if (units[position] == 0x1b) {
            const remaining = units[position..];
            var end: usize = 1;
            while (end <= remaining.len) : (end += 1) {
                if (!complete(remaining[0..end])) continue;
                if (end == 2 and remaining[1] == 0x1b and end < remaining.len and std.mem.indexOfScalar(u16, &.{ '[', ']', 'O', 'P', '_' }, remaining[end]) != null) {
                    const sequence = try utf16.string(engine, &.{0x1b});
                    defer engine.freeValue(sequence);
                    try js.push(engine, sequences, sequence);
                    position += 1;
                    break;
                }
                const sequence = try utf16.string(engine, remaining[0..end]);
                defer engine.freeValue(sequence);
                try js.push(engine, sequences, sequence);
                position += end;
                break;
            }
            if (end > remaining.len) return .{ .sequences = sequences, .remainder = try utf16.string(engine, remaining) };
        } else {
            const sequence = try utf16.string(engine, units[position..][0..1]);
            defer engine.freeValue(sequence);
            try js.push(engine, sequences, sequence);
            position += 1;
        }
    }
    return .{ .sequences = sequences, .remainder = try v.text(engine, "") };
}
fn emitSequences(engine: *js.Engine, object: c.JSValue, sequences: c.JSValue, symbol: c.JSValue) !void {
    var iterator = try js.Iterator.init(engine, sequences, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |sequence| {
        defer engine.freeValue(sequence);
        try invokeVoid(engine, object, "emitDataSequence", &.{sequence});
    }
}
fn fieldSlice(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    return js.invoke(engine, value, "slice", args);
}
fn findPaste(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, delimiter: []const u8) !c.JSValue {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    const text = try v.text(engine, delimiter);
    defer engine.freeValue(text);
    return js.invoke(engine, value, "indexOf", &.{text});
}
fn finishPaste(engine: *js.Engine, object: c.JSValue, index: c.JSValue, data: [*c]c.JSValue) !void {
    const content = try fieldSlice(engine, object, "pasteBuffer", &.{ c.JS_NewInt32(engine.context, 0), index });
    defer engine.freeValue(content);
    const end = try arithmetic.add(engine, index, c.JS_NewInt32(engine.context, paste_end.len), data[2]);
    defer engine.freeValue(end);
    const remaining = try fieldSlice(engine, object, "pasteBuffer", &.{end});
    defer engine.freeValue(remaining);
    try v.set(engine, object, "pasteMode", c.pi_js_bool(engine.context, 0));
    try v.set(engine, object, "pasteBuffer", try v.text(engine, ""));
    try v.set(engine, object, "pendingKittyPrintableCodepoint", c.pi_js_undefined());
    const event = try v.text(engine, "paste");
    defer engine.freeValue(event);
    try invokeVoid(engine, object, "emit", &.{ event, content });
    if (try v.numberField(engine, remaining, "length") > 0) try invokeVoid(engine, object, "process", &.{remaining});
}
fn timerCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    timerOperation(engine, data[0], data[1]) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn timerOperation(engine: *js.Engine, object: c.JSValue, symbol: c.JSValue) !void {
    const flushed = try js.invoke(engine, object, "flush", &.{});
    defer engine.freeValue(flushed);
    try emitSequences(engine, object, flushed, symbol);
}
fn processInput(engine: *js.Engine, object: c.JSValue, input: c.JSValue, data: [*c]c.JSValue) !void {
    if (process_depth >= 64) {
        _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum call stack size exceeded"));
        unreachable;
    }
    process_depth += 1;
    defer process_depth -= 1;
    try clearTimer(engine, object);
    const buffer_constructor = try js.global(engine, "Buffer");
    defer engine.freeValue(buffer_constructor);
    const is_buffer = try js.invoke(engine, buffer_constructor, "isBuffer", &.{input});
    defer engine.freeValue(is_buffer);
    const text = if (v.truthy(engine, is_buffer)) blk: {
        const length = try js.get(engine, input, "length");
        defer engine.freeValue(length);
        var high = false;
        if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 1))) {
            const byte = try js.getKey(engine, input, c.JS_NewInt32(engine.context, 0));
            defer engine.freeValue(byte);
            high = try v.number(engine, byte) > 127;
        }
        if (high) {
            const byte = try js.getKey(engine, input, c.JS_NewInt32(engine.context, 0));
            defer engine.freeValue(byte);
            const character = try js.global(engine, "String");
            defer engine.freeValue(character);
            const result = try js.invoke(engine, character, "fromCharCode", &.{v.numeric(engine, try v.number(engine, byte) - 128)});
            defer engine.freeValue(result);
            const escape = try v.text(engine, "\x1b");
            defer engine.freeValue(escape);
            break :blk try v.concat(engine, &.{ escape, result });
        }
        break :blk try js.invoke(engine, input, "toString", &.{});
    } else c.JS_DupValue(engine.context, input);
    defer engine.freeValue(text);
    const length = try js.get(engine, text, "length");
    defer engine.freeValue(length);
    if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 0))) {
        const buffer = try js.get(engine, object, "buffer");
        defer engine.freeValue(buffer);
        const buffer_length = try js.get(engine, buffer, "length");
        defer engine.freeValue(buffer_length);
        if (c.JS_IsStrictEqual(engine.context, buffer_length, c.JS_NewInt32(engine.context, 0))) {
            const empty = try v.text(engine, "");
            defer engine.freeValue(empty);
            try invokeVoid(engine, object, "emitDataSequence", &.{empty});
            return;
        }
    }
    const old = try js.get(engine, object, "buffer");
    defer engine.freeValue(old);
    try v.set(engine, object, "buffer", try arithmetic.add(engine, old, text, data[2]));
    if (try truthyField(engine, object, "pasteMode")) {
        const paste = try js.get(engine, object, "pasteBuffer");
        defer engine.freeValue(paste);
        const buffer = try js.get(engine, object, "buffer");
        defer engine.freeValue(buffer);
        try v.set(engine, object, "pasteBuffer", try arithmetic.add(engine, paste, buffer, data[2]));
        try v.set(engine, object, "buffer", try v.text(engine, ""));
        const end = try findPaste(engine, object, "pasteBuffer", paste_end);
        defer engine.freeValue(end);
        if (!c.JS_IsStrictEqual(engine.context, end, c.JS_NewInt32(engine.context, -1))) try finishPaste(engine, object, end, data);
        return;
    }
    const start = try findPaste(engine, object, "buffer", paste_start);
    defer engine.freeValue(start);
    if (!c.JS_IsStrictEqual(engine.context, start, c.JS_NewInt32(engine.context, -1))) {
        if (try v.number(engine, start) > 0) {
            const before = try fieldSlice(engine, object, "buffer", &.{ c.JS_NewInt32(engine.context, 0), start });
            defer engine.freeValue(before);
            const parsed = try extract(engine, before);
            defer parsed.deinit(engine);
            try emitSequences(engine, object, parsed.sequences, data[1]);
        }
        try v.set(engine, object, "pendingKittyPrintableCodepoint", c.pi_js_undefined());
        const offset = try arithmetic.add(engine, start, c.JS_NewInt32(engine.context, paste_start.len), data[2]);
        defer engine.freeValue(offset);
        try v.set(engine, object, "buffer", try fieldSlice(engine, object, "buffer", &.{offset}));
        try v.set(engine, object, "pasteMode", c.pi_js_bool(engine.context, 1));
        try v.set(engine, object, "pasteBuffer", try js.get(engine, object, "buffer"));
        try v.set(engine, object, "buffer", try v.text(engine, ""));
        const end = try findPaste(engine, object, "pasteBuffer", paste_end);
        defer engine.freeValue(end);
        if (!c.JS_IsStrictEqual(engine.context, end, c.JS_NewInt32(engine.context, -1))) try finishPaste(engine, object, end, data);
        return;
    }
    const buffer = try js.get(engine, object, "buffer");
    defer engine.freeValue(buffer);
    const parsed = try extract(engine, buffer);
    defer parsed.deinit(engine);
    try v.set(engine, object, "buffer", c.JS_DupValue(engine.context, parsed.remainder));
    try emitSequences(engine, object, parsed.sequences, data[1]);
    const current = try js.get(engine, object, "buffer");
    defer engine.freeValue(current);
    if (try v.numberField(engine, current, "length") > 0) {
        const tested = try js.get(engine, object, "buffer");
        defer engine.freeValue(tested);
        const delay = try js.get(engine, object, if (try sameText(engine, tested, "\x1b")) "escapeTimeoutMs" else "timeoutMs");
        defer engine.freeValue(delay);
        const set_timeout = try js.global(engine, "setTimeout");
        defer engine.freeValue(set_timeout);
        var captured = [_]c.JSValue{ object, data[1] };
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, timerCall, "", 0, 0, captured.len, &captured));
        defer engine.freeValue(callback);
        try v.set(engine, object, "timeout", try js.call(engine, set_timeout, c.pi_js_undefined(), &.{ callback, delay }));
    }
}
fn emitData(engine: *js.Engine, object: c.JSValue, sequence: c.JSValue) !void {
    const length = try js.get(engine, sequence, "length");
    defer engine.freeValue(length);
    const raw = if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 1))) try js.invoke(engine, sequence, "codePointAt", &.{c.JS_NewInt32(engine.context, 0)}) else c.pi_js_undefined();
    defer engine.freeValue(raw);
    if (!c.JS_IsUndefined(raw)) {
        const pending = try js.get(engine, object, "pendingKittyPrintableCodepoint");
        defer engine.freeValue(pending);
        if (c.JS_IsStrictEqual(engine.context, raw, pending)) {
            try v.set(engine, object, "pendingKittyPrintableCodepoint", c.pi_js_undefined());
            return;
        }
    }
    const pattern = try v.text(engine, "^\\x1b\\[(\\d+)(?::\\d*)?(?::\\d+)?u$");
    defer engine.freeValue(pattern);
    var arguments = [_]c.JSValue{pattern};
    const regex = try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, arguments.len, &arguments));
    defer engine.freeValue(regex);
    const match = try js.invoke(engine, sequence, "match", &.{regex});
    defer engine.freeValue(match);
    var codepoint = c.pi_js_undefined();
    defer engine.freeValue(codepoint);
    if (v.truthy(engine, match)) {
        const parse = try js.global(engine, "parseInt");
        defer engine.freeValue(parse);
        const digits = try js.getKey(engine, match, c.JS_NewInt32(engine.context, 1));
        defer engine.freeValue(digits);
        const number = try js.call(engine, parse, c.pi_js_undefined(), &.{ digits, c.JS_NewInt32(engine.context, 10) });
        if (try v.number(engine, number) >= 32) codepoint = number else engine.freeValue(number);
    }
    try v.set(engine, object, "pendingKittyPrintableCodepoint", c.JS_DupValue(engine.context, codepoint));
    const name = try v.text(engine, "data");
    defer engine.freeValue(name);
    try invokeVoid(engine, object, "emit", &.{ name, sequence });
}
fn operation(engine: *js.Engine, object: c.JSValue, method: Method, args: []const c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    switch (method) {
        .process => try processInput(engine, object, v.arg(args, 0), data),
        .emitDataSequence => try emitData(engine, object, v.arg(args, 0)),
        .getBuffer => return js.get(engine, object, "buffer"),
        .destroy => try invokeVoid(engine, object, "clear", &.{}),
        .flush => {
            try clearTimer(engine, object);
            const buffer = try js.get(engine, object, "buffer");
            defer engine.freeValue(buffer);
            const length = try js.get(engine, buffer, "length");
            defer engine.freeValue(length);
            if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 0))) return js.array(engine);
            const result = try js.array(engine);
            errdefer engine.freeValue(result);
            const current = try js.get(engine, object, "buffer");
            if (c.JS_DefinePropertyValueUint32(engine.context, result, 0, current, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
            try v.set(engine, object, "buffer", try v.text(engine, ""));
            try v.set(engine, object, "pendingKittyPrintableCodepoint", c.pi_js_undefined());
            return result;
        },
        .clear => {
            try clearTimer(engine, object);
            try v.set(engine, object, "buffer", try v.text(engine, ""));
            try v.set(engine, object, "pasteMode", c.pi_js_bool(engine.context, 0));
            try v.set(engine, object, "pasteBuffer", try v.text(engine, ""));
            try v.set(engine, object, "pendingKittyPrintableCodepoint", c.pi_js_undefined());
        },
    }
    return c.pi_js_undefined();
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return operation(engine, object, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, data) catch |err| fail(engine, err);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const self = try js.get(engine, data[0], "constructor");
    defer engine.freeValue(self);
    const base = try engine.checked(c.JS_GetPrototype(engine.context, self));
    defer engine.freeValue(base);
    const object = try engine.checked(c.JS_CallConstructor2(engine.context, base, target, 0, null));
    errdefer engine.freeValue(object);
    try js.define(engine, object, "buffer", try v.text(engine, ""));
    try js.define(engine, object, "timeout", c.pi_js_null());
    try js.define(engine, object, "timeoutMs", c.pi_js_undefined());
    try js.define(engine, object, "escapeTimeoutMs", c.pi_js_undefined());
    try js.define(engine, object, "pasteMode", c.pi_js_bool(engine.context, 0));
    try js.define(engine, object, "pasteBuffer", try v.text(engine, ""));
    try js.define(engine, object, "pendingKittyPrintableCodepoint", c.pi_js_undefined());
    const supplied = v.arg(args, 0);
    const options = if (c.JS_IsUndefined(supplied)) try js.object(engine) else c.JS_DupValue(engine.context, supplied);
    defer engine.freeValue(options);
    inline for (.{ .{ "timeout", "timeoutMs", 50 }, .{ "escapeTimeout", "escapeTimeoutMs", 10 } }) |field| {
        const value = try js.get(engine, options, field[0]);
        defer engine.freeValue(value);
        try v.set(engine, object, field[1], if (c.JS_IsNull(value) or c.JS_IsUndefined(value)) c.JS_NewInt32(engine.context, field[2]) else c.JS_DupValue(engine.context, value));
    }
    return object;
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    try @import("node_events.zig").install(engine);
    try @import("node_buffer.zig").install(engine);
    const module = engine.native_module_values.get("node:events") orelse return error.NativeEventEmitterUnavailable;
    const emitter = try js.get(engine, module, "EventEmitter");
    defer engine.freeValue(emitter);
    const base = try js.get(engine, emitter, "prototype");
    defer engine.freeValue(base);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, base));
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const record = try js.object(engine);
    defer engine.freeValue(record);
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const iterator = try js.get(engine, symbol, "iterator");
    defer engine.freeValue(iterator);
    const primitive = try js.get(engine, symbol, "toPrimitive");
    defer engine.freeValue(primitive);
    var data = [_]c.JSValue{ record, iterator, primitive };
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, if (field.value <= @intFromEnum(Method.emitDataSequence)) 1 else 0, @intCast(field.value), data.len, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const constructor = try @import("native_class.zig").constructor(engine, "StdinBuffer", 0, prototype, construct, &.{record});
    defer engine.freeValue(constructor);
    if (c.JS_SetPrototype(engine.context, constructor, emitter) < 0) return js.capture(engine);
    try js.define(engine, record, "constructor", c.JS_DupValue(engine.context, constructor));
    try js.define(engine, exports, "StdinBuffer", c.JS_DupValue(engine.context, constructor));
}
