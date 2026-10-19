//! Native Node24 stat/Stats/realpath semantics, derived from the genuine
//! Source22 caller capture and the pinned Node lib/internal/fs/utils.js.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const em = @import("engine.zig");
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const functions = @import("native_node_function.zig");
const stat = @import("native_file_stat.zig");
const url = @import("native_url.zig");
const buffer = @import("node_buffer.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const fields = [_][:0]const u8{ "dev", "mode", "nlink", "uid", "gid", "rdev", "blksize", "ino", "size", "blocks", "atimeMs", "mtimeMs", "ctimeMs", "birthtimeMs" };
const dates = [_][:0]const u8{ "atime", "mtime", "ctime", "birthtime" };
const nanos = [_][:0]const u8{ "atimeNs", "mtimeNs", "ctimeNs", "birthtimeNs" };

fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn setPrototype(engine: *em.Engine, value: c.JSValue, prototype: c.JSValue) !void {
    if (c.JS_SetPrototype(engine.context, value, prototype) < 0) return js.capture(engine);
}
fn baseConstructor(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    inline for (fields[0..10], 0..) |name, index| try js.define(engine, receiver, name, c.JS_DupValue(engine.context, argument(args, index)));
    return c.pi_js_undefined();
}
fn statsConstructor(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const ignored = try baseConstructor(engine, receiver, args, &.{});
    engine.freeValue(ignored);
    const big = c.JS_ToBool(engine.context, roots[0]) == 1;
    inline for (fields[10..], 0..) |name, index| {
        const value = argument(args, index + 10);
        const milliseconds = if (big) try arithmetic.binary(engine, .divide, value, try scope.own(try engine.checked(c.JS_NewBigInt64(engine.context, 1000000)))) else c.JS_DupValue(engine.context, value);
        try js.define(engine, receiver, name, milliseconds);
    }
    if (big) inline for (nanos, 0..) |name, index| try js.define(engine, receiver, name, c.JS_DupValue(engine.context, argument(args, index + 10)));
    return c.pi_js_undefined();
}
fn deprecatedStats(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return js.call(engine, roots[0], receiver, args);
}
fn typeMethod(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return js.invoke(engine, receiver, "_checkModeProperty", &.{roots[0]});
}
fn checkMode(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const property = argument(args, 0);
    if (builtin.os.tag == .windows) for ([_]i32{ 0o010000, 0o060000, 0o140000 }) |kind| {
        if (c.JS_IsStrictEqual(engine.context, property, c.JS_NewInt32(engine.context, kind))) return c.pi_js_bool(engine.context, 0);
    };
    const big = c.JS_ToBool(engine.context, roots[0]) == 1;
    const mask = if (big) try scope.own(try engine.checked(c.JS_NewBigInt64(engine.context, 0o170000))) else c.JS_NewInt32(engine.context, 0o170000);
    const value = try scope.own(try arithmetic.binary(engine, .bit_and, try scope.get(receiver, "mode"), mask));
    const compared = if (big) try scope.call(engine.intrinsic_bigint_constructor, c.pi_js_undefined(), &.{property}) else property;
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, value, compared)));
}
fn dateInvoke(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return dateOperation(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined(), @intCast(magic)) catch |err| {
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
        return engine.throwCaptured();
    };
}
fn dateOperation(engine: *em.Engine, receiver: c.JSValue, supplied: c.JSValue, index: usize) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var value = supplied;
    if (index < 4) {
        const milliseconds = switch (index) {
            0 => try scope.get(receiver, "atimeMs"),
            1 => try scope.get(receiver, "mtimeMs"),
            2 => try scope.get(receiver, "ctimeMs"),
            else => try scope.get(receiver, "birthtimeMs"),
        };
        const number = try scope.call(try scope.global("Number"), c.pi_js_undefined(), &.{milliseconds});
        const rounded = try scope.invoke(try scope.global("Math"), "round", &.{number});
        var numeric: f64 = undefined;
        if (c.JS_ToFloat64(engine.context, &numeric, rounded) < 0) return js.capture(engine);
        value = try scope.own(try engine.checked(c.JS_NewDate(engine.context, numeric)));
    }
    const atom = try js.atom(engine, try scope.text(dates[index % 4]));
    defer c.JS_FreeAtom(engine.context, atom);
    // Source's setter supplies only {value,writable:true}; these new own
    // Date fields are nonenumerable and nonconfigurable.
    if (c.JS_DefinePropertyValue(engine.context, receiver, atom, c.JS_DupValue(engine.context, value), c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return if (index < 4) c.JS_DupValue(engine.context, value) else c.pi_js_undefined();
}
fn addDates(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (dates, 0..) |name, index| {
        const getter = try engine.checked(c.pi_js_function_magic(engine.context, dateInvoke, "get", 0, index));
        defer engine.freeValue(getter);
        const setter = try engine.checked(c.pi_js_function_magic(engine.context, dateInvoke, "set", 1, index + 4));
        defer engine.freeValue(setter);
        const atom = c.JS_NewAtom(engine.context, name);
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, getter), c.JS_DupValue(engine.context, setter), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const base = try scope.own(try functions.create(engine, "StatsBase", 10, baseConstructor, &.{}));
    const base_prototype = try scope.get(base, "prototype");
    inline for (.{ .{ "isDirectory", 0o040000 }, .{ "isFile", 0o100000 }, .{ "isBlockDevice", 0o060000 }, .{ "isCharacterDevice", 0o020000 }, .{ "isSymbolicLink", 0o120000 }, .{ "isFIFO", 0o010000 }, .{ "isSocket", 0o140000 } }) |method| {
        try scope.put(base_prototype, method[0], try scope.own(try functions.create(engine, "", 0, typeMethod, &.{c.JS_NewInt32(engine.context, method[1])})));
    }
    var prototypes: [2]c.JSValue = undefined;
    var numeric_constructor: c.JSValue = undefined;
    inline for (.{ "Stats", "BigIntStats" }, 0..) |name, index| {
        const flag = c.pi_js_bool(engine.context, @intCast(index));
        const constructor = try scope.own(try functions.create(engine, name, 14, statsConstructor, &.{flag}));
        if (index == 0) numeric_constructor = constructor;
        prototypes[index] = try scope.get(constructor, "prototype");
        try setPrototype(engine, constructor, base);
        try setPrototype(engine, prototypes[index], base_prototype);
        try addDates(engine, prototypes[index]);
        try scope.put(prototypes[index], "_checkModeProperty", try scope.own(try functions.create(engine, "", 1, checkMode, &.{flag})));
    }
    const deprecated = try scope.own(try functions.create(engine, "deprecated", 14, deprecatedStats, &.{numeric_constructor}));
    try setPrototype(engine, deprecated, numeric_constructor);
    if (c.JS_DefinePropertyValueStr(engine.context, deprecated, "prototype", c.JS_DupValue(engine.context, prototypes[0]), c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    try scope.put(exports, "Stats", deprecated);
    try scope.put(exports, "statSync", try scope.own(try functions.create(engine, "statSync", 1, statSync, &prototypes)));
    try scope.put(exports, "lstatSync", try scope.own(try functions.create(engine, "lstatSync", 1, lstatSync, &prototypes)));
    const realpath_function = try scope.own(try functions.create(engine, "realpathSync", 2, realpathSync, &.{}));
    const native = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, realpathNative, "", 2)));
    try scope.put(realpath_function, "native", native);
    try scope.put(exports, "realpathSync", realpath_function);
}

pub fn throwTyped(engine: *em.Engine, code: []const u8, message: []const u8) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const error_value = try scope.own(try js.builtin(engine, "TypeError", &.{}));
    try scope.put(error_value, "code", try scope.text(code));
    if (c.JS_DefinePropertyValueStr(engine.context, error_value, "message", c.JS_DupValue(engine.context, try scope.text(message)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, error_value)));
}
pub fn pathText(engine: *em.Engine, value: c.JSValue, coerce: bool) ![]u8 {
    return pathTextNamed(engine, value, coerce, "path");
}
pub fn pathTextNamed(engine: *em.Engine, value: c.JSValue, coerce: bool, label: []const u8) ![]u8 {
    var path: []u8 = undefined;
    if (url.isURL(engine, value)) {
        path = try url.filePath(engine, value, builtin.os.tag == .windows);
    } else if (c.JS_IsString(value) or coerce) {
        path = try engine.toString(value);
    } else if (c.JS_GetTypedArrayType(value) == c.JS_TYPED_ARRAY_UINT8) {
        var offset: usize = 0;
        var length: usize = 0;
        var element: usize = 0;
        const backing = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, value, &offset, &length, &element));
        defer engine.freeValue(backing);
        var total: usize = 0;
        const bytes = c.JS_GetArrayBuffer(engine.context, &total, backing);
        if (offset > total or length > total - offset or (bytes == null and length != 0)) return error.InvalidFileStatPath;
        path = try engine.gpa.dupe(u8, if (length == 0) &.{} else bytes[offset .. offset + length]);
    } else {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const received = if (c.JS_IsObject(value)) try engine.toString(try scope.get(try scope.get(value, "constructor"), "name")) else try engine.toString(value);
        defer engine.gpa.free(received);
        const message = try std.fmt.allocPrint(engine.gpa, "The \"{s}\" argument must be of type string or an instance of Buffer or URL. Received {s}{s}", .{ label, if (c.JS_IsObject(value)) "an instance of " else "", received });
        defer engine.gpa.free(message);
        _ = try throwTyped(engine, "ERR_INVALID_ARG_TYPE", message);
        unreachable;
    }
    errdefer engine.gpa.free(path);
    if (std.mem.indexOfScalar(u8, path, 0) != null) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const original = try scope.text(path);
        const inspected = try @import("node_event_inspect.zig").inspect(engine, original, 2);
        defer engine.gpa.free(inspected);
        const inspected_value = try scope.text(inspected);
        const units = try @import("native_utf16.zig").unitsAlloc(engine, inspected_value);
        defer engine.gpa.free(units);
        const truncated = if (units.len > 128) try scope.invoke(inspected_value, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, 128) }) else inspected_value;
        const text = try engine.toString(truncated);
        defer engine.gpa.free(text);
        const message = try std.fmt.allocPrint(engine.gpa, "The argument '{s}' must be a string, Uint8Array, or URL without null bytes. Received {s}{s}", .{ label, text, if (units.len > 128) "..." else "" });
        defer engine.gpa.free(message);
        _ = try throwTyped(engine, "ERR_INVALID_ARG_VALUE", message);
        unreachable;
    }
    return path;
}
fn throwFilesystem(engine: *em.Engine, err: anyerror, path: []const u8, syscall: []const u8) !c.JSValue {
    if (err == error.OutOfMemory) return err;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const code: []const u8 = switch (err) {
        error.FileNotFound => "ENOENT",
        error.AccessDenied => "EACCES",
        error.NotDir => "ENOTDIR",
        else => return err,
    };
    const reason: []const u8 = switch (err) {
        error.FileNotFound => "no such file or directory",
        error.AccessDenied => "permission denied",
        error.NotDir => "not a directory",
        else => unreachable,
    };
    const errno: i32 = switch (err) {
        error.FileNotFound => if (builtin.os.tag == .windows) -4058 else -2,
        error.AccessDenied => if (builtin.os.tag == .windows) -4092 else -13,
        error.NotDir => if (builtin.os.tag == .windows) -4052 else -20,
        else => unreachable,
    };
    const message = try std.fmt.allocPrint(engine.gpa, "{s}: {s}, {s} '{s}'", .{ code, reason, syscall, path });
    defer engine.gpa.free(message);
    const value = try scope.own(try js.builtin(engine, "Error", &.{try scope.text(message)}));
    try scope.put(value, "errno", c.JS_NewInt32(engine.context, errno));
    try scope.put(value, "code", try scope.text(code));
    try scope.put(value, "syscall", try scope.text(syscall));
    try scope.put(value, "path", try scope.text(path));
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
}
fn integer(engine: *em.Engine, value: i128, big: bool) !c.JSValue {
    if (!big) return c.JS_NewFloat64(engine.context, @floatFromInt(value));
    const decimal = try std.fmt.allocPrint(engine.gpa, "{d}", .{value});
    defer engine.gpa.free(decimal);
    const text = try engine.checked(c.JS_NewStringLen(engine.context, decimal.ptr, decimal.len));
    defer engine.freeValue(text);
    // Node's stats binding/primordial BigInt do not consult a later guest
    // global replacement. Engine retains this real intrinsic from bootstrap.
    return js.call(engine, engine.intrinsic_bigint_constructor, c.pi_js_undefined(), &.{text});
}
fn statSync(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return readStats(engine, args, roots, true);
}
fn lstatSync(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return readStats(engine, args, roots, false) catch |err| return lstatFailure(engine, err, generation);
}
fn lstatFailure(engine: *em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.OutOfMemory) {
        _ = engine.throwNativeOutOfMemory();
        const reason = c.JS_GetException(engine.context);
        c.JS_SetUncatchableError(engine.context, reason);
        _ = c.JS_Throw(engine.context, reason);
        return error.JavaScriptException;
    }
    if (err != error.JavaScriptException) return err;
    if (engine.captured_exception) |reason| {
        @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| {
            if (fatal != error.JavaScriptException) return fatal;
        };
        // Transfer the one owned ordinary/fatal captured reason back to the
        // pending VM completion before the generic callback exit runs. No
        // stale ordinary captured copy remains after a guest catch returns.
        if (engine.captured_exception) |owned| {
            engine.captured_exception = null;
            _ = c.JS_Throw(engine.context, owned);
        }
    }
    return error.JavaScriptException;
}
fn readStats(engine: *em.Engine, args: []const c.JSValue, roots: []const c.JSValue, follow: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = try pathText(engine, argument(args, 0), false);
    defer engine.gpa.free(path);
    const options = argument(args, 1);
    const defaults = c.JS_IsUndefined(options);
    const big = !defaults and c.JS_IsStrictEqual(engine.context, try scope.get(options, "bigint"), c.pi_js_bool(engine.context, 1));
    const throw_missing = defaults or !c.JS_IsStrictEqual(engine.context, try scope.get(options, "throwIfNoEntry"), c.pi_js_bool(engine.context, 0));
    const info = (if (follow) stat.read(engine.gpa, path) else lstatMetadata(engine, path, throw_missing)) catch |err| {
        if (err == error.FileNotFound and !throw_missing) return c.pi_js_undefined();
        return throwFilesystem(engine, err, path, if (follow) "stat" else "lstat");
    };
    // Node's public stat binding writes the same 36-slot record before creating
    // Stats. A cache callback can reenter here while classic realpath retains
    // that actual shared numeric array.
    try @import("native_node_fs_stat_values.zig").updateIfInstalled(engine, big, info);
    const result = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, roots[@intFromBool(big)])));
    const values = [_]i128{ info.dev, info.mode, info.nlink, info.uid, info.gid, info.rdev, info.blksize, info.ino, info.size, info.blocks };
    inline for (fields[0..10], 0..) |name, index| try scope.put(result, name, try scope.own(try integer(engine, values[index], big)));
    const times = [_]i128{ info.atime_ns, info.mtime_ns, info.ctime_ns, info.birthtime_ns };
    inline for (fields[10..], 0..) |name, index| {
        const value = if (big) try scope.own(try integer(engine, @divTrunc(times[index], 1000000), true)) else c.JS_NewFloat64(engine.context, @as(f64, @floatFromInt(@divFloor(times[index], 1000000000))) * 1000 + @as(f64, @floatFromInt(@mod(times[index], 1000000000))) / 1000000);
        try scope.put(result, name, value);
    }
    if (big) inline for (nanos, 0..) |name, index| try scope.put(result, name, try scope.own(try integer(engine, times[index], true)));
    return c.JS_DupValue(engine.context, result);
}
fn lstatMetadata(engine: *em.Engine, path: []const u8, throw_missing: bool) !stat.Stat {
    return switch (try stat.readLink(engine.gpa, path)) {
        .metadata => |value| value,
        .windows_error => |raw| {
            const errors = @import("native_node_lstat_error.zig");
            const code = errors.translate(raw);
            if (code == .ENOENT and !throw_missing) return error.FileNotFound;
            return errors.throwFilesystem(engine, code, path);
        },
    };
}
fn realpathNative(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return realpath(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, true) catch |err| {
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
        return engine.throwCaptured();
    };
}
fn realpathSync(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return realpath(engine, args, false);
}
fn realpath(engine: *em.Engine, args: []const c.JSValue, native: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = argument(args, 1);
    // Source getOptions observes the encoding getter before validating paths.
    const encoding = if (c.JS_IsString(options)) options else if (c.JS_IsNull(options) or c.JS_IsUndefined(options)) c.pi_js_undefined() else try scope.get(options, "encoding");
    const path = try pathText(engine, argument(args, 0), !native);
    defer engine.gpa.free(path);
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    var directory = try std.Io.Dir.cwd().openDir(io, ".", .{});
    defer directory.close(io);
    var current: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try directory.realPath(io, &current);
    const absolute = try @import("node_path.zig").resolve(engine.gpa, current[0..length], &.{path}, if (builtin.os.tag == .windows) .win32 else .posix);
    defer engine.gpa.free(absolute);
    if (!native) {
        var index: usize = if (builtin.os.tag == .windows and absolute.len > 2 and absolute[1] == ':') 3 else 1;
        while (index <= absolute.len) : (index += 1) {
            if (index != absolute.len and absolute[index] != '/' and absolute[index] != '\\') continue;
            _ = stat.read(engine.gpa, absolute[0..index]) catch |err| return throwFilesystem(engine, err, absolute[0..index], "lstat");
        }
    }
    const physical = if (builtin.os.tag == .windows) try stat.windowsNamespacedPath(engine.gpa, absolute) else try engine.gpa.dupe(u8, absolute);
    defer engine.gpa.free(physical);
    var output: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = std.Io.Dir.cwd().realPathFile(io, physical, &output) catch |err| return throwFilesystem(engine, err, path, if (native) "realpath" else "lstat");
    if (c.JS_IsString(encoding)) {
        const codec = try engine.toString(encoding);
        defer engine.gpa.free(codec);
        if (std.mem.eql(u8, codec, "buffer")) return buffer.fromBytes(engine, output[0..count]);
        const selected = buffer.encodings.parse(codec) orelse return error.UnsupportedNativeTextEncoding;
        const text = try buffer.encodings.decode(engine.gpa, output[0..count], selected);
        defer engine.gpa.free(text);
        return engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
    }
    return engine.checked(c.JS_NewStringLen(engine.context, &output, count));
}
