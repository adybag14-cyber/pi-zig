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


//! Actual Node v24.13.0 lib/_http_incoming.js owner. The complete incoming
//! message class consumes the original Readable/finished imports; TCP and HTTP
//! parser publication is owned separately by the physical server graph.
const std = @import("std");
const v = @import("native_public_values.zig");
const Operation = @import("native_image_arithmetic.zig").Operation;
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const frames = @import("native_public_lexical_frame.zig");
const cache_key = "\x00node.http.incoming";
const Key = enum(usize) { readable, finished, headers, headers_distinct, headers_count, trailers, trailers_distinct, trailers_count };
const HeaderFrame = frames.Frame(enum { source, destination, index });
const LineFrame = frames.Frame(enum { field, flag });
const DestroyFrame = frames.Frame(enum { cleanup });
pub const Inputs = struct { streams: c.JSValue };

fn binary(s: *Scope, operation: Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return v.binary(s, @intFromEnum(operation), left, right);
}

fn expression(engine: *Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, @call(.auto, body, .{&s} ++ args));
}
fn statement(engine: *Engine, comptime body: anytype, args: anytype) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, @call(.auto, body, .{&s} ++ args));
}
fn value(s: *Scope, comptime body: anytype, args: anytype) !c.JSValue {
    return v.own(s, try expression(s.engine, body, args));
}
fn truth(s: *Scope, comptime body: anytype, args: anytype) !bool {
    return v.truthy(s, try expression(s.engine, body, args));
}
fn field(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.get(s, receiver, name));
}
fn fieldTruth(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.get(s, receiver, name)));
}
fn keyTruth(s: *Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.key(s, receiver, key)));
}
fn invoke(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const callable = try v.get(s, receiver, name);
    return v.duplicate(s, try v.call(s, callable, receiver, args));
}
fn invokeVoid(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    _ = try v.call(s, try v.get(s, receiver, name), receiver, args);
}
fn invokeText(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, text: []const u8) !void {
    const callable = try v.get(s, receiver, name);
    _ = try v.call(s, callable, receiver, &.{try v.text(s, text)});
}
fn setField(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, input: c.JSValue) !void {
    try v.set(s, receiver, name, input);
}
fn setNested(s: *Scope, receiver: c.JSValue, first: [*:0]const u8, second: [*:0]const u8, input: c.JSValue) !void {
    try v.set(s, try v.get(s, receiver, first), second, input);
}
fn symbol(roots: []const c.JSValue, key: Key) c.JSValue { return roots[@intFromEnum(key)]; }
fn selectedRoots(roots: []const c.JSValue, comptime keys: anytype) [@typeInfo(Key).@"enum".fields.len]c.JSValue {
    var selected: [@typeInfo(Key).@"enum".fields.len]c.JSValue = @splat(c.pi_js_undefined());
    inline for (keys) |key| selected[@intFromEnum(key)] = symbol(roots, key);
    return selected;
}

/// A Source property reference owns its already converted key across the RHS.
/// Repeated Source references create repeated keys; compound assignment gets and
/// sets through the same reference, without an extra ToPropertyKey operation.
const Property = struct {
    engine: *Engine, receiver: c.JSValue, atom: c.JSAtom,
    fn init(s: *Scope, receiver: c.JSValue, key: c.JSValue) !Property {
        var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
        const atom = c.JS_ValueToAtom(s.engine.context, key);
        errdefer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
        try boundary.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
        return .{ .engine = s.engine, .receiver = receiver, .atom = atom };
    }
    fn deinit(self: Property) void { c.JS_FreeAtom(self.engine.context, self.atom); }
    fn get(self: Property, s: *Scope) !c.JSValue {
        return v.guest.getAtom(s, self.receiver, self.atom);
    }
    fn set(self: Property, s: *Scope, incoming: c.JSValue) !void {
        var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
        try boundary.finishStatus(c.JS_SetProperty(s.engine.context, self.receiver,
            self.atom, v.duplicate(s, incoming)));
    }
};
fn assignKey(s: *Scope, receiver: c.JSValue, key: c.JSValue, incoming: c.JSValue) !void {
    const reference = try Property.init(s, receiver, key); defer reference.deinit();
    try reference.set(s, incoming);
}
fn assignObject(s: *Scope, receiver: c.JSValue, key: c.JSValue) !void {
    const reference = try Property.init(s, receiver, key); defer reference.deinit();
    try reference.set(s, try v.object(s));
}
fn keyField(s: *Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.key(s, receiver, key));
}
fn stringKeyTest(s: *Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    return v.boolean(s, c.JS_IsString(try v.key(s, receiver, key)));
}
fn undefinedKeyTest(s: *Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    return v.boolean(s, c.JS_IsUndefined(try v.key(s, receiver, key)));
}
fn singleArray(s: *Scope, input: c.JSValue) !c.JSValue {
    const result = try v.array(s); try v.index(s, result, 0, input);
    return v.duplicate(s, result);
}
fn assignArray(s: *Scope, destination: c.JSValue, key: c.JSValue, input: c.JSValue) !void {
    const reference = try Property.init(s, destination, key); defer reference.deinit();
    const result = try value(s, singleArray, .{input});
    try reference.set(s, result);
}
fn compoundValue(s: *Scope, reference: Property, separator: []const u8, incoming: c.JSValue) !c.JSValue {
    const old = try reference.get(s);
    const suffix = try binary(s, .add, try v.text(s, separator), incoming);
    return v.duplicate(s, try binary(s, .add, old, suffix));
}
fn compound(s: *Scope, destination: c.JSValue, key: c.JSValue, separator: []const u8, incoming: c.JSValue) !void {
    const reference = try Property.init(s, destination, key); defer reference.deinit();
    // Both binary producers consume their operands before Source PutValue.
    // The converted reference itself still spans the complete compound RHS.
    const result = try value(s, compoundValue, .{reference, separator, incoming});
    try reference.set(s, result);
}
fn pushKey(s: *Scope, destination: c.JSValue, key: c.JSValue, incoming: c.JSValue) !void {
    const list = try v.key(s, destination, key);
    const push = try v.get(s, list, "push");
    _ = try v.call(s, push, list, &.{incoming});
}
fn appendHeader(s: *Scope, receiver: c.JSValue, destination: c.JSValue, name: [*:0]const u8, source: c.JSValue, index: c.JSValue) !void {
    const callable = try v.get(s, receiver, name);
    const first_index = try binary(s, .add, index, v.number(s, 0));
    const first = try v.key(s, source, first_index);
    const second_index = try binary(s, .add, index, v.number(s, 1));
    const second = try v.key(s, source, second_index);
    _ = try v.call(s, callable, receiver, &.{first, second, destination});
}
fn countCondition(s: *Scope, receiver: c.JSValue, count_key: c.JSValue, index: c.JSValue) !c.JSValue {
    const count = try v.key(s, receiver, count_key);
    return v.duplicate(s, try binary(s, .less, index, count));
}
fn numericCondition(s: *Scope, index: c.JSValue, count: c.JSValue) !c.JSValue {
    return v.duplicate(s, try binary(s, .less, index, count));
}
fn increment(s: *Scope, index: c.JSValue) !c.JSValue {
    return v.duplicate(s, try binary(s, .add, index, v.number(s, 2)));
}

fn readStartBody(s: *Scope, socket: c.JSValue) !void {
    if (v.truthy(s, socket) and !try truth(s, fieldTruth, .{socket, @as([*:0]const u8, "_paused")}) and
        try truth(s, fieldTruth, .{socket, @as([*:0]const u8, "readable")}))
        try statement(s.engine, invokeVoid, .{socket, @as([*:0]const u8, "resume"), @as([]const c.JSValue, &.{})});
}
fn readStart(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    try statement(engine, readStartBody, .{v.arg(args, 0)}); return c.pi_js_undefined();
}
fn readStop(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const socket = v.arg(args, 0);
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, stopBody(&s, socket));
}
fn stopBody(s: *Scope, socket: c.JSValue) !c.JSValue {
    if (v.truthy(s, socket)) try statement(s.engine, invokeVoid,
        .{socket, @as([*:0]const u8, "pause"), @as([]const c.JSValue, &.{})});
    return c.pi_js_undefined();
}
fn streamOptions(s: *Scope, socket: c.JSValue) !c.JSValue {
    if (!v.truthy(s, socket)) return c.pi_js_undefined();
    const result = try v.object(s);
    try v.put(s, result, "highWaterMark", try v.get(s, socket, "readableHighWaterMark"));
    return v.duplicate(s, result);
}
fn callReadable(s: *Scope, readable: c.JSValue, receiver: c.JSValue, options: c.JSValue) !void {
    // Source uses Readable.call, so this method lookup remains live.
    const callable = try v.get(s, readable, "call");
    _ = try v.call(s, callable, readable, &.{receiver, options});
}
fn constructBody(s: *Scope, receiver: c.JSValue, socket: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const options = try value(s, streamOptions, .{socket});
    try statement(s.engine, callReadable, .{symbol(roots, .readable), receiver, options});
    try statement(s.engine, setNested, .{receiver, @as([*:0]const u8, "_readableState"), @as([*:0]const u8, "readingMore"), v.boolean(s, true)});
    try statement(s.engine, setField, .{receiver, @as([*:0]const u8, "socket"), socket});
    inline for (.{ "httpVersionMajor", "httpVersionMinor", "httpVersion" }) |name|
        try statement(s.engine, setField, .{receiver, @as([*:0]const u8, name), c.pi_js_null()});
    try statement(s.engine, setField, .{receiver, @as([*:0]const u8, "complete"), v.boolean(s, false)});
    try statement(s.engine, assignKey, .{receiver, symbol(roots, .headers), c.pi_js_null()});
    try statement(s.engine, assignKey, .{receiver, symbol(roots, .headers_count), v.number(s, 0)});
    try statement(s.engine, setNewArray, .{receiver, @as([*:0]const u8, "rawHeaders")});
    try statement(s.engine, assignKey, .{receiver, symbol(roots, .trailers), c.pi_js_null()});
    try statement(s.engine, assignKey, .{receiver, symbol(roots, .trailers_count), v.number(s, 0)});
    try statement(s.engine, setNewArray, .{receiver, @as([*:0]const u8, "rawTrailers")});
    inline for (.{ "joinDuplicateHeaders", "aborted" }) |name|
        try statement(s.engine, setField, .{receiver, @as([*:0]const u8, name), v.boolean(s, false)});
    try statement(s.engine, setField, .{receiver, @as([*:0]const u8, "upgrade"), c.pi_js_null()});
    try statement(s.engine, setEmptyUrl, .{receiver});
    inline for (.{ "method", "statusCode", "statusMessage" }) |name|
        try statement(s.engine, setField, .{receiver, @as([*:0]const u8, name), c.pi_js_null()});
    try statement(s.engine, setField, .{receiver, @as([*:0]const u8, "client"), socket});
    inline for (.{ "_consuming", "_dumped" }) |name|
        try statement(s.engine, setField, .{receiver, @as([*:0]const u8, name), v.boolean(s, false)});
    return c.pi_js_undefined();
}
fn setNewArray(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !void { try v.set(s, receiver, name, try v.array(s)); }
fn setEmptyUrl(s: *Scope, receiver: c.JSValue) !void { try v.set(s, receiver, "url", try v.text(s, "")); }
fn construct(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, constructBody, .{receiver, v.arg(args, 0), roots});
}
fn connectionGet(engine: *Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, field, .{receiver, @as([*:0]const u8, "socket")});
}
fn connectionSet(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    try statement(engine, setField, .{receiver, @as([*:0]const u8, "socket"), v.arg(args, 0)});
    return c.pi_js_undefined();
}
fn headersBody(s: *Scope, frame: *HeaderFrame, receiver: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const key = roots[0]; const count = roots[1];
    const raw: [*:0]const u8 = if (v.truthy(s, roots[2])) "rawTrailers" else "rawHeaders";
    const method: [*:0]const u8 = if (v.truthy(s, roots[3])) "_addHeaderLineDistinct" else "_addHeaderLine";
    if (!try truth(s, keyTruth, .{receiver, key})) {
        try statement(s.engine, assignObject, .{receiver, key});
        try frame.take(.source, expression(s.engine, field, .{receiver, raw}));
        try frame.take(.destination, expression(s.engine, keyField, .{receiver, key}));
        try frame.copy(.index, v.number(s, 0));
        var steps: usize = 0;
        while (try truth(s, countCondition, .{receiver, count, frame.get(.index)})) {
            try v.poll(s.engine, &steps);
            try statement(s.engine, appendHeader, .{receiver, frame.get(.destination), method, frame.get(.source), frame.get(.index)});
            try frame.take(.index, expression(s.engine, increment, .{frame.get(.index)}));
        }
    }
    return expression(s.engine, keyField, .{receiver, key});
}
fn headersGet(engine: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const frame = HeaderFrame.create(&s) catch |err| return v.owned.finishValue(&s, @as(anyerror!c.JSValue, err));
    var result = v.owned.Completion.initValue(engine, headersBody(&s, frame, receiver, roots));
    frame.close(&result); result.releaseScope(&s); return result.finishValue();
}
fn headersSet(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, assignKey, .{receiver, roots[0], v.arg(args, 0)}); return c.pi_js_undefined();
}
fn timeoutBody(s: *Scope, receiver: c.JSValue, milliseconds: c.JSValue, callback: c.JSValue) !c.JSValue {
    if (v.truthy(s, callback)) try statement(s.engine, timeoutListen, .{receiver, callback});
    try statement(s.engine, socketTimeout, .{receiver, milliseconds});
    return v.duplicate(s, receiver);
}
fn timeoutListen(s: *Scope, receiver: c.JSValue, callback: c.JSValue) !void {
    const on = try v.get(s, receiver, "on");
    _ = try v.call(s, on, receiver, &.{try v.text(s, "timeout"), callback});
}
fn socketTimeout(s: *Scope, receiver: c.JSValue, milliseconds: c.JSValue) !void {
    const socket = try v.get(s, receiver, "socket");
    const callable = try v.get(s, socket, "setTimeout");
    _ = try v.call(s, callable, socket, &.{milliseconds});
}
fn timeout(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, timeoutBody, .{receiver, v.arg(args, 0), v.arg(args, 1)});
}
fn socketReadable(s: *Scope, receiver: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.get(s, try v.get(s, receiver, "socket"), "readable")));
}
fn startSocket(s: *Scope, receiver: c.JSValue, read_start: c.JSValue) !void {
    const socket = try v.get(s, receiver, "socket");
    _ = try v.call(s, read_start, c.pi_js_undefined(), &.{socket});
}
fn readBody(s: *Scope, receiver: c.JSValue, read_start: c.JSValue) !c.JSValue {
    if (!try truth(s, fieldTruth, .{receiver, @as([*:0]const u8, "_consuming")})) {
        try statement(s.engine, setNested, .{receiver, @as([*:0]const u8, "_readableState"), @as([*:0]const u8, "readingMore"), v.boolean(s, false)});
        try statement(s.engine, setField, .{receiver, @as([*:0]const u8, "_consuming"), v.boolean(s, true)});
    }
    if (try truth(s, socketReadable, .{receiver}))
        try statement(s.engine, startSocket, .{receiver, read_start});
    return c.pi_js_undefined();
}
fn read(engine: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, readBody, .{receiver, roots[0]});
}

fn addLinesLength(s: *Scope, headers: c.JSValue) !c.JSValue {
    return v.boolean(s, !v.nullish(headers) and v.truthy(s, try v.get(s, headers, "length")));
}
fn addLinesBody(s: *Scope, frame: *HeaderFrame, receiver: c.JSValue, headers: c.JSValue, count: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (try truth(s, addLinesLength, .{headers})) {
        const complete = try truth(s, fieldTruth, .{receiver, @as([*:0]const u8, "complete")});
        const key: Key = if (complete) .trailers else .headers;
        const count_key: Key = if (complete) .trailers_count else .headers_count;
        const name: [*:0]const u8 = if (complete) "rawTrailers" else "rawHeaders";
        try statement(s.engine, setField, .{receiver, name, headers});
        try statement(s.engine, assignKey, .{receiver, symbol(roots, count_key), count});
        try frame.take(.destination, expression(s.engine, keyField, .{receiver, symbol(roots, key)}));
        if (v.truthy(s, frame.get(.destination))) {
            try frame.copy(.index, v.number(s, 0));
            var steps: usize = 0;
            while (try truth(s, numericCondition, .{frame.get(.index), count})) {
                try v.poll(s.engine, &steps);
                try statement(s.engine, appendHeader, .{receiver, frame.get(.destination), @as([*:0]const u8, "_addHeaderLine"), headers, frame.get(.index)});
                try frame.take(.index, expression(s.engine, increment, .{frame.get(.index)}));
            }
        }
    }
    return c.pi_js_undefined();
}
fn addLines(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const frame = HeaderFrame.create(&s) catch |err| return v.owned.finishValue(&s, @as(anyerror!c.JSValue, err));
    var result = v.owned.Completion.initValue(engine, addLinesBody(&s, frame, receiver, v.arg(args, 0), v.arg(args, 1), roots));
    frame.close(&result); result.releaseScope(&s); return result.finishValue();
}
fn lengthCase(s: *Scope, input: c.JSValue) !c.JSValue {
    const length = try v.get(s, input, "length");
    inline for (.{3,4,6,7,8,10,11,12,13,14,15,16,17,19}) |n|
        if (v.equal(s, length, v.number(s, n))) return v.number(s, n);
    return v.number(s, 0);
}
fn pair(s: *Scope, input: c.JSValue, upper: []const u8, lower: []const u8) !bool {
    return try v.eq(s, input, upper) or try v.eq(s, input, lower);
}
fn knownBody(s: *Scope, input: c.JSValue, lowercased: bool) anyerror!c.JSValue {
    const selected = try expression(s.engine, lengthCase, .{input});
    const count: u8 = @intCast(c.JS_VALUE_GET_INT(selected));
    switch (count) {
        3 => { if (try pair(s,input,"Age","age")) return v.duplicate(s,try v.text(s,"age")); },
        4 => {
            if (try pair(s,input,"Host","host")) return v.duplicate(s,try v.text(s,"host"));
            if (try pair(s,input,"From","from")) return v.duplicate(s,try v.text(s,"from"));
            if (try pair(s,input,"ETag","etag")) return v.duplicate(s,try v.text(s,"etag"));
            if (try pair(s,input,"Date","date")) return v.duplicate(s,try v.text(s,"\x00date"));
            if (try pair(s,input,"Vary","vary")) return v.duplicate(s,try v.text(s,"\x00vary"));
        },
        6 => {
            if (try pair(s,input,"Server","server")) return v.duplicate(s,try v.text(s,"server"));
            if (try pair(s,input,"Cookie","cookie")) return v.duplicate(s,try v.text(s,"\x02cookie"));
            if (try pair(s,input,"Origin","origin")) return v.duplicate(s,try v.text(s,"\x00origin"));
            if (try pair(s,input,"Expect","expect")) return v.duplicate(s,try v.text(s,"\x00expect"));
            if (try pair(s,input,"Accept","accept")) return v.duplicate(s,try v.text(s,"\x00accept"));
        },
        7 => {
            if (try pair(s,input,"Referer","referer")) return v.duplicate(s,try v.text(s,"referer"));
            if (try pair(s,input,"Expires","expires")) return v.duplicate(s,try v.text(s,"expires"));
            if (try pair(s,input,"Upgrade","upgrade")) return v.duplicate(s,try v.text(s,"\x00upgrade"));
        },
        8 => {
            if (try pair(s,input,"Location","location")) return v.duplicate(s,try v.text(s,"location"));
            if (try pair(s,input,"If-Match","if-match")) return v.duplicate(s,try v.text(s,"\x00if-match"));
        },
        10 => {
            if (try pair(s,input,"User-Agent","user-agent")) return v.duplicate(s,try v.text(s,"user-agent"));
            if (try pair(s,input,"Set-Cookie","set-cookie")) return v.duplicate(s,try v.text(s,"\x01"));
            if (try pair(s,input,"Connection","connection")) return v.duplicate(s,try v.text(s,"\x00connection"));
        },
        11 => { if (try pair(s,input,"Retry-After","retry-after")) return v.duplicate(s,try v.text(s,"retry-after")); },
        12 => {
            if (try pair(s,input,"Content-Type","content-type")) return v.duplicate(s,try v.text(s,"content-type"));
            if (try pair(s,input,"Max-Forwards","max-forwards")) return v.duplicate(s,try v.text(s,"max-forwards"));
        },
        13 => {
            if (try pair(s,input,"Authorization","authorization")) return v.duplicate(s,try v.text(s,"authorization"));
            if (try pair(s,input,"Last-Modified","last-modified")) return v.duplicate(s,try v.text(s,"last-modified"));
            if (try pair(s,input,"Cache-Control","cache-control")) return v.duplicate(s,try v.text(s,"\x00cache-control"));
            if (try pair(s,input,"If-None-Match","if-none-match")) return v.duplicate(s,try v.text(s,"\x00if-none-match"));
        },
        14 => { if (try pair(s,input,"Content-Length","content-length")) return v.duplicate(s,try v.text(s,"content-length")); },
        15 => {
            if (try pair(s,input,"Accept-Encoding","accept-encoding")) return v.duplicate(s,try v.text(s,"\x00accept-encoding"));
            if (try pair(s,input,"Accept-Language","accept-language")) return v.duplicate(s,try v.text(s,"\x00accept-language"));
            if (try pair(s,input,"X-Forwarded-For","x-forwarded-for")) return v.duplicate(s,try v.text(s,"\x00x-forwarded-for"));
        },
        16 => {
            if (try pair(s,input,"Content-Encoding","content-encoding")) return v.duplicate(s,try v.text(s,"\x00content-encoding"));
            if (try pair(s,input,"X-Forwarded-Host","x-forwarded-host")) return v.duplicate(s,try v.text(s,"\x00x-forwarded-host"));
        },
        17 => {
            if (try pair(s,input,"If-Modified-Since","if-modified-since")) return v.duplicate(s,try v.text(s,"if-modified-since"));
            if (try pair(s,input,"Transfer-Encoding","transfer-encoding")) return v.duplicate(s,try v.text(s,"\x00transfer-encoding"));
            if (try pair(s,input,"X-Forwarded-Proto","x-forwarded-proto")) return v.duplicate(s,try v.text(s,"\x00x-forwarded-proto"));
        },
        19 => {
            if (try pair(s,input,"Proxy-Authorization","proxy-authorization")) return v.duplicate(s,try v.text(s,"proxy-authorization"));
            if (try pair(s,input,"If-Unmodified-Since","if-unmodified-since")) return v.duplicate(s,try v.text(s,"if-unmodified-since"));
        },
        else => {},
    }
    if (lowercased) return v.duplicate(s, try binary(s, .add, try v.text(s, "\x00"), input));
    const lowered = try value(s, invoke, .{input, @as([*:0]const u8, "toLowerCase"), @as([]const c.JSValue, &.{})});
    // The Source recursion is at most one additional activation, since the
    // recursive invocation passes literal true. Original input stays borrowed.
    return expression(s.engine, knownBody, .{lowered, true});
}
fn flagBody(s: *Scope, input: c.JSValue) !c.JSValue {
    const method = try v.get(s, input, "charCodeAt");
    return v.duplicate(s, try v.call(s, method, input, &.{v.number(s, 0)}));
}
fn sliceField(s: *Scope, input: c.JSValue) !c.JSValue {
    const method = try v.get(s, input, "slice");
    return v.duplicate(s, try v.call(s, method, input, &.{v.number(s, 1)}));
}
fn addLineBody(s: *Scope, frame: *LineFrame, receiver: c.JSValue, incoming_field: c.JSValue, incoming: c.JSValue, destination: c.JSValue) !c.JSValue {
    try frame.take(.field, expression(s.engine, knownBody, .{incoming_field, false}));
    try frame.take(.flag, expression(s.engine, flagBody, .{frame.get(.field)}));
    const flag = frame.get(.flag);
    if (v.equal(s, flag, v.number(s, 0)) or v.equal(s, flag, v.number(s, 2))) {
        try frame.take(.field, expression(s.engine, sliceField, .{frame.get(.field)}));
        if (try truth(s, stringKeyTest, .{destination, frame.get(.field)}))
            try statement(s.engine, compound, .{destination, frame.get(.field),
                @as([]const u8, if (v.equal(s, flag, v.number(s, 0))) ", " else "; "), incoming})
        else try statement(s.engine, assignKey, .{destination, frame.get(.field), incoming});
    } else if (v.equal(s, flag, v.number(s, 1))) {
        const key = try v.text(s, "set-cookie");
        if (!try truth(s, undefinedKeyTest, .{destination, key}))
            try statement(s.engine, pushKey, .{destination, key, incoming})
        else try statement(s.engine, assignArray, .{destination, key, incoming});
    } else if (try truth(s, fieldTruth, .{receiver, @as([*:0]const u8, "joinDuplicateHeaders")})) {
        if (try truth(s, undefinedKeyTest, .{destination, frame.get(.field)}))
            try statement(s.engine, assignKey, .{destination, frame.get(.field), incoming})
        else try statement(s.engine, compound, .{destination, frame.get(.field), @as([]const u8, ", "), incoming});
    } else if (try truth(s, undefinedKeyTest, .{destination, frame.get(.field)})) {
        try statement(s.engine, assignKey, .{destination, frame.get(.field), incoming});
    }
    return c.pi_js_undefined();
}
fn addLine(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const frame = LineFrame.create(&s) catch |err| return v.owned.finishValue(&s, @as(anyerror!c.JSValue, err));
    var result = v.owned.Completion.initValue(engine, addLineBody(&s, frame, receiver, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)));
    frame.close(&result); result.releaseScope(&s); return result.finishValue();
}
fn distinctBody(s: *Scope, frame: *LineFrame, field_value: c.JSValue, incoming: c.JSValue, destination: c.JSValue) !c.JSValue {
    try frame.take(.field, expression(s.engine, invoke, .{field_value, @as([*:0]const u8, "toLowerCase"), @as([]const c.JSValue, &.{})}));
    if (!try truth(s, keyTruth, .{destination, frame.get(.field)}))
        try statement(s.engine, assignArray, .{destination, frame.get(.field), incoming})
    else try statement(s.engine, pushKey, .{destination, frame.get(.field), incoming});
    return c.pi_js_undefined();
}
fn addDistinct(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const frame = LineFrame.create(&s) catch |err| return v.owned.finishValue(&s, @as(anyerror!c.JSValue, err));
    var result = v.owned.Completion.initValue(engine, distinctBody(&s, frame, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)));
    frame.close(&result); result.releaseScope(&s); return result.finishValue();
}
fn dumpClosedBody(s: *Scope, receiver: c.JSValue) !c.JSValue {
    try statement(s.engine, setField, .{receiver, @as([*:0]const u8, "_dumped"), v.boolean(s, true)});
    inline for (.{ "ended", "endEmitted", "destroyed", "closed", "closeEmitted" }) |name|
        try statement(s.engine, setNested, .{receiver, @as([*:0]const u8, "_readableState"), @as([*:0]const u8, name), v.boolean(s, true)});
    return c.pi_js_undefined();
}
fn dumpClosed(engine: *Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, dumpClosedBody, .{receiver});
}
fn dumpBody(s: *Scope, receiver: c.JSValue) !c.JSValue {
    if (!try truth(s, fieldTruth, .{receiver, @as([*:0]const u8, "_dumped")})) {
        try statement(s.engine, setField, .{receiver, @as([*:0]const u8, "_dumped"), v.boolean(s, true)});
        try statement(s.engine, invokeText, .{receiver, @as([*:0]const u8, "removeAllListeners"), @as([]const u8, "data")});
        try statement(s.engine, invokeVoid, .{receiver, @as([*:0]const u8, "resume"), @as([]const c.JSValue, &.{})});
    }
    return c.pi_js_undefined();
}
fn dump(engine: *Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, dumpBody, .{receiver});
}


fn socketDestroyed(s: *Scope, receiver: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.get(s, try v.get(s, receiver, "socket"), "destroyed")));
}
fn destroySocket(s: *Scope, receiver: c.JSValue, reason: c.JSValue) !void {
    const socket = try v.get(s, receiver, "socket");
    const callable = try v.get(s, socket, "destroy");
    _ = try v.call(s, callable, socket, &.{reason});
}
fn prematureClose(s: *Scope, reason: c.JSValue) !c.JSValue {
    return v.boolean(s, !v.nullish(reason) and try v.eq(s, try v.get(s, reason, "code"), "ERR_STREAM_PREMATURE_CLOSE"));
}
fn callCleanup(s: *Scope, binding: c.JSValue) !void {
    const callable = try DestroyFrame.read(s, binding);
    _ = try v.call(s, callable, c.pi_js_undefined(), &.{});
}
fn nextError(s: *Scope, on_error: c.JSValue, receiver: c.JSValue, reason: c.JSValue, callback: c.JSValue) !void {
    // process is a live global in the actual Node module. Its nextTick method
    // is selected before evaluating any of the four arguments.
    const process = try v.global(s, "process");
    const next_tick = try v.get(s, process, "nextTick");
    _ = try v.call(s, next_tick, process, &.{on_error, receiver, reason, callback});
}
fn finishedCallbackBody(s: *Scope, incoming: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const selected = if (try truth(s, prematureClose, .{incoming})) c.pi_js_null() else incoming;
    try statement(s.engine, callCleanup, .{roots[0]});
    try statement(s.engine, nextError, .{roots[4], roots[1], if (v.truthy(s, selected)) selected else roots[2], roots[3]});
    return c.pi_js_undefined();
}
fn finishedCallback(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, finishedCallbackBody, .{v.arg(args, 0), roots});
}
fn finishSocket(s: *Scope, frame: *DestroyFrame, receiver: c.JSValue, reason: c.JSValue, callback: c.JSValue, finished: c.JSValue, on_error: c.JSValue) !c.JSValue {
    const socket = try v.get(s, receiver, "socket");
    const binding = try frame.capture(s, .cleanup, "cleanup");
    const closure = try v.arrow(s, "", 1, finishedCallback, &.{binding, receiver, reason, callback, on_error});
    return v.duplicate(s, try v.call(s, finished, c.pi_js_undefined(), &.{socket, closure}));
}
fn destroyBody(s: *Scope, frame: *DestroyFrame, receiver: c.JSValue, reason: c.JSValue, callback: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (!try truth(s, fieldTruth, .{receiver, @as([*:0]const u8, "readableEnded")}) or
        !try truth(s, fieldTruth, .{receiver, @as([*:0]const u8, "complete")})) {
        try statement(s.engine, setField, .{receiver, @as([*:0]const u8, "aborted"), v.boolean(s, true)});
        try statement(s.engine, invokeText, .{receiver, @as([*:0]const u8, "emit"), @as([]const u8, "aborted")});
    }
    if (try truth(s, fieldTruth, .{receiver, @as([*:0]const u8, "socket")}) and
        !try truth(s, socketDestroyed, .{receiver}) and
        try truth(s, fieldTruth, .{receiver, @as([*:0]const u8, "aborted")})) {
        try statement(s.engine, destroySocket, .{receiver, reason});
        try frame.take(.cleanup, expression(s.engine, finishSocket, .{frame, receiver, reason, callback, roots[0], roots[1]}));
    } else {
        try statement(s.engine, nextError, .{roots[1], receiver, reason, callback});
    }
    return c.pi_js_undefined();
}
fn destroy(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const frame = DestroyFrame.create(&s) catch |err| return v.owned.finishValue(&s, @as(anyerror!c.JSValue, err));
    var result = v.owned.Completion.initValue(engine, destroyBody(&s, frame, receiver, v.arg(args, 0), v.arg(args, 1), roots));
    frame.close(&result); result.releaseScope(&s); return result.finishValue();
}
fn noErrorListeners(s: *Scope, receiver: c.JSValue) !c.JSValue {
    const callable = try v.get(s, receiver, "listenerCount");
    const count = try v.call(s, callable, receiver, &.{try v.text(s, "error")});
    return v.boolean(s, v.equal(s, count, v.number(s, 0)));
}
fn onErrorBody(s: *Scope, receiver: c.JSValue, reason: c.JSValue, callback: c.JSValue) !c.JSValue {
    const no_listeners = try truth(s, noErrorListeners, .{receiver});
    _ = try v.call(s, callback, c.pi_js_undefined(), if (no_listeners) &.{} else &.{reason});
    return c.pi_js_undefined();
}
fn onError(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, onErrorBody, .{v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)});
}

fn freshSymbol(s: *Scope, description: [*:0]const u8) !c.JSValue {
    var operations: @import("native_sdk_catalog_values.zig").Ops = .{ .s = s };
    const generation = try operations.beforeAllocation();
    return operations.allocation(c.JS_NewSymbol(s.engine.context, description, false), generation);
}
fn setPrototype(s: *Scope, target: c.JSValue, prototype: c.JSValue) !void {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    try boundary.finishStatus(c.JS_SetPrototype(s.engine.context, target, prototype));
}
fn inheritPrototype(s: *Scope, constructor: c.JSValue, readable: c.JSValue) !void {
    const target = try v.get(s, constructor, "prototype");
    const prototype = try v.get(s, readable, "prototype");
    try setPrototype(s, target, prototype);
}
fn accessor(s: *Scope, prototype: c.JSValue, name: [*:0]const u8, getter: v.function.Callback, setter: v.function.Callback, roots: []const c.JSValue) !void {
    // These are actual ordinary functions in a null-prototype descriptor.
    const get = try v.ordinary(s, "get", 0, getter, roots);
    const set = try v.ordinary(s, "set", 1, setter, roots);
    const property = try v.text(s, std.mem.span(name));
    const reference = try Property.init(s, prototype, property); defer reference.deinit();
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    try boundary.finishStatus(c.JS_DefinePropertyGetSet(s.engine.context, prototype, reference.atom,
        v.duplicate(s, get), v.duplicate(s, set), c.JS_PROP_THROW));
}
fn installAccessor(s: *Scope, constructor: c.JSValue, name: [*:0]const u8, getter: v.function.Callback, setter: v.function.Callback, roots: []const c.JSValue) !void {
    const prototype = try v.get(s, constructor, "prototype");
    try accessor(s, prototype, name, getter, setter, roots);
}
fn installMethod(s: *Scope, constructor: c.JSValue, name: [*:0]const u8, arity: c_int, body: v.function.Callback, roots: []const c.JSValue) !void {
    const prototype = try v.get(s, constructor, "prototype");
    const function = try v.ordinary(s, name, arity, body, roots);
    // Actual Source assignment; the inherited Readable prototype may expose
    // a setter, and that setter runs before the next method is created.
    try v.set(s, prototype, name, function);
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    const readable = try v.get(s, inputs.streams, "Readable");
    const finished = try v.get(s, inputs.streams, "finished");
    var roots: [@typeInfo(Key).@"enum".fields.len]c.JSValue = undefined;
    roots[@intFromEnum(Key.readable)] = readable;
    roots[@intFromEnum(Key.finished)] = finished;
    inline for (.{
        .{Key.headers, "kHeaders"}, .{Key.headers_distinct, "kHeadersDistinct"}, .{Key.headers_count, "kHeadersCount"},
        .{Key.trailers, "kTrailers"}, .{Key.trailers_distinct, "kTrailersDistinct"}, .{Key.trailers_count, "kTrailersCount"},
    }) |entry| roots[@intFromEnum(entry[0])] = try freshSymbol(s, entry[1]);
    const read_start = try v.ordinary(s, "readStart", 1, readStart, &.{});
    const read_stop = try v.ordinary(s, "readStop", 1, readStop, &.{});
    const constructor_roots = selectedRoots(&roots, .{ Key.readable, Key.headers, Key.headers_count, Key.trailers, Key.trailers_count });
    const constructor = try v.ordinary(s, "IncomingMessage", 1, construct, &constructor_roots);
    const on_error = try v.ordinary(s, "onError", 3, onError, &.{});
    try statement(s.engine, inheritPrototype, .{constructor, readable});
    try statement(s.engine, setPrototype, .{constructor, readable});
    try statement(s.engine, installAccessor, .{constructor, @as([*:0]const u8, "connection"), connectionGet, connectionSet, @as([]const c.JSValue, &.{})});
    inline for (.{
        .{"headers", Key.headers, Key.headers_count, false, false},
        .{"headersDistinct", Key.headers_distinct, Key.headers_count, false, true},
        .{"trailers", Key.trailers, Key.trailers_count, true, false},
        .{"trailersDistinct", Key.trailers_distinct, Key.trailers_count, true, true},
    }) |entry| {
        const captured: []const c.JSValue = &.{symbol(&roots, entry[1]), symbol(&roots, entry[2]), v.boolean(s, entry[3]), v.boolean(s, entry[4])};
        try statement(s.engine, installAccessor, .{constructor, @as([*:0]const u8, entry[0]), headersGet, headersSet, captured});
    }
    try statement(s.engine, installMethod, .{constructor, @as([*:0]const u8, "setTimeout"), @as(c_int, 2), timeout, @as([]const c.JSValue, &.{})});
    try statement(s.engine, installMethod, .{constructor, @as([*:0]const u8, "_read"), @as(c_int, 1), read, @as([]const c.JSValue, &.{read_start})});
    try statement(s.engine, installMethod, .{constructor, @as([*:0]const u8, "_destroy"), @as(c_int, 2), destroy, @as([]const c.JSValue, &.{finished, on_error})});
    const lines_roots = selectedRoots(&roots, .{ Key.headers, Key.headers_count, Key.trailers, Key.trailers_count });
    try statement(s.engine, installMethod, .{constructor, @as([*:0]const u8, "_addHeaderLines"), @as(c_int, 2), addLines, @as([]const c.JSValue, &lines_roots)});
    try statement(s.engine, installMethod, .{constructor, @as([*:0]const u8, "_addHeaderLine"), @as(c_int, 3), addLine, @as([]const c.JSValue, &.{})});
    try statement(s.engine, installMethod, .{constructor, @as([*:0]const u8, "_addHeaderLineDistinct"), @as(c_int, 3), addDistinct, @as([]const c.JSValue, &.{})});
    try statement(s.engine, installMethod, .{constructor, @as([*:0]const u8, "_dumpAndCloseReadable"), @as(c_int, 0), dumpClosed, @as([]const c.JSValue, &.{})});
    try statement(s.engine, installMethod, .{constructor, @as([*:0]const u8, "_dump"), @as(c_int, 0), dump, @as([]const c.JSValue, &.{})});
    const result = try v.object(s);
    try v.put(s, result, "IncomingMessage", constructor);
    try v.put(s, result, "readStart", read_start);
    try v.put(s, result, "readStop", read_stop);
    return v.duplicate(s, result);
}
pub fn create(engine: *Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |known| return c.JS_DupValue(engine.context, known);
    const candidate = try expression(engine, createBody, .{inputs});
    if (engine.native_module_values.get(cache_key)) |known| {
        var completed = v.owned.Completion.initValue(engine, c.JS_DupValue(engine.context, known));
        completed.release(candidate); return completed.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate); return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return c.JS_DupValue(engine.context, candidate);
}
