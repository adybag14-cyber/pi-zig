//! Consumed Node24 os bodies: actual native account home/release and existing
//! tmpdir, plus live platform/arch. Not a complete node:os public-surface claim.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const functions = @import("native_node_function.zig");
const c = em.c;
const w = std.os.windows;
const posix_signals = if (builtin.os.tag == .windows) struct {} else @cImport({ @cInclude("signal.h"); });
const Win = struct {
    extern "advapi32" fn OpenProcessToken(w.HANDLE, u32, *w.HANDLE) callconv(.winapi) c_int;
    extern "userenv" fn GetUserProfileDirectoryW(w.HANDLE, ?[*]u16, *u32) callconv(.winapi) c_int;
    extern "advapi32" fn GetUserNameW([*]u16, *u32) callconv(.winapi) c_int;
    extern "advapi32" fn RegOpenKeyExW(w.HANDLE, [*:0]const u16, u32, u32, *w.HANDLE) callconv(.winapi) i32;
    extern "advapi32" fn RegGetValueW(w.HANDLE, ?[*:0]const u16, [*:0]const u16, u32, ?*u32, ?*anyopaque, *u32) callconv(.winapi) i32;
    extern "advapi32" fn RegCloseKey(w.HANDLE) callconv(.winapi) i32;
};
const Code = enum { noent, access, perm, nomem, nobufs, invalid, badf, io, unknown };
fn errnoValue(code: Code) c_int {
    if (builtin.os.tag == .windows) return switch (code) { .noent => -4058, .access => -4092, .perm => -4048, .nomem => -4057, .nobufs => -4060, .invalid => -4071, .badf => -4083, .io => -4070, .unknown => -4094 };
    return -@as(c_int, switch (code) { .noent => @intFromEnum(std.c.E.NOENT), .access => @intFromEnum(std.c.E.ACCES), .perm => @intFromEnum(std.c.E.PERM), .nomem => @intFromEnum(std.c.E.NOMEM), .nobufs => @intFromEnum(std.c.E.NOBUFS), .invalid => @intFromEnum(std.c.E.INVAL), .badf => @intFromEnum(std.c.E.BADF), .io => @intFromEnum(std.c.E.IO), .unknown => 4094 });
}
fn contextSet(s: *Scope, target: c.JSValue, name: []const u8, value: c.JSValue) !void {
    // Node Environment::CollectExceptionInfo uses V8 Object::Set: invoke real
    // inherited setters and ignore an ordinary false result, preserving throws.
    const key = try s.text(name);
    if (c.JS_SetPropertyValue(s.engine.context, target, c.JS_DupValue(s.engine.context, key), c.JS_DupValue(s.engine.context, value), 0) < 0) return js.capture(s.engine);
}
fn failure(engine: *em.Engine, code: Code, syscall: []const u8) anyerror {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const info = s.object() catch |err| return err;
    const Info = struct { name: []const u8, message: []const u8 };
    const item: Info = switch (code) {
        .noent => .{ .name = "ENOENT", .message = "no such file or directory" },
        .access => .{ .name = "EACCES", .message = "permission denied" },
        .perm => .{ .name = "EPERM", .message = "operation not permitted" },
        .nomem => .{ .name = "ENOMEM", .message = "not enough memory" },
        .nobufs => .{ .name = "ENOBUFS", .message = "no buffer space available" },
        .invalid => .{ .name = "EINVAL", .message = "invalid argument" },
        .badf => .{ .name = "EBADF", .message = "bad file descriptor" },
        .io => .{ .name = "EIO", .message = "i/o error" },
        .unknown => .{ .name = "UNKNOWN", .message = "unknown error" },
    };
    contextSet(&s, info, "errno", c.JS_NewInt32(engine.context, errnoValue(code))) catch |err| return err;
    contextSet(&s, info, "code", s.text(item.name) catch |err| return err) catch |err| return err;
    contextSet(&s, info, "message", s.text(item.message) catch |err| return err) catch |err| return err;
    contextSet(&s, info, "syscall", s.text(syscall) catch |err| return err) catch |err| return err;
    const reason = @import("native_node_fs_system_error.zig").fromContext(engine, info) catch |err| return err;
    defer engine.freeValue(reason);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    return js.capture(engine);
}
fn winCode() !Code {
    const code = @intFromEnum(w.kernel32.GetLastError());
    return switch (code) { 2, 3, 203 => .noent, 5, 1314 => .perm, 6 => .badf, 8, 14 => .nomem, 13, 87, 122 => .invalid, else => error.RequiredActualWindowsAccountErrorMapping };
}
fn posixCode(code: std.c.E) !Code {
    return switch (code) { .NOENT => .noent, .ACCES => .access, .PERM => .perm, .NOMEM => .nomem, .NOBUFS => .nobufs, .INVAL => .invalid, .BADF => .badf, .IO => .io, else => error.RequiredActualPosixAccountErrorMapping };
}
fn pathBytes(engine: *em.Engine, bytes: []const u8) !c.JSValue {
    const limit = if (builtin.os.tag == .windows) 260 else std.posix.PATH_MAX;
    const len = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
    if (len >= limit) return failure(engine, .nobufs, "uv_os_homedir");
    return engine.checked(c.JS_NewStringLen(engine.context, bytes.ptr, len));
}
const NativeHome = union(enum) { bytes: []u8, failed: Code };
// No guest execution here: release native token/scratch ownership BEFORE any
// error-context setter/SystemError construction or guest-visible JS allocation.
fn accountHomeBytes(engine: *em.Engine) !NativeHome {
    if (builtin.os.tag == .windows) {
        var token: w.HANDLE = undefined;
        if (Win.OpenProcessToken(w.GetCurrentProcess(), 0x20008, &token) == 0) return .{ .failed = try winCode() };
        defer w.CloseHandle(token);
        var count: u32 = 0;
        _ = Win.GetUserProfileDirectoryW(token, null, &count);
        if (w.kernel32.GetLastError() != .INSUFFICIENT_BUFFER) return .{ .failed = try winCode() };
        const buffer = try engine.gpa.alloc(u16, count); defer engine.gpa.free(buffer);
        if (Win.GetUserProfileDirectoryW(token, buffer.ptr, &count) == 0) return .{ .failed = try winCode() };
        // uv_os_get_passwd also queries the real account name before success.
        var username: [257]u16 = undefined; var user_count: u32 = username.len;
        if (Win.GetUserNameW(&username, &user_count) == 0) {
            if (w.kernel32.GetLastError() == .INSUFFICIENT_BUFFER) return .{ .failed = .nomem };
            return .{ .failed = try winCode() };
        }
        const end = std.mem.indexOfScalar(u16, buffer, 0) orelse buffer.len;
        return .{ .bytes = try std.unicode.wtf16LeToWtf8Alloc(engine.gpa, buffer[0..end]) };
    } else {
        var count: usize = 2000;
        while (true) {
            const buffer = try engine.gpa.alloc(u8, count); defer engine.gpa.free(buffer);
            var pwd: std.c.passwd = undefined; var result: ?*std.c.passwd = null;
            var rc: c_int = 0;
            while (true) { rc = std.c.getpwuid_r(std.c.geteuid(), &pwd, buffer.ptr, buffer.len, &result); if (rc != @intFromEnum(std.c.E.INTR)) break; }
            if (rc == @intFromEnum(std.c.E.RANGE)) { count = std.math.mul(usize, count, 2) catch return error.OutOfMemory; continue; }
            if (rc != 0) return .{ .failed = try posixCode(@enumFromInt(rc)) };
            if (result == null or pwd.dir == null) return .{ .failed = .noent };
            return .{ .bytes = try engine.gpa.dupe(u8, std.mem.span(pwd.dir.?)) };
        }
    }
}
fn accountHome(engine: *em.Engine) !c.JSValue {
    const result = try accountHomeBytes(engine);
    switch (result) {
        .bytes => |bytes| { defer engine.gpa.free(bytes); return pathBytes(engine, bytes); },
        .failed => |code| return failure(engine, code, "uv_os_homedir"),
    }
}
fn environmentHome(engine: *em.Engine, environment: c.JSValue) !?c.JSValue {
    const key = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
    var atom = c.JS_NewAtom(engine.context, key); if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (builtin.os.tag == .windows) {
        var properties: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, environment, c.JS_GPN_STRING_MASK) < 0) return js.capture(engine);
        defer c.JS_FreePropertyEnum(engine.context, properties, count);
        var matched = false;
        for (0..count) |index| {
            const name = c.JS_AtomToCString(engine.context, properties[index].atom) orelse return js.capture(engine);
            defer c.JS_FreeCString(engine.context, name);
            if (std.ascii.eqlIgnoreCase(std.mem.span(name), key)) {
                if (matched) return error.RequiredUnambiguousNativeEnvironmentEntry;
                matched = true;
                c.JS_FreeAtom(engine.context, atom);
                atom = c.JS_DupAtom(engine.context, properties[index].atom);
            }
        }
    }
    var descriptor: c.JSPropertyDescriptor = undefined;
    const found = c.JS_GetOwnProperty(engine.context, &descriptor, environment, atom);
    if (found < 0) return js.capture(engine); if (found == 0) return null;
    defer engine.freeValue(descriptor.value); defer engine.freeValue(descriptor.getter); defer engine.freeValue(descriptor.setter);
    // Actual native environment entries are own string data, not getter calls.
    // Full process.env exotic mutation semantics remain a separate provider gate.
    if (descriptor.flags & c.JS_PROP_GETSET != 0 or !c.JS_IsString(descriptor.value)) return error.RequiredActualNativeEnvironmentStringData;
    const bytes = try engine.toString(descriptor.value); defer engine.gpa.free(bytes);
    const len = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
    if (builtin.os.tag == .windows and len < 3) return failure(engine, .noent, "uv_os_homedir");
    return try pathBytes(engine, bytes[0..len]);
}
fn home(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (try environmentHome(engine, roots[0])) |value| return value;
    return accountHome(engine);
}
const OsInformation = struct { release: c.JSValue, kind: c.JSValue, version: c.JSValue };
fn windowsVersionBytes(engine: *em.Engine, info: *const w.RTL_OSVERSIONINFOW) ![]u8 {
    var product: [256]u16 = undefined;
    {
        const machine: w.HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2147483646))));
        var registry: w.HANDLE = undefined;
        if (Win.RegOpenKeyExW(machine, std.unicode.utf8ToUtf16LeStringLiteral("SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion"), 0, 0x101, &registry) != 0) return error.RequiredActualWindowsProductMetadata;
        defer _ = Win.RegCloseKey(registry);
        var bytes: u32 = @sizeOf(@TypeOf(product));
        if (Win.RegGetValueW(registry, null, std.unicode.utf8ToUtf16LeStringLiteral("ProductName"), 2, null, &product, &bytes) != 0) return error.RequiredActualWindowsProductMetadata;
    }
    // Native registry ownership is retired before any JS-visible work.
    const length = std.mem.indexOfScalar(u16, &product, 0) orelse return error.RequiredTerminatedWindowsProductMetadata;
    if (info.dwMajorVersion == 10 and info.dwBuildNumber >= 22000 and std.mem.startsWith(u16, product[0..length], std.unicode.utf8ToUtf16LeStringLiteral("Windows 10"))) product[9] = '1';
    const service_pack = std.mem.sliceTo(&info.szCSDVersion, 0);
    var joined: std.ArrayList(u16) = .empty; defer joined.deinit(engine.gpa);
    try joined.appendSlice(engine.gpa, product[0..length]);
    if (service_pack.len != 0) { if (length != 0) try joined.append(engine.gpa, ' '); try joined.appendSlice(engine.gpa, service_pack); }
    const bytes = try std.unicode.wtf16LeToWtf8Alloc(engine.gpa, joined.items); errdefer engine.gpa.free(bytes);
    if (bytes.len >= 256) return error.RequiredRepresentableWindowsProductMetadata;
    return bytes;
}
fn osInformation(s: *Scope) !OsInformation {
    const engine = s.engine;
    if (builtin.os.tag == .windows) {
        var info: w.RTL_OSVERSIONINFOW = std.mem.zeroes(w.RTL_OSVERSIONINFOW); info.dwOSVersionInfoSize = @sizeOf(w.RTL_OSVERSIONINFOW);
        if (w.ntdll.RtlGetVersion(&info) != .SUCCESS) return error.RequiredActualWindowsVersionInformation;
        const text = try std.fmt.allocPrint(engine.gpa, "{d}.{d}.{d}", .{ info.dwMajorVersion, info.dwMinorVersion, info.dwBuildNumber }); defer engine.gpa.free(text);
        const version = try windowsVersionBytes(engine, &info); defer engine.gpa.free(version);
        return .{ .release = try s.text(text), .kind = try s.text("Windows_NT"), .version = try s.text(version) };
    } else {
        var info: std.c.utsname = undefined; const rc = std.c.uname(&info);
        if (rc != 0) return failure(engine, try posixCode(std.c.errno(rc)), "uv_os_uname");
        return .{ .release = try s.text(std.mem.sliceTo(&info.release, 0)), .kind = try s.text(std.mem.sliceTo(&info.sysname, 0)), .version = try s.text(std.mem.sliceTo(&info.version, 0)) };
    }
}
fn release(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return c.JS_DupValue(engine.context, roots[0]); }
fn platform(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); return c.JS_DupValue(engine.context, try s.get(try s.global("process"), "platform"));
}
fn arch(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); return c.JS_DupValue(engine.context, try s.get(try s.global("process"), "arch"));
}
fn primitive(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return js.call(engine, roots[0], c.pi_js_undefined(), &.{}); }
fn addPrimitive(s: *Scope, function: c.JSValue) !void {
    const symbol = try s.get(try s.global("Symbol"), "toPrimitive"); const atom = try js.atom(s.engine, symbol); defer c.JS_FreeAtom(s.engine.context, atom);
    const convert = try s.own(try functions.createArrow(s.engine, "", 0, primitive, &.{function}));
    if (c.JS_DefinePropertyValue(s.engine.context, function, atom, c.JS_DupValue(s.engine.context, convert), c.JS_PROP_C_W_E) < 0) return js.capture(s.engine);
}
fn addSignals(s: *Scope, exports: c.JSValue) !void {
    const signals = try s.object();
    if (builtin.os.tag == .windows) {
        // Node official Windows/MSVC constants + libuv win.h, in actual Node
        // DefineSignalConstants order. SIGABRT_COMPAT is not a public export.
        inline for (.{ .{ "SIGHUP", 1 }, .{ "SIGINT", 2 }, .{ "SIGQUIT", 3 }, .{ "SIGILL", 4 }, .{ "SIGABRT", 22 }, .{ "SIGFPE", 8 }, .{ "SIGKILL", 9 }, .{ "SIGSEGV", 11 }, .{ "SIGTERM", 15 }, .{ "SIGBREAK", 21 }, .{ "SIGWINCH", 28 } }) |entry| {
            if (c.JS_DefinePropertyValueStr(s.engine.context, signals, entry[0], c.JS_NewInt32(s.engine.context, entry[1]), c.JS_PROP_ENUMERABLE) < 0) return js.capture(s.engine);
        }
    } else {
        inline for (.{ "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGTRAP", "SIGABRT", "SIGIOT", "SIGBUS", "SIGFPE", "SIGKILL", "SIGUSR1", "SIGSEGV", "SIGUSR2", "SIGPIPE", "SIGALRM", "SIGTERM", "SIGCHLD", "SIGSTKFLT", "SIGCONT", "SIGSTOP", "SIGTSTP", "SIGBREAK", "SIGTTIN", "SIGTTOU", "SIGURG", "SIGXCPU", "SIGXFSZ", "SIGVTALRM", "SIGPROF", "SIGWINCH", "SIGIO", "SIGPOLL", "SIGLOST", "SIGPWR", "SIGINFO", "SIGSYS", "SIGUNUSED" }) |name| {
            if (@hasDecl(posix_signals, name)) {
                if (c.JS_DefinePropertyValueStr(s.engine.context, signals, name, c.JS_NewInt32(s.engine.context, @intCast(@field(posix_signals, name))), c.JS_PROP_ENUMERABLE) < 0) return js.capture(s.engine);
            }
        }
    }
    if (c.JS_PreventExtensions(s.engine.context, signals) < 0) return js.capture(s.engine);
    const constants = try s.object(); try s.put(constants, "signals", signals);
    if (c.JS_DefinePropertyValueStr(s.engine.context, exports, "constants", c.JS_DupValue(s.engine.context, constants), c.JS_PROP_ENUMERABLE) < 0) return js.capture(s.engine);
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const process_module = engine.native_module_values.get("node:process") orelse return error.RequiredActualNativeProcess;
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const process = try s.get(process_module, "default"); const environment = try s.get(process, "env");
    try @import("native_node_stream.zig").install(engine, process);
    try @import("native_node_fs_system_error.zig").install(engine);
    const result = try s.object();
    const homedir = try s.own(try functions.create(engine, "checkError", 0, home, &.{environment})); try addPrimitive(&s, homedir); try s.put(result, "homedir", homedir);
    const info = try osInformation(&s);
    inline for (.{ .{ "release", "getOSRelease", info.release }, .{ "type", "getOSType", info.kind }, .{ "version", "getOSVersion", info.version } }) |entry| {
        const function = try s.own(try functions.createArrow(engine, entry[1], 0, release, &.{entry[2]})); try addPrimitive(&s, function); try s.put(result, entry[0], function);
    }
    inline for (.{ .{ "platform", platform }, .{ "arch", arch } }) |entry| { const function = try s.own(try functions.create(engine, entry[0], 0, entry[1], &.{})); try addPrimitive(&s, function); try s.put(result, entry[0], function); }
    const temporary = try s.own(try @import("native_os_tmpdir.zig").create(engine)); try s.put(result, "tmpdir", try s.get(temporary, "tmpdir"));
    inline for (.{ .{ "EOL", if (builtin.os.tag == .windows) "\r\n" else "\n" }, .{ "devNull", if (builtin.os.tag == .windows) "\\\\.\\nul" else "/dev/null" } }) |entry| {
        const value = try s.text(entry[1]);
        if (c.JS_DefinePropertyValueStr(engine.context, result, entry[0], c.JS_DupValue(engine.context, value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    }
    try addSignals(&s, result);
    return c.JS_DupValue(engine.context, result);
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains("node:os")) return;
    const exports = try create(engine); defer engine.freeValue(exports);
    try engine.registerDefaultModule("node:os", exports);
    try engine.registerDefaultModule("os", exports);
}
