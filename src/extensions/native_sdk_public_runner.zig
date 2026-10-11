//! Public ExtensionRunner construction over actual supplied JavaScript refs.
//! Only real method bodies are installed; the remaining async/UI/shortcut
//! contracts stay absent and explicitly inventoried until ported.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    if (engine.native_sdk_command_runner_constructor) |constructor| return sdk.put(engine, exports, "ExtensionRunner", c.JS_DupValue(engine.context, constructor));
    const prototype = try @import("native_sdk_command_runner.zig").getPrototype(engine);
    defer engine.freeValue(prototype);
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, construct, "ExtensionRunner", 5, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(constructor);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    engine.native_sdk_command_runner_constructor = c.JS_DupValue(engine.context, constructor);
    try sdk.put(engine, exports, "ExtensionRunner", c.JS_DupValue(engine.context, constructor));
}
fn construct(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return create(engine, target, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
pub fn create(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var prototype = if (c.JS_IsObject(target)) try sdk.get(engine, target, "prototype") else c.pi_js_undefined();
    defer engine.freeValue(prototype);
    if (!c.JS_IsObject(prototype)) {
        engine.freeValue(prototype);
        prototype = try @import("native_sdk_command_runner.zig").getPrototype(engine);
    }
    const runner = try engine.checked(c.JS_NewObjectProto(engine.context, prototype));
    errdefer engine.freeValue(runner);
    inline for (.{ "extensions", "runtime", "uiContext", "mode", "cwd", "sessionManager", "modelRegistry" }, 0..) |name, index| {
        const value = switch (index) {
            2 => try @import("native_sdk_ui_context.zig").noop(engine),
            3 => try sdk.text(engine, "print"),
            else => borrowed: {
                const parameter = switch (index) {
                    0 => 0,
                    1 => 1,
                    4 => 2,
                    5 => 3,
                    else => 4,
                };
                break :borrowed if (parameter < args.len) c.JS_DupValue(engine.context, args[parameter]) else c.pi_js_undefined();
            },
        };
        try sdk.put(engine, runner, name, value);
    }
    try sdk.put(engine, runner, "errorListeners", try js.builtin(engine, "Set", &.{}));
    inline for (std.meta.fields(Default)) |field| {
        if (field.value == @intFromEnum(Default.getCallableToolsFn)) try sdk.put(engine, runner, "executeToolFn", c.pi_js_undefined());
        if (field.value == @intFromEnum(Default.newSessionHandler)) try sdk.put(engine, runner, "reportedMcpServers", try js.builtin(engine, "Set", &.{}));
        var roots = [_]c.JSValue{runner};
        try sdk.put(engine, runner, field.name, try engine.checked(c.JS_NewCFunctionData2(engine.context, defaultCall, field.name, 0, field.value, roots.len, &roots)));
    }
    try sdk.put(engine, runner, "shortcutDiagnostics", try sdk.array(engine));
    try sdk.put(engine, runner, "commandDiagnostics", try sdk.array(engine));
    try sdk.put(engine, runner, "staleMessage", c.pi_js_undefined());
    try sdk.put(engine, runner, "uiPromptDepth", c.JS_NewInt32(engine.context, 0));
    try sdk.put(engine, runner, "activeUIPrompt", c.pi_js_undefined());
    return runner;
}
const Default = enum(c_int) { getModel, getScopedModels, isIdleFn, isProjectTrustedFn, getSignalFn, waitForIdleFn, abortFn, hasPendingMessagesFn, getContextUsageFn, compactFn, getSystemPromptFn, getSystemPromptOptionsFn, getCallableToolsFn, newSessionHandler, forkHandler, navigateTreeHandler, switchSessionHandler, reloadHandler, shutdownHandler };
fn defaultCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return defaultValue(engine, @enumFromInt(magic), roots[0]) catch |err| sdk.fail(engine, err);
}
fn defaultValue(engine: *em.Engine, operation: Default, runner: c.JSValue) !c.JSValue {
    return switch (operation) {
        .getScopedModels, .getCallableToolsFn => sdk.array(engine),
        .isIdleFn, .isProjectTrustedFn => c.pi_js_bool(engine.context, 1),
        .hasPendingMessagesFn => c.pi_js_bool(engine.context, 0),
        .getSystemPromptFn => sdk.text(engine, ""),
        .getSystemPromptOptionsFn => defaultOptions(engine, runner),
        .waitForIdleFn, .reloadHandler => sdk.promise(engine, c.pi_js_undefined()),
        .newSessionHandler, .forkHandler, .navigateTreeHandler, .switchSessionHandler => cancelled: {
            const result = try sdk.object(engine);
            defer engine.freeValue(result);
            try sdk.put(engine, result, "cancelled", c.pi_js_bool(engine.context, 0));
            break :cancelled sdk.promise(engine, result);
        },
        else => c.pi_js_undefined(),
    };
}
pub fn defaultOptions(engine: *em.Engine, runner: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "customPrompt", c.pi_js_undefined());
    try sdk.put(engine, result, "forceSystemPrompt", c.pi_js_undefined());
    const selected = try sdk.array(engine);
    inline for (.{ "read", "bash", "edit", "write" }) |name| try sdk.append(engine, selected, try sdk.text(engine, name));
    try sdk.put(engine, result, "selectedTools", selected);
    try sdk.put(engine, result, "hiddenTools", try sdk.array(engine));
    try sdk.put(engine, result, "toolSnippets", try sdk.object(engine));
    try sdk.put(engine, result, "toolGuidelines", try sdk.object(engine));
    try sdk.put(engine, result, "promptGuidelines", try sdk.array(engine));
    try sdk.put(engine, result, "appendSystemPrompt", try sdk.text(engine, ""));
    try sdk.put(engine, result, "sections", try sdk.object(engine));
    try sdk.put(engine, result, "cwd", try sdk.get(engine, runner, "cwd"));
    try sdk.put(engine, result, "contextFiles", try sdk.array(engine));
    try sdk.put(engine, result, "skills", try sdk.array(engine));
    return result;
}
const Method = enum(c_int) { bindCore, bindCommandContext, setUIContext, wrapUIPromptContext, getUIContext, hasUI, getExtensionPaths, getAllRegisteredTools, getToolDefinition, getFlags, setFlagValue, getFlagValues, getShortcutDiagnostics, invalidate, assertActive, onError, emitError, reportUnhandledMcpServers, hasHandlers, getMessageRenderer, getMarkdownTransformers, resolveToolRenderers, getEntryRenderer, getModelRegistry, shutdown, getActiveTools, createContext, createToolContext, createCommandContext, withUIPrompt, emitUIPromptEvent };
pub fn installPrototype(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| {
        const kind: Method = @enumFromInt(field.value);
        const arity: c_int = switch (kind) {
            .bindCore, .withUIPrompt => 3,
            .setFlagValue, .createToolContext, .resolveToolRenderers => 2,
            .bindCommandContext, .setUIContext, .wrapUIPromptContext, .getToolDefinition, .onError, .emitError, .hasHandlers, .getMessageRenderer, .getEntryRenderer, .emitUIPromptEvent => 1,
            else => 0,
        };
        const function = try engine.checked(c.pi_js_function_magic(engine.context, method, field.name, arity, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    }
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return methodValue(engine, receiver, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn assign(engine: *em.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_SetPropertyStr(engine.context, object, name, value) < 0) return js.capture(engine);
}
fn methodValue(engine: *em.Engine, runner: c.JSValue, operation: Method, args: []const c.JSValue) !c.JSValue {
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    switch (operation) {
        .withUIPrompt => return @import("native_sdk_public_runner_ui_prompts.zig").withPrompt(engine, runner, first, if (args.len > 1) args[1] else c.pi_js_undefined(), if (args.len > 2) args[2] else c.pi_js_undefined()),
        .emitUIPromptEvent => return @import("native_sdk_public_runner_ui_prompts.zig").queue(engine, runner, first),
        .bindCore => return @import("native_sdk_public_runner_core.zig").bind(engine, runner, args),
        .reportUnhandledMcpServers => return @import("native_sdk_public_runner_mcp.zig").report(engine, runner),
        .assertActive => {
            const stale = try sdk.get(engine, runner, "staleMessage");
            defer engine.freeValue(stale);
            if (c.JS_ToBool(engine.context, stale) == 1) return engine.checked(c.JS_Throw(engine.context, try js.builtin(engine, "Error", &.{stale})));
            return c.pi_js_undefined();
        },
        .invalidate => {
            const stale = try sdk.get(engine, runner, "staleMessage");
            defer engine.freeValue(stale);
            if (c.JS_ToBool(engine.context, stale) != 1) {
                const message = if (c.JS_IsUndefined(first)) try sdk.text(engine, @import("native_context_lifetime.zig").default_message) else c.JS_DupValue(engine.context, first);
                defer engine.freeValue(message);
                try assign(engine, runner, "staleMessage", c.JS_DupValue(engine.context, message));
                const runtime = try sdk.get(engine, runner, "runtime");
                defer engine.freeValue(runtime);
                const ignored = try js.invoke(engine, runtime, "invalidate", &.{message});
                engine.freeValue(ignored);
            }
            return c.pi_js_undefined();
        },
        .getUIContext => return sdk.get(engine, runner, "uiContext"),
        .hasUI => {
            const current = try sdk.get(engine, runner, "uiContext");
            defer engine.freeValue(current);
            const noop = try @import("native_sdk_ui_context.zig").noop(engine);
            defer engine.freeValue(noop);
            return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsStrictEqual(engine.context, current, noop)));
        },
        .setUIContext => {
            const wrapped = if (c.JS_ToBool(engine.context, first) == 1) try wrapUI(engine, runner, first) else try @import("native_sdk_ui_context.zig").noop(engine);
            try assign(engine, runner, "uiContext", wrapped);
            try assign(engine, runner, "mode", if (args.len < 2 or c.JS_IsUndefined(args[1])) try sdk.text(engine, "print") else c.JS_DupValue(engine.context, args[1]));
            return c.pi_js_undefined();
        },
        .wrapUIPromptContext => return wrapUI(engine, runner, first),
        .getModelRegistry => return sdk.get(engine, runner, "modelRegistry"),
        .getShortcutDiagnostics => return sdk.get(engine, runner, "shortcutDiagnostics"),
        .shutdown => {
            const ignored = try js.invoke(engine, runner, "shutdownHandler", &.{});
            engine.freeValue(ignored);
            return c.pi_js_undefined();
        },
        .getActiveTools => {
            const checked = try js.invoke(engine, runner, "assertActive", &.{});
            engine.freeValue(checked);
            const runtime = try sdk.get(engine, runner, "runtime");
            defer engine.freeValue(runtime);
            return js.invoke(engine, runtime, "getActiveTools", &.{});
        },
        .onError => {
            const listeners = try sdk.get(engine, runner, "errorListeners");
            defer engine.freeValue(listeners);
            const ignored = try js.invoke(engine, listeners, "add", &.{first});
            engine.freeValue(ignored);
            var roots = [_]c.JSValue{ runner, first };
            return engine.checked(c.JS_NewCFunctionData2(engine.context, unsubscribe, "", 0, 0, roots.len, &roots));
        },
        .emitError => {
            const listeners = try sdk.get(engine, runner, "errorListeners");
            defer engine.freeValue(listeners);
            const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
            defer engine.freeValue(symbol);
            var iterator = try js.Iterator.init(engine, listeners, symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |listener| {
                defer engine.freeValue(listener);
                const ignored = try js.call(engine, listener, c.pi_js_undefined(), &.{first});
                engine.freeValue(ignored);
            }
            return c.pi_js_undefined();
        },
        .bindCommandContext => return bindCommands(engine, runner, first),
        .createContext, .createCommandContext => return @import("native_sdk_public_runner_context.zig").create(engine, runner, operation == .createCommandContext),
        .createToolContext => return @import("native_sdk_public_runner_tool_context.zig").create(engine, runner, first, if (args.len > 1) args[1] else c.pi_js_undefined()),
        .resolveToolRenderers => return @import("native_sdk_public_runner_renderers.zig").resolve(engine, runner, first, if (args.len > 1) args[1] else c.pi_js_undefined()),
        else => return @import("native_sdk_public_runner_catalog.zig").invoke(engine, runner, @tagName(operation), args),
    }
}
fn unsubscribe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const listeners = sdk.get(engine, roots[0], "errorListeners") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(listeners);
    return js.invoke(engine, listeners, "delete", &.{roots[1]}) catch |err| sdk.fail(engine, err);
}
fn bindCommands(engine: *em.Engine, runner: c.JSValue, actions: c.JSValue) !c.JSValue {
    inline for (.{ .{ "waitForIdle", "waitForIdleFn", Default.waitForIdleFn }, .{ "newSession", "newSessionHandler", Default.newSessionHandler }, .{ "fork", "forkHandler", Default.forkHandler }, .{ "navigateTree", "navigateTreeHandler", Default.navigateTreeHandler }, .{ "switchSession", "switchSessionHandler", Default.switchSessionHandler }, .{ "reload", "reloadHandler", Default.reloadHandler } }) |entry| {
        var roots = [_]c.JSValue{runner};
        const value = if (c.JS_ToBool(engine.context, actions) == 1) try sdk.get(engine, actions, entry[0]) else try engine.checked(c.JS_NewCFunctionData2(engine.context, defaultCall, "", 0, @intFromEnum(entry[2]), roots.len, &roots));
        try assign(engine, runner, entry[1], value);
    }
    return c.pi_js_undefined();
}
const Prompt = enum(c_int) { select, confirm, input, editor, custom };
fn wrapUI(engine: *em.Engine, runner: c.JSValue, ui: c.JSValue) !c.JSValue {
    const result = try js.spread(engine, ui);
    errdefer engine.freeValue(result);
    var roots = [_]c.JSValue{ runner, ui };
    inline for (std.meta.fields(Prompt)) |field| try sdk.put(engine, result, field.name, try engine.checked(c.JS_NewCFunctionData2(engine.context, uiPrompt, field.name, if (field.value <= @intFromEnum(Prompt.input)) 3 else 2, field.value, roots.len, &roots)));
    return result;
}
fn uiPrompt(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invokeUI(engine, roots[0], roots[1], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn invokeUI(engine: *em.Engine, runner: c.JSValue, ui: c.JSValue, kind: Prompt, args: []const c.JSValue) !c.JSValue {
    const arguments = try sdk.array(engine);
    defer engine.freeValue(arguments);
    const count: usize = if (kind == .select or kind == .confirm or kind == .input) 3 else 2;
    for (0..count) |index| try sdk.append(engine, arguments, if (index < args.len) c.JS_DupValue(engine.context, args[index]) else c.pi_js_undefined());
    var roots = [_]c.JSValue{ ui, arguments };
    const run = try engine.checked(c.JS_NewCFunctionData2(engine.context, runUI, "", 0, @intFromEnum(kind), roots.len, &roots));
    defer engine.freeValue(run);
    const kind_value = try sdk.text(engine, @tagName(kind));
    defer engine.freeValue(kind_value);
    return js.invoke(engine, runner, "withUIPrompt", &.{ kind_value, if (kind == .custom or args.len == 0) c.pi_js_undefined() else args[0], run });
}
fn runUI(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const kind: Prompt = @enumFromInt(magic);
    const function = sdk.get(engine, roots[0], @tagName(kind)) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(function);
    const global = c.JS_GetGlobalObject(context);
    defer engine.freeValue(global);
    const reflect = sdk.get(engine, global, "Reflect") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(reflect);
    return js.invoke(engine, reflect, "apply", &.{ function, roots[0], roots[1] }) catch |err| sdk.fail(engine, err);
}
