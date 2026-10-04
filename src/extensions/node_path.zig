//! Native lexical path operations for extension input on either platform.
const std = @import("std");
const builtin = @import("builtin");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;

pub const Flavor = enum { posix, win32 };
const native: Flavor = if (builtin.os.tag == .windows) .win32 else .posix;
const Method = enum(u8) { normalize, join, resolve, relative, dirname, basename, extname, isAbsolute, parse, format, toNamespacedPath };

fn separator(flavor: Flavor) u8 {
    return if (flavor == .win32) '\\' else '/';
}
fn isSep(flavor: Flavor, byte: u8) bool {
    return byte == '/' or (flavor == .win32 and byte == '\\');
}

const Root = struct { end: usize = 0, device: []const u8 = "", absolute: bool = false };
fn root(path: []const u8, flavor: Flavor) Root {
    return rootMode(path, flavor, false);
}

fn rootMode(path: []const u8, flavor: Flavor, namespace_device: bool) Root {
    if (path.len == 0) return .{};
    if (flavor == .posix) return if (path[0] == '/') .{ .end = 1, .absolute = true } else .{};
    if (path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') {
        const absolute = path.len > 2 and isSep(flavor, path[2]);
        return .{ .end = if (absolute) 3 else 2, .device = path[0..2], .absolute = absolute };
    }
    if (!isSep(flavor, path[0])) return .{};
    if (path.len > 2 and isSep(flavor, path[1]) and !isSep(flavor, path[2])) {
        var server_end: usize = 2;
        while (server_end < path.len and !isSep(flavor, path[server_end])) : (server_end += 1) {}
        var share_start = server_end;
        while (share_start < path.len and isSep(flavor, path[share_start])) : (share_start += 1) {}
        var share_end = share_start;
        while (share_end < path.len and !isSep(flavor, path[share_end])) : (share_end += 1) {}
        if (share_end > share_start) {
            if (namespace_device and server_end == 3 and (path[2] == '.' or path[2] == '?')) return .{ .end = 4, .device = path[0..3], .absolute = true };
            return .{ .end = if (share_end < path.len) share_end + 1 else share_end, .device = path[0..share_end], .absolute = true };
        }
    }
    return .{ .end = 1, .absolute = true };
}

fn writeCanonical(writer: *std.Io.Writer, text: []const u8, flavor: Flavor) !void {
    for (text) |byte| try writer.writeByte(if (isSep(flavor, byte)) separator(flavor) else byte);
}

fn writeDevice(writer: *std.Io.Writer, text: []const u8, flavor: Flavor) !void {
    if (flavor != .win32 or text.len < 2 or !isSep(flavor, text[0]) or !isSep(flavor, text[1])) return writeCanonical(writer, text, flavor);
    try writer.writeAll("\\\\");
    var parts = std.mem.splitAny(u8, text[2..], "/\\");
    var first = true;
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (!first) try writer.writeByte('\\');
        try writer.writeAll(part);
        first = false;
    }
}

fn reservedDevice(path: []const u8) bool {
    const colon = std.mem.indexOfScalar(u8, path, ':') orelse if (path.len > 0) path.len - 1 else return false;
    const name = path[0..colon];
    for ([_][]const u8{ "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9", "COM\u{b9}", "COM\u{b2}", "COM\u{b3}", "LPT\u{b9}", "LPT\u{b2}", "LPT\u{b3}" }) |reserved| if (std.ascii.eqlIgnoreCase(name, reserved)) return true;
    return false;
}

pub fn normalize(gpa: std.mem.Allocator, path: []const u8, flavor: Flavor) ![]u8 {
    if (path.len == 0) return gpa.dupe(u8, ".");
    var parsed = rootMode(path, flavor, true);
    if (flavor == .win32) {
        if (std.mem.indexOfScalar(u8, path, ':')) |colon| {
            if (colon > 0 and reservedDevice(path)) parsed = .{ .end = colon + 1, .device = path[0 .. colon + 1] };
            if (parsed.device.len == 3 and path[2] == '?' and path.len > 4 and reservedDevice(path[4..])) {
                parsed.end = colon + 1;
                parsed.device = path[0 .. colon + 1];
            }
        }
    }
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(gpa);
    var iterator = std.mem.splitAny(u8, path[parsed.end..], if (flavor == .win32) "/\\" else "/");
    while (iterator.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (parts.items.len > 0 and !std.mem.eql(u8, parts.items[parts.items.len - 1], "..")) {
                _ = parts.pop();
            } else if (!parsed.absolute) try parts.append(gpa, part);
        } else try parts.append(gpa, part);
    }
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    try writeDevice(&output.writer, parsed.device, flavor);
    if (parsed.absolute) try output.writer.writeByte(separator(flavor));
    for (parts.items, 0..) |part, index| {
        if (index > 0) try output.writer.writeByte(separator(flavor));
        try output.writer.writeAll(part);
    }
    if (parts.items.len == 0 and !parsed.absolute) try output.writer.writeByte('.');
    if (parts.items.len > 0 or !parsed.absolute) {
        if (isSep(flavor, path[path.len - 1])) try output.writer.writeByte(separator(flavor));
    }
    if (flavor == .win32 and !parsed.absolute and parsed.device.len == 0 and std.mem.indexOfScalar(u8, path, ':') != null) {
        const normalized = output.written();
        var needs_prefix = normalized.len >= 2 and std.ascii.isAlphabetic(normalized[0]) and normalized[1] == ':';
        for (path, 0..) |byte, index| if (byte == ':' and (index == path.len - 1 or isSep(flavor, path[index + 1]))) {
            needs_prefix = true;
        };
        if (needs_prefix) return std.fmt.allocPrint(gpa, ".\\{s}", .{normalized});
    }
    if (flavor == .win32 and reservedDevice(path)) return std.fmt.allocPrint(gpa, ".\\{s}", .{output.written()});
    return output.toOwnedSlice();
}

pub fn join(gpa: std.mem.Allocator, paths: []const []const u8, flavor: Flavor) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    var first: ?[]const u8 = null;
    for (paths) |path| {
        if (path.len == 0) continue;
        if (first == null) first = path else try output.writer.writeByte(separator(flavor));
        try output.writer.writeAll(path);
    }
    var joined = output.written();
    if (flavor == .win32 and first != null) {
        const initial = first.?;
        const unc = initial.len > 2 and isSep(flavor, initial[0]) and isSep(flavor, initial[1]) and !isSep(flavor, initial[2]);
        if (!unc) {
            var leading: usize = 0;
            while (leading < joined.len and isSep(flavor, joined[leading])) : (leading += 1) {}
            if (leading > 1) joined = joined[leading - 1 ..];
        }
    }
    return normalize(gpa, joined, flavor);
}

pub fn resolve(gpa: std.mem.Allocator, cwd: []const u8, paths: []const []const u8, flavor: Flavor) ![]u8 {
    var tail: std.ArrayList([]const u8) = .empty;
    defer tail.deinit(gpa);
    var absolute = false;
    var device: []const u8 = "";
    var index = paths.len;
    while (true) {
        const fallback = index == 0;
        var path = if (fallback) cwd else paths[index - 1];
        var drive_root: ?[]u8 = null;
        defer if (drive_root) |owned| gpa.free(owned);
        if (fallback and flavor == .win32 and device.len > 0 and !std.ascii.eqlIgnoreCase(root(path, flavor).device, device)) {
            drive_root = try std.fmt.allocPrint(gpa, "{s}\\", .{device});
            path = drive_root.?;
        }
        if (path.len > 0) {
            const parsed = rootMode(path, flavor, true);
            if (flavor == .win32 and parsed.device.len > 0) {
                if (device.len > 0 and !std.ascii.eqlIgnoreCase(device, parsed.device)) {
                    if (fallback) break;
                    index -= 1;
                    continue;
                }
                if (device.len == 0) device = parsed.device;
            }
            if (!absolute) {
                try tail.append(gpa, path[parsed.end..]);
                absolute = parsed.absolute;
            }
        }
        if (fallback or (absolute and (flavor == .posix or device.len > 0))) break;
        index -= 1;
    }
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    try writeDevice(&output.writer, device, flavor);
    if (absolute) try output.writer.writeByte(separator(flavor));
    var count = tail.items.len;
    while (count > 0) {
        count -= 1;
        try output.writer.writeAll(tail.items[count]);
        if (count > 0) try output.writer.writeByte(separator(flavor));
    }
    const result = try normalize(gpa, output.written(), flavor);
    errdefer gpa.free(result);
    const parsed = root(result, flavor);
    const namespace_root = flavor == .win32 and result.len == 4 and isSep(flavor, result[0]) and isSep(flavor, result[1]) and (result[2] == '.' or result[2] == '?') and isSep(flavor, result[3]);
    if (!namespace_root and result.len > parsed.end and isSep(flavor, result[result.len - 1])) return gpa.realloc(result, result.len - 1);
    return result;
}

pub fn dirname(path: []const u8, flavor: Flavor) []const u8 {
    if (path.len == 0) return ".";
    const parsed = root(path, flavor);
    var end = path.len;
    while (end > parsed.end and isSep(flavor, path[end - 1])) : (end -= 1) {}
    while (end > parsed.end and !isSep(flavor, path[end - 1])) : (end -= 1) {}
    if (end <= parsed.end) return if (parsed.end > 0) path[0..parsed.end] else ".";
    // POSIX preserves the special two-slash dirname of //file.
    if (flavor == .posix and end == 2 and path[0] == '/') return path[0..2];
    return path[0 .. end - 1];
}

pub fn basename(path: []const u8, flavor: Flavor) []const u8 {
    const start: usize = if (flavor == .win32 and path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') 2 else 0;
    var end = path.len;
    while (end > start and isSep(flavor, path[end - 1])) : (end -= 1) {}
    var begin = end;
    while (begin > start and !isSep(flavor, path[begin - 1])) : (begin -= 1) {}
    return path[begin..end];
}

pub fn extname(path: []const u8, flavor: Flavor) []const u8 {
    const base = basename(path, flavor);
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return "";
    if (dot == 0 or std.mem.eql(u8, base, "..")) return "";
    return base[dot..];
}

fn function(engine: *engine_mod.Engine, object: c.JSValue, method: Method, flavor: Flavor) !void {
    const name = @tagName(method);
    const magic: c_int = @as(c_int, @intFromEnum(method)) + if (flavor == .win32) @as(c_int, 256) else 0;
    const value = try engine.checked(c.pi_js_function_magic(engine.context, invoke, name.ptr, 2, magic));
    if (c.JS_DefinePropertyValueStr(engine.context, object, name.ptr, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}

pub fn install(engine: *engine_mod.Engine, io: std.Io) !void {
    engine.native_io = io;
    var objects: [2]c.JSValue = undefined;
    var initialized: usize = 0;
    defer for (objects[0..initialized]) |object| engine.freeValue(object);
    inline for (.{ Flavor.posix, Flavor.win32 }, 0..) |flavor, index| {
        objects[index] = try engine.checked(c.JS_NewObject(engine.context));
        initialized += 1;
        inline for (std.meta.fields(Method)) |field| try function(engine, objects[index], @enumFromInt(field.value), flavor);
        const sep = [_]u8{separator(flavor)};
        const delimiter = [_]u8{if (flavor == .win32) ';' else ':'};
        if (c.JS_DefinePropertyValueStr(engine.context, objects[index], "sep", c.JS_NewStringLen(engine.context, &sep, 1), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        if (c.JS_DefinePropertyValueStr(engine.context, objects[index], "delimiter", c.JS_NewStringLen(engine.context, &delimiter, 1), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    for (objects) |object| {
        if (c.JS_DefinePropertyValueStr(engine.context, object, "posix", c.JS_DupValue(engine.context, objects[0]), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        if (c.JS_DefinePropertyValueStr(engine.context, object, "win32", c.JS_DupValue(engine.context, objects[1]), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    const object = objects[if (native == .win32) @as(usize, 1) else 0];
    try engine.registerDefaultModule("node:path", object);
    try engine.registerDefaultModule("path", object);
}

fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const flavor: Flavor = if (magic >= 256) .win32 else .posix;
    return call(engine, @enumFromInt(@as(u8, @intCast(@mod(magic, 256)))), flavor, argv[0..@intCast(argc)]) catch |err| c.JS_ThrowTypeError(context, "Native path operation failed: %s", @as([*:0]const u8, @errorName(err)));
}

fn argumentText(engine: *engine_mod.Engine, value: c.JSValue, allocator: std.mem.Allocator) ![]u8 {
    if (!c.JS_IsString(value)) return error.InvalidNativePathArgument;
    const source = try engine.toString(value);
    defer engine.gpa.free(source);
    return allocator.dupe(u8, source);
}

fn currentDirectory(engine: *engine_mod.Engine, allocator: std.mem.Allocator, flavor: Flavor) ![]u8 {
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try std.Io.Dir.cwd().realPath(io, &buffer);
    if (flavor == .posix and builtin.os.tag == .windows) {
        for (buffer[0..length]) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
        const start = std.mem.indexOfScalar(u8, buffer[0..length], '/') orelse 0;
        return allocator.dupe(u8, buffer[start..length]);
    }
    return allocator.dupe(u8, buffer[0..length]);
}

fn objectField(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, allocator: std.mem.Allocator) ![]const u8 {
    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, object, name));
    defer engine.freeValue(value);
    return if (c.JS_IsUndefined(value)) "" else argumentText(engine, value, allocator);
}

fn put(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: []const u8) !void {
    const string = try engine.checked(c.JS_NewStringLen(engine.context, value.ptr, value.len));
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, string, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}

fn call(engine: *engine_mod.Engine, method: Method, flavor: Flavor, args: []c.JSValue) !c.JSValue {
    var arena: std.heap.ArenaAllocator = .init(engine.gpa);
    defer arena.deinit();
    const gpa = arena.allocator();
    var result: []const u8 = "";
    if (method == .format) {
        if (args.len == 0 or !c.JS_IsObject(args[0]) or c.JS_IsArray(args[0])) return error.InvalidNativePathArgument;
        const root_value = try objectField(engine, args[0], "root", gpa);
        const dir = try objectField(engine, args[0], "dir", gpa);
        var base = try objectField(engine, args[0], "base", gpa);
        if (base.len == 0) {
            const name = try objectField(engine, args[0], "name", gpa);
            const ext = try objectField(engine, args[0], "ext", gpa);
            base = try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ name, if (ext.len > 0 and ext[0] != '.') "." else "", ext });
        }
        const directory = if (dir.len > 0) dir else root_value;
        result = if (directory.len == 0) base else if (std.mem.eql(u8, directory, root_value)) try std.fmt.allocPrint(gpa, "{s}{s}", .{ directory, base }) else try std.fmt.allocPrint(gpa, "{s}{c}{s}", .{ directory, separator(flavor), base });
    } else if (method == .join or method == .resolve) {
        const paths = try gpa.alloc([]const u8, args.len);
        for (args, paths) |arg, *path| path.* = try argumentText(engine, arg, gpa);
        result = if (method == .join) try join(gpa, paths, flavor) else try resolve(gpa, try currentDirectory(engine, gpa, flavor), paths, flavor);
    } else {
        if (method == .toNamespacedPath and args.len == 0) return c.pi_js_undefined();
        if (args.len == 0) return error.InvalidNativePathArgument;
        if (method == .toNamespacedPath and !c.JS_IsString(args[0])) return c.JS_DupValue(engine.context, args[0]);
        const path = try argumentText(engine, args[0], gpa);
        switch (method) {
            .normalize => result = try normalize(gpa, path, flavor),
            .dirname => result = dirname(path, flavor),
            .basename => {
                result = basename(path, flavor);
                if (args.len > 1 and !c.JS_IsUndefined(args[1])) {
                    const suffix = try argumentText(engine, args[1], gpa);
                    if (suffix.len > 0 and suffix.len <= path.len) {
                        if (std.mem.eql(u8, path, suffix)) result = "" else if (result.len == 0) {
                            const drive_end: usize = if (flavor == .win32 and path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') 2 else 0;
                            result = path[drive_end..];
                        } else if (result.len > suffix.len and std.mem.endsWith(u8, result, suffix)) result = result[0 .. result.len - suffix.len];
                    }
                }
            },
            .extname => result = extname(path, flavor),
            .isAbsolute => return c.pi_js_bool(engine.context, @intFromBool(root(path, flavor).absolute)),
            .relative => {
                if (args.len < 2) return error.InvalidNativePathArgument;
                const to = try argumentText(engine, args[1], gpa);
                const directory = try currentDirectory(engine, gpa, flavor);
                result = if (flavor == .win32) try std.fs.path.relativeWindows(gpa, directory, null, path, to) else try std.fs.path.relativePosix(gpa, directory, path, to);
            },
            .parse => {
                const parsed = root(path, flavor);
                const root_value = path[0..parsed.end];
                const base = if (path.len <= parsed.end) "" else basename(path, flavor);
                const base_start = if (base.len > 0) @intFromPtr(base.ptr) - @intFromPtr(path.ptr) else parsed.end;
                const directory = if (base.len == 0 or base_start <= parsed.end) root_value else path[0 .. base_start - 1];
                const ext = extname(base, flavor);
                const object = try engine.checked(c.JS_NewObject(engine.context));
                errdefer engine.freeValue(object);
                try put(engine, object, "root", root_value);
                try put(engine, object, "dir", directory);
                try put(engine, object, "base", base);
                try put(engine, object, "ext", ext);
                try put(engine, object, "name", base[0 .. base.len - ext.len]);
                return object;
            },
            .toNamespacedPath => {
                result = path;
                if (flavor == .win32 and path.len > 0) {
                    const absolute = try resolve(gpa, try currentDirectory(engine, gpa, flavor), &.{path}, flavor);
                    if (absolute.len >= 3 and absolute[1] == ':' and absolute[2] == '\\') result = try std.fmt.allocPrint(gpa, "\\\\?\\{s}", .{absolute}) else if (std.mem.startsWith(u8, absolute, "\\\\") and absolute.len > 2 and absolute[2] != '?' and absolute[2] != '.') result = try std.fmt.allocPrint(gpa, "\\\\?\\UNC\\{s}", .{absolute[2..]});
                }
            },
            else => unreachable,
        }
    }
    return engine.checked(c.JS_NewStringLen(engine.context, result.ptr, result.len));
}

test "native path operations preserve roots dot segments trailing separators and Windows devices" {
    const gpa = std.testing.allocator;
    inline for (.{
        .{ Flavor.posix, "", "." },               .{ Flavor.posix, "../a//b/..//", "../a/" },                    .{ Flavor.posix, "/../../a", "/a" },
        .{ Flavor.posix, "./", "./" },            .{ Flavor.posix, "a/../../", "../" },                          .{ Flavor.win32, "C:foo\\..\\", "C:.\\" },
        .{ Flavor.win32, "C:\\a\\..\\", "C:\\" }, .{ Flavor.win32, "\\\\server\\share", "\\\\server\\share\\" }, .{ Flavor.win32, "\\\\server\\share\\..\\x", "\\\\server\\share\\x" },
    }) |sample| {
        const value = try normalize(gpa, sample[1], sample[0]);
        defer gpa.free(value);
        try std.testing.expectEqualStrings(sample[2], value);
    }
    const joined = try join(gpa, &.{ "/", "/server", "share" }, .win32);
    defer gpa.free(joined);
    try std.testing.expectEqualStrings("\\server\\share", joined);
    const resolved = try resolve(gpa, "C:\\cwd", &.{ "C:one", "\\two" }, .win32);
    defer gpa.free(resolved);
    try std.testing.expectEqualStrings("C:\\two", resolved);
    const other_drive = try resolve(gpa, "C:\\cwd", &.{"d:one"}, .win32);
    defer gpa.free(other_drive);
    try std.testing.expectEqualStrings("d:\\one", other_drive);
    try std.testing.expectEqualStrings("//", dirname("//file", .posix));
    try std.testing.expectEqualStrings("/a/", dirname("/a//b/", .posix));
    try std.testing.expectEqualStrings("share", basename("\\\\server\\share", .win32));
    try std.testing.expectEqualStrings("", extname("..", .posix));
    try std.testing.expectEqualStrings(".", extname("...", .posix));
}

test "native path module exports platform objects and validates extension arguments" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const namespace = engine.evalModule(
        "import path,{posix,win32} from 'node:path'; import legacy from 'path';" ++
            "if (path!==legacy || path.posix!==posix || win32.posix!==posix || posix.win32!==win32 || win32.sep!=='\\\\' || posix.delimiter!==':') throw Error('identity');" ++
            "if (posix.join('/a','/b','..','c')!=='/a/c' || posix.resolve('/a','/b')!=='/b' || !win32.isAbsolute('\\\\a') || win32.isAbsolute('C:a')) throw Error('paths');" ++
            "if (posix.format({dir:'/tmp',name:'native',ext:'txt'})!=='/tmp/native.txt' || win32.basename('C:\\\\a\\\\file.ts','.ts')!=='file') throw Error('format');" ++
            "export const parsed=posix.parse('/a/file.tar.gz/');" ++
            "let rejected=0; for (const call of [()=>posix.join('a',4),()=>posix.normalize(null),()=>win32.relative('a'),()=>posix.format([])]) {try{call();}catch(error){if(!(error instanceof TypeError))throw error;rejected++;}} if(rejected!==4)throw Error('arguments');",
        "native-path-fixture.mjs",
    ) catch |err| {
        std.debug.print("Native path fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(namespace);
    const parsed = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "parsed"));
    defer engine.freeValue(parsed);
    const json = try engine.stringify(parsed);
    defer engine.gpa.free(json);
    try std.testing.expectEqualStrings("{\"root\":\"/\",\"dir\":\"/a\",\"base\":\"file.tar.gz\",\"ext\":\".gz\",\"name\":\"file.tar\"}", json);
}

test "native path contracts match independently captured Node oracle data" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const fixture = try std.json.parseFromSliceLeaky(std.json.Value, gpa, @embedFile("fixtures/node_path.json"), .{});
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    var mismatches: usize = 0;
    for (fixture.object.get("cases").?.array.items) |sample| {
        const object = sample.object;
        const flavor: Flavor = if (std.mem.eql(u8, object.get("flavor").?.string, "win32")) .win32 else .posix;
        const method = std.meta.stringToEnum(Method, object.get("method").?.string).?;
        const input = object.get("args").?.array.items;
        const args = try gpa.alloc(c.JSValue, input.len);
        var initialized: usize = 0;
        defer for (args[0..initialized]) |arg| engine.freeValue(arg);
        for (input, args) |arg, *slot| {
            slot.* = try engine.checked(c.JS_NewStringLen(engine.context, arg.string.ptr, arg.string.len));
            initialized += 1;
        }
        const actual = try call(engine, method, flavor, args);
        defer engine.freeValue(actual);
        const json = try engine.stringify(actual);
        defer engine.gpa.free(json);
        const expected = object.get("expected").?;
        const expected_json = try std.json.Stringify.valueAlloc(gpa, expected, .{});
        if (!std.mem.eql(u8, expected_json, json)) {
            if (mismatches < 25) std.debug.print("Path oracle mismatch {s}.{s} {s}: expected {s}; actual {s}\n", .{ @tagName(flavor), @tagName(method), try std.json.Stringify.valueAlloc(gpa, object.get("args").?, .{}), expected_json, json });
            mismatches += 1;
        }
    }
    if (mismatches > 0) {
        std.debug.print("Native path oracle total mismatches: {d}\n", .{mismatches});
        return error.NativePathOracleMismatch;
    }
}
