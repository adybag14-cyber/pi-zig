//! Real built-in theme assets for a native compiled distribution.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const v = @import("native_select_list.zig");
const c = em.c;
const paths = @import("node_path.zig");
const flavor: paths.Flavor = if (builtin.os.tag == .windows) .win32 else .posix;
pub const Asset = struct { name: []const u8, bytes: []const u8 };
pub const sources = [_]Asset{ .{ .name = "dark.json", .bytes = @embedFile("../themes/fixtures/dark-original-6fb.json") }, .{ .name = "light.json", .bytes = @embedFile("../themes/fixtures/light-original-6fb.json") } };

pub fn ensure(gpa: std.mem.Allocator, io: std.Io, asset_directory: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, asset_directory);
    for (sources) |asset| {
        const path = try std.fs.path.join(gpa, &.{ asset_directory, asset.name });
        defer gpa.free(path);
        // An installed or explicitly supplied asset remains authoritative.
        const exists = blk: {
            std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
                error.FileNotFound => break :blk false,
                else => return err,
            };
            break :blk true;
        };
        if (exists) continue;
        var nonce: [16]u8 = undefined;
        std.Io.random(io, &nonce);
        const temporary = try std.fmt.allocPrint(gpa, "{s}.{s}.tmp", .{ path, std.fmt.bytesToHex(nonce, .lower) });
        defer gpa.free(temporary);
        defer std.Io.Dir.cwd().deleteFile(io, temporary) catch {};
        {
            const file = try std.Io.Dir.cwd().createFile(io, temporary, .{ .exclusive = true });
            defer file.close(io);
            try file.writeStreamingAll(io, asset.bytes);
            try file.sync(io);
        }
        // Readers see complete bytes, including when multiple workers start
        // against the same unpackaged executable directory concurrently.
        std.Io.Dir.cwd().renamePreserve(temporary, .cwd(), path, io) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
}
fn configuredPackage(engine: *em.Engine) !?[]u8 {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    if (c.JS_IsUndefined(process)) return null;
    const environment = try js.get(engine, process, "env");
    defer engine.freeValue(environment);
    const configured = try js.get(engine, environment, "PI_PACKAGE_DIR");
    defer engine.freeValue(configured);
    if (!v.truthy(engine, configured)) return null;
    const home = try @import("native_home.zig").get(engine);
    defer engine.freeValue(home);
    const home_text = try engine.toString(home);
    defer engine.gpa.free(home_text);
    const text = try engine.toString(configured);
    defer engine.gpa.free(text);
    const normalized = try @import("native_theme_watch.zig").normalizeWindowsShell(engine, text);
    defer engine.gpa.free(normalized);
    if (std.mem.startsWith(u8, normalized, "file://")) {
        const module = try @import("native_theme.zig").moduleState(engine);
        defer engine.freeValue(module);
        const converter = try js.get(engine, module, "themeFileURLToPath");
        defer engine.freeValue(converter);
        const value = try v.text(engine, normalized);
        defer engine.freeValue(value);
        const converted = try js.call(engine, converter, c.pi_js_undefined(), &.{value});
        defer engine.freeValue(converted);
        return try engine.toString(converted);
    }
    if (std.mem.eql(u8, normalized, "~") or std.mem.startsWith(u8, normalized, "~/") or (builtin.os.tag == .windows and std.mem.startsWith(u8, normalized, "~\\"))) return try paths.join(engine.gpa, &.{ home_text, if (normalized.len > 1) normalized[2..] else "" }, flavor);
    return try paths.join(engine.gpa, &.{normalized}, flavor);
}
pub fn directory(engine: *em.Engine) ![]u8 {
    if (try configuredPackage(engine)) |package| {
        defer engine.gpa.free(package);
        // Source compiled-binary layout. Explicit package directories are read
        // as supplied; a typo must not silently populate an unrelated location.
        return paths.join(engine.gpa, &.{ package, "theme" }, flavor);
    }
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    const executable = try std.process.executablePathAlloc(io, engine.gpa);
    defer engine.gpa.free(executable);
    const selected = try paths.join(engine.gpa, &.{ std.fs.path.dirname(executable) orelse ".", "theme" }, flavor);
    errdefer engine.gpa.free(selected);
    ensure(engine.gpa, io, selected) catch |err| switch (err) {
        error.AccessDenied, error.ReadOnlyFileSystem => {
            const home = try @import("native_home.zig").get(engine);
            defer engine.freeValue(home);
            const home_text = try engine.toString(home);
            defer engine.gpa.free(home_text);
            var digest: [32]u8 = undefined;
            var hash = std.crypto.hash.sha2.Sha256.init(.{});
            for (sources) |asset| hash.update(asset.bytes);
            hash.final(&digest);
            const identity = std.fmt.bytesToHex(digest, .lower);
            const fallback = try paths.join(engine.gpa, &.{ home_text, ".pi", "native-assets", &identity, "theme" }, flavor);
            errdefer engine.gpa.free(fallback);
            try ensure(engine.gpa, io, fallback);
            engine.gpa.free(selected);
            return fallback;
        },
        else => return err,
    };
    return selected;
}
fn getThemesDir(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const path = directory(engine) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return c.JS_ThrowTypeError(context, "Native theme assets: %s", @as([*:0]const u8, @errorName(err)));
    };
    defer engine.gpa.free(path);
    return c.JS_NewStringLen(context, path.ptr, path.len);
}
pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    try js.define(engine, exports, "getThemesDir", try engine.checked(c.JS_NewCFunction(engine.context, getThemesDir, "getThemesDir", 0)));
}

pub fn builtinSources(engine: *em.Engine) !c.JSValue {
    const module = try @import("native_theme.zig").moduleState(engine);
    defer engine.freeValue(module);
    const previous = try js.get(engine, module, "nativeBuiltinThemeSources");
    if (!c.JS_IsUndefined(previous)) return previous;
    engine.freeValue(previous);
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    const root = try directory(engine);
    defer engine.gpa.free(root);
    inline for (sources, .{ "dark", "light" }) |asset, name| {
        const path = try paths.join(engine.gpa, &.{ root, asset.name }, flavor);
        defer engine.gpa.free(path);
        const raw = try std.Io.Dir.cwd().readFileAlloc(engine.native_io orelse return error.NativeIoUnavailable, path, engine.gpa, .limited(4 * 1024 * 1024));
        defer engine.gpa.free(raw);
        const input = if (std.mem.startsWith(u8, raw, "\xef\xbb\xbf")) raw[3..] else raw;
        const terminated = try engine.gpa.dupeZ(u8, input);
        defer engine.gpa.free(terminated);
        const parsed = try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, terminated.len, "builtin-theme.json"));
        engine.freeValue(parsed);
        try js.define(engine, result, name, try v.text(engine, input));
    }
    try js.define(engine, module, "nativeBuiltinThemeSources", c.JS_DupValue(engine.context, result));
    return result;
}
pub fn loadBuiltin(engine: *em.Engine, name: [:0]const u8, mode: ?@import("native_theme.zig").ColorMode) !c.JSValue {
    const values = try builtinSources(engine);
    defer engine.freeValue(values);
    const value = try js.get(engine, values, name);
    defer engine.freeValue(value);
    const raw = try engine.toString(value);
    defer engine.gpa.free(raw);
    return @import("native_theme.zig").fromJson(engine, raw, null, mode);
}
