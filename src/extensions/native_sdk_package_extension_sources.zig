//! Ordinary Source resolveExtensionSources body. Assembly also requires the real
//! resolvePackageSources body; this module does not stand in for that resolver.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const af = @import("native_async_function.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Callback = enum(c_int) { builtin, package, entry };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const function = try scope.own(try af.createResumable(engine, "resolveExtensionSources", 2, dispatch, &.{}));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "resolveExtensionSources", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(engine: *em.Engine, manager: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, input) };
    if (completion == .fulfilled) return .{ .returned = try resolved(engine, state.*, manager) };
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const owner = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()))); af.replaceState(engine, state, c.JS_DupValue(engine.context, owner));
    return initialize(engine, owner, manager, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
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
fn initialize(engine: *em.Engine, owner: c.JSValue, manager: c.JSValue, sources: c.JSValue, options: c.JSValue) !af.Action {
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
    return .{ .awaited = c.JS_DupValue(engine.context, try scope.invoke(manager, "resolvePackageSources", &.{ packages, accumulator })) };
}
fn resolved(engine: *em.Engine, owner: c.JSValue, manager: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const to_resolved = try scope.get(manager, "toResolvedPaths");
    return js.call(engine, to_resolved, manager, &.{try scope.get(owner, "accumulator")});
}
