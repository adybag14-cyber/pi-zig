//! Source Editor marker-aware segmentation and genuine native Segments iterables.
const std = @import("std");
const e = @import("native_editor_values.zig");
const js = e.js;
const c = e.c;
const Engine = e.Engine;
const v = e.v;
const graphemes = @import("../tui/utf16_graphemes.zig");
const words = @import("../tui/utf16_words.zig");
const Piece = struct { start: usize, end: usize, word: ?bool = null };
const Classes = struct {
    engine: *Engine,
    segments_class: c.JSClassID,
    iterator_class: c.JSClassID,
    segments_proto: c.JSValue,
    iterator_proto: c.JSValue,
    iterator_symbol: c.JSValue,
};
const Segments = struct { engine: *Engine, input: c.JSValue, units: []u16, pieces: []Piece };
const Iterator = struct { engine: *Engine, segments: c.JSValue, position: usize = 0 };
fn owner(value: c.JSValue) *Classes {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn ownerMark(runtime: ?*c.JSRuntime, value: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Classes = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for ([_]c.JSValue{ state.segments_proto, state.iterator_proto, state.iterator_symbol }) |item| c.JS_MarkValue(runtime, item, mark);
}
fn ownerFinalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Classes = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    _ = c.JS_SetOpaque(value, null);
    for ([_]c.JSValue{ state.segments_proto, state.iterator_proto, state.iterator_symbol }) |item| c.JS_FreeValueRT(runtime, item);
    state.engine.gpa.destroy(state);
}
fn segmentState(value: c.JSValue) *Segments {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn segmentsMark(runtime: ?*c.JSRuntime, value: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Segments = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.input, mark);
}
fn segmentsFinalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Segments = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    _ = c.JS_SetOpaque(value, null);
    c.JS_FreeValueRT(runtime, state.input);
    state.engine.gpa.free(state.units);
    state.engine.gpa.free(state.pieces);
    state.engine.gpa.destroy(state);
}
fn iteratorState(value: c.JSValue) *Iterator {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn iteratorMark(runtime: ?*c.JSRuntime, value: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Iterator = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.segments, mark);
}
fn iteratorFinalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Iterator = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    _ = c.JS_SetOpaque(value, null);
    c.JS_FreeValueRT(runtime, state.segments);
    state.engine.gpa.destroy(state);
}
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Editor segments: %s", @as([*:0]const u8, @errorName(err)));
}
fn dataRecord(engine: *Engine, state: *Segments, piece: Piece) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "segment", try e.utf16.string(engine, state.units[piece.start..piece.end]));
    try js.define(engine, result, "index", v.numeric(engine, @floatFromInt(piece.start)));
    try js.define(engine, result, "input", c.JS_DupValue(engine.context, state.input));
    if (piece.word) |word| try js.define(engine, result, "isWordLike", c.pi_js_bool(engine.context, @intFromBool(word)));
    return result;
}
const Method = enum(c_int) { containing, iterate, next };
fn operation(classes: *Classes, object: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const engine = classes.engine;
    switch (method) {
        .containing => {
            const state: *Segments = @ptrCast(@alignCast(c.JS_GetOpaque(object, classes.segments_class) orelse return js.typeError(engine, "Invalid Segments receiver")));
            var index = try v.number(engine, v.arg(args, 0));
            if (std.math.isNan(index)) index = 0;
            index = @trunc(index);
            if (index < 0 or index >= @as(f64, @floatFromInt(state.units.len))) return c.pi_js_undefined();
            const at: usize = @intFromFloat(index);
            for (state.pieces) |piece| if (at >= piece.start and at < piece.end) return dataRecord(engine, state, piece);
            return c.pi_js_undefined();
        },
        .iterate => {
            if (c.JS_GetOpaque(object, classes.segments_class) == null) return js.typeError(engine, "Invalid Segments receiver");
            const result = try engine.checked(c.JS_NewObjectProtoClass(engine.context, classes.iterator_proto, classes.iterator_class));
            errdefer engine.freeValue(result);
            const state = try engine.gpa.create(Iterator);
            state.* = .{ .engine = engine, .segments = c.JS_DupValue(engine.context, object) };
            _ = c.JS_SetOpaque(result, state);
            return result;
        },
        .next => {
            const iterator: *Iterator = @ptrCast(@alignCast(c.JS_GetOpaque(object, classes.iterator_class) orelse return js.typeError(engine, "Invalid Segmenter iterator receiver")));
            const segments = segmentState(iterator.segments);
            const result = try js.object(engine);
            errdefer engine.freeValue(result);
            const done = iterator.position >= segments.pieces.len;
            try js.define(engine, result, "value", if (done) c.pi_js_undefined() else try dataRecord(engine, segments, segments.pieces[iterator.position]));
            try js.define(engine, result, "done", c.pi_js_bool(engine.context, @intFromBool(done)));
            if (!done) iterator.position += 1;
            return result;
        },
    }
}
fn callback(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const classes = owner(data[0]);
    _ = context;
    return operation(classes, object, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(classes.engine, err);
}
fn function(engine: *Engine, token: c.JSValue, method: Method, name: [*:0]const u8, arity: c_int) !c.JSValue {
    var data = [_]c.JSValue{token};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, arity, @intFromEnum(method), 1, &data));
}
fn defineSymbol(engine: *Engine, object: c.JSValue, symbol: c.JSValue, value: c.JSValue, flags: c_int) !void {
    const atom = try js.atom(engine, symbol);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, object, atom, value, flags) < 0) return js.capture(engine);
}
pub fn install(engine: *Engine) !c.JSValue {
    var owner_class: c.JSClassID = 0;
    var segments_class: c.JSClassID = 0;
    var iterator_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &owner_class);
    _ = c.JS_NewClassID(engine.runtime, &segments_class);
    _ = c.JS_NewClassID(engine.runtime, &iterator_class);
    const owner_definition: c.JSClassDef = .{ .class_name = "Native Editor Segments Owner", .gc_mark = ownerMark, .finalizer = ownerFinalize, .call = null, .exotic = null };
    const segment_definition: c.JSClassDef = .{ .class_name = "Native Editor Segments", .gc_mark = segmentsMark, .finalizer = segmentsFinalize, .call = null, .exotic = null };
    const iterator_definition: c.JSClassDef = .{ .class_name = "Native Editor Segmenter Iterator", .gc_mark = iteratorMark, .finalizer = iteratorFinalize, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, owner_class, &owner_definition) < 0 or c.JS_NewClass(engine.runtime, segments_class, &segment_definition) < 0 or c.JS_NewClass(engine.runtime, iterator_class, &iterator_definition) < 0) return error.OutOfMemory;
    const token = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(owner_class)));
    errdefer engine.freeValue(token);
    const state = try engine.gpa.create(Classes);
    state.* = .{ .engine = engine, .segments_class = segments_class, .iterator_class = iterator_class, .segments_proto = c.pi_js_undefined(), .iterator_proto = c.pi_js_undefined(), .iterator_symbol = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(token, state);
    state.segments_proto = try js.object(engine);
    const array = try js.array(engine);
    defer engine.freeValue(array);
    const array_iterator = try js.invoke(engine, array, "values", &.{});
    defer engine.freeValue(array_iterator);
    const array_iterator_proto = try engine.checked(c.JS_GetPrototype(engine.context, array_iterator));
    defer engine.freeValue(array_iterator_proto);
    const generic_iterator_proto = try engine.checked(c.JS_GetPrototype(engine.context, array_iterator_proto));
    defer engine.freeValue(generic_iterator_proto);
    state.iterator_proto = try engine.checked(c.JS_NewObjectProto(engine.context, generic_iterator_proto));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    state.iterator_symbol = try js.get(engine, symbol, "iterator");
    const tag = try js.get(engine, symbol, "toStringTag");
    defer engine.freeValue(tag);
    if (c.JS_DefinePropertyValueStr(engine.context, state.segments_proto, "containing", try function(engine, token, .containing, "containing", 1), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    try defineSymbol(engine, state.segments_proto, state.iterator_symbol, try function(engine, token, .iterate, "[Symbol.iterator]", 0), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE);
    if (c.JS_DefinePropertyValueStr(engine.context, state.iterator_proto, "next", try function(engine, token, .next, "next", 0), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    try defineSymbol(engine, state.iterator_proto, tag, try v.text(engine, "Segmenter String Iterator"), c.JS_PROP_CONFIGURABLE);
    return token;
}
fn basePieces(engine: *Engine, units: []const u16, word: bool) ![]Piece {
    var result: std.ArrayList(Piece) = .empty;
    errdefer result.deinit(engine.gpa);
    if (word) {
        const parts = try words.segmentsAlloc(engine.gpa, units);
        defer engine.gpa.free(parts);
        for (parts) |part| try result.append(engine.gpa, .{ .start = part.start, .end = part.end, .word = part.word });
    } else {
        var iterator: graphemes.Iterator = .{ .text = units };
        while (iterator.next()) |part| try result.append(engine.gpa, .{ .start = part.start, .end = part.end });
    }
    return result.toOwnedSlice(engine.gpa);
}
pub fn segment(engine: *Engine, editor: c.JSValue, input: c.JSValue, mode: c.JSValue, token: c.JSValue) !c.JSValue {
    const classes = owner(token);
    const valid = try js.invoke(engine, editor, "validPasteIds", &.{});
    defer engine.freeValue(valid);
    const size = try js.get(engine, valid, "size");
    defer engine.freeValue(size);
    var markers: std.ArrayList(Piece) = .empty;
    defer markers.deinit(engine.gpa);
    if (!c.JS_IsStrictEqual(engine.context, size, v.numeric(engine, 0))) {
        const prefix = try v.text(engine, "[paste #");
        defer engine.freeValue(prefix);
        const includes = try js.invoke(engine, input, "includes", &.{prefix});
        defer engine.freeValue(includes);
        if (v.truthy(engine, includes)) {
            const regex = try e.literalPattern(engine, "\\[paste #(\\d+)( (\\+\\d+ lines|\\d+ chars))?\\]", "g");
            defer engine.freeValue(regex);
            const matches = try js.invoke(engine, input, "matchAll", &.{regex});
            defer engine.freeValue(matches);
            var iterator = try js.Iterator.init(engine, matches, classes.iterator_symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |match| {
                defer engine.freeValue(match);
                const raw_id = try v.fieldAt(engine, match, 1);
                defer engine.freeValue(raw_id);
                const numeric = try js.global(engine, "Number");
                defer engine.freeValue(numeric);
                const id = try js.invoke(engine, numeric, "parseInt", &.{ raw_id, v.numeric(engine, 10) });
                defer engine.freeValue(id);
                const has = try js.invoke(engine, valid, "has", &.{id});
                defer engine.freeValue(has);
                if (!v.truthy(engine, has)) continue;
                const start = try e.number(engine, match, "index");
                const whole = try v.fieldAt(engine, match, 0);
                defer engine.freeValue(whole);
                if (!std.math.isFinite(start) or start < 0 or start > 1_000_000) return error.NativeEditorStateLimit;
                const offset: usize = @intFromFloat(start);
                try markers.append(engine.gpa, .{ .start = offset, .end = offset + try e.length(engine, whole) });
            }
        }
    }
    const string = try engine.checked(c.JS_ToString(engine.context, input));
    defer engine.freeValue(string);
    const units = try e.utf16.unitsAlloc(engine, string);
    var units_transferred = false;
    defer if (!units_transferred) engine.gpa.free(units);
    const pieces = try basePieces(engine, units, try e.equalText(engine, mode, "word"));
    var pieces_transferred = false;
    defer if (!pieces_transferred) engine.gpa.free(pieces);
    const state = try engine.gpa.create(Segments);
    var state_transferred = false;
    defer if (!state_transferred) engine.gpa.destroy(state);
    state.* = .{ .engine = engine, .input = string, .units = units, .pieces = pieces };
    if (markers.items.len == 0) {
        const result = try engine.checked(c.JS_NewObjectProtoClass(engine.context, classes.segments_proto, classes.segments_class));
        state.input = c.JS_DupValue(engine.context, string);
        _ = c.JS_SetOpaque(result, state);
        state_transferred = true;
        units_transferred = true;
        pieces_transferred = true;
        return result;
    }
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    var marker_index: usize = 0;
    for (pieces) |piece| {
        while (marker_index < markers.items.len and markers.items[marker_index].end <= piece.start) marker_index += 1;
        if (marker_index < markers.items.len) {
            const marker = markers.items[marker_index];
            if (piece.start >= marker.start and piece.start < marker.end) {
                if (piece.start == marker.start) {
                    const item = try js.object(engine);
                    defer engine.freeValue(item);
                    try js.define(engine, item, "segment", try js.invoke(engine, input, "slice", &.{ v.numeric(engine, @floatFromInt(marker.start)), v.numeric(engine, @floatFromInt(marker.end)) }));
                    try js.define(engine, item, "index", v.numeric(engine, @floatFromInt(marker.start)));
                    try js.define(engine, item, "input", c.JS_DupValue(engine.context, input));
                    try js.push(engine, result, item);
                }
                continue;
            }
        }
        const item = try dataRecord(engine, state, piece);
        defer engine.freeValue(item);
        try js.push(engine, result, item);
    }
    return result;
}
test "Source6fb public Editor segments owner allocation failure cleans uninitialized native objects" {
    for (0..2) |offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try Engine.init(failing.allocator(), .{});
        failing.fail_index = failing.alloc_index + offset;
        const token = install(engine) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expect(failing.has_induced_failure);
            failing.fail_index = std.math.maxInt(usize);
            // The same VM remains usable after the failed class-owner allocation.
            const reused = try install(engine);
            engine.freeValue(reused);
            c.JS_RunGC(engine.runtime);
            engine.deinit();
            try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            continue;
        };
        try std.testing.expect(!failing.has_induced_failure);
        engine.freeValue(token);
        c.JS_RunGC(engine.runtime);
        engine.deinit();
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}
test "Source6fb public Editor segments iterator allocation failure releases unattached native object" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try Engine.init(failing.allocator(), .{});
    const token = try install(engine);
    const classes = owner(token);
    const input = try v.text(engine, "abc");
    const units = try e.utf16.unitsAlloc(engine, input);
    const pieces = try basePieces(engine, units, false);
    const state = try engine.gpa.create(Segments);
    state.* = .{ .engine = engine, .input = input, .units = units, .pieces = pieces };
    const object = try engine.checked(c.JS_NewObjectProtoClass(engine.context, classes.segments_proto, classes.segments_class));
    _ = c.JS_SetOpaque(object, state);
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, operation(classes, object, .iterate, &.{}));
    try std.testing.expect(failing.has_induced_failure);
    failing.fail_index = std.math.maxInt(usize);
    const iterator = try operation(classes, object, .iterate, &.{});
    engine.freeValue(iterator);
    engine.freeValue(object);
    engine.freeValue(token);
    c.JS_RunGC(engine.runtime);
    engine.deinit();
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}
