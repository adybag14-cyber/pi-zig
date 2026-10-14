//! Original live AgentSession registry algorithms. Private composition only.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;

const Method = enum(c_int) { _refreshToolRegistry, _isAllowedTool, _isDeclarable, _isActivatedOnRegistration, _setActiveTools, _rebuildSystemPrompt, _normalizePromptSnippet, _normalizePromptGuidelines, _buildRuntime, _applyExtensionBindings, _refreshCurrentModelFromRegistry, _bindExtensionCore, _restoreToolsFromTranscript };
const Mapper = enum(c_int) { previous_activated, custom_entry, custom_allowed, base_allowed, base_entry, snippet_entry, guideline_entry, present_entry, builtin_allowed, builtin_entry, name_entry, next_allowed, valid_name, tool_name, override_entry, identity_entry, command_extension, command_prompt, command_skill };
const Closure = enum(c_int) {
    sendMessage,
    sendUserMessage,
    appendEntry,
    setSessionName,
    getSessionName,
    setLabel,
    getActiveTools,
    getAllTools,
    getSettings,
    setActiveTools,
    refreshTools,
    getCommands,
    setModel,
    getThinkingLevel,
    setThinkingLevel,
    getModel,
    getScopedModels,
    isIdle,
    isProjectTrusted,
    getSignal,
    abort,
    hasPendingMessages,
    shutdown,
    getContextUsage,
    compact,
    getSystemPrompt,
    getSystemPromptOptions,
    executeTool,
    getCallableTools,
    registerProvider,
    registerNativeProvider,
    unregisterProvider,
    registerVirtualModel,
    unregisterVirtualModel,
};

pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    // Actual mcp-servers.ts initializes its module-private Set before callers
    // can mutate Set.prototype.has. Its live has method remains observable.
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = try mcpResources(&scope);
    inline for (std.meta.fields(Method)) |field| {
        const kind: Method = @enumFromInt(field.value);
        const installed = try engine.checked(c.pi_js_function_magic(engine.context, methodCallback, field.name, if (kind == ._refreshCurrentModelFromRegistry or kind == ._restoreToolsFromTranscript) 0 else 1, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, installed, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn methodCallback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return dispatch(engine, receiver, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn mapperCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return mapped(engine, @enumFromInt(magic), roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn map(scope: *Scope, rows: c.JSValue, name: [*:0]const u8, kind: Mapper, receiver: c.JSValue) !c.JSValue {
    const callee = try scope.get(rows, name);
    var roots = [_]c.JSValue{receiver};
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, mapperCallback, "", 1, @intFromEnum(kind), roots.len, &roots)));
    return scope.call(callee, rows, &.{callback});
}
fn spread(scope: *Scope, input: c.JSValue) !c.JSValue {
    return scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(scope.engine, input, null));
}
fn symbol(scope: *Scope) !c.JSValue {
    return scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
}
fn first(scope: *Scope, input: c.JSValue) !c.JSValue {
    var iterator = try js.Iterator.init(scope.engine, input, try symbol(scope));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const value = try scope.own((try iterator.next()) orelse c.pi_js_undefined());
    try iterator.close();
    return value;
}
fn pair(scope: *Scope, input: c.JSValue) ![2]c.JSValue {
    const values = try js.pair(scope.engine, input, try symbol(scope));
    const a = scope.own(values[0]) catch |err| {
        scope.engine.freeValue(values[1]);
        return err;
    };
    const b = try scope.own(values[1]);
    return .{ a, b };
}
fn tuple(scope: *Scope, a: c.JSValue, b: c.JSValue) !c.JSValue {
    const result = try scope.array();
    try scope.index(result, 0, a);
    try scope.index(result, 1, b);
    return result;
}
fn construct(scope: *Scope, constructor: c.JSValue, value: c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{value};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
}
fn synthetic(scope: *Scope, path: c.JSValue, source: []const u8) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "path", path);
    try scope.put(result, "source", try scope.text(source));
    try scope.put(result, "scope", try scope.text("temporary"));
    try scope.put(result, "origin", try scope.text("top-level"));
    try scope.put(result, "baseDir", c.pi_js_undefined());
    return result;
}
fn builtinEntry(scope: *Scope, definition: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "definition", definition);
    const path = try scope.concat(try scope.text("builtin:"), try scope.stringify(try scope.get(definition, "name")));
    try scope.put(result, "sourceInfo", try synthetic(scope, path, "builtin"));
    return result;
}
fn invokeName(scope: *Scope, receiver: c.JSValue, method: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const callee = try scope.get(receiver, method);
    return scope.call(callee, receiver, &.{try scope.get(value, "name")});
}
fn mapped(engine: *em.Engine, kind: Mapper, receiver: c.JSValue, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = switch (kind) {
        .previous_activated => try scope.invoke(receiver, "_isActivatedOnRegistration", &.{input}),
        .custom_entry => custom: {
            const value = try scope.object();
            try scope.put(value, "definition", input);
            const path = try scope.concat(try scope.concat(try scope.text("<sdk:"), try scope.stringify(try scope.get(input, "name"))), try scope.text(">"));
            try scope.put(value, "sourceInfo", try synthetic(&scope, path, "sdk"));
            break :custom value;
        },
        .custom_allowed => allowed: {
            const callee = try scope.get(receiver, "_isAllowedTool");
            break :allowed try scope.call(callee, receiver, &.{try scope.get(try scope.get(input, "definition"), "name")});
        },
        .base_allowed => allowed: {
            const name = try first(&scope, input);
            break :allowed try scope.invoke(receiver, "_isAllowedTool", &.{name});
        },
        .base_entry => base: {
            const values = try pair(&scope, input);
            const entry = try scope.object();
            try scope.put(entry, "definition", values[1]);
            try scope.put(entry, "sourceInfo", try synthetic(&scope, try scope.concat(try scope.text("builtin:"), try scope.stringify(values[0])), "builtin"));
            break :base try tuple(&scope, values[0], entry);
        },
        .snippet_entry, .guideline_entry => metadata: {
            const definition = try scope.get(input, "definition");
            const normalize = try scope.get(receiver, if (kind == .snippet_entry) "_normalizePromptSnippet" else "_normalizePromptGuidelines");
            const value = try scope.call(normalize, receiver, &.{try scope.get(definition, if (kind == .snippet_entry) "promptSnippet" else "promptGuidelines")});
            const present = if (kind == .snippet_entry) scope.truthy(value) else try scope.positive(try scope.get(value, "length"));
            break :metadata if (present) try tuple(&scope, try scope.get(definition, "name"), value) else c.pi_js_undefined();
        },
        .present_entry => c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(input))),
        .builtin_allowed => try invokeName(&scope, receiver, "_isAllowedTool", input),
        .builtin_entry => try builtinEntry(&scope, input),
        .name_entry => try tuple(&scope, try scope.get(input, "name"), input),
        .next_allowed => try scope.invoke(receiver, "_isAllowedTool", &.{input}),
        .valid_name => try scope.invoke(try scope.get(receiver, "_toolRegistry"), "has", &.{input}),
        .tool_name => try scope.get(input, "name"),
        .override_entry => entry: {
            const values = try pair(&scope, input);
            break :entry try tuple(&scope, values[0], try wrap(&scope, values[1], c.pi_js_undefined(), true));
        },
        .identity_entry => entry: {
            const values = try pair(&scope, input);
            break :entry try tuple(&scope, values[0], values[1]);
        },
        .command_extension, .command_prompt, .command_skill => command: {
            const value = try scope.object();
            const name = try scope.get(input, if (kind == .command_extension) "invocationName" else "name");
            try scope.put(value, "name", if (kind == .command_skill) try scope.concat(try scope.text("skill:"), try scope.stringify(name)) else name);
            try scope.put(value, "description", try scope.get(input, "description"));
            try scope.put(value, "source", try scope.text(if (kind == .command_extension) "extension" else if (kind == .command_prompt) "prompt" else "skill"));
            try scope.put(value, "sourceInfo", try scope.get(input, "sourceInfo"));
            break :command value;
        },
    };
    return c.JS_DupValue(engine.context, result);
}

/// Source wrapToolDefinition/wrapRegisteredTool: keep the definition and the
/// actual runner in VM function data; call createToolContext at execution time.
fn wrap(scope: *Scope, definition: c.JSValue, runner: c.JSValue, from_agent: bool) !c.JSValue {
    const result = try scope.object();
    inline for (.{ "name", "label", "description", "parameters", "outputSchema", "constrainedSampling", "prepareArguments", "executionMode" }) |key| try scope.put(result, key, try scope.get(definition, key));
    var roots = [_]c.JSValue{ definition, runner };
    const execute = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, toolExecute, "execute", if (from_agent) 4 else 5, @intFromBool(from_agent), roots.len, &roots)));
    if (from_agent) {
        const prototype = try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)));
        if (c.JS_SetPrototype(scope.engine.context, execute, prototype) < 0) return js.capture(scope.engine);
    }
    try scope.put(result, "execute", execute);
    return result;
}
fn toolExecute(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    if (magic == 0) return executeWrapped(engine, roots[0], roots[1], argv[0..@intCast(argc)]) catch |err| sdk.fail(engine, err);
    // The original AgentTool-to-definition arrow is async: synchronous throws
    // reject and returned thenables are adopted by the intrinsic promise.
    const result = executeAgent(engine, roots[0], argv[0..@intCast(argc)]) catch |err| {
        const reason = @import("native_agent_async.zig").reason(engine, err);
        defer engine.freeValue(reason);
        return rejected(engine, reason) catch |failure| sdk.fail(engine, failure);
    };
    defer engine.freeValue(result);
    return engine.checked(c.JS_PiPromiseResolve(engine.context, result)) catch |err| sdk.fail(engine, err);
}
fn rejected(engine: *em.Engine, reason: c.JSValue) !c.JSValue {
    var callbacks: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &callbacks));
    errdefer engine.freeValue(promise);
    defer for (callbacks) |callback| engine.freeValue(callback);
    const ignored = try js.call(engine, callbacks[1], c.pi_js_undefined(), &.{reason});
    engine.freeValue(ignored);
    return promise;
}
fn executeWrapped(engine: *em.Engine, definition: c.JSValue, runner: c.JSValue, input: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const execute = try scope.get(definition, "execute");
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 5;
    for (0..@min(args.len, input.len)) |i| args[i] = input[i];
    if (temp.nullish(args[4])) args[4] = try scope.invoke(runner, "createToolContext", &.{ args[0], args[2] });
    return js.call(engine, execute, definition, &args);
}
fn executeAgent(engine: *em.Engine, tool: c.JSValue, input: []const c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 4;
    for (0..@min(args.len, input.len)) |i| args[i] = input[i];
    return js.invoke(engine, tool, "execute", &args);
}
fn wrappedRows(scope: *Scope, registered: c.JSValue, runner: c.JSValue) !c.JSValue {
    const callee = try scope.get(registered, "map");
    var roots = [_]c.JSValue{runner};
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, wrapCallback, "", 1, 0, roots.len, &roots)));
    return scope.call(callee, registered, &.{callback});
}
fn wrapCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const definition = scope.get(if (argc > 0) argv[0] else c.pi_js_undefined(), "definition") catch |err| return sdk.fail(engine, err);
    const result = wrap(&scope, definition, roots[0], false) catch |err| return sdk.fail(engine, err);
    return c.JS_DupValue(engine.context, result);
}
fn appendSpread(scope: *Scope, target: c.JSValue, values: c.JSValue) !void {
    var iterator = try js.Iterator.init(scope.engine, values, try symbol(scope));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var index: u32 = @intCast(try sdk.length(scope.engine, target));
    while (try iterator.next()) |value| {
        defer scope.engine.freeValue(value);
        try scope.index(target, index, value);
        index += 1;
    }
}
fn fromField(scope: *Scope, receiver: c.JSValue, field: [*:0]const u8, operation: [*:0]const u8) !c.JSValue {
    const array = try scope.global("Array");
    const from = try scope.get(array, "from");
    return scope.call(from, array, &.{try scope.invoke(try scope.get(receiver, field), operation, &.{})});
}
fn refresh(scope: *Scope, receiver: c.JSValue, options: c.JSValue) !void {
    const previous_set = try scope.global("Set");
    const previous_names = try spread(scope, try scope.invoke(try scope.get(receiver, "_toolRegistry"), "keys", &.{}));
    const previous = try construct(scope, previous_set, try map(scope, previous_names, "filter", .previous_activated, receiver));
    const active_before = try scope.invoke(receiver, "getActiveToolNames", &.{});
    const allowed = try scope.get(receiver, "_allowedTools");
    const registered = try scope.invoke(try scope.get(receiver, "_extensionRunner"), "getAllRegisteredTools", &.{});
    const combined = try spread(scope, registered);
    const custom = try map(scope, try scope.get(receiver, "_customTools"), "map", .custom_entry, receiver);
    try appendSpread(scope, combined, custom);
    const all_custom = try map(scope, combined, "filter", .custom_allowed, receiver);
    const map_constructor = try scope.global("Map");
    const base = try map(scope, try fromField(scope, receiver, "_baseToolDefinitions", "entries"), "filter", .base_allowed, receiver);
    const definitions = try construct(scope, map_constructor, try map(scope, base, "map", .base_entry, receiver));
    {
        var iterator = try js.Iterator.init(scope.engine, all_custom, try symbol(scope));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |tool| {
            defer scope.engine.freeValue(tool);
            const setter = try scope.get(definitions, "set");
            const name = try scope.get(try scope.get(tool, "definition"), "name");
            const entry = try scope.object();
            try scope.put(entry, "definition", try scope.get(tool, "definition"));
            try scope.put(entry, "sourceInfo", try scope.get(tool, "sourceInfo"));
            _ = try scope.call(setter, definitions, &.{ name, entry });
        }
    }
    try scope.set(receiver, "_toolDefinitions", definitions);
    inline for (.{ .{ "_toolPromptSnippets", Mapper.snippet_entry }, .{ "_toolPromptGuidelines", Mapper.guideline_entry } }) |entry| {
        const constructor = try scope.global("Map");
        const array = try scope.global("Array");
        const from = try scope.get(array, "from");
        const values = try scope.call(from, array, &.{try scope.invoke(definitions, "values", &.{})});
        const normalized = try map(scope, values, "map", entry[1], receiver);
        const present = try map(scope, normalized, "filter", .present_entry, receiver);
        try scope.set(receiver, entry[0], try construct(scope, constructor, present));
    }
    const runner = try scope.get(receiver, "_extensionRunner");
    const extensions = try wrappedRows(scope, all_custom, runner);
    const builtins = try map(scope, try fromField(scope, receiver, "_baseToolDefinitions", "values"), "filter", .builtin_allowed, receiver);
    const builtin_entries = try map(scope, builtins, "map", .builtin_entry, receiver);
    const wrapped_builtins = try wrappedRows(scope, builtin_entries, runner);
    const registry_constructor = try scope.global("Map");
    const registry = try construct(scope, registry_constructor, try map(scope, wrapped_builtins, "map", .name_entry, receiver));
    {
        var iterator = try js.Iterator.init(scope.engine, extensions, try symbol(scope));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |tool| {
            defer scope.engine.freeValue(tool);
            const setter = try scope.get(registry, "set");
            _ = try scope.call(setter, registry, &.{ try scope.get(tool, "name"), tool });
        }
    }
    try scope.set(receiver, "_toolRegistry", registry);
    const requested = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "activeToolNames");
    const next = try map(scope, if (scope.truthy(requested)) try spread(scope, try scope.get(options, "activeToolNames")) else try spread(scope, active_before), "filter", .next_allowed, receiver);
    if (scope.truthy(allowed)) {
        var iterator = try js.Iterator.init(scope.engine, try scope.invoke(try scope.get(receiver, "_toolRegistry"), "keys", &.{}), try symbol(scope));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |name| {
            defer scope.engine.freeValue(name);
            if (scope.truthy(try scope.call(allowed, c.pi_js_undefined(), &.{name})) and scope.truthy(try scope.invoke(receiver, "_isDeclarable", &.{name}))) _ = try scope.invoke(next, "push", &.{name});
        }
    } else if (!temp.nullish(options) and scope.truthy(try scope.get(options, "includeAllExtensionTools"))) {
        var iterator = try js.Iterator.init(scope.engine, extensions, try symbol(scope));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |tool| {
            defer scope.engine.freeValue(tool);
            if (scope.truthy(try invokeName(scope, receiver, "_isActivatedOnRegistration", tool))) _ = try invokeName(scope, next, "push", tool);
        }
    } else if (temp.nullish(options) or !scope.truthy(try scope.get(options, "activeToolNames"))) {
        var iterator = try js.Iterator.init(scope.engine, try scope.invoke(try scope.get(receiver, "_toolRegistry"), "keys", &.{}), try symbol(scope));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |name| {
            defer scope.engine.freeValue(name);
            if (!scope.truthy(try scope.invoke(previous, "has", &.{name})) and scope.truthy(try scope.invoke(receiver, "_isActivatedOnRegistration", &.{name}))) _ = try scope.invoke(next, "push", &.{name});
        }
    }
    const push = try scope.get(next, "push");
    const pending = try spread(scope, try scope.get(receiver, "_pendingToolNames"));
    const count = try sdk.length(scope.engine, pending);
    const arguments = try scope.engine.gpa.alloc(c.JSValue, count);
    defer scope.engine.gpa.free(arguments);
    var initialized: usize = 0;
    defer for (arguments[0..initialized]) |value| scope.engine.freeValue(value);
    for (arguments, 0..) |*slot, index| {
        slot.* = try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, pending, @intCast(index)));
        initialized += 1;
    }
    _ = try scope.call(push, next, arguments);
    const set_active = try scope.get(receiver, "_setActiveTools");
    const unique_constructor = try scope.global("Set");
    _ = try scope.call(set_active, receiver, &.{try spread(scope, try construct(scope, unique_constructor, next))});
}

fn snippet(scope: *Scope, input: c.JSValue) !c.JSValue {
    if (!scope.truthy(input)) return c.pi_js_undefined();
    const replace = try scope.get(input, "replace");
    const flags = try scope.text("g");
    const line_regex = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, 2, @constCast(&[_]c.JSValue{ try scope.text("[\r\n]+"), flags }))));
    const one = try scope.call(replace, input, &.{ line_regex, try scope.text(" ") });
    const spaces_replace = try scope.get(one, "replace");
    const space_regex = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, 2, @constCast(&[_]c.JSValue{ try scope.text("\\s+"), flags }))));
    const two = try scope.call(spaces_replace, one, &.{ space_regex, try scope.text(" ") });
    const normalized = try scope.invoke(two, "trim", &.{});
    return if (try scope.positive(try scope.get(normalized, "length"))) normalized else c.pi_js_undefined();
}
fn guidelines(scope: *Scope, input: c.JSValue) !c.JSValue {
    if (!scope.truthy(input) or scope.equal(try scope.get(input, "length"), c.JS_NewInt32(scope.engine.context, 0))) return scope.array();
    const unique = try scope.own(try js.builtin(scope.engine, "Set", &.{}));
    var iterator = try js.Iterator.init(scope.engine, input, try symbol(scope));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |line| {
        defer scope.engine.freeValue(line);
        const normalized = try scope.invoke(line, "trim", &.{});
        if (try scope.positive(try scope.get(normalized, "length"))) _ = try scope.invoke(unique, "add", &.{normalized});
    }
    return scope.invoke(try scope.global("Array"), "from", &.{unique});
}
fn mcpResources(scope: *Scope) !c.JSValue {
    const key = "pi-native:session-mcp-resource-names";
    if (!scope.engine.native_module_values.contains(key)) {
        const values = try scope.array();
        inline for (.{ "list_mcp_resources", "list_mcp_resource_templates", "read_mcp_resource" }, 0..) |name, index| try scope.index(values, index, try scope.text(name));
        const set = try construct(scope, try scope.global("Set"), values);
        const exports = try scope.object();
        try scope.put(exports, "names", set);
        try scope.engine.registerValueModule(key, exports);
    }
    return scope.get(scope.engine.native_module_values.get(key).?, "names");
}
fn mcp(scope: *Scope, name: c.JSValue) !c.JSValue {
    const prefix = try scope.invoke(name, "startsWith", &.{try scope.text("mcp__")});
    return if (scope.truthy(prefix)) prefix else scope.invoke(try mcpResources(scope), "has", &.{name});
}
fn rebuild(scope: *Scope, receiver: c.JSValue, names: c.JSValue) !void {
    const valid = try map(scope, names, "filter", .valid_name, receiver);
    const snippets = try scope.object();
    {
        var iterator = try js.Iterator.init(scope.engine, try scope.invoke(try scope.get(receiver, "_toolRegistry"), "keys", &.{}), try symbol(scope));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |name| {
            defer scope.engine.freeValue(name);
            const value = try scope.invoke(try scope.get(receiver, "_toolPromptSnippets"), "get", &.{name});
            if (scope.truthy(value)) try js.setKey(scope.engine, snippets, name, value);
        }
    }
    const custom = try scope.invoke(try scope.get(receiver, "_resourceLoader"), "getSystemPrompt", &.{});
    const append = try scope.invoke(try scope.get(receiver, "_resourceLoader"), "getAppendSystemPrompt", &.{});
    const appended = if (try scope.positive(try scope.get(append, "length"))) try scope.invoke(append, "join", &.{try scope.text("\n\n")}) else try scope.text("");
    const skills = try scope.get(try scope.invoke(try scope.get(receiver, "_resourceLoader"), "getSkills", &.{}), "skills");
    const files = try scope.get(try scope.invoke(try scope.get(receiver, "_resourceLoader"), "getAgentsFiles", &.{}), "agentsFiles");
    const options = try scope.object();
    try scope.put(options, "cwd", try scope.get(receiver, "_cwd"));
    try scope.put(options, "skills", skills);
    try scope.put(options, "contextFiles", files);
    try scope.put(options, "customPrompt", custom);
    try scope.put(options, "appendSystemPrompt", appended);
    try scope.put(options, "selectedTools", valid);
    try scope.put(options, "hiddenTools", try spread(scope, try scope.get(receiver, "_hiddenDeclarations")));
    try scope.put(options, "toolSnippets", snippets);
    const object = try scope.global("Object");
    const from_entries = try scope.get(object, "fromEntries");
    try scope.put(options, "toolGuidelines", try scope.call(from_entries, object, &.{try scope.get(receiver, "_toolPromptGuidelines")}));
    try scope.set(receiver, "_baseSystemPromptOptions", try scope.own(try @import("native_sdk_prompt_normalize.zig").normalize(scope.engine, options)));
}
fn optionalText(scope: *Scope, value: c.JSValue) !?[]u8 {
    if (temp.nullish(value)) return null;
    return try scope.engine.toString(value);
}
fn buildRuntime(scope: *Scope, receiver: c.JSValue, options: c.JSValue) !void {
    const resize = try scope.invoke(try scope.get(receiver, "settingsManager"), "getImageAutoResize", &.{});
    const prefix = try scope.invoke(try scope.get(receiver, "settingsManager"), "getShellCommandPrefix", &.{});
    const shell = try scope.invoke(try scope.get(receiver, "settingsManager"), "getShellPath", &.{});
    const definitions = if (scope.truthy(try scope.get(receiver, "_baseToolsOverride"))) overrides: {
        const object = try scope.global("Object");
        const from_entries = try scope.get(object, "fromEntries");
        const entries_object = try scope.global("Object");
        const entries = try scope.get(entries_object, "entries");
        const rows = try scope.call(entries, entries_object, &.{try scope.get(receiver, "_baseToolsOverride")});
        break :overrides try scope.call(from_entries, object, &.{try map(scope, rows, "map", .override_entry, receiver)});
    } else builtins: {
        const cwd = try scope.engine.toString(try scope.get(receiver, "_cwd"));
        defer scope.engine.gpa.free(cwd);
        const prefix_text = try optionalText(scope, prefix);
        defer if (prefix_text) |text| scope.engine.gpa.free(text);
        const shell_text = try optionalText(scope, shell);
        defer if (shell_text) |text| scope.engine.gpa.free(text);
        const result = try scope.object();
        inline for (.{ "read", "bash", "powershell", "edit", "write", "grep", "find", "ls" }) |name| {
            const value = try scope.own(try @import("native_sdk_builtin_execution.zig").createDefinitionWithOptions(scope.engine, name, cwd, .{
                .auto_resize = temp.nullish(resize) or scope.truthy(resize),
                .command_prefix = if (std.mem.eql(u8, name, "bash")) prefix_text else null,
                .shell_path = if (std.mem.eql(u8, name, "bash")) shell_text else null,
            }));
            try scope.put(result, name, value);
        }
        break :builtins result;
    };
    const constructor = try scope.global("Map");
    const object = try scope.global("Object");
    const entries = try scope.get(object, "entries");
    const rows = try scope.call(entries, object, &.{definitions});
    try scope.set(receiver, "_baseToolDefinitions", try construct(scope, constructor, try map(scope, rows, "map", .identity_entry, receiver)));
    const extensions = try scope.invoke(try scope.get(receiver, "_resourceLoader"), "getExtensions", &.{});
    if (scope.truthy(try scope.get(options, "flagValues"))) {
        var iterator = try js.Iterator.init(scope.engine, try scope.get(options, "flagValues"), try symbol(scope));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |entry| {
            defer scope.engine.freeValue(entry);
            const values = try pair(scope, entry);
            _ = try scope.invoke(try scope.get(try scope.get(extensions, "runtime"), "flagValues"), "set", &values);
        }
    }
    const runner_constructor = scope.engine.native_sdk_command_runner_constructor orelse return error.NativeExtensionRunnerUnavailable;
    var runner_arguments = [_]c.JSValue{
        try scope.get(extensions, "extensions"),
        try scope.get(extensions, "runtime"),
        try scope.get(receiver, "_cwd"),
        try scope.get(receiver, "sessionManager"),
        try scope.own(try sdk.newModelRegistry(scope.engine, try scope.get(receiver, "_modelRuntime"))),
    };
    const runner = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, runner_constructor, runner_arguments.len, &runner_arguments)));
    try scope.set(receiver, "_extensionRunner", runner);
    if (scope.truthy(try scope.get(receiver, "_extensionRunnerRef"))) try scope.set(try scope.get(receiver, "_extensionRunnerRef"), "current", try scope.get(receiver, "_extensionRunner"));
    const bind = try scope.get(receiver, "_bindExtensionCore");
    _ = try scope.call(bind, receiver, &.{try scope.get(receiver, "_extensionRunner")});
    const apply = try scope.get(receiver, "_applyExtensionBindings");
    _ = try scope.call(apply, receiver, &.{try scope.get(receiver, "_extensionRunner")});
    const defaults = if (scope.truthy(try scope.get(receiver, "_baseToolsOverride"))) keys: {
        const object_type = try scope.global("Object");
        const keys = try scope.get(object_type, "keys");
        break :keys try scope.call(keys, object_type, &.{try scope.get(receiver, "_baseToolsOverride")});
    } else defaults: {
        const result = try scope.array();
        inline for (.{ "read", "bash", "edit", "write" }, 0..) |name, index| try scope.index(result, index, try scope.text(name));
        break :defaults result;
    };
    const selected = try scope.get(options, "activeToolNames");
    const refresh_method = try scope.get(receiver, "_refreshToolRegistry");
    const refresh_options = try scope.object();
    try scope.put(refresh_options, "activeToolNames", if (temp.nullish(selected)) defaults else selected);
    try scope.put(refresh_options, "includeAllExtensionTools", try scope.get(options, "includeAllExtensionTools"));
    _ = try scope.call(refresh_method, receiver, &.{refresh_options});
}
fn applyBindings(scope: *Scope, receiver: c.JSValue, runner: c.JSValue) !void {
    const set_ui = try scope.get(runner, "setUIContext");
    _ = try scope.call(set_ui, runner, &.{ try scope.get(receiver, "_extensionUIContext"), try scope.get(receiver, "_extensionMode") });
    const bind_context = try scope.get(runner, "bindCommandContext");
    _ = try scope.call(bind_context, runner, &.{try scope.get(receiver, "_extensionCommandContextActions")});
    const unsubscribe = try scope.get(receiver, "_extensionErrorUnsubscriber");
    if (!temp.nullish(unsubscribe)) _ = try scope.call(unsubscribe, receiver, &.{});
    const next = if (scope.truthy(try scope.get(receiver, "_extensionErrorListener"))) listener: {
        const subscribe = try scope.get(runner, "onError");
        break :listener try scope.call(subscribe, runner, &.{try scope.get(receiver, "_extensionErrorListener")});
    } else c.pi_js_undefined();
    try scope.set(receiver, "_extensionErrorUnsubscriber", next);
}
fn refreshModel(scope: *Scope, receiver: c.JSValue) !void {
    const current = try scope.get(receiver, "model");
    if (!scope.truthy(current)) return;
    const runtime = try scope.get(receiver, "_modelRuntime");
    const lookup = try scope.get(runtime, "getModel");
    const refreshed = try scope.call(lookup, runtime, &.{ try scope.get(current, "provider"), try scope.get(current, "id") });
    if (!scope.truthy(refreshed) or scope.equal(refreshed, current)) return;
    try scope.set(try scope.get(try scope.get(receiver, "agent"), "state"), "model", refreshed);
}
fn restore(scope: *Scope, receiver: c.JSValue, modifiers: c.JSValue) !void {
    _ = try scope.invoke(try scope.get(receiver, "_pendingToolNames"), "clear", &.{});
    const context = try scope.invoke(try scope.get(receiver, "sessionManager"), "buildSessionContext", &.{});
    const current = try scope.own(try @import("native_sdk_transcript_replay.zig").currentSystemMessage(scope.engine, try scope.get(context, "messages")));
    if (!scope.truthy(current)) return;
    const added = try scope.get(current, "toolsAdded");
    const declared = try map(scope, if (temp.nullish(added)) try scope.array() else added, "map", .tool_name, receiver);
    const names = try scope.own(try @import("native_sdk_tool_modifiers.zig").apply(scope.engine, declared, modifiers));
    const constructor = try scope.global("Set");
    try scope.set(receiver, "_pendingToolNames", try construct(scope, constructor, try map(scope, names, "filter", .next_allowed, receiver)));
    _ = try scope.invoke(receiver, "_setActiveTools", &.{names});
}
fn closure(scope: *Scope, receiver: c.JSValue, runner: c.JSValue, kind: Closure) !c.JSValue {
    var roots = [_]c.JSValue{ receiver, runner };
    const count: c_int = switch (kind) {
        .sendMessage, .sendUserMessage, .appendEntry, .setLabel, .registerProvider, .unregisterVirtualModel => 2,
        .executeTool => 4,
        .setSessionName, .setActiveTools, .setModel, .setThinkingLevel, .compact, .registerNativeProvider, .unregisterProvider, .registerVirtualModel => 1,
        else => 0,
    };
    const value = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, closureCallback, @tagName(kind), count, @intFromEnum(kind), roots.len, &roots)));
    if (kind == .setModel) {
        const prototype = try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)));
        if (c.JS_SetPrototype(scope.engine.context, value, prototype) < 0) return js.capture(scope.engine);
    }
    return value;
}
fn closureCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const kind: Closure = @enumFromInt(magic);
    if (kind == .setModel) return setModelAsync(engine, roots[0], args) catch |err| sdk.fail(engine, err);
    return closureValue(engine, roots[0], roots[1], kind, args) catch |err| sdk.fail(engine, err);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn bindCore(scope: *Scope, receiver: c.JSValue, runner: c.JSValue) !void {
    const get_commands = try closure(scope, receiver, runner, .getCommands);
    const bind = try scope.get(runner, "bindCore");
    const actions = try scope.object();
    inline for (.{ Closure.sendMessage, .sendUserMessage, .appendEntry, .setSessionName, .getSessionName, .setLabel, .getActiveTools, .getAllTools, .getSettings, .setActiveTools, .refreshTools, .getCommands, .setModel, .getThinkingLevel, .setThinkingLevel }) |kind| try scope.put(actions, @tagName(kind), if (kind == .getCommands) get_commands else try closure(scope, receiver, runner, kind));
    const context = try scope.object();
    inline for (.{ Closure.getModel, .getScopedModels, .isIdle, .isProjectTrusted, .getSignal, .abort, .hasPendingMessages, .shutdown, .getContextUsage, .compact, .getSystemPrompt, .getSystemPromptOptions, .executeTool, .getCallableTools }) |kind| try scope.put(context, @tagName(kind), try closure(scope, receiver, runner, kind));
    const providers = try scope.object();
    inline for (.{ Closure.registerProvider, .registerNativeProvider, .unregisterProvider, .registerVirtualModel, .unregisterVirtualModel }) |kind| try scope.put(providers, @tagName(kind), try closure(scope, receiver, runner, kind));
    // Original Source creates getCommands before invoking bindCore. All closures
    // capture the same live receiver and actual runner rather than snapshots.
    _ = try scope.call(bind, runner, &.{ actions, context, providers });
}
fn reportSendError(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    reportError(&scope, roots[0], if (magic == 0) "send_message" else "send_user_message", if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn reportError(scope: *Scope, runner: c.JSValue, event: []const u8, reason: c.JSValue) !void {
    const emit = try scope.get(runner, "emitError");
    const report = try scope.object();
    try scope.put(report, "extensionPath", try scope.text("<runtime>"));
    try scope.put(report, "event", try scope.text(event));
    const is_error = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (is_error < 0) return js.capture(scope.engine);
    try scope.put(report, "error", if (is_error != 0) try scope.get(reason, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason}));
    _ = try scope.call(emit, runner, &.{report});
}
fn commands(scope: *Scope, receiver: c.JSValue, runner: c.JSValue) !c.JSValue {
    const registered = try scope.invoke(runner, "getRegisteredCommands", &.{});
    const extension_commands = try map(scope, registered, "map", .command_extension, receiver);
    const templates = try map(scope, try scope.get(receiver, "promptTemplates"), "map", .command_prompt, receiver);
    const skills = try scope.get(try scope.invoke(try scope.get(receiver, "_resourceLoader"), "getSkills", &.{}), "skills");
    const skill_commands = try map(scope, skills, "map", .command_skill, receiver);
    const result = try spread(scope, extension_commands);
    try appendSpread(scope, result, templates);
    try appendSpread(scope, result, skill_commands);
    return result;
}
fn closureValue(engine: *em.Engine, receiver: c.JSValue, runner: c.JSValue, kind: Closure, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first_arg = argument(args, 0);
    const result = switch (kind) {
        .sendMessage, .sendUserMessage => sent: {
            const pending = try scope.invoke(receiver, if (kind == .sendMessage) "sendCustomMessage" else "sendUserMessage", &.{ first_arg, argument(args, 1) });
            const catch_method = try scope.get(pending, "catch");
            var roots = [_]c.JSValue{runner};
            const report = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, reportSendError, "", 1, if (kind == .sendMessage) 0 else 1, roots.len, &roots)));
            _ = try scope.call(catch_method, pending, &.{report});
            break :sent c.pi_js_undefined();
        },
        .appendEntry => appended: {
            const id = try scope.invoke(try scope.get(receiver, "sessionManager"), "appendCustomEntry", &.{ first_arg, argument(args, 1) });
            const entry = try scope.invoke(try scope.get(receiver, "sessionManager"), "getEntry", &.{id});
            if (scope.truthy(entry)) {
                const emit = try scope.get(receiver, "_emit");
                const event = try scope.object();
                try scope.put(event, "type", try scope.text("entry_appended"));
                try scope.put(event, "entry", entry);
                _ = try scope.call(emit, receiver, &.{event});
            }
            break :appended c.pi_js_undefined();
        },
        .setSessionName => changed: {
            _ = try scope.invoke(receiver, "setSessionName", &.{first_arg});
            break :changed c.pi_js_undefined();
        },
        .setActiveTools, .setThinkingLevel => try scope.invoke(receiver, if (kind == .setActiveTools) "setActiveToolsByName" else "setThinkingLevel", &.{first_arg}),
        .getSessionName => try scope.invoke(try scope.get(receiver, "sessionManager"), "getSessionName", &.{}),
        .setLabel => labeled: {
            _ = try scope.invoke(try scope.get(receiver, "sessionManager"), "appendLabelChange", &.{ first_arg, argument(args, 1) });
            break :labeled c.pi_js_undefined();
        },
        .getActiveTools => try scope.invoke(receiver, "getActiveToolNames", &.{}),
        .getAllTools, .getContextUsage => try scope.invoke(receiver, @tagName(kind), &.{}),
        .getSettings => try scope.invoke(try scope.get(receiver, "settingsManager"), "getSettings", &.{}),
        .refreshTools => try scope.invoke(receiver, "_refreshToolRegistry", &.{}),
        .getCommands => try commands(&scope, receiver, runner),
        .getThinkingLevel => try scope.get(receiver, "thinkingLevel"),
        .getModel => try scope.get(receiver, "model"),
        .getScopedModels => try scope.get(receiver, "_scopedModels"),
        .isIdle => try scope.get(receiver, "isIdle"),
        .isProjectTrusted => try scope.invoke(try scope.get(receiver, "settingsManager"), "isProjectTrusted", &.{}),
        .getSignal => try scope.get(try scope.get(receiver, "agent"), "signal"),
        .abort => aborted: {
            _ = try scope.invoke(receiver, if (scope.truthy(try scope.get(receiver, "_extensionAbortHandler"))) "_extensionAbortHandler" else "abort", &.{});
            break :aborted c.pi_js_undefined();
        },
        .hasPendingMessages => c.pi_js_bool(engine.context, @intFromBool(try scope.positive(try scope.get(receiver, "pendingMessageCount")))),
        .shutdown => shutdown: {
            const handler = try scope.get(receiver, "_extensionShutdownHandler");
            if (!temp.nullish(handler)) _ = try scope.call(handler, receiver, &.{});
            break :shutdown c.pi_js_undefined();
        },
        .compact => compacted: {
            try compactAsync(engine, receiver, first_arg);
            break :compacted c.pi_js_undefined();
        },
        .getSystemPrompt => try scope.get(receiver, "systemPrompt"),
        .getSystemPromptOptions => try scope.get(receiver, "_baseSystemPromptOptions"),
        .executeTool => try scope.invoke(receiver, "_executeNestedToolCall", &.{ first_arg, argument(args, 1), argument(args, 2), argument(args, 3) }),
        .getCallableTools => try scope.invoke(receiver, "_getCallableTools", &.{}),
        .registerProvider, .registerNativeProvider, .unregisterProvider, .registerVirtualModel, .unregisterVirtualModel => registered: {
            const runtime = try scope.get(receiver, "_modelRuntime");
            _ = try scope.invoke(runtime, @tagName(kind), if (kind == .registerProvider or kind == .unregisterVirtualModel) &.{ first_arg, argument(args, 1) } else &.{first_arg});
            _ = try scope.invoke(receiver, "_refreshCurrentModelFromRegistry", &.{});
            break :registered c.pi_js_undefined();
        },
        .setModel => unreachable,
    };
    return c.JS_DupValue(engine.context, result);
}
fn setModelAsync(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const flow = @import("native_agent_async.zig");
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    setModelStart(engine, pending.owner, argument(args, 0)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn setModelStart(engine: *em.Engine, owner: c.JSValue, model: c.JSValue) !void {
    const flow = @import("native_agent_async.zig");
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const runtime = try scope.get(receiver, "_modelRuntime");
    const configured = try scope.get(runtime, "hasConfiguredAuth");
    if (!scope.truthy(try scope.call(configured, runtime, &.{try scope.get(model, "provider")}))) return flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
    const result = try scope.invoke(receiver, "setModel", &.{model});
    try flow.wait(modelSettled, engine, owner, result, 0);
}
fn modelSettled(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, failed: bool, _: c_int) !void {
    return @import("native_agent_async.zig").settle(engine, owner, failed, if (failed) value else c.pi_js_bool(engine.context, 1));
}
fn compactAsync(engine: *em.Engine, receiver: c.JSValue, options: c.JSValue) !void {
    const flow = @import("native_agent_async.zig");
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    scope.put(pending.owner, "options", options) catch |err| return flow.rejectError(engine, pending.owner, err);
    compactStart(engine, pending.owner) catch |err| {
        compactError(engine, pending.owner, flow.reason(engine, err)) catch |failure| try flow.rejectError(engine, pending.owner, failure);
    };
}
fn compactStart(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const options = try scope.get(owner, "options");
    const compact = try scope.get(receiver, "compact");
    const instructions = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "customInstructions");
    const pending = try scope.call(compact, receiver, &.{instructions});
    try @import("native_agent_async.zig").wait(compactSettled, engine, owner, pending, 0);
}
fn compactSettled(engine: *em.Engine, owner: c.JSValue, result: c.JSValue, failed: bool, _: c_int) !void {
    if (failed) return compactError(engine, owner, c.JS_DupValue(engine.context, result));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = try scope.get(owner, "options");
    const complete = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "onComplete");
    if (!temp.nullish(complete)) {
        _ = scope.call(complete, options, &.{result}) catch |err| return compactError(engine, owner, @import("native_agent_async.zig").reason(engine, err));
    }
    try @import("native_agent_async.zig").settle(engine, owner, false, c.pi_js_undefined());
}
fn compactError(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    defer engine.freeValue(reason);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const is_error = c.JS_IsInstanceOf(engine.context, reason, try scope.global("Error"));
    if (is_error < 0) return js.capture(engine);
    const error_value = if (is_error != 0) reason else wrapped: {
        const constructor = try scope.global("Error");
        const message = try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason});
        var args = [_]c.JSValue{message};
        break :wrapped try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args)));
    };
    const options = try scope.get(owner, "options");
    const callback = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "onError");
    if (!temp.nullish(callback)) {
        _ = scope.call(callback, options, &.{error_value}) catch |err| return @import("native_agent_async.zig").rejectError(engine, owner, err);
    }
    try @import("native_agent_async.zig").settle(engine, owner, false, c.pi_js_undefined());
}
fn dispatch(engine: *em.Engine, receiver: c.JSValue, operation: Method, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = switch (operation) {
        ._refreshToolRegistry => result: {
            try refresh(&scope, receiver, input);
            break :result c.pi_js_undefined();
        },
        ._normalizePromptSnippet => try snippet(&scope, input),
        ._normalizePromptGuidelines => try guidelines(&scope, input),
        ._isAllowedTool => allowed: {
            const excluded = try scope.get(receiver, "_excludedTools");
            if (!temp.nullish(excluded) and scope.truthy(try scope.call(excluded, receiver, &.{input}))) break :allowed c.pi_js_bool(engine.context, 0);
            if (!scope.truthy(try scope.get(receiver, "_allowedTools")) or scope.truthy(try scope.invoke(receiver, "_allowedTools", &.{input}))) break :allowed c.pi_js_bool(engine.context, 1);
            if (scope.truthy(try scope.get(receiver, "_allowlistFiltersMcp"))) break :allowed c.pi_js_bool(engine.context, 0);
            break :allowed try mcp(&scope, input);
        },
        ._isDeclarable => declarable: {
            const exposure = try scope.invoke(receiver, "_getToolExposure", &.{input});
            break :declarable c.pi_js_bool(engine.context, @intFromBool(scope.equal(exposure, try scope.text("direct")) or scope.equal(exposure, try scope.text("model-only"))));
        },
        ._isActivatedOnRegistration => activated: {
            const declarable = try scope.invoke(receiver, "_isDeclarable", &.{input});
            if (!scope.truthy(declarable)) break :activated declarable;
            const entry = try scope.invoke(try scope.get(receiver, "_toolDefinitions"), "get", &.{input});
            const active = if (temp.nullish(entry)) c.pi_js_undefined() else try scope.get(try scope.get(entry, "definition"), "defaultActive");
            break :activated c.pi_js_bool(engine.context, @intFromBool(!scope.equal(active, c.pi_js_bool(engine.context, 0))));
        },
        ._setActiveTools => active: {
            const tools = try scope.invoke(receiver, "_applyToolLoadout", &.{input});
            var iterator = try js.Iterator.init(engine, tools, try symbol(&scope));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |tool| {
                defer engine.freeValue(tool);
                const pending = try scope.get(receiver, "_pendingToolNames");
                const delete = try scope.get(pending, "delete");
                _ = try scope.call(delete, pending, &.{try scope.get(tool, "name")});
            }
            const rebuild_method = try scope.get(receiver, "_rebuildSystemPrompt");
            _ = try scope.call(rebuild_method, receiver, &.{try map(&scope, tools, "map", .tool_name, receiver)});
            break :active c.pi_js_undefined();
        },
        ._rebuildSystemPrompt => result: {
            try rebuild(&scope, receiver, input);
            break :result c.pi_js_undefined();
        },
        ._buildRuntime => result: {
            try buildRuntime(&scope, receiver, input);
            break :result c.pi_js_undefined();
        },
        ._applyExtensionBindings => result: {
            try applyBindings(&scope, receiver, input);
            break :result c.pi_js_undefined();
        },
        ._refreshCurrentModelFromRegistry => result: {
            try refreshModel(&scope, receiver);
            break :result c.pi_js_undefined();
        },
        ._bindExtensionCore => result: {
            try bindCore(&scope, receiver, input);
            break :result c.pi_js_undefined();
        },
        ._restoreToolsFromTranscript => result: {
            const modifiers = if (c.JS_IsUndefined(input)) try scope.array() else input;
            try restore(&scope, receiver, modifiers);
            break :result c.pi_js_undefined();
        },
    };
    return c.JS_DupValue(engine.context, result);
}
