//! Ordinary Source updateThemesFromPaths, including synchronous override/cache order.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    try @import("native_tui.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const terminal = engine.native_module_values.get("pi-tui") orelse return error.ActualNativeTerminalExportsRequired;
    var roots = [_]c.JSValue{ try scope.get(terminal, "detectCapabilities"), try scope.get(terminal, "getTerminalColorMode") };
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "updateThemesFromPaths", 2, 0, roots.len, &roots));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "updateThemesFromPaths", function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn noProbe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, 0);
}
fn dispatch(context: ?*c.JSContext, loader: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    update(engine, loader, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), roots) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn mapped(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return attach(engine, roots[0], roots[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn attach(engine: *em.Engine, loader: c.JSValue, metadata: c.JSValue, theme: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = try scope.get(theme, "sourcePath");
    const info = if (scope.truthy(path)) selected: {
        const find = try scope.get(loader, "findSourceInfoForPath");
        const found = try scope.call(find, loader, &.{ path, try scope.get(loader, "extensionThemeSourceInfos"), metadata });
        if (!temp.nullish(found)) break :selected found;
        const existing = try scope.get(theme, "sourceInfo");
        if (!temp.nullish(existing)) break :selected existing;
        break :selected try scope.invoke(loader, "getDefaultSourceInfoForPath", &.{path});
    } else try scope.get(theme, "sourceInfo");
    try scope.set(theme, "sourceInfo", info);
    return c.JS_DupValue(engine.context, theme);
}
fn append(scope: *Scope, result: c.JSValue, values: c.JSValue, count: *u32) !void {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var it = try js.Iterator.init(scope.engine, values, symbol);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |value| {
        defer scope.engine.freeValue(value);
        try scope.index(result, count.*, value);
        count.* += 1;
    }
}
fn update(engine: *em.Engine, loader: c.JSValue, paths: c.JSValue, metadata: c.JSValue, imports: [*c]c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const base = try scope.object();
    if (scope.truthy(try scope.get(loader, "noThemes")) and scope.equal(try scope.get(paths, "length"), c.JS_NewInt32(engine.context, 0))) {
        try scope.put(base, "themes", try scope.array());
        try scope.put(base, "diagnostics", try scope.array());
    } else {
        const capabilities = try scope.object();
        const probe = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, noProbe, "", 0)));
        try js.spreadInto(engine, capabilities, try scope.call(imports[0], c.pi_js_undefined(), &.{probe}));
        const overrides = try scope.invoke(try scope.get(loader, "settingsManager"), "getTerminalCapabilityOverrides", &.{});
        try js.spreadInto(engine, capabilities, overrides);
        const color_mode = try scope.call(imports[1], c.pi_js_undefined(), &.{capabilities});
        const loaded = try scope.invoke(loader, "loadThemes", &.{ paths, c.pi_js_bool(engine.context, 0), color_mode });
        const dedupe = try scope.get(loader, "dedupeThemes");
        const deduped = try scope.call(dedupe, loader, &.{try scope.get(loaded, "themes")});
        try scope.put(base, "themes", try scope.get(deduped, "themes"));
        const diagnostics = try scope.array();
        var count: u32 = 0;
        try append(&scope, diagnostics, try scope.get(loaded, "diagnostics"), &count);
        try append(&scope, diagnostics, try scope.get(deduped, "diagnostics"), &count);
        try scope.put(base, "diagnostics", diagnostics);
    }
    const resolved = if (scope.truthy(try scope.get(loader, "themesOverride"))) try scope.invoke(loader, "themesOverride", &.{base}) else base;
    const themes = try scope.get(resolved, "themes");
    const map = try scope.get(themes, "map");
    var roots = [_]c.JSValue{ loader, metadata };
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, mapped, "", 1, 0, roots.len, &roots)));
    try scope.set(loader, "themes", try scope.call(map, themes, &.{callback}));
    try scope.set(loader, "themeDiagnostics", try scope.get(resolved, "diagnostics"));
}
