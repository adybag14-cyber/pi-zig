//! Ordinary Source resolveExtensionSources body. Assembly also requires the real
//! resolvePackageSources body; this module does not stand in for that resolver.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Callback = enum(c_int) { builtin, package, entry };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const function = try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, dispatch, "resolveExtensionSources", 2, 0)));
    const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "resolveExtensionSources", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, manager: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, manager, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return mapped(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn mapped(engine: *em.Engine, kind: Callback, input: c.JSValue, selected_scope: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (kind == .entry) {
        const result = try scope.object();
        try scope.put(result, "pkg", input);
        try scope.put(result, "scope", selected_scope);
        return c.JS_DupValue(engine.context, result);
    }
    const found = try scope.invoke(input, "startsWith", &.{try scope.text("builtin:")});
    return if (kind == .builtin) c.JS_DupValue(engine.context, found) else c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(found)));
}
fn collection(scope: *Scope, values: c.JSValue, name: [*:0]const u8, kind: Callback, selected_scope: c.JSValue) !c.JSValue {
    const method = try scope.get(values, name);
    var roots = [_]c.JSValue{selected_scope};
    const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", 1, @intFromEnum(kind), roots.len, &roots)));
    return scope.call(method, values, &.{function});
}
fn begin(engine: *em.Engine, manager: c.JSValue, sources: c.JSValue, options: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, manager);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, manager, sources, options) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, manager: c.JSValue, sources: c.JSValue, options: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const accumulator = try scope.invoke(manager, "createAccumulator", &.{});
    try scope.put(owner, "accumulator", accumulator);
    const temporary = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "temporary");
    const selected_scope = try scope.text(if (scope.truthy(temporary)) "temporary" else selected: {
        const local = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "local");
        break :selected if (scope.truthy(local)) "project" else "user";
    });
    const builtins = try collection(&scope, sources, "filter", .builtin, selected_scope);
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var it = try js.Iterator.init(engine, builtins, symbol);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |source| {
        defer engine.freeValue(source);
        const add = try scope.get(manager, "addResource");
        const target = try scope.get(accumulator, "extensions");
        const metadata = try scope.object();
        try scope.put(metadata, "source", try scope.text("builtin"));
        try scope.put(metadata, "scope", selected_scope);
        try scope.put(metadata, "origin", try scope.text("top-level"));
        _ = try scope.call(add, manager, &.{ target, source, metadata, c.pi_js_bool(engine.context, 1) });
    }
    const packages = try collection(&scope, try collection(&scope, sources, "filter", .package, selected_scope), "map", .entry, selected_scope);
    try flow.wait(resolved, engine, owner, try scope.invoke(manager, "resolvePackageSources", &.{ packages, accumulator }), 0);
}
fn resolved(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const manager = try scope.get(owner, "agent");
    const to_resolved = try scope.get(manager, "toResolvedPaths");
    try flow.settle(engine, owner, false, try scope.call(to_resolved, manager, &.{try scope.get(owner, "accumulator")}));
}
