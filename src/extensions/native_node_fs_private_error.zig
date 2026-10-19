//! Private actual UV filesystem failure construction. Input is native status,
//! not a guest Error/name or inferred missing-file result.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
pub fn windowsCode(raw: u32, readlink: bool) i32 {
    if (readlink and raw == 4390) return -4071; // libuv readlink's explicit EINVAL override
    return @intFromEnum(@import("native_node_lstat_error.zig").translate(raw));
}
pub fn posixCode(raw: u32) !i32 {
    if (raw == 0 or raw > std.math.maxInt(i32)) return error.InvalidNativeFilesystemStatus;
    return -@as(i32, @intCast(raw));
}
fn name(code: i32) !?[]const u8 {
    if (builtin.os.tag == .windows) {
        inline for (std.meta.fields(@import("native_node_lstat_error.zig").Code)) |field| if (code == field.value) return field.name;
        if (code == -4052) return "ENOTDIR";
        return null;
    }
    return @import("native_node_util_error_name_linux.zig").name(code);
}
fn message(code_name: []const u8) ![]const u8 {
    if (std.meta.stringToEnum(@import("native_node_lstat_error.zig").Code, code_name)) |code|
        return @import("native_node_lstat_error.zig").message(code);
    // Remaining names from the same actual UV_ERRNO_MAP on admitted Linux.
    inline for (.{
        .{ "EAI_ADDRFAMILY", "address family not supported" }, .{ "EAI_AGAIN", "temporary failure" },
        .{ "EAI_BADFLAGS", "bad ai_flags value" }, .{ "EAI_BADHINTS", "invalid value for hints" },
        .{ "EAI_CANCELED", "request canceled" }, .{ "EAI_FAIL", "permanent failure" },
        .{ "EAI_FAMILY", "ai_family not supported" }, .{ "EAI_MEMORY", "out of memory" },
        .{ "EAI_NODATA", "no address" }, .{ "EAI_NONAME", "unknown node or service" },
        .{ "EAI_OVERFLOW", "argument buffer overflow" }, .{ "EAI_PROTOCOL", "resolved protocol is unknown" },
        .{ "EAI_SERVICE", "service not available for socket type" }, .{ "EAI_SOCKTYPE", "socket type not supported" },
        .{ "EDESTADDRREQ", "destination address required" }, .{ "EFBIG", "file too large" },
        .{ "EINTR", "interrupted system call" }, .{ "ENETDOWN", "network is down" },
        .{ "ENFILE", "file table overflow" }, .{ "ENODEV", "no such device" },
        .{ "ENONET", "machine is not on the network" }, .{ "ENOPROTOOPT", "protocol not available" },
        .{ "ENOSYS", "function not implemented" }, .{ "ENOTDIR", "not a directory" },
        .{ "EOVERFLOW", "value too large for defined data type" }, .{ "EPROTO", "protocol error" },
        .{ "EPROTOTYPE", "protocol wrong type for socket" }, .{ "ERANGE", "result too large" },
        .{ "ESHUTDOWN", "cannot send after transport endpoint shutdown" }, .{ "ESPIPE", "invalid seek" },
        .{ "ESRCH", "no such process" }, .{ "ETXTBSY", "text file is busy" },
        .{ "ENXIO", "no such device or address" }, .{ "EMLINK", "too many links" },
        .{ "EHOSTDOWN", "host is down" }, .{ "EREMOTEIO", "remote I/O error" },
        .{ "ENOTTY", "inappropriate ioctl for device" }, .{ "EILSEQ", "illegal byte sequence" },
        .{ "ENODATA", "no data available" }, .{ "EUNATCH", "protocol driver not attached" },
        .{ "ENOEXEC", "exec format error" },
    }) |entry| if (std.mem.eql(u8, code_name, entry[0])) return entry[1];
    return error.RequiredActualFilesystemErrorMessage;
}
fn errorPath(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    // Actual src/api/exceptions.cc StringFromPath; namespace spelling is
    // removed only after the binding has selected its native operation path.
    if (builtin.os.tag == .windows) {
        if (std.mem.startsWith(u8, path, "\\\\?\\UNC\\"))
            return std.fmt.allocPrint(gpa, "\\\\{s}", .{path[8..]});
        if (std.mem.startsWith(u8, path, "\\\\?\\")) return gpa.dupe(u8, path[4..]);
    }
    return gpa.dupe(u8, path);
}
pub fn throw(s: *Scope, code: i32, syscall: []const u8, path: []const u8) !c.JSValue {
    const known = try name(code);
    const unknown: ?[]u8 = if (known == null)
        try std.fmt.allocPrint(s.engine.gpa, "Unknown system error {d}", .{code}) else null;
    defer if (unknown) |text| s.engine.gpa.free(text);
    const code_name = known orelse unknown.?;
    const description = if (known != null) try message(code_name) else code_name;
    const actual_path = try errorPath(s.engine.gpa, path);
    defer s.engine.gpa.free(actual_path);
    const formatted = try std.fmt.allocPrint(s.engine.gpa, "{s}: {s}, {s} '{s}'",
        .{code_name, description, syscall, actual_path});
    defer s.engine.gpa.free(formatted);
    // Source constructs all string operands before its intrinsic Error and
    // then performs actual Set operations in errno/code/syscall/path order.
    const code_value = try s.text(code_name);
    const syscall_value = try s.text(syscall);
    const path_value = try s.text(actual_path);
    const message_value = try s.text(formatted);
    const generation = try s.beforeAllocation();
    const reason = try s.checkedAllocation(c.JS_NewError(s.engine.context), generation);
    const definition_generation = try s.beforeAllocation();
    const rc = c.JS_DefinePropertyValueStr(s.engine.context, reason, "message",
        c.JS_DupValue(s.engine.context, message_value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    _ = try s.checkedAllocation(c.pi_js_undefined(), definition_generation);
    if (rc < 0) return error.MissingActualFilesystemDefinitionReason;
    try s.put(reason, "errno", c.JS_NewInt32(s.engine.context, code));
    try s.put(reason, "code", code_value);
    try s.put(reason, "syscall", syscall_value);
    try s.put(reason, "path", path_value);
    _ = c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason));
    try s.pending();
    return error.ActualFilesystemThrowDidNotEscape;
}
