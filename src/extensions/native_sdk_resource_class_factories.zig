//! Actual ordinary async inline-factory loop. The genuine initializer is required
//! explicitly at installation; there is no legacy-factory or empty-result fallback.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const iterator = @import("native_sdk_resource_async_iterator.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn install(engine: *em.Engine, prototype: c.JSValue, load_extension_from_factory: c.JSValue) !void {
    if (!c.JS_IsFunction(engine.context, load_extension_from_factory)) return error.NativeResourceInitializerRequired;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{load_extension_from_factory};
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "loadExtensionFactories", 1, 0, roots.len, &roots)));
    if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "loadExtensionFactories", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, loader: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, loader, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, loader: c.JSValue, runtime: c.JSValue, initializer: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, loader);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, runtime, initializer) catch |err| try reject(engine, pending.owner, err);
    return pending.promise;
}
fn reject(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    iterator.closePreserving(engine, owner);
    try flow.rejectError(engine, owner, err);
}
fn initialize(engine: *em.Engine, owner: c.JSValue, runtime: c.JSValue, initializer: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "runtime", runtime);
    try scope.put(owner, "initializer", initializer);
    try scope.put(owner, "extensions", try scope.array());
    try scope.put(owner, "errors", try scope.array());
    const loader = try scope.get(owner, "agent");
    try iterator.retain(&scope, owner, try scope.invoke(try scope.get(loader, "extensionFactories"), "entries", &.{}));
    try advance(engine, owner);
}
fn pair(scope: *Scope, entry: c.JSValue) ![2]c.JSValue {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    const values = try js.pair(scope.engine, entry, symbol);
    const first = scope.own(values[0]) catch |err| {
        scope.engine.freeValue(values[1]);
        return err;
    };
    const second = try scope.own(values[1]);
    return .{ first, second };
}
fn attempt(scope: *Scope, owner: c.JSValue, factory: c.JSValue, path: c.JSValue) !c.JSValue {
    const loader = try scope.get(owner, "agent");
    return scope.call(try scope.get(owner, "initializer"), c.pi_js_undefined(), &.{ factory, try scope.get(loader, "cwd"), try scope.get(loader, "eventBus"), try scope.get(owner, "runtime"), path });
}
fn advance(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    while (try iterator.next(&scope, owner)) |raw| {
        const entry = try scope.own(raw);
        const values = try pair(&scope, entry);
        const named = !c.JS_IsFunction(engine.context, values[1]);
        const factory = if (named) try scope.get(values[1], "factory") else values[1];
        const identifier = if (named) try scope.get(values[1], "name") else try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, values[0], c.JS_NewInt32(engine.context, 1))));
        const path = try scope.concat(try scope.concat(try scope.text("<inline:"), try scope.stringify(identifier)), try scope.text(">"));
        try scope.put(owner, "input", values[1]);
        try scope.put(owner, "named", c.pi_js_bool(engine.context, @intFromBool(named)));
        try scope.put(owner, "path", path);
        const generation = engine.native_allocation_generation;
        const result = attempt(&scope, owner, factory, path) catch |err| {
            if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
            const reason = try scope.own(flow.reason(engine, err));
            clearException(engine);
            try failed(&scope, owner, reason);
            continue;
        };
        return flow.wait(loaded, engine, owner, result, 0);
    }
    const result = try scope.object();
    try scope.put(result, "extensions", try scope.get(owner, "extensions"));
    try scope.put(result, "errors", try scope.get(owner, "errors"));
    try flow.settle(engine, owner, false, result);
}
fn clearException(engine: *em.Engine) void {
    if (engine.captured_exception) |value| engine.freeValue(value);
    engine.captured_exception = null;
}
fn failed(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    const error_constructor = try scope.global("Error");
    const is_error = c.JS_IsInstanceOf(scope.engine.context, reason, error_constructor);
    if (is_error < 0) return js.capture(scope.engine);
    const message = if (is_error != 0) try scope.get(reason, "message") else try scope.text("failed to load extension");
    const errors = try scope.get(owner, "errors");
    const push = try scope.get(errors, "push");
    const row = try scope.object();
    try scope.put(row, "path", try scope.get(owner, "path"));
    try scope.put(row, "error", message);
    _ = try scope.call(push, errors, &.{row});
}
fn success(scope: *Scope, owner: c.JSValue, extension: c.JSValue) !void {
    const named = try scope.get(owner, "named");
    const input = try scope.get(owner, "input");
    try scope.set(extension, "hidden", if (scope.truthy(named)) try scope.get(input, "hidden") else named);
    try scope.set(extension, "replaceable", c.pi_js_bool(scope.engine.context, @intFromBool(scope.truthy(named) and scope.equal(try scope.get(input, "replaceable"), c.pi_js_bool(scope.engine.context, 1)))));
    _ = try scope.invoke(try scope.get(owner, "extensions"), "push", &.{extension});
}
fn loaded(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    continueLoaded(engine, owner, value, rejected) catch |err| try reject(engine, owner, err);
}
fn continueLoaded(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        try failed(&scope, owner, value);
    } else {
        const generation = engine.native_allocation_generation;
        success(&scope, owner, value) catch |err| {
            if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
            const reason = try scope.own(flow.reason(engine, err));
            clearException(engine);
            try failed(&scope, owner, reason);
        };
    }
    try advance(engine, owner);
}
