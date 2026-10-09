//! Node-compatible current-user home lookup without a subprocess or host shim.
//! Read-only OS fallback requires the embedding owner's admitted native IO.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
const win = struct {
    extern "advapi32" fn OpenProcessToken(std.os.windows.HANDLE, u32, *std.os.windows.HANDLE) callconv(.winapi) std.os.windows.BOOL;
    extern "userenv" fn GetUserProfileDirectoryW(std.os.windows.HANDLE, ?[*]u16, *u32) callconv(.winapi) std.os.windows.BOOL;
};
fn missing(engine: *Engine) anyerror {
    const message = try v.text(engine, "A system error occurred: uv_os_homedir returned ENOENT (no such file or directory)");
    defer engine.freeValue(message);
    const exception = try js.builtin(engine, "Error", &.{message});
    var exception_transferred = false;
    errdefer if (!exception_transferred) engine.freeValue(exception);
    try js.define(engine, exception, "name", try v.text(engine, "SystemError"));
    try js.define(engine, exception, "code", try v.text(engine, "ERR_SYSTEM_ERROR"));
    const info = try js.object(engine);
    var transferred = false;
    defer if (!transferred) engine.freeValue(info);
    try js.define(engine, info, "errno", v.numeric(engine, if (builtin.os.tag == .windows) -4058 else -2));
    try js.define(engine, info, "code", try v.text(engine, "ENOENT"));
    try js.define(engine, info, "message", try v.text(engine, "no such file or directory"));
    try js.define(engine, info, "syscall", try v.text(engine, "uv_os_homedir"));
    transferred = true;
    try js.define(engine, exception, "info", info);
    exception_transferred = true;
    _ = try engine.checked(c.JS_Throw(engine.context, exception));
    unreachable;
}
pub fn get(engine: *Engine) !c.JSValue {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const environment = try js.get(engine, process, "env");
    defer engine.freeValue(environment);
    const name: [*:0]const u8 = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
    const supplied = try js.get(engine, environment, name);
    defer engine.freeValue(supplied);
    if (!c.JS_IsUndefined(supplied)) {
        const units = try utf16.unitsAlloc(engine, supplied);
        defer engine.gpa.free(units);
        if (builtin.os.tag == .windows and units.len < 3) return missing(engine);
        return utf16.string(engine, units);
    }
    if (engine.native_io == null) return error.NativeHomeIoUnavailable;
    if (comptime builtin.os.tag == .windows) {
        var token: std.os.windows.HANDLE = undefined;
        if (!win.OpenProcessToken(std.os.windows.GetCurrentProcess(), 0x20008, &token).toBool()) return error.NativeHomeTokenUnavailable;
        defer std.os.windows.CloseHandle(token);
        var length: u32 = 0;
        _ = win.GetUserProfileDirectoryW(token, null, &length);
        if (std.os.windows.GetLastError() != .INSUFFICIENT_BUFFER or length == 0) return error.NativeHomeProfileUnavailable;
        if (length > 1024 * 1024) return error.NativeHomeProfileLimit;
        const buffer = try engine.gpa.alloc(u16, length);
        defer engine.gpa.free(buffer);
        if (!win.GetUserProfileDirectoryW(token, buffer.ptr, &length).toBool()) return error.NativeHomeProfileUnavailable;
        return utf16.string(engine, std.mem.sliceTo(buffer, 0));
    } else if (comptime builtin.os.tag == .linux or builtin.os.tag == .macos or builtin.os.tag == .freebsd) {
        var size: usize = 1024;
        while (size <= 1024 * 1024) : (size *= 2) {
            const buffer = try engine.gpa.alloc(u8, size);
            defer engine.gpa.free(buffer);
            var record: std.c.passwd = undefined;
            var result: ?*std.c.passwd = null;
            const status = std.c.getpwuid_r(std.c.getuid(), &record, buffer.ptr, buffer.len, &result);
            if (status == @intFromEnum(std.c.E.RANGE)) continue;
            if (status != 0 or result == null or record.dir == null) return missing(engine);
            return v.text(engine, std.mem.span(record.dir.?));
        }
        return error.NativeHomeProfileLimit;
    } else return error.NativeHomePlatformUnavailable;
}
fn invoke(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return get(engine) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return c.JS_ThrowTypeError(context, "Native home lookup: %s", @as([*:0]const u8, @errorName(err)));
    };
}
test "Source6fb terminal image home lookup matches actual Node24 environment and OS fallback" {
    if (builtin.os.tag != .windows and builtin.os.tag != .linux) return error.SkipZigTest;
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment = try std.testing.environ.createMap(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"native-home"});
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeHome", try engine.checked(c.JS_NewCFunction(engine.context, invoke, "homedir", 0)));
    const bytes = if (builtin.os.tag == .windows) @embedFile("fixtures/home-directory-original-win32-node24.json") else @embedFile("fixtures/home-directory-original-linux-node24.json");
    try js.define(engine, root, "homeFixture", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "home-directory-original-node24.json")));
    const result = engine.evalModule(
        \\const key=process.platform==='win32'?'USERPROFILE':'HOME',old=process.env[key],baseline=nativeHome();try{for(const item of homeFixture.cases){if(item.fallback)delete process.env[key];else process.env[key]=item.value;let actual;try{actual=nativeHome()}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage&&e.code===item.errorCode&&JSON.stringify(e.info)===JSON.stringify(item.info))continue;throw e}if(item.errorName||actual!==(item.fallback&&item.matchesBaseline?baseline:item.result))throw Error(JSON.stringify({item,actual}));}}finally{if(old===undefined)delete process.env[key];else process.env[key]=old}
    , "native-home-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native image home lookup: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
