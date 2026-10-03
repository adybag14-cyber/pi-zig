//! Filesystem module functions implemented in Zig for trusted extension input.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Method = enum(c_int) { readFileSync, writeFileSync, existsSync, mkdirSync, unlinkSync, accessSync };
const PromiseMethod = enum(c_int) { readFile, writeFile, mkdir, unlink, access };

pub fn install(engine: *engine_mod.Engine, io: std.Io) !void {
    engine.native_io = io;
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
    if (c.JS_DefinePropertyValueStr(engine.context, promises, "default", c.JS_DupValue(engine.context, promises), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, exports, "promises", c.JS_DupValue(engine.context, promises), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, exports, "default", c.JS_DupValue(engine.context, exports), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    try engine.registerValueModule("node:fs", exports);
    try engine.registerValueModule("fs", exports);
    try engine.registerValueModule("node:fs/promises", promises);
    try engine.registerValueModule("fs/promises", promises);
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
    const value = call(engine, method, argv[0..@intCast(argc)]) catch |err| failure: {
        failed = true;
        if (c.JS_HasException(context)) break :failure c.JS_GetException(context);
        const failure = c.JS_NewError(context);
        if (!c.JS_IsException(failure)) {
            const message = if (err == error.JavaScriptException) engine.last_error orelse @errorName(err) else @errorName(err);
            const text = c.JS_NewStringLen(context, message.ptr, message.len);
            if (c.JS_DefinePropertyValueStr(context, failure, "message", text, c.JS_PROP_C_W_E) < 0) {
                engine.freeValue(failure);
                engine.freeValue(promise);
                return c.JS_Throw(context, c.JS_GetException(context));
            }
        }
        break :failure failure;
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
    try source.writer.writeAll("; const order=[]; const writing=writeFile(path,'async-native'); if (!(writing instanceof Promise)) throw Error('not a Promise'); writing.then(()=>order.push('settled')); order.push('sync'); await writing; export const text=await readFile(path,'utf8'); await access(path); export const shared=fs.promises===fsp; await unlink(path); export let failure=''; try {await readFile(path,'utf8');} catch(error) {if (!(error instanceof Error)) throw Error('not an Error'); failure=error.message;} export const observed=order;");
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
    return call(engine, @enumFromInt(magic), argv[0..@intCast(argc)]) catch |err| c.JS_ThrowInternalError(context, "Native filesystem operation failed: %s", @as([*:0]const u8, @errorName(err)));
}

fn optionBoolean(engine: *engine_mod.Engine, options: c.JSValue, key: [*:0]const u8) !bool {
    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, options, key));
    defer engine.freeValue(value);
    return c.JS_ToBool(engine.context, value) == 1;
}

fn checkEncoding(engine: *engine_mod.Engine, value: c.JSValue) !void {
    if (c.JS_IsNull(value) or c.JS_IsUndefined(value)) return;
    if (!c.JS_IsString(value)) return error.InvalidNativeEncoding;
    const encoding = try engine.toString(value);
    defer engine.gpa.free(encoding);
    if (!std.ascii.eqlIgnoreCase(encoding, "utf8") and !std.ascii.eqlIgnoreCase(encoding, "utf-8")) return error.UnsupportedNativeTextEncoding;
}

fn writeOptions(engine: *engine_mod.Engine, args: []c.JSValue) !std.Io.Dir.CreateFileOptions {
    var options: std.Io.Dir.CreateFileOptions = .{};
    if (args.len < 3 or c.JS_IsUndefined(args[2]) or c.JS_IsNull(args[2])) return options;
    if (c.JS_IsString(args[2])) {
        try checkEncoding(engine, args[2]);
        return options;
    }
    if (!c.JS_IsObject(args[2])) return error.InvalidNativeFilesystemOptions;
    const encoding = try engine.checked(c.JS_GetPropertyStr(engine.context, args[2], "encoding"));
    defer engine.freeValue(encoding);
    try checkEncoding(engine, encoding);
    const flag = try engine.checked(c.JS_GetPropertyStr(engine.context, args[2], "flag"));
    defer engine.freeValue(flag);
    if (!c.JS_IsUndefined(flag)) {
        if (!c.JS_IsString(flag)) return error.UnsupportedNativeWriteFlag;
        const name = try engine.toString(flag);
        defer engine.gpa.free(name);
        if (std.mem.eql(u8, name, "wx")) options.exclusive = true else if (!std.mem.eql(u8, name, "w")) return error.UnsupportedNativeWriteFlag;
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
    if (args.len == 0) return error.MissingFilesystemPath;
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    const path = try engine.toString(args[0]);
    defer engine.gpa.free(path);
    switch (method) {
        .readFileSync => {
            const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, engine.gpa, .limited(64 * 1024 * 1024));
            defer engine.gpa.free(bytes);
            var text_encoding = false;
            if (args.len > 1) {
                if (c.JS_IsString(args[1])) {
                    const encoding = try engine.toString(args[1]);
                    defer engine.gpa.free(encoding);
                    if (!std.ascii.eqlIgnoreCase(encoding, "utf8") and !std.ascii.eqlIgnoreCase(encoding, "utf-8")) return error.UnsupportedNativeTextEncoding;
                    text_encoding = true;
                } else if (c.JS_IsObject(args[1])) {
                    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, args[1], "encoding"));
                    defer engine.freeValue(value);
                    if (!c.JS_IsNull(value) and !c.JS_IsUndefined(value)) {
                        const encoding = try engine.toString(value);
                        defer engine.gpa.free(encoding);
                        if (!std.ascii.eqlIgnoreCase(encoding, "utf8") and !std.ascii.eqlIgnoreCase(encoding, "utf-8")) return error.UnsupportedNativeTextEncoding;
                        text_encoding = true;
                    }
                }
            }
            if (text_encoding) return engine.checked(c.JS_NewStringLen(engine.context, bytes.ptr, bytes.len));
            const buffer = try engine.checked(c.JS_NewArrayBufferCopy(engine.context, bytes.ptr, bytes.len));
            defer engine.freeValue(buffer);
            var parameters = [_]c.JSValue{buffer};
            return engine.checked(c.JS_NewTypedArray(engine.context, parameters.len, &parameters, c.JS_TYPED_ARRAY_UINT8));
        },
        .writeFileSync => {
            if (args.len < 2) return error.MissingFilesystemData;
            const options = try writeOptions(engine, args);
            if (c.JS_IsString(args[1])) {
                const bytes = try engine.toString(args[1]);
                defer engine.gpa.free(bytes);
                const file = try std.Io.Dir.cwd().createFile(io, path, options);
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
                if (bytes == null) return error.UnsupportedNativeFilesystemData;
                if (c.JS_IsArrayBuffer(args[1])) length = backing_length;
                if (offset > backing_length or length > backing_length - offset) return error.InvalidNativeBufferRange;
                const file = try std.Io.Dir.cwd().createFile(io, path, options);
                defer file.close(io);
                try file.writePositionalAll(io, bytes[offset .. offset + length], 0);
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
    try source.writer.writeAll("; writeFileSync(path,'preserve'); export let rejected=0; for (const perform of [()=>writeFileSync(path,{}),()=>writeFileSync(path,'overwrite',{flag:'wx'}),()=>writeFileSync(path,'overwrite',{flag:'a'}),()=>writeFileSync(path,'overwrite','hex')]) {try {perform();} catch {rejected++;}} export const retained=readFileSync(path,'utf8'); writeFileSync(path,new Uint8Array([1,2,3,4]).subarray(1,3)); export const bytes=Array.from(readFileSync(path));");
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
    try std.testing.expectEqual(@as(i32, 4), rejected_count);
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
