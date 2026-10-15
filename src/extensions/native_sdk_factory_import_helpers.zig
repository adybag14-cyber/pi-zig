//! Full Source factory selection/import helpers. Provider defaults are derived
//! unchanged from latest4954 model-resolver.ts; no available-model subset or
//! empty Models substitute is used. Config paths remain actual imports.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const functions = @import("native_node_function.zig");
const c = em.c;
const Body = enum(c_int) { findInitialModel, getBranchSelection, isToolModifier, getToolListError, formatNoModelsAvailableMessage };
pub fn create(engine: *em.Engine, get_docs_path: c.JSValue, join: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, get_docs_path) or !c.JS_IsFunction(engine.context, join)) return error.RequiredActualSdkFactoryConfigPaths;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bytes = @embedFile("fixtures/sdk-factory-default-models-4954.json");
    const defaults = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "source4954-default-models.json")));
    const exports = try scope.object();
    const predicate_roots = [_]c.JSValue{ defaults, get_docs_path, join, c.pi_js_undefined(), c.JS_NewInt32(engine.context, @intFromEnum(Body.isToolModifier)) };
    const modifier_function = try scope.own(try functions.create(engine, "isToolModifier", 1, exported, &predicate_roots));
    inline for (@typeInfo(Body).@"enum".fields) |field| {
        const roots = [_]c.JSValue{ defaults, get_docs_path, join, modifier_function, c.JS_NewInt32(engine.context, field.value) };
        const length = if (field.value == @intFromEnum(Body.getBranchSelection)) 2 else if (field.value == @intFromEnum(Body.formatNoModelsAvailableMessage)) 0 else 1;
        const function = if (field.value == @intFromEnum(Body.isToolModifier)) modifier_function else try scope.own(try (if (field.value == @intFromEnum(Body.findInitialModel)) functions.createMethod(engine, field.name, length, exported, &roots) else functions.create(engine, field.name, length, exported, &roots)));
        if (field.value == @intFromEnum(Body.findInitialModel)) if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
        try scope.put(exports, field.name, function);
    }
    try scope.put(exports, "applyToolModifiers", try scope.own(try functions.create(engine, "applyToolModifiers", 2, applyModifiers, &.{})));
    try scope.put(exports, "createToolNameMatcher", try scope.own(try @import("native_sdk_tool_name_matcher.zig").create(engine)));
    try scope.put(exports, "DEFAULT_THINKING_LEVEL", try scope.text("medium"));
    const tool_names = try scope.array();
    inline for (.{ "read", "bash", "edit", "write" }, 0..) |name, index| try scope.index(tool_names, index, try scope.text(name));
    try scope.put(exports, "DEFAULT_TOOL_NAMES", tool_names);
    try scope.put(exports, "defaultModelPerProvider", defaults);
    return c.JS_DupValue(engine.context, exports);
}
fn arg(argc: c_int, argv: [*c]c.JSValue, index: usize) c.JSValue {
    return if (argc > @as(c_int, @intCast(index))) argv[index] else c.pi_js_undefined();
}
fn exported(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var mode: i32 = 0;
    if (c.JS_ToInt32(engine.context, &mode, roots[4]) < 0) return js.capture(engine);
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else c.pi_js_undefined();
    const body: Body = @enumFromInt(mode);
    return if (body == .findInitialModel) initialPromise(engine, first, roots[0]) else run(engine, body, first, second, roots);
}
fn applyModifiers(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return @import("native_sdk_tool_modifiers.zig").apply(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
}
fn run(engine: *em.Engine, body: Body, first: c.JSValue, second: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (body) {
        .findInitialModel => unreachable,
        .getBranchSelection => return branchSelection(engine, first, second),
        .isToolModifier => return c.pi_js_bool(engine.context, @intFromBool(try modifier(&scope, first))),
        .getToolListError => {
            const filter = try scope.get(first, "filter");
            const predicate = roots[3];
            const modifiers = try scope.call(filter, first, &.{predicate});
            if (scope.equal(try scope.get(modifiers, "length"), c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
            if (try arithmetic.compare(engine, .less, try scope.get(modifiers, "length"), try scope.get(first, "length"))) return sdk.text(engine, "tool names cannot be mixed with +name or -name entries");
            const find = try scope.get(modifiers, "find");
            const matches = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, patternCallback, "", 1)));
            const pattern = try scope.call(find, modifiers, &.{matches});
            if (scope.truthy(pattern)) return c.JS_DupValue(engine.context, try scope.concat(try scope.text("+name and -name entries take exact tool names, not patterns: "), try scope.stringify(pattern)));
            return c.pi_js_undefined();
        },
        .formatNoModelsAvailableMessage => {
            const lines = try scope.array();
            try scope.index(lines, 0, try scope.text("Use /login to log into a provider via OAuth or API key. See:"));
            inline for (.{ "providers.md", "models.md" }, 1..) |name, index| {
                const docs = try scope.call(roots[1], c.pi_js_undefined(), &.{});
                const path = try scope.call(roots[2], c.pi_js_undefined(), &.{ docs, try scope.text(name) });
                try scope.index(lines, index, try scope.concat(try scope.text("  "), try scope.stringify(path)));
            }
            const help = try scope.invoke(lines, "join", &.{try scope.text("\n")});
            return c.JS_DupValue(engine.context, try scope.concat(try scope.text("No models available. "), try scope.stringify(help)));
        },
    }
}
fn modifier(scope: *Scope, value: c.JSValue) !bool {
    return c.JS_IsString(value) and (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("+")})) or scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("-")})));
}
fn patternCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(context, scope.invoke(arg(argc, args, 0), "includes", &.{scope.text("*") catch |err| return sdk.fail(engine, err)}) catch |err| return sdk.fail(engine, err));
}
fn initialPromise(engine: *em.Engine, options: c.JSValue, defaults: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const value = findInitial(engine, options, defaults) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    defer engine.freeValue(value);
    try flow.settle(engine, pending.owner, false, value);
    return pending.promise;
}
fn result(scope: *Scope, model: c.JSValue, thinking: c.JSValue) !c.JSValue {
    const value = try scope.object();
    try scope.put(value, "model", model);
    try scope.put(value, "thinkingLevel", thinking);
    try scope.put(value, "fallbackMessage", c.pi_js_undefined());
    return value;
}
fn findInitial(engine: *em.Engine, options: c.JSValue, defaults: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const scoped = try scope.get(options, "scopedModels");
    const continuing = try scope.get(options, "isContinuing");
    const provider = try scope.get(options, "defaultProvider");
    const model_id = try scope.get(options, "defaultModelId");
    const thinking = try scope.get(options, "defaultThinkingLevel");
    const levels = try scope.get(options, "modelThinkingLevels");
    const runtime = try scope.get(options, "modelRuntime");
    const medium = try scope.text("medium");
    if (try scope.positive(try scope.get(scoped, "length")) and !scope.truthy(continuing)) {
        const row = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, scoped, 0)));
        const per_model = if (temp.nullish(levels)) c.pi_js_undefined() else try scope.own(try js.getKey(engine, levels, try scope.concat(try scope.concat(try scope.stringify(try scope.get(try scope.get(row, "model"), "provider")), try scope.text("/")), try scope.stringify(try scope.get(try scope.get(row, "model"), "id")))));
        const model = try scope.get(row, "model");
        var chosen = try scope.get(row, "thinkingLevel");
        if (temp.nullish(chosen)) chosen = per_model;
        if (temp.nullish(chosen)) chosen = thinking;
        if (temp.nullish(chosen)) chosen = medium;
        return c.JS_DupValue(engine.context, try result(&scope, model, chosen));
    }
    if (scope.truthy(provider) and scope.truthy(model_id)) {
        const found = try scope.invoke(runtime, "getModel", &.{ provider, model_id });
        const configured = if (scope.truthy(found)) configured: {
            const check = try scope.get(runtime, "hasConfiguredAuth");
            break :configured scope.truthy(try scope.call(check, runtime, &.{try scope.get(found, "provider")}));
        } else false;
        if (configured) {
            const per_model = if (temp.nullish(levels)) c.pi_js_undefined() else try scope.own(try js.getKey(engine, levels, try scope.concat(try scope.concat(try scope.stringify(provider), try scope.text("/")), try scope.stringify(model_id))));
            return c.JS_DupValue(engine.context, try result(&scope, found, if (scope.truthy(per_model)) per_model else if (scope.truthy(thinking)) thinking else medium));
        }
    }
    const available = try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(engine, try scope.invoke(runtime, "getAvailableSnapshot", &.{}), null));
    if (try scope.positive(try scope.get(available, "length"))) {
        const keys = try scope.invoke(try scope.global("Object"), "keys", &.{defaults});
        var iterator = try js.Iterator.init(engine, keys, try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context))));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |key| {
            defer engine.freeValue(key);
            var frame: Scope = .{ .engine = engine };
            defer frame.deinit();
            const id = try frame.own(try js.getKey(engine, defaults, key));
            const find = try frame.get(available, "find");
            var roots = [_]c.JSValue{ key, id };
            const predicate = try frame.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, matchesDefault, "", 1, 0, roots.len, &roots)));
            const match = try frame.call(find, available, &.{predicate});
            if (frame.truthy(match)) {
                try iterator.close();
                return c.JS_DupValue(engine.context, try result(&scope, match, medium));
            }
        }
        return c.JS_DupValue(engine.context, try result(&scope, try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, available, 0))), medium));
    }
    return c.JS_DupValue(engine.context, try result(&scope, c.pi_js_undefined(), medium));
}
fn matchesDefault(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const row = arg(argc, argv, 0);
    const provider = scope.get(row, "provider") catch |err| return sdk.fail(engine, err);
    if (!scope.equal(provider, roots[0])) return c.pi_js_bool(context, 0);
    const id = scope.get(row, "id") catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(context, @intFromBool(scope.equal(id, roots[1])));
}
fn selection(scope: *Scope, entry: c.JSValue) !c.JSValue {
    const value = try scope.object();
    try scope.put(value, "provider", try scope.get(entry, "provider"));
    try scope.put(value, "modelId", try scope.get(entry, "modelId"));
    return value;
}
fn previousChange(scope: *Scope, branch: c.JSValue, before: c.JSValue) !c.JSValue {
    var index = try scope.own(try arithmetic.binary(scope.engine, .subtract, before, c.JS_NewInt32(scope.engine.context, 1)));
    while (try arithmetic.compare(scope.engine, .greater_equal, index, c.JS_NewInt32(scope.engine.context, 0))) {
        var frame: Scope = .{ .engine = scope.engine };
        defer frame.deinit();
        const entry = try frame.own(try js.getKey(scope.engine, branch, index));
        if (frame.equal(try frame.get(entry, "type"), try frame.text("model_change"))) return selection(scope, entry);
        index = try scope.own(try arithmetic.binary(scope.engine, .subtract, index, c.JS_NewInt32(scope.engine.context, 1)));
    }
    return c.pi_js_undefined();
}
fn branchSelection(engine: *em.Engine, branch: c.JSValue, lookup: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var index = try scope.own(try arithmetic.binary(engine, .subtract, try scope.get(branch, "length"), c.JS_NewInt32(engine.context, 1)));
    while (try arithmetic.compare(engine, .greater_equal, index, c.JS_NewInt32(engine.context, 0))) {
        var frame: Scope = .{ .engine = engine };
        defer frame.deinit();
        const entry = try frame.own(try js.getKey(engine, branch, index));
        if (frame.equal(try frame.get(entry, "type"), try frame.text("model_change"))) return c.JS_DupValue(engine.context, try selection(&frame, entry));
        if (frame.equal(try frame.get(entry, "type"), try frame.text("message")) and frame.equal(try frame.get(try frame.get(entry, "message"), "role"), try frame.text("assistant")) and !try isVirtual(&frame, try frame.get(entry, "message"))) {
            const response = try frame.object();
            try frame.put(response, "provider", try frame.get(try frame.get(entry, "message"), "provider"));
            try frame.put(response, "modelId", try frame.get(try frame.get(entry, "message"), "model"));
            const change = try previousChange(&frame, branch, index);
            const model = if (frame.truthy(change)) try frame.call(lookup, c.pi_js_undefined(), &.{ try frame.get(change, "provider"), try frame.get(change, "modelId") }) else change;
            return c.JS_DupValue(engine.context, if (frame.truthy(change) and frame.truthy(model) and try isVirtual(&frame, model)) change else response);
        }
        index = try scope.own(try arithmetic.binary(engine, .subtract, index, c.JS_NewInt32(engine.context, 1)));
    }
    return c.pi_js_undefined();
}
fn isVirtual(scope: *Scope, value: c.JSValue) !bool {
    return scope.equal(try scope.get(value, "api"), try scope.text("pi-virtual"));
}
