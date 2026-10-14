//! Ordinary upstream reload body. resetApiProviders is the captured binding of
//! the same native AI module used by the application's provider stream calls.
//! This installer does not create a private substitute provider registry.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Stage = enum(c_int) { shutdown, settings, resources, before_start, started, extended };

pub fn install(engine: *em.Engine, prototype: c.JSValue, reset_api_providers: c.JSValue) !void {
    if (!c.JS_IsFunction(engine.context, reset_api_providers)) return error.RequiredSharedNativeApiProviderReset;
    var roots = [_]c.JSValue{reset_api_providers};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "reload", 1, 0, roots.len, &roots));
    defer engine.freeValue(function);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "reload", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, session, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn event(scope: *Scope, kind: []const u8) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "type", try scope.text(kind));
    try scope.put(result, "reason", try scope.text("reload"));
    return result;
}
fn begin(engine: *em.Engine, session: c.JSValue, options: c.JSValue, reset: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, options, reset) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, options: c.JSValue, reset: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const runner = try scope.get(session, "_extensionRunner");
    try scope.put(owner, "oldRunner", runner);
    try scope.put(owner, "options", options);
    try scope.put(owner, "reset", reset);
    try scope.put(owner, "flagValues", try scope.invoke(runner, "getFlagValues", &.{}));
    // emitSessionShutdownEvent is itself async, including the no-handler path.
    const shutdown = try emitShutdown(engine, runner, try event(&scope, "session_shutdown"));
    defer engine.freeValue(shutdown);
    try flow.wait(step, engine, owner, shutdown, @intFromEnum(Stage.shutdown));
}
fn emitShutdown(engine: *em.Engine, runner: c.JSValue, shutdown_event: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, runner);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    emitShutdownStart(engine, pending.owner, shutdown_event) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn emitShutdownStart(engine: *em.Engine, owner: c.JSValue, shutdown_event: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runner = try scope.get(owner, "agent");
    if (scope.truthy(try scope.invoke(runner, "hasHandlers", &.{try scope.text("session_shutdown")}))) {
        try flow.wait(shutdownDone, engine, owner, try scope.invoke(runner, "emit", &.{shutdown_event}), 0);
    } else try flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
}
fn shutdownDone(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, if (rejected) value else c.pi_js_bool(engine.context, 1));
}
fn defaultTools(scope: *Scope, session: c.JSValue) !c.JSValue {
    if (!scope.truthy(try scope.get(session, "_usesDefaultTools"))) return scope.array();
    var defaults = try scope.invoke(try scope.get(session, "settingsManager"), "getDefaultTools", &.{});
    if (temp.nullish(defaults)) {
        defaults = try scope.array();
        inline for (.{ "read", "bash", "edit", "write" }, 0..) |name, index| try scope.index(defaults, index, try scope.text(name));
    }
    return scope.own(try @import("native_sdk_tool_modifiers.zig").apply(scope.engine, defaults, try scope.get(session, "_defaultToolModifiers")));
}
fn added(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const found = scope.invoke(roots[0], "has", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(found)));
}
fn appendIterable(scope: *Scope, output: c.JSValue, source: c.JSValue, position: *u32) !void {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, source, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        defer scope.engine.freeValue(value);
        try scope.index(output, position.*, value);
        position.* += 1;
    }
}
fn step(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, magic: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    switch (@as(Stage, @enumFromInt(magic))) {
        .shutdown => {
            _ = try scope.invoke(try scope.get(owner, "oldRunner"), "invalidate", &.{});
            const set = try scope.global("Set");
            var args = [_]c.JSValue{try defaultTools(&scope, session)};
            const previous = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, set, args.len, &args)));
            try scope.put(owner, "previous", previous);
            try flow.wait(step, engine, owner, try scope.invoke(try scope.get(session, "settingsManager"), "reload", &.{}), @intFromEnum(Stage.settings));
        },
        .settings => {
            _ = try scope.invoke(session, "syncQueueModesFromSettings", &.{});
            _ = try scope.call(try scope.get(owner, "reset"), c.pi_js_undefined(), &.{});
            try flow.wait(step, engine, owner, try scope.invoke(try scope.get(session, "_resourceLoader"), "reload", &.{}), @intFromEnum(Stage.resources));
        },
        .resources => {
            const defaults = try defaultTools(&scope, session);
            const filter = try scope.get(defaults, "filter");
            var roots = [_]c.JSValue{try scope.get(owner, "previous")};
            const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, added, "", 1, 0, roots.len, &roots)));
            const additions = try scope.call(filter, defaults, &.{callback});
            const current = try scope.invoke(session, "getActiveToolNames", &.{});
            const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
            var iterator = try js.Iterator.init(engine, current, symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |name| {
                defer engine.freeValue(name);
                _ = try scope.invoke(try scope.get(session, "_pendingToolNames"), "add", &.{name});
            }
            const build = try scope.get(session, "_buildRuntime");
            const options = try scope.object();
            const names = try scope.array();
            var position: u32 = 0;
            try appendIterable(&scope, names, try scope.invoke(session, "getActiveToolNames", &.{}), &position);
            try appendIterable(&scope, names, additions, &position);
            try scope.put(options, "activeToolNames", names);
            try scope.put(options, "flagValues", try scope.get(owner, "flagValues"));
            try scope.put(options, "includeAllExtensionTools", c.pi_js_bool(engine.context, 1));
            _ = try scope.call(build, session, &.{options});
            var bound = false;
            inline for (.{ "_extensionUIContext", "_extensionCommandContextActions", "_extensionShutdownHandler", "_extensionErrorListener" }) |name| {
                if (!bound) bound = scope.truthy(try scope.get(session, name));
            }
            if (!bound) return flow.settle(engine, owner, false, c.pi_js_undefined());
            const supplied = try scope.get(owner, "options");
            var before = c.pi_js_undefined();
            if (!temp.nullish(supplied)) {
                const function = try scope.get(supplied, "beforeSessionStart");
                if (!temp.nullish(function)) before = try scope.call(function, supplied, &.{});
            }
            try flow.wait(step, engine, owner, before, @intFromEnum(Stage.before_start));
        },
        .before_start => try flow.wait(step, engine, owner, try scope.invoke(try scope.get(session, "_extensionRunner"), "emit", &.{try event(&scope, "session_start")}), @intFromEnum(Stage.started)),
        .started => {
            _ = try scope.invoke(try scope.get(session, "_extensionRunner"), "reportUnhandledMcpServers", &.{});
            try flow.wait(step, engine, owner, try scope.invoke(session, "extendResourcesFromExtensions", &.{try scope.text("reload")}), @intFromEnum(Stage.extended));
        },
        .extended => try flow.settle(engine, owner, false, c.pi_js_undefined()),
    }
}
