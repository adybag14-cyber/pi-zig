//! Source-authored native Undici7.21 FormData for the unqualified Body phase.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const web = @import("native_headers_webidl.zig");
const idl = @import("native_web_idl.zig");
const blob = @import("native_web_blob.zig");
const c = em.c;
const cache_key = "\x00native-web-FormData";
pub const Entry = struct { name: c.JSValue, value: c.JSValue };
const State = struct { engine: *em.Engine, owner: c.JSValue, entries: std.ArrayList(Entry) = .empty };
const Iter = struct { engine: *em.Engine, owner: c.JSValue, target: c.JSValue, position: usize = 0, kind: Kind };
const Slot = enum(usize) { constructor, prototype, iterator_prototype, has_instance, blob_ctor, file_ctor };
const Root = struct { engine: *em.Engine, class: c.JSClassID, iterator_class: c.JSClassID, values: [6]c.JSValue };
const Kind = enum(c_int) { append, delete, get, getAll, has, set, keys, values, entries, forEach, next };
fn rootOf(owner: c.JSValue) *Root {
    return @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
}
fn rootValue(root: *Root, slot: Slot) c.JSValue {
    return root.values[@intFromEnum(slot)];
}
fn replace(root: *Root, slot: Slot, value: c.JSValue) void {
    root.engine.freeValue(root.values[@intFromEnum(slot)]);
    root.values[@intFromEnum(slot)] = value;
}
fn freeRoot(runtime: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const root: *Root = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for (root.values) |item| c.JS_FreeValueRT(runtime, item);
    root.engine.gpa.destroy(root);
}
fn markRoot(runtime: ?*c.JSRuntime, owner: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const root: *Root = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for (root.values) |item| c.JS_MarkValue(runtime, item, visit);
}
fn freeState(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_FreeValueRT(runtime, state.owner);
    for (state.entries.items) |entry| {
        c.JS_FreeValueRT(runtime, entry.name);
        c.JS_FreeValueRT(runtime, entry.value);
    }
    state.entries.deinit(state.engine.gpa);
    state.engine.gpa.destroy(state);
}
fn markState(runtime: ?*c.JSRuntime, object: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_MarkValue(runtime, state.owner, visit);
    for (state.entries.items) |entry| {
        c.JS_MarkValue(runtime, entry.name, visit);
        c.JS_MarkValue(runtime, entry.value, visit);
    }
}
fn freeIter(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const iter: *Iter = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_FreeValueRT(runtime, iter.owner);
    c.JS_FreeValueRT(runtime, iter.target);
    iter.engine.gpa.destroy(iter);
}
fn markIter(runtime: ?*c.JSRuntime, object: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const iter: *Iter = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_MarkValue(runtime, iter.owner, visit);
    c.JS_MarkValue(runtime, iter.target, visit);
}
fn newClass(engine: *em.Engine, name: [*:0]const u8, finalizer: *const c.JSClassFinalizer, marker: *const c.JSClassGCMark) !c.JSClassID {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = name, .finalizer = finalizer, .gc_mark = marker };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    return class;
}
fn stateOf(scope: *Scope, owner: c.JSValue, target: c.JSValue) !*State {
    if (c.JS_GetOpaque(target, rootOf(owner).class)) |opaque_state| return @ptrCast(@alignCast(opaque_state));
    try web.typeError(scope, try scope.text("Cannot read private member #state from an object whose class did not declare it"), null);
}
fn brand(scope: *Scope, owner: c.JSValue, target: c.JSValue) !void {
    const root = rootOf(owner);
    if (!scope.truthy(try scope.call(rootValue(root, .has_instance), rootValue(root, .constructor), &.{target}))) try web.typeError(scope, try scope.text("Illegal invocation"), "ERR_INVALID_THIS");
}
pub fn isFormData(engine: *em.Engine, target: c.JSValue) bool {
    const owner = engine.native_module_values.get(cache_key) orelse return false;
    return c.JS_GetOpaque(target, rootOf(owner).class) != null;
}
fn find(scope: *Scope, state: *State, name: c.JSValue) ?usize {
    for (state.entries.items, 0..) |entry, position| if (scope.equal(entry.name, name)) return position;
    return null;
}
fn releaseEntry(engine: *em.Engine, entry: Entry) void {
    engine.freeValue(entry.name);
    engine.freeValue(entry.value);
}
fn fileFrom(scope: *Scope, owner: c.JSValue, value: c.JSValue, name: c.JSValue, options: c.JSValue) !c.JSValue {
    const parts = try scope.array();
    try scope.index(parts, 0, value);
    var args = [_]c.JSValue{ parts, name, options };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, rootValue(rootOf(owner), .file_ctor), args.len, &args)));
}
fn makeEntry(scope: *Scope, owner: c.JSValue, original: c.JSValue, filename: c.JSValue) !c.JSValue {
    if (c.JS_IsString(original)) return original;
    var value = original;
    const root = rootOf(owner);
    if (!scope.truthy(try scope.call(rootValue(root, .has_instance), rootValue(root, .file_ctor), &.{value}))) {
        const options = try scope.object();
        try scope.set(options, "type", try scope.get(value, "type"));
        value = try fileFrom(scope, owner, value, try scope.text("blob"), options);
    }
    if (!c.JS_IsUndefined(filename)) {
        const options = try scope.object();
        try scope.set(options, "type", try scope.get(value, "type"));
        try scope.set(options, "lastModified", try scope.get(value, "lastModified"));
        value = try fileFrom(scope, owner, value, filename, options);
    }
    return value;
}
fn newIterator(scope: *Scope, owner: c.JSValue, target: c.JSValue, kind: Kind) !c.JSValue {
    const root = rootOf(owner);
    const result = try scope.own(try scope.engine.checked(c.JS_NewObjectProtoClass(scope.engine.context, rootValue(root, .iterator_prototype), root.iterator_class)));
    const iter = try scope.engine.gpa.create(Iter);
    iter.* = .{ .engine = scope.engine, .owner = c.JS_DupValue(scope.engine.context, owner), .target = c.JS_DupValue(scope.engine.context, target), .kind = kind };
    _ = c.JS_SetOpaque(result, iter);
    return result;
}
fn next(scope: *Scope, owner: c.JSValue, target: c.JSValue) !c.JSValue {
    const opaque_iter = c.JS_GetOpaque(target, rootOf(owner).iterator_class) orelse {
        try web.typeError(scope, try scope.text("'next' called on an object that does not implement interface FormData Iterator."), null);
    };
    const iter: *Iter = @ptrCast(@alignCast(opaque_iter));
    const state = try stateOf(scope, owner, iter.target);
    const done = iter.position >= state.entries.items.len;
    var value = c.pi_js_undefined();
    if (!done) {
        const entry = state.entries.items[iter.position];
        iter.position += 1;
        value = switch (iter.kind) {
            .keys => entry.name,
            .values => entry.value,
            else => pair: {
                const array = try scope.array();
                try scope.index(array, 0, entry.name);
                try scope.index(array, 1, entry.value);
                break :pair array;
            },
        };
    }
    const result = try scope.object();
    try scope.put(result, "value", value);
    try scope.put(result, "done", c.JS_NewBool(scope.engine.context, done));
    return result;
}
fn operation(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, kind: Kind) anyerror!c.JSValue {
    if (kind == .next) return next(scope, owner, receiver);
    try brand(scope, owner, receiver);
    if (kind == .keys or kind == .values or kind == .entries) return newIterator(scope, owner, receiver, kind);
    if (kind == .forEach) {
        try web.arity(scope, args.len, 1, "FormData.forEach");
        if (!c.JS_IsFunction(scope.engine.context, args[0])) try web.typeError(scope, try scope.text("Failed to execute 'forEach' on 'FormData': parameter 1 is not of type 'Function'."), null);
        const this_arg = if (args.len < 2 or c.JS_IsUndefined(args[1])) try scope.own(c.JS_GetGlobalObject(scope.engine.context)) else args[1];
        const iterator = try newIterator(scope, owner, receiver, .entries);
        while (true) {
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
        .append => "FormData.append",
        .delete => "FormData.delete",
        .get => "FormData.get",
        .getAll => "FormData.getAll",
        .has => "FormData.has",
        .set => "FormData.set",
        else => unreachable,
    };
    try web.arity(scope, args.len, if (kind == .append or kind == .set) 2 else 1, prefix);
    const name = try idl.usvString(scope, args[0]);
    if (kind == .append or kind == .set) {
        const root = rootOf(owner);
        const is_blob = scope.truthy(try scope.call(rootValue(root, .has_instance), rootValue(root, .blob_ctor), &.{args[1]}));
        var value = args[1];
        var filename = c.pi_js_undefined();
        if (args.len == 3 or is_blob) {
            if (!is_blob) {
                const message = try scope.concat(try scope.concat(try scope.text(prefix), try scope.text(": Expected value (\"")), try web.stringify(scope, value));
                try web.typeError(scope, try scope.concat(message, try scope.text("\") to be an instance of Blob.")), null);
            }
            if (args.len > 2 and !c.JS_IsUndefined(args[2])) filename = try idl.usvString(scope, args[2]);
        } else value = try idl.usvString(scope, value);
        value = try makeEntry(scope, owner, value, filename);
        const state = try stateOf(scope, owner, receiver);
        const found = if (kind == .set) find(scope, state, name) else null;
        if (found) |position| {
            const replacement: Entry = .{ .name = c.JS_DupValue(scope.engine.context, name), .value = c.JS_DupValue(scope.engine.context, value) };
            releaseEntry(scope.engine, state.entries.items[position]);
            state.entries.items[position] = replacement;
            var cursor = position + 1;
            while (cursor < state.entries.items.len) {
                if (scope.equal(state.entries.items[cursor].name, name)) releaseEntry(scope.engine, state.entries.orderedRemove(cursor)) else cursor += 1;
            }
        } else {
            try state.entries.ensureUnusedCapacity(scope.engine.gpa, 1);
            state.entries.appendAssumeCapacity(.{ .name = c.JS_DupValue(scope.engine.context, name), .value = c.JS_DupValue(scope.engine.context, value) });
        }
        return c.pi_js_undefined();
    }
    const state = try stateOf(scope, owner, receiver);
    const found = find(scope, state, name);
    if (kind == .get) return if (found) |position| state.entries.items[position].value else c.pi_js_null();
    if (kind == .has) return c.JS_NewBool(scope.engine.context, found != null);
    if (kind == .getAll) {
        const result = try scope.array();
        var position: u32 = 0;
        for (state.entries.items) |entry| if (scope.equal(entry.name, name)) {
            try scope.index(result, position, entry.value);
            position += 1;
        };
        return result;
    }
    var position: usize = 0;
    while (position < state.entries.items.len) {
        if (scope.equal(state.entries.items[position].name, name)) releaseEntry(scope.engine, state.entries.orderedRemove(position)) else position += 1;
    }
    return c.pi_js_undefined();
}
fn fail(engine: *em.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowInternalError(engine.context, "Native FormData: %s", @as([*:0]const u8, @errorName(err)));
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, kind: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = operation(&scope, captures[0], receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(kind)) catch |err| return fail(engine, err);
    return c.JS_DupValue(context, result);
}
fn ordinary(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var kind: i32 = 0;
    if (c.JS_ToInt32(engine.context, &kind, captures[1]) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, try operation(&scope, captures[0], receiver, args, @enumFromInt(kind)));
}
fn function(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, length: c_int, kind: Kind) !c.JSValue {
    if (kind == .keys or kind == .values or kind == .entries or kind == .forEach) return scope.own(try @import("native_node_function.zig").create(scope.engine, name, length, ordinary, &.{ owner, c.JS_NewInt32(scope.engine.context, @intFromEnum(kind)) }));
    var captures = [_]c.JSValue{owner};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, name, length, @intFromEnum(kind), 1, &captures)));
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.get(target, "prototype");
    if (args.len > 0 and !c.JS_IsUndefined(args[0])) try web.typeError(&scope, try scope.text("FormData constructor: Argument 1 could not be converted to: undefined."), null);
    const owner = captures[0];
    const root = rootOf(owner);
    const result = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, if (c.JS_IsObject(prototype)) prototype else rootValue(root, .prototype), root.class)));
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .owner = c.JS_DupValue(engine.context, owner) };
    _ = c.JS_SetOpaque(result, state);
    return c.JS_DupValue(engine.context, result);
}
fn symbolProperty(scope: *Scope, target: c.JSValue, symbol: c.JSValue, value: c.JSValue, flags: c_int) !void {
    const atom = try js.atom(scope.engine, symbol);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, target, atom, c.JS_DupValue(scope.engine.context, value), flags) < 0) return js.capture(scope.engine);
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains(cache_key)) return;
    try blob.install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const root_class = try newClass(engine, "Native FormData Owner", freeRoot, markRoot);
    const owner = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, root_class)));
    const root = try engine.gpa.create(Root);
    root.* = .{ .engine = engine, .class = 0, .iterator_class = 0, .values = undefined };
    for (&root.values) |*slot| slot.* = c.pi_js_undefined();
    _ = c.JS_SetOpaque(owner, root);
    root.class = try newClass(engine, "FormData", freeState, markState);
    root.iterator_class = try newClass(engine, "FormData Iterator", freeIter, markIter);
    replace(root, .prototype, try js.object(engine));
    const array = try scope.array();
    const iter = try scope.invoke(array, "values", &.{});
    const iter_proto = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, iter)));
    const base_proto = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, iter_proto)));
    replace(root, .iterator_prototype, try engine.checked(c.JS_NewObjectProto(engine.context, base_proto)));
    const symbols = try scope.global("Symbol");
    replace(root, .has_instance, try js.getKey(engine, try scope.get(try scope.global("Function"), "prototype"), try scope.get(symbols, "hasInstance")));
    replace(root, .blob_ctor, try js.global(engine, "Blob"));
    replace(root, .file_ctor, try js.global(engine, "File"));
    replace(root, .constructor, try @import("native_class.zig").constructor(engine, "FormData", 0, rootValue(root, .prototype), construct, &.{owner}));
    inline for (.{ .{ "append", 2, Kind.append }, .{ "delete", 1, Kind.delete }, .{ "get", 1, Kind.get }, .{ "getAll", 1, Kind.getAll }, .{ "has", 1, Kind.has }, .{ "set", 2, Kind.set }, .{ "keys", 0, Kind.keys }, .{ "values", 0, Kind.values }, .{ "entries", 0, Kind.entries }, .{ "forEach", 1, Kind.forEach } }) |spec| try scope.put(rootValue(root, .prototype), spec[0], try function(&scope, owner, spec[0], spec[1], spec[2]));
    try scope.put(rootValue(root, .iterator_prototype), "next", try function(&scope, owner, "next", 0, .next));
    try symbolProperty(&scope, rootValue(root, .prototype), try web.iteratorSymbol(&scope), try scope.get(rootValue(root, .prototype), "entries"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    const tag = try scope.get(symbols, "toStringTag");
    try symbolProperty(&scope, rootValue(root, .prototype), tag, try scope.text("FormData"), c.JS_PROP_CONFIGURABLE);
    try symbolProperty(&scope, rootValue(root, .iterator_prototype), tag, try scope.text("FormData Iterator"), c.JS_PROP_CONFIGURABLE);
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    if (c.JS_DefinePropertyValueStr(engine.context, global, "FormData", c.JS_DupValue(engine.context, rootValue(root, .constructor)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    engine.native_module_values.putAssumeCapacity(cache_key, c.JS_DupValue(engine.context, owner));
}
pub fn create(engine: *em.Engine) !c.JSValue {
    try install(engine);
    return engine.checked(c.JS_CallConstructor(engine.context, rootValue(rootOf(engine.native_module_values.get(cache_key).?), .constructor), 0, null));
}
/// Native parser handoff. Entries must already be genuine parsed strings/Files.
pub fn appendEntry(scope: *Scope, target: c.JSValue, name: c.JSValue, value: c.JSValue) !void {
    const owner = scope.engine.native_module_values.get(cache_key) orelse return error.NativeWebFormDataUnavailable;
    const state = try stateOf(scope, owner, target);
    try state.entries.ensureUnusedCapacity(scope.engine.gpa, 1);
    state.entries.appendAssumeCapacity(.{ .name = c.JS_DupValue(scope.engine.context, name), .value = c.JS_DupValue(scope.engine.context, value) });
}
/// Bundled multipart parser's makeEntry(name,value,filename), including the
/// captured File constructor's second wrapping when filename is supplied.
pub fn appendParsedEntry(scope: *Scope, target: c.JSValue, name: c.JSValue, value: c.JSValue, filename: c.JSValue) !void {
    const owner = scope.engine.native_module_values.get(cache_key) orelse return error.NativeWebFormDataUnavailable;
    const entry_value = try makeEntry(scope, owner, value, filename);
    try appendEntry(scope, target, name, entry_value);
}
