//! Original coding-agent image normalization over the linked Photon codec and
//! native resize worker. Every promise and temporary byte view stays VM owned.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const p = @import("../ai/photon_session.zig");
const c = em.c;
const Stage = enum(c_int) { convert, converted, normalized, resized };
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{ try scope.own(try @import("native_image_resize_api.zig").create(engine)), try scope.own(try @import("native_image_dimension_note.zig").create(engine)) };
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, call, "processImage", 3, 0, roots.len, &roots));
    errdefer engine.freeValue(function);
    const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    return function;
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return begin(engine, if (argc > 0) args[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initial(engine, pending.owner, args, roots) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn option(scope: *Scope, options: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(options)) c.pi_js_undefined() else scope.get(options, key);
}
fn baseMime(scope: *Scope, mime: c.JSValue) !c.JSValue {
    const split = try scope.invoke(mime, "split", &.{try scope.text(";")});
    const first = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, split, 0)));
    const lower = if (temp.nullish(first)) c.pi_js_undefined() else try scope.invoke(try scope.invoke(first, "trim", &.{}), "toLowerCase", &.{});
    return if (temp.nullish(lower)) scope.invoke(mime, "toLowerCase", &.{}) else lower;
}
fn initial(engine: *em.Engine, owner: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = arg(args, 2);
    const automatic = try option(&scope, options, "autoResizeImages");
    try scope.put(owner, "automatic", if (temp.nullish(automatic)) c.pi_js_bool(engine.context, 1) else automatic);
    try scope.put(owner, "options", options);
    try scope.put(owner, "resize", roots[0]);
    try scope.put(owner, "dimension", roots[1]);
    const bytes = arg(args, 0);
    const mime = arg(args, 1);
    const normalized = try scope.own(try normalize(engine, bytes, mime));
    try flow.wait(step, engine, owner, normalized, @intFromEnum(Stage.normalized));
}
fn normalize(engine: *em.Engine, bytes: c.JSValue, mime: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    normalizeBody(engine, pending.owner, bytes, mime) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn normalizeBody(engine: *em.Engine, owner: c.JSValue, bytes: c.JSValue, mime: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const base = try baseMime(&scope, mime);
    var supported: ?[]const u8 = null;
    inline for (.{ "image/png", "image/jpeg", "image/jpg", "image/gif", "image/webp" }) |name| {
        if (scope.equal(base, try scope.text(name))) supported = if (comptime std.mem.eql(u8, name, "image/jpg")) "image/jpeg" else name;
    }
    if (supported) |name| {
        const value = try scope.object();
        try scope.put(value, "bytes", bytes);
        try scope.put(value, "mimeType", try scope.text(name));
        try flow.settle(engine, owner, false, value);
    } else {
        try scope.put(owner, "bytes", bytes);
        try scope.put(owner, "mime", mime);
        const conversion = try flow.create(engine, c.pi_js_undefined());
        defer engine.freeValue(conversion.owner);
        defer engine.freeValue(conversion.promise);
        try scope.put(conversion.owner, "bytes", bytes);
        try flow.wait(step, engine, conversion.owner, c.pi_js_undefined(), @intFromEnum(Stage.convert));
        try flow.wait(step, engine, owner, conversion.promise, @intFromEnum(Stage.converted));
    }
}
fn failure(scope: *Scope, owner: c.JSValue, message: []const u8) !void {
    const result = try scope.object();
    try scope.put(result, "ok", c.pi_js_bool(scope.engine.context, 0));
    try scope.put(result, "message", try scope.text(message));
    try flow.settle(scope.engine, owner, false, result);
}
fn step(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (@as(Stage, @enumFromInt(stage))) {
        .convert => {
            const converted = try scope.own(try convert(engine, try scope.get(owner, "bytes")));
            try flow.settle(engine, owner, false, converted);
        },
        .converted => {
            if (!scope.truthy(value)) return flow.settle(engine, owner, false, c.pi_js_null());
            const normalized = try scope.object();
            try scope.put(normalized, "bytes", value);
            try scope.put(normalized, "mimeType", try scope.text("image/png"));
            try scope.put(normalized, "convertedFrom", try baseMime(&scope, try scope.get(owner, "mime")));
            try flow.settle(engine, owner, false, normalized);
        },
        .normalized => {
            if (!scope.truthy(value)) return failure(&scope, owner, "[Image omitted: could not be converted to a supported inline image format.]");
            try scope.put(owner, "normalized", value);
            if (scope.truthy(try scope.get(owner, "automatic"))) {
                const resize = try scope.get(owner, "resize");
                const bytes = try scope.get(value, "bytes");
                const mime = try scope.get(value, "mimeType");
                const options = try option(&scope, try scope.get(owner, "options"), "resizeOptions");
                return flow.wait(step, engine, owner, try scope.call(resize, c.pi_js_undefined(), &.{ bytes, mime, options }), @intFromEnum(Stage.resized));
            }
            const buffer = try scope.invoke(try scope.global("Buffer"), "from", &.{try scope.get(value, "bytes")});
            const data = try scope.invoke(buffer, "toString", &.{try scope.text("base64")});
            try finish(&scope, owner, data, try scope.get(value, "mimeType"), null);
        },
        .resized => {
            if (!scope.truthy(value)) return failure(&scope, owner, "[Image omitted: could not be resized below the inline image size limit.]");
            try finish(&scope, owner, try scope.get(value, "data"), try scope.get(value, "mimeType"), value);
        },
    }
}
fn finish(scope: *Scope, owner: c.JSValue, data: c.JSValue, mime: c.JSValue, resized: ?c.JSValue) !void {
    const hints = try scope.array();
    const from = try scope.get(try scope.get(owner, "normalized"), "convertedFrom");
    if (scope.truthy(from) and !scope.equal(from, mime)) {
        var text = try scope.concat(try scope.text("[Image converted from "), from);
        text = try scope.concat(text, try scope.text(" to "));
        text = try scope.concat(text, mime);
        text = try scope.concat(text, try scope.text(".]"));
        _ = try scope.invoke(hints, "push", &.{text});
    }
    if (resized) |value| {
        const note = try scope.call(try scope.get(owner, "dimension"), c.pi_js_undefined(), &.{value});
        if (scope.truthy(note)) _ = try scope.invoke(hints, "push", &.{note});
    }
    const result = try scope.object();
    try scope.put(result, "ok", c.pi_js_bool(scope.engine.context, 1));
    try scope.put(result, "data", data);
    try scope.put(result, "mimeType", mime);
    try scope.put(result, "hints", hints);
    try flow.settle(scope.engine, owner, false, result);
}
fn convert(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var offset: usize = 0;
    var length: usize = 0;
    var element: usize = 0;
    const backing = try scope.own(try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, input, &offset, &length, &element)));
    var total: usize = 0;
    const pointer = c.JS_GetArrayBuffer(engine.context, &total, backing);
    if (c.JS_HasException(engine.context)) return js.capture(engine);
    if (offset > total or length > total - offset or (pointer == null and length != 0)) return js.typeError(engine, "Invalid image byte buffer");
    const bytes = if (length == 0) &.{} else pointer[offset .. offset + length];
    const session = p.Session.init(engine.gpa) catch |err| return if (err == error.OutOfMemory) err else c.pi_js_null();
    defer session.deinit();
    const raw = session.checked(session.call(p.operations.PI_SESSION_DECODE, 0, bytes, 0, 0, 0)) catch |err| return if (err == error.OutOfMemory) err else c.pi_js_null();
    defer session.freeReply(raw);
    // Session teardown releases all image handles on every exceptional path.
    const image = @import("../ai/photon_session_orientation.zig").apply(session, raw.image, @import("../ai/photon_exif.zig").read(bytes)) catch |err| return if (err == error.OutOfMemory) err else c.pi_js_null();
    const encoded = session.checked(session.call(p.operations.PI_SESSION_PNG, image, null, 0, 0, 0)) catch |err| return if (err == error.OutOfMemory) err else c.pi_js_null();
    defer session.freeReply(encoded);
    const array_buffer = try scope.own(try engine.checked(c.JS_NewArrayBufferCopy(engine.context, encoded.bytes, encoded.length)));
    var arguments = [_]c.JSValue{array_buffer};
    return engine.checked(c.JS_CallConstructor(engine.context, try scope.global("Uint8Array"), arguments.len, &arguments));
}
