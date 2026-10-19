// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

//! Actual private header-check values from Node v24.13 lib/_http_common.js.
//! The complete common-module owner adopts this record at the corresponding
//! initialization point; this file does not publish a partial Node module.
const v = @import("native_public_values.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const Operation = @import("native_image_arithmetic.zig").Operation;

fn expression(engine: *Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, @call(.auto, body, .{&s} ++ args));
}
fn binary(s: *Scope, operation: Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return v.binary(s, @intFromEnum(operation), left, right);
}
fn literal(s: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    // This is the retained intrinsic constructor, never live global RegExp.
    return v.construct(s, s.engine.intrinsic_regexp_constructor, &.{try v.text(s, pattern), try v.text(s, flags)});
}
const token_chars = [_]u8{
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 0-15
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 16-31
  0, 1, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0, // 32-47 (!"#$%&'()*+,-./)
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, // 48-63 (0-9:;<=>?)
  0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 64-79 (@A-O)
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, // 80-95 (P-Z[\]^_)
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 96-111 (`a-o)
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, // 112-127 (p-z{|}~)
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 128-143
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 144-159
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 160-175
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 176-191
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 192-207
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 208-223
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 224-239
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // 240-255

};
fn table(s: *Scope) !c.JSValue {
    const values = try v.array(s);
    for (token_chars, 0..) |byte, index| try v.index(s, values, @intCast(index), v.number(s, @floatFromInt(byte)));
    const args = [_]c.JSValue{values};
    // The real constructor handles the actual iterable Array; its iterator
    // lookup/calls are guest operations, not a raw allocation-generation span.
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return v.duplicate(s, try boundary.finishValue(s,
        c.JS_NewTypedArray(s.engine.context, args.len, @constCast(&args), c.JS_TYPED_ARRAY_UINT8)));
}
pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    return expression(engine, createBody, .{});
}
fn createBody(s: *Scope) !c.JSValue {
    const token = try literal(s, "^[\\^_`a-zA-Z\\-0-9!#$%&'*+.|~]+$", "");
    const chars = try v.own(s, try expression(s.engine, table, .{}));
    const header = try literal(s, "[^\\t\\x20-\\x7e\\x80-\\xff]", "");
    const result = try v.object(s);
    try v.put(s, result, "_checkInvalidHeaderChar", try v.ordinary(s, "checkInvalidHeaderChar", 1, checkInvalidHeaderChar, &.{header}));
    try v.put(s, result, "_checkIsHttpToken", try v.ordinary(s, "checkIsHttpToken", 1, checkIsHttpToken, &.{token, chars}));
    try v.put(s, result, "chunkExpression", try literal(s, "(?:^|\\W)chunked(?:$|\\W)", "i"));
    try v.put(s, result, "continueExpression", try literal(s, "(?:^|\\W)100-continue(?:$|\\W)", "i"));
    try v.put(s, result, "CRLF", try v.text(s, "\r\n"));
    return v.duplicate(s, result);
}
fn testBody(s: *Scope, regexp: c.JSValue, input: c.JSValue) !c.JSValue {
    const method = try v.get(s, regexp, "test");
    return v.duplicate(s, try v.call(s, method, regexp, &.{input}));
}
fn checkInvalidHeaderChar(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, testBody, .{roots[0], v.arg(args, 0)});
}
fn lengthAtLeastTen(s: *Scope, input: c.JSValue) !c.JSValue {
    return v.duplicate(s, try binary(s, .greater_equal, try v.get(s, input, "length"), v.number(s, 10)));
}
fn lengthIsZero(s: *Scope, input: c.JSValue) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, input, "length"), v.number(s, 0)));
}
fn withinLength(s: *Scope, input: c.JSValue, index: f64) !c.JSValue {
    return v.duplicate(s, try binary(s, .less, v.number(s, index), try v.get(s, input, "length")));
}
fn charCode(s: *Scope, input: c.JSValue, index: f64) !c.JSValue {
    const method = try v.get(s, input, "charCodeAt");
    return v.duplicate(s, try v.call(s, method, input, &.{v.number(s, index)}));
}
fn charAtom(engine: *Engine, input: c.JSValue, index: f64) !c.JSAtom {
    var s: Scope = .{ .engine = engine };
    const atom = charAtomBody(&s, input, index) catch |err| {
        try v.owned.finishVoid(&s, @as(anyerror!void, err)); unreachable;
    };
    // Source GetPropertyValue consumes the computed key before the property
    // access. Keep only its converted atom through the actual typed lookup.
    errdefer c.JS_FreeAtom(engine.context, atom);
    try v.owned.finishVoid(&s, {});
    return atom;
}
fn charAtomBody(s: *Scope, input: c.JSValue, index: f64) !c.JSAtom {
    const code = try v.own(s, try expression(s.engine, charCode, .{input, index}));
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const atom = c.JS_ValueToAtom(s.engine.context, code);
    errdefer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try boundary.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
    return atom;
}
fn validChar(s: *Scope, input: c.JSValue, index: f64, chars: c.JSValue) !c.JSValue {
    const atom = try charAtom(s.engine, input, index); defer c.JS_FreeAtom(s.engine.context, atom);
    return v.boolean(s, v.truthy(s, try v.guest.getAtom(s, chars, atom)));
}
fn checkIsHttpToken(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, tokenBody, .{v.arg(args, 0), roots});
}
fn tokenBody(s: *Scope, input: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (v.truthy(s, try expression(s.engine, lengthAtLeastTen, .{input})))
        return expression(s.engine, testBody, .{roots[0], input});
    if (v.truthy(s, try expression(s.engine, lengthIsZero, .{input}))) return v.boolean(s, false);
    var index: f64 = 0;
    var steps: usize = 0;
    while (v.truthy(s, try expression(s.engine, withinLength, .{input, index}))) : (index += 1) {
        try v.poll(s.engine, &steps);
        if (!v.truthy(s, try expression(s.engine, validChar, .{input, index, roots[1]}))) return v.boolean(s, false);
    }
    return v.boolean(s, true);
}
