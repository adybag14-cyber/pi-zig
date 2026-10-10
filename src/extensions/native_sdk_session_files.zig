//! SDK file sessions preserve explicit paths, delayed persistence, and loaded
//! session identity. Discovery/branch selection stays on the owning thread.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const projection = @import("native_sdk_session_projection.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
fn pathText(engine: *engine_mod.Engine, value: c.JSValue) ![]u8 {
    const normalized = try @import("native_sdk_settings.zig").normalizePath(engine, value);
    defer engine.freeValue(normalized);
    return engine.toString(normalized);
}
fn isHeader(engine: *engine_mod.Engine, row: c.JSValue) !bool {
    const typ = try sdk.get(engine, row, "type");
    defer engine.freeValue(typ);
    const tag = try sdk.text(engine, "session");
    defer engine.freeValue(tag);
    const id = try sdk.get(engine, row, "id");
    defer engine.freeValue(id);
    return c.JS_IsStrictEqual(engine.context, typ, tag) and c.JS_IsString(id);
}
pub fn load(engine: *engine_mod.Engine, path: []const u8) !c.JSValue {
    const io = engine.native_io orelse return error.NativeSDKRequiresIO;
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, engine.gpa, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return sdk.array(engine),
        else => return err,
    };
    defer engine.gpa.free(raw);
    const text = try sdk.text(engine, raw);
    defer engine.freeValue(text);
    const parsed = try projection.parseLines(engine, text, false);
    defer engine.freeValue(parsed);
    const entries = try sdk.array(engine);
    errdefer engine.freeValue(entries);
    for (0..try sdk.length(engine, parsed)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, parsed, @intCast(index)));
        defer engine.freeValue(row);
        if (c.JS_ToBool(engine.context, row) == 1) try sdk.append(engine, entries, c.JS_DupValue(engine.context, row));
    }
    if (try sdk.length(engine, entries) == 0) return entries;
    const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, 0));
    defer engine.freeValue(first);
    if (!try isHeader(engine, first)) {
        const empty = try sdk.array(engine);
        engine.freeValue(entries);
        return empty;
    }
    if (raw.len > 0 and raw[raw.len - 1] != '\n') {
        const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_write });
        defer file.close(io);
        const stat = try file.stat(io);
        try file.writePositionalAll(io, "\n", stat.size);
    }
    return entries;
}
pub fn rewrite(self: *sdk.State) !void {
    const engine = self.engine;
    const path = try sdk.get(engine, self.data, "sessionFile");
    defer engine.freeValue(path);
    if (!c.JS_IsString(path)) return;
    const raw_path = try engine.toString(path);
    defer engine.gpa.free(raw_path);
    var output: std.Io.Writer.Allocating = .init(engine.gpa);
    defer output.deinit();
    const header = try sdk.get(engine, self.data, "header");
    defer engine.freeValue(header);
    const raw_header = try engine.stringify(header);
    defer engine.gpa.free(raw_header);
    output.writer.writeAll(raw_header) catch return error.OutOfMemory;
    output.writer.writeByte('\n') catch return error.OutOfMemory;
    const rows = try sdk.get(engine, self.data, "entries");
    defer engine.freeValue(rows);
    for (0..try sdk.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const raw = try engine.stringify(row);
        defer engine.gpa.free(raw);
        output.writer.writeAll(raw) catch return error.OutOfMemory;
        output.writer.writeByte('\n') catch return error.OutOfMemory;
    }
    try std.Io.Dir.cwd().writeFile(engine.native_io orelse return error.NativeSDKRequiresIO, .{ .sub_path = raw_path, .data = output.written() });
    self.persisted_count = try sdk.length(engine, rows);
    self.session_flushed = true;
}
pub fn open(engine: *engine_mod.Engine, args: []const c.JSValue) !c.JSValue {
    return openMode(engine, args, true);
}
pub fn openMode(engine: *engine_mod.Engine, args: []const c.JSValue, persistent: bool) !c.JSValue {
    if (args.len == 0) return error.NativeSDKMissingArgument;
    const io = engine.native_io orelse return error.NativeSDKRequiresIO;
    const path = try sdk.resolveSdkPath(engine, args[0]);
    defer engine.gpa.free(path);
    const path_value = try sdk.text(engine, path);
    defer engine.freeValue(path_value);
    const entries = try load(engine, path);
    defer engine.freeValue(entries);
    const count = try sdk.length(engine, entries);
    const first = if (count > 0) try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, 0)) else c.pi_js_undefined();
    defer engine.freeValue(first);
    const header_cwd = if (count > 0) try sdk.get(engine, first, "cwd") else c.pi_js_undefined();
    defer engine.freeValue(header_cwd);
    const default_cwd = try sdk.cwd(engine);
    defer engine.gpa.free(default_cwd);
    const fallback_cwd = try sdk.text(engine, default_cwd);
    defer engine.freeValue(fallback_cwd);
    const working = if (args.len > 2 and !c.JS_IsUndefined(args[2]) and !c.JS_IsNull(args[2])) args[2] else if (c.JS_IsString(header_cwd)) header_cwd else fallback_cwd;
    const directory = if (args.len > 1 and c.JS_ToBool(engine.context, args[1]) == 1) try pathText(engine, args[1]) else try engine.gpa.dupe(u8, std.fs.path.dirname(path) orelse ".");
    defer engine.gpa.free(directory);
    if (persistent) try std.Io.Dir.cwd().createDirPath(io, directory);
    var existed = true;
    const file: ?std.Io.File = std.Io.Dir.cwd().openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => missing: {
            existed = false;
            break :missing null;
        },
        else => return err,
    };
    var file_size: u64 = 0;
    if (file) |opened| {
        defer opened.close(io);
        file_size = (try opened.stat(io)).size;
    }
    if (existed and count == 0 and file_size > 0) {
        const message = try std.fmt.allocPrint(engine.gpa, "Session file is not a valid pi session: {s}", .{path});
        defer engine.gpa.free(message);
        return sdk.sourceError(engine, message);
    }
    const migrated = if (count > 0) try projection.migrate(engine, entries) else false;
    const manager = try sdk.initManager(engine, &.{ working, c.pi_js_undefined(), entries }, false);
    errdefer engine.freeValue(manager);
    const owner = try sdk.state(engine, manager);
    try sdk.put(engine, owner.data, "sessionFile", c.JS_DupValue(engine.context, path_value));
    try sdk.put(engine, owner.data, "sessionDir", try sdk.text(engine, directory));
    try sdk.put(engine, owner.data, "persistent", c.pi_js_bool(engine.context, @intFromBool(persistent)));
    const rows = try sdk.get(engine, owner.data, "entries");
    defer engine.freeValue(rows);
    owner.persisted_count = try sdk.length(engine, rows);
    owner.session_flushed = existed;
    if (persistent and existed and (count == 0 or migrated)) try rewrite(owner);
    return manager;
}
