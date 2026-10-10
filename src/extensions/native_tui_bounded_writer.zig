//! Source private BoundedTerminalWriter for regular-screen render writes.
//! The private buffer is a rooted JS string; slicing preserves UTF16 boundaries.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub const Writer = struct {
    engine: *js.Engine,
    screen: c.JSValue,
    bindings: c.JSValue,
    buffer: c.JSValue,
    written_chars: f64 = 0,
    pub fn init(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue) !Writer {
        const buffer = try v.text(engine, "");
        return .{ .engine = engine, .screen = c.JS_DupValue(engine.context, screen), .bindings = c.JS_DupValue(engine.context, bindings), .buffer = buffer };
    }
    pub fn deinit(self: *Writer) void {
        self.engine.freeValue(self.buffer);
        self.engine.freeValue(self.bindings);
        self.engine.freeValue(self.screen);
    }
    pub fn length(self: *Writer) !f64 {
        return self.written_chars + try v.numberField(self.engine, self.buffer, "length");
    }
    pub fn flush(self: *Writer) !void {
        const engine = self.engine;
        if (!v.truthy(engine, self.buffer)) return;
        const terminal = try js.get(engine, self.screen, "terminal");
        defer engine.freeValue(terminal);
        try v.invokeVoid(engine, terminal, "write", &.{self.buffer});
        self.written_chars += try v.numberField(engine, self.buffer, "length");
        const empty = try v.text(engine, "");
        engine.freeValue(self.buffer);
        self.buffer = empty;
    }
    fn code(self: *Writer, value: c.JSValue, index: f64) !f64 {
        const result = try js.invoke(self.engine, value, "charCodeAt", &.{v.numeric(self.engine, index)});
        defer self.engine.freeValue(result);
        return v.number(self.engine, result);
    }
    pub fn append(self: *Writer, value: c.JSValue) !void {
        const engine = self.engine;
        var offset: f64 = 0;
        while (offset < try v.numberField(engine, value, "length")) {
            const capacity = 1048576 - try v.numberField(engine, self.buffer, "length");
            if (capacity == 0) {
                try self.flush();
                continue;
            }
            const math = try js.global(engine, "Math");
            defer engine.freeValue(math);
            const minimum = try js.get(engine, math, "min");
            defer engine.freeValue(minimum);
            const value_length = try js.get(engine, value, "length");
            defer engine.freeValue(value_length);
            const chosen = try js.call(engine, minimum, math, &.{ value_length, v.numeric(engine, offset + capacity) });
            defer engine.freeValue(chosen);
            var end = try v.number(engine, chosen);
            if (end < try v.numberField(engine, value, "length") and try self.code(value, end - 1) >= 0xd800 and try self.code(value, end - 1) <= 0xdbff and try self.code(value, end) >= 0xdc00 and try self.code(value, end) <= 0xdfff) end -= 1;
            if (end == offset) {
                try self.flush();
                continue;
            }
            const piece = try js.invoke(engine, value, "slice", &.{ v.numeric(engine, offset), v.numeric(engine, end) });
            defer engine.freeValue(piece);
            const symbol = try js.get(engine, self.bindings, "primitiveSymbol");
            defer engine.freeValue(symbol);
            const next = try @import("native_tui_value_arithmetic.zig").add(engine, self.buffer, piece, symbol);
            engine.freeValue(self.buffer);
            self.buffer = next;
            offset = end;
            const buffer_length = try js.get(engine, self.buffer, "length");
            defer engine.freeValue(buffer_length);
            if (c.JS_IsStrictEqual(engine.context, buffer_length, c.JS_NewInt32(engine.context, 1048576))) try self.flush();
        }
    }
    pub fn text(self: *Writer, bytes: []const u8) !void {
        const value = try v.text(self.engine, bytes);
        defer self.engine.freeValue(value);
        try self.append(value);
    }
    pub fn sequence(self: *Writer, count: f64, suffix: []const u8) !void {
        const begin = try v.text(self.engine, "\x1b[");
        defer self.engine.freeValue(begin);
        const end = try v.text(self.engine, suffix);
        defer self.engine.freeValue(end);
        const value = try v.concat(self.engine, &.{ begin, v.numeric(self.engine, count), end });
        defer self.engine.freeValue(value);
        try self.append(value);
    }
};
