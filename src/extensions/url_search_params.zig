//! Native ordered URL parameters, form encoding, live iteration and URL hooks.
const std = @import("std");
const engine_mod = @import("engine.zig");
const binary = @import("binary_encoding.zig");
const c = engine_mod.c;
pub const Pair = struct { name: []u8, value: []u8 };
pub const Association = struct {
    owner: c.JSValue,
    context: *anyopaque,
    /// Commit the URL query only after all allocations succeed. Called before
    /// replacing the parameter list; no JavaScript executes inside this hook.
    update: *const fn (*anyopaque, []const Pair) anyerror!void,
};
pub const State = struct {
    engine: *engine_mod.Engine,
    pairs: std.ArrayList(Pair) = .empty,
    association: ?Association = null,
};
const Iterator = struct { engine: *engine_mod.Engine, params: c.JSValue, index: usize = 0, kind: c_int };
const Constructor = struct { engine: *engine_mod.Engine, prototype: c.JSValue, iterator: c.JSValue };
const Method = enum(c_int) { append, delete, get, getAll, has, set, sort, toString, forEach, keys, values, entries, size };
const max_pairs = 1_000_000;

pub fn freePairs(gpa: std.mem.Allocator, pairs: *std.ArrayList(Pair)) void {
    for (pairs.items) |pair| {
        gpa.free(pair.name);
        gpa.free(pair.value);
    }
    pairs.deinit(gpa);
    pairs.* = .empty;
}
pub fn clonePairs(gpa: std.mem.Allocator, pairs: []const Pair) !std.ArrayList(Pair) {
    var output: std.ArrayList(Pair) = .empty;
    errdefer freePairs(gpa, &output);
    for (pairs) |pair| {
        const name = try gpa.dupe(u8, pair.name);
        errdefer gpa.free(name);
        const value = try gpa.dupe(u8, pair.value);
        errdefer gpa.free(value);
        try output.append(gpa, .{ .name = name, .value = value });
    }
    return output;
}
pub fn usvString(engine: *engine_mod.Engine, value: c.JSValue) ![]u8 {
    const input = try engine.toString(value);
    defer engine.gpa.free(input);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(engine.gpa);
    var iterator = (try std.unicode.Wtf8View.init(input)).iterator();
    var buffer: [4]u8 = undefined;
    while (iterator.nextCodepoint()) |point| {
        const scalar: u21 = if (point >= 0xd800 and point <= 0xdfff) 0xfffd else point;
        const length = try std.unicode.utf8Encode(scalar, &buffer);
        try output.appendSlice(engine.gpa, buffer[0..length]);
    }
    return output.toOwnedSlice(engine.gpa);
}
fn decodeForm(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(gpa);
    var index: usize = 0;
    while (index < input.len) : (index += 1) {
        const byte = input[index];
        if (byte == '%' and index + 2 < input.len) {
            const high = std.fmt.charToDigit(input[index + 1], 16) catch null;
            const low = std.fmt.charToDigit(input[index + 2], 16) catch null;
            if (high != null and low != null) {
                try bytes.append(gpa, (high.? << 4) | low.?);
                index += 2;
                continue;
            }
        }
        try bytes.append(gpa, if (byte == '+') ' ' else byte);
    }
    return binary.decode(gpa, bytes.items, .utf8);
}
pub fn parse(gpa: std.mem.Allocator, input: []const u8) !std.ArrayList(Pair) {
    const query = if (std.mem.startsWith(u8, input, "?")) input[1..] else input;
    var output: std.ArrayList(Pair) = .empty;
    errdefer freePairs(gpa, &output);
    var entries = std.mem.splitScalar(u8, query, '&');
    while (entries.next()) |entry| {
        if (entry.len == 0) continue;
        if (output.items.len >= max_pairs) return error.SearchParamsLimit;
        const equals = std.mem.indexOfScalar(u8, entry, '=') orelse entry.len;
        const name = try decodeForm(gpa, entry[0..equals]);
        errdefer gpa.free(name);
        const value = try decodeForm(gpa, if (equals < entry.len) entry[equals + 1 ..] else "");
        errdefer gpa.free(value);
        try output.append(gpa, .{ .name = name, .value = value });
    }
    return output;
}
fn encodeForm(output: *std.ArrayList(u8), gpa: std.mem.Allocator, value: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "*-._", byte) != null) {
            try output.append(gpa, byte);
        } else if (byte == ' ') try output.append(gpa, '+') else {
            try output.appendSlice(gpa, &.{ '%', hex[byte >> 4], hex[byte & 15] });
        }
    }
}
pub fn serialize(gpa: std.mem.Allocator, pairs: []const Pair) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    for (pairs, 0..) |pair, index| {
        if (index != 0) try output.append(gpa, '&');
        try encodeForm(&output, gpa, pair.name);
        try output.append(gpa, '=');
        try encodeForm(&output, gpa, pair.value);
    }
    return output.toOwnedSlice(gpa);
}
pub fn stateFor(engine: *engine_mod.Engine, value: c.JSValue) !*State {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.url_search_params_class) orelse return error.IllegalURLSearchParamsReceiver));
    if (state.engine != engine) return error.IllegalURLSearchParamsReceiver;
    return state;
}
fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    if (err == error.SearchParamsLimit) return c.JS_ThrowRangeError(engine.context, "URLSearchParams entry limit");
    return c.JS_ThrowTypeError(engine.context, "Native URLSearchParams: %s", @as([*:0]const u8, @errorName(err)));
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (state.association) |association| c.JS_FreeValueRT(runtime, association.owner);
    freePairs(state.engine.gpa, &state.pairs);
    state.engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, mark_value: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (state.association) |association| c.JS_MarkValue(runtime, association.owner, mark_value);
}
fn constructorFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    c.JS_FreeValueRT(runtime, state.iterator);
    state.engine.gpa.destroy(state);
}
fn constructorMark(runtime: ?*c.JSRuntime, value: c.JSValue, mark_value: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, mark_value);
    c.JS_MarkValue(runtime, state.iterator, mark_value);
}
fn property(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, object, name));
}
fn symbolProperty(engine: *engine_mod.Engine, object: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const atom = c.JS_ValueToAtom(engine.context, symbol);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    return engine.checked(c.JS_GetProperty(engine.context, object, atom));
}
fn iteratorClose(engine: *engine_mod.Engine, iterator: c.JSValue, err: anyerror) void {
    const primary: ?c.JSValue = if (err == error.JavaScriptException) if (c.JS_HasException(engine.context)) c.JS_GetException(engine.context) else if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else null else null;
    const method = c.JS_GetPropertyStr(engine.context, iterator, "return");
    if (c.JS_IsException(method)) {
        engine.freeValue(c.JS_GetException(engine.context));
    } else {
        defer engine.freeValue(method);
        if (c.JS_IsFunction(engine.context, method)) {
            const result = c.JS_Call(engine.context, method, iterator, 0, null);
            if (c.JS_IsException(result)) engine.freeValue(c.JS_GetException(engine.context)) else engine.freeValue(result);
        }
    }
    if (primary) |value| _ = c.JS_Throw(engine.context, value);
}
const Accept = *const fn (*engine_mod.Engine, *anyopaque, c.JSValue) anyerror!void;
fn iterate(engine: *engine_mod.Engine, source: c.JSValue, method: c.JSValue, accept: Accept, context: *anyopaque) !void {
    if (!c.JS_IsFunction(engine.context, method)) return error.InvalidSearchParamsIterator;
    const iterator = try engine.checked(c.JS_Call(engine.context, method, source, 0, null));
    defer engine.freeValue(iterator);
    if (!c.JS_IsObject(iterator)) return error.InvalidSearchParamsIterator;
    const next = try property(engine, iterator, "next");
    defer engine.freeValue(next);
    if (!c.JS_IsFunction(engine.context, next)) return error.InvalidSearchParamsIterator;
    var body_active = false;
    errdefer |err| if (body_active) iteratorClose(engine, iterator, err);
    for (0..max_pairs + 1) |_| {
        const result = try engine.checked(c.JS_Call(engine.context, next, iterator, 0, null));
        defer engine.freeValue(result);
        if (!c.JS_IsObject(result)) return error.InvalidSearchParamsIterator;
        const done = try property(engine, result, "done");
        defer engine.freeValue(done);
        if (c.JS_ToBool(engine.context, done) != 0) return;
        const value = try property(engine, result, "value");
        defer engine.freeValue(value);
        body_active = true;
        try accept(engine, context, value);
        body_active = false;
    }
    return error.SearchParamsLimit;
}
const PairContext = struct { pairs: *std.ArrayList(Pair), symbol: c.JSValue };
const TupleContext = struct { values: std.ArrayList([]u8) = .empty };
fn tupleValue(engine: *engine_mod.Engine, context: *anyopaque, value: c.JSValue) !void {
    const tuple: *TupleContext = @ptrCast(@alignCast(context));
    const text = try usvString(engine, value);
    errdefer engine.gpa.free(text);
    try tuple.values.append(engine.gpa, text);
}
fn acceptPair(engine: *engine_mod.Engine, context: *anyopaque, pair: c.JSValue) !void {
    const target: *PairContext = @ptrCast(@alignCast(context));
    if (!c.JS_IsObject(pair)) return error.InvalidSearchParamsTuple;
    var tuple: TupleContext = .{};
    defer {
        for (tuple.values.items) |value| engine.gpa.free(value);
        tuple.values.deinit(engine.gpa);
    }
    if (c.JS_IsArray(pair)) {
        const length = try property(engine, pair, "length");
        defer engine.freeValue(length);
        if (!c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 2))) return error.InvalidSearchParamsTuple;
        for (0..2) |index| {
            const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, @intCast(index)));
            defer engine.freeValue(value);
            try tupleValue(engine, &tuple, value);
        }
    } else {
        const method = try symbolProperty(engine, pair, target.symbol);
        defer engine.freeValue(method);
        try iterate(engine, pair, method, tupleValue, &tuple);
        if (tuple.values.items.len != 2) return error.InvalidSearchParamsTuple;
    }
    if (target.pairs.items.len >= max_pairs) return error.SearchParamsLimit;
    try target.pairs.append(engine.gpa, .{ .name = tuple.values.items[0], .value = tuple.values.items[1] });
    tuple.values.clearRetainingCapacity();
}
fn initialize(engine: *engine_mod.Engine, input: c.JSValue, symbol: c.JSValue) !std.ArrayList(Pair) {
    if (c.JS_IsNull(input) or c.JS_IsUndefined(input)) return .empty;
    if (!c.JS_IsObject(input)) {
        const text = try usvString(engine, input);
        defer engine.gpa.free(text);
        return parse(engine.gpa, text);
    }
    var result: std.ArrayList(Pair) = .empty;
    errdefer freePairs(engine.gpa, &result);
    const method = try symbolProperty(engine, input, symbol);
    defer engine.freeValue(method);
    if (!c.JS_IsNull(method) and !c.JS_IsUndefined(method)) {
        var context: PairContext = .{ .pairs = &result, .symbol = symbol };
        try iterate(engine, input, method, acceptPair, &context);
    } else {
        var keys: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(engine.context, &keys, &count, input, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(engine.context, keys, count);
        for (0..count) |index| {
            var descriptor: c.JSPropertyDescriptor = undefined;
            const found = c.JS_GetOwnProperty(engine.context, &descriptor, input, keys[index].atom);
            if (found < 0) return error.JavaScriptException;
            if (found == 0) continue;
            defer engine.freeValue(descriptor.value);
            defer engine.freeValue(descriptor.getter);
            defer engine.freeValue(descriptor.setter);
            if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
            const key = try engine.checked(c.JS_AtomToValue(engine.context, keys[index].atom));
            defer engine.freeValue(key);
            const name = try usvString(engine, key);
            var name_owned = true;
            defer if (name_owned) engine.gpa.free(name);
            const source = try engine.checked(c.JS_GetProperty(engine.context, input, keys[index].atom));
            defer engine.freeValue(source);
            const value = try usvString(engine, source);
            var value_owned = true;
            defer if (value_owned) engine.gpa.free(value);
            for (result.items) |*existing| {
                if (!std.mem.eql(u8, existing.name, name)) continue;
                engine.gpa.free(existing.value);
                existing.value = value;
                value_owned = false;
                break;
            } else {
                if (result.items.len >= max_pairs) return error.SearchParamsLimit;
                try result.append(engine.gpa, .{ .name = name, .value = value });
                name_owned = false;
                value_owned = false;
            }
        }
    }
    return result;
}
/// Consumes pairs only on success. URL callers may attach an association later.
pub fn create(engine: *engine_mod.Engine, pairs: *std.ArrayList(Pair)) !c.JSValue {
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.url_search_params_class));
    errdefer engine.freeValue(object);
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .pairs = pairs.* };
    pairs.* = .empty;
    _ = c.JS_SetOpaque(object, state);
    return object;
}
pub fn associate(engine: *engine_mod.Engine, params: c.JSValue, association: Association) !void {
    const state = try stateFor(engine, params);
    if (state.association != null) return error.URLSearchParamsAlreadyAssociated;
    state.association = association;
    state.association.?.owner = c.JS_DupValue(engine.context, association.owner);
}
/// A URL setter prepares both new record and pairs first, then transfers here.
pub fn replacePairs(state: *State, pairs: *std.ArrayList(Pair)) void {
    freePairs(state.engine.gpa, &state.pairs);
    state.pairs = pairs.*;
    pairs.* = .empty;
}
fn construct(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "URLSearchParams requires new");
    const constructor: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    return constructValue(engine, constructor, target, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn constructValue(engine: *engine_mod.Engine, constructor: *Constructor, target: c.JSValue, input: c.JSValue) !c.JSValue {
    const prototype = try property(engine, target, "prototype");
    defer engine.freeValue(prototype);
    var pairs = try initialize(engine, input, constructor.iterator);
    defer freePairs(engine.gpa, &pairs);
    const object = try create(engine, &pairs);
    errdefer engine.freeValue(object);
    if (c.JS_SetPrototype(engine.context, object, if (c.JS_IsObject(prototype)) prototype else constructor.prototype) < 0) return error.JavaScriptException;
    return object;
}
fn utf16Less(_: void, a: Pair, b: Pair) bool {
    var left = std.unicode.Utf8View.initUnchecked(a.name).iterator();
    var right = std.unicode.Utf8View.initUnchecked(b.name).iterator();
    var left_tail: ?u16 = null;
    var right_tail: ?u16 = null;
    while (true) {
        const lhs = nextUnit(&left, &left_tail);
        const rhs = nextUnit(&right, &right_tail);
        if (lhs == null or rhs == null) return lhs == null and rhs != null;
        if (lhs.? != rhs.?) return lhs.? < rhs.?;
    }
}
fn nextUnit(iterator: *std.unicode.Utf8Iterator, tail: *?u16) ?u16 {
    if (tail.*) |value| {
        tail.* = null;
        return value;
    }
    const point = iterator.nextCodepoint() orelse return null;
    if (point <= 0xffff) return @intCast(point);
    tail.* = @intCast(0xdc00 + ((point - 0x10000) & 1023));
    return @intCast(0xd800 + ((point - 0x10000) >> 10));
}
fn mutate(state: *State, method: Method, name: ?[]const u8, value: ?[]const u8) !void {
    const gpa = state.engine.gpa;
    var proposed = try clonePairs(gpa, state.pairs.items);
    defer freePairs(gpa, &proposed);
    switch (method) {
        .append => {
            if (proposed.items.len >= max_pairs) return error.SearchParamsLimit;
            const new_name = try gpa.dupe(u8, name.?);
            errdefer gpa.free(new_name);
            const new_value = try gpa.dupe(u8, value.?);
            errdefer gpa.free(new_value);
            try proposed.append(gpa, .{ .name = new_name, .value = new_value });
        },
        .delete => {
            var index: usize = 0;
            while (index < proposed.items.len) {
                const pair = proposed.items[index];
                if (std.mem.eql(u8, pair.name, name.?) and (value == null or std.mem.eql(u8, pair.value, value.?))) {
                    gpa.free(pair.name);
                    gpa.free(pair.value);
                    _ = proposed.orderedRemove(index);
                } else index += 1;
            }
        },
        .set => {
            var found = false;
            var index: usize = 0;
            while (index < proposed.items.len) {
                const pair = &proposed.items[index];
                if (!std.mem.eql(u8, pair.name, name.?)) {
                    index += 1;
                    continue;
                }
                if (!found) {
                    const replacement = try gpa.dupe(u8, value.?);
                    gpa.free(pair.value);
                    pair.value = replacement;
                    found = true;
                    index += 1;
                } else {
                    gpa.free(pair.name);
                    gpa.free(pair.value);
                    _ = proposed.orderedRemove(index);
                }
            }
            if (!found) {
                if (proposed.items.len >= max_pairs) return error.SearchParamsLimit;
                const new_name = try gpa.dupe(u8, name.?);
                errdefer gpa.free(new_name);
                const new_value = try gpa.dupe(u8, value.?);
                errdefer gpa.free(new_value);
                try proposed.append(gpa, .{ .name = new_name, .value = new_value });
            }
        },
        .sort => std.mem.sort(Pair, proposed.items, {}, utf16Less),
        else => unreachable,
    }
    if (state.association) |association| try association.update(association.context, proposed.items);
    replacePairs(state, &proposed);
}
fn methodCall(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return methodValue(engine, this, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn methodValue(engine: *engine_mod.Engine, this: c.JSValue, method: Method, args: []c.JSValue) !c.JSValue {
    const state = try stateFor(engine, this);
    switch (method) {
        .size => return c.JS_NewInt64(engine.context, @intCast(state.pairs.items.len)),
        .toString => {
            const text = try serialize(engine.gpa, state.pairs.items);
            defer engine.gpa.free(text);
            return engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
        },
        .keys, .values, .entries => return createIterator(engine, this, @intFromEnum(method)),
        .sort => {
            try mutate(state, .sort, null, null);
            return c.pi_js_undefined();
        },
        .forEach => {
            if (args.len == 0 or !c.JS_IsFunction(engine.context, args[0])) return error.InvalidSearchParamsCallback;
            var index: usize = 0;
            while (index < state.pairs.items.len) : (index += 1) {
                if (index >= max_pairs) return error.SearchParamsLimit;
                const pair = state.pairs.items[index];
                const value = try engine.checked(c.JS_NewStringLen(engine.context, pair.value.ptr, pair.value.len));
                defer engine.freeValue(value);
                const name = try engine.checked(c.JS_NewStringLen(engine.context, pair.name.ptr, pair.name.len));
                defer engine.freeValue(name);
                var values = [_]c.JSValue{ value, name, this };
                const result = try engine.checked(c.JS_Call(engine.context, args[0], if (args.len > 1) args[1] else c.pi_js_undefined(), 3, &values));
                engine.freeValue(result);
            }
            return c.pi_js_undefined();
        },
        else => {},
    }
    if (args.len == 0 or ((method == .append or method == .set) and args.len < 2)) return error.MissingSearchParamsArgument;
    const name = try usvString(engine, args[0]);
    defer engine.gpa.free(name);
    const has_value = method == .append or method == .set or ((method == .has or method == .delete) and args.len > 1 and !c.JS_IsUndefined(args[1]));
    const value = if (has_value) try usvString(engine, args[1]) else null;
    defer if (value) |text| engine.gpa.free(text);
    switch (method) {
        .append, .delete, .set => {
            try mutate(state, method, name, value);
            return c.pi_js_undefined();
        },
        .get => {
            for (state.pairs.items) |pair| if (std.mem.eql(u8, pair.name, name)) return engine.checked(c.JS_NewStringLen(engine.context, pair.value.ptr, pair.value.len));
            return c.pi_js_null();
        },
        .has => {
            for (state.pairs.items) |pair| if (std.mem.eql(u8, pair.name, name) and (value == null or std.mem.eql(u8, pair.value, value.?))) return c.pi_js_bool(engine.context, 1);
            return c.pi_js_bool(engine.context, 0);
        },
        .getAll => {
            const result = try engine.checked(c.JS_NewArray(engine.context));
            errdefer engine.freeValue(result);
            var count: u32 = 0;
            for (state.pairs.items) |pair| {
                if (!std.mem.eql(u8, pair.name, name)) continue;
                const item = try engine.checked(c.JS_NewStringLen(engine.context, pair.value.ptr, pair.value.len));
                if (c.JS_SetPropertyUint32(engine.context, result, count, item) < 0) return error.JavaScriptException;
                count += 1;
            }
            return result;
        },
        else => unreachable,
    }
}
fn iteratorFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Iterator = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.params);
    state.engine.gpa.destroy(state);
}
fn iteratorMark(runtime: ?*c.JSRuntime, value: c.JSValue, mark_value: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Iterator = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.params, mark_value);
}
fn createIterator(engine: *engine_mod.Engine, params: c.JSValue, kind: c_int) !c.JSValue {
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.url_search_params_iterator_class));
    errdefer engine.freeValue(object);
    const state = try engine.gpa.create(Iterator);
    state.* = .{ .engine = engine, .params = c.JS_DupValue(engine.context, params), .kind = kind };
    _ = c.JS_SetOpaque(object, state);
    return object;
}
fn iteratorNext(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return iteratorNextValue(engine, this) catch |err| fail(engine, err);
}
fn iteratorNextValue(engine: *engine_mod.Engine, this: c.JSValue) !c.JSValue {
    const iterator: *Iterator = @ptrCast(@alignCast(c.JS_GetOpaque(this, engine.url_search_params_iterator_class) orelse return error.IllegalSearchParamsIterator));
    const state = try stateFor(engine, iterator.params);
    const done = iterator.index >= state.pairs.items.len;
    const value = if (done) c.pi_js_undefined() else item: {
        const pair = state.pairs.items[iterator.index];
        if (iterator.kind == @intFromEnum(Method.keys)) break :item try engine.checked(c.JS_NewStringLen(engine.context, pair.name.ptr, pair.name.len));
        if (iterator.kind == @intFromEnum(Method.values)) break :item try engine.checked(c.JS_NewStringLen(engine.context, pair.value.ptr, pair.value.len));
        const output = try engine.checked(c.JS_NewArray(engine.context));
        errdefer engine.freeValue(output);
        const name = try engine.checked(c.JS_NewStringLen(engine.context, pair.name.ptr, pair.name.len));
        if (c.JS_SetPropertyUint32(engine.context, output, 0, name) < 0) return error.JavaScriptException;
        const text = try engine.checked(c.JS_NewStringLen(engine.context, pair.value.ptr, pair.value.len));
        if (c.JS_SetPropertyUint32(engine.context, output, 1, text) < 0) return error.JavaScriptException;
        break :item output;
    };
    defer engine.freeValue(value);
    const result = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(result);
    if (c.JS_DefinePropertyValueStr(engine.context, result, "value", c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0 or c.JS_DefinePropertyValueStr(engine.context, result, "done", c.pi_js_bool(engine.context, @intFromBool(done)), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    if (!done) iterator.index += 1;
    return result;
}
fn defineSymbol(engine: *engine_mod.Engine, object: c.JSValue, symbol: c.JSValue, value: c.JSValue, flags: c_int) !void {
    const atom = c.JS_ValueToAtom(engine.context, symbol);
    if (atom == c.JS_ATOM_NULL) {
        engine.freeValue(value);
        return error.OutOfMemory;
    }
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, object, atom, value, flags) < 0) return error.JavaScriptException;
}
pub fn install(engine: *engine_mod.Engine) !void {
    if (engine.url_search_params_class != 0) return error.URLSearchParamsAlreadyInstalled;
    var params_class: c.JSClassID = 0;
    var iterator_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &params_class);
    _ = c.JS_NewClassID(engine.runtime, &iterator_class);
    const definition: c.JSClassDef = .{ .class_name = "URLSearchParams", .finalizer = finalizer, .gc_mark = mark, .call = null, .exotic = null };
    const iterator_definition: c.JSClassDef = .{ .class_name = "URLSearchParamsIterator", .finalizer = iteratorFinalizer, .gc_mark = iteratorMark, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, params_class, &definition) < 0 or c.JS_NewClass(engine.runtime, iterator_class, &iterator_definition) < 0) return error.SearchParamsClassFailed;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const symbol = try property(engine, global, "Symbol");
    defer engine.freeValue(symbol);
    const iterator_symbol = try property(engine, symbol, "iterator");
    defer engine.freeValue(iterator_symbol);
    const tag = try property(engine, symbol, "toStringTag");
    defer engine.freeValue(tag);
    const prototype = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(prototype);
    c.JS_SetClassProto(engine.context, params_class, c.JS_DupValue(engine.context, prototype));
    const array = try property(engine, global, "Array");
    defer engine.freeValue(array);
    const array_prototype = try property(engine, array, "prototype");
    defer engine.freeValue(array_prototype);
    const values = try property(engine, array_prototype, "values");
    defer engine.freeValue(values);
    const empty_array = try engine.checked(c.JS_NewArray(engine.context));
    defer engine.freeValue(empty_array);
    const array_iterator = try engine.checked(c.JS_Call(engine.context, values, empty_array, 0, null));
    defer engine.freeValue(array_iterator);
    const array_iterator_prototype = try engine.checked(c.JS_GetPrototype(engine.context, array_iterator));
    defer engine.freeValue(array_iterator_prototype);
    const base_iterator_prototype = try engine.checked(c.JS_GetPrototype(engine.context, array_iterator_prototype));
    defer engine.freeValue(base_iterator_prototype);
    const iterator_prototype = try engine.checked(c.JS_NewObjectProto(engine.context, base_iterator_prototype));
    defer engine.freeValue(iterator_prototype);
    c.JS_SetClassProto(engine.context, iterator_class, c.JS_DupValue(engine.context, iterator_prototype));
    if (c.JS_DefinePropertyValueStr(engine.context, iterator_prototype, "next", c.JS_NewCFunction(engine.context, iteratorNext, "next", 0), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    try defineSymbol(engine, iterator_prototype, tag, c.JS_NewString(engine.context, "URLSearchParams Iterator"), c.JS_PROP_CONFIGURABLE);
    var constructor_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &constructor_class);
    const constructor_definition: c.JSClassDef = .{ .class_name = "URLSearchParamsConstructor", .finalizer = constructorFinalizer, .gc_mark = constructorMark, .call = construct, .exotic = null };
    if (c.JS_NewClass(engine.runtime, constructor_class, &constructor_definition) < 0) return error.SearchParamsClassFailed;
    const function = try property(engine, global, "Function");
    defer engine.freeValue(function);
    const function_prototype = try property(engine, function, "prototype");
    defer engine.freeValue(function_prototype);
    const constructor = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, constructor_class));
    defer engine.freeValue(constructor);
    const state = try engine.gpa.create(Constructor);
    state.* = .{ .engine = engine, .prototype = c.JS_DupValue(engine.context, prototype), .iterator = c.JS_DupValue(engine.context, iterator_symbol) };
    _ = c.JS_SetOpaque(constructor, state);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "name", c.JS_NewString(engine.context, "URLSearchParams"), c.JS_PROP_CONFIGURABLE) < 0 or c.JS_DefinePropertyValueStr(engine.context, constructor, "length", c.JS_NewInt32(engine.context, 0), c.JS_PROP_CONFIGURABLE) < 0 or c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const method: Method = @enumFromInt(field.value);
        const length: c_int = if (method == .append or method == .set) 2 else if (method == .get or method == .getAll or method == .delete or method == .has or method == .forEach) 1 else 0;
        const callback = try engine.checked(c.pi_js_function_magic(engine.context, methodCall, if (method == .size) "get size" else name.ptr, length, @intCast(field.value)));
        if (method == .size) {
            const atom = c.JS_NewAtom(engine.context, name.ptr);
            if (atom == c.JS_ATOM_NULL) {
                engine.freeValue(callback);
                return error.OutOfMemory;
            }
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, callback, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
        } else {
            if (method == .entries) try defineSymbol(engine, prototype, iterator_symbol, c.JS_DupValue(engine.context, callback), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
            if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, callback, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
    }
    try defineSymbol(engine, prototype, tag, c.JS_NewString(engine.context, "URLSearchParams"), c.JS_PROP_CONFIGURABLE);
    if (c.JS_DefinePropertyValueStr(engine.context, global, "URLSearchParams", c.JS_DupValue(engine.context, constructor), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    engine.url_search_params_class = params_class;
    engine.url_search_params_iterator_class = iterator_class;
}

test "native URLSearchParams form parsing ordered pairs duplicate selection mutations live iteration and UTF16 sorting" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const value = try engine.eval(
        \\const p=new URLSearchParams('?a=1&a=2&b=&=blank&empty');if(p.size!==5||String(p)!=='a=1&a=2&b=&=blank&empty='||p.get('missing')!==null||JSON.stringify(p.getAll('a'))!=='["1","2"]')throw Error('parse');const bad=new URLSearchParams('q=hello+world&x=%E0%A4%A&tilde=~&plus=%2b');if(String(bad)!=='q=hello+world&x=%EF%BF%BD%25A&tilde=%7E&plus=%2B')throw Error('codec');const x=new URLSearchParams([['b',1],['a',2],['a',3]]);x.sort();x.delete('a','2');x.append('a',4);x.set('b',5);if(String(x)!=='a=3&b=5&a=4'||!x.has('a','4')||x.has('a','2'))throw Error('mutations');const i=x.entries();x.append('late',6);if(JSON.stringify([...i])!=='[["a","3"],["b","5"],["a","4"],["late","6"]]')throw Error('live iterator');const s=new URLSearchParams([['\ue000','bmp'],['\ud800\udc00','astral'],['a','first'],['a','last']]);s.sort();if([...s.values()].join(',')!=='first,last,astral,bmp')throw Error('UTF16 stable order');if(URLSearchParams.prototype[Symbol.iterator]!==URLSearchParams.prototype.entries||Object.prototype.toString.call(p)!=='[object URLSearchParams]')throw Error('symbols');
    , "search-params.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
}
test "native URLSearchParams constructor iterables records original errors brands and reentrant conversions" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const value = engine.eval(
        \\const original={},record={};record['\ud800']='first';record['\ud801']='last';const p=new URLSearchParams(record);if(String(p)!=='%EF%BF%BD=last')throw Error('USV record collisions');if(String(new URLSearchParams(null))!==''||String(new URLSearchParams(undefined))!=='')throw Error('null');for(const tuple of [['ab'],[['a',1,2]]]){let caught=false;try{new URLSearchParams(tuple)}catch(e){caught=e instanceof TypeError}if(!caught)throw Error('tuple accepted')}let closed=0;function* sequence(){try{yield [{toString(){throw original}},'v']}finally{closed++}}try{new URLSearchParams(sequence());throw Error('missing error')}catch(e){if(e!==original)throw e}if(closed!==1)throw Error('iterator not closed');for(const input of [{get [Symbol.iterator](){throw original}},{get key(){throw original}}]){try{new URLSearchParams(input);throw Error('getter accepted')}catch(e){if(e!==original)throw e}}const q=new URLSearchParams('a=1');q.set({toString(){q.append('inner',2);return'a'}},3);if(String(q)!=='a=3&inner=2')throw Error('reentrant mutation');let calls=[];q.forEach((value,name,self)=>{calls.push(name+value);if(name==='a')self.append('late',4)});if(calls.join(',')!=='a3,inner2,late4')throw Error('live forEach');for(const receiver of [{},new Proxy(q,{})]){let branded=false;try{URLSearchParams.prototype.get.call(receiver,'a')}catch(e){branded=e instanceof TypeError}if(!branded)throw Error('brand')}class Child extends URLSearchParams{}if(!(new Child('a=1') instanceof Child))throw Error('subclass');
    , "search-params-errors.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
        std.debug.print("Search params fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(value);
    c.JS_RunGC(engine.runtime);
}

test "native URLSearchParams runtime allocation failure retains live iterator position and pairs" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    var pairs = try parse(engine.gpa, "a=1&a=2");
    defer freePairs(engine.gpa, &pairs);
    const object = try create(engine, &pairs);
    defer engine.freeValue(object);
    const iterator = try createIterator(engine, object, @intFromEnum(Method.entries));
    defer engine.freeValue(iterator);
    const state: *Iterator = @ptrCast(@alignCast(c.JS_GetOpaque(iterator, engine.url_search_params_iterator_class).?));
    c.JS_SetMemoryLimit(engine.runtime, 1);
    try std.testing.expectError(error.JavaScriptException, iteratorNextValue(engine, iterator));
    try std.testing.expectEqual(@as(usize, 0), state.index);
    try std.testing.expectEqual(@as(usize, 2), (try stateFor(engine, object)).pairs.items.len);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    engine.beginInvocation();
    const result = try iteratorNextValue(engine, iterator);
    defer engine.freeValue(result);
    const encoded = try engine.stringify(result);
    defer engine.gpa.free(encoded);
    try std.testing.expectEqualStrings("{\"value\":[\"a\",\"1\"],\"done\":false}", encoded);
    try std.testing.expectEqual(@as(usize, 1), state.index);
    c.JS_RunGC(engine.runtime);
}

const AssociationProbe = struct {
    gpa: std.mem.Allocator,
    query: []u8,
    fail: bool = false,
    fn update(context: *anyopaque, pairs: []const Pair) !void {
        const self: *AssociationProbe = @ptrCast(@alignCast(context));
        if (self.fail) return error.OutOfMemory;
        const query = try serialize(self.gpa, pairs);
        self.gpa.free(self.query);
        self.query = query;
    }
};
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try install(engine);
    var pairs = try parse(gpa, "b=2&a=1&a=3&space=hello+world");
    defer freePairs(gpa, &pairs);
    const object = try create(engine, &pairs);
    defer engine.freeValue(object);
    const owner = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(owner);
    const state = try stateFor(engine, object);
    var associated: AssociationProbe = .{ .gpa = gpa, .query = try serialize(gpa, state.pairs.items) };
    defer gpa.free(associated.query);
    try associate(engine, object, .{ .owner = owner, .context = &associated, .update = AssociationProbe.update });
    try mutate(state, .append, "late", "value");
    try mutate(state, .set, "a", "replacement");
    try mutate(state, .delete, "b", null);
    try mutate(state, .sort, null, null);
    try std.testing.expectEqualStrings("a=replacement&late=value&space=hello+world", associated.query);
    const iterator = try createIterator(engine, object, @intFromEnum(Method.entries));
    defer engine.freeValue(iterator);
    const result = try iteratorNextValue(engine, iterator);
    defer engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native URLSearchParams every allocation failure releases constructor pairs associations and iterators" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
test "native URLSearchParams association update failures preserve both parameter and URL query state" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    var pairs = try parse(engine.gpa, "a=1");
    defer freePairs(engine.gpa, &pairs);
    const object = try create(engine, &pairs);
    defer engine.freeValue(object);
    const owner = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(owner);
    const state = try stateFor(engine, object);
    var associated: AssociationProbe = .{ .gpa = engine.gpa, .query = try serialize(engine.gpa, state.pairs.items), .fail = true };
    defer engine.gpa.free(associated.query);
    try associate(engine, object, .{ .owner = owner, .context = &associated, .update = AssociationProbe.update });
    try std.testing.expectError(error.OutOfMemory, mutate(state, .append, "b", "2"));
    try std.testing.expectEqual(@as(usize, 1), state.pairs.items.len);
    try std.testing.expectEqualStrings("a=1", associated.query);
    associated.fail = false;
    try mutate(state, .append, "b", "2");
    try std.testing.expectEqualStrings("a=1&b=2", associated.query);
    // The associated owner/params cycle is visible to the C collector.
    if (c.JS_SetPropertyStr(engine.context, owner, "params", c.JS_DupValue(engine.context, object)) < 0) return error.JavaScriptException;
    c.JS_RunGC(engine.runtime);
}
