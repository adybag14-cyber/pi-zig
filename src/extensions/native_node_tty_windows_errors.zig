//! Exact native libuv Windows error mapping, Node24.14 retained error.c,
//! errno.h and UV_ERRNO_MAP. Header-linked Win32/WSA constants, no guessed code.
const builtin = @import("builtin");
const win = if (builtin.os.tag == .windows) @cImport({ @cInclude("winerror.h"); }) else struct {};
pub const Code = enum(i32) {
    EOF = -4095, UNKNOWN = -4094, E2BIG = -4093, EACCES = -4092,
    EADDRINUSE = -4091, EADDRNOTAVAIL = -4090, EAFNOSUPPORT = -4089,
    EAGAIN = -4088, EALREADY = -4084, EBADF = -4083, EBUSY = -4082,
    ECANCELED = -4081, ECHARSET = -4080, ECONNABORTED = -4079,
    ECONNREFUSED = -4078, ECONNRESET = -4077, EEXIST = -4075, EFAULT = -4074,
    EHOSTUNREACH = -4073, EINVAL = -4071, EIO = -4070, EISCONN = -4069,
    EISDIR = -4068, ELOOP = -4067, EMFILE = -4066, EMSGSIZE = -4065,
    ENAMETOOLONG = -4064, ENETUNREACH = -4062, ENOBUFS = -4060,
    ENOENT = -4058, ENOMEM = -4057, ENOSPC = -4055, ENOTCONN = -4053,
    ENOTEMPTY = -4051, ENOTSOCK = -4050, ENOTSUP = -4049, EPERM = -4048,
    EPIPE = -4047, EPROTONOSUPPORT = -4045, EROFS = -4043,
    ETIMEDOUT = -4039, EXDEV = -4037, EFTYPE = -4028, ESOCKTNOSUPPORT = -4025,
};
fn w(comptime name: []const u8) i32 { return @intCast(@field(win, name)); }
/// Negative values are already a UV/native error, as in the original API.
pub fn translate(native_error: i32) i32 {
    if (native_error <= 0) return native_error;
    const code: Code = switch (native_error) {
        w("WSAEACCES"), w("ERROR_ELEVATION_REQUIRED"), w("ERROR_CANT_ACCESS_FILE") => .EACCES,
        w("ERROR_ADDRESS_ALREADY_ASSOCIATED"), w("WSAEADDRINUSE") => .EADDRINUSE,
        w("WSAEADDRNOTAVAIL") => .EADDRNOTAVAIL,
        w("WSAEAFNOSUPPORT") => .EAFNOSUPPORT,
        w("WSAEWOULDBLOCK"), w("ERROR_NO_DATA") => .EAGAIN,
        w("WSAEALREADY") => .EALREADY,
        w("ERROR_INVALID_FLAGS"), w("ERROR_INVALID_HANDLE") => .EBADF,
        w("ERROR_LOCK_VIOLATION"), w("ERROR_PIPE_BUSY"), w("ERROR_SHARING_VIOLATION") => .EBUSY,
        w("ERROR_OPERATION_ABORTED"), w("WSAEINTR") => .ECANCELED,
        w("ERROR_NO_UNICODE_TRANSLATION") => .ECHARSET,
        w("ERROR_CONNECTION_ABORTED"), w("WSAECONNABORTED") => .ECONNABORTED,
        w("ERROR_CONNECTION_REFUSED"), w("WSAECONNREFUSED") => .ECONNREFUSED,
        w("ERROR_NETNAME_DELETED"), w("WSAECONNRESET") => .ECONNRESET,
        w("ERROR_ALREADY_EXISTS"), w("ERROR_FILE_EXISTS") => .EEXIST,
        w("ERROR_NOACCESS"), w("WSAEFAULT") => .EFAULT,
        w("ERROR_HOST_UNREACHABLE"), w("WSAEHOSTUNREACH") => .EHOSTUNREACH,
        w("ERROR_INSUFFICIENT_BUFFER"), w("ERROR_INVALID_DATA"), w("ERROR_INVALID_PARAMETER"), w("ERROR_SYMLINK_NOT_SUPPORTED"), w("WSAEINVAL"), w("WSAEPFNOSUPPORT") => .EINVAL,
        w("ERROR_BEGINNING_OF_MEDIA"), w("ERROR_BUS_RESET"), w("ERROR_CRC"), w("ERROR_DEVICE_DOOR_OPEN"), w("ERROR_DEVICE_REQUIRES_CLEANING"), w("ERROR_DISK_CORRUPT"), w("ERROR_EOM_OVERFLOW"), w("ERROR_FILEMARK_DETECTED"), w("ERROR_GEN_FAILURE"), w("ERROR_INVALID_BLOCK_LENGTH"), w("ERROR_IO_DEVICE"), w("ERROR_NO_DATA_DETECTED"), w("ERROR_NO_SIGNAL_SENT"), w("ERROR_OPEN_FAILED"), w("ERROR_SETMARK_DETECTED"), w("ERROR_SIGNAL_REFUSED") => .EIO,
        w("WSAEISCONN") => .EISCONN,
        w("ERROR_CANT_RESOLVE_FILENAME") => .ELOOP,
        w("ERROR_TOO_MANY_OPEN_FILES"), w("WSAEMFILE") => .EMFILE,
        w("WSAEMSGSIZE") => .EMSGSIZE,
        w("ERROR_BUFFER_OVERFLOW"), w("ERROR_FILENAME_EXCED_RANGE") => .ENAMETOOLONG,
        w("ERROR_NETWORK_UNREACHABLE"), w("WSAENETUNREACH") => .ENETUNREACH,
        w("WSAENOBUFS") => .ENOBUFS,
        w("ERROR_BAD_PATHNAME"), w("ERROR_DIRECTORY"), w("ERROR_ENVVAR_NOT_FOUND"), w("ERROR_FILE_NOT_FOUND"), w("ERROR_INVALID_NAME"), w("ERROR_INVALID_DRIVE"), w("ERROR_INVALID_REPARSE_DATA"), w("ERROR_MOD_NOT_FOUND"), w("ERROR_PATH_NOT_FOUND"), w("WSAHOST_NOT_FOUND"), w("WSANO_DATA") => .ENOENT,
        w("ERROR_NOT_ENOUGH_MEMORY"), w("ERROR_OUTOFMEMORY") => .ENOMEM,
        w("ERROR_CANNOT_MAKE"), w("ERROR_DISK_FULL"), w("ERROR_EA_TABLE_FULL"), w("ERROR_END_OF_MEDIA"), w("ERROR_HANDLE_DISK_FULL") => .ENOSPC,
        w("ERROR_NOT_CONNECTED"), w("WSAENOTCONN") => .ENOTCONN,
        w("ERROR_DIR_NOT_EMPTY") => .ENOTEMPTY,
        w("WSAENOTSOCK") => .ENOTSOCK,
        w("ERROR_NOT_SUPPORTED") => .ENOTSUP,
        w("ERROR_BROKEN_PIPE") => .EOF,
        w("ERROR_ACCESS_DENIED"), w("ERROR_PRIVILEGE_NOT_HELD") => .EPERM,
        w("ERROR_BAD_PIPE"), w("ERROR_PIPE_NOT_CONNECTED"), w("WSAESHUTDOWN") => .EPIPE,
        w("WSAEPROTONOSUPPORT") => .EPROTONOSUPPORT,
        w("ERROR_WRITE_PROTECT") => .EROFS,
        w("ERROR_SEM_TIMEOUT"), w("WSAETIMEDOUT") => .ETIMEDOUT,
        w("ERROR_NOT_SAME_DEVICE") => .EXDEV,
        w("ERROR_INVALID_FUNCTION") => .EISDIR,
        w("ERROR_META_EXPANSION_TOO_LONG") => .E2BIG,
        w("WSAESOCKTNOSUPPORT") => .ESOCKTNOSUPPORT,
        w("ERROR_BAD_EXE_FORMAT") => .EFTYPE,
        else => .UNKNOWN,
    };
    return @intFromEnum(code);
}
pub fn fromWindows(native_error: u32) i32 { return translate(@bitCast(native_error)); }
pub fn message(code: Code) []const u8 {
    return switch (code) {
        .EOF => "end of file", .UNKNOWN => "unknown error", .E2BIG => "argument list too long",
        .EACCES => "permission denied", .EADDRINUSE => "address already in use", .EADDRNOTAVAIL => "address not available",
        .EAFNOSUPPORT => "address family not supported", .EAGAIN => "resource temporarily unavailable", .EALREADY => "connection already in progress",
        .EBADF => "bad file descriptor", .EBUSY => "resource busy or locked", .ECANCELED => "operation canceled", .ECHARSET => "invalid Unicode character",
        .ECONNABORTED => "software caused connection abort", .ECONNREFUSED => "connection refused", .ECONNRESET => "connection reset by peer",
        .EEXIST => "file already exists", .EFAULT => "bad address in system call argument", .EHOSTUNREACH => "host is unreachable",
        .EINVAL => "invalid argument", .EIO => "i/o error", .EISCONN => "socket is already connected", .EISDIR => "illegal operation on a directory",
        .ELOOP => "too many symbolic links encountered", .EMFILE => "too many open files", .EMSGSIZE => "message too long", .ENAMETOOLONG => "name too long",
        .ENETUNREACH => "network is unreachable", .ENOBUFS => "no buffer space available", .ENOENT => "no such file or directory", .ENOMEM => "not enough memory",
        .ENOSPC => "no space left on device", .ENOTCONN => "socket is not connected", .ENOTEMPTY => "directory not empty", .ENOTSOCK => "socket operation on non-socket",
        .ENOTSUP => "operation not supported on socket", .EPERM => "operation not permitted", .EPIPE => "broken pipe", .EPROTONOSUPPORT => "protocol not supported",
        .EROFS => "read-only file system", .ETIMEDOUT => "connection timed out", .EXDEV => "cross-device link not permitted", .EFTYPE => "inappropriate file type or format",
        .ESOCKTNOSUPPORT => "socket type not supported",
    };
}
