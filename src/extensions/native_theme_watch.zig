//! Source module-global custom Theme watcher and debounce lifecycle.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const v = @import("native_select_list.zig");
const paths = @import("node_path.zig");
const theme = @import("native_theme.zig");
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowInternalError(engine.context, "Native Theme watcher: %s", @as([*:0]const u8, @errorName(err)));
}
fn discardException(engine: *Engine) void {
    if (engine.captured_exception) |value| engine.freeValue(value);
    engine.captured_exception = null;
    if (engine.last_error) |value| engine.gpa.free(value);
    engine.last_error = null;
}
fn invokeGlobal(engine: *Engine, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try js.global(engine, name);
    defer engine.freeValue(function);
    return js.call(engine, function, c.pi_js_undefined(), args);
}
fn closeWatch(engine: *Engine, value: c.JSValue) void {
    if (!v.truthy(engine, value)) return;
    const ignored = js.invoke(engine, value, "close", &.{}) catch {
        discardException(engine);
        return;
    };
    engine.freeValue(ignored);
}
pub fn initialize(engine: *Engine, module: c.JSValue) !void {
    try @import("native_io_watch.zig").install(engine, module);
    try @import("node_url.zig").install(engine);
    try js.define(engine, module, "themeFileURLToPath", try js.get(engine, engine.native_module_values.get("node:url").?, "fileURLToPath"));
    inline for (.{ "currentThemeName", "themeWatcher", "themeReloadTimer", "onThemeChangeCallback" }) |name| try js.define(engine, module, name, c.pi_js_undefined());
}
pub fn stop(engine: *Engine, module: c.JSValue) !void {
    const timer = try js.get(engine, module, "themeReloadTimer");
    defer engine.freeValue(timer);
    if (v.truthy(engine, timer)) {
        const ignored = try invokeGlobal(engine, "clearTimeout", &.{timer});
        engine.freeValue(ignored);
        try js.define(engine, module, "themeReloadTimer", c.pi_js_undefined());
    }
    const watcher = try js.get(engine, module, "themeWatcher");
    defer engine.freeValue(watcher);
    closeWatch(engine, watcher);
    try js.define(engine, module, "themeWatcher", c.pi_js_undefined());
}
pub fn notify(engine: *Engine, module: c.JSValue) !void {
    const callback = try js.get(engine, module, "onThemeChangeCallback");
    defer engine.freeValue(callback);
    if (!v.truthy(engine, callback)) return;
    const ignored = try js.call(engine, callback, c.pi_js_undefined(), &.{});
    engine.freeValue(ignored);
}
fn exists(engine: *Engine, path: []const u8) bool {
    const io = engine.native_io orelse return false;
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}
fn sameName(engine: *Engine, module: c.JSValue, watched: c.JSValue) !bool {
    const current = try js.get(engine, module, "currentThemeName");
    defer engine.freeValue(current);
    return c.JS_IsStrictEqual(engine.context, current, watched);
}
fn reload(engine: *Engine, module: c.JSValue, watched: c.JSValue, file: c.JSValue) !void {
    try js.define(engine, module, "themeReloadTimer", c.pi_js_undefined());
    if (!try sameName(engine, module, watched)) return;
    const path = try engine.toString(file);
    defer engine.gpa.free(path);
    if (!exists(engine, path)) return;
    const loaded = try theme.loadFile(engine, engine.native_io orelse return error.NativeThemeIoUnavailable, path, null);
    defer engine.freeValue(loaded);
    const registry = try js.get(engine, module, "registeredThemes");
    defer engine.freeValue(registry);
    const ignored = try js.invoke(engine, registry, "set", &.{ watched, loaded });
    engine.freeValue(ignored);
    try js.define(engine, module, "current", c.JS_DupValue(engine.context, loaded));
    try js.define(engine, module, "resourceSignature", c.pi_js_undefined());
    try notify(engine, module);
}
fn reloadCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    reload(engine, data[0], data[1], data[2]) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        discardException(engine);
    };
    return c.pi_js_undefined();
}
fn scheduleReload(engine: *Engine, module: c.JSValue, watched: c.JSValue, file: c.JSValue) !void {
    const previous = try js.get(engine, module, "themeReloadTimer");
    defer engine.freeValue(previous);
    if (v.truthy(engine, previous)) {
        const ignored = try invokeGlobal(engine, "clearTimeout", &.{previous});
        engine.freeValue(ignored);
    }
    var data = [_]c.JSValue{ module, watched, file };
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, reloadCall, "theme reload", 0, 0, 3, &data));
    defer engine.freeValue(callback);
    const timer = try invokeGlobal(engine, "setTimeout", &.{ callback, v.numeric(engine, 100) });
    try js.define(engine, module, "themeReloadTimer", timer);
}
fn changed(engine: *Engine, module: c.JSValue, watched: c.JSValue, filename: c.JSValue, expected: c.JSValue, file: c.JSValue) !void {
    if (!try sameName(engine, module, watched)) return;
    if (v.truthy(engine, filename) and !c.JS_IsStrictEqual(engine.context, filename, expected)) return;
    try scheduleReload(engine, module, watched, file);
}
fn changedCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    changed(engine, data[0], data[1], if (argc > 1) argv[1] else c.pi_js_undefined(), data[2], data[3]) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn errorCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const watcher = js.get(engine, data[0], "themeWatcher") catch |err| return fail(engine, err);
    defer engine.freeValue(watcher);
    closeWatch(engine, watcher);
    js.define(engine, data[0], "themeWatcher", c.pi_js_undefined()) catch |err| return fail(engine, err);
    // Source leaves a previously scheduled reload active after watch errors.
    return c.pi_js_undefined();
}
fn normalizeWindowsShell(engine: *Engine, path: []const u8) ![]u8 {
    if (builtin.os.tag != .windows or path.len == 0 or path[0] != '/' or std.mem.startsWith(u8, path, "//") or std.mem.indexOfScalar(u8, path, '\\') != null) return engine.gpa.dupe(u8, path);
    var tail = path[1..];
    if (tail.len >= 4 and std.ascii.eqlIgnoreCase(tail[0..4], "mnt/")) tail = tail[4..] else if (tail.len >= 9 and std.ascii.eqlIgnoreCase(tail[0..9], "cygdrive/")) tail = tail[9..];
    if (tail.len == 0 or !std.ascii.isAlphabetic(tail[0]) or (tail.len > 1 and tail[1] != '/') or std.mem.indexOfAny(u8, tail, "\r\n") != null or std.mem.indexOf(u8, tail, "\xe2\x80\xa8") != null or std.mem.indexOf(u8, tail, "\xe2\x80\xa9") != null) return engine.gpa.dupe(u8, path);
    const suffix = if (tail.len > 1) tail[2..] else "";
    const result = try engine.gpa.alloc(u8, 3 + suffix.len);
    result[0] = std.ascii.toUpper(tail[0]);
    result[1] = ':';
    result[2] = '\\';
    for (suffix, result[3..]) |byte, *output| output.* = if (byte == '/') '\\' else byte;
    return result;
}
pub fn directory(engine: *Engine) ![]u8 {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const environment = try js.get(engine, process, "env");
    defer engine.freeValue(environment);
    const supplied = try js.get(engine, environment, "PI_CODING_AGENT_DIR");
    defer engine.freeValue(supplied);
    const flavor: paths.Flavor = if (builtin.os.tag == .windows) .win32 else .posix;
    // Source normalizePath evaluates its default home even for an absolute
    // configured directory; a home lookup error remains observable.
    const home = try @import("native_home.zig").get(engine);
    defer engine.freeValue(home);
    const home_bytes = try engine.toString(home);
    defer engine.gpa.free(home_bytes);
    if (v.truthy(engine, supplied)) {
        const input = try engine.toString(supplied);
        defer engine.gpa.free(input);
        const value = try normalizeWindowsShell(engine, input);
        defer engine.gpa.free(value);
        if (std.mem.eql(u8, value, "~") or std.mem.startsWith(u8, value, "~/") or (builtin.os.tag == .windows and std.mem.startsWith(u8, value, "~\\"))) {
            return paths.join(engine.gpa, &.{ home_bytes, if (value.len > 1) value[2..] else "", "themes" }, flavor);
        }
        if (std.mem.startsWith(u8, value, "file://")) {
            const module = try theme.moduleState(engine);
            defer engine.freeValue(module);
            const converter = try js.get(engine, module, "themeFileURLToPath");
            defer engine.freeValue(converter);
            const argument = try v.text(engine, value);
            defer engine.freeValue(argument);
            const converted = try js.call(engine, converter, c.pi_js_undefined(), &.{argument});
            defer engine.freeValue(converted);
            const bytes = try engine.toString(converted);
            defer engine.gpa.free(bytes);
            return paths.join(engine.gpa, &.{ bytes, "themes" }, flavor);
        }
        return paths.join(engine.gpa, &.{ value, "themes" }, flavor);
    }
    return paths.join(engine.gpa, &.{ home_bytes, ".pi", "agent", "themes" }, flavor);
}
pub fn start(engine: *Engine, module: c.JSValue) !void {
    try stop(engine, module);
    const name = try js.get(engine, module, "currentThemeName");
    defer engine.freeValue(name);
    if (!v.truthy(engine, name)) return;
    inline for (.{ "dark", "light", "system" }) |builtin_name| {
        const value = try v.text(engine, builtin_name);
        defer engine.freeValue(value);
        if (c.JS_IsStrictEqual(engine.context, name, value)) return;
    }
    const dir = try directory(engine);
    defer engine.gpa.free(dir);
    const suffix = try v.text(engine, ".json");
    defer engine.freeValue(suffix);
    const filename = try v.concat(engine, &.{ name, suffix });
    defer engine.freeValue(filename);
    const filename_bytes = try engine.toString(filename);
    defer engine.gpa.free(filename_bytes);
    const path = try paths.join(engine.gpa, &.{ dir, filename_bytes }, if (builtin.os.tag == .windows) .win32 else .posix);
    defer engine.gpa.free(path);
    if (!exists(engine, path)) return;
    const file = try v.text(engine, path);
    defer engine.freeValue(file);
    var event_data = [_]c.JSValue{ module, name, filename, file };
    const on_change = try engine.checked(c.JS_NewCFunctionData2(engine.context, changedCall, "theme file change", 2, 0, 4, &event_data));
    defer engine.freeValue(on_change);
    var error_data = [_]c.JSValue{module};
    const on_error = try engine.checked(c.JS_NewCFunctionData2(engine.context, errorCall, "theme watch error", 0, 0, 1, &error_data));
    defer engine.freeValue(on_error);
    const watcher = @import("native_io_watch.zig").open(engine, module, dir, on_change, on_error) catch |err| {
        if (err == error.OutOfMemory) return err;
        discardException(engine);
        return;
    };
    try js.define(engine, module, "themeWatcher", watcher);
}
fn directoryCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const path = directory(engine) catch |err| return fail(engine, err);
    defer engine.gpa.free(path);
    return v.text(engine, path) catch |err| fail(engine, err);
}
test "Source6fb Theme watcher custom directory normalization home errors shell paths and file URLs" {
    if (builtin.os.tag != .windows and builtin.os.tag != .linux) return error.SkipZigTest;
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"theme-directory"});
    try @import("native_tui.zig").install(engine);
    try engine.bindFunction("watchThemesDirectory", directoryCall, 0);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = if (builtin.os.tag == .windows) @embedFile("fixtures/theme-directory-original-win32-6fb.json") else @embedFile("fixtures/theme-directory-original-linux-6fb.json");
    try js.define(engine, global, "themeDirectoryOracle", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "theme-directory-original-6fb.json")));
    const result = engine.evalModule(
        \\for(const[index,item]of themeDirectoryOracle.cases.entries()){process.env[themeDirectoryOracle.platform==='win32'?'USERPROFILE':'HOME']=item.home;if(item.value===null)delete process.env.PI_CODING_AGENT_DIR;else process.env.PI_CODING_AGENT_DIR=item.value;let actual;try{actual=watchThemesDirectory()}catch(e){if(e.name===item.errorName&&e.code===item.errorCode)continue;throw Error(JSON.stringify({index,error:{name:e.name,code:e.code,message:e.message},expected:item}))}if(item.errorName||actual!==item.result)throw Error(JSON.stringify({index,actual,expected:item}));}
    , "theme-directory-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Theme directory: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb Theme watcher actual native events debounce reload and retain last valid file" {
    if (builtin.os.tag != .windows and builtin.os.tag != .linux and builtin.os.tag != .macos) return error.SkipZigTest;
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "themes", .default_dir);
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const root_path = path_buffer[0..path_length];
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("PI_CODING_AGENT_DIR", root_path);
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"theme-watch"});
    try @import("node_fs.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    const module = try theme.moduleState(engine);
    defer engine.freeValue(module);
    defer stop(engine, module) catch {};
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "themeWatchRoot", try v.text(engine, root_path));
    const bytes = @embedFile("../themes/fixtures/dark-original-6fb.json");
    try js.define(engine, global, "themeWatchBase", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "theme-watch-base.json")));
    const result = engine.evalModule(
        \\import fs from'node:fs';import{initTheme,theme}from'pi-coding-agent';const file=themeWatchRoot+'/themes/custom.json',write=color=>fs.writeFileSync(file,JSON.stringify({...themeWatchBase,name:'custom',colors:{...themeWatchBase.colors,accent:color}})),observe=()=>JSON.stringify([theme.colors.accent.r,theme.colors.accent.g,theme.colors.accent.b]),sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));write('#112233');initTheme('custom',true);if(observe()!=='[17,34,51]')throw Error('initial custom file '+observe());write('#010203');await sleep(300);if(observe()!=='[1,2,3]')throw Error('native reload '+observe());fs.writeFileSync(file,'{invalid');await sleep(160);if(observe()!=='[1,2,3]')throw Error('invalid replaced last valid '+observe());fs.unlinkSync(file);await sleep(160);if(observe()!=='[1,2,3]')throw Error('missing replaced last valid '+observe());
    , "theme-watch-native-events.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Theme watch events: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
