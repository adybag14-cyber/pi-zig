//! Private Node24 read/write overload algorithms over the genuine descriptor
//! owner. The complete FileHandle class/lifecycle/streams are not installed.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const validate = @import("native_env_node_file_validation.zig");
const async_value = @import("native_agent_async.zig");
const binary_encoding = @import("binary_encoding.zig");
const c = js.c;
const Scope = h.Scope;
const Method = enum(c_int) { read, write, readv, writev };

fn zero(scope: *Scope, buffer: c.JSValue, method: Method) !c.JSValue {
    const result = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
    try scope.put(result, if (method == .read or method == .readv) "bytesRead" else "bytesWritten", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(result, if (method == .readv or method == .writev) "buffers" else "buffer", buffer);
    return result;
}
fn defaultLength(scope: *Scope, buffer: c.JSValue, offset: c.JSValue) !c.JSValue {
    return validate.binary(scope, 1, try scope.get(buffer, "byteLength"), offset);
}
fn allocateDefault(scope: *Scope, bindings: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.get(bindings, "Buffer"), "alloc", &.{c.JS_NewInt32(scope.engine.context, 16384)});
}
fn read(scope: *Scope, owner: c.JSValue, descriptor: c.JSValue, operation: c.JSValue, bindings: c.JSValue, args: []const c.JSValue) !void {
    const engine = scope.engine;
    var buffer = h.arg(args, 0);
    var offset = h.arg(args, 1);
    var length = h.arg(args, 2);
    var position = h.arg(args, 3);
    if (!validate.isView(buffer)) {
        const options = buffer;
        if (!c.JS_IsUndefined(options) and (!h.nullish(options) and (!c.JS_IsObject(options) or c.JS_IsArray(options) or c.JS_IsFunction(engine.context, options)))) return validate.invalidType(scope, bindings, "options", "of type object", options);
        buffer = try h.optional(scope, options, "buffer");
        if (c.JS_IsUndefined(buffer)) buffer = try allocateDefault(scope, bindings);
        offset = try h.optional(scope, options, "offset");
        if (c.JS_IsUndefined(offset)) offset = c.JS_NewInt32(engine.context, 0);
        length = try h.optional(scope, options, "length");
        if (c.JS_IsUndefined(length)) length = try defaultLength(scope, buffer, offset);
        position = try h.optional(scope, options, "position");
        if (c.JS_IsUndefined(position)) position = c.pi_js_null();
        if (!validate.isView(buffer)) return validate.invalidType(scope, bindings, "buffer", "an instance of Buffer, TypedArray, or DataView", buffer);
    }
    if (!c.JS_IsNull(offset) and c.JS_IsObject(offset) and !c.JS_IsFunction(engine.context, offset)) {
        const options = offset;
        offset = try scope.get(options, "offset");
        if (c.JS_IsUndefined(offset)) offset = c.JS_NewInt32(engine.context, 0);
        length = try scope.get(options, "length");
        if (c.JS_IsUndefined(length)) length = try defaultLength(scope, buffer, offset);
        position = try scope.get(options, "position");
        if (c.JS_IsUndefined(position)) position = c.pi_js_null();
    }
    if (h.nullish(offset)) offset = c.JS_NewInt32(engine.context, 0) else try validate.integer(scope, bindings, offset, "offset", 0, 9007199254740991);
    if (h.nullish(length)) length = try defaultLength(scope, buffer, offset);
    if (scope.equal(length, c.JS_NewInt32(engine.context, 0))) return async_value.settle(engine, owner, false, try zero(scope, buffer, .read));
    if (scope.equal(try scope.get(buffer, "byteLength"), c.JS_NewInt32(engine.context, 0))) return validate.emptyRead(scope, bindings, buffer);
    const buffer_length = try scope.get(buffer, "byteLength");
    if (try validate.relation(scope, 4, offset, c.JS_NewInt32(engine.context, 0))) return validate.outOfRange(scope, bindings, "offset", ">= 0", offset);
    if (try validate.relation(scope, 4, length, c.JS_NewInt32(engine.context, 0))) return validate.outOfRange(scope, bindings, "length", ">= 0", length);
    if (try validate.relation(scope, 6, try validate.binary(scope, 0, offset, length), buffer_length)) {
        const maximum = try engine.toString(try validate.binary(scope, 1, buffer_length, offset));
        defer engine.gpa.free(maximum);
        const range = try std.fmt.allocPrint(engine.gpa, "<= {s}", .{maximum});
        defer engine.gpa.free(range);
        return validate.outOfRange(scope, bindings, "length", range, length);
    }
    if (h.nullish(position)) position = c.JS_NewInt32(engine.context, -1) else try validate.readPosition(scope, bindings, position, length);
    try async_value.wait(completed, engine, owner, try scope.call(operation, descriptor, &.{ buffer, offset, length, position }), 0);
}
fn write(scope: *Scope, owner: c.JSValue, descriptor: c.JSValue, operation: c.JSValue, bindings: c.JSValue, args: []const c.JSValue) !void {
    const engine = scope.engine;
    const buffer = h.arg(args, 0);
    var offset = h.arg(args, 1);
    var length = h.arg(args, 2);
    var position = h.arg(args, 3);
    if (!h.nullish(buffer) and scope.equal(try scope.get(buffer, "byteLength"), c.JS_NewInt32(engine.context, 0))) return async_value.settle(engine, owner, false, try zero(scope, buffer, .write));
    if (validate.isView(buffer)) {
        // typeof null is object, so null options receive the empty object defaults.
        if (c.JS_IsNull(offset) or (c.JS_IsObject(offset) and !c.JS_IsFunction(engine.context, offset))) {
            const options = offset;
            offset = try h.optional(scope, options, "offset");
            if (c.JS_IsUndefined(offset)) offset = c.JS_NewInt32(engine.context, 0);
            length = try h.optional(scope, options, "length");
            if (c.JS_IsUndefined(length)) length = try defaultLength(scope, buffer, offset);
            position = try h.optional(scope, options, "position");
            if (c.JS_IsUndefined(position)) position = c.pi_js_null();
        }
        if (h.nullish(offset)) offset = c.JS_NewInt32(engine.context, 0) else try validate.integer(scope, bindings, offset, "offset", 0, 9007199254740991);
        if (!c.JS_IsNumber(length)) length = try defaultLength(scope, buffer, offset);
        if (!c.JS_IsNumber(position)) position = c.pi_js_null();
        const byte_length = try scope.get(buffer, "byteLength");
        if (try validate.relation(scope, 6, offset, byte_length)) {
            const maximum = try engine.toString(byte_length);
            defer engine.gpa.free(maximum);
            const range = try std.fmt.allocPrint(engine.gpa, "<= {s}", .{maximum});
            defer engine.gpa.free(range);
            return validate.outOfRange(scope, bindings, "offset", range, offset);
        }
        const available = try validate.binary(scope, 1, byte_length, offset);
        if (try validate.relation(scope, 6, length, available)) {
            const maximum = try engine.toString(try validate.binary(scope, 1, byte_length, offset));
            defer engine.gpa.free(maximum);
            const range = try std.fmt.allocPrint(engine.gpa, "<= {s}", .{maximum});
            defer engine.gpa.free(range);
            return validate.outOfRange(scope, bindings, "length", range, length);
        }
        if (try validate.relation(scope, 4, length, c.JS_NewInt32(engine.context, 0))) return validate.outOfRange(scope, bindings, "length", ">= 0", length);
        try validate.integer(scope, bindings, length, "length", 0, std.math.maxInt(i32));
        try async_value.wait(completed, engine, owner, try scope.call(operation, descriptor, &.{ buffer, offset, length, position }), 0);
        return;
    }
    if (!c.JS_IsString(buffer)) return validate.invalidType(scope, bindings, "buffer", "of type string or an instance of Buffer, TypedArray, or DataView", buffer);
    const encoding_text = if (c.JS_IsString(length)) try engine.toString(length) else try engine.gpa.dupe(u8, "utf8");
    defer engine.gpa.free(encoding_text);
    const encoding = binary_encoding.parse(encoding_text) orelse .utf8;
    if (encoding == .hex) {
        const string_length = try validate.number(scope, try scope.get(buffer, "length"));
        if (@mod(string_length, 2) != 0) {
            const reason = try std.fmt.allocPrint(engine.gpa, "is invalid for data of length {d}", .{@as(usize, @intFromFloat(string_length))});
            defer engine.gpa.free(reason);
            return validate.invalidValue(scope, bindings, "encoding", reason, length);
        }
    }
    const text = try engine.toString(buffer);
    defer engine.gpa.free(text);
    const bytes = try binary_encoding.encode(engine.gpa, text, encoding);
    defer engine.gpa.free(bytes);
    const encoded = try scope.own(try @import("node_buffer.zig").fromBytes(engine, bytes));
    try scope.put(owner, "stringBuffer", buffer);
    try scope.put(owner, "hasStringBuffer", c.pi_js_bool(engine.context, 1));
    try async_value.wait(completed, engine, owner, try scope.call(operation, descriptor, &.{ encoded, c.JS_NewInt32(engine.context, 0), c.JS_NewFloat64(engine.context, @floatFromInt(bytes.len)), offset }), 0);
}
fn vector(scope: *Scope, owner: c.JSValue, descriptor: c.JSValue, operation: c.JSValue, bindings: c.JSValue, args: []const c.JSValue, method: Method) !void {
    const buffer = h.arg(args, 0);
    try validate.bufferArray(scope, bindings, buffer);
    const position = if (c.JS_IsNumber(h.arg(args, 1))) h.arg(args, 1) else c.pi_js_null();
    if (method == .writev and scope.equal(try scope.get(buffer, "length"), c.JS_NewInt32(scope.engine.context, 0))) return async_value.settle(scope.engine, owner, false, try zero(scope, buffer, method));
    try async_value.wait(completed, scope.engine, owner, try scope.call(operation, descriptor, &.{ buffer, position }), 0);
}
fn completed(engine: *js.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!rejected and scope.truthy(try scope.get(owner, "hasStringBuffer"))) try scope.set(value, "buffer", try scope.get(owner, "stringBuffer"));
    try async_value.settle(engine, owner, rejected, value);
}
fn begin(scope: *Scope, owner: c.JSValue, descriptor: c.JSValue, operation: c.JSValue, bindings: c.JSValue, args: []const c.JSValue, method: Method) !void {
    if (scope.equal(try scope.get(descriptor, "fd"), c.JS_NewInt32(scope.engine.context, -1))) return async_value.wait(completed, scope.engine, owner, try scope.call(operation, descriptor, args), 0);
    switch (method) {
        .read => try read(scope, owner, descriptor, operation, bindings, args),
        .write => try write(scope, owner, descriptor, operation, bindings, args),
        .readv, .writev => try vector(scope, owner, descriptor, operation, bindings, args, method),
    }
}
fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, method: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = call(&scope, roots[0], roots[1], roots[2], if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(method)) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    return result;
}
fn call(scope: *Scope, descriptor: c.JSValue, operation: c.JSValue, bindings: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    const pending = try async_value.create(scope.engine, descriptor);
    defer scope.engine.freeValue(pending.owner);
    errdefer scope.engine.freeValue(pending.promise);
    begin(scope, pending.owner, descriptor, operation, bindings, args, method) catch |err| try async_value.rejectError(scope.engine, pending.owner, err);
    return pending.promise;
}
// Explicit private installation for qualification only. This does not create,
// export or replace the public FileHandle class or its symbol/ref lifecycle.
pub fn installPrivate(scope: *Scope, descriptor: c.JSValue) !void {
    const bindings = try validate.prepare(scope);
    inline for (std.meta.fields(Method)) |field| {
        var roots = [_]c.JSValue{ descriptor, try scope.get(descriptor, field.name), bindings };
        const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, invoke, field.name, if (field.value < 2) 4 else 2, @intCast(field.value), roots.len, &roots)));
        try scope.put(descriptor, field.name, function);
    }
}
