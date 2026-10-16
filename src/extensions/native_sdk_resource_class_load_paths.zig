//! Actual ordinary async disk/builtin loading. Both imported native loader
//! helpers are mandatory; this module supplies no controlled or empty loader.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const iterator = @import("native_sdk_resource_async_iterator.zig");
const c = em.c;
pub const Dependencies = struct { load_extensions_cached: c.JSValue, load_extension_from_factory: c.JSValue };
pub fn install(engine: *em.Engine, prototype: c.JSValue, deps: Dependencies) !void {
    if (!c.JS_IsFunction(engine.context, deps.load_extensions_cached) or !c.JS_IsFunction(engine.context, deps.load_extension_from_factory)) return error.NativeResourceLoaderHelpersRequired;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{ deps.load_extensions_cached, deps.load_extension_from_factory };
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "loadExtensionPaths", 2, 0, roots.len, &roots)));
    if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "loadExtensionPaths", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, loader: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, loader, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), roots) catch |err| sdk.fail(engine, err);
}
fn predicate(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return predicateValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic, roots) catch |err| sdk.fail(engine, err);
}
fn predicateValue(engine: *em.Engine, input: c.JSValue, mode: c_int, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (mode == 0) return c.JS_DupValue(engine.context, try scope.invoke(input, "startsWith", &.{try scope.text("builtin:")}));
    return c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(try scope.call(roots[0], c.pi_js_undefined(), &.{input}))));
}
fn begin(engine: *em.Engine, loader: c.JSValue, paths: c.JSValue, runtime: c.JSValue, deps: [*c]c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, loader);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, paths, runtime, deps) catch |err| try reject(engine, pending.owner, err);
    return pending.promise;
}
fn reject(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    iterator.closePreserving(engine, owner);
    try flow.rejectError(engine, owner, err);
}
fn initialize(engine: *em.Engine, owner: c.JSValue, paths: c.JSValue, runtime: c.JSValue, deps: [*c]c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "paths", paths);
    try scope.put(owner, "initializer", deps[1]);
    const builtin = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, predicate, "isBuiltinPath", 1, 0, 0, null)));
    try scope.put(owner, "isBuiltinPath", builtin);
    const filter = try scope.get(paths, "filter");
    var roots = [_]c.JSValue{builtin};
    const nonbuiltin = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, predicate, "", 1, 1, roots.len, &roots)));
    const disk_paths = try scope.call(filter, paths, &.{nonbuiltin});
    const loader = try scope.get(owner, "agent");
    const result = try scope.call(deps[0], c.pi_js_undefined(), &.{ disk_paths, try scope.get(loader, "cwd"), try scope.get(loader, "eventBus"), runtime });
    try flow.wait(diskLoaded, engine, owner, result, 0);
}
fn diskLoaded(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    startBuiltins(engine, owner, value) catch |err| try reject(engine, owner, err);
}
fn startBuiltins(engine: *em.Engine, owner: c.JSValue, result: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "result", result);
    const paths = try scope.get(owner, "paths");
    try iterator.retain(&scope, owner, try scope.invoke(paths, "filter", &.{try scope.get(owner, "isBuiltinPath")}));
    try advance(engine, owner);
}
fn addError(scope: *Scope, owner: c.JSValue, reason: ?c.JSValue) !void {
    const errors = try scope.get(try scope.get(owner, "result"), "errors");
    const push = try scope.get(errors, "push");
    const row = try scope.object();
    const path = try scope.get(owner, "path");
    try scope.put(row, "path", path);
    const message = if (reason) |value| message: {
        const instance = c.JS_IsInstanceOf(scope.engine.context, value, try scope.global("Error"));
        if (instance < 0) return js.capture(scope.engine);
        break :message if (instance != 0) try scope.get(value, "message") else try scope.text("failed to load extension");
    } else try scope.concat(try scope.text("Unknown built-in extension: "), try scope.stringify(path));
    try scope.put(row, "error", message);
    _ = try scope.call(push, errors, &.{row});
}
fn attempt(scope: *Scope, owner: c.JSValue, builtin: c.JSValue, path: c.JSValue) !c.JSValue {
    const initializer = try scope.get(owner, "initializer");
    const factory = try scope.get(builtin, "factory");
    const loader = try scope.get(owner, "agent");
    return scope.call(initializer, c.pi_js_undefined(), &.{ factory, try scope.get(loader, "cwd"), try scope.get(loader, "eventBus"), try scope.get(try scope.get(owner, "result"), "runtime"), path });
}
fn clearException(engine: *em.Engine) void {
    if (engine.captured_exception) |value| engine.freeValue(value);
    engine.captured_exception = null;
}
fn advance(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    while (try iterator.next(&scope, owner)) |raw| {
        const path = try scope.own(raw);
        const loader = try scope.get(owner, "agent");
        const builtins = try scope.get(loader, "builtinExtensions");
        const get = try scope.get(builtins, "get");
        const name = try scope.invoke(path, "slice", &.{c.JS_NewInt32(engine.context, 8)});
        const builtin = try scope.call(get, builtins, &.{name});
        try scope.put(owner, "path", path);
        if (!scope.truthy(builtin)) {
            try addError(&scope, owner, null);
            continue;
        }
        try scope.put(owner, "builtin", builtin);
        const generation = engine.native_allocation_generation;
        const result = attempt(&scope, owner, builtin, path) catch |err| {
            if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
            const reason = try scope.own(flow.reason(engine, err));
            clearException(engine);
            try addError(&scope, owner, reason);
            continue;
        };
        return flow.wait(builtinLoaded, engine, owner, result, 0);
    }
    try flow.settle(engine, owner, false, try scope.get(owner, "result"));
}
fn success(scope: *Scope, owner: c.JSValue, extension: c.JSValue) !void {
    try scope.set(extension, "hidden", c.pi_js_bool(scope.engine.context, 1));
    try scope.set(extension, "replaceable", c.pi_js_bool(scope.engine.context, @intFromBool(scope.equal(try scope.get(try scope.get(owner, "builtin"), "replaceable"), c.pi_js_bool(scope.engine.context, 1)))));
    _ = try scope.invoke(try scope.get(try scope.get(owner, "result"), "extensions"), "push", &.{extension});
}
fn builtinLoaded(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    continueBuiltin(engine, owner, value, rejected) catch |err| try reject(engine, owner, err);
}
fn continueBuiltin(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        try addError(&scope, owner, value);
    } else {
        const generation = engine.native_allocation_generation;
        success(&scope, owner, value) catch |err| {
            if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
            const reason = try scope.own(flow.reason(engine, err));
            clearException(engine);
            try addError(&scope, owner, reason);
        };
    }
    try advance(engine, owner);
}
