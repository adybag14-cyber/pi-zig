//! Source-authored native Blob/File dependency for the unqualified Body phase.
//! Byte storage is native owned immutable data. stream() requires the actual
//! shared native ReadableStream provider; absence is an explicit dependency error.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const web = @import("native_headers_webidl.zig");
const c = em.c;
const cache_key = "\x00native-web-Blob";
pub const StreamProvider = struct {
    owner: c.JSValue,
    /// Takes a genuine copied Uint8Array; returns an owned genuine byte stream.
    create: *const fn (*em.Engine, c.JSValue, c.JSValue) anyerror!c.JSValue,
};
const Slot = enum(usize) { blob_proto, file_proto, blob_ctor, file_ctor, decoder_ctor, decoder, stream_owner, shared_ctor, date_now, number_is_nan, well_formed };
const Root = struct { engine: *em.Engine, class: c.JSClassID, values: [11]c.JSValue, stream_create: ?*const fn (*em.Engine, c.JSValue, c.JSValue) anyerror!c.JSValue = null };
const State = struct { engine: *em.Engine, owner: c.JSValue, bytes: []u8, mime: c.JSValue, name: c.JSValue, modified: c.JSValue, file: bool };
const Kind = enum(c_int) { size, mime, slice, arrayBuffer, text, bytes, stream, name, lastModified };
fn rootOf(owner: c.JSValue) *Root {
    return @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
}
fn value(root: *Root, slot: Slot) c.JSValue {
    return root.values[@intFromEnum(slot)];
}
fn replace(root: *Root, slot: Slot, item: c.JSValue) void {
    root.engine.freeValue(root.values[@intFromEnum(slot)]);
    root.values[@intFromEnum(slot)] = item;
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
    for ([_]c.JSValue{ state.owner, state.mime, state.name, state.modified }) |item| c.JS_FreeValueRT(runtime, item);
    state.engine.gpa.free(state.bytes);
    state.engine.gpa.destroy(state);
}
fn markState(runtime: ?*c.JSRuntime, object: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    for ([_]c.JSValue{ state.owner, state.mime, state.name, state.modified }) |item| c.JS_MarkValue(runtime, item, visit);
}
fn newClass(engine: *em.Engine, name: [*:0]const u8, finalizer: *const c.JSClassFinalizer, marker: *const c.JSClassGCMark) !c.JSClassID {
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = name, .finalizer = finalizer, .gc_mark = marker };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    return id;
}
fn stateOf(owner: c.JSValue, object: c.JSValue) ?*State {
    return if (c.JS_GetOpaque(object, rootOf(owner).class)) |opaque_state| @ptrCast(@alignCast(opaque_state)) else null;
}
fn typeError(scope: *Scope, name: []const u8) anyerror!noreturn {
    const message = try scope.concat(try scope.concat(try scope.text("Value of \"this\" must be of type "), try scope.text(name)), try scope.text(""));
    try web.typeError(scope, message, "ERR_INVALID_THIS");
}
fn checkedState(scope: *Scope, owner: c.JSValue, object: c.JSValue, file: bool) !*State {
    const state = stateOf(owner, object) orelse {
        try typeError(scope, if (file) "File" else "Blob");
    };
    if (file and !state.file) try typeError(scope, "File");
    return state;
}
pub fn isBlob(engine: *em.Engine, object: c.JSValue) bool {
    const owner = engine.native_module_values.get(cache_key) orelse return false;
    return stateOf(owner, object) != null;
}
pub fn isFile(engine: *em.Engine, object: c.JSValue) bool {
    const owner = engine.native_module_values.get(cache_key) orelse return false;
    const state = stateOf(owner, object) orelse return false;
    return state.file;
}
/// Borrowed immutable bytes: retain object and copy before unrelated JS calls.
pub fn data(engine: *em.Engine, object: c.JSValue) ![]const u8 {
    const owner = engine.native_module_values.get(cache_key) orelse return error.NativeWebBlobUnavailable;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return (try checkedState(&scope, owner, object, false)).bytes;
}
fn specific(scope: *Scope, item: c.JSValue) !c.JSValue {
    if (c.JS_IsNull(item)) return scope.text("null");
    if (c.JS_IsUndefined(item)) return scope.text("undefined");
    if (c.JS_IsFunction(scope.engine.context, item)) return scope.concat(try scope.text("function "), try scope.get(item, "name"));
    if (c.JS_IsObject(item)) {
        const constructor = try scope.get(item, "constructor");
        if (scope.truthy(constructor) and try js.hasKey(scope.engine, constructor, try scope.text("name"))) return scope.concat(try scope.text("an instance of "), try scope.get(constructor, "name"));
        const inspected = try @import("node_event_inspect.zig").inspect(scope.engine, item, -1);
        defer scope.engine.gpa.free(inspected);
        return scope.text(inspected);
    }
    var text = try web.string(scope, item);
    if (c.JS_IsString(item)) {
        if (try web.count(scope, text) > 28) text = try scope.concat(try scope.invoke(text, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 25) }), try scope.text("..."));
        const inspected = try @import("node_event_inspect.zig").inspect(scope.engine, text, 2);
        defer scope.engine.gpa.free(inspected);
        return scope.concat(try scope.concat(try scope.text("type string ("), try scope.text(inspected)), try scope.text(")"));
    }
    const label = if (c.JS_IsBool(item)) "boolean" else if (c.JS_IsBigInt(item)) "bigint" else if (c.JS_IsSymbol(item)) "symbol" else "number";
    if (c.JS_IsBigInt(item)) text = try scope.concat(text, try scope.text("n"));
    return scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.text("type "), try scope.text(label)), try scope.text(" (")), text), try scope.text(")"));
}
fn invalid(scope: *Scope, argument: []const u8, expected: []const u8, item: c.JSValue) anyerror!noreturn {
    var message = try scope.concat(try scope.concat(try scope.text("The \""), try scope.text(argument)), try scope.text("\" argument must be "));
    message = try scope.concat(message, try scope.text(expected));
    try web.typeError(scope, try scope.concat(try scope.concat(message, try scope.text(". Received ")), try specific(scope, item)), "ERR_INVALID_ARG_TYPE");
}
fn normalizeType(scope: *Scope, input: c.JSValue) !c.JSValue {
    const text = try scope.stringify(input);
    const units = try @import("native_utf16.zig").unitsAlloc(scope.engine, text);
    defer scope.engine.gpa.free(units);
    for (units) |unit| if (unit < 0x20 or unit > 0x7e) return scope.text("");
    // Source uses the primordial lower-case operation, not an override on input.
    const bytes = try scope.engine.toString(text);
    defer scope.engine.gpa.free(bytes);
    for (bytes) |*byte| byte.* = std.ascii.toLower(byte.*);
    return scope.text(bytes);
}
fn appendBytes(scope: *Scope, output: *std.ArrayList(u8), bytes: []const u8) !void {
    if (bytes.len > scope.engine.options.memory_limit -| output.items.len) return error.NativeWebBlobResourceLimit;
    try output.appendSlice(scope.engine.gpa, bytes);
}
fn appendPart(scope: *Scope, owner: c.JSValue, output: *std.ArrayList(u8), part: c.JSValue, native_endings: bool) !void {
    if (stateOf(owner, part)) |blob| return appendBytes(scope, output, blob.bytes);
    const view = c.JS_IsDataView(part) or c.JS_GetTypedArrayType(part) >= 0;
    const shared_ctor = value(rootOf(owner), .shared_ctor);
    const shared = if (!c.JS_IsUndefined(shared_ctor)) c.JS_IsInstanceOf(scope.engine.context, part, shared_ctor) == 1 else false;
    if (c.JS_IsArrayBuffer(part) or shared or view) {
        const buffer = if (view) try scope.get(part, "buffer") else part;
        var offset: u64 = 0;
        var length: u64 = 0;
        if (view and c.JS_ToIndex(scope.engine.context, &offset, try scope.get(part, "byteOffset")) < 0) return js.capture(scope.engine);
        if (c.JS_ToIndex(scope.engine.context, &length, try scope.get(part, "byteLength")) < 0) return js.capture(scope.engine);
        var size: usize = 0;
        const bytes = c.JS_GetArrayBuffer(scope.engine.context, &size, buffer);
        if (bytes == null and c.JS_HasException(scope.engine.context)) return js.capture(scope.engine);
        if (offset > size or length > size - offset) return error.NativeWebBlobBufferBounds;
        if (length > 0) try appendBytes(scope, output, bytes[@intCast(offset)..@intCast(offset + length)]);
        return;
    }
    const text = try scope.stringify(part);
    const bytes = try @import("url_search_params.zig").usvString(scope.engine, text);
    defer scope.engine.gpa.free(bytes);
    if (!native_endings) return appendBytes(scope, output, bytes);
    var start: usize = 0;
    for (bytes, 0..) |byte, position| if (byte == '\n') {
        const end = if (position > start and bytes[position - 1] == '\r') position - 1 else position;
        try appendBytes(scope, output, bytes[start..end]);
        try appendBytes(scope, output, if (@import("builtin").os.tag == .windows) "\r\n" else "\n");
        start = position + 1;
    };
    try appendBytes(scope, output, bytes[start..]);
}
fn make(scope: *Scope, owner: c.JSValue, prototype: c.JSValue, bytes: []const u8, mime: c.JSValue, name: c.JSValue, modified: c.JSValue, file: bool) !c.JSValue {
    const engine = scope.engine;
    const root = rootOf(owner);
    const result = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, root.class)));
    const copied = try engine.gpa.dupe(u8, bytes);
    errdefer engine.gpa.free(copied);
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .owner = c.JS_DupValue(engine.context, owner), .bytes = copied, .mime = c.JS_DupValue(engine.context, mime), .name = c.JS_DupValue(engine.context, name), .modified = c.JS_DupValue(engine.context, modified), .file = file };
    _ = c.JS_SetOpaque(result, state);
    return result;
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = captures[0];
    const root = rootOf(owner);
    const file = c.JS_ToBool(engine.context, captures[1]) == 1;
    if (file and args.len < 2) try web.typeError(&scope, try scope.text("The \"fileBits\" and \"fileName\" arguments must be specified"), "ERR_MISSING_ARGS");
    const requested_proto = try scope.get(target, "prototype");
    const prototype = if (c.JS_IsObject(requested_proto)) requested_proto else value(root, if (file) .file_proto else .blob_proto);
    const parts = if (args.len == 0 or c.JS_IsUndefined(args[0])) try scope.array() else args[0];
    const iterator_symbol = try web.iteratorSymbol(&scope);
    if (c.JS_IsNull(parts) or !c.JS_IsFunction(engine.context, try scope.own(try js.getKey(engine, parts, iterator_symbol))) or c.JS_IsString(parts)) try invalid(&scope, "sources", "a sequence", parts);
    const options_index: usize = if (file) 2 else 1;
    const options = if (args.len > options_index) args[options_index] else c.pi_js_undefined();
    if (!c.JS_IsNull(options) and !c.JS_IsUndefined(options) and !c.JS_IsObject(options)) try invalid(&scope, "options", "a dictionary", options);
    const no_options = c.JS_IsNull(options) or c.JS_IsUndefined(options);
    const raw_type = if (no_options) c.pi_js_undefined() else try scope.get(options, "type");
    const raw_endings = if (no_options) c.pi_js_undefined() else try scope.get(options, "endings");
    const endings = try scope.stringify(if (c.JS_IsUndefined(raw_endings)) try scope.text("transparent") else raw_endings);
    const native_endings = scope.equal(endings, try scope.text("native"));
    if (!native_endings and !scope.equal(endings, try scope.text("transparent"))) {
        const inspected = try @import("node_event_inspect.zig").inspect(engine, endings, 2);
        defer engine.gpa.free(inspected);
        try web.typeError(&scope, try scope.concat(try scope.text("The property 'options.endings' is invalid. Received "), try scope.text(inspected)), "ERR_INVALID_ARG_VALUE");
    }
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(engine.gpa);
    var iterator = try js.Iterator.init(engine, parts, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |part| {
        defer engine.freeValue(part);
        try appendPart(&scope, owner, &output, part, native_endings);
    }
    const mime = try normalizeType(&scope, if (c.JS_IsUndefined(raw_type)) try scope.text("") else raw_type);
    var name = c.pi_js_undefined();
    var modified = c.pi_js_undefined();
    if (file) {
        const raw_modified = if (no_options) c.pi_js_undefined() else try scope.get(options, "lastModified");
        if (c.JS_IsUndefined(raw_modified)) modified = try scope.call(value(root, .date_now), c.pi_js_undefined(), &.{}) else {
            modified = try scope.own(try engine.checked(c.JS_ToNumber(engine.context, raw_modified)));
            if (scope.truthy(try scope.call(value(root, .number_is_nan), c.pi_js_undefined(), &.{modified}))) modified = c.JS_NewInt32(engine.context, 0);
        }
        name = try scope.call(value(root, .well_formed), try scope.stringify(args[1]), &.{});
    }
    return c.JS_DupValue(engine.context, try make(&scope, owner, prototype, output.items, mime, name, modified, file));
}
fn integer(scope: *Scope, input: c.JSValue, maximum: usize) !usize {
    const number = try scope.own(try scope.engine.checked(c.JS_ToNumber(scope.engine.context, input)));
    var raw: f64 = 0;
    if (c.JS_ToFloat64(scope.engine.context, &raw, number) < 0) return js.capture(scope.engine);
    if (!std.math.isFinite(raw) or raw == 0) return 0;
    // Actual internal/webidl signed64 conversion keeps signed remainder.
    raw = @rem(@trunc(raw), 18446744073709551616.0);
    if (raw >= 9223372036854775808.0) raw -= 18446744073709551616.0;
    const relative = if (raw < 0) @max(@as(f64, @floatFromInt(maximum)) + @ceil(raw), 0) else @min(@floor(raw), @as(f64, @floatFromInt(maximum)));
    return @intFromFloat(relative);
}
fn operation(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, kind: Kind) !c.JSValue {
    const state = try checkedState(scope, owner, receiver, kind == .name or kind == .lastModified);
    const root = rootOf(owner);
    switch (kind) {
        .size => return web.number(scope, state.bytes.len),
        .mime => return state.mime,
        .name => return state.name,
        .lastModified => return state.modified,
        .slice => {
            const start = if (args.len > 0 and !c.JS_IsUndefined(args[0])) try integer(scope, args[0], state.bytes.len) else 0;
            const end = if (args.len > 1 and !c.JS_IsUndefined(args[1])) try integer(scope, args[1], state.bytes.len) else state.bytes.len;
            const mime = try normalizeType(scope, if (args.len > 2 and !c.JS_IsUndefined(args[2])) args[2] else try scope.text(""));
            const result = try make(scope, owner, value(root, .blob_proto), state.bytes[start..@max(start, end)], mime, c.pi_js_undefined(), c.pi_js_undefined(), false);
            // Node's createBlob fixes constructor as an ordinary own property.
            try scope.set(result, "constructor", value(root, .blob_ctor));
            return result;
        },
        .arrayBuffer => return scope.own(try scope.engine.checked(c.JS_NewArrayBufferCopy(scope.engine.context, state.bytes.ptr, state.bytes.len))),
        .bytes => return scope.own(try scope.engine.checked(c.JS_NewUint8ArrayCopy(scope.engine.context, state.bytes.ptr, state.bytes.len))),
        .text => {
            if (c.JS_IsUndefined(value(root, .decoder))) {
                const decoder = try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, value(root, .decoder_ctor), 0, null));
                replace(root, .decoder, decoder);
            }
            const buffer = try scope.own(try scope.engine.checked(c.JS_NewArrayBufferCopy(scope.engine.context, state.bytes.ptr, state.bytes.len)));
            return scope.invoke(value(root, .decoder), "decode", &.{buffer});
        },
        .stream => {
            const create = root.stream_create orelse return error.NativeWebReadableStreamUnavailable;
            const bytes = try scope.own(try scope.engine.checked(c.JS_NewUint8ArrayCopy(scope.engine.context, state.bytes.ptr, state.bytes.len)));
            return scope.own(try create(scope.engine, value(root, .stream_owner), bytes));
        },
    }
}
fn fail(engine: *em.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowInternalError(engine.context, "Native Web Blob: %s", @as([*:0]const u8, @errorName(err)));
}
fn asyncJob(context: ?*c.JSContext, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var tag: i32 = 0;
    if (c.JS_ToInt32(context, &tag, captures[4]) < 0) return fail(engine, js.capture(engine));
    const result = operation(&scope, captures[0], captures[1], &.{}, @enumFromInt(tag)) catch |err| {
        _ = fail(engine, err);
        const reason = c.JS_GetException(context);
        defer engine.freeValue(reason);
        _ = scope.call(captures[3], c.pi_js_undefined(), &.{reason}) catch |failure| return fail(engine, failure);
        return c.pi_js_undefined();
    };
    _ = scope.call(captures[2], c.pi_js_undefined(), &.{result}) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn invoke(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, kind: Kind) !c.JSValue {
    if (kind != .text and kind != .bytes and kind != .arrayBuffer) return operation(scope, owner, receiver, args, kind);
    var caps: [2]c.JSValue = undefined;
    const promise = try scope.own(try scope.engine.checked(c.JS_NewPromiseCapability(scope.engine.context, &caps)));
    defer for (caps) |cap| scope.engine.freeValue(cap);
    if (stateOf(owner, receiver) == null) {
        _ = checkedState(scope, owner, receiver, false) catch |err| {
            _ = fail(scope.engine, err);
            const reason = try scope.own(c.JS_GetException(scope.engine.context));
            _ = try scope.call(caps[1], c.pi_js_undefined(), &.{reason});
            return promise;
        };
    }
    var captures = [_]c.JSValue{ owner, receiver, caps[0], caps[1], c.JS_NewInt32(scope.engine.context, @intFromEnum(kind)) };
    if (c.JS_EnqueueJob(scope.engine.context, asyncJob, captures.len, &captures) < 0) return js.capture(scope.engine);
    return promise;
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, tag: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = invoke(&scope, captures[0], receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(tag)) catch |err| return fail(engine, err);
    return c.JS_DupValue(context, result);
}
fn function(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, length: c_int, kind: Kind) !c.JSValue {
    var captures = [_]c.JSValue{owner};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, name, length, @intFromEnum(kind), 1, &captures)));
}
fn getter(scope: *Scope, owner: c.JSValue, prototype: c.JSValue, name: [*:0]const u8, display: [*:0]const u8, kind: Kind) !void {
    const atom = c.JS_NewAtom(scope.engine.context, name);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyGetSet(scope.engine.context, prototype, atom, c.JS_DupValue(scope.engine.context, try function(scope, owner, display, 0, kind)), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(scope.engine);
}
fn defineTag(scope: *Scope, prototype: c.JSValue, text: []const u8) !void {
    const symbol = try scope.get(try scope.global("Symbol"), "toStringTag");
    const atom = try js.atom(scope.engine, symbol);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, prototype, atom, c.JS_DupValue(scope.engine.context, try scope.text(text)), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(scope.engine);
}
pub fn bindStreams(engine: *em.Engine, provider: StreamProvider) !void {
    const owner = engine.native_module_values.get(cache_key) orelse return error.NativeWebBlobUnavailable;
    const root = rootOf(owner);
    replace(root, .stream_owner, c.JS_DupValue(engine.context, provider.owner));
    root.stream_create = provider.create;
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains(cache_key)) return;
    if (engine.text_decoder_class == 0) try @import("text_decoder.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const root_class = try newClass(engine, "Native Blob Owner", freeRoot, markRoot);
    const owner = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, root_class)));
    const root = try engine.gpa.create(Root);
    root.* = .{ .engine = engine, .class = 0, .values = undefined };
    for (&root.values) |*slot| slot.* = c.pi_js_undefined();
    _ = c.JS_SetOpaque(owner, root);
    root.class = try newClass(engine, "Native Blob Data", freeState, markState);
    replace(root, .blob_proto, try js.object(engine));
    replace(root, .file_proto, try engine.checked(c.JS_NewObjectProto(engine.context, value(root, .blob_proto))));
    replace(root, .decoder_ctor, try js.global(engine, "TextDecoder"));
    replace(root, .shared_ctor, try js.global(engine, "SharedArrayBuffer"));
    replace(root, .date_now, try js.get(engine, try scope.global("Date"), "now"));
    replace(root, .number_is_nan, try js.get(engine, try scope.global("Number"), "isNaN"));
    replace(root, .well_formed, try js.get(engine, try scope.get(try scope.global("String"), "prototype"), "toWellFormed"));
    replace(root, .blob_ctor, try @import("native_class.zig").constructor(engine, "Blob", 0, value(root, .blob_proto), construct, &.{ owner, c.JS_NewBool(engine.context, false) }));
    replace(root, .file_ctor, try @import("native_class.zig").constructor(engine, "File", 2, value(root, .file_proto), construct, &.{ owner, c.JS_NewBool(engine.context, true) }));
    if (c.JS_SetPrototype(engine.context, value(root, .file_ctor), value(root, .blob_ctor)) < 0) return js.capture(engine);
    try getter(&scope, owner, value(root, .blob_proto), "type", "get type", .mime);
    try getter(&scope, owner, value(root, .blob_proto), "size", "get size", .size);
    inline for (.{ .{ "slice", 0, Kind.slice }, .{ "arrayBuffer", 0, Kind.arrayBuffer }, .{ "text", 0, Kind.text }, .{ "bytes", 0, Kind.bytes }, .{ "stream", 0, Kind.stream } }) |spec| try scope.put(value(root, .blob_proto), spec[0], try function(&scope, owner, spec[0], spec[1], spec[2]));
    try getter(&scope, owner, value(root, .file_proto), "name", "get name", .name);
    try getter(&scope, owner, value(root, .file_proto), "lastModified", "get lastModified", .lastModified);
    try defineTag(&scope, value(root, .blob_proto), "Blob");
    try defineTag(&scope, value(root, .file_proto), "File");
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    if (c.JS_DefinePropertyValueStr(engine.context, global, "Blob", c.JS_DupValue(engine.context, value(root, .blob_ctor)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, global, "File", c.JS_DupValue(engine.context, value(root, .file_ctor)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    engine.native_module_values.putAssumeCapacity(cache_key, c.JS_DupValue(engine.context, owner));
}
pub fn fromBytes(engine: *em.Engine, bytes: []const u8, mime: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = engine.native_module_values.get(cache_key).?;
    return c.JS_DupValue(engine.context, try make(&scope, owner, value(rootOf(owner), .blob_proto), bytes, try normalizeType(&scope, mime), c.pi_js_undefined(), c.pi_js_undefined(), false));
}
