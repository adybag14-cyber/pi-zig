//! Ordinary Source resource path methods over observable loader fields.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Method = enum(c_int) { resolveExtensionLoadPath, normalizeExtensionPaths, mergePaths, resolveResourcePath };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, dispatch, field.name, if (field.value == @intFromEnum(Method.mergePaths)) 2 else 1, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn dispatch(context: ?*c.JSContext, loader: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return method(engine, loader, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn synthetic(scope: *Scope, path: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("builtin:")})) or scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("<")}));
}
fn resolved(scope: *Scope, loader: c.JSValue, path: c.JSValue, extension: bool) !c.JSValue {
    if (try synthetic(scope, path)) return path;
    const cwd = try scope.get(loader, "cwd");
    const options = try scope.object();
    try scope.put(options, if (extension) "normalizeUnicodeSpaces" else "trim", c.pi_js_bool(scope.engine.context, 1));
    return scope.own(try @import("native_sdk_source_paths.zig").resolve(scope.engine, path, cwd, options));
}
fn normalizedEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return entry(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn entry(engine: *em.Engine, loader: c.JSValue, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const metadata = if (scope.truthy(try scope.get(try scope.get(input, "metadata"), "baseDir"))) changed: {
        const copied = try scope.own(try js.spread(engine, try scope.get(input, "metadata")));
        const resolve = try scope.get(loader, "resolveResourcePath");
        const base = try scope.call(resolve, loader, &.{try scope.get(try scope.get(input, "metadata"), "baseDir")});
        try scope.put(copied, "baseDir", base);
        break :changed copied;
    } else try scope.get(input, "metadata");
    const result = try scope.object();
    const resolve = try scope.get(loader, "resolveResourcePath");
    try scope.put(result, "path", try scope.call(resolve, loader, &.{try scope.get(input, "path")}));
    try scope.put(result, "metadata", metadata);
    return c.JS_DupValue(engine.context, result);
}
fn canonical(scope: *Scope, path: c.JSValue) !c.JSValue {
    const raw = try scope.engine.toString(path);
    defer scope.engine.gpa.free(raw);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = std.Io.Dir.cwd().realPathFile(scope.engine.native_io orelse return error.NativeIoUnavailable, raw, &buffer) catch return path;
    return scope.text(buffer[0..count]);
}
fn append(scope: *Scope, output: c.JSValue, values: c.JSValue, count: *u32) !void {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, values, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        defer scope.engine.freeValue(value);
        try scope.index(output, count.*, value);
        count.* += 1;
    }
}
fn merged(scope: *Scope, loader: c.JSValue, primary: c.JSValue, additional: c.JSValue) !c.JSValue {
    const result = try scope.array();
    const seen = try scope.own(try js.builtin(scope.engine, "Set", &.{}));
    const all = try scope.array();
    var count: u32 = 0;
    try append(scope, all, primary, &count);
    try append(scope, all, additional, &count);
    for (0..count) |index| {
        const resolve = try scope.get(loader, "resolveResourcePath");
        const input = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, all, @intCast(index))));
        const path = try scope.call(resolve, loader, &.{input});
        const key = try canonical(scope, path);
        if (scope.truthy(try scope.invoke(seen, "has", &.{key}))) continue;
        _ = try scope.invoke(seen, "add", &.{key});
        _ = try scope.invoke(result, "push", &.{path});
    }
    return result;
}
fn method(engine: *em.Engine, loader: c.JSValue, kind: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const result = switch (kind) {
        .resolveExtensionLoadPath => try resolved(&scope, loader, first, true),
        .resolveResourcePath => try resolved(&scope, loader, first, false),
        .normalizeExtensionPaths => mapped: {
            const map = try scope.get(first, "map");
            var roots = [_]c.JSValue{loader};
            const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, normalizedEntry, "", 1, 0, roots.len, &roots)));
            break :mapped try scope.call(map, first, &.{callback});
        },
        .mergePaths => try merged(&scope, loader, first, if (args.len > 1) args[1] else c.pi_js_undefined()),
    };
    return c.JS_DupValue(engine.context, result);
}
