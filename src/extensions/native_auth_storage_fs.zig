//! Actual auth-storage filesystem binding with creation-only 0600/0700 modes.
//! Existing shared Node writes reject mode, so this native boundary implements
//! the Source operations directly rather than deleting the requested mode.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const fs = engine.native_module_values.get("node:fs") orelse return error.NativeAuthStorageRequiresFs;
    const result = try scope.object();
    inline for (.{ "readFileSync", "existsSync" }) |name| try scope.put(result, name, try scope.get(fs, name));
    try scope.put(result, "writeFileSync", try scope.own(try functions.create(engine, "writeFileSync", 3, write, &.{})));
    try scope.put(result, "mkdirSync", try scope.own(try functions.create(engine, "mkdirSync", 2, mkdir, &.{})));
    return c.JS_DupValue(engine.context, result);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn mode(scope: *Scope, options: c.JSValue, fallback: u32) !u32 {
    const value = try v.optional(scope, options, "mode");
    if (c.JS_IsUndefined(value)) return fallback;
    var result: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &result, value) < 0) return v.js.capture(scope.engine);
    return result;
}
fn fail(scope: *Scope, err: anyerror, syscall: []const u8, path: []const u8) anyerror {
    if (err == error.OutOfMemory) return err;
    const code: []const u8 = switch (err) {
        error.FileNotFound => "ENOENT",
        error.NotDir => "ENOTDIR",
        error.IsDir => "EISDIR",
        error.AccessDenied => "EACCES",
        error.PermissionDenied => "EPERM",
        error.PathAlreadyExists => "EEXIST",
        else => "EIO",
    };
    const desc: []const u8 = if (std.mem.eql(u8, code, "ENOENT")) "no such file or directory" else if (std.mem.eql(u8, code, "ENOTDIR")) "not a directory" else if (std.mem.eql(u8, code, "EISDIR")) "illegal operation on a directory" else if (std.mem.eql(u8, code, "EACCES")) "permission denied" else if (std.mem.eql(u8, code, "EPERM")) "operation not permitted" else if (std.mem.eql(u8, code, "EEXIST")) "file already exists" else "i/o error";
    const text = std.fmt.allocPrint(scope.engine.gpa, "{s}: {s}, {s} '{s}'", .{ code, desc, syscall, path }) catch |failure| return failure;
    defer scope.engine.gpa.free(text);
    const value = scope.own(v.js.builtin(scope.engine, "Error", &.{scope.text(text) catch |failure| return failure}) catch |failure| return failure) catch |failure| return failure;
    scope.put(value, "code", scope.text(code) catch |failure| return failure) catch |failure| return failure;
    scope.put(value, "syscall", scope.text(syscall) catch |failure| return failure) catch |failure| return failure;
    scope.put(value, "path", scope.text(path) catch |failure| return failure) catch |failure| return failure;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, value))) catch |failure| return failure;
    unreachable;
}
fn write(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const io = engine.native_io orelse return error.NativeAuthStorageRequiresIo;
    const path = try @import("native_url.zig").filePath(engine, arg(args, 0), builtin.os.tag == .windows);
    defer engine.gpa.free(path);
    const options = arg(args, 2);
    const encoding_value = if (c.JS_IsString(options)) options else try v.optional(&scope, options, "encoding");
    const encoding_name = if (v.nullish(encoding_value)) try engine.gpa.dupe(u8, "utf-8") else try engine.toString(encoding_value);
    defer engine.gpa.free(encoding_name);
    const encoding = @import("binary_encoding.zig").parse(encoding_name) orelse return error.UnsupportedNativeTextEncoding;
    const creation_mode = try mode(&scope, if (c.JS_IsString(options)) c.pi_js_undefined() else options, 0o666);
    const data = arg(args, 1);
    var owned: ?[]u8 = null;
    defer if (owned) |bytes| engine.gpa.free(bytes);
    var backing: ?c.JSValue = null;
    defer if (backing) |value| engine.freeValue(value);
    const content: []const u8 = if (c.JS_IsString(data)) text: {
        const input = try engine.toString(data);
        defer engine.gpa.free(input);
        owned = try @import("binary_encoding.zig").encode(engine.gpa, input, encoding);
        break :text owned.?;
    } else bytes: {
        var offset: usize = 0;
        var count: usize = 0;
        var width: usize = 0;
        backing = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, data, &offset, &count, &width));
        var length: usize = 0;
        const raw = c.JS_GetArrayBuffer(engine.context, &length, backing.?);
        if (raw == null and c.JS_HasException(engine.context)) return v.js.capture(engine);
        if (offset > length or count > length - offset) return error.InvalidNativeBufferRange;
        break :bytes if (count == 0) &.{} else raw[offset .. offset + count];
    };
    const permissions = if (@hasDecl(std.Io.File.Permissions, "fromMode")) std.Io.File.Permissions.fromMode(creation_mode) else std.Io.File.Permissions.default_file;
    const file = std.Io.Dir.cwd().createFile(io, path, .{ .permissions = permissions }) catch |err| return fail(&scope, err, "open", path);
    defer file.close(io);
    file.writePositionalAll(io, content, 0) catch |err| return fail(&scope, err, "write", path);
    return c.pi_js_undefined();
}
fn mkdir(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const io = engine.native_io orelse return error.NativeAuthStorageRequiresIo;
    const path = try @import("native_url.zig").filePath(engine, arg(args, 0), builtin.os.tag == .windows);
    defer engine.gpa.free(path);
    const options = arg(args, 1);
    const creation_mode = try mode(&scope, options, 0o777);
    const permissions = if (@hasDecl(std.Io.Dir.Permissions, "fromMode")) std.Io.Dir.Permissions.fromMode(creation_mode) else std.Io.Dir.Permissions.default_dir;
    if (scope.truthy(try v.optional(&scope, options, "recursive"))) {
        _ = std.Io.Dir.cwd().createDirPathStatus(io, path, permissions) catch |err| return fail(&scope, err, "mkdir", path);
    } else std.Io.Dir.cwd().createDir(io, path, permissions) catch |err| return fail(&scope, err, "mkdir", path);
    return c.pi_js_undefined();
}
