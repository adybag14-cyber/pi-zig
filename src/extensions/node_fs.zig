//! Filesystem module functions implemented in Zig for trusted extension input.
const std = @import("std");
const builtin = @import("builtin");
const engine_mod = @import("engine.zig");
const node_buffer = @import("node_buffer.zig");
const node_directory = @import("node_directory.zig");
const native_url = @import("native_url.zig");
const c = engine_mod.c;
const Method = enum(c_int) { readFileSync, writeFileSync, existsSync, mkdirSync, unlinkSync, accessSync };
const PromiseMethod = enum(c_int) { readFile, writeFile, mkdir, unlink, access };

pub fn install(engine: *engine_mod.Engine, io: std.Io) !void {
    engine.native_io = io;
    try node_buffer.install(engine);
    const exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(exports);
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const function = try engine.checked(c.pi_js_function_magic(engine.context, invoke, name.ptr, 2, @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, exports, name.ptr, function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    const promises = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(promises);
    inline for (std.meta.fields(PromiseMethod)) |field| {
        const name: [:0]const u8 = field.name;
        const function = try engine.checked(c.pi_js_function_magic(engine.context, invokePromise, name.ptr, 2, @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, promises, name.ptr, function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    if (c.JS_DefinePropertyValueStr(engine.context, exports, "promises", c.JS_DupValue(engine.context, promises), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    try node_directory.install(engine, exports, promises);
    try engine.registerDefaultModule("node:fs", exports);
    try engine.registerDefaultModule("fs", exports);
    try engine.registerDefaultModule("node:fs/promises", promises);
    try engine.registerDefaultModule("fs/promises", promises);
}

fn invokePromise(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var resolvers: [2]c.JSValue = undefined;
    const promise = c.JS_NewPromiseCapability(context, &resolvers);
    if (c.JS_IsException(promise)) return promise;
    defer engine.freeValue(resolvers[0]);
    defer engine.freeValue(resolvers[1]);
    const method: Method = switch (@as(PromiseMethod, @enumFromInt(magic))) {
        .readFile => .readFileSync,
        .writeFile => .writeFileSync,
        .mkdir => .mkdirSync,
        .unlink => .unlinkSync,
        .access => .accessSync,
    };
    var failed = false;
    const args: []c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
    var snapshot: ?c.JSValue = null;
    defer if (snapshot) |value| engine.freeValue(value);
    const value = callCaptured(engine, method, args, &snapshot) catch |err| failure: {
        failed = true;
        if (c.JS_HasException(context)) break :failure c.JS_GetException(context);
        if (err == error.JavaScriptException) {
            if (engine.captured_exception) |exception| break :failure c.JS_DupValue(context, exception);
        }
        var error_args = [_]c.JSValue{snapshot orelse c.pi_js_undefined()};
        break :failure filesystemError(engine, err, method, if (snapshot != null) &error_args else args);
    };
    defer engine.freeValue(value);
    if (c.JS_IsException(value)) {
        engine.freeValue(promise);
        return value;
    }
    var arguments = [_]c.JSValue{value};
    const settled = c.JS_Call(context, resolvers[@intFromBool(failed)], c.pi_js_undefined(), arguments.len, &arguments);
    if (c.JS_IsException(settled)) {
        engine.freeValue(promise);
        return settled;
    }
    engine.freeValue(settled);
    return promise;
}

test "native filesystem promises settle asynchronous reads writes access and failures" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    const path = try std.fs.path.join(std.testing.allocator, &.{ buffer[0..length], "promises.txt" });
    defer std.testing.allocator.free(path);
    var source: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer source.deinit();
    try source.writer.writeAll("import fs from 'node:fs'; import fsp, {writeFile,readFile,access,unlink} from 'node:fs/promises'; const path=");
    try std.json.Stringify.value(path, .{}, &source.writer);
    try source.writer.writeAll("; const order=[]; const writing=writeFile(path,'async-native'); if (!(writing instanceof Promise)) throw Error('not a Promise'); writing.then(()=>order.push('settled')); order.push('sync'); await writing; export const text=await readFile(path,'utf8'); await access(path); export const shared=fs.promises===fsp; if (JSON.stringify(fs)!=='{\"promises\":{}}' || 'default' in fsp) throw Error('cyclic builtin default'); await unlink(path); export let failure=''; try {await readFile(path,'utf8');} catch(error) {if (!(error instanceof Error)) throw Error('not an Error'); failure=error.message;} export const observed=order;");
    const namespace = engine.evalModule(source.written(), "native-fs-promises.js") catch |err| {
        std.debug.print("Native filesystem promise fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(namespace);
    const text = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "text"));
    defer engine.freeValue(text);
    const decoded = try engine.toString(text);
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings("async-native", decoded);
    const shared = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "shared"));
    defer engine.freeValue(shared);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, shared));
    const failure = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "failure"));
    defer engine.freeValue(failure);
    const message = try engine.toString(failure);
    defer std.testing.allocator.free(message);
    try std.testing.expect(message.len > 0);
    const observed = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "observed"));
    defer engine.freeValue(observed);
    const order = try engine.stringify(observed);
    defer std.testing.allocator.free(order);
    try std.testing.expectEqualStrings("[\"sync\",\"settled\"]", order);
}

fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const args: []c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
    var snapshot: ?c.JSValue = null;
    defer if (snapshot) |value| engine.freeValue(value);
    return callCaptured(engine, @enumFromInt(magic), args, &snapshot) catch |err| {
        if (@as(Method, @enumFromInt(magic)) == .existsSync and err != error.OutOfMemory) {
            // Node's existence probe suppresses path validation and getter
            // exceptions. Allocation failure remains a native exception.
            if (c.JS_HasException(context)) engine.freeValue(c.JS_GetException(context));
            return c.pi_js_bool(context, 0);
        }
        if (err == error.JavaScriptException) return engine.throwCaptured();
        var error_args = [_]c.JSValue{snapshot orelse c.pi_js_undefined()};
        const failure = filesystemError(engine, err, @enumFromInt(magic), if (snapshot != null) &error_args else args);
        if (c.JS_IsException(failure)) return failure;
        return c.JS_Throw(context, failure);
    };
}

fn filesystemCode(err: anyerror) ?[:0]const u8 {
    return switch (err) {
        error.FileNotFound => "ENOENT",
        error.AccessDenied => "EACCES",
        error.PermissionDenied => "EPERM",
        error.PathAlreadyExists => "EEXIST",
        error.NotDir => "ENOTDIR",
        error.IsDir => "EISDIR",
        error.DirNotEmpty => "ENOTEMPTY",
        error.NoSpaceLeft => "ENOSPC",
        error.NameTooLong => "ENAMETOOLONG",
        error.SymLinkLoop => "ELOOP",
        error.ProcessFdQuotaExceeded => "EMFILE",
        error.SystemFdQuotaExceeded => "ENFILE",
        error.FileTooBig => "EFBIG",
        error.ReadOnlyFileSystem => "EROFS",
        error.FileBusy => "EBUSY",
        else => null,
    };
}

fn filesystemError(engine: *engine_mod.Engine, err: anyerror, method: Method, args: []c.JSValue) c.JSValue {
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    if (native_url.isFilePathError(err)) return native_url.filePathErrorValue(engine, err);
    const failure = c.JS_NewError(engine.context);
    if (c.JS_IsException(failure)) return failure;
    const message = c.JS_NewString(engine.context, @as([*:0]const u8, @errorName(err)));
    if (c.JS_DefinePropertyValueStr(engine.context, failure, "message", message, c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(failure);
        return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
    }
    if (filesystemCode(err)) |code| {
        const syscall: [:0]const u8 = switch (method) {
            .readFileSync => if (err == error.IsDir or err == error.InputOutput) "read" else "open",
            .writeFileSync => if (err == error.NoSpaceLeft or err == error.FileTooBig or err == error.InputOutput) "write" else "open",
            .mkdirSync => "mkdir",
            .unlinkSync => "unlink",
            .accessSync => "access",
            .existsSync => "stat",
        };
        const fields = [_]struct { key: [*:0]const u8, text: [:0]const u8 }{
            .{ .key = "code", .text = code },
            .{ .key = "syscall", .text = syscall },
        };
        for (fields) |field| {
            if (c.JS_DefinePropertyValueStr(engine.context, failure, field.key, c.JS_NewString(engine.context, field.text.ptr), c.JS_PROP_C_W_E) < 0) {
                engine.freeValue(failure);
                return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
            }
        }
        // The validated path remains an input value. Never invoke user coercion
        // again while constructing an operation's error.
        if (args.len != 0 and c.JS_IsString(args[0])) {
            if (c.JS_DefinePropertyValueStr(engine.context, failure, "path", c.JS_DupValue(engine.context, args[0]), c.JS_PROP_C_W_E) < 0) {
                engine.freeValue(failure);
                return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
            }
        }
    }
    return failure;
}

test "native filesystem missing paths expose Node error codes and syscall fields in sync and promise APIs" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &path_buffer);
    const path = try std.fs.path.join(std.testing.allocator, &.{ path_buffer[0..length], "missing-parent", "missing-file" });
    defer std.testing.allocator.free(path);
    var source: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer source.deinit();
    try source.writer.writeAll("import fs from 'node:fs';const path=");
    try std.json.Stringify.value(path, .{}, &source.writer);
    try source.writer.writeAll(
        ";let checks=0;for(const [sync,async,syscall,args]of [['readFileSync','readFile','open',[]],['writeFileSync','writeFile','open',['data']],['mkdirSync','mkdir','mkdir',[]],['unlinkSync','unlink','unlink',[]],['accessSync','access','access',[]]]){" ++
            "for(const call of [()=>fs[sync](path,...args),()=>fs.promises[async](path,...args)]){let caught=false;try{await call()}catch(error){caught=true;if(!(error instanceof Error)||error.name!=='Error'||error.code!=='ENOENT'||error.path!==path||error.syscall!==syscall)throw error;checks++}if(!caught)throw Error('missing path accepted')}}" ++
            "if(checks!==10||fs.existsSync(path)!==false)throw Error('filesystem error checks');export const result=checks;",
    );
    const namespace = engine.evalModule(source.written(), "native-fs-error-fields.mjs") catch |err| {
        std.debug.print("Native filesystem error fields: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(namespace);
}

test "native filesystem error construction preserves native memory failures" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const failure = filesystemError(engine, error.OutOfMemory, .readFileSync, &.{});
    try std.testing.expect(c.JS_IsException(failure));
    const exception = c.JS_GetException(engine.context);
    defer engine.freeValue(exception);
    const name = try engine.checked(c.JS_GetPropertyStr(engine.context, exception, "name"));
    defer engine.freeValue(name);
    const text = try engine.toString(name);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("InternalError", text);
}

test "native filesystem and readdir accept actual URL objects real paths errors and original getters" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "sub");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "sub/entry.txt", .data = "native" });
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("node_url.zig").install(engine);
    try install(engine, std.testing.io);
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "fixturePath", c.JS_NewStringLen(engine.context, &path_buffer, length)) < 0) return error.JavaScriptException;
    const value = engine.evalModule(
        \\import fs from 'node:fs';import fsp from 'node:fs/promises';import {pathToFileURL,fileURLToPath} from 'node:url';const directory=pathToFileURL(fixturePath),file=pathToFileURL(fixturePath+'/sub/entry.txt');if(fs.readFileSync(file,'utf8')!=='native'||await fsp.readFile(file,'utf8')!=='native')throw Error('read URL');fs.writeFileSync(file,'updated');if(await fsp.readFile(file,'utf8')!=='updated'||!fs.existsSync(file))throw Error('write URL');await fsp.access(file);const sync=fs.readdirSync(directory,{recursive:true}),async=await fsp.readdir(directory,{recursive:true});if(sync.map(x=>x.replaceAll('\\','/')).join(',')!=='sub,sub/entry.txt'||async.map(x=>x.replaceAll('\\','/')).join(',')!=='sub,sub/entry.txt')throw Error('recursive URL');for(const entry of fs.readdirSync(directory,{withFileTypes:true})){if(entry.parentPath!==fileURLToPath(directory))throw Error('parent URL')}const missing=pathToFileURL(fixturePath+'/missing');for(const call of [()=>fs.readFileSync(missing),()=>fsp.readFile(missing),()=>fs.readdirSync(missing),()=>fsp.readdir(missing)]){try{await call();throw Error('missing accepted')}catch(e){if(e.code!=='ENOENT'||e.path!==fileURLToPath(missing))throw e}}const reason={};for(const call of [u=>fs.readFileSync(u),u=>fsp.readFile(u),u=>fs.readdirSync(u),u=>fsp.readdir(u)]){const u=new URL(file);Object.defineProperty(u,'pathname',{get(){throw reason}});try{await call(u);throw Error('getter accepted')}catch(e){if(e!==reason)throw e}}for(const call of [u=>fs.readFileSync(u),u=>fsp.readFile(u),u=>fs.readdirSync(u),u=>fsp.readdir(u)])try{await call(new URL('file:///tmp/%FF'));throw Error('URI accepted')}catch(e){if(!(e instanceof URIError))throw e}for(const call of [()=>fs.accessSync(new URL('https://host/a')),()=>fsp.access(new URL('https://host/a'))])try{await call();throw Error('scheme accepted')}catch(e){if(e.code!=='ERR_INVALID_URL_SCHEME')throw e}await fsp.unlink(file);
    , "native-url-filesystem.mjs") catch |err| {
        std.debug.print("URL filesystem fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(value);
    const exists_value = try engine.evalModule(
        \\import fs from 'node:fs';const reason={},u=new URL('file:///missing');Object.defineProperty(u,'pathname',{get(){throw reason}});if(fs.existsSync(u)!==false||fs.existsSync(new URL('https://host/a'))!==false||fs.existsSync()!==false)throw Error('Node24 existence validation suppression');
    , "native-url-exists-validation.mjs");
    defer engine.freeValue(exists_value);
}

fn optionBoolean(engine: *engine_mod.Engine, options: c.JSValue, key: [*:0]const u8) !bool {
    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, options, key));
    defer engine.freeValue(value);
    return c.JS_ToBool(engine.context, value) == 1;
}

fn parseEncoding(engine: *engine_mod.Engine, value: c.JSValue) !node_buffer.encodings.Encoding {
    if (c.JS_IsNull(value) or c.JS_IsUndefined(value)) return .utf8;
    if (!c.JS_IsString(value)) return error.InvalidNativeEncoding;
    const encoding = try engine.toString(value);
    defer engine.gpa.free(encoding);
    return node_buffer.encodings.parse(encoding) orelse error.UnsupportedNativeTextEncoding;
}

const WriteOptions = struct { file: std.Io.Dir.CreateFileOptions = .{}, encoding: node_buffer.encodings.Encoding = .utf8 };

fn writeOptions(engine: *engine_mod.Engine, args: []c.JSValue) !WriteOptions {
    var options: WriteOptions = .{};
    if (args.len < 3 or c.JS_IsUndefined(args[2]) or c.JS_IsNull(args[2])) return options;
    if (c.JS_IsString(args[2])) {
        options.encoding = try parseEncoding(engine, args[2]);
        return options;
    }
    if (!c.JS_IsObject(args[2])) return error.InvalidNativeFilesystemOptions;
    const encoding = try engine.checked(c.JS_GetPropertyStr(engine.context, args[2], "encoding"));
    defer engine.freeValue(encoding);
    options.encoding = try parseEncoding(engine, encoding);
    const flag = try engine.checked(c.JS_GetPropertyStr(engine.context, args[2], "flag"));
    defer engine.freeValue(flag);
    if (!c.JS_IsUndefined(flag)) {
        if (!c.JS_IsString(flag)) return error.UnsupportedNativeWriteFlag;
        const name = try engine.toString(flag);
        defer engine.gpa.free(name);
        if (std.mem.eql(u8, name, "wx")) options.file.exclusive = true else if (!std.mem.eql(u8, name, "w")) return error.UnsupportedNativeWriteFlag;
    }
    const mode = try engine.checked(c.JS_GetPropertyStr(engine.context, args[2], "mode"));
    defer engine.freeValue(mode);
    if (!c.JS_IsUndefined(mode)) return error.UnsupportedNativeFileMode;
    const signal = try engine.checked(c.JS_GetPropertyStr(engine.context, args[2], "signal"));
    defer engine.freeValue(signal);
    if (!c.JS_IsUndefined(signal)) return error.UnsupportedNativeFilesystemSignal;
    return options;
}

fn call(engine: *engine_mod.Engine, method: Method, args: []c.JSValue) !c.JSValue {
    var snapshot: ?c.JSValue = null;
    defer if (snapshot) |value| engine.freeValue(value);
    return callCaptured(engine, method, args, &snapshot);
}
fn callCaptured(engine: *engine_mod.Engine, method: Method, args: []c.JSValue, snapshot: *?c.JSValue) !c.JSValue {
    if (args.len == 0) return error.MissingFilesystemPath;
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    const path = if (native_url.isURL(engine, args[0])) try native_url.filePath(engine, args[0], builtin.os.tag == .windows) else try engine.toString(args[0]);
    defer engine.gpa.free(path);
    if (native_url.isURL(engine, args[0])) snapshot.* = try engine.checked(c.JS_NewStringLen(engine.context, path.ptr, path.len));
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidNativeFilesystemPath;
    switch (method) {
        .readFileSync => {
            var text_encoding: ?node_buffer.encodings.Encoding = null;
            if (args.len > 1) {
                if (c.JS_IsString(args[1])) {
                    text_encoding = try parseEncoding(engine, args[1]);
                } else if (c.JS_IsObject(args[1])) {
                    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, args[1], "encoding"));
                    defer engine.freeValue(value);
                    if (!c.JS_IsNull(value) and !c.JS_IsUndefined(value)) {
                        text_encoding = try parseEncoding(engine, value);
                    }
                }
            }
            const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, engine.gpa, .limited(64 * 1024 * 1024));
            defer engine.gpa.free(bytes);
            if (text_encoding) |codec| {
                const text = try node_buffer.encodings.decode(engine.gpa, bytes, codec);
                defer engine.gpa.free(text);
                return engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
            }
            return node_buffer.fromBytes(engine, bytes);
        },
        .writeFileSync => {
            if (args.len < 2) return error.MissingFilesystemData;
            const options = try writeOptions(engine, args);
            if (c.JS_IsString(args[1])) {
                const text = try engine.toString(args[1]);
                defer engine.gpa.free(text);
                const bytes = try node_buffer.encodings.encode(engine.gpa, text, options.encoding);
                defer engine.gpa.free(bytes);
                const file = try std.Io.Dir.cwd().createFile(io, path, options.file);
                defer file.close(io);
                try file.writePositionalAll(io, bytes, 0);
            } else {
                var backing_length: usize = 0;
                var offset: usize = 0;
                var length: usize = 0;
                var element_bytes: usize = 0;
                const backing = if (c.JS_IsArrayBuffer(args[1])) c.JS_DupValue(engine.context, args[1]) else try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, args[1], &offset, &length, &element_bytes));
                defer engine.freeValue(backing);
                const bytes = c.JS_GetArrayBuffer(engine.context, &backing_length, backing);
                if (bytes == null and (backing_length != 0 or c.JS_HasException(engine.context))) return error.UnsupportedNativeFilesystemData;
                if (c.JS_IsArrayBuffer(args[1])) length = backing_length;
                if (offset > backing_length or length > backing_length - offset) return error.InvalidNativeBufferRange;
                const file = try std.Io.Dir.cwd().createFile(io, path, options.file);
                defer file.close(io);
                const content: []const u8 = if (length == 0) &.{} else bytes[offset .. offset + length];
                try file.writePositionalAll(io, content, 0);
            }
            return c.pi_js_undefined();
        },
        .existsSync => {
            std.Io.Dir.cwd().access(io, path, .{}) catch return c.pi_js_bool(engine.context, 0);
            return c.pi_js_bool(engine.context, 1);
        },
        .accessSync => {
            var mode: i32 = 0;
            if (args.len > 1 and !c.JS_IsUndefined(args[1])) {
                if (c.JS_ToInt32(engine.context, &mode, args[1]) < 0) return error.JavaScriptException;
                if (mode < 0 or mode > 7) return error.InvalidNativeAccessMode;
            }
            try std.Io.Dir.cwd().access(io, path, .{ .read = mode & 4 != 0, .write = mode & 2 != 0, .execute = mode & 1 != 0 });
            return c.pi_js_undefined();
        },
        .mkdirSync => {
            const recursive = args.len > 1 and c.JS_IsObject(args[1]) and try optionBoolean(engine, args[1], "recursive");
            if (recursive) try std.Io.Dir.cwd().createDirPath(io, path) else try std.Io.Dir.cwd().createDir(io, path, .default_dir);
            return c.pi_js_undefined();
        },
        .unlinkSync => {
            try std.Io.Dir.cwd().deleteFile(io, path);
            return c.pi_js_undefined();
        },
    }
}

test "native filesystem preserves existing content on invalid writes and supports typed array views" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    const path = try std.fs.path.join(std.testing.allocator, &.{ buffer[0..length], "preserved.txt" });
    defer std.testing.allocator.free(path);
    var source: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer source.deinit();
    try source.writer.writeAll("import {writeFileSync,readFileSync} from 'node:fs'; const path=");
    try std.json.Stringify.value(path, .{}, &source.writer);
    try source.writer.writeAll("; writeFileSync(path,'preserve'); export let rejected=0; for (const perform of [()=>writeFileSync(path,{}),()=>writeFileSync(path,'overwrite',{flag:'wx'}),()=>writeFileSync(path,'overwrite',{flag:'a'}),()=>writeFileSync(path,'overwrite','unsupported-encoding'),()=>writeFileSync(path+'\\0suffix','overwrite')]) {try {perform();} catch {rejected++;}} export const retained=readFileSync(path,'utf8'); writeFileSync(path,new Uint8Array([1,2,3,4]).subarray(1,3)); export const bytes=Array.from(readFileSync(path)); writeFileSync(path,new ArrayBuffer(0)); if(readFileSync(path).length!==0) throw Error('empty ArrayBuffer'); writeFileSync(path,new Uint8Array(0)); if(readFileSync(path).length!==0) throw Error('empty typed array');");
    const namespace = try engine.evalModule(source.written(), "filesystem-views.js");
    defer engine.freeValue(namespace);
    const retained = c.JS_GetPropertyStr(engine.context, namespace, "retained");
    defer engine.freeValue(retained);
    const text = try engine.toString(retained);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("preserve", text);
    const rejected = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "rejected"));
    defer engine.freeValue(rejected);
    var rejected_count: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &rejected_count, rejected));
    try std.testing.expectEqual(@as(i32, 5), rejected_count);
    const bytes = c.JS_GetPropertyStr(engine.context, namespace, "bytes");
    defer engine.freeValue(bytes);
    const encoded = try engine.stringify(bytes);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("[2,3]", encoded);
}

test "trusted extension reads and writes through Zig filesystem bindings" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    const path = try std.fs.path.join(std.testing.allocator, &.{ buffer[0..length], "extension-output.txt" });
    defer std.testing.allocator.free(path);
    var source: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer source.deinit();
    try source.writer.writeAll("import {writeFileSync,readFileSync,existsSync,unlinkSync} from 'node:fs'; const path=");
    try std.json.Stringify.value(path, .{}, &source.writer);
    try source.writer.writeAll("; writeFileSync(path,'hello 🌍'); export const text=readFileSync(path,'utf8'); export const existed=existsSync(path); unlinkSync(path); export const removed=!existsSync(path);");
    const namespace = try engine.evalModule(source.written(), "native-filesystem.js");
    defer engine.freeValue(namespace);
    const value = c.JS_GetPropertyStr(engine.context, namespace, "text");
    defer engine.freeValue(value);
    const text = try engine.toString(value);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("hello 🌍", text);
    const removed = c.JS_GetPropertyStr(engine.context, namespace, "removed");
    defer engine.freeValue(removed);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, removed));
}

test "native filesystem Buffer values preserve binary encodings promises and original getter failures" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const size = try tmp.dir.realPath(std.testing.io, &buffer);
    const path = try std.fs.path.join(engine.gpa, &.{ buffer[0..size], "binary-file" });
    defer engine.gpa.free(path);
    var source: std.Io.Writer.Allocating = .init(engine.gpa);
    defer source.deinit();
    try source.writer.writeAll("import fs from 'node:fs'; import fsp from 'node:fs/promises'; import {Buffer} from 'node:buffer'; const path=");
    try std.json.Stringify.value(path, .{}, &source.writer);
    try source.writer.writeAll(
        "; fs.writeFileSync(path,'68656c6c6f','hex'); const binary=fs.readFileSync(path); if(!Buffer.isBuffer(binary)||binary.toString()!=='hello'||fs.readFileSync(path,'base64')!=='aGVsbG8=')throw Error('binary read');" ++
            "const asyncBinary=await fsp.readFile(path);if(!Buffer.isBuffer(asyncBinary)||!asyncBinary.equals(binary))throw Error('promise binary read');" ++
            "let reads=0;fs.writeFileSync(path,'é',{get encoding(){reads++;return 'latin1';}});if(reads!==1||fs.readFileSync(path).toString('hex')!=='e9'||fs.readFileSync(path,'latin1')!=='é')throw Error('single option snapshot');" ++
            "fs.writeFileSync(path,new Uint8Array([239,187]));if(fs.readFileSync(path,'utf8')!=='�')throw Error('invalid UTF8');" ++
            "fs.writeFileSync(path,'retained');const original=new RangeError('options getter');const bad={get encoding(){throw original;}};let failures=0;try{fs.writeFileSync(path,'changed',bad);}catch(error){if(error!==original)throw Error('sync getter exception replaced');failures++;}try{await fsp.writeFile(path,'changed',bad);}catch(error){if(error!==original)throw Error('promise getter exception replaced');failures++;}if(failures!==2||fs.readFileSync(path,'utf8')!=='retained')throw Error('preserved file');",
    );
    const namespace = engine.evalModule(source.written(), "native-binary-filesystem.mjs") catch |err| {
        std.debug.print("Native binary filesystem fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(namespace);
}
