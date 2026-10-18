//! Actual c268 RPC JSONL framing over the installed native StringDecoder.
//! Source callbacks share real closed lexical cells; each expression retires
//! before the next property lookup, assignment, or callback.
const v = @import("native_public_values.zig");
const lexical = @import("native_public_lexical_frame.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const math = @import("native_image_arithmetic.zig");
const key = "\x00native.public.rpc-jsonl";
const Names = enum { stream, on_line, decoder, buffer, emit_line, on_data, on_end };
const Frame = lexical.Frame(Names);
const DataFrame = lexical.Frame(enum { newline_index });
const Kind = enum { emit_line, on_data, on_end, detach };

fn expression(engine: *Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, @call(.auto, body, .{&s} ++ args));
}
fn statement(engine: *Engine, comptime body: anytype, args: anytype) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, @call(.auto, body, .{&s} ++ args));
}
fn duplicate(engine: *Engine, value: c.JSValue) c.JSValue { return c.JS_DupValue(engine.context, value); }
fn emptyText(s: *Scope) !c.JSValue { return v.duplicate(s, try v.text(s, "")); }

pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |cached| return duplicate(engine, cached);
    const candidate = try expression(engine, createBody, .{});
    if (engine.native_module_values.get(key)) |cached| {
        var completion = v.owned.Completion.initValue(engine, duplicate(engine, cached));
        completion.release(candidate); return completion.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = v.owned.Completion.initVoid(engine, err);
        completion.release(candidate); try completion.finishVoid(); unreachable;
    };
    const result = duplicate(engine, candidate);
    engine.native_module_values.putAssumeCapacity(key, candidate);
    return result;
}
fn createBody(s: *Scope) !c.JSValue {
    try @import("native_node_string_decoder.zig").install(s.engine);
    const namespace = s.engine.native_module_values.get("node:string_decoder") orelse return error.RpcJsonlRequiresActualStringDecoder;
    const decoder = try v.get(s, namespace, "StringDecoder");
    const result = try v.object(s);
    try v.put(s, result, "serializeJsonLine", try v.ordinary(s, "serializeJsonLine", 1, serialize, &.{}));
    try v.put(s, result, "attachJsonlLineReader", try v.ordinary(s, "attachJsonlLineReader", 2, attach, &.{decoder}));
    return v.duplicate(s, result);
}
fn serialize(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, serializeBody, .{v.arg(args, 0)});
}
fn serializeBody(s: *Scope, value: c.JSValue) !c.JSValue {
    const text = try v.own(s, try expression(s.engine, stringifiedJSON, .{value}));
    return v.duplicate(s, try v.binary(s, 0, text, try v.text(s, "\n")));
}
fn stringifiedJSON(s: *Scope, value: c.JSValue) !c.JSValue {
    const json = try v.own(s, try expression(s.engine, jsonStringify, .{value}));
    return v.duplicate(s, try v.stringify(s, json));
}
fn jsonStringify(s: *Scope, value: c.JSValue) !c.JSValue {
    const receiver = try v.global(s, "JSON");
    const callable = try v.get(s, receiver, "stringify");
    return v.duplicate(s, try v.call(s, callable, receiver, &.{value}));
}
fn attach(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var owner = c.pi_js_undefined();
    const result = expression(engine, attachBody, .{ args, roots[0], &owner });
    var completion = v.owned.Completion.initValue(engine, result);
    if (!c.JS_IsUndefined(owner)) Frame.from(owner).close(&completion);
    completion.release(owner);
    return completion.finishValue();
}
fn attachBody(s: *Scope, args: []const c.JSValue, constructor: c.JSValue, owner: *c.JSValue) !c.JSValue {
    const f = try Frame.create(s);
    owner.* = v.duplicate(s, f.owner);
    try f.copy(.stream, v.arg(args, 0));
    try f.copy(.on_line, v.arg(args, 1));
    try f.take(.decoder, expression(s.engine, newDecoder, .{constructor}));
    try f.take(.buffer, expression(s.engine, emptyText, .{}));
    try f.take(.emit_line, expression(s.engine, createArrow, .{
        Kind.emit_line, @as([*:0]const u8, "emitLine"), @as(c_int, 1),
        @as([]const c.JSValue, &.{try f.capture(s, .on_line, "onLine")}),
    }));
    try f.take(.on_data, expression(s.engine, createArrow, .{
        Kind.on_data, @as([*:0]const u8, "onData"), @as(c_int, 1),
        @as([]const c.JSValue, &.{
            try f.capture(s, .buffer, "buffer"), try f.capture(s, .decoder, "decoder"), try f.capture(s, .emit_line, "emitLine"),
        }),
    }));
    try f.take(.on_end, expression(s.engine, createArrow, .{
        Kind.on_end, @as([*:0]const u8, "onEnd"), @as(c_int, 0),
        @as([]const c.JSValue, &.{
            try f.capture(s, .buffer, "buffer"), try f.capture(s, .decoder, "decoder"), try f.capture(s, .emit_line, "emitLine"),
        }),
    }));
    try statement(s.engine, streamEvent, .{ f.get(.stream), @as([*:0]const u8, "on"), @as([]const u8, "data"), f.get(.on_data) });
    try statement(s.engine, streamEvent, .{ f.get(.stream), @as([*:0]const u8, "on"), @as([]const u8, "end"), f.get(.on_end) });
    return expression(s.engine, createArrow, .{
        Kind.detach, @as([*:0]const u8, ""), @as(c_int, 0),
        @as([]const c.JSValue, &.{
            try f.capture(s, .stream, "stream"), try f.capture(s, .on_data, "onData"), try f.capture(s, .on_end, "onEnd"),
        }),
    });
}
fn newDecoder(s: *Scope, constructor: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.construct(s, constructor, &.{try v.text(s, "utf8")}));
}
fn createArrow(s: *Scope, comptime kind: Kind, name: [*:0]const u8, length: c_int, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, saved: []const c.JSValue) !c.JSValue {
            if (kind == .on_data) return onData(engine, v.arg(args, 0), saved);
            return expression(engine, callbackBody, .{ kind, args, saved });
        }
    };
    return v.duplicate(s, try v.arrow(s, name, length, Adapter.call, roots));
}
fn callbackBody(s: *Scope, comptime kind: Kind, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    switch (kind) {
        .emit_line => try statement(s.engine, emitLine, .{ roots[0], v.arg(args, 0) }),
        .on_end => {
            try Frame.assign(roots[0], expression(s.engine, appended, .{ roots[0], roots[1], c.pi_js_undefined(), false }));
            if (try bufferNonempty(s.engine, roots[0])) {
                try statement(s.engine, emitBuffer, .{ roots[2], roots[0] });
                try Frame.assign(roots[0], expression(s.engine, emptyText, .{}));
            }
        },
        .detach => {
            try statement(s.engine, detachEvent, .{ roots[0], roots[1], @as([]const u8, "data") });
            try statement(s.engine, detachEvent, .{ roots[0], roots[2], @as([]const u8, "end") });
        },
        .on_data => unreachable,
    }
    return c.pi_js_undefined();
}
fn streamEvent(s: *Scope, stream: c.JSValue, name: [*:0]const u8, event: []const u8, handler: c.JSValue) !void {
    const callable = try v.get(s, stream, name);
    _ = try v.call(s, callable, stream, &.{try v.text(s, event), handler});
}
fn detachEvent(s: *Scope, stream_cell: c.JSValue, handler_cell: c.JSValue, event: []const u8) !void {
    const stream = try Frame.read(s, stream_cell);
    const callable = try v.get(s, stream, "off");
    const name = try v.text(s, event);
    const handler = try Frame.read(s, handler_cell);
    _ = try v.call(s, callable, stream, &.{name, handler});
}
fn emitLine(s: *Scope, on_line: c.JSValue, line: c.JSValue) !void {
    const callable = try Frame.read(s, on_line);
    const argument = if (try endsInCarriageReturn(s.engine, line))
        try v.own(s, try expression(s.engine, stripCarriageReturn, .{line}))
    else line;
    _ = try v.call(s, callable, c.pi_js_undefined(), &.{argument});
}
fn endsInCarriageReturn(engine: *Engine, line: c.JSValue) !bool {
    return c.JS_ToBool(engine.context, try expression(engine, endsBody, .{line})) == 1;
}
fn endsBody(s: *Scope, line: c.JSValue) !c.JSValue {
    return v.boolean(s, try v.testText(s, line, "endsWith", "\r"));
}
fn stripCarriageReturn(s: *Scope, line: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.invoke(s, line, "slice", &.{v.number(s, 0), v.number(s, -1)}));
}
fn appended(s: *Scope, buffer: c.JSValue, decoder: c.JSValue, chunk: c.JSValue, data: bool) !c.JSValue {
    // Compound assignment selects the old binding before the RHS call. The
    // decoder expression then retires before either operand is coerced by +.
    const old = try Frame.read(s, buffer);
    const right = if (data and c.JS_IsString(chunk)) chunk
        else try v.own(s, try expression(s.engine, decode, .{ decoder, chunk, data }));
    return v.duplicate(s, try v.binary(s, 0, old, right));
}
fn decode(s: *Scope, decoder: c.JSValue, chunk: c.JSValue, data: bool) !c.JSValue {
    const receiver = try Frame.read(s, decoder);
    const callable = try v.get(s, receiver, if (data) "write" else "end");
    return v.duplicate(s, try v.call(s, callable, receiver, if (data) &.{chunk} else &.{}));
}
fn onData(engine: *Engine, chunk: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var owner = c.pi_js_undefined();
    const result = expression(engine, onDataBody, .{ chunk, roots, &owner });
    var completion = v.owned.Completion.initValue(engine, result);
    if (!c.JS_IsUndefined(owner)) DataFrame.from(owner).close(&completion);
    completion.release(owner);
    return completion.finishValue();
}
fn onDataBody(s: *Scope, chunk: c.JSValue, roots: []const c.JSValue, owner: *c.JSValue) !c.JSValue {
    const f = try DataFrame.create(s);
    owner.* = v.duplicate(s, f.owner);
    try Frame.assign(roots[0], expression(s.engine, appended, .{ roots[0], roots[1], chunk, true }));
    var steps: usize = 0;
    while (true) {
        try v.poll(s.engine, &steps);
        // The previous body local survives the loop tail; the next true body
        // entry resets it before reading the next buffer/indexOf expression.
        try f.clear(.newline_index);
        try f.take(.newline_index, expression(s.engine, newlineIndex, .{roots[0]}));
        if (v.equal(s, f.get(.newline_index), v.number(s, -1))) return c.pi_js_undefined();
        try statement(s.engine, emitPart, .{ roots[2], roots[0], f.get(.newline_index) });
        try Frame.assign(roots[0], expression(s.engine, remainingBuffer, .{ roots[0], f.get(.newline_index) }));
    }
}
fn newlineIndex(s: *Scope, buffer: c.JSValue) !c.JSValue {
    const receiver = try Frame.read(s, buffer);
    const callable = try v.get(s, receiver, "indexOf");
    return v.duplicate(s, try v.call(s, callable, receiver, &.{try v.text(s, "\n")}));
}
fn emitPart(s: *Scope, emit_line: c.JSValue, buffer: c.JSValue, index: c.JSValue) !void {
    const callable = try Frame.read(s, emit_line);
    const line = try v.own(s, try expression(s.engine, bufferPrefix, .{buffer, index}));
    _ = try v.call(s, callable, c.pi_js_undefined(), &.{line});
}
fn bufferPrefix(s: *Scope, buffer: c.JSValue, index: c.JSValue) !c.JSValue {
    const receiver = try Frame.read(s, buffer);
    const callable = try v.get(s, receiver, "slice");
    return v.duplicate(s, try v.call(s, callable, receiver, &.{v.number(s, 0), index}));
}
fn remainingBuffer(s: *Scope, buffer: c.JSValue, index: c.JSValue) !c.JSValue {
    const receiver = try Frame.read(s, buffer);
    const callable = try v.get(s, receiver, "slice");
    const start = try v.binary(s, 0, index, v.number(s, 1));
    return v.duplicate(s, try v.call(s, callable, receiver, &.{start}));
}
fn bufferNonempty(engine: *Engine, buffer: c.JSValue) !bool {
    return c.JS_ToBool(engine.context, try expression(engine, nonemptyBody, .{expression(engine, bufferLength, .{buffer})})) == 1;
}
fn bufferLength(s: *Scope, buffer: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.get(s, try Frame.read(s, buffer), "length"));
}
fn nonemptyBody(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const length = try v.own(s, try incoming);
    return v.boolean(s, v.truthy(s, try v.binary(s, @intFromEnum(math.Operation.greater), length, v.number(s, 0))));
}
fn emitBuffer(s: *Scope, emit_line: c.JSValue, buffer: c.JSValue) !void {
    const callable = try Frame.read(s, emit_line);
    _ = try v.call(s, callable, c.pi_js_undefined(), &.{try Frame.read(s, buffer)});
}
