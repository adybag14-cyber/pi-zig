//! Concrete native copyFileSync operations needed by the actual SDK. The
//! default copy and COPYFILE_EXCL execute on real kernel file objects. Clone
//! flags remain an explicit unsupported scope until separately qualified.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const paths = @import("node_fs_metadata.zig");
const kernel = @import("native_file_stat.zig");
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(exports, "copyFileSync", try scope.own(try @import("native_node_function.zig").create(engine, "copyFileSync", 3, copy, &.{})));
    const constants = try scope.get(exports, "constants");
    if (c.JS_DefinePropertyValueStr(engine.context, constants, "COPYFILE_EXCL", c.JS_NewInt32(engine.context, 1), c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn failure(engine: *js.Engine, err: anyerror, source: []const u8, destination: []const u8) !c.JSValue {
    if (err == error.OutOfMemory) return err;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const code: []const u8 = switch (err) { error.PathAlreadyExists => "EEXIST", error.FileNotFound => "ENOENT", error.AccessDenied, error.PermissionDenied => "EACCES", error.IsDir => "EISDIR", error.NotDir => "ENOTDIR", else => "EIO" };
    const description: []const u8 = if (std.mem.eql(u8, code, "EEXIST")) "file already exists" else if (std.mem.eql(u8, code, "ENOENT")) "no such file or directory" else if (std.mem.eql(u8, code, "EACCES")) "permission denied" else if (std.mem.eql(u8, code, "EISDIR")) "illegal operation on a directory" else if (std.mem.eql(u8, code, "ENOTDIR")) "not a directory" else "i/o error";
    const message = try std.fmt.allocPrint(engine.gpa, "{s}: {s}, copyfile '{s}' -> '{s}'", .{ code, description, source, destination });
    defer engine.gpa.free(message);
    const value = try scope.own(try js.builtin(engine, "Error", &.{try scope.text(message)}));
    const errno: i32 = if (std.mem.eql(u8, code, "EEXIST")) (if (builtin.os.tag == .windows) -4075 else -17) else if (std.mem.eql(u8, code, "ENOENT")) (if (builtin.os.tag == .windows) -4058 else -2) else if (std.mem.eql(u8, code, "EACCES")) (if (builtin.os.tag == .windows) -4092 else -13) else if (std.mem.eql(u8, code, "EISDIR")) (if (builtin.os.tag == .windows) -4068 else -21) else if (std.mem.eql(u8, code, "ENOTDIR")) (if (builtin.os.tag == .windows) -4052 else -20) else (if (builtin.os.tag == .windows) -4070 else -5);
    try scope.put(value, "errno", c.JS_NewInt32(engine.context, errno));
    try scope.put(value, "code", try scope.text(code));
    try scope.put(value, "syscall", try scope.text("copyfile"));
    try scope.put(value, "path", try scope.text(source));
    try scope.put(value, "dest", try scope.text(destination));
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
}
fn copy(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const source = try paths.pathTextNamed(engine, arg(args, 0), false, "src");
    defer engine.gpa.free(source);
    const destination = try paths.pathTextNamed(engine, arg(args, 1), false, "dest");
    defer engine.gpa.free(destination);
    const supplied = arg(args, 2);
    var flags: u32 = 0;
    if (!c.JS_IsUndefined(supplied)) {
        if (!c.JS_IsNumber(supplied)) return error.CopyFileModeMustBeNumber;
        var numeric: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &numeric, supplied) < 0) return js.capture(engine);
        if (!std.math.isFinite(numeric) or numeric < 0 or numeric > 1 or @trunc(numeric) != numeric) return error.UnsupportedNativeCopyFileMode;
        flags = @intFromFloat(numeric);
    }
    copyKernel(engine, source, destination, flags == 1) catch |err| return failure(engine, err, source, destination);
    return c.pi_js_undefined();
}
fn copyKernel(engine: *js.Engine, source: []const u8, destination: []const u8, exclusive: bool) !void {
    if (builtin.os.tag == .windows) {
        const Native = struct { extern "kernel32" fn CopyFileW([*:0]const u16, [*:0]const u16, i32) callconv(.winapi) i32; };
        const source_path = try kernel.windowsNamespacedPath(engine.gpa, source);
        defer engine.gpa.free(source_path);
        const destination_path = try kernel.windowsNamespacedPath(engine.gpa, destination);
        defer engine.gpa.free(destination_path);
        const source_wide = try std.unicode.wtf8ToWtf16LeAllocZ(engine.gpa, source_path);
        defer engine.gpa.free(source_wide);
        const destination_wide = try std.unicode.wtf8ToWtf16LeAllocZ(engine.gpa, destination_path);
        defer engine.gpa.free(destination_wide);
        if (Native.CopyFileW(source_wide, destination_wide, @intFromBool(exclusive)) == 0) return switch (std.os.windows.GetLastError()) { .FILE_EXISTS, .ALREADY_EXISTS => error.PathAlreadyExists, .FILE_NOT_FOUND, .PATH_NOT_FOUND => error.FileNotFound, .ACCESS_DENIED => error.AccessDenied, else => error.NativeCopyFileFailed };
        return;
    }
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    const input = try std.Io.Dir.cwd().openFile(io, source, .{});
    defer input.close(io);
    const info = try input.stat(io);
    if (info.kind == .directory) return error.IsDir;
    if (!exclusive) {
        const source_stat = try kernel.read(engine.gpa, source);
        const destination_stat: ?kernel.Stat = kernel.read(engine.gpa, destination) catch |err| switch (err) { error.FileNotFound => null, else => return err };
        if (destination_stat) |target| if (source_stat.dev == target.dev and source_stat.ino == target.ino) return;
    }
    const output = try std.Io.Dir.cwd().createFile(io, destination, .{ .exclusive = exclusive, .truncate = true, .permissions = info.permissions });
    defer output.close(io);
    var reader: std.Io.File.Reader = .init(input, io, &.{});
    var storage: [4096]u8 = undefined;
    var writer = output.writer(io, &storage);
    _ = writer.interface.sendFileAll(&reader, .unlimited) catch |err| switch (err) { error.ReadFailed => return reader.err.?, error.WriteFailed => return writer.err.? };
    try writer.flush();
}
