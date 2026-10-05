//! CommonJS host behavior in Zig. The wrapper only scopes user input syntax.
const std = @import("std");
const builtin = @import("builtin");
const engine_mod = @import("engine.zig");
const file_urls = @import("file_urls.zig");
const native_url = @import("native_url.zig");
const c = engine_mod.c;

fn platformFilename(engine: *engine_mod.Engine, name: []const u8) ![:0]u8 {
    const filename = try engine.gpa.dupeZ(u8, name);
    if (builtin.os.tag == .windows and std.fs.path.isAbsolute(name)) for (filename) |*byte| {
        if (byte.* == '/') byte.* = '\\';
    };
    return filename;
}

fn property(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}

fn stringProperty(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, text: []const u8) !void {
    try property(engine, object, name, try engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len)));
}

fn cachedModule(engine: *engine_mod.Engine, filename: [:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, engine.commonjs_cache, filename.ptr));
}

fn cachedExports(engine: *engine_mod.Engine, filename: [:0]const u8) !?c.JSValue {
    const module = try cachedModule(engine, filename);
    defer engine.freeValue(module);
    if (c.JS_IsUndefined(module)) return null;
    if (!c.JS_IsObject(module)) return error.InvalidCommonJsCacheEntry;
    return try engine.checked(c.JS_GetPropertyStr(engine.context, module, "exports"));
}

fn nativeRequire(engine: *engine_mod.Engine, filename: [:0]const u8, resolve_only: bool) !c.JSValue {
    var data = [_]c.JSValue{try engine.checked(c.JS_NewStringLen(engine.context, filename.ptr, filename.len))};
    defer engine.freeValue(data[0]);
    const function = try engine.checked(c.JS_NewCFunctionData(engine.context, requireCallback, 1, @intFromBool(resolve_only), data.len, &data));
    errdefer engine.freeValue(function);
    if (!resolve_only) {
        try property(engine, function, "resolve", try nativeRequire(engine, filename, true));
        try property(engine, function, "cache", c.JS_DupValue(engine.context, engine.commonjs_cache));
        try property(engine, function, "main", c.pi_js_undefined());
    }
    return function;
}

pub fn install(engine: *engine_mod.Engine) !void {
    const module = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(module);
    try property(engine, module, "createRequire", try engine.checked(c.JS_NewCFunction(engine.context, createRequire, "createRequire", 1)));
    try engine.registerDefaultModule("node:module", module);
    try engine.registerDefaultModule("module", module);
}

fn createRequire(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return createRequireCall(engine, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        _ = c.JS_ThrowTypeError(context, "Native createRequire: %s", @as([*:0]const u8, @errorName(err)));
        const value = c.JS_GetException(context);
        if (!c.JS_IsError(value)) return c.JS_Throw(context, value);
        if (c.JS_DefinePropertyValueStr(context, value, "code", c.JS_NewString(context, "ERR_INVALID_ARG_VALUE"), c.JS_PROP_C_W_E) < 0) {
            engine.freeValue(value);
            return c.JS_Throw(context, c.JS_GetException(context));
        }
        return c.JS_Throw(context, value);
    };
}

fn createRequireCall(engine: *engine_mod.Engine, args: []c.JSValue) !c.JSValue {
    if (args.len == 0) return error.InvalidNativeRequireArgument;
    const path = if (native_url.isURL(engine, args[0])) actual_url: {
        if (!try native_url.visibleURL(engine, args[0])) return error.InvalidNativeRequireArgument;
        break :actual_url native_url.clonedFilePath(engine, args[0], builtin.os.tag == .windows) catch |err| {
            if (err == error.OutOfMemory) return err;
            if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
            return error.InvalidNativeRequireArgument;
        };
    } else string: {
        if (!c.JS_IsString(args[0])) return error.InvalidNativeRequireArgument;
        const input = try engine.toString(args[0]);
        defer engine.gpa.free(input);
        break :string if (std.ascii.startsWithIgnoreCase(input, "file:")) try file_urls.toPath(engine.gpa, input, builtin.os.tag == .windows) else try engine.gpa.dupe(u8, input);
    };
    defer engine.gpa.free(path);
    if (!std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidNativeRequireFilename;
    const flavor: std.fs.path.PathType = if (builtin.os.tag == .windows) .windows else .posix;
    const filename = if (path.len > 0 and flavor.isSep(u8, path[path.len - 1])) try std.fs.path.join(engine.gpa, &.{ path, "noop.js" }) else try engine.gpa.dupe(u8, path);
    defer engine.gpa.free(filename);
    const platform = try platformFilename(engine, filename);
    defer engine.gpa.free(platform);
    return nativeRequire(engine, platform, false);
}

fn requireCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return requireCall(engine, data[0], if (argc == 0) &.{} else argv[0..@intCast(argc)], magic != 0) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        const message = if (err == error.JavaScriptException) engine.last_error orelse @errorName(err) else @errorName(err);
        const terminated = engine.gpa.dupeZ(u8, message) catch return c.JS_ThrowOutOfMemory(context);
        defer engine.gpa.free(terminated);
        if (err == error.InvalidNativeRequireArgument) return c.JS_ThrowTypeError(context, "Native require: %s", terminated.ptr);
        return c.JS_ThrowReferenceError(context, "Native require: %s", terminated.ptr);
    };
}

fn requireCall(engine: *engine_mod.Engine, base_value: c.JSValue, args: []c.JSValue, resolve_only: bool) !c.JSValue {
    if (args.len == 0 or !c.JS_IsString(args[0])) return error.InvalidNativeRequireArgument;
    if (args.len > 1 and !c.JS_IsUndefined(args[1])) return error.UnsupportedNativeRequireOptions;
    const base = try engine.toString(base_value);
    defer engine.gpa.free(base);
    const specifier = try engine.toString(args[0]);
    defer engine.gpa.free(specifier);
    const filename = try engine.normalizeRequire(base, specifier);
    defer engine.gpa.free(filename);
    const terminated = try platformFilename(engine, filename);
    defer engine.gpa.free(terminated);
    if (resolve_only) return engine.checked(c.JS_NewStringLen(engine.context, terminated.ptr, terminated.len));
    if (try cachedExports(engine, terminated)) |value| return value;
    if (try engine.requireBuiltin(filename)) |value| return value;
    const loaded = try engine.loadModuleInput(filename);
    switch (loaded) {
        .exports => |value| return value,
        .source => |source| {
            defer engine.gpa.free(source);
            return error.NativeRequireEsmNotSupported;
        },
    }
}

fn createModule(engine: *engine_mod.Engine, filename: [:0]const u8, exports: c.JSValue) !c.JSValue {
    const module = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(module);
    const directory = std.fs.path.dirname(filename) orelse ".";
    try property(engine, module, "exports", c.JS_DupValue(engine.context, exports));
    try property(engine, module, "loaded", c.pi_js_bool(engine.context, 0));
    try property(engine, module, "parent", c.pi_js_null());
    try property(engine, module, "children", try engine.checked(c.JS_NewArray(engine.context)));
    try stringProperty(engine, module, "id", filename);
    try stringProperty(engine, module, "filename", filename);
    try stringProperty(engine, module, "path", directory);
    return module;
}

fn removeCached(engine: *engine_mod.Engine, filename: [:0]const u8) void {
    const atom = c.JS_NewAtom(engine.context, filename.ptr);
    defer c.JS_FreeAtom(engine.context, atom);
    _ = c.JS_DeleteProperty(engine.context, engine.commonjs_cache, atom, 0);
}

pub fn load(engine: *engine_mod.Engine, input: []const u8, name: []const u8, json: bool) !c.JSValue {
    if (std.mem.indexOfScalar(u8, name, 0) != null) return error.InvalidNativeModuleName;
    const filename = try platformFilename(engine, name);
    defer engine.gpa.free(filename);
    if (try cachedExports(engine, filename)) |exports| return exports;
    var source = input;
    if (std.mem.startsWith(u8, source, "\xef\xbb\xbf")) source = source[3..];
    if (json) {
        const terminated = try engine.gpa.dupeZ(u8, source);
        defer engine.gpa.free(terminated);
        const exports = try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, source.len, filename.ptr));
        errdefer engine.freeValue(exports);
        const module = try createModule(engine, filename, exports);
        defer engine.freeValue(module);
        try property(engine, module, "loaded", c.pi_js_bool(engine.context, 1));
        if (c.JS_SetPropertyStr(engine.context, engine.commonjs_cache, filename.ptr, c.JS_DupValue(engine.context, module)) < 0) return error.JavaScriptException;
        return exports;
    }
    if (std.mem.startsWith(u8, source, "#!")) source = if (std.mem.indexOfScalar(u8, source, '\n')) |end| source[end..] else "";
    const exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(exports);
    const module = try createModule(engine, filename, exports);
    defer engine.freeValue(module);
    const require = try nativeRequire(engine, filename, false);
    defer engine.freeValue(require);
    try property(engine, module, "require", c.JS_DupValue(engine.context, require));
    if (c.JS_SetPropertyStr(engine.context, engine.commonjs_cache, filename.ptr, c.JS_DupValue(engine.context, module)) < 0) return error.JavaScriptException;
    errdefer removeCached(engine, filename);
    // Only the grammar needed to scope user-authored CommonJS input is added.
    // Resolution, cache ownership, modules and invocation are native Zig.
    const wrapper = try std.fmt.allocPrint(engine.gpa, "(function(exports, require, module, __filename, __dirname) {{\n{s}\n}})", .{source});
    defer engine.gpa.free(wrapper);
    const function = try engine.eval(wrapper, filename, c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(function);
    const path = try engine.checked(c.JS_NewStringLen(engine.context, filename.ptr, filename.len));
    defer engine.freeValue(path);
    const directory = std.fs.path.dirname(filename) orelse ".";
    const dirname = try engine.checked(c.JS_NewStringLen(engine.context, directory.ptr, directory.len));
    defer engine.freeValue(dirname);
    var arguments = [_]c.JSValue{ exports, require, module, path, dirname };
    const result = try engine.checked(c.JS_Call(engine.context, function, exports, arguments.len, &arguments));
    defer engine.freeValue(result);
    try property(engine, module, "loaded", c.pi_js_bool(engine.context, 1));
    return engine.checked(c.JS_GetPropertyStr(engine.context, module, "exports"));
}

test "native CommonJS scopes exports caches JSON and rolls back failed evaluation" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const first = try load(engine, "globalThis.commonjsLoads=(globalThis.commonjsLoads||0)+1; exports.value=41; module.exports.value++; module.exports.self=this===exports;", "native-commonjs.cjs", false);
    defer engine.freeValue(first);
    const cached = try load(engine, "throw Error('must not reload');", "native-commonjs.cjs", false);
    defer engine.freeValue(cached);
    const json = try engine.stringify(cached);
    defer engine.gpa.free(json);
    try std.testing.expectEqualStrings("{\"value\":42,\"self\":true}", json);
    try std.testing.expectError(error.JavaScriptException, load(engine, "exports.partial=true; throw Error('owned failure');", "native-failing.cjs", false));
    const recovered = try load(engine, "module.exports='recovered';", "native-failing.cjs", false);
    defer engine.freeValue(recovered);
    const recovered_text = try engine.toString(recovered);
    defer engine.gpa.free(recovered_text);
    try std.testing.expectEqualStrings("recovered", recovered_text);
    const parsed = try load(engine, "\xef\xbb\xbf{\"native\":true}", "native-json.json", true);
    defer engine.freeValue(parsed);
    const json_cached = try load(engine, "invalid JSON", "native-json.json", true);
    defer engine.freeValue(json_cached);
    const encoded = try engine.stringify(json_cached);
    defer engine.gpa.free(encoded);
    try std.testing.expectEqualStrings("{\"native\":true}", encoded);
}

test "native createRequire accepts absolute file locations and rejects ambiguous inputs" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const source = "import module,{createRequire} from 'node:module'; import legacy from 'module'; if(module!==legacy)throw Error('identity');" ++
        "const require=createRequire(" ++ (if (builtin.os.tag == .windows) "'file:///C:/native/input.mjs'" else "'file:///native/input.mjs'") ++ ");" ++
        "if(typeof require!=='function'||require.resolve('node:module')!=='node:module'||require('module')!==module)throw Error('require');" ++
        "let rejected=0;for(const value of [undefined,null,'relative.mjs','https://example.com/module']){try{createRequire(value);}catch(error){if(!(error instanceof TypeError))throw error;rejected++;}}if(rejected!==4)throw Error('input validation');";
    const namespace = engine.evalModule(source, "native-create-require.mjs") catch |err| {
        std.debug.print("Native createRequire fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(namespace);
}

test "native createRequire accepts branded actual file URL and reads a real JSON module" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(io, .{ .sub_path = "data.json", .data = "{\"marker\":\"native-file\",\"value\":42}" });
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = io;
    try @import("node_url.zig").install(engine);
    try install(engine);
    const loader = struct {
        fn loadFile(_: ?*anyopaque, gpa: std.mem.Allocator, path: []const u8) ![]u8 {
            return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, gpa, .limited(1024 * 1024));
        }
        fn normalize(_: ?*anyopaque, gpa: std.mem.Allocator, base: []const u8, name: []const u8) ![]u8 {
            if (std.mem.startsWith(u8, name, "node:")) return gpa.dupe(u8, name);
            const joined = try std.fs.path.join(gpa, &.{ std.fs.path.dirname(base) orelse ".", name });
            defer gpa.free(joined);
            return @import("node_path.zig").normalize(gpa, joined, if (builtin.os.tag == .windows) .win32 else .posix);
        }
        fn input(_: ?*anyopaque, host: *engine_mod.Engine, path: []const u8) !engine_mod.ModuleInput {
            const bytes = try loadFile(null, host.gpa, path);
            defer host.gpa.free(bytes);
            return .{ .exports = try load(host, bytes, path, std.mem.endsWith(u8, path, ".json")) };
        }
    };
    engine.setSourceLoader(.{ .load = loader.loadFile, .normalize_require = loader.normalize, .input = loader.input });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(io, &path_buffer);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "fixturePath", c.JS_NewStringLen(engine.context, &path_buffer, length)) < 0) return error.JavaScriptException;
    const value = engine.evalModule(
        \\import {createRequire} from 'node:module';import {pathToFileURL} from 'node:url';const file=pathToFileURL(fixturePath+'/module.mjs'),require=createRequire(file),record=require('./data.json');if(record.marker!=='native-file'||record.value!==42||require('./data.json')!==record)throw Error('real module');const reason={};for(const key of ['href','protocol','auth','path']){const changed=new URL(file);Object.defineProperty(changed,key,{get(){throw reason}});try{createRequire(changed);throw Error('getter accepted')}catch(e){if(e!==reason)throw e}}for(const key of ['hostname','pathname']){const changed=new URL(file);Object.defineProperty(changed,key,{get(){throw reason}});if(createRequire(changed)('./data.json')!==record)throw Error('clone did not ignore public path fields')}for(const input of [{href:file.href},new URL('https://host/a'),new URL('file:///C:/%GG')])try{createRequire(input);throw Error('invalid accepted')}catch(e){if(e.code!=='ERR_INVALID_ARG_VALUE')throw e}const changed=new URL(file);Object.defineProperty(changed,'toString',{get(){throw reason}});try{createRequire(changed);throw Error('clone getter accepted')}catch(e){if(e.code!=='ERR_INVALID_ARG_VALUE')throw e}
    , "native-create-require-url.mjs") catch |err| {
        std.debug.print("createRequire URL fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(value);
}
