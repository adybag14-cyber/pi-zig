//! Native Node24 bundled Undici7.21 Headers. JS values are owned and marked;
//! prototype brand checks never substitute records for an actual Headers store.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const web = @import("native_headers_webidl.zig");
const utf16 = @import("native_utf16.zig");
const c = em.c;
const cache_key = "\x00native-web-Headers";
pub const Guard = enum { none, request, response, immutable };
const Entry = struct { lower: c.JSValue, name: c.JSValue, value: c.JSValue };
const Root = struct {
    engine: *em.Engine,
    header_class: c.JSClassID,
    iterator_class: c.JSClassID,
    constructor: c.JSValue,
    prototype: c.JSValue,
    iterator_prototype: c.JSValue,
    has_instance: c.JSValue,
};
const State = struct { engine: *em.Engine, owner: c.JSValue, entries: std.ArrayList(Entry) = .empty, cookies: std.ArrayList(c.JSValue) = .empty, guard: Guard = .none };
const Iter = struct { engine: *em.Engine, owner: c.JSValue, target: c.JSValue, position: usize = 0, kind: Kind };
const Kind = enum(c_int) { append, delete, get, has, set, getSetCookie, keys, values, entries, forEach, next, inspect };
fn rootOf(value: c.JSValue) *Root {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn freeRoot(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const root: *Root = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for ([_]c.JSValue{ root.constructor, root.prototype, root.iterator_prototype, root.has_instance }) |item| c.JS_FreeValueRT(runtime, item);
    root.engine.gpa.destroy(root);
}
fn markRoot(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const root: *Root = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for ([_]c.JSValue{ root.constructor, root.prototype, root.iterator_prototype, root.has_instance }) |item| c.JS_MarkValue(runtime, item, visit);
}
fn freeHeader(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.owner);
    for (state.entries.items) |entry| {
        c.JS_FreeValueRT(runtime, entry.lower);
        c.JS_FreeValueRT(runtime, entry.name);
        c.JS_FreeValueRT(runtime, entry.value);
    }
    for (state.cookies.items) |item| c.JS_FreeValueRT(runtime, item);
    state.entries.deinit(state.engine.gpa);
    state.cookies.deinit(state.engine.gpa);
    state.engine.gpa.destroy(state);
}
fn markHeader(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.owner, visit);
    for (state.entries.items) |entry| {
        c.JS_MarkValue(runtime, entry.lower, visit);
        c.JS_MarkValue(runtime, entry.name, visit);
        c.JS_MarkValue(runtime, entry.value, visit);
    }
    for (state.cookies.items) |item| c.JS_MarkValue(runtime, item, visit);
}
fn freeIterator(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const iter: *Iter = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, iter.owner);
    c.JS_FreeValueRT(runtime, iter.target);
    iter.engine.gpa.destroy(iter);
}
fn markIterator(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const iter: *Iter = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, iter.owner, visit);
    c.JS_MarkValue(runtime, iter.target, visit);
}
fn classId(engine: *em.Engine, name: [*:0]const u8, finalizer: *const c.JSClassFinalizer, marker: *const c.JSClassGCMark) !c.JSClassID {
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = name, .finalizer = finalizer, .gc_mark = marker };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    return id;
}
fn privateState(scope: *Scope, owner: c.JSValue, target: c.JSValue, guard: bool) !*State {
    const root = rootOf(owner);
    if (c.JS_GetOpaque(target, root.header_class)) |opaque_state| return @ptrCast(@alignCast(opaque_state));
    try web.typeError(scope, try scope.text(if (guard) "Cannot read private member #guard from an object whose class did not declare it" else "Cannot read private member #headersList from an object whose class did not declare it"), null);
}
fn brand(scope: *Scope, owner: c.JSValue, target: c.JSValue) !void {
    const root = rootOf(owner);
    const valid = try scope.call(root.has_instance, root.constructor, &.{target});
    if (!scope.truthy(valid)) try web.typeError(scope, try scope.text("Illegal invocation"), "ERR_INVALID_THIS");
}
pub fn setGuard(engine: *em.Engine, target: c.JSValue, guard: Guard) !void {
    const owner = engine.native_module_values.get(cache_key) orelse return error.HeadersNotInstalled;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    (try privateState(&scope, owner, target, true)).guard = guard;
}
pub fn isHeaders(engine: *em.Engine, value: c.JSValue) bool {
    const owner = engine.native_module_values.get(cache_key) orelse return false;
    return c.JS_GetOpaque(value, rootOf(owner).header_class) != null;
}
fn find(scope: *Scope, state: *State, lower: c.JSValue) ?usize {
    for (state.entries.items, 0..) |entry, position| if (scope.equal(entry.lower, lower)) return position;
    return null;
}
fn isCookie(scope: *Scope, lower: c.JSValue) !bool {
    return scope.equal(lower, try scope.text("set-cookie"));
}
fn trim(scope: *Scope, value: c.JSValue) !c.JSValue {
    var start: usize = 0;
    var end = try web.count(scope, value);
    while (end > start and try whitespace(scope, value, end - 1)) end -= 1;
    while (end > start and try whitespace(scope, value, start)) start += 1;
    if (start == 0 and end == try web.count(scope, value)) return value;
    return scope.invoke(value, "substring", &.{ web.number(scope, start), web.number(scope, end) });
}
fn whitespace(scope: *Scope, value: c.JSValue, position: usize) !bool {
    const result = try scope.invoke(value, "charCodeAt", &.{web.number(scope, position)});
    var code: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &code, result) < 0) return js.capture(scope.engine);
    return code == 10 or code == 13 or code == 9 or code == 32;
}
fn validate(scope: *Scope, value: c.JSValue, prefix: []const u8, name: bool) !void {
    const units = try utf16.unitsAlloc(scope.engine, value);
    defer scope.engine.gpa.free(units);
    var valid = if (name) units.len > 0 else true;
    for (units) |unit| {
        if (name) {
            if (unit > 127 or !(std.ascii.isAlphanumeric(@intCast(unit)) or std.mem.indexOfScalar(u8, "!#$%&'*+-.^_`|~", @intCast(unit)) != null)) valid = false;
        } else if (unit == 0 or unit == 10 or unit == 13) valid = false;
    }
    if (!valid) {
        var message = try scope.concat(try scope.text(prefix), try scope.text(": \""));
        message = try scope.concat(message, value);
        try web.typeError(scope, try scope.concat(message, try scope.text(if (name) "\" is an invalid header name." else "\" is an invalid header value.")), null);
    }
}
fn store(scope: *Scope, state: *State, name: c.JSValue, value: c.JSValue, replace: bool) !void {
    const engine = scope.engine;
    const lower = try scope.invoke(name, "toLowerCase", &.{});
    const existing = find(scope, state, lower);
    const cookie = try isCookie(scope, lower);
    const combined = if (!replace and existing != null) try scope.concat(try scope.concat(state.entries.items[existing.?].value, try scope.text(if (scope.equal(lower, try scope.text("cookie"))) "; " else ", ")), value) else value;
    // Complete host reservations before changing any owned list.
    if (existing == null) try state.entries.ensureUnusedCapacity(engine.gpa, 1);
    if (cookie) try state.cookies.ensureTotalCapacity(engine.gpa, if (replace) 1 else state.cookies.items.len + 1);
    if (existing) |position| {
        const entry = &state.entries.items[position];
        engine.freeValue(entry.value);
        entry.value = c.JS_DupValue(engine.context, combined);
        if (replace) {
            engine.freeValue(entry.name);
            entry.name = c.JS_DupValue(engine.context, name);
        }
    } else state.entries.appendAssumeCapacity(.{ .lower = c.JS_DupValue(engine.context, lower), .name = c.JS_DupValue(engine.context, name), .value = c.JS_DupValue(engine.context, combined) });
    if (cookie) {
        if (replace) {
            for (state.cookies.items) |item| engine.freeValue(item);
            state.cookies.clearRetainingCapacity();
        }
        state.cookies.appendAssumeCapacity(c.JS_DupValue(engine.context, value));
    }
}
fn append(scope: *Scope, owner: c.JSValue, target: c.JSValue, name: c.JSValue, value: c.JSValue, replace: bool) !void {
    const normalized = try trim(scope, value);
    const prefix = if (replace) "Headers.set" else "Headers.append";
    try validate(scope, name, prefix, true);
    try validate(scope, normalized, prefix, false);
    const state = try privateState(scope, owner, target, true);
    if (state.guard == .immutable) try web.typeError(scope, try scope.text("immutable"), null);
    try store(scope, state, name, normalized, replace);
}
fn newIterator(scope: *Scope, owner: c.JSValue, target: c.JSValue, kind: Kind) !c.JSValue {
    const root = rootOf(owner);
    const result = try scope.own(try scope.engine.checked(c.JS_NewObjectProtoClass(scope.engine.context, root.iterator_prototype, root.iterator_class)));
    const iter = try scope.engine.gpa.create(Iter);
    iter.* = .{ .engine = scope.engine, .owner = c.JS_DupValue(scope.engine.context, owner), .target = c.JS_DupValue(scope.engine.context, target), .kind = kind };
    _ = c.JS_SetOpaque(result, iter);
    return result;
}
fn sorted(scope: *Scope, state: *State) !c.JSValue {
    const indices = try scope.engine.gpa.alloc(usize, state.entries.items.len);
    defer scope.engine.gpa.free(indices);
    for (indices, 0..) |*slot, position| slot.* = position;
    // Small-list insertion sort compares actual JavaScript strings.
    for (@min(1, indices.len)..indices.len) |position| {
        const selected = indices[position];
        var cursor = position;
        while (cursor > 0) {
            const less = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 4, state.entries.items[selected].lower, state.entries.items[indices[cursor - 1]].lower)));
            if (!scope.truthy(less)) break;
            indices[cursor] = indices[cursor - 1];
            cursor -= 1;
        }
        indices[cursor] = selected;
    }
    const output = try scope.array();
    var position: u32 = 0;
    for (indices) |entry_index| {
        const entry = state.entries.items[entry_index];
        if (try isCookie(scope, entry.lower)) {
            for (state.cookies.items) |cookie| {
                const pair = try scope.array();
                try scope.index(pair, 0, entry.lower);
                try scope.index(pair, 1, cookie);
                try scope.index(output, position, pair);
                position += 1;
            }
        } else {
            const pair = try scope.array();
            try scope.index(pair, 0, entry.lower);
            try scope.index(pair, 1, entry.value);
            try scope.index(output, position, pair);
            position += 1;
        }
    }
    return output;
}
fn next(scope: *Scope, owner: c.JSValue, target: c.JSValue) !c.JSValue {
    const opaque_iter = c.JS_GetOpaque(target, rootOf(owner).iterator_class) orelse {
        try web.typeError(scope, try scope.text("'next' called on an object that does not implement interface Headers Iterator."), null);
    };
    const iter: *Iter = @ptrCast(@alignCast(opaque_iter));
    const state = try privateState(scope, owner, iter.target, false);
    const items = try sorted(scope, state);
    const done = iter.position >= try web.count(scope, items);
    var value = c.pi_js_undefined();
    if (!done) {
        const pair = try web.index(scope, items, iter.position);
        iter.position += 1;
        value = switch (iter.kind) {
            .keys => try web.index(scope, pair, 0),
            .values => try web.index(scope, pair, 1),
            else => pair,
        };
    }
    const result = try scope.object();
    try scope.put(result, "value", value);
    try scope.put(result, "done", c.JS_NewBool(scope.engine.context, done));
    return result;
}
fn operate(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, kind: Kind) anyerror!c.JSValue {
    if (kind == .next) return next(scope, owner, receiver);
    if (kind == .inspect) {
        const options = if (args.len > 1) args[1] else c.pi_js_undefined();
        const depth = if (args.len > 0) args[0] else c.pi_js_undefined();
        if (c.JS_IsNull(try scope.get(options, "depth")) or c.JS_IsUndefined(try scope.get(options, "depth"))) try scope.set(options, "depth", depth);
        const state = try privateState(scope, owner, receiver, false);
        const record = try scope.object();
        for (state.entries.items) |entry| try js.setKey(scope.engine, record, entry.name, entry.value);
        var integer_depth: i32 = 2;
        if (!c.JS_IsUndefined(depth) and c.JS_ToInt32(scope.engine.context, &integer_depth, depth) < 0) return js.capture(scope.engine);
        const bytes = try @import("node_event_inspect.zig").inspect(scope.engine, record, integer_depth);
        defer scope.engine.gpa.free(bytes);
        return scope.concat(try scope.text("Headers "), try scope.text(bytes));
    }
    try brand(scope, owner, receiver);
    if (kind == .keys or kind == .values or kind == .entries) return newIterator(scope, owner, receiver, kind);
    if (kind == .getSetCookie) {
        const state = try privateState(scope, owner, receiver, false);
        const result = try scope.array();
        for (state.cookies.items, 0..) |item, position| try scope.index(result, @intCast(position), item);
        return result;
    }
    if (kind == .forEach) {
        try web.arity(scope, args.len, 1, "Headers.forEach");
        if (!c.JS_IsFunction(scope.engine.context, args[0])) try web.typeError(scope, try scope.text("Failed to execute 'forEach' on 'Headers': parameter 1 is not of type 'Function'."), null);
        const this_arg = if (args.len < 2 or c.JS_IsUndefined(args[1])) try scope.own(c.JS_GetGlobalObject(scope.engine.context)) else args[1];
        const iterator = try newIterator(scope, owner, receiver, .entries);
        while (true) {
            // Iteration roots are released each turn, preserving live mutations.
            var turn: Scope = .{ .engine = scope.engine };
            defer turn.deinit();
            const step = try next(&turn, owner, iterator);
            if (turn.truthy(try turn.get(step, "done"))) break;
            const pair = try turn.get(step, "value");
            _ = try turn.invoke(args[0], "call", &.{ this_arg, try web.index(&turn, pair, 1), try web.index(&turn, pair, 0), receiver });
        }
        return c.pi_js_undefined();
    }
    const prefix = switch (kind) {
        .append => "Headers.append",
        .delete => "Headers.delete",
        .get => "Headers.get",
        .has => "Headers.has",
        .set => "Headers.set",
        else => unreachable,
    };
    try web.arity(scope, args.len, if (kind == .append or kind == .set) 2 else 1, prefix);
    const name = try web.byteString(scope, args[0], prefix, try scope.text("name"));
    if (kind == .append or kind == .set) {
        const value = try web.byteString(scope, args[1], prefix, try scope.text("value"));
        try append(scope, owner, receiver, name, value, kind == .set);
        return c.pi_js_undefined();
    }
    try validate(scope, name, prefix, true);
    const state = try privateState(scope, owner, receiver, kind == .delete);
    if (kind == .delete and state.guard == .immutable) try web.typeError(scope, try scope.text("immutable"), null);
    const lower = try scope.invoke(name, "toLowerCase", &.{});
    const found = find(scope, state, lower);
    if (kind == .get) return if (found) |position| state.entries.items[position].value else c.pi_js_null();
    if (kind == .has) return c.JS_NewBool(scope.engine.context, found != null);
    if (found) |position| {
        const entry = state.entries.orderedRemove(position);
        scope.engine.freeValue(entry.lower);
        scope.engine.freeValue(entry.name);
        scope.engine.freeValue(entry.value);
        if (try isCookie(scope, lower)) {
            for (state.cookies.items) |item| scope.engine.freeValue(item);
            state.cookies.clearRetainingCapacity();
        }
    }
    return c.pi_js_undefined();
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = operate(&scope, captures[0], receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic)) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
        return c.JS_ThrowInternalError(context, "Native Headers: %s", @as([*:0]const u8, @errorName(err)));
    };
    return c.JS_DupValue(context, result);
}
fn create(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = captures[0];
    const root = rootOf(owner);
    const prototype = try scope.get(target, "prototype");
    const result = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, if (c.JS_IsObject(prototype)) prototype else root.prototype, root.header_class)));
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .owner = c.JS_DupValue(engine.context, owner) };
    _ = c.JS_SetOpaque(result, state);
    if (args.len > 0 and !c.JS_IsUndefined(args[0])) try initialize(&scope, owner, result, args[0]);
    return c.JS_DupValue(engine.context, result);
}
fn originalPairs(scope: *Scope, state: *State) !c.JSValue {
    const output = try scope.array();
    for (state.entries.items) |entry| {
        if (try isCookie(scope, entry.lower)) {
            for (state.cookies.items) |cookie| {
                const pair = try scope.array();
                try scope.index(pair, 0, entry.name);
                try scope.index(pair, 1, cookie);
                _ = try scope.invoke(output, "push", &.{pair});
            }
        } else {
            const pair = try scope.array();
            try scope.index(pair, 0, entry.name);
            try scope.index(pair, 1, entry.value);
            _ = try scope.invoke(output, "push", &.{pair});
        }
    }
    return output;
}
fn convert(scope: *Scope, owner: c.JSValue, init: c.JSValue, prefix: []const u8, argument: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(init)) try web.typeError(scope, try scope.text("Headers constructor: Argument 1 could not be converted to one of: sequence<sequence<ByteString>>, record<ByteString, ByteString>."), null);
    const iterator = try scope.own(try js.getKey(scope.engine, init, try web.iteratorSymbol(scope)));
    return selected: {
        if (!c.JS_IsProxy(init) and scope.equal(iterator, try scope.get(rootOf(owner).prototype, "entries"))) {
            if (c.JS_GetOpaque(init, rootOf(owner).header_class)) |opaque_state| break :selected try originalPairs(scope, @ptrCast(@alignCast(opaque_state)));
        }
        if (c.JS_IsFunction(scope.engine.context, iterator)) {
            const bound = try scope.invoke(iterator, "bind", &.{init});
            break :selected try web.sequence(scope, init, true, prefix, argument, bound);
        }
        break :selected try web.record(scope, init, prefix, argument);
    };
}
/// WebIDL HeadersInit conversion deliberately does not validate names/values
/// or pair lengths. ResponseInit and RequestInit convert before fill does so.
/// The result is owned by the supplied scope.
pub fn convertInit(scope: *Scope, init: c.JSValue, prefix: []const u8, argument: c.JSValue) !c.JSValue {
    try install(scope.engine);
    return convert(scope, scope.engine.native_module_values.get(cache_key).?, init, prefix, argument);
}
fn initialize(scope: *Scope, owner: c.JSValue, target: c.JSValue, init: c.JSValue) !void {
    const converted = try convert(scope, owner, init, "Headers constructor", try scope.text("init"));
    if (c.JS_IsArray(converted)) {
        for (0..try web.count(scope, converted)) |position| {
            const pair = try web.index(scope, converted, position);
            const length = try web.count(scope, pair);
            if (length != 2) {
                const message = try scope.concat(try scope.concat(try scope.text("Headers constructor: expected name/value pair to be length 2, found "), web.number(scope, length)), try scope.text("."));
                try web.typeError(scope, message, null);
            }
            try append(scope, owner, target, try web.index(scope, pair, 0), try web.index(scope, pair, 1), false);
        }
    } else {
        const keys = try scope.invoke(try scope.global("Object"), "keys", &.{converted});
        for (0..try web.count(scope, keys)) |position| {
            const key = try web.index(scope, keys, position);
            try append(scope, owner, target, key, try scope.own(try js.getKey(scope.engine, converted, key)), false);
        }
    }
}
fn symbolProperty(scope: *Scope, object: c.JSValue, symbol: c.JSValue, value: c.JSValue, flags: c_int) !void {
    const atom = try js.atom(scope.engine, symbol);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, object, atom, c.JS_DupValue(scope.engine.context, value), flags) < 0) return js.capture(scope.engine);
}
fn function(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, length: c_int, kind: Kind) !c.JSValue {
    // Undici's iteratorMixin defines ordinary functions, whereas Headers and
    // FastIterableIterator class methods are nonconstructible class methods.
    if (kind == .keys or kind == .values or kind == .entries or kind == .forEach) {
        return scope.own(try @import("native_node_function.zig").create(scope.engine, name, length, ordinary, &.{ owner, c.JS_NewInt32(scope.engine.context, @intFromEnum(kind)) }));
    }
    var captures = [_]c.JSValue{owner};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, name, length, @intFromEnum(kind), 1, &captures)));
}
fn ordinary(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var kind: i32 = 0;
    if (c.JS_ToInt32(engine.context, &kind, captures[1]) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, try operate(&scope, captures[0], receiver, args, @enumFromInt(kind)));
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains(cache_key)) return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const root_class = try classId(engine, "Native Headers Owner", freeRoot, markRoot);
    const owner = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, root_class)));
    const root = try engine.gpa.create(Root);
    root.* = .{ .engine = engine, .header_class = 0, .iterator_class = 0, .constructor = c.pi_js_undefined(), .prototype = c.pi_js_undefined(), .iterator_prototype = c.pi_js_undefined(), .has_instance = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(owner, root);
    root.header_class = try classId(engine, "Headers", freeHeader, markHeader);
    root.iterator_class = try classId(engine, "Headers Iterator", freeIterator, markIterator);
    root.prototype = try js.object(engine);
    const array = try scope.array();
    const array_iterator = try scope.invoke(array, "values", &.{});
    const array_iterator_proto = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, array_iterator)));
    const iterator_proto = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, array_iterator_proto)));
    root.iterator_prototype = try engine.checked(c.JS_NewObjectProto(engine.context, iterator_proto));
    const symbols = try scope.global("Symbol");
    const has_instance_symbol = try scope.get(symbols, "hasInstance");
    root.has_instance = try js.getKey(engine, try scope.get(try scope.global("Function"), "prototype"), has_instance_symbol);
    root.constructor = try @import("native_class.zig").constructor(engine, "Headers", 0, root.prototype, create, &.{owner});
    inline for (.{ .{ "append", 2, Kind.append }, .{ "delete", 1, Kind.delete }, .{ "get", 1, Kind.get }, .{ "has", 1, Kind.has }, .{ "set", 2, Kind.set }, .{ "getSetCookie", 0, Kind.getSetCookie }, .{ "keys", 0, Kind.keys }, .{ "values", 0, Kind.values }, .{ "entries", 0, Kind.entries }, .{ "forEach", 1, Kind.forEach } }) |spec| try scope.put(root.prototype, spec[0], try function(&scope, owner, spec[0], spec[1], spec[2]));
    try scope.put(root.iterator_prototype, "next", try function(&scope, owner, "next", 0, .next));
    const inspect_symbol = try scope.invoke(symbols, "for", &.{try scope.text("nodejs.util.inspect.custom")});
    try symbolProperty(&scope, root.prototype, inspect_symbol, try function(&scope, owner, "[nodejs.util.inspect.custom]", 2, .inspect), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    try symbolProperty(&scope, root.prototype, try web.iteratorSymbol(&scope), try scope.get(root.prototype, "entries"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    const tag = try scope.get(symbols, "toStringTag");
    try symbolProperty(&scope, root.prototype, tag, try scope.text("Headers"), c.JS_PROP_CONFIGURABLE);
    try symbolProperty(&scope, root.iterator_prototype, tag, try scope.text("Headers Iterator"), c.JS_PROP_CONFIGURABLE);
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    if (c.JS_DefinePropertyValueStr(engine.context, global, "Headers", c.JS_DupValue(engine.context, root.constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    engine.native_module_values.putAssumeCapacity(cache_key, c.JS_DupValue(engine.context, owner));
}
/// Standard HeadersInit conversion, despite the convenience name. Caller owns
/// the genuine Headers result. SDK nullable tombstones belong to SDK callers.
pub fn fromRecord(engine: *em.Engine, init: c.JSValue) !c.JSValue {
    try install(engine);
    const root = rootOf(engine.native_module_values.get(cache_key).?);
    var args = [_]c.JSValue{init};
    return engine.checked(c.JS_CallConstructor(engine.context, root.constructor, 1, &args));
}
