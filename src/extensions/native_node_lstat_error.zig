//! Private lstat Win32 -> libuv filesystem error transport. No OS operation,
//! thread-local error lookup, process bridge or new public error namespace.
//! Derived from Node24.14 bundled libuv win/error.c, errno.h and UV_ERRNO_MAP;
//! Copyright Joyent/Node.js contributors, MIT (retained libuv-LICENSE).
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub const Code = enum(i32) {
    EOF = -4095, UNKNOWN = -4094, E2BIG = -4093, EACCES = -4092,
    EADDRINUSE = -4091, EADDRNOTAVAIL = -4090, EAFNOSUPPORT = -4089,
    EAGAIN = -4088, EALREADY = -4084, EBADF = -4083, EBUSY = -4082,
    ECANCELED = -4081, ECHARSET = -4080, ECONNABORTED = -4079,
    ECONNREFUSED = -4078, ECONNRESET = -4077, EEXIST = -4075,
    EFAULT = -4074, EHOSTUNREACH = -4073, EINVAL = -4071, EIO = -4070,
    EISCONN = -4069, EISDIR = -4068, ELOOP = -4067, EMFILE = -4066,
    EMSGSIZE = -4065, ENAMETOOLONG = -4064, ENETUNREACH = -4062,
    ENOBUFS = -4060, ENOENT = -4058, ENOMEM = -4057, ENOSPC = -4055,
    ENOTCONN = -4053, ENOTEMPTY = -4051, ENOTSOCK = -4050, ENOTSUP = -4049,
    EPERM = -4048, EPIPE = -4047, EPROTONOSUPPORT = -4045, EROFS = -4043,
    ETIMEDOUT = -4039, EXDEV = -4037, EFTYPE = -4028, ESOCKTNOSUPPORT = -4025,
};
fn win(comptime name: []const u8) u32 { return @intFromEnum(@field(std.os.windows.Win32Error, name)); }
/// Exact positive-system-error switch from pinned uv_translate_sys_error.
/// The caller owns a latched failing Win32 code, never a borrowed last-error.
pub fn translate(code: u32) Code {
    return switch (code) {
        10013, win("ELEVATION_REQUIRED"), win("CANT_ACCESS_FILE") => .EACCES,
        win("ADDRESS_ALREADY_ASSOCIATED"), 10048 => .EADDRINUSE,
        10049 => .EADDRNOTAVAIL, 10047 => .EAFNOSUPPORT,
        10035, win("NO_DATA") => .EAGAIN, 10037 => .EALREADY,
        win("INVALID_FLAGS"), win("INVALID_HANDLE") => .EBADF,
        win("LOCK_VIOLATION"), win("PIPE_BUSY"), win("SHARING_VIOLATION") => .EBUSY,
        win("OPERATION_ABORTED"), 10004 => .ECANCELED,
        win("NO_UNICODE_TRANSLATION") => .ECHARSET,
        win("CONNECTION_ABORTED"), 10053 => .ECONNABORTED,
        win("CONNECTION_REFUSED"), 10061 => .ECONNREFUSED,
        win("NETNAME_DELETED"), 10054 => .ECONNRESET,
        win("ALREADY_EXISTS"), win("FILE_EXISTS") => .EEXIST,
        win("NOACCESS"), 10014 => .EFAULT,
        win("HOST_UNREACHABLE"), 10065 => .EHOSTUNREACH,
        win("INSUFFICIENT_BUFFER"), win("INVALID_DATA"), win("INVALID_PARAMETER"), win("SYMLINK_NOT_SUPPORTED"), 10022, 10046 => .EINVAL,
        win("BEGINNING_OF_MEDIA"), win("BUS_RESET"), win("CRC"), win("DEVICE_DOOR_OPEN"), win("DEVICE_REQUIRES_CLEANING"),
        win("DISK_CORRUPT"), win("EOM_OVERFLOW"), win("FILEMARK_DETECTED"), win("GEN_FAILURE"), win("INVALID_BLOCK_LENGTH"),
        win("IO_DEVICE"), win("NO_DATA_DETECTED"), win("NO_SIGNAL_SENT"), win("OPEN_FAILED"), win("SETMARK_DETECTED"), win("SIGNAL_REFUSED") => .EIO,
        10056 => .EISCONN, win("CANT_RESOLVE_FILENAME") => .ELOOP,
        win("TOO_MANY_OPEN_FILES"), 10024 => .EMFILE, 10040 => .EMSGSIZE,
        win("BUFFER_OVERFLOW"), win("FILENAME_EXCED_RANGE") => .ENAMETOOLONG,
        win("NETWORK_UNREACHABLE"), 10051 => .ENETUNREACH, 10055 => .ENOBUFS,
        win("BAD_PATHNAME"), win("DIRECTORY"), win("ENVVAR_NOT_FOUND"), win("FILE_NOT_FOUND"), win("INVALID_NAME"),
        win("INVALID_DRIVE"), 4392, win("MOD_NOT_FOUND"), win("PATH_NOT_FOUND"), 11001, 11004 => .ENOENT,
        win("NOT_ENOUGH_MEMORY"), win("OUTOFMEMORY") => .ENOMEM,
        win("CANNOT_MAKE"), win("DISK_FULL"), win("EA_TABLE_FULL"), win("END_OF_MEDIA"), win("HANDLE_DISK_FULL") => .ENOSPC,
        win("NOT_CONNECTED"), 10057 => .ENOTCONN,
        win("DIR_NOT_EMPTY") => .ENOTEMPTY, 10038 => .ENOTSOCK,
        win("NOT_SUPPORTED") => .ENOTSUP, win("BROKEN_PIPE") => .EOF,
        win("ACCESS_DENIED"), win("PRIVILEGE_NOT_HELD") => .EPERM,
        win("BAD_PIPE"), win("PIPE_NOT_CONNECTED"), 10058 => .EPIPE,
        10043 => .EPROTONOSUPPORT, win("WRITE_PROTECT") => .EROFS,
        win("SEM_TIMEOUT"), 10060 => .ETIMEDOUT,
        win("NOT_SAME_DEVICE") => .EXDEV, win("INVALID_FUNCTION") => .EISDIR,
        win("META_EXPANSION_TOO_LONG") => .E2BIG, 10044 => .ESOCKTNOSUPPORT,
        win("BAD_EXE_FORMAT") => .EFTYPE,
        else => .UNKNOWN,
    };
}
pub fn message(code: Code) []const u8 {
    return switch (code) {
        .EOF => "end of file", .UNKNOWN => "unknown error", .E2BIG => "argument list too long", .EACCES => "permission denied",
        .EADDRINUSE => "address already in use", .EADDRNOTAVAIL => "address not available", .EAFNOSUPPORT => "address family not supported",
        .EAGAIN => "resource temporarily unavailable", .EALREADY => "connection already in progress", .EBADF => "bad file descriptor",
        .EBUSY => "resource busy or locked", .ECANCELED => "operation canceled", .ECHARSET => "invalid Unicode character",
        .ECONNABORTED => "software caused connection abort", .ECONNREFUSED => "connection refused", .ECONNRESET => "connection reset by peer",
        .EEXIST => "file already exists", .EFAULT => "bad address in system call argument", .EHOSTUNREACH => "host is unreachable",
        .EINVAL => "invalid argument", .EIO => "i/o error", .EISCONN => "socket is already connected", .EISDIR => "illegal operation on a directory",
        .ELOOP => "too many symbolic links encountered", .EMFILE => "too many open files", .EMSGSIZE => "message too long", .ENAMETOOLONG => "name too long",
        .ENETUNREACH => "network is unreachable", .ENOBUFS => "no buffer space available", .ENOENT => "no such file or directory", .ENOMEM => "not enough memory",
        .ENOSPC => "no space left on device", .ENOTCONN => "socket is not connected", .ENOTEMPTY => "directory not empty",
        .ENOTSOCK => "socket operation on non-socket", .ENOTSUP => "operation not supported on socket", .EPERM => "operation not permitted",
        .EPIPE => "broken pipe", .EPROTONOSUPPORT => "protocol not supported", .EROFS => "read-only file system", .ETIMEDOUT => "connection timed out",
        .EXDEV => "cross-device link not permitted", .EFTYPE => "inappropriate file type or format", .ESOCKTNOSUPPORT => "socket type not supported",
    };
}
pub fn throwFilesystem(engine: *v.em.Engine, code: Code, path: []const u8) anyerror {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const formatted = std.fmt.allocPrint(engine.gpa, "{s}: {s}, lstat '{s}'", .{ @tagName(code), message(code), path }) catch |err| return err;
    defer engine.gpa.free(formatted);
    // Use the VM's actual Error intrinsic, independent of a late global Error.
    const reason = s.own(engine.checked(c.JS_NewError(engine.context)) catch |err| return err) catch |err| return err;
    const text = s.text(formatted) catch |err| return err;
    if (c.JS_DefinePropertyValueStr(engine.context, reason, "message", c.JS_DupValue(engine.context, text), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
    s.put(reason, "errno", c.JS_NewInt32(engine.context, @intFromEnum(code))) catch |err| return err;
    s.put(reason, "code", s.text(@tagName(code)) catch |err| return err) catch |err| return err;
    s.put(reason, "syscall", s.text("lstat") catch |err| return err) catch |err| return err;
    s.put(reason, "path", s.text(path) catch |err| return err) catch |err| return err;
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch |err| return err;
    unreachable;
}
