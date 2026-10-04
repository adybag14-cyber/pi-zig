//! Native URL file conversion; other URL APIs remain separate ports.
const std = @import("std");
const builtin = @import("builtin");
const engine_mod = @import("engine.zig");
const file_urls = @import("file_urls.zig");
const c = engine_mod.c;

pub fn install(engine: *engine_mod.Engine) !void {
    const object = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(object);
    const function = try engine.checked(c.JS_NewCFunction(engine.context, fileURLToPath, "fileURLToPath", 1));
    if (c.JS_DefinePropertyValueStr(engine.context, object, "fileURLToPath", function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    try engine.registerDefaultModule("node:url", object);
    try engine.registerDefaultModule("url", object);
}

fn fileURLToPath(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return convert(engine, argv[0..@intCast(argc)]) catch |err| c.JS_ThrowTypeError(context, "Native file URL conversion failed: %s", @as([*:0]const u8, @errorName(err)));
}

fn convert(engine: *engine_mod.Engine, args: []c.JSValue) !c.JSValue {
    if (args.len == 0 or !c.JS_IsString(args[0])) return error.InvalidNativeFileUrlArgument;
    var windows = builtin.os.tag == .windows;
    if (args.len > 1 and !c.JS_IsUndefined(args[1])) {
        if (!c.JS_IsObject(args[1]) or c.JS_IsNull(args[1])) return error.InvalidNativeFileUrlOptions;
        const option = try engine.checked(c.JS_GetPropertyStr(engine.context, args[1], "windows"));
        defer engine.freeValue(option);
        if (!c.JS_IsUndefined(option)) {
            if (!c.JS_IsBool(option)) return error.InvalidNativeFileUrlOptions;
            windows = c.JS_ToBool(engine.context, option) == 1;
        }
    }
    const input = try engine.toString(args[0]);
    defer engine.gpa.free(input);
    const path = try file_urls.toPath(engine.gpa, input, windows);
    defer engine.gpa.free(path);
    return engine.checked(c.JS_NewStringLen(engine.context, path.ptr, path.len));
}

test "native fileURLToPath exports decode file URLs with explicit platform options" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const result = engine.evalModule(
        "import {fileURLToPath} from 'node:url'; import legacy from 'url';" ++
            "if (legacy.fileURLToPath!==fileURLToPath || fileURLToPath('file:///tmp/a%20b.js?x#part',{windows:false})!=='/tmp/a b.js' || fileURLToPath('file:///C:/a%20b.js',{windows:true})!=='C:\\\\a b.js') throw Error('conversion');" ++
            "let rejected=0; for(const call of [()=>fileURLToPath('https://example.com/a'),()=>fileURLToPath('file:///a%2fb',{windows:false}),()=>fileURLToPath('file:///tmp/a',{windows:'false'}),()=>fileURLToPath(null)]){try{call();}catch(error){if(!(error instanceof TypeError))throw error;rejected++;}}if(rejected!==4)throw Error('validation');",
        "native-url-fixture.mjs",
    ) catch |err| {
        std.debug.print("Native URL fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(result);
}
