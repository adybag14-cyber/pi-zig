//! Actual session-export.ts branch serialization and synchronous export.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;

pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const function = try engine.checked(c.JS_NewCFunction(engine.context, callback, "exportToJsonl", 1));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "exportToJsonl", function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn callback(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const manager = sdk.get(engine, session, "sessionManager") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(manager);
    return exportBranch(engine, manager, if (argc > 0) argv[0] else c.pi_js_undefined(), c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn isoNow(scope: *Scope) !c.JSValue {
    const date = try scope.own(try js.builtin(scope.engine, "Date", &.{}));
    return scope.invoke(date, "toISOString", &.{});
}
fn iterator(scope: *Scope, value: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, value, try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context))));
}
pub fn serialize(engine: *em.Engine, manager: c.JSValue, trailing_entries: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const timestamp = try isoNow(&scope);
    const header = try scope.object();
    try scope.put(header, "type", try scope.text("session"));
    try scope.put(header, "version", c.JS_NewInt32(engine.context, 3));
    try scope.put(header, "id", try scope.invoke(manager, "getSessionId", &.{}));
    try scope.put(header, "timestamp", timestamp);
    try scope.put(header, "cwd", try scope.invoke(manager, "getCwd", &.{}));
    const entries = try scope.array();
    try scope.index(entries, 0, header);
    var parent = c.pi_js_null();
    var branch = try iterator(&scope, try scope.invoke(manager, "getBranch", &.{}));
    defer branch.deinit();
    errdefer branch.closePreserving();
    while (try branch.next()) |entry| {
        defer engine.freeValue(entry);
        var item: Scope = .{ .engine = engine };
        defer item.deinit();
        const copied = try item.own(try js.spread(engine, entry));
        try item.put(copied, "parentId", parent);
        _ = try item.invoke(entries, "push", &.{copied});
        parent = try scope.get(entry, "id");
    }
    const push = try scope.get(entries, "push");
    const trailing = if (temp.nullish(trailing_entries)) c.pi_js_undefined() else try scope.call(trailing_entries, c.pi_js_undefined(), &.{ parent, timestamp });
    _ = try scope.own(try @import("native_iterator_spread.zig").call(engine, entries, push, if (temp.nullish(trailing)) try scope.array() else trailing));
    const line = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, jsonLine, "", 1)));
    const lines = try scope.invoke(entries, "map", &.{line});
    const joined = try scope.invoke(lines, "join", &.{try scope.text("\n")});
    return c.JS_DupValue(engine.context, try scope.concat(joined, try scope.text("\n")));
}
fn jsonLine(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const json = scope.global("JSON") catch |err| return sdk.fail(engine, err);
    return js.invoke(engine, json, "stringify", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| sdk.fail(engine, err);
}
fn defaultPath(scope: *Scope) !c.JSValue {
    const timestamp = try isoNow(scope);
    const regexp = try scope.own(try js.builtin(scope.engine, "RegExp", &.{ try scope.text("[:.]"), try scope.text("g") }));
    const safe = try scope.invoke(timestamp, "replace", &.{ regexp, try scope.text("-") });
    return scope.concat(try scope.concat(try scope.text("session-"), safe), try scope.text(".jsonl"));
}
fn resolvePath(scope: *Scope, input: c.JSValue) !c.JSValue {
    const base = try scope.invoke(try scope.global("process"), "cwd", &.{});
    const normalized = try scope.own(try @import("native_sdk_settings.zig").normalizePath(scope.engine, input));
    const normalized_base = try scope.own(try @import("native_sdk_settings.zig").normalizePath(scope.engine, base));
    const path = try scope.engine.toString(normalized);
    defer scope.engine.gpa.free(path);
    const directory = try scope.engine.toString(normalized_base);
    defer scope.engine.gpa.free(directory);
    const resolved = try @import("node_path.zig").resolve(scope.engine.gpa, directory, &.{path}, if (builtin.os.tag == .windows) .win32 else .posix);
    defer scope.engine.gpa.free(resolved);
    return scope.text(resolved);
}
pub fn exportBranch(engine: *em.Engine, manager: c.JSValue, output_path: c.JSValue, trailing_entries: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = try resolvePath(&scope, if (temp.nullish(output_path)) try defaultPath(&scope) else output_path);
    const raw_path = try engine.toString(path);
    defer engine.gpa.free(raw_path);
    const directory = try scope.text(@import("node_path.zig").dirname(raw_path, if (builtin.os.tag == .windows) .win32 else .posix));
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, engine.native_io orelse return error.NativeSDKRequiresIO);
    const filesystem = engine.native_module_values.get("node:fs").?;
    if (!scope.truthy(try scope.invoke(filesystem, "existsSync", &.{directory}))) {
        const options = try scope.object();
        try scope.put(options, "recursive", c.pi_js_bool(engine.context, 1));
        _ = try scope.invoke(filesystem, "mkdirSync", &.{ directory, options });
    }
    const body = try scope.own(try serialize(engine, manager, trailing_entries));
    _ = try scope.invoke(filesystem, "writeFileSync", &.{ path, body });
    return c.JS_DupValue(engine.context, path);
}
