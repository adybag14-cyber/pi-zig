//! Filesystem module functions implemented in Zig for trusted extension input.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Method = enum(c_int) { readFileSync, writeFileSync, existsSync, mkdirSync, unlinkSync };

pub fn install(engine: *engine_mod.Engine, io: std.Io) !void {
    engine.native_io = io;
    const exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(exports);
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const function = try engine.checked(c.pi_js_function_magic(engine.context, invoke, name.ptr, 2, @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, exports, name.ptr, function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    if (c.JS_DefinePropertyValueStr(engine.context, exports, "default", c.JS_DupValue(engine.context, exports), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    try engine.registerValueModule("node:fs", exports);
    try engine.registerValueModule("fs", exports);
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
            if (c.JS_IsString(args[1])) {
                const bytes = try engine.toString(args[1]);
                defer engine.gpa.free(bytes);
                const file = try std.Io.Dir.cwd().createFile(io, path, .{});
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
                const file = try std.Io.Dir.cwd().createFile(io, path, .{});
                defer file.close(io);
                try file.writePositionalAll(io, bytes[offset .. offset + length], 0);
            }
            return c.pi_js_undefined();
        },
        .existsSync => {
            std.Io.Dir.cwd().access(io, path, .{}) catch return c.pi_js_bool(engine.context, 0);
            return c.pi_js_bool(engine.context, 1);
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
    try source.writer.writeAll("; writeFileSync(path,'preserve'); try {writeFileSync(path,{});} catch {} export const retained=readFileSync(path,'utf8'); writeFileSync(path,new Uint8Array([1,2,3,4]).subarray(1,3)); export const bytes=Array.from(readFileSync(path));");
    const namespace = try engine.evalModule(source.written(), "filesystem-views.js");
    defer engine.freeValue(namespace);
    const retained = c.JS_GetPropertyStr(engine.context, namespace, "retained");
    defer engine.freeValue(retained);
    const text = try engine.toString(retained);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("preserve", text);
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
