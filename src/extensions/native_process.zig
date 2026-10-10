//! Process information required by native programmatic SDK inputs.
//! Environment ownership is supplied by the embedding host, never synthesized
//! from a JavaScript bootstrap or retrieved through a child process.
const std = @import("std");
const builtin = @import("builtin");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
fn put(engine: *engine_mod.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}
fn currentDirectory(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const io = engine.native_io orelse return c.JS_ThrowTypeError(context, "Native process requires IO");
    const directory = std.Io.Dir.cwd().openDir(io, ".", .{}) catch return c.JS_ThrowTypeError(context, "Unable to open current directory");
    defer directory.close(io);
    const count = directory.realPath(io, &buffer) catch return c.JS_ThrowTypeError(context, "Unable to resolve current directory");
    return c.JS_NewStringLen(context, &buffer, count);
}
pub fn install(engine: *engine_mod.Engine, io: std.Io, environment: *const std.process.Environ.Map, arguments: []const []const u8) !void {
    engine.native_io = io;
    const process = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(process);
    const env = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(env);
    var fields = environment.iterator();
    while (fields.next()) |field| {
        const key = try engine.gpa.dupeZ(u8, field.key_ptr.*);
        defer engine.gpa.free(key);
        try put(engine, env, key, try engine.checked(c.JS_NewStringLen(engine.context, field.value_ptr.ptr, field.value_ptr.len)));
    }
    try put(engine, process, "env", c.JS_DupValue(engine.context, env));
    try put(engine, process, "cwd", try engine.checked(c.JS_NewCFunction(engine.context, currentDirectory, "cwd", 0)));
    const platform = if (builtin.os.tag == .windows) "win32" else @tagName(builtin.os.tag);
    try put(engine, process, "platform", try engine.checked(c.JS_NewString(engine.context, platform)));
    const args = try engine.checked(c.JS_NewArray(engine.context));
    defer engine.freeValue(args);
    for (arguments, 0..) |arg, index| if (c.JS_SetPropertyUint32(engine.context, args, @intCast(index), try engine.checked(c.JS_NewStringLen(engine.context, arg.ptr, arg.len))) < 0) return error.JavaScriptException;
    try put(engine, process, "argv", c.JS_DupValue(engine.context, args));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try put(engine, global, "process", c.JS_DupValue(engine.context, process));
    try engine.registerDefaultModule("node:process", process);
    try engine.registerDefaultModule("process", process);
}

test "native process retains host environment and module identity" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("PI_AGENT_DIR", "isolated");
    try install(engine, std.testing.io, &environment, &.{ "native-sdk", "example.ts" });
    environment.deinit();
    environment = .init(std.testing.allocator);
    const result = try engine.evalModule("import process,{env,cwd} from 'node:process';if(process!==globalThis.process||env!==process.env||env.PI_AGENT_DIR!=='isolated'||process.argv[1]!=='example.ts'||typeof cwd()!=='string')throw Error('process ownership');export const result=true;", "process-sdk.mjs");
    defer engine.freeValue(result);
}
