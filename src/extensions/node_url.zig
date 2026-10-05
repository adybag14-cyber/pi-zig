//! Native URL module exports and strongly branded file-URL adapters.
const std = @import("std");
const builtin = @import("builtin");
const engine_mod = @import("engine.zig");
const native_url = @import("native_url.zig");
const parser = @import("url_parser.zig");
const search_params = @import("url_search_params.zig");
const file_urls = @import("file_urls.zig");
const node_path = @import("node_path.zig");
const c = engine_mod.c;

pub fn install(engine: *engine_mod.Engine) !void {
    if (engine.url_class == 0) try native_url.install(engine);
    const object = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(object);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const uri_error = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "URIError"));
    defer engine.freeValue(uri_error);
    var data = [_]c.JSValue{uri_error};
    inline for (.{ .{ "fileURLToPath", 0 }, .{ "pathToFileURL", 1 } }) |method| {
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, invoke, method[0], 1, method[1], 1, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, object, method[0], function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    inline for (.{ "URL", "URLSearchParams" }) |name| {
        const constructor = try engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
        if (c.JS_DefinePropertyValueStr(engine.context, object, name, constructor, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    try engine.registerDefaultModule("node:url", object);
    try engine.registerDefaultModule("url", object);
}

fn failure(engine: *engine_mod.Engine, err: anyerror, uri_constructor: c.JSValue) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory or err == error.WriteFailed) return c.JS_ThrowOutOfMemory(engine.context);
    if (err == error.InvalidFileUrlEncoding) {
        var args = [_]c.JSValue{c.JS_NewString(engine.context, "URI malformed")};
        if (c.JS_IsException(args[0])) return args[0];
        defer engine.freeValue(args[0]);
        const exception = c.JS_CallConstructor(engine.context, uri_constructor, 1, &args);
        return if (c.JS_IsException(exception)) exception else c.JS_Throw(engine.context, exception);
    }
    _ = c.JS_ThrowTypeError(engine.context, "Native file URL conversion: %s", @as([*:0]const u8, @errorName(err)));
    const exception = c.JS_GetException(engine.context);
    if (!c.JS_IsError(exception)) return c.JS_Throw(engine.context, exception);
    const code: [*:0]const u8 = switch (err) {
        error.InvalidFileUrlArgument, error.InvalidPathToFileUrlArgument => "ERR_INVALID_ARG_TYPE",
        error.InvalidFileUrlScheme => "ERR_INVALID_URL_SCHEME",
        error.InvalidFileUrlHost => "ERR_INVALID_FILE_URL_HOST",
        error.InvalidFileUrlDrive, error.InvalidFileUrlSeparator, error.InvalidFileUrl, error.InvalidFileUrlPath => "ERR_INVALID_FILE_URL_PATH",
        error.InvalidFileUrlEncoding => unreachable,
        else => "ERR_INVALID_URL",
    };
    if (c.JS_DefinePropertyValueStr(engine.context, exception, "code", c.JS_NewString(engine.context, code), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(exception);
        return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
    }
    return c.JS_Throw(engine.context, exception);
}
fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return convert(engine, if (argc == 0) &.{} else argv[0..@intCast(argc)], magic == 1) catch |err| failure(engine, err, data[0]);
}
fn windowsOption(engine: *engine_mod.Engine, args: []c.JSValue) !bool {
    if (args.len < 2 or c.JS_IsNull(args[1]) or c.JS_IsUndefined(args[1])) return builtin.os.tag == .windows;
    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, args[1], "windows"));
    defer engine.freeValue(value);
    return if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) builtin.os.tag == .windows else c.JS_ToBool(engine.context, value) != 0;
}
fn currentDirectory(engine: *engine_mod.Engine) ![]u8 {
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    var directory = try std.Io.Dir.cwd().openDir(io, ".", .{});
    defer directory.close(io);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try directory.realPath(io, &buffer);
    return engine.gpa.dupe(u8, buffer[0..length]);
}
fn convert(engine: *engine_mod.Engine, args: []c.JSValue, to_url: bool) !c.JSValue {
    if (to_url and (args.len == 0 or !c.JS_IsString(args[0]))) return error.InvalidPathToFileUrlArgument;
    const windows = try windowsOption(engine, args);
    if (args.len == 0) return error.InvalidFileUrlArgument;
    if (!to_url) {
        const object = if (c.JS_IsString(args[0])) parsed: {
            const text = try search_params.usvString(engine, args[0]);
            defer engine.gpa.free(text);
            var record = try parser.parse(engine.gpa, text, null);
            var transferred = false;
            defer if (!transferred) record.deinit(engine.gpa);
            const value = try native_url.create(engine, &record, null);
            transferred = true;
            break :parsed value;
        } else if (native_url.isURL(engine, args[0])) c.JS_DupValue(engine.context, args[0]) else return error.InvalidFileUrlArgument;
        defer engine.freeValue(object);
        const path = try native_url.filePath(engine, object, windows);
        defer engine.gpa.free(path);
        return engine.checked(c.JS_NewStringLen(engine.context, path.ptr, path.len));
    }
    if (!c.JS_IsString(args[0])) return error.InvalidPathToFileUrlArgument;
    const input = try search_params.usvString(engine, args[0]);
    defer engine.gpa.free(input);
    const qualified = if (windows) (input.len >= 3 and std.ascii.isAlphabetic(input[0]) and input[1] == ':' and (input[2] == '/' or input[2] == '\\')) or std.mem.startsWith(u8, input, "\\\\") else std.mem.startsWith(u8, input, "/");
    const cwd = if (qualified) try engine.gpa.dupe(u8, "") else try currentDirectory(engine);
    defer engine.gpa.free(cwd);
    const resolved = try node_path.resolve(engine.gpa, cwd, &.{input}, if (windows) .win32 else .posix);
    defer engine.gpa.free(resolved);
    var absolute: std.ArrayList(u8) = .empty;
    defer absolute.deinit(engine.gpa);
    try absolute.appendSlice(engine.gpa, resolved);
    if (input.len > 0 and (input[input.len - 1] == '/' or (windows and input[input.len - 1] == '\\')) and absolute.items.len > 0 and absolute.items[absolute.items.len - 1] != '/' and absolute.items[absolute.items.len - 1] != '\\') try absolute.append(engine.gpa, if (windows) '\\' else '/');
    const text = if (windows and std.mem.startsWith(u8, absolute.items, "\\") and !std.mem.startsWith(u8, absolute.items, "\\\\")) rooted: {
        for (absolute.items) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
        break :rooted try file_urls.fromPathURL(engine.gpa, absolute.items, false);
    } else try file_urls.fromPathURL(engine.gpa, absolute.items, windows);
    defer engine.gpa.free(text);
    var record = try parser.parse(engine.gpa, text, null);
    var transferred = false;
    defer if (!transferred) record.deinit(engine.gpa);
    const value = try native_url.create(engine, &record, null);
    transferred = true;
    return value;
}

test "native URL module exports real URL classes and bidirectional file conversions with original exceptions" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try install(engine);
    const result = engine.evalModule(
        \\import {URL as NativeURL,URLSearchParams as NativeParams,fileURLToPath,pathToFileURL} from 'node:url';import legacy from 'url';if(NativeURL!==URL||NativeParams!==URLSearchParams||legacy.URL!==URL)throw Error('constructors');const win=pathToFileURL('C:\\a b\\🌍#%.js',{windows:true}),posix=pathToFileURL('/tmp/a b/#%.js',{windows:false});if(!(win instanceof URL)||win.href!=='file:///C:/a%20b/%F0%9F%8C%8D%23%25.js'||fileURLToPath(win,{windows:true})!=='C:\\a b\\🌍#%.js'||posix.href!=='file:///tmp/a%20b/%23%25.js'||fileURLToPath(posix,{windows:false})!=='/tmp/a b/#%.js')throw Error('paths');if(fileURLToPath(new URL('file:///tmp/a%20b.js?x#part'),{windows:false})!=='/tmp/a b.js')throw Error('suffix ignored');let rejected=0;for(const fn of [()=>fileURLToPath({href:'file:///tmp/a'}),()=>fileURLToPath(new URL('https://host/a')),()=>fileURLToPath('file:///tmp/a%2fb',{windows:false})]){try{fn()}catch(e){if(!(e instanceof TypeError))throw e;rejected++}}if(rejected!==3)throw Error('brand/errors');const reason={};for(const key of ['href','protocol','hostname','pathname']){const u=new URL('file:///tmp/a');Object.defineProperty(u,key,{get(){throw reason}});try{fileURLToPath(u,{windows:false});throw Error('missing getter error')}catch(e){if(e!==reason)throw e}}try{pathToFileURL('/tmp/a',{get windows(){throw reason}});throw Error('option accepted')}catch(e){if(e!==reason)throw e}let malformed=0;for(const input of ['file:///tmp/%ZZ','file:///tmp/%FF'])try{fileURLToPath(input,{windows:false})}catch(e){if(!(e instanceof URIError))throw e;malformed++}if(malformed!==2)throw Error('URI errors');
    , "native-node-url.mjs") catch |err| {
        std.debug.print("Node URL fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(result);
    const order = try engine.evalModule(
        \\import {fileURLToPath,pathToFileURL} from 'node:url';const reason={};for(const input of [null,new URL('https://host/a')]){try{pathToFileURL(input,{get windows(){throw reason}});throw Error('invalid path accepted')}catch(e){if(e.code!=='ERR_INVALID_ARG_TYPE')throw e}try{fileURLToPath(input,{get windows(){throw reason}});throw Error('option accepted')}catch(e){if(e!==reason)throw e}}for(const key of ['href','protocol','auth']){const u=new URL('file:///tmp/a');Object.defineProperty(u,key,{get(){return key==='auth'?null:''}});Object.defineProperty(u,'path',{get(){throw reason}});try{fileURLToPath(u);throw Error('URL aliases accepted')}catch(e){if(e.code!=='ERR_INVALID_ARG_TYPE')throw e}}
    , "native-file-url-observation-order.mjs");
    defer engine.freeValue(order);
    const punctuation = try engine.evalModule(
        \\import {fileURLToPath,pathToFileURL} from 'node:url';const path="/tmp/!$&'()*+,:;=@[]^|{}~",u=pathToFileURL(path,{windows:false});if(u.href!=="file:///tmp/!$&'()*+,:;=@%5B%5D%5E%7C%7B%7D%7E"||fileURLToPath(u,{windows:false})!==path)throw Error('Node24 path punctuation');const nul=pathToFileURL('/tmp/a\0b',{windows:false});if(nul.href!=='file:///tmp/a%00b'||fileURLToPath(nul,{windows:false})!=='/tmp/a\0b')throw Error('file URL NUL');const unc=pathToFileURL('\\\\bücher.example\\share\\a',{windows:true});if(unc.href!=='file://xn--bcher-kva.example/share/a'||fileURLToPath(unc,{windows:true})!=='\\\\bücher.example\\share\\a')throw Error('UNC Unicode');
    , "native-file-url-punctuation-unc.mjs");
    defer engine.freeValue(punctuation);
    const precedence = try engine.evalModule(
        \\import {fileURLToPath} from 'node:url';for(const [input,code]of [['file://remote/%FF','ERR_INVALID_FILE_URL_HOST'],['file:///tmp/%GG%2F','ERR_INVALID_FILE_URL_PATH']])try{fileURLToPath(input,{windows:false});throw Error('invalid URL accepted')}catch(e){if(e.code!==code)throw e}if(fileURLToPath('file://[::1]/share/a',{windows:true})!=='\\\\[::1]\\share\\a')throw Error('IPv6 UNC');
    , "native-file-url-error-precedence.mjs");
    defer engine.freeValue(precedence);
}
