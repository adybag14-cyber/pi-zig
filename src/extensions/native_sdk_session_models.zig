//! Original ordinary AgentSession model selection and thinking-level methods.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const values = @import("native_ai_model_values.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const Method = enum(c_int) { _emitModelSelect, setModel, _addPersistedDefaultToNonEmptyScope, cycleModel, _cycleScopedModel, _cycleAvailableModel, setThinkingLevel, cycleThinkingLevel, getAvailableThinkingLevels, supportsThinking, _getThinkingLevelForModelSwitch, _clampThinkingLevel };
fn isAsync(method: Method) bool {
    return switch (method) {
        ._emitModelSelect, .setModel, .cycleModel, ._cycleScopedModel, ._cycleAvailableModel => true,
        else => false,
    };
}
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const dependencies = try values.bindings(engine);
    defer engine.freeValue(dependencies);
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const length: c_int = switch (method) {
            ._emitModelSelect => 3,
            .setModel, ._addPersistedDefaultToNonEmptyScope, .setThinkingLevel => 1,
            ._cycleScopedModel, ._cycleAvailableModel, ._getThinkingLevelForModelSwitch, ._clampThinkingLevel => 2,
            else => 0,
        };
        var roots = [_]c.JSValue{dependencies};
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, length, field.value, roots.len, &roots));
        defer engine.freeValue(function);
        if (isAsync(method)) {
            const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
            defer engine.freeValue(parent);
            if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const method: Method = @enumFromInt(magic);
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    if (isAsync(method)) return begin(engine, session, method, args) catch |err| sdk.fail(engine, err);
    return sync(engine, session, method, args, roots[0]) catch |err| sdk.fail(engine, err);
}
fn sync(engine: *em.Engine, session: c.JSValue, method: Method, args: []const c.JSValue, dependencies: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (method) {
        .getAvailableThinkingLevels => {
            if (!scope.truthy(try scope.get(session, "model"))) return c.JS_DupValue(engine.context, try values.extended(&scope));
            const supported = try scope.get(dependencies, "getSupportedThinkingLevels");
            return js.call(engine, supported, c.pi_js_undefined(), &.{try scope.get(session, "model")});
        },
        .supportsThinking => {
            const model = try scope.get(session, "model");
            return c.pi_js_bool(engine.context, @intFromBool(!temp.nullish(model) and scope.truthy(try scope.get(model, "reasoning"))));
        },
        ._getThinkingLevelForModelSwitch => {
            if (!c.JS_IsUndefined(arg(args, 1))) return c.JS_DupValue(engine.context, arg(args, 1));
            const target = arg(args, 0);
            if (scope.truthy(target)) {
                const settings = try scope.get(session, "settingsManager");
                const function = try scope.get(settings, "getModelThinkingLevel");
                const level = try scope.call(function, settings, &.{ try scope.get(target, "provider"), try scope.get(target, "id") });
                if (!c.JS_IsUndefined(level)) return c.JS_DupValue(engine.context, level);
            }
            const configured = try scope.invoke(try scope.get(session, "settingsManager"), "getDefaultThinkingLevel", &.{});
            if (!temp.nullish(configured)) return c.JS_DupValue(engine.context, configured);
            const current = try scope.get(session, "thinkingLevel");
            return if (!temp.nullish(current)) c.JS_DupValue(engine.context, current) else sdk.text(engine, "medium");
        },
        ._clampThinkingLevel => {
            if (!scope.truthy(try scope.get(session, "model"))) return sdk.text(engine, "off");
            const clamp = try scope.get(dependencies, "clampThinkingLevel");
            return js.call(engine, clamp, c.pi_js_undefined(), &.{ try scope.get(session, "model"), arg(args, 0) });
        },
        .setThinkingLevel => {
            const level = arg(args, 0);
            const options = if (c.JS_IsUndefined(arg(args, 1))) try scope.object() else arg(args, 1);
            const available = try scope.invoke(session, "getAvailableThinkingLevels", &.{});
            const includes = try scope.invoke(available, "includes", &.{level});
            const effective = if (scope.truthy(includes)) level else try scope.invoke(session, "_clampThinkingLevel", &.{ level, available });
            const previous = try scope.get(try scope.get(try scope.get(session, "agent"), "state"), "thinkingLevel");
            const changing = !scope.equal(effective, previous);
            try scope.set(try scope.get(try scope.get(session, "agent"), "state"), "thinkingLevel", effective);
            if (scope.truthy(try scope.get(options, "persist"))) _ = try scope.invoke(try scope.get(session, "settingsManager"), "setDefaultThinkingLevel", &.{level});
            if (changing) {
                _ = try scope.invoke(try scope.get(session, "sessionManager"), "appendThinkingLevelChange", &.{effective});
                const emit = try scope.get(session, "_emit");
                const event = try scope.object();
                try scope.put(event, "type", try scope.text("thinking_level_changed"));
                try scope.put(event, "level", effective);
                _ = try scope.call(emit, session, &.{event});
                const runner = try scope.get(session, "_extensionRunner");
                const extension_emit = try scope.get(runner, "emit");
                const selected = try scope.object();
                try scope.put(selected, "type", try scope.text("thinking_level_select"));
                try scope.put(selected, "level", effective);
                try scope.put(selected, "previousLevel", previous);
                _ = try scope.call(extension_emit, runner, &.{selected});
            }
        },
        .cycleThinkingLevel => {
            const options = if (c.JS_IsUndefined(arg(args, 0))) try scope.object() else arg(args, 0);
            if (!scope.truthy(try scope.invoke(session, "supportsThinking", &.{}))) return c.pi_js_undefined();
            const levels = try scope.invoke(session, "getAvailableThinkingLevels", &.{});
            const index_of = try scope.get(levels, "indexOf");
            const index = try scope.call(index_of, levels, &.{try scope.get(session, "thinkingLevel")});
            const incremented = try scope.own(try arithmetic.binary(engine, .add, index, c.JS_NewInt32(engine.context, 1)));
            const next_index = try scope.own(try arithmetic.binary(engine, .remainder, incremented, try scope.get(levels, "length")));
            const next = try scope.own(try js.getKey(engine, levels, next_index));
            _ = try scope.invoke(session, "setThinkingLevel", &.{ next, options });
            return c.JS_DupValue(engine.context, next);
        },
        ._addPersistedDefaultToNonEmptyScope => try addDefault(&scope, session, arg(args, 0)),
        else => unreachable,
    }
    return c.pi_js_undefined();
}
const Predicate = enum(c_int) { scope_contains, enabled_contains, available_key, available_scope, find_scoped, find_available };
fn predicate(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return predicateValue(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn callback(scope: *Scope, kind: Predicate, captured: c.JSValue) !c.JSValue {
    var roots = [_]c.JSValue{captured};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, predicate, "", 1, @intFromEnum(kind), roots.len, &roots)));
}
fn predicateValue(engine: *em.Engine, kind: Predicate, value: c.JSValue, captured: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (kind) {
        .scope_contains, .find_scoped => return c.pi_js_bool(engine.context, @intFromBool(try values.equal(engine, try scope.get(value, "model"), captured))),
        .find_available => return c.pi_js_bool(engine.context, @intFromBool(try values.equal(engine, value, captured))),
        .enabled_contains => return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.invoke(value, "toLowerCase", &.{}), try scope.invoke(captured, "toLowerCase", &.{})))),
        .available_key => return key(&scope, value),
        .available_scope => {
            const has = try scope.get(captured, "has");
            const provider = try scope.stringify(try scope.get(try scope.get(value, "model"), "provider"));
            const prefix = try scope.concat(provider, try scope.text("\x00"));
            const model_id = try scope.stringify(try scope.get(try scope.get(value, "model"), "id"));
            return js.call(engine, has, captured, &.{try scope.concat(prefix, model_id)});
        },
    }
}
fn key(scope: *Scope, model: c.JSValue) !c.JSValue {
    const provider = try scope.stringify(try scope.get(model, "provider"));
    const prefix = try scope.concat(provider, try scope.text("\x00"));
    const id = try scope.stringify(try scope.get(model, "id"));
    return c.JS_DupValue(scope.engine.context, try scope.concat(prefix, id));
}
fn addDefault(scope: *Scope, session: c.JSValue, model: c.JSValue) !void {
    const engine = scope.engine;
    if (scope.equal(try scope.get(try scope.get(session, "_scopedModels"), "length"), c.JS_NewInt32(engine.context, 0))) return;
    const scoped = try scope.get(session, "_scopedModels");
    const some = try scope.get(scoped, "some");
    if (scope.truthy(try scope.call(some, scoped, &.{try callback(scope, .scope_contains, model)}))) return;
    const expanded = try scope.own(try @import("native_iterator_spread.zig").snapshot(engine, try scope.get(session, "_scopedModels")));
    const entry = try scope.object();
    try scope.put(entry, "model", model);
    try scope.index(expanded, @intCast(try sdk.length(engine, expanded)), entry);
    try scope.set(session, "_scopedModels", expanded);
    const enabled = try scope.invoke(try scope.get(session, "settingsManager"), "getEnabledModels", &.{});
    if (temp.nullish(enabled) or !scope.truthy(try scope.get(enabled, "length"))) return;
    const reference = try scope.concat(try scope.concat(try scope.stringify(try scope.get(model, "provider")), try scope.text("/")), try scope.stringify(try scope.get(model, "id")));
    const patterns = try scope.get(enabled, "some");
    if (scope.truthy(try scope.call(patterns, enabled, &.{try callback(scope, .enabled_contains, reference)}))) return;
    const settings = try scope.get(session, "settingsManager");
    const set = try scope.get(settings, "setEnabledModels");
    const updated = try scope.own(try @import("native_iterator_spread.zig").snapshot(engine, enabled));
    try scope.index(updated, @intCast(try sdk.length(engine, updated)), reference);
    _ = try scope.call(set, settings, &.{updated});
}
fn begin(engine: *em.Engine, session: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initial(engine, pending.owner, method, args) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initial(engine: *em.Engine, owner: c.JSValue, method: Method, args: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    try scope.put(owner, "method", c.JS_NewInt32(engine.context, @intFromEnum(method)));
    if (method == ._emitModelSelect) {
        if (try values.equal(engine, arg(args, 1), arg(args, 0))) return flow.settle(engine, owner, false, c.pi_js_undefined());
        return emitSelect(&scope, owner, arg(args, 0), arg(args, 1), arg(args, 2));
    }
    if (method == .setModel) {
        try scope.put(owner, "next", arg(args, 0));
        try scope.put(owner, "options", if (c.JS_IsUndefined(arg(args, 1))) try scope.object() else arg(args, 1));
        const runtime = try scope.get(session, "_modelRuntime");
        const check = try scope.get(runtime, "checkAuth");
        const pending = try scope.call(check, runtime, &.{try scope.get(arg(args, 0), "provider")});
        return flow.wait(continued, engine, owner, pending, 0);
    }
    const direction = if (c.JS_IsUndefined(arg(args, 0)) and method == .cycleModel) try scope.text("forward") else arg(args, 0);
    const options = if (c.JS_IsUndefined(arg(args, 1)) and method == .cycleModel) try scope.object() else arg(args, 1);
    if (method == .cycleModel) {
        const scoped = try scope.get(session, "_scopedModels");
        const use_scoped = try arithmetic.compare(engine, .greater, try scope.get(scoped, "length"), c.JS_NewInt32(engine.context, 0));
        const result = try scope.invoke(session, if (use_scoped) "_cycleScopedModel" else "_cycleAvailableModel", &.{ direction, options });
        return flow.wait(continued, engine, owner, result, 2);
    }
    try scope.put(owner, "options", options);
    const is_scoped = method == ._cycleScopedModel;
    try scope.put(owner, "isScoped", c.pi_js_bool(engine.context, @intFromBool(is_scoped)));
    const available = if (is_scoped) filtered: {
        const constructor = try scope.global("Set");
        const models = try scope.invoke(try scope.get(session, "_modelRuntime"), "getAvailableSnapshot", &.{});
        const map = try scope.get(models, "map");
        var input = [_]c.JSValue{try scope.call(map, models, &.{try callback(&scope, .available_key, c.pi_js_undefined())})};
        const ids = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, input.len, &input)));
        const scoped = try scope.get(session, "_scopedModels");
        const filter = try scope.get(scoped, "filter");
        break :filtered try scope.call(filter, scoped, &.{try callback(&scope, .available_scope, ids)});
    } else try scope.invoke(try scope.get(session, "_modelRuntime"), "getAvailableSnapshot", &.{});
    if (try arithmetic.compare(engine, .less_equal, try scope.get(available, "length"), c.JS_NewInt32(engine.context, 1))) return flow.settle(engine, owner, false, c.pi_js_undefined());
    const current = try scope.get(session, "model");
    try scope.put(owner, "previous", current);
    const finder = try scope.get(available, "findIndex");
    var index = try scope.call(finder, available, &.{try callback(&scope, if (is_scoped) .find_scoped else .find_available, current)});
    if (scope.equal(index, c.JS_NewInt32(engine.context, -1))) index = c.JS_NewInt32(engine.context, 0);
    const len = try scope.get(available, "length");
    const numerator = if (scope.equal(direction, try scope.text("forward"))) try scope.own(try arithmetic.binary(engine, .add, index, c.JS_NewInt32(engine.context, 1))) else try scope.own(try arithmetic.binary(engine, .add, try scope.own(try arithmetic.binary(engine, .subtract, index, c.JS_NewInt32(engine.context, 1))), len));
    const next_index = try scope.own(try arithmetic.binary(engine, .remainder, numerator, len));
    const next = try scope.own(try js.getKey(engine, available, next_index));
    try scope.put(owner, "next", next);
    try applySelection(engine, owner, is_scoped);
}
fn selectedModel(scope: *Scope, owner: c.JSValue, is_scoped: bool) !c.JSValue {
    const next = try scope.get(owner, "next");
    return if (is_scoped) scope.get(next, "model") else next;
}
fn applySelection(engine: *em.Engine, owner: c.JSValue, is_scoped: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const thinking_function = try scope.get(session, "_getThinkingLevelForModelSwitch");
    const model = try selectedModel(&scope, owner, is_scoped);
    const thinking = if (is_scoped) try scope.call(thinking_function, session, &.{ model, try scope.get(try scope.get(owner, "next"), "thinkingLevel") }) else try scope.call(thinking_function, session, &.{model});
    const state = try scope.get(try scope.get(session, "agent"), "state");
    try scope.set(state, "model", try selectedModel(&scope, owner, is_scoped));
    const manager = try scope.get(session, "sessionManager");
    const append = try scope.get(manager, "appendModelChange");
    _ = try scope.call(append, manager, &.{ try scope.get(try selectedModel(&scope, owner, is_scoped), "provider"), try scope.get(try selectedModel(&scope, owner, is_scoped), "id") });
    if (scope.truthy(try scope.get(try scope.get(owner, "options"), "persist"))) {
        const settings = try scope.get(session, "settingsManager");
        const set = try scope.get(settings, "setDefaultModelAndProvider");
        _ = try scope.call(set, settings, &.{ try scope.get(try selectedModel(&scope, owner, is_scoped), "provider"), try scope.get(try selectedModel(&scope, owner, is_scoped), "id") });
        const add = try scope.get(session, "_addPersistedDefaultToNonEmptyScope");
        _ = try scope.call(add, session, &.{try selectedModel(&scope, owner, is_scoped)});
    }
    _ = try scope.invoke(session, "setThinkingLevel", &.{thinking});
    const emit_function = try scope.get(session, "_emitModelSelect");
    const pending = try scope.call(emit_function, session, &.{ try selectedModel(&scope, owner, is_scoped), try scope.get(owner, "previous"), try scope.text(if (scope.truthy(try scope.get(owner, "isScoped")) or is_scoped or !c.JS_IsUndefined(try scope.get(owner, "isScoped"))) "cycle" else "set") });
    try flow.wait(continued, engine, owner, pending, 1);
}
fn emitSelect(scope: *Scope, owner: c.JSValue, model: c.JSValue, previous: c.JSValue, source: c.JSValue) !void {
    const session = try scope.get(owner, "agent");
    const runner = try scope.get(session, "_extensionRunner");
    const function = try scope.get(runner, "emit");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("model_select"));
    try scope.put(event, "model", model);
    try scope.put(event, "previousModel", previous);
    try scope.put(event, "source", source);
    const pending = try scope.call(function, runner, &.{event});
    try flow.wait(continued, scope.engine, owner, pending, 3);
}
fn continued(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    if (stage == 2) return flow.settle(engine, owner, false, value);
    if (stage == 3) return flow.settle(engine, owner, false, c.pi_js_undefined());
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    if (stage == 0) {
        const model = try scope.get(owner, "next");
        if (!scope.truthy(value)) {
            const constructor = try scope.global("Error");
            const message = try scope.concat(try scope.concat(try scope.concat(try scope.text("No API key for "), try scope.stringify(try scope.get(model, "provider"))), try scope.text("/")), try scope.stringify(try scope.get(model, "id")));
            var args = [_]c.JSValue{message};
            const reason = try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
            _ = try engine.checked(c.JS_Throw(engine.context, reason));
            return;
        }
        try scope.put(owner, "previous", try scope.get(session, "model"));
        return applySelection(engine, owner, false);
    }
    const is_scoped_value = try scope.get(owner, "isScoped");
    if (c.JS_IsUndefined(is_scoped_value)) return flow.settle(engine, owner, false, c.pi_js_undefined());
    const is_scoped = scope.truthy(is_scoped_value);
    const result = try scope.object();
    try scope.put(result, "model", try selectedModel(&scope, owner, is_scoped));
    try scope.put(result, "thinkingLevel", try scope.get(session, "thinkingLevel"));
    try scope.put(result, "isScoped", is_scoped_value);
    try flow.settle(engine, owner, false, result);
}
