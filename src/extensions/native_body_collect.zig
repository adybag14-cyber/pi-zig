//! Owned byte consumption shared by native HTTP JSON and web Body facades.
//! Chunks remain GC-visible until EOF, matching Undici readAllBytes. This
//! collector never releases a reader lock. The byte budget is a native resource
//! policy, not an upstream body-size promise.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const flow = @import("native_agent_async.zig");
pub const Mode = enum { bytes, array_buffer, text };
pub const Input = enum { reader, byte_events };
pub const Options = struct {
    mode: Mode = .bytes,
    input: Input = .reader,
    max_bytes: ?usize = null,
    signal: ?c.JSValue = null,
    /// Optional bound native cancellation function. Receives the original reason.
    cancel: ?c.JSValue = null,
};
pub fn budget(engine: *v.em.Engine) usize {
    return @min(32 * 1024 * 1024, engine.options.memory_limit / 4);
}
pub fn collect(engine: *v.em.Engine, source: c.JSValue, options: Options) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, source);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const owner = pending.owner;
    try scope.put(owner, "chunks", try scope.array());
    try scope.put(owner, "total", c.JS_NewFloat64(engine.context, 0));
    try scope.put(owner, "retained", c.JS_NewFloat64(engine.context, 0));
    try scope.put(owner, "limit", c.JS_NewFloat64(engine.context, @floatFromInt(@min(options.max_bytes orelse budget(engine), budget(engine)))));
    try scope.put(owner, "mode", c.JS_NewInt32(engine.context, @intFromEnum(options.mode)));
    try scope.put(owner, "framed", c.pi_js_bool(engine.context, @intFromBool(options.input == .byte_events)));
    try scope.put(owner, "signal", options.signal orelse c.pi_js_undefined());
    try scope.put(owner, "cancel", options.cancel orelse c.pi_js_undefined());
    try scope.put(owner, "finished", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "listener", c.pi_js_undefined());
    start(&scope, owner) catch |err| try fail(&scope, owner, err);
    return pending.promise;
}
fn start(scope: *Scope, owner: c.JSValue) !void {
    const signal = try scope.get(owner, "signal");
    if (!v.nullish(signal)) {
        if (scope.truthy(try scope.get(signal, "aborted"))) return finish(scope, owner, true, try scope.get(signal, "reason"), true);
        const Abort = struct {
            fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                engine.native_exception_diagnostics_suppressed += 1;
                defer engine.native_exception_diagnostics_suppressed -= 1;
                var row: Scope = .{ .engine = engine };
                defer row.deinit();
                if (!row.truthy(try row.get(roots[0], "finished"))) try finish(&row, roots[0], true, try row.get(try row.get(roots[0], "signal"), "reason"), true);
                return c.pi_js_undefined();
            }
        };
        const listener = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 0, Abort.call, &.{owner}));
        try scope.put(owner, "listener", listener);
        const once = try scope.object();
        try scope.put(once, "once", c.pi_js_bool(scope.engine.context, 1));
        _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), listener, once });
    }
    try read(scope, owner);
}
fn read(scope: *Scope, owner: c.JSValue) !void {
    const source = try scope.get(owner, "agent");
    const next = try scope.invoke(source, if (scope.truthy(try scope.get(owner, "framed"))) "next" else "read", &.{});
    try flow.wait(continued, scope.engine, owner, next, 0);
}
fn number(scope: *Scope, owner: c.JSValue, name: [*:0]const u8) !usize {
    var value: f64 = 0;
    if (c.JS_ToFloat64(scope.engine.context, &value, try scope.get(owner, name)) < 0) return v.js.capture(scope.engine);
    return @intFromFloat(value);
}
fn chunkBytes(scope: *Scope, chunk: c.JSValue) ![]const u8 {
    // JS_GetUint8Array accepts Uint8ClampedArray too; the brand check is separate.
    if (c.JS_GetTypedArrayType(chunk) != c.JS_TYPED_ARRAY_UINT8) {
        _ = c.JS_ThrowTypeError(scope.engine.context, "Received non-Uint8Array chunk");
        return v.js.capture(scope.engine);
    }
    var size: usize = 0;
    const bytes = c.JS_GetUint8Array(scope.engine.context, &size, chunk);
    if (bytes == null) return v.js.capture(scope.engine);
    return bytes[0..size];
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(owner, "finished"))) return;
    if (rejected) return finish(&scope, owner, true, value, false);
    advance(&scope, owner, value) catch |err| try fail(&scope, owner, err);
}
fn advance(scope: *Scope, owner: c.JSValue, row: c.JSValue) !void {
    if (scope.truthy(try scope.get(row, "done"))) return concatenate(scope, owner);
    var chunk = try scope.get(row, "value");
    if (scope.truthy(try scope.get(owner, "framed"))) {
        if (!try v.eq(scope, try scope.get(chunk, "type"), "bytes")) return error.InvalidNativeByteEvent;
        chunk = try scope.get(chunk, "data");
    }
    const bytes = try chunkBytes(scope, chunk);
    const retained = try number(scope, owner, "retained");
    const limit = try number(scope, owner, "limit");
    if (bytes.len > limit - retained) {
        const failure = try scope.own(try v.js.builtin(scope.engine, "RangeError", &.{try scope.text("Native body byte limit exceeded")}));
        try scope.put(failure, "code", try scope.text("NativeBodyLimit"));
        try scope.put(failure, "limit", c.JS_NewFloat64(scope.engine.context, @floatFromInt(limit)));
        return finish(scope, owner, true, failure, true);
    }
    const chunks = try scope.get(owner, "chunks");
    try scope.index(chunks, try v.length(scope, chunks), chunk);
    try scope.put(owner, "retained", c.JS_NewFloat64(scope.engine.context, @floatFromInt(retained + bytes.len)));
    // Undici records chunk.length with an ordinary property get and +. Keep
    // that observation separate from the native retained-byte resource budget.
    try scope.put(owner, "total", try scope.concat(try scope.get(owner, "total"), try scope.get(chunk, "length")));
    try read(scope, owner);
}
fn concatenate(scope: *Scope, owner: c.JSValue) !void {
    const raw_total = try scope.get(owner, "total");
    var numeric_total: f64 = 0;
    if (!c.JS_IsNumber(raw_total)) {
        _ = c.JS_ThrowTypeError(scope.engine.context, "Body byte length must be a number");
        return v.js.capture(scope.engine);
    }
    if (c.JS_ToFloat64(scope.engine.context, &numeric_total, raw_total) < 0) return v.js.capture(scope.engine);
    const limit = try number(scope, owner, "limit");
    if (!(numeric_total >= 0) or numeric_total > @as(f64, @floatFromInt(limit)) or @trunc(numeric_total) != numeric_total) {
        _ = c.JS_ThrowRangeError(scope.engine.context, "Body byte length is outside the native body limit");
        return v.js.capture(scope.engine);
    }
    const total: usize = @intFromFloat(numeric_total);
    const output = try scope.engine.gpa.alloc(u8, total);
    defer scope.engine.gpa.free(output);
    // Buffer.concat(bytes, recordedLength) zero-fills a short final total.
    @memset(output, 0);
    const chunks = try scope.get(owner, "chunks");
    const count = try v.length(scope, chunks);
    var offset: usize = 0;
    for (0..count) |index| {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const chunk = try v.at(&row, chunks, @intCast(index));
        const bytes = try chunkBytes(&row, chunk);
        const size = @min(bytes.len, total - offset);
        @memcpy(output[offset..][0..size], bytes[0..size]);
        offset += size;
    }
    const mode: Mode = @enumFromInt(try number(scope, owner, "mode"));
    const result = switch (mode) {
        .bytes => try scope.own(try scope.engine.checked(c.JS_NewUint8ArrayCopy(scope.engine.context, output.ptr, output.len))),
        .array_buffer => try scope.own(try scope.engine.checked(c.JS_NewArrayBufferCopy(scope.engine.context, output.ptr, output.len))),
        .text => blk: {
            const decoded = try @import("text_decoder.zig").decodeUtf8(scope.engine, output);
            defer scope.engine.gpa.free(decoded);
            break :blk try scope.text(decoded);
        },
    };
    try finish(scope, owner, false, result, false);
}
fn ignore(_: *v.em.Engine, _: c.JSValue, _: c.JSValue, _: bool, _: c_int) !void {}
fn finish(scope: *Scope, owner: c.JSValue, rejected: bool, value: c.JSValue, cancel: bool) !void {
    if (scope.truthy(try scope.get(owner, "finished"))) return;
    try scope.put(owner, "finished", c.pi_js_bool(scope.engine.context, 1));
    const signal = try scope.get(owner, "signal");
    const listener = try scope.get(owner, "listener");
    const callback = try scope.get(owner, "cancel");
    try flow.settle(scope.engine, owner, rejected, value);
    if (!v.nullish(signal) and !c.JS_IsUndefined(listener)) _ = try scope.invoke(signal, "removeEventListener", &.{ try scope.text("abort"), listener });
    try scope.put(owner, "chunks", c.pi_js_undefined());
    try scope.put(owner, "listener", c.pi_js_undefined());
    try scope.put(owner, "agent", c.pi_js_undefined());
    try scope.put(owner, "signal", c.pi_js_undefined());
    try scope.put(owner, "cancel", c.pi_js_undefined());
    if (cancel and !v.nullish(callback)) {
        // Cancellation cannot replace the already-published original reason.
        const result = scope.call(callback, c.pi_js_undefined(), &.{value}) catch {
            if (scope.engine.captured_exception) |captured| {
                scope.engine.captured_exception = null;
                scope.engine.freeValue(captured);
            }
            return;
        };
        try flow.wait(ignore, scope.engine, owner, result, 0);
    }
}
fn fail(scope: *Scope, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(scope.engine, err);
    defer scope.engine.freeValue(reason);
    if (scope.engine.captured_exception) |captured| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(captured);
    }
    try finish(scope, owner, true, reason, true);
}
