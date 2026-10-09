//! Executes captured extension-language input against native Theme operations.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Engine = js.Engine;
const theme = @import("native_theme.zig");
const watch = @import("native_theme_watch.zig");
const io_watch = @import("native_io_watch.zig");
const v = @import("native_select_list.zig");
const Method = enum(c_int) { initTheme, setTheme, setThemeInstance, onThemeChange, stopThemeWatcher, getThemeByName, setRegisteredThemes };
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowInternalError(engine.context, "Theme fixture: %s", @as([*:0]const u8, @errorName(err)));
}
fn listener(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    switch (magic) {
        0 => io_watch.deliver(engine, data[0], if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| return fail(engine, err),
        1 => io_watch.deliverError(engine, data[0]) catch |err| return fail(engine, err),
        2 => return c.pi_js_bool(engine.context, @intFromBool(io_watch.closed(data[0]))),
        else => unreachable,
    }
    return c.pi_js_undefined();
}
fn recordWatcher(engine: *Engine, watchers: c.JSValue) !void {
    const module = try theme.moduleState(engine);
    defer engine.freeValue(module);
    const holder = try js.get(engine, module, "themeWatcher");
    defer engine.freeValue(holder);
    if (c.JS_IsUndefined(holder)) return;
    const wrapper = try js.object(engine);
    defer engine.freeValue(wrapper);
    var data = [_]c.JSValue{holder};
    inline for (.{ .{ "listener", 0 }, .{ "error", 1 } }) |entry| try js.define(engine, wrapper, entry[0], try engine.checked(c.JS_NewCFunctionData2(engine.context, listener, entry[0], 2, entry[1], 1, &data)));
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, listener, "get closed", 0, 2, 1, &data));
    const atom = c.JS_NewAtom(engine.context, "closed");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, wrapper, atom, getter, c.pi_js_undefined(), c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    try js.push(engine, watchers, wrapper);
}
fn call(engine: *Engine, operation: Method, args: []const c.JSValue, watchers: c.JSValue) !c.JSValue {
    switch (operation) {
        .initTheme => {
            const exports = engine.native_module_values.get("pi-coding-agent").?;
            const ignored = try js.invoke(engine, exports, "initTheme", args);
            engine.freeValue(ignored);
            if (v.truthy(engine, v.arg(args, 1))) try recordWatcher(engine, watchers);
        },
        .setTheme => return theme.setTheme(engine, v.arg(args, 0), v.truthy(engine, v.arg(args, 1))),
        .setThemeInstance => try theme.setThemeInstance(engine, v.arg(args, 0)),
        .onThemeChange => try theme.onThemeChange(engine, v.arg(args, 0)),
        .setRegisteredThemes => try theme.setRegisteredThemes(engine, v.arg(args, 0)),
        .stopThemeWatcher => {
            const module = try theme.moduleState(engine);
            defer engine.freeValue(module);
            try watch.stop(engine, module);
        },
        .getThemeByName => {
            const name = try engine.toString(v.arg(args, 0));
            defer engine.gpa.free(name);
            return theme.getThemeByName(engine, name);
        },
    }
    return c.pi_js_undefined();
}
fn method(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return call(engine, @enumFromInt(magic), argv[0..@intCast(argc)], data[0]) catch |err| fail(engine, err);
}
test "Source6fb Theme watcher captured module lifecycle debounce stale timers errors and explicit stops" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "themes", .default_dir);
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("PI_CODING_AGENT_DIR", path_buffer[0..length]);
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"watch-oracle"});
    try @import("node_fs.zig").install(engine, std.testing.io);
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    const module = try theme.moduleState(engine);
    defer engine.freeValue(module);
    defer watch.stop(engine, module) catch {};
    const api = try js.object(engine);
    defer engine.freeValue(api);
    const watchers = try js.array(engine);
    defer engine.freeValue(watchers);
    var data = [_]c.JSValue{watchers};
    inline for (std.meta.fields(Method)) |field| try js.define(engine, api, field.name.ptr, try engine.checked(c.JS_NewCFunctionData2(engine.context, method, field.name.ptr, 1, @intCast(field.value), 1, &data)));
    try js.define(engine, api, "theme", try js.get(engine, engine.native_module_values.get("pi-coding-agent").?, "theme"));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "themeWatchApi", c.JS_DupValue(engine.context, api));
    try js.define(engine, global, "themeWatchers", c.JS_DupValue(engine.context, watchers));
    try js.define(engine, global, "themeWatchRoot", try v.text(engine, path_buffer[0..length]));
    const bytes = @embedFile("fixtures/theme-watcher-original-6fb.json");
    try js.define(engine, global, "themeWatchOracle", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "theme-watcher-original-6fb.json")));
    const base = @embedFile("../themes/fixtures/dark-original-6fb.json");
    try js.define(engine, global, "themeWatchBase", try engine.checked(c.JS_ParseJSON(engine.context, base.ptr, base.len, "theme-watcher-base.json")));
    const result = engine.evalModule(
        \\import fs from'node:fs';const actual=new Function('api','watchers','root','base','fs',themeWatchOracle.script)(themeWatchApi,themeWatchers,themeWatchRoot,themeWatchBase,fs);const expected=themeWatchOracle.observations.map(({events,...item})=>({...item,timerEvents:events.filter(event=>event[0]==='timeout'||event[0]==='clear')}));if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));for(const[index,item]of themeWatchOracle.structural.entries()){let result;try{result=new Function('api','"use strict";'+item.script)(themeWatchApi)}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw e}finally{themeWatchApi.onThemeChange(undefined);themeWatchApi.setRegisteredThemes([]);themeWatchApi.initTheme('dark',false)}if(item.errorName||JSON.stringify(result)!==JSON.stringify(item.result))throw Error(JSON.stringify({structural:index,result,expected:item}));}
    , "theme-watcher-source-oracle.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Theme watch oracle: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
