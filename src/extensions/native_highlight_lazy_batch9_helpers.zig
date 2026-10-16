//! Private operations needed by exact batch9 factory bodies.
const b = @import("native_highlight_lazy_batch3_values.zig");
const js = @import("native_js_values.zig");
const std = @import("std");
extern "c" fn JS_GetIteratorSymbol(context: ?*b.c.JSContext) b.c.JSValue;
pub fn rxFlags(s: *b.Scope, pattern: []const u8, flags: []const u8) !b.c.JSValue {
    var args = [_]b.c.JSValue{ try s.text(pattern), try s.text(flags) };
    return s.own(try s.engine.checked(b.c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
pub fn spread(s: *b.Scope, array: b.c.JSValue, index: *u32, iterable: b.c.JSValue) !void {
    const symbol = try s.own(try s.engine.checked(JS_GetIteratorSymbol(s.engine.context)));
    var iterator = try js.Iterator.init(s.engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        defer s.engine.freeValue(value);
        try s.index(array, index.*, value);
        index.* += 1;
    }
}
pub fn callSpread(s: *b.Scope, function: b.c.JSValue, receiver: b.c.JSValue, array: b.c.JSValue) !b.c.JSValue {
    // The caller has already consumed every spread iterator into its fresh
    // argument-list array. Reading that private list must not invoke another
    // user-observable Symbol.iterator.
    const length_value = try s.get(array, "length");
    var length: u32 = 0;
    if (b.c.JS_ToUint32(s.engine.context, &length, length_value) < 0) return js.capture(s.engine);
    var values: std.ArrayList(b.c.JSValue) = .empty;
    defer {
        for (values.items) |value| s.engine.freeValue(value);
        values.deinit(s.engine.gpa);
    }
    var index: u32 = 0;
    while (index < length) : (index += 1) {
        const value = try s.engine.checked(b.c.JS_GetPropertyUint32(s.engine.context, array, index));
        values.append(s.engine.gpa, value) catch |err| {
            s.engine.freeValue(value);
            return err;
        };
    }
    return s.call(function, receiver, values.items);
}
