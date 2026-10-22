//! Real VM Latin-1 controls. Native fatal policy is bound to original source;
//! no native-fatal subprocess or compiler execution is implied by this file.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const latin1 = @import("extensions/native_node_one_byte_string.zig");
const Engine = a.v.em.Engine;

fn create(engine: *Engine, bytes: [*c]const u8, length: c_int) !c.JSValue {
    return a.expression(engine, struct {
        fn body(s: *a.Scope, data: [*c]const u8, count: c_int) !c.JSValue {
            return a.duplicate(s.engine, try latin1.fromOneByte(s, data, count, null));
        }
    }.body, .{bytes, length});
}
fn expect(engine: *Engine, value: c.JSValue, expression: []const u8) !void {
    const ignored = try a.expression(engine, struct {
        fn body(s: *a.Scope, actual: c.JSValue) !c.JSValue {
            const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
            try s.put(global, "actualLatin1", actual);
            return c.pi_js_undefined();
        }
    }.body, .{value});
    engine.freeValue(ignored);
    const result = try engine.eval(expression, "native-latin1-control.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsBool(result));
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, result));
}

test "native OneByteString explicit full byte range preserves all Latin1 code units including high bytes" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var bytes: [256]u8 = undefined;
    for (&bytes, 0..) |*byte, i| byte.* = @intCast(i);
    const value = try create(engine, &bytes, bytes.len); defer engine.freeValue(value);
    try expect(engine, value, "actualLatin1.length===256 && Array.from({length:256},(_,i)=>actualLatin1.charCodeAt(i)===i).every(Boolean)");
}

test "native OneByteString UTF8-looking bytes remain two original Latin1 code units" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const bytes = [_]u8{ 0xc3, 0xa9 };
    const value = try create(engine, &bytes, bytes.len); defer engine.freeValue(value);
    try expect(engine, value, "actualLatin1.length===2 && actualLatin1.charCodeAt(0)===195 && actualLatin1.charCodeAt(1)===169");
}

test "native OneByteString explicit length preserves embedded NUL before nonASCII bytes" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const bytes = [_]u8{ 'A', 0, 0xff, 'B' };
    const value = try create(engine, &bytes, bytes.len); defer engine.freeValue(value);
    try expect(engine, value, "actualLatin1.length===4 && actualLatin1.charCodeAt(1)===0 && actualLatin1.charCodeAt(2)===255 && actualLatin1[3]==='B'");
}

test "native OneByteString negative length follows original strlen termination" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const bytes = [_:0]u8{ 0x80, 0, 0xff };
    const value = try create(engine, &bytes, -1); defer engine.freeValue(value);
    try expect(engine, value, "actualLatin1.length===1 && actualLatin1.charCodeAt(0)===128");
}

test "native OneByteString zero length accepts null data without reading a byte" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const value = try create(engine, null, 0); defer engine.freeValue(value);
    try expect(engine, value, "actualLatin1==='' && actualLatin1.length===0");
}

test "native OneByteString all negative signed lengths select the CString branch" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const bytes = [_:0]u8{ 0xfe, 0xff };
    const first = try create(engine, &bytes, -1); defer engine.freeValue(first);
    const second = try create(engine, &bytes, -2); defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    try expect(engine, second, "actualLatin1.length===2 && actualLatin1.charCodeAt(0)===254 && actualLatin1.charCodeAt(1)===255");
}

test "native OneByteString explicit prefix does not consume trailing buffer bytes" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const bytes = [_]u8{ 0xff, 'a', 0x80, 'b' };
    const value = try create(engine, &bytes, 2); defer engine.freeValue(value);
    try expect(engine, value, "actualLatin1.length===2 && actualLatin1.charCodeAt(0)===255 && actualLatin1[1]==='a'");
}

test "native OneByteString returned caller ownership survives source scope and real VM collection" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const bytes = [_]u8{ 0x80, 0, 0xff };
    const value = try create(engine, &bytes, bytes.len); defer engine.freeValue(value);
    c.JS_RunGC(engine.runtime);
    try expect(engine, value, "actualLatin1.length===3 && actualLatin1.charCodeAt(0)===128 && actualLatin1.charCodeAt(1)===0 && actualLatin1.charCodeAt(2)===255");
}
