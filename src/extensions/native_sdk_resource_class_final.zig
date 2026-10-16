//! Ordinary Source final extension-set composition with preserved preload runtime/identity.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const replacement = @import("native_sdk_extension_replacements.zig");
const spread = @import("native_sdk_resource_spread.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Callback = enum(c_int) { noninline, pair, failed, remaining, inline_extension, ordered, present };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const function = try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, dispatch, "loadFinalExtensionSet", 2, 0)));
    if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "loadFinalExtensionSet", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, loader: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, loader, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return observed(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots) catch |err| sdk.fail(engine, err);
}
fn observed(engine: *em.Engine, kind: Callback, input: c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = switch (kind) {
        .noninline, .inline_extension => value: {
            const found = scope.truthy(try scope.invoke(try scope.get(input, "path"), "startsWith", &.{try scope.text("<inline:")}));
            break :value c.pi_js_bool(engine.context, @intFromBool(if (kind == .noninline) !found else found));
        },
        .pair => value: {
            const row = try scope.array();
            try scope.index(row, 0, try scope.get(input, "resolvedPath"));
            try scope.index(row, 1, input);
            break :value row;
        },
        .failed => value: {
            const method = try scope.get(roots[0], "resolveExtensionLoadPath");
            break :value try scope.call(method, roots[0], &.{try scope.get(input, "path")});
        },
        .remaining => value: {
            const resolved = try scope.invoke(roots[0], "resolveExtensionLoadPath", &.{input});
            const missing = !scope.truthy(try scope.invoke(roots[1], "has", &.{resolved})) and !scope.truthy(try scope.invoke(roots[2], "has", &.{resolved}));
            break :value c.pi_js_bool(engine.context, @intFromBool(missing));
        },
        .ordered => value: {
            const get = try scope.get(roots[1], "get");
            const resolved = try scope.invoke(roots[0], "resolveExtensionLoadPath", &.{input});
            break :value try scope.call(get, roots[1], &.{resolved});
        },
        .present => c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(input))),
    };
    return c.JS_DupValue(engine.context, value);
}
fn collection(scope: *Scope, values: c.JSValue, method: [*:0]const u8, kind: Callback, roots: []c.JSValue) !c.JSValue {
    const function = try scope.get(values, method);
    const mapped = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", 1, @intFromEnum(kind), @intCast(roots.len), roots.ptr)));
    return scope.call(function, values, &.{mapped});
}
fn optional(scope: *Scope, value: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(value)) c.pi_js_undefined() else scope.get(value, key);
}
fn defaultArray(scope: *Scope, value: c.JSValue) !c.JSValue {
    return if (temp.nullish(value)) scope.array() else value;
}
fn begin(engine: *em.Engine, loader: c.JSValue, paths: c.JSValue, pretrust: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, loader);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, loader, paths, pretrust) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, loader: c.JSValue, paths: c.JSValue, pretrust: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "paths", paths);
    try scope.put(owner, "pretrust", pretrust);
    const preloaded = try defaultArray(&scope, try optional(&scope, pretrust, "extensions"));
    try scope.put(owner, "preloaded", preloaded);
    const map_constructor = try scope.global("Map");
    const files = try collection(&scope, preloaded, "filter", .noninline, &.{});
    var map_args = [_]c.JSValue{try collection(&scope, files, "map", .pair, &.{})};
    const preloaded_map = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, map_constructor, map_args.len, &map_args)));
    try scope.put(owner, "preloadedMap", preloaded_map);
    const set_constructor = try scope.global("Set");
    var failed_roots = [_]c.JSValue{loader};
    const errors = try defaultArray(&scope, try optional(&scope, pretrust, "errors"));
    var set_args = [_]c.JSValue{try collection(&scope, errors, "map", .failed, &failed_roots)};
    const failed = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, set_constructor, set_args.len, &set_args)));
    var remaining_roots = [_]c.JSValue{ loader, preloaded_map, failed };
    const remaining = try collection(&scope, paths, "filter", .remaining, &remaining_roots);
    const load = try scope.get(loader, "loadExtensionPaths");
    try flow.wait(remainingLoaded, engine, owner, try scope.call(load, loader, &.{ remaining, try optional(&scope, pretrust, "runtime") }), 0);
}
fn remainingLoaded(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "remaining", value);
    const loader = try scope.get(owner, "agent");
    const loaded = try scope.own(try js.builtin(engine, "Map", &.{try scope.get(owner, "preloadedMap")}));
    try scope.put(owner, "loadedMap", loaded);
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var it = try js.Iterator.init(engine, try scope.get(value, "extensions"), symbol);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |extension| {
        defer engine.freeValue(extension);
        const set = try scope.get(loaded, "set");
        _ = try scope.call(set, loaded, &.{ try scope.get(extension, "resolvedPath"), extension });
    }
    if (scope.truthy(try scope.get(owner, "pretrust"))) {
        const inline_result = try scope.object();
        try scope.put(inline_result, "extensions", try collection(&scope, try scope.get(owner, "preloaded"), "filter", .inline_extension, &.{}));
        try scope.put(inline_result, "errors", try scope.array());
        return finish(engine, owner, inline_result);
    }
    const factories = try scope.get(loader, "loadExtensionFactories");
    try flow.wait(inlineLoaded, engine, owner, try scope.call(factories, loader, &.{try scope.get(value, "runtime")}), 0);
}
fn inlineLoaded(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    try finish(engine, owner, value);
}
fn finish(engine: *em.Engine, owner: c.JSValue, inline_result: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const loader = try scope.get(owner, "agent");
    var roots = [_]c.JSValue{ loader, try scope.get(owner, "loadedMap") };
    const mapped = try collection(&scope, try scope.get(owner, "paths"), "map", .ordered, &roots);
    const ordered = try collection(&scope, mapped, "filter", .present, &.{});
    const push = try scope.get(ordered, "push");
    _ = try spread.call(&scope, push, ordered, try scope.get(inline_result, "extensions"));
    const warnings = try scope.array();
    const result = try scope.object();
    try scope.put(result, "extensions", try replacement.omit(&scope, ordered, warnings));
    const pretrust = try scope.get(owner, "pretrust");
    const remaining = try scope.get(owner, "remaining");
    const errors = try scope.array();
    var index: u32 = 0;
    try spread.literal(&scope, errors, try defaultArray(&scope, try optional(&scope, pretrust, "errors")), &index);
    try spread.literal(&scope, errors, try scope.get(remaining, "errors"), &index);
    try spread.literal(&scope, errors, try scope.get(inline_result, "errors"), &index);
    try scope.put(result, "errors", errors);
    const combined_warnings = try scope.array();
    index = 0;
    try spread.literal(&scope, combined_warnings, try defaultArray(&scope, try optional(&scope, pretrust, "warnings")), &index);
    try spread.literal(&scope, combined_warnings, try defaultArray(&scope, try scope.get(remaining, "warnings")), &index);
    try scope.put(result, "warnings", combined_warnings);
    try scope.put(result, "runtime", try scope.get(remaining, "runtime"));
    try replacement.mergeWarnings(&scope, result, warnings);
    _ = try scope.invoke(loader, "addExtensionConflictDiagnostics", &.{result});
    try flow.settle(engine, owner, false, result);
}
