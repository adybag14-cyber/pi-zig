//! Ordinary Source theme discovery methods, using real native Theme instances.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const theme = @import("native_theme.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Method = enum(c_int) { loadThemes, loadThemesFromDir, loadThemeFromFile };
const Import = enum(usize) { join, exists, stat, readdir };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const io = engine.native_io orelse return error.NativeResourceThemesRequireIo;
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = engine.native_module_values.get("node:path").?;
    const fs = engine.native_module_values.get("node:fs").?;
    var roots = [_]c.JSValue{ try scope.get(path, "join"), try scope.get(fs, "existsSync"), try scope.get(fs, "statSync"), try scope.get(fs, "readdirSync") };
    inline for (std.meta.fields(Method)) |field| {
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, if (field.value == @intFromEnum(Method.loadThemes)) 3 else 4, field.value, roots.len, &roots));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn dispatch(context: ?*c.JSContext, loader: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return method(engine, loader, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots) catch |err| sdk.fail(engine, err);
}
fn imported(scope: *Scope, roots: [*c]c.JSValue, kind: Import, args: []const c.JSValue) !c.JSValue {
    return scope.call(roots[@intFromEnum(kind)], c.pi_js_undefined(), args);
}
fn iterator(scope: *Scope, value: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, value, try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context))));
}
fn warning(scope: *Scope, diagnostics: c.JSValue, message: c.JSValue, path: c.JSValue) !void {
    const push = try scope.get(diagnostics, "push");
    const row = try scope.object();
    try scope.put(row, "type", try scope.text("warning"));
    try scope.put(row, "message", message);
    try scope.put(row, "path", path);
    _ = try scope.call(push, diagnostics, &.{row});
}
fn discard(scope: *Scope, err: anyerror, generation: u64) !void {
    const original = scope.engine.nativeAllocationError(err, generation);
    if (original == error.OutOfMemory) return original;
    if (scope.engine.captured_exception) |value| scope.engine.freeValue(value);
    scope.engine.captured_exception = null;
}
fn caught(scope: *Scope, err: anyerror, generation: u64, diagnostics: c.JSValue, path: c.JSValue, fallback: []const u8) !void {
    const original = scope.engine.nativeAllocationError(err, generation);
    if (original == error.OutOfMemory) return original;
    const reason = try scope.own(flow.reason(scope.engine, original));
    if (scope.engine.captured_exception) |value| scope.engine.freeValue(value);
    scope.engine.captured_exception = null;
    const error_constructor = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, error_constructor);
    if (instance < 0) return js.capture(scope.engine);
    const message = if (instance != 0) try scope.get(reason, "message") else try scope.text(fallback);
    try warning(scope, diagnostics, message, path);
}
fn loadFile(scope: *Scope, path: c.JSValue, themes: c.JSValue, diagnostics: c.JSValue, mode: c.JSValue) !void {
    const generation = scope.engine.native_allocation_generation;
    loadFileBody(scope, path, themes, mode) catch |err| try caught(scope, err, generation, diagnostics, path, "failed to load theme");
}
fn loadFileBody(scope: *Scope, path: c.JSValue, themes: c.JSValue, mode: c.JSValue) !void {
    const push = try scope.get(themes, "push");
    const raw = try scope.engine.toString(path);
    defer scope.engine.gpa.free(raw);
    const color_mode: ?theme.ColorMode = if (c.JS_IsUndefined(mode)) null else value: {
        const name = try scope.engine.toString(mode);
        defer scope.engine.gpa.free(name);
        break :value std.meta.stringToEnum(theme.ColorMode, name) orelse return error.InvalidResourceThemeColorMode;
    };
    const loaded = try scope.own(try theme.loadFile(scope.engine, scope.engine.native_io orelse return error.NativeIoUnavailable, raw, color_mode));
    _ = try scope.call(push, themes, &.{loaded});
}
fn symlinkIsFile(scope: *Scope, roots: [*c]c.JSValue, dir: c.JSValue, entry: c.JSValue) !bool {
    const path = try imported(scope, roots, .join, &.{ dir, try scope.get(entry, "name") });
    return scope.truthy(try scope.invoke(try imported(scope, roots, .stat, &.{path}), "isFile", &.{}));
}
fn directoryBody(scope: *Scope, roots: [*c]c.JSValue, loader: c.JSValue, dir: c.JSValue, themes: c.JSValue, diagnostics: c.JSValue, mode: c.JSValue) !void {
    const options = try scope.object();
    try scope.put(options, "withFileTypes", c.pi_js_bool(scope.engine.context, 1));
    const entries = try imported(scope, roots, .readdir, &.{ dir, options });
    var it = try iterator(scope, entries);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var is_file = scope.truthy(try scope.invoke(entry, "isFile", &.{}));
        if (scope.truthy(try scope.invoke(entry, "isSymbolicLink", &.{}))) {
            const generation = scope.engine.native_allocation_generation;
            is_file = symlinkIsFile(scope, roots, dir, entry) catch |err| {
                try discard(scope, err, generation);
                continue;
            };
        }
        if (!is_file) continue;
        if (!scope.truthy(try scope.invoke(try scope.get(entry, "name"), "endsWith", &.{try scope.text(".json")}))) continue;
        const load_function = try scope.get(loader, "loadThemeFromFile");
        const path = try imported(scope, roots, .join, &.{ dir, try scope.get(entry, "name") });
        _ = try scope.call(load_function, loader, &.{ path, themes, diagnostics, mode });
    }
}
fn directory(scope: *Scope, roots: [*c]c.JSValue, loader: c.JSValue, dir: c.JSValue, themes: c.JSValue, diagnostics: c.JSValue, mode: c.JSValue) !void {
    if (!scope.truthy(try imported(scope, roots, .exists, &.{dir}))) return;
    const generation = scope.engine.native_allocation_generation;
    directoryBody(scope, roots, loader, dir, themes, diagnostics, mode) catch |err| try caught(scope, err, generation, diagnostics, dir, "failed to read theme directory");
}
fn pathBody(scope: *Scope, roots: [*c]c.JSValue, loader: c.JSValue, path: c.JSValue, themes: c.JSValue, diagnostics: c.JSValue, mode: c.JSValue) !void {
    const stats = try imported(scope, roots, .stat, &.{path});
    if (scope.truthy(try scope.invoke(stats, "isDirectory", &.{}))) {
        _ = try scope.invoke(loader, "loadThemesFromDir", &.{ path, themes, diagnostics, mode });
    } else if (scope.truthy(try scope.invoke(stats, "isFile", &.{})) and scope.truthy(try scope.invoke(path, "endsWith", &.{try scope.text(".json")}))) {
        _ = try scope.invoke(loader, "loadThemeFromFile", &.{ path, themes, diagnostics, mode });
    } else try warning(scope, diagnostics, try scope.text("theme path is not a json file"), path);
}
fn load(scope: *Scope, roots: [*c]c.JSValue, loader: c.JSValue, paths: c.JSValue, defaults: c.JSValue, mode: c.JSValue) !c.JSValue {
    const themes = try scope.array();
    const diagnostics = try scope.array();
    if (scope.truthy(defaults)) {
        const dirs = try scope.array();
        try scope.index(dirs, 0, try imported(scope, roots, .join, &.{ try scope.get(loader, "agentDir"), try scope.text("themes") }));
        try scope.index(dirs, 1, try imported(scope, roots, .join, &.{ try scope.get(loader, "cwd"), try scope.text(".pi"), try scope.text("themes") }));
        var it = try iterator(scope, dirs);
        defer it.deinit();
        errdefer it.closePreserving();
        while (try it.next()) |dir| {
            defer scope.engine.freeValue(dir);
            _ = try scope.invoke(loader, "loadThemesFromDir", &.{ dir, themes, diagnostics, mode });
        }
    }
    var it = try iterator(scope, paths);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |input| {
        defer scope.engine.freeValue(input);
        const path = try scope.invoke(loader, "resolveResourcePath", &.{input});
        if (!scope.truthy(try imported(scope, roots, .exists, &.{path}))) {
            try warning(scope, diagnostics, try scope.text("theme path does not exist"), path);
            continue;
        }
        const generation = scope.engine.native_allocation_generation;
        pathBody(scope, roots, loader, path, themes, diagnostics, mode) catch |err| try caught(scope, err, generation, diagnostics, path, "failed to read theme path");
    }
    const result = try scope.object();
    try scope.put(result, "themes", themes);
    try scope.put(result, "diagnostics", diagnostics);
    return result;
}
fn method(engine: *em.Engine, loader: c.JSValue, kind: Method, args: []const c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else c.pi_js_undefined();
    const third = if (args.len > 2) args[2] else c.pi_js_undefined();
    const fourth = if (args.len > 3) args[3] else c.pi_js_undefined();
    switch (kind) {
        .loadThemes => return c.JS_DupValue(engine.context, try load(&scope, roots, loader, first, second, third)),
        .loadThemesFromDir => try directory(&scope, roots, loader, first, second, third, fourth),
        .loadThemeFromFile => try loadFile(&scope, first, second, third, fourth),
    }
    return c.pi_js_undefined();
}
