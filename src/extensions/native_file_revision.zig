//! Actual coding-agent utils/paths.ts getFileRevision: statSync(bigint), in
//! dev:ino:size:mtimeNs:ctimeNs order, with undefined for any stat/path error.
//! No normalization, tilde expansion, realpath, or content read occurs here.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const fs = @import("native_file_stat.zig");
const url = @import("native_url.zig");
const c = em.c;
const pending_owner = @import("native_pending_owner.zig");

/// The caller owns the returned string. This typed native entry is shared by
/// AuthStorage, FileAuthStorageBackend and FileModelsStore.
pub fn revision(engine: *em.Engine, path: []const u8) !?[]u8 {
    return revisionAlloc(engine.gpa, path);
}
pub fn revisionAlloc(gpa: std.mem.Allocator, path: []const u8) !?[]u8 {
    const info = fs.read(gpa, path) catch |err| {
        if (err == error.OutOfMemory) return err;
        return null;
    };
    return try format(gpa, info);
}
pub fn format(gpa: std.mem.Allocator, info: fs.Stat) ![]u8 {
    return std.fmt.allocPrint(gpa, "{d}:{d}:{d}:{d}:{d}", .{ info.dev, info.ino, info.size, info.mtime_ns, info.ctime_ns });
}

/// Public Source-value entry. Node stat accepts strings, Uint8Array/Buffer and
/// file URL objects at runtime; it rejects ordinary objects without coercing
/// their toString. The Source catch also suppresses URL getter exceptions.
pub fn getFileRevision(engine: *em.Engine, path: c.JSValue) !c.JSValue {
    var frame = pending_owner.Frame.init(engine);
    frame.enter() catch |err| return frame.finishValue(err);
    return frame.finishValue(getFileRevisionOwned(engine, path));
}
fn getFileRevisionOwned(engine: *em.Engine, path: c.JSValue) !c.JSValue {
    const previous = if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else null;
    defer if (previous) |value| engine.releaseNativeValue(value);
    return get(engine, path) catch |err| {
        // Source suppresses an ordinary stat/path/getter failure. Only the
        // actual slot/invocation or a real typed allocator result can bypass
        // that catch; diagnostic flags and a whole guest generation cannot.
        try pending_owner.catchFailure(engine, err);
        if (c.JS_HasException(engine.context)) engine.releaseNativeValue(c.JS_GetException(engine.context));
        try pending_owner.checkFatal(engine);
        // Detach the diagnostic entitlement before its destructor can record
        // another actual event, then restore the old DATA identity.
        while (engine.captured_exception) |value| {
            engine.captured_exception = null;
            engine.releaseNativeValue(value);
            try pending_owner.checkFatal(engine);
        }
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
        defer engine.releaseNativeValue(backing);
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
    var frame = pending_owner.Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    const result = getFileRevision(engine, if (argc > 0) args[0] else c.pi_js_undefined())
        catch |err| @import("native_durable.zig").reject(engine, err);
    return frame.finishCallback(result);
}
