//! Actual consumed util.getSystemErrorName body and Windows UV error map.
//! No public namespace registration, OS errno guess or Error relabeling.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const f = @import("native_node_module_callable.zig");
pub const Inputs = struct { invalid_arg_type: c.JSValue, out_of_range: c.JSValue };
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    if (!c.JS_IsFunction(engine.context, inputs.invalid_arg_type) or !c.JS_IsFunction(engine.context, inputs.out_of_range)) return error.RequiredActualUtilErrorConstructors;
    return f.create(engine, "getSystemErrorName", 1, true, getSystemErrorName, &.{ inputs.invalid_arg_type, inputs.out_of_range });
}
fn getSystemErrorName(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const value = h.arg(args, 0);
    if (!c.JS_IsNumber(value)) return h.throwValue(engine, try h.construct(&s, roots[0], &.{ try s.text("err"), try s.text("number"), value }));
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) return v.js.capture(engine);
    // validateNumber does not reject NaN; this second Source condition does.
    if (number >= 0 or !std.math.isFinite(number) or @trunc(number) != number or @abs(number) > 9007199254740991) {
        return h.throwValue(engine, try h.construct(&s, roots[1], &.{ try s.text("err"), try s.text("a negative integer"), value }));
    }
    if (@import("builtin").os.tag != .windows) return error.RequiredActualPlatformUvErrnoMap;
    if (number >= std.math.minInt(i32) and number <= std.math.maxInt(i32)) {
        if (windowsName(@intFromFloat(number))) |name| return c.JS_DupValue(engine.context, try s.text(name));
    }
    // Internal uvErrmapGet is an exact numeric Map lookup, not ToInt32. In
    // particular a negative safe integer outside int32 must not wrap to EPIPE.
    const text = try s.own(try h.success(engine, try engine.checked(c.JS_ToString(engine.context, value))));
    return c.JS_DupValue(engine.context, try h.binary(&s, .add, try s.text("Unknown system error "), text));
}
/// Source uv.h UV_ERRNO_MAP, numeric Windows branches in uv/errno.h.
pub fn windowsName(number: i32) ?[]const u8 {
    return switch (number) {
        -4095 => "EOF", -4094 => "UNKNOWN",
        -3000 => "EAI_ADDRFAMILY", -3001 => "EAI_AGAIN", -3002 => "EAI_BADFLAGS",
        -3003 => "EAI_CANCELED", -3004 => "EAI_FAIL", -3005 => "EAI_FAMILY",
        -3006 => "EAI_MEMORY", -3007 => "EAI_NODATA", -3008 => "EAI_NONAME",
        -3009 => "EAI_OVERFLOW", -3010 => "EAI_SERVICE", -3011 => "EAI_SOCKTYPE",
        -3013 => "EAI_BADHINTS", -3014 => "EAI_PROTOCOL",
        -4093 => "E2BIG", -4092 => "EACCES", -4091 => "EADDRINUSE",
        -4090 => "EADDRNOTAVAIL", -4089 => "EAFNOSUPPORT", -4088 => "EAGAIN",
        -4084 => "EALREADY", -4083 => "EBADF", -4082 => "EBUSY",
        -4081 => "ECANCELED", -4080 => "ECHARSET", -4079 => "ECONNABORTED",
        -4078 => "ECONNREFUSED", -4077 => "ECONNRESET", -4076 => "EDESTADDRREQ",
        -4075 => "EEXIST", -4074 => "EFAULT", -4073 => "EHOSTUNREACH",
        -4072 => "EINTR", -4071 => "EINVAL", -4070 => "EIO", -4069 => "EISCONN",
        -4068 => "EISDIR", -4067 => "ELOOP", -4066 => "EMFILE", -4065 => "EMSGSIZE",
        -4064 => "ENAMETOOLONG", -4063 => "ENETDOWN", -4062 => "ENETUNREACH",
        -4061 => "ENFILE", -4060 => "ENOBUFS", -4059 => "ENODEV", -4058 => "ENOENT",
        -4057 => "ENOMEM", -4056 => "ENONET", -4055 => "ENOSPC", -4054 => "ENOSYS",
        -4053 => "ENOTCONN", -4052 => "ENOTDIR", -4051 => "ENOTEMPTY", -4050 => "ENOTSOCK",
        -4049 => "ENOTSUP", -4048 => "EPERM", -4047 => "EPIPE", -4046 => "EPROTO",
        -4045 => "EPROTONOSUPPORT", -4044 => "EPROTOTYPE", -4043 => "EROFS",
        -4042 => "ESHUTDOWN", -4041 => "ESPIPE", -4040 => "ESRCH", -4039 => "ETIMEDOUT",
        -4038 => "ETXTBSY", -4037 => "EXDEV", -4036 => "EFBIG", -4035 => "ENOPROTOOPT",
        -4034 => "ERANGE", -4033 => "ENXIO", -4032 => "EMLINK", -4031 => "EHOSTDOWN",
        -4030 => "EREMOTEIO", -4029 => "ENOTTY", -4028 => "EFTYPE", -4027 => "EILSEQ",
        -4026 => "EOVERFLOW", -4025 => "ESOCKTNOSUPPORT", -4024 => "ENODATA",
        -4023 => "EUNATCH", -4022 => "ENOEXEC",
        else => null,
    };
}
