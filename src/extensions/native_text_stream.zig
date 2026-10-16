//! Real TextEncoderStream/TextDecoderStream over the native Transform pair.
//! The encoder owns a cross-chunk high surrogate. The decoder owns a genuine
//! native TextDecoder and calls its retained streaming decode and EOF paths.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const transform = @import("native_transform_stream.zig");
const c = em.c;
const key = "pi-native:text-streams";
const State = struct {
    engine: *em.Engine,
    owner: c.JSValue,
    decoder: c.JSValue,
    readable: c.JSValue,
    writable: c.JSValue,
    pending_high: ?u16 = null,
};
const Op = enum(c_int) { encoding, fatal, ignore_bom, readable, writable, chunk, flush };
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ self.owner, self.decoder, self.readable, self.writable }) |root| c.JS_FreeValueRT(runtime, root);
    self.engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ self.owner, self.decoder, self.readable, self.writable }) |root| c.JS_MarkValue(runtime, root, visit);
}
fn classId(engine: *em.Engine, owner: c.JSValue) !c.JSClassID {
    const value = try js.get(engine, owner, "class");
    defer engine.freeValue(value);
    var result: u32 = 0;
    if (c.JS_ToUint32(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn callback(scope: *Scope, root: c.JSValue, op: Op, name: [*:0]const u8, length: c_int, internal: bool) !c.JSValue {
    var roots = [_]c.JSValue{ root, c.pi_js_bool(scope.engine.context, @intFromBool(internal)) };
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, @intFromEnum(op), roots.len, &roots)));
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc == 0) &.{} else argv[0..@intCast(argc)], @enumFromInt(magic), roots[0], c.JS_ToBool(context, roots[1]) == 1) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn emitScalar(engine: *em.Engine, bytes: *std.ArrayList(u8), point: u21) !void {
    var encoded: [4]u8 = undefined;
    const count = try std.unicode.utf8Encode(point, &encoded);
    try bytes.appendSlice(engine.gpa, encoded[0..count]);
}
fn encode(self: *State, scope: *Scope, chunk: c.JSValue, controller: c.JSValue, flush: bool) !void {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(self.engine.gpa);
    if (flush) {
        if (self.pending_high != null) {
            self.pending_high = null;
            try emitScalar(self.engine, &bytes, 0xfffd);
        }
    } else {
        // String(), including Symbol conversion, runs before touching carry.
        const text_value = try scope.call(try scope.get(self.owner, "String"), c.pi_js_undefined(), &.{chunk});
        const text = try self.engine.toString(text_value);
        defer self.engine.gpa.free(text);
        var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
        while (iterator.nextCodepoint()) |point| {
            if (self.pending_high) |high| {
                self.pending_high = null;
                if (point >= 0xdc00 and point <= 0xdfff) {
                    try emitScalar(self.engine, &bytes, 0x10000 + (@as(u21, high - 0xd800) << 10) + point - 0xdc00);
                    continue;
                }
                try emitScalar(self.engine, &bytes, 0xfffd);
            }
            if (point >= 0xd800 and point <= 0xdbff) {
                self.pending_high = @intCast(point);
            } else try emitScalar(self.engine, &bytes, if (point >= 0xdc00 and point <= 0xdfff) 0xfffd else point);
        }
    }
    if (bytes.items.len == 0) return;
    const buffer = try scope.own(try self.engine.checked(c.JS_NewArrayBufferCopy(self.engine.context, bytes.items.ptr, bytes.items.len)));
    var args = [_]c.JSValue{buffer};
    const value = try scope.own(try self.engine.checked(c.JS_NewTypedArray(self.engine.context, args.len, &args, c.JS_TYPED_ARRAY_UINT8)));
    try transform.enqueueNative(self.engine, controller, value);
}
fn invalidUndefined(scope: *Scope) !void {
    var args = [_]c.JSValue{try scope.text("The \"chunk\" argument must be of type string. Received undefined")};
    const error_value = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(scope.engine.native_module_values.get(key).?, "TypeError"), args.len, &args)));
    try scope.put(error_value, "code", try scope.text("ERR_INVALID_ARG_TYPE"));
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, error_value))) catch |err| return err;
    unreachable;
}
fn invoke(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, op: Op, root: c.JSValue, internal: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const instance = if (internal) root else receiver;
    const owner = if (internal) blk: {
        const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(root, c.JS_GetClassID(root)).?));
        break :blk self.owner;
    } else root;
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(instance, try classId(engine, owner)) orelse return js.typeError(engine, "Cannot read private member from an object whose class did not declare it")));
    const decoding = !c.JS_IsUndefined(self.decoder);
    switch (op) {
        .readable => return c.JS_DupValue(engine.context, self.readable),
        .writable => return c.JS_DupValue(engine.context, self.writable),
        .encoding, .fatal, .ignore_bom => {
            if (!decoding) return scope.engine.checked(c.JS_NewString(engine.context, "utf-8"));
            const bindings = try scope.get(owner, "decoderBindings");
            const name: [*:0]const u8 = switch (op) {
                .encoding => "encoding",
                .fatal => "fatal",
                .ignore_bom => "ignoreBOM",
                else => unreachable,
            };
            return js.call(engine, try scope.get(bindings, name), self.decoder, &.{});
        },
        .chunk, .flush => {
            const flush = op == .flush;
            const chunk = if (args.len == 0) c.pi_js_undefined() else args[0];
            const controller = if (flush) chunk else if (args.len > 1) args[1] else c.pi_js_undefined();
            if (!decoding) {
                try encode(self, &scope, chunk, controller, flush);
            } else {
                if (!flush and c.JS_IsUndefined(chunk)) try invalidUndefined(&scope);
                const bindings = try scope.get(owner, "decoderBindings");
                const stream_option = try scope.get(owner, "streamOption");
                const value = try scope.call(try scope.get(bindings, "decode"), self.decoder, if (flush) &.{} else &.{ chunk, stream_option });
                if (scope.truthy(value)) try transform.enqueueNative(engine, controller, value);
                if (flush) try transform.terminateNative(engine, controller);
            }
            return c.pi_js_undefined();
        },
    }
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = roots[0];
    const decoding = c.JS_ToBool(engine.context, roots[1]) == 1;
    const decoder = if (decoding) blk: {
        var inputs = [_]c.JSValue{ if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined() };
        const bindings = try scope.get(owner, "decoderBindings");
        break :blk try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.get(bindings, "constructor"), inputs.len, &inputs)));
    } else c.pi_js_undefined();
    const prototype = try scope.get(target, "prototype");
    const fallback = try scope.get(owner, "prototype");
    const instance = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, if (c.JS_IsObject(prototype)) prototype else fallback, try classId(engine, owner))));
    const self = try engine.gpa.create(State);
    self.* = .{ .engine = engine, .owner = c.JS_DupValue(engine.context, owner), .decoder = c.JS_DupValue(engine.context, decoder), .readable = c.pi_js_undefined(), .writable = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(instance, self);
    const transformer = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(transformer, "transform", try callback(&scope, instance, .chunk, "transform", 2, true));
    try scope.put(transformer, "flush", try callback(&scope, instance, .flush, "flush", 1, true));
    const pair = try scope.own(try transform.createNative(engine, transformer, c.pi_js_undefined(), c.pi_js_undefined()));
    self.readable = try transform.readableNative(engine, pair);
    self.writable = try transform.writableNative(engine, pair);
    return c.JS_DupValue(engine.context, instance);
}
pub fn exports(engine: *em.Engine) !c.JSValue {
    try install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const retained = engine.native_module_values.get(key).?;
    const result = try scope.object();
    inline for (.{ "TextEncoderStream", "TextDecoderStream" }) |name| try scope.put(result, name, try scope.get(retained, name));
    return c.JS_DupValue(engine.context, result);
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains(key)) return;
    try transform.install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(result, "TypeError", try scope.global("TypeError"));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const decoder_bindings = try scope.own(try @import("text_decoder.zig").nativeBindings(engine));
    inline for (.{ false, true }, .{ "TextEncoderStream", "TextDecoderStream" }) |decoding, name| {
        var id: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &id);
        const definition: c.JSClassDef = .{ .class_name = name, .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
        const owner = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
        const prototype = try scope.object();
        try scope.put(owner, "class", c.JS_NewUint32(engine.context, id));
        try scope.put(owner, "prototype", prototype);
        try scope.put(owner, "String", try scope.global("String"));
        try scope.put(owner, "decoderBindings", decoder_bindings);
        const stream_option = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
        try scope.put(stream_option, "stream", c.pi_js_bool(engine.context, 1));
        try scope.put(owner, "streamOption", stream_option);
        const constructor = try scope.own(try @import("native_class.zig").constructor(engine, name, 0, prototype, construct, &.{ owner, c.pi_js_bool(engine.context, @intFromBool(decoding)) }));
        inline for (.{ "encoding", "fatal", "ignoreBOM", "readable", "writable" }, .{ Op.encoding, Op.fatal, Op.ignore_bom, Op.readable, Op.writable }) |property, op| {
            if (!decoding and (op == .fatal or op == .ignore_bom)) continue;
            const atom = c.JS_NewAtom(engine.context, property);
            if (atom == c.JS_ATOM_NULL) return js.capture(engine);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, try callback(&scope, owner, op, "get " ++ property, 0, false)), c.pi_js_undefined(), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        }
        try scope.put(result, name, constructor);
        if (c.JS_DefinePropertyValueStr(engine.context, global, name, c.JS_DupValue(engine.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try engine.registerValueModule(key, result);
}
