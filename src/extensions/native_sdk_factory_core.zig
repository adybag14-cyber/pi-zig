//! Source AgentSession core callbacks root the actual session and runner refs.
//! Underlying compact/nested-tool/custom-message Session bodies remain separate
//! explicit SDK gaps; forwarding never invents successful operations.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
const Kind = enum(c_int) { sendMessage, sendUserMessage, appendEntry, setSessionName, getSessionName, setLabel, getActiveTools, getAllTools, getSettings, setActiveTools, refreshTools, getCommands, setModel, getThinkingLevel, setThinkingLevel, getModel, getScopedModels, isIdle, isProjectTrusted, getSignal, abort, hasPendingMessages, shutdown, getContextUsage, compact, getSystemPrompt, getSystemPromptOptions, executeTool, getCallableTools, registerProvider, registerNativeProvider, unregisterProvider, registerVirtualModel, unregisterVirtualModel };
pub fn applyBindings(engine: *em.Engine, owner: *sdk.State, session: c.JSValue, runner: c.JSValue) !void {
    const ui = try sdk.get(engine, owner.data, "extension_uiContext");
    defer engine.freeValue(ui);
    const mode = try sdk.get(engine, owner.data, "extension_mode");
    defer engine.freeValue(mode);
    const installed = try js.invoke(engine, runner, "setUIContext", &.{ ui, mode });
    engine.freeValue(installed);
    try @import("native_sdk_command_runner.zig").bind(owner);
    const previous = try sdk.get(engine, owner.data, "_sdkRunnerErrorOff");
    defer engine.freeValue(previous);
    if (!c.JS_IsNull(previous) and !c.JS_IsUndefined(previous)) {
        const ignored = try js.call(engine, previous, session, &.{});
        engine.freeValue(ignored);
    }
    const listener = try sdk.get(engine, owner.data, "extension_onError");
    defer engine.freeValue(listener);
    try sdk.put(engine, owner.data, "_sdkRunnerErrorOff", if (c.JS_ToBool(engine.context, listener) == 1) try js.invoke(engine, runner, "onError", &.{listener}) else c.pi_js_undefined());
    try sdk.put(engine, owner.data, "extension_wrappedUI", try js.invoke(engine, runner, "getUIContext", &.{}));
}
pub fn bind(engine: *em.Engine, session: c.JSValue, runner: c.JSValue) !void {
    const actions = try sdk.object(engine);
    defer engine.freeValue(actions);
    const contexts = try sdk.object(engine);
    defer engine.freeValue(contexts);
    const providers = try sdk.object(engine);
    defer engine.freeValue(providers);
    var roots = [_]c.JSValue{ session, runner };
    inline for (std.meta.fields(Kind)) |field| {
        const kind: Kind = @enumFromInt(field.value);
        const arity: c_int = switch (kind) {
            .sendMessage, .sendUserMessage, .appendEntry, .setLabel, .registerProvider, .unregisterVirtualModel => 2,
            .setSessionName, .setActiveTools, .setModel, .setThinkingLevel, .compact, .registerNativeProvider, .unregisterProvider, .registerVirtualModel => 1,
            .executeTool => 4,
            else => 0,
        };
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, field.name, arity, field.value, roots.len, &roots));
        if (kind == .setModel) {
            const async_prototype = engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)) catch |err| {
                engine.freeValue(function);
                return err;
            };
            defer engine.freeValue(async_prototype);
            if (c.JS_SetPrototype(engine.context, function, async_prototype) < 0) {
                engine.freeValue(function);
                return js.capture(engine);
            }
        }
        const bundle = if (field.value < @intFromEnum(Kind.getModel)) actions else if (field.value < @intFromEnum(Kind.registerProvider)) contexts else providers;
        try sdk.put(engine, bundle, field.name, function);
    }
    const ignored = try js.invoke(engine, runner, "bindCore", &.{ actions, contexts, providers });
    engine.freeValue(ignored);
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const kind: Kind = @enumFromInt(magic);
    return invoke(engine, kind, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots) catch |err| {
        if (kind == .setModel or kind == .compact) {
            const reason = capture(engine, err);
            defer engine.freeValue(reason);
            const rejected = reject(engine, reason) catch |failure| return sdk.fail(engine, failure);
            if (kind == .setModel) return rejected;
            engine.freeValue(rejected);
            return c.pi_js_undefined();
        }
        return sdk.fail(engine, err);
    };
}
fn capture(engine: *em.Engine, err: anyerror) c.JSValue {
    _ = sdk.fail(engine, err);
    return c.JS_GetException(engine.context);
}
fn reject(engine: *em.Engine, reason: c.JSValue) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(promise);
    defer for (functions) |function| engine.freeValue(function);
    const ignored = try js.call(engine, functions[1], c.pi_js_undefined(), &.{reason});
    engine.freeValue(ignored);
    return promise;
}
fn invoke(engine: *em.Engine, kind: Kind, args: []const c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    const session = roots[0];
    const runner = roots[1];
    const owner = try sdk.state(engine, session);
    if (owner.kind != .agent_session) return error.InvalidNativeSDKSession;
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else c.pi_js_undefined();
    switch (kind) {
        .sendMessage, .sendUserMessage => {
            const pending = try js.invoke(engine, session, if (kind == .sendMessage) "sendCustomMessage" else "sendUserMessage", &.{ first, second });
            defer engine.freeValue(pending);
            var retained = [_]c.JSValue{runner};
            const handler = try engine.checked(c.JS_NewCFunctionData2(engine.context, sendError, "", 1, @intFromBool(kind == .sendUserMessage), retained.len, &retained));
            defer engine.freeValue(handler);
            const caught = try js.invoke(engine, pending, "catch", &.{handler});
            engine.freeValue(caught);
        },
        .appendEntry => {
            const manager = try sdk.get(engine, session, "sessionManager");
            defer engine.freeValue(manager);
            const id = try js.invoke(engine, manager, "appendCustomEntry", &.{ first, second });
            defer engine.freeValue(id);
            const current_manager = try sdk.get(engine, session, "sessionManager");
            defer engine.freeValue(current_manager);
            const entry = try js.invoke(engine, current_manager, "getEntry", &.{id});
            defer engine.freeValue(entry);
            if (c.JS_ToBool(engine.context, entry) == 1) {
                const event = try sdk.object(engine);
                defer engine.freeValue(event);
                try sdk.put(engine, event, "type", try sdk.text(engine, "entry_appended"));
                try sdk.put(engine, event, "entry", c.JS_DupValue(engine.context, entry));
                try sdk.emit(owner, event);
            }
        },
        .setSessionName, .setThinkingLevel => {
            const ignored = try js.invoke(engine, session, @tagName(kind), &.{first});
            engine.freeValue(ignored);
        },
        .getSessionName => {
            const manager = try sdk.get(engine, session, "sessionManager");
            defer engine.freeValue(manager);
            return js.invoke(engine, manager, "getSessionName", &.{});
        },
        .setLabel => {
            const manager = try sdk.get(engine, session, "sessionManager");
            defer engine.freeValue(manager);
            const ignored = try js.invoke(engine, manager, "appendLabelChange", &.{ first, second });
            engine.freeValue(ignored);
        },
        .getActiveTools => return js.invoke(engine, session, "getActiveToolNames", &.{}),
        .getAllTools, .getContextUsage => return js.invoke(engine, session, @tagName(kind), &.{}),
        .getSettings, .isProjectTrusted => {
            const settings = try sdk.get(engine, session, "settingsManager");
            defer engine.freeValue(settings);
            return js.invoke(engine, settings, @tagName(kind), &.{});
        },
        .setActiveTools => {
            const ignored = try js.invoke(engine, session, "setActiveToolsByName", &.{first});
            engine.freeValue(ignored);
        },
        .refreshTools => try @import("native_sdk_tool_catalog.zig").refreshRegistration(owner),
        .getCommands => return commands(engine, session, runner),
        .getThinkingLevel => return sdk.get(engine, session, "thinkingLevel"),
        .getModel => return sdk.get(engine, session, "model"),
        .getScopedModels => return sdk.get(engine, owner.data, "scopedModels"),
        .isIdle => return sdk.get(engine, session, "isIdle"),
        .getSignal => {
            const agent = try sdk.get(engine, session, "agent");
            defer engine.freeValue(agent);
            return sdk.get(engine, agent, "signal");
        },
        .abort, .shutdown => try @import("native_sdk_ui_context.zig").action(engine, session, kind == .abort),
        .hasPendingMessages => {
            const count = try sdk.get(engine, session, "pendingMessageCount");
            defer engine.freeValue(count);
            return engine.checked(c.JS_PiBinaryOperator(engine.context, 6, count, c.JS_NewInt32(engine.context, 0)));
        },
        .getSystemPrompt => return sdk.get(engine, session, "systemPrompt"),
        .getSystemPromptOptions => return sdk.get(engine, session, "_baseSystemPromptOptions"),
        .getCallableTools => return @import("native_sdk_tool_catalog.zig").callableDefinitions(owner),
        .executeTool => {
            var forwarded = [_]c.JSValue{ first, second, if (args.len > 2) args[2] else c.pi_js_undefined(), if (args.len > 3) args[3] else c.pi_js_undefined() };
            return js.invoke(engine, session, "_executeNestedToolCall", &forwarded);
        },
        .setModel => {
            const runtime = try sdk.get(engine, owner.data, "modelRuntime");
            defer engine.freeValue(runtime);
            const checker = try sdk.get(engine, runtime, "hasConfiguredAuth");
            defer engine.freeValue(checker);
            const provider = try sdk.get(engine, first, "provider");
            defer engine.freeValue(provider);
            const configured = try js.call(engine, checker, runtime, &.{provider});
            defer engine.freeValue(configured);
            if (c.JS_ToBool(engine.context, configured) != 1) return sdk.promise(engine, c.pi_js_bool(engine.context, 0));
            const pending = try js.invoke(engine, session, "setModel", &.{first});
            defer engine.freeValue(pending);
            const promise = try engine.checked(c.JS_PiPromiseResolve(engine.context, pending));
            defer engine.freeValue(promise);
            const fulfilled = try engine.checked(c.pi_js_function_magic(engine.context, modelSet, "", 1, 0));
            defer engine.freeValue(fulfilled);
            return engine.checked(c.JS_PromiseThen(engine.context, promise, fulfilled, c.pi_js_undefined()));
        },
        .compact => try compact(engine, session, first),
        .registerProvider, .registerNativeProvider, .unregisterProvider, .registerVirtualModel, .unregisterVirtualModel => {
            const runtime = try sdk.get(engine, owner.data, "modelRuntime");
            defer engine.freeValue(runtime);
            const ignored = try js.invoke(engine, runtime, @tagName(kind), if (kind == .registerProvider or kind == .unregisterVirtualModel) &.{ first, second } else &.{first});
            engine.freeValue(ignored);
            const current = try sdk.get(engine, session, "model");
            defer engine.freeValue(current);
            if (c.JS_ToBool(engine.context, current) == 1) {
                const get = try sdk.get(engine, runtime, "getModel");
                defer engine.freeValue(get);
                const provider = try sdk.get(engine, current, "provider");
                defer engine.freeValue(provider);
                const id = try sdk.get(engine, current, "id");
                defer engine.freeValue(id);
                const refreshed = try js.call(engine, get, runtime, &.{ provider, id });
                defer engine.freeValue(refreshed);
                if (c.JS_ToBool(engine.context, refreshed) == 1 and !c.JS_IsStrictEqual(engine.context, refreshed, current)) try sdk.setAgentField(owner, "model", refreshed);
            }
        },
    }
    return c.pi_js_undefined();
}
fn modelSet(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, 1);
}
fn sendError(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return reported(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), magic != 0) catch |err| sdk.fail(engine, err);
}
fn reported(engine: *em.Engine, runner: c.JSValue, reason: c.JSValue, user: bool) !c.JSValue {
    const event = try sdk.object(engine);
    defer engine.freeValue(event);
    try sdk.put(engine, event, "extensionPath", try sdk.text(engine, "<runtime>"));
    try sdk.put(engine, event, "event", try sdk.text(engine, if (user) "send_user_message" else "send_message"));
    const error_class = try js.global(engine, "Error");
    defer engine.freeValue(error_class);
    const is_error = c.JS_IsInstanceOf(engine.context, reason, error_class);
    if (is_error < 0) return js.capture(engine);
    const message = if (is_error == 1) try sdk.get(engine, reason, "message") else string: {
        const converter = try js.global(engine, "String");
        defer engine.freeValue(converter);
        break :string try js.call(engine, converter, c.pi_js_undefined(), &.{reason});
    };
    try sdk.put(engine, event, "error", message);
    const ignored = try js.invoke(engine, runner, "emitError", &.{event});
    engine.freeValue(ignored);
    return c.pi_js_undefined();
}
fn optional(engine: *em.Engine, receiver: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (c.JS_IsNull(receiver) or c.JS_IsUndefined(receiver)) c.pi_js_undefined() else sdk.get(engine, receiver, key);
}
fn compact(engine: *em.Engine, session: c.JSValue, options: c.JSValue) !void {
    const method = sdk.get(engine, session, "compact") catch |err| {
        const reason = capture(engine, err);
        defer engine.freeValue(reason);
        return compactFinish(engine, options, reason, true);
    };
    defer engine.freeValue(method);
    const instructions = optional(engine, options, "customInstructions") catch |err| {
        const reason = capture(engine, err);
        defer engine.freeValue(reason);
        return compactFinish(engine, options, reason, true);
    };
    defer engine.freeValue(instructions);
    const pending = js.call(engine, method, session, &.{instructions}) catch |err| {
        const reason = capture(engine, err);
        defer engine.freeValue(reason);
        return compactFinish(engine, options, reason, true);
    };
    defer engine.freeValue(pending);
    const promise = engine.checked(c.JS_PiPromiseResolve(engine.context, pending)) catch |err| {
        const reason = capture(engine, err);
        defer engine.freeValue(reason);
        return compactFinish(engine, options, reason, true);
    };
    defer engine.freeValue(promise);
    var roots = [_]c.JSValue{options};
    const complete = try engine.checked(c.JS_NewCFunctionData2(engine.context, compactResume, "", 1, 0, roots.len, &roots));
    defer engine.freeValue(complete);
    const failed = try engine.checked(c.JS_NewCFunctionData2(engine.context, compactResume, "", 1, 1, roots.len, &roots));
    defer engine.freeValue(failed);
    const ignored = try engine.checked(c.JS_PromiseThen(engine.context, promise, complete, failed));
    engine.freeValue(ignored);
}
fn compactResume(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    compactFinish(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), magic != 0) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn compactFinish(engine: *em.Engine, options: c.JSValue, value: c.JSValue, failed: bool) anyerror!void {
    var argument = c.JS_DupValue(engine.context, value);
    defer engine.freeValue(argument);
    if (failed) {
        const error_class = try js.global(engine, "Error");
        defer engine.freeValue(error_class);
        const is_error = c.JS_IsInstanceOf(engine.context, value, error_class);
        if (is_error < 0) return js.capture(engine);
        if (is_error == 0) {
            const constructor = try js.global(engine, "Error");
            defer engine.freeValue(constructor);
            const converter = try js.global(engine, "String");
            defer engine.freeValue(converter);
            const text = try js.call(engine, converter, c.pi_js_undefined(), &.{value});
            defer engine.freeValue(text);
            var values = [_]c.JSValue{text};
            const replacement = try engine.checked(c.JS_CallConstructor(engine.context, constructor, values.len, &values));
            engine.freeValue(argument);
            argument = replacement;
        }
    }
    const handler = optional(engine, options, if (failed) "onError" else "onComplete") catch |err| {
        if (!failed) {
            const reason = capture(engine, err);
            defer engine.freeValue(reason);
            return compactFinish(engine, options, reason, true);
        }
        return err;
    };
    defer engine.freeValue(handler);
    if (!c.JS_IsNull(handler) and !c.JS_IsUndefined(handler)) {
        const ignored = js.call(engine, handler, options, &.{argument}) catch |err| {
            if (!failed) {
                const reason = capture(engine, err);
                defer engine.freeValue(reason);
                return compactFinish(engine, options, reason, true);
            }
            return err;
        };
        engine.freeValue(ignored);
    }
}
fn commands(engine: *em.Engine, session: c.JSValue, runner: c.JSValue) !c.JSValue {
    const registered = try js.invoke(engine, runner, "getRegisteredCommands", &.{});
    defer engine.freeValue(registered);
    const extension_mapper = try engine.checked(c.pi_js_function_magic(engine.context, projectCommand, "", 1, 0));
    defer engine.freeValue(extension_mapper);
    const extension = try js.invoke(engine, registered, "map", &.{extension_mapper});
    defer engine.freeValue(extension);
    const prompts = try sdk.get(engine, session, "promptTemplates");
    defer engine.freeValue(prompts);
    const prompt_mapper = try engine.checked(c.pi_js_function_magic(engine.context, projectCommand, "", 1, 1));
    defer engine.freeValue(prompt_mapper);
    const templates = try js.invoke(engine, prompts, "map", &.{prompt_mapper});
    defer engine.freeValue(templates);
    const owner = try sdk.state(engine, session);
    const loader = try sdk.get(engine, owner.data, "resourceLoader");
    defer engine.freeValue(loader);
    const skill_result = try js.invoke(engine, loader, "getSkills", &.{});
    defer engine.freeValue(skill_result);
    const skill_rows = try sdk.get(engine, skill_result, "skills");
    defer engine.freeValue(skill_rows);
    const skill_mapper = try engine.checked(c.pi_js_function_magic(engine.context, projectCommand, "", 1, 2));
    defer engine.freeValue(skill_mapper);
    const skills = try js.invoke(engine, skill_rows, "map", &.{skill_mapper});
    defer engine.freeValue(skills);
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    inline for (.{ extension, templates, skills }) |rows| {
        const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
        defer engine.freeValue(symbol);
        var iterator = try js.Iterator.init(engine, rows, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |row| {
            defer engine.freeValue(row);
            const length = try sdk.length(engine, result);
            if (c.JS_DefinePropertyValueUint32(engine.context, result, @intCast(length), c.JS_DupValue(engine.context, row), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        }
    }
    return result;
}
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
fn projectCommand(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return projected(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic) catch |err| sdk.fail(engine, err);
}
fn projected(engine: *em.Engine, row: c.JSValue, kind: c_int) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const name = try sdk.get(engine, row, if (kind == 0) "invocationName" else "name");
    defer engine.freeValue(name);
    const complete_name = if (kind == 2) prefixed: {
        const prefix = try sdk.text(engine, "skill:");
        defer engine.freeValue(prefix);
        // Template interpolation uses string coercion rather than + hints.
        const text = try engine.checked(c.JS_ToString(engine.context, name));
        defer engine.freeValue(text);
        break :prefixed try @import("native_select_list.zig").concat(engine, &.{ prefix, text });
    } else c.JS_DupValue(engine.context, name);
    try sdk.put(engine, result, "name", complete_name);
    try sdk.put(engine, result, "description", try sdk.get(engine, row, "description"));
    try sdk.put(engine, result, "source", try sdk.text(engine, if (kind == 0) "extension" else if (kind == 1) "prompt" else "skill"));
    try sdk.put(engine, result, "sourceInfo", try sdk.get(engine, row, "sourceInfo"));
    return result;
}
