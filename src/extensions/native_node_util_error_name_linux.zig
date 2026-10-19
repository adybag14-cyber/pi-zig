//! Exact libuv1.51 UV_ERRNO_MAP names projected through Linux's actual errno ABI.
//! util.getSystemErrorName's VM type/range/error construction stays in its real
//! shared body. This native leaf performs only the actual numeric map lookup.
const builtin = @import("builtin");
const linux = @import("std").os.linux;
pub fn requirePlatform() !void {
    return switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) { .x86_64, .aarch64 => {}, else => error.RequiredQualifiedLinuxUvErrnoArchitecture },
        else => error.RequiredLinuxUvErrnoMap,
    };
}
pub fn name(number: i32) !?[]const u8 {
    return switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .x86_64, .aarch64 => nameSupported(number),
            else => error.RequiredQualifiedLinuxUvErrnoArchitecture,
        },
        else => error.RequiredLinuxUvErrnoMap,
    };
}
fn nameSupported(number: i32) ?[]const u8 {
    // uv/errno.h gives these private UV values on every platform. ECHARSET
    // and EFTYPE have no Linux errno macro, so the genuine UV fallbacks apply.
    switch (number) {
        -4095 => return "EOF", -4094 => return "UNKNOWN",
        -4080 => return "ECHARSET", -4028 => return "EFTYPE",
        -3000 => return "EAI_ADDRFAMILY", -3001 => return "EAI_AGAIN",
        -3002 => return "EAI_BADFLAGS", -3003 => return "EAI_CANCELED",
        -3004 => return "EAI_FAIL", -3005 => return "EAI_FAMILY",
        -3006 => return "EAI_MEMORY", -3007 => return "EAI_NODATA",
        -3008 => return "EAI_NONAME", -3009 => return "EAI_OVERFLOW",
        -3010 => return "EAI_SERVICE", -3011 => return "EAI_SOCKTYPE",
        -3013 => return "EAI_BADHINTS", -3014 => return "EAI_PROTOCOL",
        else => {},
    }
    // UV__ERR(errno) is -errno for Linux. Resolve the pinned actual target E
    // enum; never reuse Windows UV numbers or include Linux-only errno names
    // absent from the original UV_ERRNO_MAP. ENOTSUP is the actual OPNOTSUPP
    // alias on these admitted Linux architectures.
    inline for (.{
        .{ "2BIG", "E2BIG" }, .{ "ACCES", "EACCES" },
        .{ "ADDRINUSE", "EADDRINUSE" }, .{ "ADDRNOTAVAIL", "EADDRNOTAVAIL" },
        .{ "AFNOSUPPORT", "EAFNOSUPPORT" }, .{ "AGAIN", "EAGAIN" },
        .{ "ALREADY", "EALREADY" }, .{ "BADF", "EBADF" },
        .{ "BUSY", "EBUSY" }, .{ "CANCELED", "ECANCELED" },
        .{ "CONNABORTED", "ECONNABORTED" }, .{ "CONNREFUSED", "ECONNREFUSED" },
        .{ "CONNRESET", "ECONNRESET" }, .{ "DESTADDRREQ", "EDESTADDRREQ" },
        .{ "EXIST", "EEXIST" }, .{ "FAULT", "EFAULT" }, .{ "FBIG", "EFBIG" },
        .{ "HOSTUNREACH", "EHOSTUNREACH" }, .{ "INTR", "EINTR" },
        .{ "INVAL", "EINVAL" }, .{ "IO", "EIO" }, .{ "ISCONN", "EISCONN" },
        .{ "ISDIR", "EISDIR" }, .{ "LOOP", "ELOOP" }, .{ "MFILE", "EMFILE" },
        .{ "MSGSIZE", "EMSGSIZE" }, .{ "NAMETOOLONG", "ENAMETOOLONG" },
        .{ "NETDOWN", "ENETDOWN" }, .{ "NETUNREACH", "ENETUNREACH" },
        .{ "NFILE", "ENFILE" }, .{ "NOBUFS", "ENOBUFS" }, .{ "NODEV", "ENODEV" },
        .{ "NOENT", "ENOENT" }, .{ "NOMEM", "ENOMEM" }, .{ "NONET", "ENONET" },
        .{ "NOPROTOOPT", "ENOPROTOOPT" }, .{ "NOSPC", "ENOSPC" },
        .{ "NOSYS", "ENOSYS" }, .{ "NOTCONN", "ENOTCONN" },
        .{ "NOTDIR", "ENOTDIR" }, .{ "NOTEMPTY", "ENOTEMPTY" },
        .{ "NOTSOCK", "ENOTSOCK" }, .{ "OPNOTSUPP", "ENOTSUP" },
        .{ "OVERFLOW", "EOVERFLOW" }, .{ "PERM", "EPERM" }, .{ "PIPE", "EPIPE" },
        .{ "PROTO", "EPROTO" }, .{ "PROTONOSUPPORT", "EPROTONOSUPPORT" },
        .{ "PROTOTYPE", "EPROTOTYPE" }, .{ "RANGE", "ERANGE" },
        .{ "ROFS", "EROFS" }, .{ "SHUTDOWN", "ESHUTDOWN" }, .{ "SPIPE", "ESPIPE" },
        .{ "SRCH", "ESRCH" }, .{ "TIMEDOUT", "ETIMEDOUT" }, .{ "TXTBSY", "ETXTBSY" },
        .{ "XDEV", "EXDEV" }, .{ "NXIO", "ENXIO" }, .{ "MLINK", "EMLINK" },
        .{ "HOSTDOWN", "EHOSTDOWN" }, .{ "REMOTEIO", "EREMOTEIO" },
        .{ "NOTTY", "ENOTTY" }, .{ "ILSEQ", "EILSEQ" },
        .{ "SOCKTNOSUPPORT", "ESOCKTNOSUPPORT" }, .{ "NODATA", "ENODATA" },
        .{ "UNATCH", "EUNATCH" }, .{ "NOEXEC", "ENOEXEC" },
    }) |entry| {
        const actual = -@as(i32, @intCast(@intFromEnum(@field(linux.E, entry[0]))));
        if (number == actual) return entry[1];
    }
    return null;
}

test "Linux actual UV map ordinary fallback aliases and unknown contrast" {
    const std = @import("std");
    if (builtin.os.tag != .linux or (builtin.cpu.arch != .x86_64 and builtin.cpu.arch != .aarch64)) return error.SkipZigTest;
    try std.testing.expectEqualStrings("ENOENT", (try name(-2)).?);
    try std.testing.expectEqualStrings("EACCES", (try name(-13)).?);
    try std.testing.expectEqualStrings("EPIPE", (try name(-32)).?);
    try std.testing.expectEqualStrings("ENOTSUP", (try name(-95)).?);
    try std.testing.expectEqualStrings("ECHARSET", (try name(-4080)).?);
    try std.testing.expectEqualStrings("EFTYPE", (try name(-4028)).?);
    try std.testing.expectEqualStrings("EAI_AGAIN", (try name(-3001)).?);
    try std.testing.expectEqualStrings("EOF", (try name(-4095)).?);
    try std.testing.expect((try name(-4058)) == null); // Windows ENOENT is NOT Linux.
    try std.testing.expect((try name(2)) == null);
    try std.testing.expect((try name(-42)) == null); // Linux ENOMSG absent UV table.
}
