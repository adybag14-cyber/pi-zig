//! Actual coding-agent utils/paths.ts getFileRevision: statSync(bigint), in
//! dev:ino:size:mtimeNs:ctimeNs order, with undefined for any stat/path error.
//! No normalization, tilde expansion, realpath, or content read occurs here.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const fs = @import("native_file_stat.zig");
const url = @import("native_url.zig");
const c = em.c;

/// The caller owns the returned string. This typed native entry is shared by
/// AuthStorage, FileAuthStorageBackend and FileModelsStore.
pub fn revision(engine: *em.Engine, path: []const u8) !?[]u8 {
    return revisionAlloc(engine.gpa, path);
}
pub fn revisionAlloc(gpa: std.mem.Allocator, path: []const u8) !?[]u8 {
    const info = fs.read(gpa, path) catch return null;
    return format(gpa, info);
}
pub fn format(gpa: std.mem.Allocator, info: fs.Stat) ![]u8 {
    return std.fmt.allocPrint(gpa, "{d}:{d}:{d}:{d}:{d}", .{ info.dev, info.ino, info.size, info.mtime_ns, info.ctime_ns });
}

/// Public Source-value entry. Node stat accepts strings, Uint8Array/Buffer and
/// file URL objects at runtime; it rejects ordinary objects without coercing
/// their toString. The Source catch also suppresses URL getter exceptions.
pub fn getFileRevision(engine: *em.Engine, path: c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    const previous = if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else null;
    defer if (previous) |value| engine.freeValue(value);
    return get(engine, path) catch |err| {
        // Preserve the host's private allocator-failure boundary even when a
        // URL getter transports that marked error through a JS callback. A
        // user Error merely named OutOfMemory still follows Source's catch.
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
        // A caught URL getter exception must not replace the host's retained
        // exception identity with a failure that Source has suppressed.
        if (engine.captured_exception) |value| engine.freeValue(value);
        engine.captured_exception = if (previous) |value| c.JS_DupValue(engine.context, value) else null;
        return c.pi_js_undefined();
    };
}
fn pathText(engine: *em.Engine, value: c.JSValue) ![]u8 {
    if (c.JS_IsString(value)) return engine.toString(value);
    if (url.isURL(engine, value)) return url.filePath(engine, value, builtin.os.tag == .windows);
    if (c.JS_GetTypedArrayType(value) == c.JS_TYPED_ARRAY_UINT8) {
        var offset: usize = 0;
        var length: usize = 0;
        var element: usize = 0;
        const backing = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, value, &offset, &length, &element));
        defer engine.freeValue(backing);
        var total: usize = 0;
        const bytes = c.JS_GetArrayBuffer(engine.context, &total, backing);
        if (c.JS_HasException(engine.context) or offset > total or length > total - offset or (bytes == null and length != 0)) return error.InvalidFileStatPath;
        return engine.gpa.dupe(u8, if (length == 0) &.{} else bytes[offset .. offset + length]);
    }
    return error.InvalidFileStatPath;
}
fn get(engine: *em.Engine, path: c.JSValue) !c.JSValue {
    const text = try pathText(engine, path);
    defer engine.gpa.free(text);
    const value = (try revision(engine, text)) orelse return c.pi_js_undefined();
    defer engine.gpa.free(value);
    return engine.checked(c.JS_NewStringLen(engine.context, value.ptr, value.len));
}

pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    const function = try engine.checked(c.JS_NewCFunction(engine.context, invoke, "getFileRevision", 1));
    try @import("native_js_values.zig").define(engine, exports, "getFileRevision", function);
}
fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return getFileRevision(engine, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
