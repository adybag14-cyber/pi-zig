//! Private native factory for the relocated actual Chord output module.
//! OutputSkip is a Source interface and intentionally has no runtime export.
const std = @import("std");
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const buffer = @import("native_durable_output_buffer.zig");
const progress = @import("native_durable_progress.zig");
const window = @import("native_durable_output_limits.zig");
const Method = enum(c_int) { push, end, snapshot, storedBytes, mark, markAndWait, stop };
const Function = enum { sanitizeOutput, boundOutput, characterEnd, utf8ByteLength };
fn number(s: *h.Scope, value: c.JSValue) !f64 {
    var result: f64 = 0;
    if (c.JS_ToFloat64(s.engine.context, &result, value) < 0) return js.capture(s.engine);
    return result;
}
fn limits(s: *h.Scope, value: c.JSValue) !window.Limits {
    const retain = try s.get(value, "retain");
    return .{ .maxBytes = try number(s, try s.get(value, "maxBytes")), .maxLines = try number(s, try s.get(value, "maxLines")), .retain = if (c.JS_IsStrictEqual(s.engine.context, retain, try s.text("head"))) .head else if (c.JS_IsStrictEqual(s.engine.context, retain, try s.text("tail"))) .tail else .other };
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = captures[0];
    const result = try s.keep(try @import("native_class.zig").object(engine, target));
    const owned = try s.record();
    const is_buffer = c.JS_ToBool(engine.context, captures[1]) != 0;
    if (is_buffer) {
        const state = try s.keep(try buffer.create(engine, .{}, try s.get(bindings, "sanitizePattern")));
        // Source stores the limits object by reference and first reads it when
        // output needs retention. Preserve construction and later mutations.
        try h.field(&s, state, "sourceLimits", h.arg(args, 0));
        try h.field(&s, state, "sourceLimitsEnabled", c.pi_js_bool(engine.context, 1));
        try h.field(&s, owned, "state", state);
    } else {
        var intrinsics = try @import("native_durable_await.zig").Intrinsics.init(engine);
        defer intrinsics.deinit(engine);
        try js.define(engine, owned, "state", try progress.create(engine, &intrinsics, h.arg(args, 0), h.arg(args, 1), h.arg(args, 2)));
    }
    _ = try h.invoke(&s, try s.get(bindings, if (is_buffer) "buffers" else "progresses"), "set", &.{ result, owned });
    return s.result(result);
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(operation);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, method, captures[0]) catch |err| if (method == .stop) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) !c.JSValue {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const is_buffer = switch (method) {
        .push, .end, .snapshot, .storedBytes => true,
        else => false,
    };
    const owned = try h.invoke(&s, try s.get(bindings, if (is_buffer) "buffers" else "progresses"), "get", &.{receiver});
    if (c.JS_IsUndefined(owned)) {
        _ = c.JS_ThrowTypeError(engine.context, "Invalid Chord output receiver");
        return js.capture(engine);
    }
    const state = try s.get(owned, "state");
    if (method == .storedBytes) return js.get(engine, state, "storedBytes");
    return js.invoke(engine, state, @tagName(method), args);
}
fn function(comptime operation: Function) @import("native_node_function.zig").Callback {
    return struct {
        fn call(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
            var s: h.Scope = .{ .engine = engine };
            defer s.deinit();
            const bindings = captures[0];
            const text = h.arg(args, 0);
            switch (operation) {
                .sanitizeOutput => return js.invoke(engine, text, "replace", &.{ try s.get(bindings, "sanitizePattern"), try s.text("") }),
                .utf8ByteLength => {
                    const runtime_buffer = try s.get(bindings, "runtimeBuffer");
                    if (c.JS_ToBool(engine.context, runtime_buffer) != 0) return js.invoke(engine, runtime_buffer, "byteLength", &.{ text, try s.text("utf8") });
                    const first = try h.invoke(&s, text, "search", &.{try s.get(bindings, "nonAsciiPattern")});
                    if (c.JS_IsStrictEqual(engine.context, first, c.JS_NewInt32(engine.context, -1))) return js.get(engine, text, "length");
                    var bytes = try number(&s, first);
                    var index = bytes;
                    while (index < try number(&s, try s.get(text, "length"))) : (index += 1) {
                        const unit = try number(&s, try h.invoke(&s, text, "charCodeAt", &.{c.JS_NewFloat64(engine.context, index)}));
                        if (unit <= 0x7f) bytes += 1 else if (unit <= 0x7ff) bytes += 2 else if (unit >= 0xd800 and unit <= 0xdbff and index + 1 < try number(&s, try s.get(text, "length"))) {
                            const next = try number(&s, try h.invoke(&s, text, "charCodeAt", &.{c.JS_NewFloat64(engine.context, index + 1)}));
                            if (next >= 0xdc00 and next <= 0xdfff) {
                                bytes += 4;
                                index += 1;
                            } else bytes += 3;
                        } else bytes += 3;
                    }
                    return c.JS_NewFloat64(engine.context, bytes);
                },
                .boundOutput => {
                    const encoded = try engine.toString(text);
                    defer engine.gpa.free(encoded);
                    try std.unicode.wtf8ToUtf8Lossy(encoded, encoded);
                    const kept = try window.boundOutput(engine.gpa, encoded, try limits(&s, h.arg(args, 1)));
                    defer engine.gpa.free(kept.text);
                    const result = try s.record();
                    try h.field(&s, result, "text", if (kept.droppedBytes == 0) text else try s.keep(try engine.checked(c.JS_NewStringLen(engine.context, kept.text.ptr, kept.text.len))));
                    inline for (.{ .{ "bytes", kept.bytes }, .{ "droppedBytes", kept.droppedBytes }, .{ "droppedLines", kept.droppedLines } }) |field| try h.field(&s, result, field[0], c.JS_NewFloat64(engine.context, @floatFromInt(field[1])));
                    return s.result(result);
                },
                .characterEnd => {
                    var end = try number(&s, h.arg(args, 1));
                    while (end > 0) {
                        const atom = try propertyAtom(engine, end);
                        defer c.JS_FreeAtom(engine.context, atom);
                        const byte = try s.keep(try engine.checked(c.JS_GetProperty(engine.context, text, atom)));
                        var integer: i32 = 0;
                        if (c.JS_ToInt32(engine.context, &integer, byte) < 0) return js.capture(engine);
                        if (integer & 0xc0 != 0x80) break;
                        end -= 1;
                    }
                    return c.JS_NewFloat64(engine.context, end);
                },
            }
        }
    }.call;
}
fn propertyAtom(engine: *h.Engine, index: f64) !c.JSAtom {
    const key = c.JS_NewFloat64(engine.context, index);
    const atom = c.JS_ValueToAtom(engine.context, key);
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    return atom;
}
pub fn exports(engine: *h.Engine) !c.JSValue {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = try s.record();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try h.field(&s, bindings, "runtimeBuffer", try s.get(global, "Buffer"));
    try h.field(&s, bindings, "nonAsciiPattern", try s.keep(try js.builtin(engine, "RegExp", &.{try s.text("[^\\x00-\\x7f]")})));
    try h.field(&s, bindings, "sanitizePattern", try s.keep(try js.builtin(engine, "RegExp", &.{ try s.text("[\\x00-\\x08\\x0b-\\x1f\\ufff9-\\ufffb]"), try s.text("g") })));
    inline for (.{ "buffers", "progresses" }) |name| try h.field(&s, bindings, name, try s.keep(try js.builtin(engine, "WeakMap", &.{})));
    const api = try s.record();
    inline for (.{ .{ "OutputBuffer", true, 1 }, .{ "Progress", false, 3 } }) |class| {
        const prototype = try s.record();
        try js.define(engine, api, class[0], try @import("native_class.zig").constructor(engine, class[0], class[2], prototype, construct, &.{ bindings, c.pi_js_bool(engine.context, @intFromBool(class[1])) }));
        if (class[1]) {
            inline for (.{ .{ "push", Method.push, 1, false }, .{ "end", Method.end, 0, false }, .{ "snapshot", Method.snapshot, 0, false }, .{ "storedBytes", Method.storedBytes, 0, true } }) |method| try h.define(&s, prototype, bindings, method[0], callback, @intFromEnum(method[1]), method[2], method[3], false);
        } else {
            inline for (.{ .{ "mark", Method.mark, 0 }, .{ "markAndWait", Method.markAndWait, 0 }, .{ "stop", Method.stop, 0 } }) |method| try h.define(&s, prototype, bindings, method[0], callback, @intFromEnum(method[1]), method[2], false, method[1] == .stop);
        }
    }
    inline for (.{ .{ "sanitizeOutput", Function.sanitizeOutput, 1 }, .{ "boundOutput", Function.boundOutput, 2 }, .{ "characterEnd", Function.characterEnd, 2 }, .{ "utf8ByteLength", Function.utf8ByteLength, 1 } }) |entry| try js.define(engine, api, entry[0], try @import("native_node_function.zig").create(engine, entry[0], entry[2], function(entry[1]), &.{bindings}));
    try h.field(&s, api, "PROGRESS_BYTES_PER_SECOND", c.JS_NewInt32(engine.context, 100 * 1024));
    return s.result(api);
}
