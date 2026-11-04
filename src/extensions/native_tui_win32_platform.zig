//! Complete, source-bound Win32 TUI addon on the existing linked C engine.
//! The selected prebuild bytes identify this one original module. They are
//! never loaded as a DLL. No generic N-API/process.dlopen surface is published.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const c = js.c;
const abi = @import("native_tui_win32_platform_abi.zig");
const callable = @import("native_node_module_callable.zig");
const Scope = @import("native_node_operation_scope.zig").Scope;
const promises = @import("native_tui_win32_clipboard_promise.zig");
const Worker = @import("native_tui_win32_clipboard_worker.zig").Worker;

fn supportedTarget() bool {
    return builtin.os.tag == .windows and
        (builtin.cpu.arch == .x86_64 or builtin.cpu.arch == .aarch64);
}
fn enableInput(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try @import("native_process_streams.zig").enableVirtualTerminalInput(engine)));
}
fn modifier(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    if (args.len == 0 or !c.JS_IsString(args[0])) return c.pi_js_bool(engine.context, 0);
    var length: usize = 0;
    const raw = c.JS_ToCStringLen(engine.context, &length, args[0]) orelse return js.capture(engine);
    defer c.JS_FreeCString(engine.context, raw);
    // The original N-API callback reads a primitive string into char name[16].
    // All accepted modifier names are ASCII; embedded NUL remains a terminator.
    var name: [16:0]u8 = @splat(0);
    const copied = @min(length, 15);
    @memcpy(name[0..copied], raw[0..copied]);
    const native_name = std.mem.sliceTo(&name, 0);
    var recognized = false;
    inline for (.{ "shift", "control", "option", "alt", "command", "super", "win" }) |accepted|
        if (std.mem.eql(u8, native_name, accepted)) { recognized = true; };
    // Original strcmp rejects every other name before any key-state query.
    // This also keeps a truncated multibyte tail out of the JSON transport.
    if (!recognized) return c.pi_js_bool(engine.context, 0);
    return c.pi_js_bool(engine.context, @intFromBool(try @import("native_process_streams.zig").isModifierPressed(engine, native_name)));
}
fn queue(engine: *js.Engine, operation: abi.Operation, args: []const c.JSValue) !c.JSValue {
    var units: ?[]const u16 = null;
    var raw: ?[*]const u16 = null;
    defer if (raw) |text| c.JS_FreeCStringUTF16(engine.context, text);
    if (operation == .write) {
        if (args.len == 0 or !c.JS_IsString(args[0])) return promises.throwMessage(engine, "setText requires a string");
        const converted = @import("native_tui_win32_value.zig").inputUtf16(engine, args[0]) catch |err| {
            if (err == error.OutOfMemory or err == error.ExecutionTerminated) return err;
            // N-API reports ordinary conversion failure with this exact public
            // message. errorValue first surfaces any real native pending event.
            return promises.throwMessage(engine, "Could not read clipboard text");
        };
        raw = converted.ptr;
        units = converted;
    }
    const task = Worker.create(engine, operation, units) catch |err| {
        if (err == error.NativeClipboardJobAllocation) return promises.throwMessage(engine, "Out of memory");
        if (err == error.NativeClipboardTextCopy) return promises.throwMessage(engine, "Could not read clipboard text");
        if (err == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal();
        return err;
    };
    // create consumes the copied native task on success and every failure.
    return promises.create(engine, task) catch |err| {
        if (err == error.OutOfMemory or err == error.JavaScriptException or err == error.ExecutionTerminated) return err;
        return promises.throwMessage(engine, "Could not queue clipboard operation");
    };
}
fn getText(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return queue(engine, .text, args);
}
fn setText(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return queue(engine, .write, args);
}
fn getImage(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return queue(engine, .image, args);
}
fn setFunctionExport(stage: *Scope, exports: c.JSValue, name: [:0]const u8, callback: callable.Callback) !void {
    const key = try stage.text(name);
    const function = try stage.own(try callable.create(stage.engine, name, 0, true, callback, &.{}));
    try stage.pending();
    // napi_set_named_property uses ordinary Set. Inherited setters run, and a
    // nonwritable property returns false without a new strict-mode exception.
    // The original export helper ignores that false/status, but a genuinely
    // pending exception still prevents the subsequent native callbacks.
    const status = c.JS_SetPropertyValue(stage.engine.context, exports,
        c.JS_DupValue(stage.engine.context, key), c.JS_DupValue(stage.engine.context, function), 0);
    try stage.pending();
    if (status < 0) return error.MissingNativeTuiExportSetReason;
}
fn initializeBody(stage: *Scope, exports: c.JSValue) !c.JSValue {
    try stage.pending();
    try setFunctionExport(stage, exports, "enableVirtualTerminalInput", enableInput);
    try setFunctionExport(stage, exports, "isModifierPressed", modifier);
    try setFunctionExport(stage, exports, "getText", getText);
    try setFunctionExport(stage, exports, "setText", setText);
    try setFunctionExport(stage, exports, "getImage", getImage);
    return c.pi_js_undefined();
}
pub fn initialize(engine: *js.Engine, exports: c.JSValue) !void {
    if (comptime !supportedTarget()) return error.NativeAddonNotAdmitted;
    // napi_create_function's original V8 factory has length zero and allows
    // construction. The real callable owner preserves return-object override.
    var stage = Scope.init(engine);
    const result = try stage.finish(initializeBody(&stage, exports));
    engine.freeValue(result);
}
/// The active CommonJS caller has already resolved the exact physical filename
/// and consulted require.cache. loadNative also rechecks that same live cache
/// immediately before publishing a new ordinary Module record.
pub fn load(engine: *js.Engine, io: std.Io, filename: []const u8) !c.JSValue {
    if (comptime !supportedTarget()) return error.NativeAddonNotAdmitted;
    const expected_size: usize = if (builtin.cpu.arch == .x86_64) 8704 else 9216;
    const expected = if (builtin.cpu.arch == .x86_64)
        [_]u8{ 0x51, 0xbe, 0xe0, 0x2b, 0xcb, 0x73, 0xb1, 0x65, 0xab, 0x92, 0xaf, 0x75, 0xae, 0x15, 0xb8, 0x8a, 0xba, 0x3f, 0x5d, 0x99, 0xf0, 0x72, 0xe6, 0x3e, 0xf6, 0x0a, 0xf9, 0x2f, 0xfd, 0xc4, 0xd5, 0x65 }
    else
        [_]u8{ 0x0e, 0x56, 0x71, 0xab, 0x39, 0xef, 0x57, 0x79, 0x40, 0x48, 0x3c, 0xed, 0x58, 0xfd, 0xf6, 0x9e, 0xcd, 0xf5, 0xf8, 0x64, 0xf3, 0x68, 0xd9, 0x0a, 0x77, 0x1e, 0xec, 0x4a, 0xee, 0xae, 0x11, 0xb8 };
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, filename, engine.gpa, .limited(expected_size + 1));
    defer engine.gpa.free(bytes);
    if (bytes.len != expected_size) return error.NativeAddonNotAdmitted;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    if (!std.mem.eql(u8, &digest, &expected)) return error.NativeAddonNotAdmitted;
    return @import("commonjs.zig").loadNative(engine, filename, initialize);
}
