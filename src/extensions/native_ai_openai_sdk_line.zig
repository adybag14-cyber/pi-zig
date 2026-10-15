//! The pinned SDK LineDecoder byte algorithm. UTF8 functions are lazily
//! captured once by the shared module codec, just as in internal/utils/bytes.
const v = @import("native_ai_provider_values.zig");
const chunks = @import("native_ai_openai_sdk_chunks.zig");
const Scope = v.Scope;
const c = v.c;
pub fn create(scope: *Scope) !c.JSValue {
    const decoder = try @import("native_ai_openai_sdk_iterator.zig").state(scope);
    try scope.put(decoder, "buffer", try scope.own(try v.js.builtin(scope.engine, "Uint8Array", &.{})));
    try scope.put(decoder, "carriageReturnIndex", c.pi_js_null());
    return decoder;
}
const Newline = struct { preceding: u32, index: u32, carriage: bool };
fn find(scope: *Scope, buffer: c.JSValue, start: c.JSValue) !?Newline {
    var index: u32 = 0;
    if (!c.JS_IsNull(start) and c.JS_ToUint32(scope.engine.context, &index, start) < 0) return v.js.capture(scope.engine);
    while (true) : (index += 1) {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        if (index >= try v.length(&row, buffer)) break;
        const value = try v.at(&row, buffer, index);
        if (scope.equal(value, c.JS_NewInt32(scope.engine.context, 10))) return .{ .preceding = index, .index = index + 1, .carriage = false };
        if (scope.equal(value, c.JS_NewInt32(scope.engine.context, 13))) return .{ .preceding = index, .index = index + 1, .carriage = true };
    }
    return null;
}
pub fn decode(scope: *Scope, decoder: c.JSValue, codec: c.JSValue, chunk: c.JSValue) !c.JSValue {
    const lines = try scope.array();
    if (v.nullish(chunk)) return lines;
    try scope.put(decoder, "buffer", try chunks.concat(scope, try scope.get(decoder, "buffer"), try chunks.binary(scope, codec, chunk), true));
    while (true) {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const buffer = try row.get(decoder, "buffer");
        const carriage_value = try row.get(decoder, "carriageReturnIndex");
        const pattern = try find(&row, buffer, carriage_value) orelse break;
        if (pattern.carriage and c.JS_IsNull(carriage_value)) {
            try row.put(decoder, "carriageReturnIndex", c.JS_NewUint32(scope.engine.context, pattern.index));
            continue;
        }
        var carriage_index: u32 = 0;
        if (!c.JS_IsNull(carriage_value) and c.JS_ToUint32(scope.engine.context, &carriage_index, carriage_value) < 0) return v.js.capture(scope.engine);
        if (!c.JS_IsNull(carriage_value) and (pattern.index != carriage_index + 1 or pattern.carriage)) {
            const bytes = try row.invoke(buffer, "subarray", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewUint32(scope.engine.context, carriage_index - 1) });
            _ = try row.invoke(lines, "push", &.{try chunks.decode(&row, codec, bytes)});
            try row.put(decoder, "buffer", try row.invoke(buffer, "subarray", &.{c.JS_NewUint32(scope.engine.context, carriage_index)}));
            try row.put(decoder, "carriageReturnIndex", c.pi_js_null());
            continue;
        }
        const end = if (!c.JS_IsNull(carriage_value)) pattern.preceding - 1 else pattern.preceding;
        const bytes = try row.invoke(buffer, "subarray", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewUint32(scope.engine.context, end) });
        _ = try row.invoke(lines, "push", &.{try chunks.decode(&row, codec, bytes)});
        try row.put(decoder, "buffer", try row.invoke(buffer, "subarray", &.{c.JS_NewUint32(scope.engine.context, pattern.index)}));
        try row.put(decoder, "carriageReturnIndex", c.pi_js_null());
    }
    return lines;
}
pub fn flush(scope: *Scope, decoder: c.JSValue, codec: c.JSValue) !c.JSValue {
    if (try v.length(scope, try scope.get(decoder, "buffer")) == 0) return scope.array();
    return decode(scope, decoder, codec, try scope.text("\n"));
}
pub fn sse(scope: *Scope, state: c.JSValue, original: c.JSValue) !c.JSValue {
    var line = original;
    if (scope.truthy(try scope.invoke(line, "endsWith", &.{try scope.text("\r")}))) {
        const length = try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .subtract, try scope.get(line, "length"), c.JS_NewInt32(scope.engine.context, 1)));
        line = try scope.invoke(line, "substring", &.{ c.JS_NewInt32(scope.engine.context, 0), length });
    }
    if (!scope.truthy(line)) {
        if (!scope.truthy(try scope.get(state, "event")) and !scope.truthy(try scope.get(try scope.get(state, "data"), "length"))) return c.pi_js_null();
        const result = try scope.object();
        try scope.put(result, "event", try scope.get(state, "event"));
        try scope.put(result, "data", try scope.invoke(try scope.get(state, "data"), "join", &.{try scope.text("\n")}));
        try scope.put(result, "raw", try scope.get(state, "chunks"));
        try scope.set(state, "event", c.pi_js_null());
        try scope.set(state, "data", try scope.array());
        try scope.set(state, "chunks", try scope.array());
        return result;
    }
    _ = try scope.invoke(try scope.get(state, "chunks"), "push", &.{line});
    if (scope.truthy(try scope.invoke(line, "startsWith", &.{try scope.text(":")}))) return c.pi_js_null();
    const index = try scope.invoke(line, "indexOf", &.{try scope.text(":")});
    var field = line;
    var value = try scope.text("");
    if (!scope.equal(index, c.JS_NewInt32(scope.engine.context, -1))) {
        field = try scope.invoke(line, "substring", &.{ c.JS_NewInt32(scope.engine.context, 0), index });
        const offset = try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .add, index, c.JS_NewInt32(scope.engine.context, 1)));
        value = try scope.invoke(line, "substring", &.{offset});
    }
    if (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text(" ")}))) value = try scope.invoke(value, "substring", &.{c.JS_NewInt32(scope.engine.context, 1)});
    if (try v.eq(scope, field, "event")) try scope.set(state, "event", value) else if (try v.eq(scope, field, "data")) _ = try scope.invoke(try scope.get(state, "data"), "push", &.{value});
    return c.pi_js_null();
}
