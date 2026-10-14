//! Original AgentSession prompt/tool-loadout algorithms over live JS fields.
//! Installation is private until the complete class and factory are qualified.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;

const Method = enum(c_int) { _applyToolLoadout, _getToolExposure, _isActivatable, _getCallableTools, getActiveToolNames, getCallableToolNames, _preparePromptAndToolLoadout };
const Callback = enum(c_int) { name, active, hook, callable, exposure, namespace, guidelines, description };

pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    try @import("native_sdk_prompt_render.zig").initialize(engine);
    try @import("native_sdk_session_restore.zig").install(engine, prototype);
    inline for (std.meta.fields(Method)) |field| {
        const installed_function = try engine.checked(c.pi_js_function_magic(engine.context, methodCallback, field.name, switch (@as(Method, @enumFromInt(field.value))) {
            .getActiveToolNames, .getCallableToolNames, ._getCallableTools => 0,
            else => 1,
        }, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, installed_function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn methodCallback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return method(engine, receiver, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return callbackValue(engine, @enumFromInt(magic), roots, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn function(scope: *Scope, kind: Callback, roots: []const c.JSValue) !c.JSValue {
    const name: [*:0]const u8 = switch (kind) {
        .exposure => "getExposure",
        .namespace => "getNamespace",
        .guidelines => "getPromptGuidelines",
        else => "",
    };
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, name, 1, @intFromEnum(kind), @intCast(roots.len), @constCast(roots.ptr))));
}
fn collection(scope: *Scope, receiver: c.JSValue, name: [*:0]const u8, kind: Callback, roots: []const c.JSValue) !c.JSValue {
    const callee = try scope.get(receiver, name);
    return scope.call(callee, receiver, &.{try function(scope, kind, roots)});
}
fn spread(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(scope.engine, value, null));
}
fn state(scope: *Scope, session: c.JSValue) !c.JSValue {
    return scope.get(try scope.get(session, "agent"), "state");
}
fn mapEntry(scope: *Scope, session: c.JSValue, field: [*:0]const u8, name: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.get(session, field), "get", &.{name});
}
fn mcpName(scope: *Scope, name: c.JSValue) !bool {
    if (scope.truthy(try scope.invoke(name, "startsWith", &.{try scope.text("mcp__")}))) return true;
    inline for (.{ "list_mcp_resources", "list_mcp_resource_templates", "read_mcp_resource" }) |resource| if (scope.equal(name, try scope.text(resource))) return true;
    return false;
}
fn exposure(scope: *Scope, session: c.JSValue, name: c.JSValue) !c.JSValue {
    const entry = try mapEntry(scope, session, "_toolDefinitions", name);
    const value = if (temp.nullish(entry)) c.pi_js_undefined() else try scope.get(try scope.get(entry, "definition"), "exposure");
    return if (temp.nullish(value)) scope.text("direct") else value;
}
fn activatable(scope: *Scope, session: c.JSValue, name: c.JSValue) !bool {
    if (!scope.truthy(try scope.get(session, "_allowedTools"))) return true;
    if (scope.truthy(try scope.invoke(session, "_allowedTools", &.{name})) or !try mcpName(scope, name)) return true;
    if (scope.equal(try scope.invoke(session, "_getToolExposure", &.{name}), try scope.text("direct"))) return false;
    return scope.truthy(try scope.invoke(try scope.get(session, "_toolRegistry"), "has", &.{try scope.text("tool_search")}));
}
fn callbackValue(engine: *em.Engine, kind: Callback, roots: [*c]c.JSValue, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = switch (kind) {
        .name => try scope.get(value, "name"),
        .active => active: {
            const tool = try mapEntry(&scope, roots[0], "_toolRegistry", value);
            const output = try scope.array();
            if (scope.truthy(tool) and !scope.equal(try scope.invoke(roots[0], "_getToolExposure", &.{value}), try scope.text("hidden")) and scope.truthy(try scope.invoke(roots[0], "_isActivatable", &.{value}))) try scope.index(output, 0, tool);
            break :active output;
        },
        .hook => hook: {
            const definitions = try scope.get(roots[0], "_toolDefinitions");
            const get = try scope.get(definitions, "get");
            const name = try scope.get(value, "name");
            const entry = try scope.call(get, definitions, &.{name});
            const output = try scope.array();
            if (!temp.nullish(entry) and scope.truthy(try scope.get(try scope.get(entry, "definition"), "prepareLoadout"))) try scope.index(output, 0, entry);
            break :hook output;
        },
        .callable => callable: {
            const classify = try scope.get(roots[0], "_getToolExposure");
            const name = try scope.get(value, "name");
            const selected_exposure = try scope.call(classify, roots[0], &.{name});
            const included = scope.equal(selected_exposure, try scope.text("codemode")) or scope.equal(selected_exposure, try scope.text("deferred")) or (scope.equal(selected_exposure, try scope.text("direct")) and scope.truthy(try scope.invoke(roots[1], "has", &.{try scope.get(value, "name")})));
            break :callable c.pi_js_bool(engine.context, @intFromBool(included));
        },
        .exposure => try scope.invoke(roots[0], "_getToolExposure", &.{value}),
        .namespace => namespace: {
            const entry = try mapEntry(&scope, roots[0], "_toolDefinitions", value);
            break :namespace if (temp.nullish(entry)) c.pi_js_undefined() else try scope.get(try scope.get(entry, "definition"), "namespace");
        },
        .guidelines => guidelines: {
            const rows = try mapEntry(&scope, roots[0], "_toolPromptGuidelines", value);
            break :guidelines if (temp.nullish(rows)) try scope.array() else rows;
        },
        .description => description: {
            const get = try scope.get(roots[0], "get");
            const name = try scope.get(value, "name");
            const replacement = try scope.call(get, roots[0], &.{name});
            if (c.JS_IsUndefined(replacement)) break :description value;
            const copy = try scope.own(try js.spread(engine, value));
            try scope.put(copy, "description", replacement);
            break :description copy;
        },
    };
    return c.JS_DupValue(engine.context, result);
}
fn callable(scope: *Scope, session: c.JSValue, active_input: c.JSValue) !c.JSValue {
    const active = if (c.JS_IsUndefined(active_input)) default_active: {
        const constructor = try scope.global("Set");
        var arguments = [_]c.JSValue{try scope.invoke(session, "getActiveToolNames", &.{})};
        break :default_active try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, arguments.len, &arguments)));
    } else active_input;
    const registered = try spread(scope, try scope.invoke(try scope.get(session, "_toolRegistry"), "values", &.{}));
    return collection(scope, registered, "filter", .callable, &.{ session, active });
}
fn errorInstance(scope: *Scope, reason: c.JSValue) !bool {
    const result = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (result < 0) return js.capture(scope.engine);
    return result != 0;
}
fn reportHookError(scope: *Scope, session: c.JSValue, source_info: c.JSValue, reason: c.JSValue) !void {
    const runner = try scope.get(session, "_extensionRunner");
    const emit = try scope.get(runner, "emitError");
    const report = try scope.object();
    try scope.put(report, "extensionPath", try scope.get(source_info, "path"));
    try scope.put(report, "event", try scope.text("prepare_loadout"));
    try scope.put(report, "error", if (try errorInstance(scope, reason)) try scope.get(reason, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason}));
    try scope.put(report, "stack", if (try errorInstance(scope, reason)) try scope.get(reason, "stack") else c.pi_js_undefined());
    _ = try scope.call(emit, runner, &.{report});
}
fn applyHook(scope: *Scope, definition: c.JSValue, loadout: c.JSValue, descriptions: c.JSValue, hidden: c.JSValue, symbol: c.JSValue) !void {
    const prepare_hook = try scope.get(definition, "prepareLoadout");
    const changes = if (temp.nullish(prepare_hook)) c.pi_js_undefined() else try scope.call(prepare_hook, definition, &.{loadout});
    const object = try scope.global("Object");
    const entries = try scope.get(object, "entries");
    const overrides = if (temp.nullish(changes)) c.pi_js_undefined() else try scope.get(changes, "descriptions");
    const rows = try scope.call(entries, object, &.{if (temp.nullish(overrides)) try scope.object() else overrides});
    var iterator = try js.Iterator.init(scope.engine, rows, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |row| {
        defer scope.engine.freeValue(row);
        const pair = try js.pair(scope.engine, row, symbol);
        defer for (pair) |value| scope.engine.freeValue(value);
        _ = try scope.invoke(descriptions, "set", &.{ pair[0], pair[1] });
    }
    const concealed = if (temp.nullish(changes)) c.pi_js_undefined() else try scope.get(changes, "hiddenDeclarations");
    var names = try js.Iterator.init(scope.engine, if (temp.nullish(concealed)) try scope.array() else concealed, symbol);
    defer names.deinit();
    errdefer names.closePreserving();
    while (try names.next()) |name| {
        defer scope.engine.freeValue(name);
        _ = try scope.invoke(hidden, "add", &.{name});
    }
}
fn apply(scope: *Scope, session: c.JSValue, names: c.JSValue) !c.JSValue {
    const unique = try spread(scope, try scope.own(try js.builtin(scope.engine, "Set", &.{names})));
    const tools = try collection(scope, unique, "flatMap", .active, &.{session});
    const hooks = try collection(scope, tools, "flatMap", .hook, &.{session});
    const hidden = try scope.own(try js.builtin(scope.engine, "Set", &.{}));
    var declared = tools;
    if (try scope.positive(try scope.get(hooks, "length"))) {
        const loadout = try scope.object();
        try scope.put(loadout, "declared", tools);
        const callable_method = try scope.get(session, "_getCallableTools");
        const set_constructor = try scope.global("Set");
        const active_names = try collection(scope, tools, "map", .name, &.{});
        var set_arguments = [_]c.JSValue{active_names};
        const active = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, set_constructor, set_arguments.len, &set_arguments)));
        try scope.put(loadout, "callable", try scope.call(callable_method, session, &.{active}));
        try scope.put(loadout, "registered", try spread(scope, try scope.invoke(try scope.get(session, "_toolRegistry"), "values", &.{})));
        try scope.put(loadout, "getExposure", try function(scope, .exposure, &.{session}));
        try scope.put(loadout, "getNamespace", try function(scope, .namespace, &.{session}));
        try scope.put(loadout, "getPromptGuidelines", try function(scope, .guidelines, &.{session}));
        const descriptions = try scope.own(try js.builtin(scope.engine, "Map", &.{}));
        const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
        var iterator = try js.Iterator.init(scope.engine, hooks, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |entry| {
            defer scope.engine.freeValue(entry);
            const definition = try scope.get(entry, "definition");
            const source_info = try scope.get(entry, "sourceInfo");
            const generation = scope.engine.native_allocation_generation;
            applyHook(scope, definition, loadout, descriptions, hidden, symbol) catch |err| {
                const original = scope.engine.nativeAllocationError(err, generation);
                if (original != error.JavaScriptException) return original;
                const reason = try scope.own(c.JS_DupValue(scope.engine.context, scope.engine.captured_exception orelse return err));
                try reportHookError(scope, session, source_info, reason);
            };
        }
        declared = try collection(scope, tools, "map", .description, &.{descriptions});
    }
    try scope.set(session, "_hiddenDeclarations", hidden);
    try scope.set(try state(scope, session), "tools", declared);
    return declared;
}
fn prepare(scope: *Scope, session: c.JSValue, options: c.JSValue, input_messages: c.JSValue) !c.JSValue {
    const messages = if (c.JS_IsUndefined(input_messages)) try scope.get(try state(scope, session), "messages") else input_messages;
    const apply_method = try scope.get(session, "_applyToolLoadout");
    const selected = try scope.get(options, "selectedTools");
    const tools = try scope.call(apply_method, session, &.{selected});
    try scope.set(options, "selectedTools", try collection(scope, tools, "map", .name, &.{}));
    try scope.set(options, "hiddenTools", try spread(scope, try scope.get(session, "_hiddenDeclarations")));
    const previous = try scope.own(try @import("native_sdk_transcript_replay.zig").currentSystemMessage(scope.engine, messages));
    const previous_sections = if (temp.nullish(previous)) c.pi_js_undefined() else try scope.get(previous, "sections");
    const before = if (temp.nullish(previous_sections)) try scope.object() else previous_sections;
    const current = try scope.own(try @import("native_sdk_prompt_render.zig").buildSections(scope.engine, options));
    const patch = try scope.own(try @import("native_sdk_prompt_render.zig").diffSections(scope.engine, before, current));
    if (!scope.truthy(patch)) return c.pi_js_undefined();
    const result = try scope.object();
    try scope.put(result, "role", try scope.text("system"));
    try scope.put(result, "content", try scope.text(""));
    try scope.put(result, "sections", patch);
    try scope.put(result, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    return result;
}
fn method(engine: *em.Engine, session: c.JSValue, operation: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const result = switch (operation) {
        ._applyToolLoadout => try apply(&scope, session, first),
        ._getToolExposure => try exposure(&scope, session, first),
        ._isActivatable => c.pi_js_bool(engine.context, @intFromBool(try activatable(&scope, session, first))),
        ._getCallableTools => try callable(&scope, session, first),
        .getActiveToolNames => try collection(&scope, try scope.get(try state(&scope, session), "tools"), "map", .name, &.{}),
        .getCallableToolNames => try collection(&scope, try scope.invoke(session, "_getCallableTools", &.{}), "map", .name, &.{}),
        ._preparePromptAndToolLoadout => try prepare(&scope, session, first, if (args.len > 1) args[1] else c.pi_js_undefined()),
    };
    return c.JS_DupValue(engine.context, result);
}
