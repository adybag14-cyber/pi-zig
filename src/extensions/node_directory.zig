//! Native directory enumeration and Dirent objects over std.Io and QuickJS C.
const std = @import("std");
const builtin = @import("builtin");
const engine_mod = @import("engine.zig");
const node_buffer = @import("node_buffer.zig");
const node_path = @import("node_path.zig");
const native_url = @import("native_url.zig");
const c = engine_mod.c;
const flavor: node_path.Flavor = if (builtin.os.tag == .windows) .win32 else .posix;
const ConstructorState = struct { engine: *engine_mod.Engine, prototype: c.JSValue, symbol: c.JSValue };
const Options = struct { encoding: ?node_buffer.encodings.Encoding = .utf8, recursive: bool = false, types: bool = false };
const Entry = struct { name: []u8, kind: std.Io.File.Kind };
const QueueItem = struct { path: []u8, relative: []u8 };
const max_entries = 100_000;

fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *ConstructorState = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    c.JS_FreeValueRT(runtime, state.symbol);
    state.engine.gpa.destroy(state);
}

fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, mark_value: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *ConstructorState = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, mark_value);
    c.JS_MarkValue(runtime, state.symbol, mark_value);
}

fn originalFailure(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Dirent: %s", @as([*:0]const u8, @errorName(err)));
}

fn set(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_SetPropertyStr(engine.context, object, name, value) < 0) return error.JavaScriptException;
}

fn dirent(engine: *engine_mod.Engine, prototype: c.JSValue, symbol: c.JSValue, name: c.JSValue, kind: c.JSValue, parent: c.JSValue) !c.JSValue {
    const object = try engine.checked(c.JS_NewObjectProto(engine.context, prototype));
    errdefer engine.freeValue(object);
    try set(engine, object, "name", c.JS_DupValue(engine.context, name));
    try set(engine, object, "parentPath", c.JS_DupValue(engine.context, parent));
    const atom = c.JS_ValueToAtom(engine.context, symbol);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_SetProperty(engine.context, object, atom, c.JS_DupValue(engine.context, kind)) < 0) return error.JavaScriptException;
    return object;
}

fn constructorCall(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "Class constructor Dirent cannot be invoked without new");
    const state: *ConstructorState = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    const prototype_value = c.JS_GetPropertyStr(context, target, "prototype");
    if (c.JS_IsException(prototype_value)) return prototype_value;
    defer engine.freeValue(prototype_value);
    const prototype = if (c.JS_IsObject(prototype_value)) prototype_value else state.prototype;
    return dirent(engine, prototype, state.symbol, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), if (argc > 2) argv[2] else c.pi_js_undefined()) catch |err| originalFailure(engine, err);
}

fn predicate(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue, kind: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const atom = c.JS_ValueToAtom(context, data[0]);
    if (atom == c.JS_ATOM_NULL) return c.JS_ThrowOutOfMemory(context);
    defer c.JS_FreeAtom(context, atom);
    const value = c.JS_GetProperty(context, this, atom);
    if (c.JS_IsException(value)) return value;
    defer c.JS_FreeValue(context, value);
    return c.pi_js_bool(context, @intFromBool(c.JS_IsStrictEqual(context, value, c.JS_NewInt32(context, kind))));
}

fn typeNumber(kind: std.Io.File.Kind) u8 {
    return switch (kind) {
        .file => 1,
        .directory => 2,
        .sym_link => 3,
        .named_pipe => 4,
        .unix_domain_socket => 5,
        .character_device => 6,
        .block_device => 7,
        else => 0,
    };
}

fn get(engine: *engine_mod.Engine, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, value, name));
}

fn parseEncoding(engine: *engine_mod.Engine, value: c.JSValue) !?node_buffer.encodings.Encoding {
    if (c.JS_ToBool(engine.context, value) == 0) return .utf8;
    if (!c.JS_IsString(value)) return error.InvalidDirectoryEncoding;
    const name = try engine.toString(value);
    defer engine.gpa.free(name);
    if (std.mem.eql(u8, name, "buffer")) return null;
    return node_buffer.encodings.parse(name) orelse error.InvalidDirectoryEncoding;
}

fn initialOptions(engine: *engine_mod.Engine, input: c.JSValue) !c.JSValue {
    const options = if (c.JS_IsUndefined(input) or c.JS_IsNull(input) or c.JS_IsFunction(engine.context, input))
        try engine.checked(c.JS_NewObject(engine.context))
    else if (c.JS_IsString(input)) string: {
        const object = try engine.checked(c.JS_NewObject(engine.context));
        errdefer engine.freeValue(object);
        try set(engine, object, "encoding", c.JS_DupValue(engine.context, input));
        break :string object;
    } else if (c.JS_IsObject(input)) c.JS_DupValue(engine.context, input) else return error.InvalidDirectoryOptions;
    errdefer engine.freeValue(options);
    const first_encoding = try get(engine, options, "encoding");
    defer engine.freeValue(first_encoding);
    const first_bytes = if (c.JS_IsString(first_encoding)) try engine.toString(first_encoding) else null;
    defer if (first_bytes) |bytes| engine.gpa.free(bytes);
    if (first_bytes == null or !std.mem.eql(u8, first_bytes.?, "buffer")) {
        const second = try get(engine, options, "encoding");
        defer engine.freeValue(second);
        _ = try parseEncoding(engine, second);
    }
    const signal = try get(engine, options, "signal");
    defer engine.freeValue(signal);
    if (!c.JS_IsUndefined(signal)) {
        const validated = try get(engine, options, "signal");
        defer engine.freeValue(validated);
        if (!c.JS_IsUndefined(validated)) {
            if (!c.JS_IsObject(validated) or c.JS_IsFunction(engine.context, validated)) return error.InvalidDirectorySignal;
            const atom = c.JS_NewAtom(engine.context, "aborted");
            if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
            defer c.JS_FreeAtom(engine.context, atom);
            const present = c.JS_HasProperty(engine.context, validated, atom);
            if (present < 0) return error.JavaScriptException;
            if (present == 0) return error.InvalidDirectorySignal;
        }
    }
    return options;
}

// Node's promise variant takes a for-in snapshot, including inherited
// enumerable keys. Keep shadowed keys and original getter exceptions intact.
fn snapshotOptions(engine: *engine_mod.Engine, source: c.JSValue) !c.JSValue {
    const target = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(target);
    var seen: std.AutoHashMapUnmanaged(c.JSAtom, void) = .empty;
    defer {
        var atoms = seen.keyIterator();
        while (atoms.next()) |atom| c.JS_FreeAtom(engine.context, atom.*);
        seen.deinit(engine.gpa);
    }
    var prototype = c.JS_DupValue(engine.context, source);
    defer engine.freeValue(prototype);
    var depth: usize = 0;
    while (!c.JS_IsNull(prototype)) : (depth += 1) {
        if (depth > 1024) return error.DirectoryEntryLimit;
        var properties: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, prototype, c.JS_GPN_STRING_MASK) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(engine.context, properties, count);
        for (0..count) |index| {
            const property = properties[index];
            if (seen.contains(property.atom)) continue;
            try seen.put(engine.gpa, property.atom, {});
            _ = c.JS_DupAtom(engine.context, property.atom);
            if (!property.is_enumerable) continue;
            const value = try engine.checked(c.JS_GetProperty(engine.context, source, property.atom));
            if (c.JS_SetProperty(engine.context, target, property.atom, value) < 0) return error.JavaScriptException;
        }
        const next = try engine.checked(c.JS_GetPrototype(engine.context, prototype));
        engine.freeValue(prototype);
        prototype = next;
    }
    return target;
}

fn pathBytes(engine: *engine_mod.Engine, value: c.JSValue) ![]u8 {
    const bytes = if (native_url.isURL(engine, value)) try native_url.filePath(engine, value, builtin.os.tag == .windows) else if (c.JS_IsString(value)) try engine.toString(value) else typed: {
        if (c.JS_GetTypedArrayType(value) != c.JS_TYPED_ARRAY_UINT8) return error.InvalidDirectoryPathType;
        var offset: usize = 0;
        var length: usize = 0;
        var element: usize = 0;
        const backing = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, value, &offset, &length, &element));
        defer engine.freeValue(backing);
        var total: usize = 0;
        const data = c.JS_GetArrayBuffer(engine.context, &total, backing);
        if (c.JS_HasException(engine.context)) return error.JavaScriptException;
        if (offset > total or length > total - offset or (data == null and length != 0)) return error.InvalidDirectoryPathType;
        break :typed try engine.gpa.dupe(u8, if (length == 0) &.{} else data[offset .. offset + length]);
    };
    errdefer engine.gpa.free(bytes);
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return error.InvalidDirectoryPathValue;
    return bytes;
}

fn entries(engine: *engine_mod.Engine, path: []const u8) !std.ArrayList(Entry) {
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    var directory = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer directory.close(io);
    var result: std.ArrayList(Entry) = .empty;
    errdefer freeEntries(engine.gpa, &result);
    var iterator = directory.iterate();
    while (try iterator.next(io)) |entry| {
        if (result.items.len >= max_entries) return error.DirectoryEntryLimit;
        const name = try engine.gpa.dupe(u8, entry.name);
        errdefer engine.gpa.free(name);
        const kind = if (entry.kind == .unknown) (try directory.statFile(io, entry.name, .{ .follow_symlinks = false })).kind else entry.kind;
        try result.append(engine.gpa, .{ .name = name, .kind = kind });
    }
    // On Windows both Node and std.Io expose the filesystem's directory
    // enumeration order (including its Unicode case ordering). POSIX libuv
    // scandir sorts names by their original bytes before encoding them.
    if (builtin.os.tag != .windows) std.mem.sort(Entry, result.items, {}, struct {
        fn less(_: void, a: Entry, b: Entry) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.less);
    return result;
}

fn freeEntries(gpa: std.mem.Allocator, values: *std.ArrayList(Entry)) void {
    for (values.items) |entry| gpa.free(entry.name);
    values.deinit(gpa);
}

fn nameValue(engine: *engine_mod.Engine, bytes: []const u8, encoding: ?node_buffer.encodings.Encoding) !c.JSValue {
    const codec = encoding orelse return node_buffer.fromBytes(engine, bytes);
    const text = try node_buffer.encodings.decode(engine.gpa, bytes, codec);
    defer engine.gpa.free(text);
    return engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
}

fn joinPath(engine: *engine_mod.Engine, left: []const u8, right: []const u8) ![]u8 {
    return node_path.join(engine.gpa, &.{ left, right }, flavor) catch |err| switch (err) {
        // node_path uses an allocating writer; its WriteFailed is allocation
        // failure rather than a filesystem I/O failure.
        error.WriteFailed => error.OutOfMemory,
        else => err,
    };
}

fn collect(engine: *engine_mod.Engine, input_path: c.JSValue, path: []const u8, options: Options, promise: bool, post_options: c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    const result = try engine.checked(c.JS_NewArray(engine.context));
    errdefer engine.freeValue(result);
    var queue: std.ArrayList(QueueItem) = .empty;
    defer {
        for (queue.items) |item| {
            engine.gpa.free(item.path);
            engine.gpa.free(item.relative);
        }
        queue.deinit(engine.gpa);
    }
    const root_path = try engine.gpa.dupe(u8, path);
    var root_transferred = false;
    errdefer if (!root_transferred) engine.gpa.free(root_path);
    const relative = try engine.gpa.dupe(u8, "");
    errdefer if (!root_transferred) engine.gpa.free(relative);
    try queue.append(engine.gpa, .{ .path = root_path, .relative = relative });
    root_transferred = true;
    var cursor: usize = 0;
    var count: u32 = 0;
    var raw_pair = false;
    var raw_types = c.pi_js_undefined();
    defer engine.freeValue(raw_types);
    while (if (promise) queue.items.len != 0 else cursor < queue.items.len) {
        const current = if (promise) queue.pop().? else queue.items[cursor];
        defer if (promise) {
            engine.gpa.free(current.path);
            engine.gpa.free(current.relative);
        };
        if (!promise) cursor += 1;
        var listed = try entries(engine, current.path);
        defer freeEntries(engine.gpa, &listed);
        if (!options.recursive) {
            const final_types = try get(engine, post_options, "withFileTypes");
            defer engine.freeValue(final_types);
            const final = c.JS_ToBool(engine.context, final_types) != 0;
            if (final and !options.types) return error.DirectoryOptionsChanged;
            raw_pair = options.types and !final;
            if (raw_pair) raw_types = try engine.checked(c.JS_NewArray(engine.context));
        }
        for (listed.items) |entry| {
            if (count >= max_entries) return error.DirectoryEntryLimit;
            const requires_join = !promise or !options.types or entry.kind == .directory;
            if (options.recursive and requires_join and (options.encoding == null or !c.JS_IsString(input_path))) return error.InvalidDirectoryPathType;
            const full = try joinPath(engine, current.path, entry.name);
            defer engine.gpa.free(full);
            const entry_relative = if (current.relative.len == 0) try engine.gpa.dupe(u8, entry.name) else try joinPath(engine, current.relative, entry.name);
            defer engine.gpa.free(entry_relative);
            const name = try nameValue(engine, if (options.recursive and !options.types) entry_relative else entry.name, options.encoding);
            defer engine.freeValue(name);
            const value = if (options.types and !raw_pair) typed: {
                const parent = if (current.relative.len == 0) c.JS_DupValue(engine.context, input_path) else try engine.checked(c.JS_NewStringLen(engine.context, current.path.ptr, current.path.len));
                defer engine.freeValue(parent);
                break :typed try dirent(engine, data[1], data[2], name, c.JS_NewInt32(engine.context, typeNumber(entry.kind)), parent);
            } else c.JS_DupValue(engine.context, name);
            if (c.JS_SetPropertyUint32(engine.context, result, count, value) < 0) return error.JavaScriptException;
            if (raw_pair and c.JS_SetPropertyUint32(engine.context, raw_types, count, c.JS_NewInt32(engine.context, typeNumber(entry.kind))) < 0) return error.JavaScriptException;
            count += 1;
            if (options.recursive) {
                const descend = if (promise and options.types) entry.kind == .directory else if (!promise and options.types and entry.kind == .directory) true else stat: {
                    const stat = std.Io.Dir.cwd().statFile(io, full, .{}) catch break :stat false;
                    break :stat stat.kind == .directory;
                };
                if (descend) {
                    const child_path = try engine.gpa.dupe(u8, full);
                    errdefer engine.gpa.free(child_path);
                    const child_relative = try engine.gpa.dupe(u8, entry_relative);
                    errdefer engine.gpa.free(child_relative);
                    try queue.append(engine.gpa, .{ .path = child_path, .relative = child_relative });
                }
            }
        }
        if (!options.recursive) break;
    }
    if (raw_pair) {
        const pair = try engine.checked(c.JS_NewArray(engine.context));
        errdefer engine.freeValue(pair);
        if (c.JS_SetPropertyUint32(engine.context, pair, 0, c.JS_DupValue(engine.context, result)) < 0 or c.JS_SetPropertyUint32(engine.context, pair, 1, c.JS_DupValue(engine.context, raw_types)) < 0) return error.JavaScriptException;
        engine.freeValue(result);
        return pair;
    }
    return result;
}

fn call(engine: *engine_mod.Engine, args: []c.JSValue, promise: bool, data: [*c]c.JSValue) !c.JSValue {
    var snapshot: ?c.JSValue = null;
    defer if (snapshot) |value| engine.freeValue(value);
    return callCaptured(engine, args, promise, data, &snapshot);
}
fn callCaptured(engine: *engine_mod.Engine, args: []c.JSValue, promise: bool, data: [*c]c.JSValue, snapshot: *?c.JSValue) !c.JSValue {
    const initial = try initialOptions(engine, if (args.len > 1) args[1] else c.pi_js_undefined());
    defer engine.freeValue(initial);
    const object = if (promise) try snapshotOptions(engine, initial) else c.JS_DupValue(engine.context, initial);
    defer engine.freeValue(object);
    const input_path = if (args.len > 0) args[0] else c.pi_js_undefined();
    const path = try pathBytes(engine, input_path);
    defer engine.gpa.free(path);
    if (native_url.isURL(engine, input_path)) snapshot.* = try engine.checked(c.JS_NewStringLen(engine.context, path.ptr, path.len));
    var options: Options = .{};
    if (!promise) {
        const first = try get(engine, object, "recursive");
        defer engine.freeValue(first);
        if (!c.JS_IsNull(first) and !c.JS_IsUndefined(first)) {
            const validated = try get(engine, object, "recursive");
            defer engine.freeValue(validated);
            if (!c.JS_IsBool(validated)) return error.InvalidDirectoryRecursive;
        }
    }
    const recursive = try get(engine, object, "recursive");
    defer engine.freeValue(recursive);
    options.recursive = c.JS_ToBool(engine.context, recursive) != 0;
    if (options.recursive) {
        const types = try get(engine, object, "withFileTypes");
        defer engine.freeValue(types);
        options.types = c.JS_ToBool(engine.context, types) != 0;
    }
    const encoding = try get(engine, object, "encoding");
    defer engine.freeValue(encoding);
    options.encoding = try parseEncoding(engine, encoding);
    if (!options.recursive) {
        const types = try get(engine, object, "withFileTypes");
        defer engine.freeValue(types);
        options.types = c.JS_ToBool(engine.context, types) != 0;
    }
    return collect(engine, snapshot.* orelse input_path, path, options, promise, object, data);
}

fn failure(engine: *engine_mod.Engine, err: anyerror, args: []c.JSValue) c.JSValue {
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    if (native_url.isFilePathError(err)) return native_url.filePathErrorValue(engine, err);
    const code: ?[:0]const u8 = switch (err) {
        error.InvalidDirectoryPathType, error.InvalidDirectoryOptions, error.InvalidDirectorySignal, error.InvalidDirectoryRecursive => "ERR_INVALID_ARG_TYPE",
        error.InvalidDirectoryEncoding, error.InvalidDirectoryPathValue => "ERR_INVALID_ARG_VALUE",
        error.DirectoryEntryLimit => "ERR_FS_RECURSION_LIMIT",
        error.FileNotFound => "ENOENT",
        error.NotDir => "ENOTDIR",
        error.AccessDenied => "EACCES",
        error.PermissionDenied => "EPERM",
        error.NameTooLong => "ENAMETOOLONG",
        error.SymLinkLoop => "ELOOP",
        error.ProcessFdQuotaExceeded => "EMFILE",
        error.SystemFdQuotaExceeded => "ENFILE",
        error.InputOutput => "EIO",
        else => null,
    };
    const validation = err == error.DirectoryOptionsChanged or (code != null and std.mem.startsWith(u8, code.?, "ERR_"));
    const value = if (validation) typed: {
        _ = if (err == error.DirectoryEntryLimit) c.JS_ThrowRangeError(engine.context, "Native readdir: %s", @as([*:0]const u8, @errorName(err))) else c.JS_ThrowTypeError(engine.context, "Native readdir: %s", @as([*:0]const u8, @errorName(err)));
        const exception = c.JS_GetException(engine.context);
        if (!c.JS_IsError(exception)) return c.JS_Throw(engine.context, exception);
        break :typed exception;
    } else c.JS_NewError(engine.context);
    if (c.JS_IsException(value)) return value;
    if (!validation and c.JS_DefinePropertyValueStr(engine.context, value, "message", c.JS_NewString(engine.context, @as([*:0]const u8, @errorName(err))), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(value);
        return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
    }
    if (code) |name| {
        if (c.JS_DefinePropertyValueStr(engine.context, value, "code", c.JS_NewString(engine.context, name.ptr), c.JS_PROP_C_W_E) < 0) {
            engine.freeValue(value);
            return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
        }
        if (!validation) {
            if (c.JS_DefinePropertyValueStr(engine.context, value, "syscall", c.JS_NewString(engine.context, "scandir"), c.JS_PROP_C_W_E) < 0) {
                engine.freeValue(value);
                return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
            }
            if (args.len > 0 and c.JS_IsString(args[0]) and c.JS_DefinePropertyValueStr(engine.context, value, "path", c.JS_DupValue(engine.context, args[0]), c.JS_PROP_C_W_E) < 0) {
                engine.freeValue(value);
                return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
            }
        }
    }
    return value;
}

fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, promise_mode: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const args: []c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
    var snapshot: ?c.JSValue = null;
    defer if (snapshot) |value| engine.freeValue(value);
    if (promise_mode == 0) return callCaptured(engine, args, false, data, &snapshot) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        var error_args = [_]c.JSValue{snapshot orelse c.pi_js_undefined()};
        const value = failure(engine, err, if (snapshot != null) &error_args else args);
        return if (c.JS_IsException(value)) value else c.JS_Throw(context, value);
    };
    var resolvers: [2]c.JSValue = undefined;
    const promise = c.JS_NewPromiseCapability(context, &resolvers);
    if (c.JS_IsException(promise)) return promise;
    defer engine.freeValue(resolvers[0]);
    defer engine.freeValue(resolvers[1]);
    var rejected = false;
    const result = callCaptured(engine, args, true, data, &snapshot) catch |err| rejected: {
        rejected = true;
        if (err == error.JavaScriptException) {
            _ = engine.throwCaptured();
            break :rejected c.JS_GetException(context);
        }
        var error_args = [_]c.JSValue{snapshot orelse c.pi_js_undefined()};
        break :rejected failure(engine, err, if (snapshot != null) &error_args else args);
    };
    defer engine.freeValue(result);
    if (c.JS_IsException(result)) {
        engine.freeValue(promise);
        return result;
    }
    var arguments = [_]c.JSValue{result};
    const settled = c.JS_Call(context, resolvers[@intFromBool(rejected)], c.pi_js_undefined(), 1, &arguments);
    if (c.JS_IsException(settled)) {
        engine.freeValue(promise);
        return settled;
    }
    engine.freeValue(settled);
    return promise;
}

pub fn install(engine: *engine_mod.Engine, exports: c.JSValue, promises: c.JSValue) !void {
    try node_buffer.install(engine);
    const prototype = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(prototype);
    const symbol = try engine.checked(c.JS_NewSymbol(engine.context, "type", false));
    defer engine.freeValue(symbol);
    var class_id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class_id);
    const definition: c.JSClassDef = .{ .class_name = "Dirent", .finalizer = finalizer, .gc_mark = mark, .call = constructorCall, .exotic = null };
    if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.DirentClassFailed;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const function = try get(engine, global, "Function");
    defer engine.freeValue(function);
    const function_prototype = try get(engine, function, "prototype");
    defer engine.freeValue(function_prototype);
    const state = try engine.gpa.create(ConstructorState);
    state.* = .{ .engine = engine, .prototype = c.JS_DupValue(engine.context, prototype), .symbol = c.JS_DupValue(engine.context, symbol) };
    var transferred = false;
    errdefer if (!transferred) {
        engine.freeValue(state.prototype);
        engine.freeValue(state.symbol);
        engine.gpa.destroy(state);
    };
    const constructor = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, class_id));
    _ = c.JS_SetOpaque(constructor, state);
    transferred = true;
    defer engine.freeValue(constructor);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "name", c.JS_NewString(engine.context, "Dirent"), c.JS_PROP_CONFIGURABLE) < 0 or c.JS_DefinePropertyValueStr(engine.context, constructor, "length", c.JS_NewInt32(engine.context, 3), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    var symbol_data = [_]c.JSValue{symbol};
    inline for (.{ .{ "isFile", 1 }, .{ "isDirectory", 2 }, .{ "isSymbolicLink", 3 }, .{ "isFIFO", 4 }, .{ "isSocket", 5 }, .{ "isCharacterDevice", 6 }, .{ "isBlockDevice", 7 } }) |method| {
        const value = try engine.checked(c.JS_NewCFunctionData2(engine.context, predicate, method[0], 0, method[1], 1, &symbol_data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, method[0], value, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    }
    var data = [_]c.JSValue{ constructor, prototype, symbol };
    const sync = try engine.checked(c.JS_NewCFunctionData2(engine.context, invoke, "readdirSync", 2, 0, data.len, &data));
    if (c.JS_DefinePropertyValueStr(engine.context, exports, "readdirSync", sync, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const async_function = try engine.checked(c.JS_NewCFunctionData2(engine.context, invoke, "readdir", 2, 1, data.len, &data));
    if (c.JS_DefinePropertyValueStr(engine.context, promises, "readdir", async_function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, exports, "Dirent", c.JS_DupValue(engine.context, constructor), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}

fn fixtureEngine(gpa: std.mem.Allocator) !*engine_mod.Engine {
    const engine = try engine_mod.Engine.init(gpa, .{});
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(exports);
    const promises = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(promises);
    try install(engine, exports, promises);
    if (c.JS_DefinePropertyValueStr(engine.context, exports, "promises", c.JS_DupValue(engine.context, promises), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    try engine.registerDefaultModule("node:fs", exports);
    try engine.registerDefaultModule("node:fs/promises", promises);
    return engine;
}

test "native Dirent constructor symbol descriptors borrowing proxies and original exceptions" {
    const engine = try fixtureEngine(std.testing.allocator);
    defer engine.deinit();
    const result = try engine.evalModule(
        \\import fs from 'node:fs';const D=fs.Dirent;let checked=0;for(let type=0;type<=7;type++){const d=new D('name',type,'parent'),symbol=Object.getOwnPropertySymbols(d)[0];if(symbol.description!=='type'||Object.keys(d).join(',')!=='name,parentPath'||d[symbol]!==type||d.name!=='name'||d.parentPath!=='parent')throw Error('Dirent fields');for(const [method,id]of [['isFile',1],['isDirectory',2],['isSymbolicLink',3],['isFIFO',4],['isSocket',5],['isCharacterDevice',6],['isBlockDevice',7]]){if(d[method]()!==(id===type)||d[method].name!==method||d[method].length!==0||Object.getOwnPropertyDescriptor(D.prototype,method).enumerable)throw Error(method);checked++}}let noNew=false;try{D('name',1,'parent')}catch(e){noNew=e instanceof TypeError}if(!noNew||D.length!==3||D.name!=='Dirent')throw Error('constructor');const d=new D('x',1,'p'),symbol=Object.getOwnPropertySymbols(d)[0];if(D.prototype.isFile.call({})!==false||D.prototype.isFile.call({[symbol]:1})!==true||!new Proxy(d,{}).isFile())throw Error('borrowing');const original={};try{D.prototype.isFile.call(new Proxy(d,{get(){throw original}}));throw Error('missing exception')}catch(e){if(e!==original)throw e}class Child extends D{}if(!(new Child('x',2,'p') instanceof Child))throw Error('subclass');export const checks=checked;
    , "native-dirent.mjs");
    defer engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native readdir scans real directories names binary output recursion and promise errors" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "a/deep");
    try temporary.dir.createDirPath(std.testing.io, "z");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "root.txt", .data = "root" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "a/file.txt", .data = "a" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "a/deep/end.txt", .data = "deep" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "z/last.txt", .data = "z" });
    const engine = try fixtureEngine(std.testing.allocator);
    defer engine.deinit();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const path = try engine.checked(c.JS_NewStringLen(engine.context, &path_buffer, length));
    defer engine.freeValue(path);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try set(engine, global, "fixturePath", c.JS_DupValue(engine.context, path));
    const result = engine.evalModule(
        \\import fs from 'node:fs';import fsp from 'node:fs/promises';const path=fixturePath,slash=s=>s.replaceAll('\\','/');const plain=fs.readdirSync(path);if(JSON.stringify(plain)!=='["a","root.txt","z"]')throw Error('names');const binary=fs.readdirSync(path,'buffer');if(binary.some(x=>!Buffer.isBuffer(x))||binary.map(x=>x.toString()).join(',')!==plain.join(','))throw Error('binary');const D=fs.Dirent;fs.Dirent=function(){throw Error('changed constructor')};const dirs=fs.readdirSync(path,{withFileTypes:true});if(dirs.some(x=>!(x instanceof D)||x.parentPath!==path)||!dirs[0].isDirectory()||!dirs[1].isFile())throw Error('types');const recursive=fs.readdirSync(path,{recursive:true}).map(slash);if(JSON.stringify(recursive)!=='["a","root.txt","z","a/deep","a/file.txt","z/last.txt","a/deep/end.txt"]')throw Error('breadth first:'+recursive);const async=(await fsp.readdir(path,{recursive:true})).map(slash);if(JSON.stringify(async)!=='["a","root.txt","z","z/last.txt","a/deep","a/file.txt","a/deep/end.txt"]')throw Error('depth first:'+async);let checks=0;const original={};for(const fn of [()=>fs.readdirSync(path,{get encoding(){throw original}}),()=>fsp.readdir(path,{get encoding(){throw original}})]){try{await fn()}catch(e){if(e!==original)throw e;checks++}}for(const fn of [()=>fs.readdirSync(path+'/missing'),()=>fsp.readdir(path+'/missing')]){try{await fn()}catch(e){if(e.code!=='ENOENT'||e.syscall!=='scandir'||e.path!==path+'/missing')throw e;checks++}}for(const fn of [()=>fs.readdirSync(path+'/root.txt'),()=>fsp.readdir(path+'/root.txt')]){try{await fn()}catch(e){if(e.code!=='ENOTDIR'||e.syscall!=='scandir')throw e;checks++}}if(checks!==6)throw Error('error checks');const typed=fs.readdirSync(path,{encoding:'buffer',withFileTypes:true});if(typed.some(x=>!Buffer.isBuffer(x.name)))throw Error('typed binary');
    , "native-readdir-real.mjs") catch |err| {
        std.debug.print("Native readdir fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(result);
}

test "native readdir validation original repeated getter exceptions promise snapshots and byte paths" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "entry", .data = "" });
    const engine = try fixtureEngine(std.testing.allocator);
    defer engine.deinit();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try set(engine, global, "fixturePath", try engine.checked(c.JS_NewStringLen(engine.context, &path_buffer, length)));
    const result = engine.evalModule(
        \\import fs from 'node:fs';import fsp from 'node:fs/promises';const path=fixturePath,reason={};let checks=0;for(const options of [false,1,{encoding:1},{encoding:'not-encoding'},{signal:null},{signal:{}},{recursive:1}]){try{fs.readdirSync(path,options);throw Error('invalid accepted')}catch(e){if(!(e instanceof TypeError)||!['ERR_INVALID_ARG_TYPE','ERR_INVALID_ARG_VALUE'].includes(e.code))throw e;checks++}}
        \\if((await fsp.readdir(path,{recursive:1})).join(',')!=='entry')throw Error('promise recursive truthiness');if(fs.readdirSync(Buffer.from(path)).join(',')!=='entry'||fs.readdirSync(new Uint8Array(Buffer.from(path))).join(',')!=='entry')throw Error('byte paths');
        \\for(const input of [path,Buffer.from(path)]){const binary=await fsp.readdir(input,{recursive:true,encoding:'buffer',withFileTypes:true});if(binary.length!==1||!Buffer.isBuffer(binary[0].name)||!binary[0].isFile())throw Error('promise file-only recursive Buffer')}
        \\for(const key of ['encoding','recursive','withFileTypes'])for(const target of [1,2]){let count=0;const options={get [key](){if(++count===target)throw reason;return key==='encoding'?'utf8':false}};try{fs.readdirSync(path,options);throw Error('getter accepted')}catch(e){if(e!==reason)throw e;checks++}}
        \\try{await fsp.readdir(path,{get extra(){throw reason}});throw Error('snapshot getter accepted')}catch(e){if(e!==reason)throw e;checks++}try{fs.readdirSync(null,{get encoding(){throw reason}});throw Error('order accepted')}catch(e){if(e!==reason)throw e;checks++}
        \\const inherited=Object.create({encoding:'buffer',withFileTypes:true});if((await fsp.readdir(path,inherited)).some(e=>!Buffer.isBuffer(e.name)))throw Error('inherited snapshot');if(checks!==15)throw Error('validation count:'+checks);const emptyPath=path+'/absent';try{fs.readdirSync(emptyPath,{recursive:true,encoding:'buffer'})}catch(e){if(e.code!=='ENOENT')throw e}
        \\let toggles=0;const raw=fs.readdirSync(path,{get withFileTypes(){return ++toggles===1}});if(JSON.stringify(raw)!=='[["entry"],[1]]')throw Error('changing types raw result');toggles=0;try{fs.readdirSync(path,{get withFileTypes(){return ++toggles!==1}});throw Error('changing types accepted')}catch(e){if(!(e instanceof TypeError)||e.code!==undefined)throw e}
    , "native-directory-validation.mjs") catch |err| {
        std.debug.print("Native directory validation: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(result);
}

test "native readdir actual file and directory symlinks follow Node's distinct recursive modes" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "dir");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "leaf", .data = "" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dir/inside", .data = "" });
    temporary.dir.symLink(std.testing.io, "leaf", "filelink", .{}) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    try temporary.dir.symLink(std.testing.io, "dir", "dirlink", .{ .is_directory = true });
    const engine = try fixtureEngine(std.testing.allocator);
    defer engine.deinit();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try set(engine, global, "fixturePath", try engine.checked(c.JS_NewStringLen(engine.context, &path_buffer, length)));
    const value = try engine.evalModule(
        \\import fs from 'node:fs';import fsp from 'node:fs/promises';const path=fixturePath,norm=s=>s.replaceAll('\\','/');for(const value of fs.readdirSync(path,{withFileTypes:true})){if(['filelink','dirlink'].includes(value.name)&&(!value.isSymbolicLink()||value.isDirectory()||value.isFile()))throw Error('link type')}
        \\for(const result of [fs.readdirSync(path,{recursive:true}),await fsp.readdir(path,{recursive:true})]){const names=result.map(norm);if(!names.includes('dir/inside')||!names.includes('dirlink/inside')||names.some(s=>s.startsWith('filelink/')))throw Error('string links')}
        \\const sync=fs.readdirSync(path,{recursive:true,withFileTypes:true}),async=await fsp.readdir(path,{recursive:true,withFileTypes:true});if(!sync.some(e=>e.name==='inside'&&norm(e.parentPath).endsWith('/dirlink'))||async.some(e=>norm(e.parentPath).endsWith('/dirlink')))throw Error('typed link traversal');
    , "native-directory-links.mjs");
    defer engine.freeValue(value);
}

fn allocationProbe(gpa: std.mem.Allocator, path: []const u8) !void {
    const engine = try fixtureEngine(gpa);
    defer engine.deinit();
    const exports = engine.native_module_values.get("node:fs").?;
    const constructor = try get(engine, exports, "Dirent");
    defer engine.freeValue(constructor);
    const state: *ConstructorState = @ptrCast(@alignCast(c.JS_GetOpaque(constructor, c.JS_GetClassID(constructor)).?));
    var data = [_]c.JSValue{ constructor, state.prototype, state.symbol };
    var args = [_]c.JSValue{
        try engine.checked(c.JS_NewStringLen(engine.context, path.ptr, path.len)),
        try engine.checked(c.JS_NewObject(engine.context)),
    };
    defer engine.freeValue(args[0]);
    defer engine.freeValue(args[1]);
    try set(engine, args[1], "recursive", c.pi_js_bool(engine.context, 1));
    try set(engine, args[1], "withFileTypes", c.pi_js_bool(engine.context, 1));
    const sync = try call(engine, &args, false, &data);
    defer engine.freeValue(sync);
    const async_value = try call(engine, &args, true, &data);
    defer engine.freeValue(async_value);
    c.JS_RunGC(engine.runtime);
    const length = try get(engine, async_value, "length");
    defer engine.freeValue(length);
    var count: i32 = 0;
    if (c.JS_ToInt32(engine.context, &count, length) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 3), count);
}

test "native directory queues descriptors snapshots constructor cycles and every allocation failure clean up" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "dir");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "one", .data = "" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dir/two", .data = "" });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{path_buffer[0..length]});
}
