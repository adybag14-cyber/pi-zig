//! Read-only bounded discovery and explicit SDK session forks.
const std = @import("std");
const builtin = @import("builtin");
const sdk = @import("native_sdk.zig");
const files = @import("native_sdk_session_files.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Method = enum(c_int) { continueRecent, forkFrom, findById };
pub const Candidate = struct { path: []u8, mtime: i96 = 0, index: usize };
pub fn install(engine: *engine_mod.Engine, constructor: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| try sdk.put(engine, constructor, field.name, try engine.checked(c.pi_js_function_magic(engine.context, callback, field.name, switch (@as(Method, @enumFromInt(field.value))) {
        .continueRecent => 2,
        .forkFrom => 4,
        .findById => 3,
    }, @intCast(field.value))));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 4;
    for (0..@min(args.len, @as(usize, @intCast(@max(argc, 0))))) |index| args[index] = argv[index];
    return dispatch(engine, @enumFromInt(magic), &args) catch |err| sdk.fail(engine, err);
}
pub fn defaultDirectory(engine: *engine_mod.Engine, working: c.JSValue) ![]u8 {
    const resolved = try sdk.resolveSdkPath(engine, working);
    defer engine.gpa.free(resolved);
    const encoded = try sdk.encodeCwd(engine, resolved);
    defer engine.gpa.free(encoded);
    const root = try sdk.agentDir(engine);
    defer engine.gpa.free(root);
    return std.fs.path.join(engine.gpa, &.{ root, "sessions", encoded });
}
pub fn directory(engine: *engine_mod.Engine, working: c.JSValue, selected: c.JSValue) ![]u8 {
    if (c.JS_ToBool(engine.context, selected) == 1) {
        const normalized = try @import("native_sdk_settings.zig").normalizePath(engine, selected);
        defer engine.freeValue(normalized);
        return engine.toString(normalized);
    }
    const result = try defaultDirectory(engine, working);
    errdefer engine.gpa.free(result);
    try std.Io.Dir.cwd().createDirPath(engine.native_io orelse return error.NativeSDKRequiresIO, result);
    return result;
}
pub fn enumerate(engine: *engine_mod.Engine, path: []const u8, with_stat: bool) ![]Candidate {
    const io = engine.native_io orelse return error.NativeSDKRequiresIO;
    var directory_handle = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer directory_handle.close(io);
    var iterator = directory_handle.iterate();
    var list: std.ArrayList(Candidate) = .empty;
    errdefer {
        for (list.items) |item| engine.gpa.free(item.path);
        list.deinit(engine.gpa);
    }
    while (try iterator.next(io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".jsonl")) continue;
        const full = try std.fs.path.join(engine.gpa, &.{ path, entry.name });
        errdefer engine.gpa.free(full);
        const mtime = if (with_stat) (try directory_handle.statFile(io, entry.name, .{})).mtime.nanoseconds else 0;
        try list.append(engine.gpa, .{ .path = full, .mtime = mtime, .index = list.items.len });
    }
    if (builtin.os.tag != .windows) std.mem.sort(Candidate, list.items, {}, struct {
        fn less(_: void, a: Candidate, b: Candidate) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.less);
    for (list.items, 0..) |*item, index| item.index = index;
    return list.toOwnedSlice(engine.gpa);
}
pub fn freeCandidates(engine: *engine_mod.Engine, items: []Candidate) void {
    for (items) |item| engine.gpa.free(item.path);
    engine.gpa.free(items);
}
fn headerCandidate(engine: *engine_mod.Engine, line: []const u8) !c.JSValue {
    const terminated = try engine.gpa.dupeZ(u8, line);
    defer engine.gpa.free(terminated);
    const row = c.JS_ParseJSON(engine.context, terminated, line.len, "session-header");
    if (c.JS_IsException(row)) {
        engine.freeValue(c.JS_GetException(engine.context));
        return c.pi_js_undefined();
    }
    if (c.JS_ToBool(engine.context, row) != 1) {
        engine.freeValue(row);
        return c.pi_js_undefined();
    }
    errdefer engine.freeValue(row);
    const typ = try sdk.get(engine, row, "type");
    defer engine.freeValue(typ);
    const tag = try sdk.text(engine, "session");
    defer engine.freeValue(tag);
    const id = try sdk.get(engine, row, "id");
    defer engine.freeValue(id);
    if (c.JS_IsStrictEqual(engine.context, typ, tag) and c.JS_IsString(id)) return row;
    engine.freeValue(row);
    return c.pi_js_null();
}
pub fn readHeader(engine: *engine_mod.Engine, path: []const u8) !c.JSValue {
    const io = engine.native_io orelse return error.NativeSDKRequiresIO;
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const limit = 1024 * 1024;
    var buffer: [64 * 1024]u8 = undefined;
    var pending: std.ArrayList(u8) = .empty;
    defer pending.deinit(engine.gpa);
    var offset: usize = 0;
    while (offset < limit) {
        const size = try file.readPositional(io, &.{buffer[0..@min(buffer.len, limit - offset)]}, offset);
        if (size == 0) {
            const row = try headerCandidate(engine, pending.items);
            return if (c.JS_IsUndefined(row)) c.pi_js_null() else row;
        }
        offset += size;
        var start: usize = 0;
        for (buffer[0..size], 0..) |byte, index| if (byte == '\n') {
            try pending.appendSlice(engine.gpa, buffer[start..index]);
            const row = try headerCandidate(engine, pending.items);
            if (!c.JS_IsUndefined(row)) return row;
            pending.clearRetainingCapacity();
            start = index + 1;
        };
        try pending.appendSlice(engine.gpa, buffer[start..size]);
    }
    var probe: [1]u8 = undefined;
    if (try file.readPositional(io, &.{&probe}, offset) > 0) return c.pi_js_null();
    const row = try headerCandidate(engine, pending.items);
    return if (c.JS_IsUndefined(row)) c.pi_js_null() else row;
}
pub fn matchesCwd(engine: *engine_mod.Engine, header: c.JSValue, resolved: []const u8) !bool {
    const cwd = try sdk.get(engine, header, "cwd");
    defer engine.freeValue(cwd);
    if (!c.JS_IsString(cwd) or c.JS_ToBool(engine.context, cwd) != 1) return false;
    const path = try sdk.resolveSdkPath(engine, cwd);
    defer engine.gpa.free(path);
    return std.mem.eql(u8, path, resolved);
}
fn dispatch(engine: *engine_mod.Engine, method: Method, args: []const c.JSValue) !c.JSValue {
    if (method == .forkFrom) return fork(engine, args);
    const selected = if (method == .continueRecent) args[1] else args[2];
    const path = try directory(engine, args[0], selected);
    defer engine.gpa.free(path);
    const default = try defaultDirectory(engine, args[0]);
    defer engine.gpa.free(default);
    const filter = !c.JS_IsUndefined(selected) and !std.mem.eql(u8, path, default);
    const working = try sdk.resolveSdkPath(engine, args[0]);
    defer engine.gpa.free(working);
    const items = enumerate(engine, path, method == .continueRecent) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (method == .findById) return c.pi_js_undefined();
        const directory_value = try sdk.text(engine, path);
        defer engine.freeValue(directory_value);
        return sdk.initManager(engine, &.{ args[0], directory_value }, true);
    };
    defer freeCandidates(engine, items);
    if (method == .continueRecent) std.mem.sort(Candidate, items, {}, struct {
        fn less(_: void, a: Candidate, b: Candidate) bool {
            return a.mtime > b.mtime or (a.mtime == b.mtime and a.index < b.index);
        }
    }.less);
    for (items) |item| {
        const header = readHeader(engine, item.path) catch |err| {
            if (err == error.OutOfMemory) return err;
            continue;
        };
        defer engine.freeValue(header);
        if (!c.JS_IsObject(header)) continue;
        if (method == .findById) {
            const id = try sdk.get(engine, header, "id");
            defer engine.freeValue(id);
            if (!c.JS_IsStrictEqual(engine.context, id, args[1])) continue;
        }
        if (filter and !try matchesCwd(engine, header, working)) continue;
        const result = try sdk.text(engine, item.path);
        if (method == .findById) return result;
        defer engine.freeValue(result);
        const directory_value = try sdk.text(engine, path);
        defer engine.freeValue(directory_value);
        return files.open(engine, &.{ result, directory_value, args[0] });
    }
    if (method == .findById) return c.pi_js_undefined();
    const directory_value = try sdk.text(engine, path);
    defer engine.freeValue(directory_value);
    return sdk.initManager(engine, &.{ args[0], directory_value }, true);
}
fn fork(engine: *engine_mod.Engine, args: []const c.JSValue) !c.JSValue {
    const source = try sdk.resolveSdkPath(engine, args[0]);
    defer engine.gpa.free(source);
    const entries = try files.load(engine, source);
    defer engine.freeValue(entries);
    if (try sdk.length(engine, entries) == 0) {
        const message = try std.fmt.allocPrint(engine.gpa, "Cannot fork: source session file is empty or invalid: {s}", .{source});
        defer engine.gpa.free(message);
        return sdk.sourceError(engine, message);
    }
    const working = try sdk.resolveSdkPath(engine, args[1]);
    defer engine.gpa.free(working);
    const working_value = try sdk.text(engine, working);
    defer engine.freeValue(working_value);
    const path = try directory(engine, working_value, args[2]);
    defer engine.gpa.free(path);
    const directory_value = try sdk.text(engine, path);
    defer engine.freeValue(directory_value);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try @import("native_sdk_models.zig").copy(engine, options, args[3]);
    try sdk.put(engine, options, "parentSession", try sdk.text(engine, source));
    const manager = try sdk.initManager(engine, &.{ working_value, directory_value, options }, true);
    errdefer engine.freeValue(manager);
    const owner = try sdk.state(engine, manager);
    const rows = try sdk.get(engine, owner.data, "entries");
    defer engine.freeValue(rows);
    for (1..try sdk.length(engine, entries)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(index)));
        defer engine.freeValue(row);
        const typ = try sdk.get(engine, row, "type");
        defer engine.freeValue(typ);
        const tag = try sdk.text(engine, "session");
        defer engine.freeValue(tag);
        if (!c.JS_IsStrictEqual(engine.context, typ, tag)) try sdk.append(engine, rows, c.JS_DupValue(engine.context, row));
    }
    if (try sdk.length(engine, rows) > 0) {
        const last = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, try sdk.length(engine, rows) - 1));
        defer engine.freeValue(last);
        try sdk.put(engine, owner.data, "leafId", try sdk.get(engine, last, "id"));
    }
    try sdk.rebuildSessionIndex(engine, owner.data);
    const output_path = try sdk.get(engine, owner.data, "sessionFile");
    defer engine.freeValue(output_path);
    const output = try engine.toString(output_path);
    defer engine.gpa.free(output);
    const file = try std.Io.Dir.cwd().createFile(engine.native_io orelse return error.NativeSDKRequiresIO, output, .{ .exclusive = true });
    file.close(engine.native_io.?);
    try files.rewrite(owner);
    return manager;
}
