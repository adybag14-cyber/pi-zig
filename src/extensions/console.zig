//! Native console output stays on stderr, outside the worker record stream.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;

pub fn format(engine: *engine_mod.Engine, arguments: []const c.JSValue) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(engine.gpa);
    defer output.deinit();
    for (arguments, 0..) |value, index| {
        if (index > 0) try output.writer.writeByte(' ');
        const projected = if (c.JS_IsString(value)) c.JS_DupValue(engine.context, value) else try engine.checked(c.JS_JSONStringify(engine.context, value, c.pi_js_undefined(), c.pi_js_undefined()));
        defer engine.freeValue(projected);
        // Matches the legacy bridge's JSON projection and join semantics.
        if (c.JS_IsUndefined(projected)) continue;
        const text = try engine.toString(projected);
        defer engine.gpa.free(text);
        try output.writer.writeAll(text);
    }
    try output.writer.writeByte('\n');
    return output.toOwnedSlice();
}

fn write(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const arguments: []const c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
    emit(engine, arguments) catch |err| return c.JS_ThrowTypeError(context, "Native console failed: %s", @as([*:0]const u8, @errorName(err)));
    return c.pi_js_undefined();
}

fn emit(engine: *engine_mod.Engine, arguments: []const c.JSValue) !void {
    const io = engine.native_io orelse return error.NativeConsoleIoUnavailable;
    const line = try format(engine, arguments);
    defer engine.gpa.free(line);
    var buffer: [4096]u8 = undefined;
    var output = (if (engine.native_console_stdout) std.Io.File.stdout() else std.Io.File.stderr()).writerStreaming(io, &buffer);
    try output.interface.writeAll(line);
    try output.interface.flush();
}

pub fn install(engine: *engine_mod.Engine, io: std.Io) !void {
    engine.native_io = io;
    const object = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(object);
    inline for (.{ "log", "info", "debug", "warn", "error" }) |name| {
        const function = try engine.checked(c.JS_NewCFunction(engine.context, write, name, 0));
        if (c.JS_DefinePropertyValueStr(engine.context, object, name, function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, "console", c.JS_DupValue(engine.context, object), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    try engine.registerDefaultModule("node:console", object);
    try engine.registerDefaultModule("console", object);
}

test "native console formats JSON values without exposing protocol records" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const value = try engine.eval("({message:'hello',value:42})", "console-value.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    const text = try engine.checked(c.JS_NewString(engine.context, "native"));
    defer engine.freeValue(text);
    const line = try format(engine, &.{ text, value, c.pi_js_undefined() });
    defer std.testing.allocator.free(line);
    try std.testing.expectEqualStrings("native {\"message\":\"hello\",\"value\":42} \n", line);
    const empty = try format(engine, &.{});
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqualStrings("\n", empty);
}

test "native console imports preserve global identity without cyclic default properties" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const namespace = try engine.evalModule("import console, {log} from 'node:console'; export const same=console===globalThis.console && log===console.log; export const encoded=JSON.stringify(console);", "console-import.js");
    defer engine.freeValue(namespace);
    const same = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "same"));
    defer engine.freeValue(same);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, same));
    const encoded = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "encoded"));
    defer engine.freeValue(encoded);
    const text = try engine.toString(encoded);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{}", text);
}
