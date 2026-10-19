//! Exact c268 Radius configuration helpers and genuine loadRadiusGatewayConfig AF.
//! One module owner supplies both Radius provider and OAuth imports.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const functions = @import("native_node_function.zig");
const h = @import("native_sdk_session_locals.zig");
const object_spread = @import("native_node_inspect_operations.zig");
const default_gateway = "https://radius.pi.dev";
const module_cache_key = "pi-native:radius-config-genuine";
const Stage = enum(i32) { response, text, json };
const ModelFrame = h.Frame(enum { model });
const SanitizeFrame = h.Frame(enum { baseUrl, models });
const NormalizeFrame = h.Frame(enum { withScheme });
const ModelsFrame = h.Frame(enum { config });
const TrimFrame = h.Frame(enum { trimmed });

fn expression(engine: *x.em.Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, @call(.auto, body, .{&o} ++ args));
}
fn statement(engine: *x.em.Engine, comptime body: anytype, args: anytype) !void {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishVoid(&scope, @call(.auto, body, .{&o} ++ args));
}
fn actionExpression(engine: *x.em.Engine, comptime body: anytype, args: anytype) !af.Action {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishAction(&scope, @call(.auto, body, .{&o} ++ args));
}
fn value(o: *x.Ops, comptime body: anytype, args: anytype) !c.JSValue {
    return o.own(try expression(o.s.engine, body, args));
}
fn truth(o: *x.Ops, comptime body: anytype, args: anytype) !bool {
    return o.truthy(try value(o, body, args));
}
fn duplicate(o: *x.Ops, input: c.JSValue) c.JSValue {
    return c.JS_DupValue(o.s.engine.context, input);
}
fn boolean(o: *x.Ops, input: bool) c.JSValue {
    return c.pi_js_bool(o.s.engine.context, @intFromBool(input));
}
fn integer(o: *x.Ops, input: i32) c.JSValue {
    return c.JS_NewInt32(o.s.engine.context, input);
}
fn array(o: *x.Ops) !c.JSValue {
    const generation = try o.beforeAllocation();
    return o.allocation(c.JS_NewArray(o.s.engine.context), generation);
}
fn property(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(o, try o.get(receiver, name));
}
fn propertyTruthy(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return boolean(o, o.truthy(try o.get(receiver, name)));
}
fn isObjectType(engine: *x.em.Engine, input: c.JSValue) bool {
    return c.JS_IsNull(input) or (c.JS_IsObject(input) and !c.JS_IsFunction(engine.context, input));
}
const Type = enum { string, boolean, number, object, not_null };
fn propertyType(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8, comptime kind: Type) !c.JSValue {
    const input = try o.get(receiver, name);
    return boolean(o, switch (kind) {
        .string => c.JS_IsString(input),
        .boolean => c.JS_IsBool(input),
        .number => c.JS_IsNumber(input),
        .object => isObjectType(o.s.engine, input),
        .not_null => !c.JS_IsNull(input),
    });
}
fn isArray(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const receiver = try o.global("Array");
    const callable = try o.get(receiver, "isArray");
    return boolean(o, o.truthy(try o.call(callable, receiver, &.{input})));
}
fn propertyIsArray(o: *x.Ops, input: c.JSValue, name: [*:0]const u8) !c.JSValue {
    // Resolve Array.isArray before evaluating its Source property argument.
    const receiver = try o.global("Array");
    const callable = try o.get(receiver, "isArray");
    return boolean(o, o.truthy(try o.call(callable, receiver, &.{try o.get(input, name)})));
}
fn modelBody(o: *x.Ops, frame: *ModelFrame, input: c.JSValue) !c.JSValue {
    if (!isObjectType(o.s.engine, input) or c.JS_IsNull(input) or try truth(o, isArray, .{input}))
        return boolean(o, false);
    try frame.set(.model, duplicate(o, input));
    const model = frame.get(.model);
    inline for (.{ .{ "id", Type.string }, .{ "name", Type.string }, .{ "reasoning", Type.boolean } }) |check| {
        if (!try truth(o, propertyType, .{model, @as([*:0]const u8, check[0]), check[1]}))
            return boolean(o, false);
    }
    if (!try truth(o, propertyIsArray, .{model, @as([*:0]const u8, "input")})) return boolean(o, false);
    if (!try truth(o, propertyType, .{model, @as([*:0]const u8, "cost"), Type.object})) return boolean(o, false);
    if (!try truth(o, propertyType, .{model, @as([*:0]const u8, "cost"), Type.not_null})) return boolean(o, false);
    if (try truth(o, propertyIsArray, .{model, @as([*:0]const u8, "cost")})) return boolean(o, false);
    if (!try truth(o, propertyType, .{model, @as([*:0]const u8, "contextWindow"), Type.number})) return boolean(o, false);
    return boolean(o, try truth(o, propertyType, .{model, @as([*:0]const u8, "maxTokens"), Type.number}));
}
fn modelCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var frame = ModelFrame.init(engine);
    return frame.finish(expression(engine, modelBody, .{&frame, x.arg(args, 0)}));
}
fn spreadBody(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const result = try o.object();
    try object_spread.copyInto(o.s, result, input);
    return duplicate(o, result);
}
fn copyModelCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, spreadBody, .{x.arg(args, 0)});
}
fn filteredModels(o: *x.Ops, module: c.JSValue, models: c.JSValue) !c.JSValue {
    const filter = try o.get(models, "filter");
    const predicate = try o.get(module, "isRadiusGatewayModel");
    return duplicate(o, try o.call(filter, models, &.{predicate}));
}
fn selectedModels(o: *x.Ops, module: c.JSValue, models: c.JSValue) !c.JSValue {
    const selected = try value(o, filteredModels, .{module, models});
    const map = try o.get(selected, "map");
    const copy = try o.own(try functions.createArrow(o.s.engine, "", 1, copyModelCall, &.{}));
    return duplicate(o, try o.call(map, selected, &.{copy}));
}
fn sanitizedRecord(o: *x.Ops, module: c.JSValue, frame: *SanitizeFrame) !c.JSValue {
    const result = try o.object();
    try o.put(result, "baseUrl", frame.get(.baseUrl));
    try o.put(result, "models", try value(o, selectedModels, .{module, frame.get(.models)}));
    return duplicate(o, result);
}
fn sanitizeBody(engine: *x.em.Engine, frame: *SanitizeFrame, module: c.JSValue, config: c.JSValue) !c.JSValue {
    if (!isObjectType(engine, config) or c.JS_IsNull(config) or h.truthy(engine, try expression(engine, isArray, .{config})))
        return c.pi_js_undefined();
    try frame.set(.baseUrl, expression(engine, property, .{config, @as([*:0]const u8, "baseUrl")}));
    try frame.set(.models, expression(engine, property, .{config, @as([*:0]const u8, "models")}));
    if (!c.JS_IsString(frame.get(.baseUrl)) or !h.truthy(engine, try expression(engine, isArray, .{frame.get(.models)})))
        return c.pi_js_undefined();
    return expression(engine, sanitizedRecord, .{module, frame});
}
fn sanitizeCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var frame = SanitizeFrame.init(engine);
    return frame.finish(sanitizeBody(engine, &frame, roots[0], x.arg(args, 0)));
}
fn regex(o: *x.Ops, pattern: []const u8, flags: []const u8) !c.JSValue {
    return x.guest.construct(o.s, o.s.engine.intrinsic_regexp_constructor, &.{try o.text(pattern), try o.text(flags)});
}
fn hasScheme(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const receiver = try regex(o, "^https?://", "iu");
    const callable = try o.get(receiver, "test");
    return boolean(o, o.truthy(try o.call(callable, receiver, &.{input})));
}
fn stringifyValue(o: *x.Ops, input: c.JSValue) !c.JSValue {
    return duplicate(o, try o.stringify(input));
}
fn propertyString(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(o, try o.stringify(try o.get(receiver, name)));
}
fn withScheme(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const prefix = try o.text("https://");
    return duplicate(o, try o.binary(0, prefix, try value(o, stringifyValue, .{input})));
}
fn removeTrailing(o: *x.Ops, input: c.JSValue) !c.JSValue {
    // The live replace lookup precedes literal RegExp allocation.
    const callable = try o.get(input, "replace");
    return duplicate(o, try o.call(callable, input, &.{try regex(o, "/+$", "u"), try o.text("")}));
}
fn normalizeCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var frame = NormalizeFrame.init(engine);
    return frame.finish(normalizeBody(engine, &frame, x.arg(args, 0)));
}
fn normalizeBody(engine: *x.em.Engine, frame: *NormalizeFrame, input: c.JSValue) !c.JSValue {
    try frame.set(.withScheme, if (h.truthy(engine, try expression(engine, hasScheme, .{input})))
        c.JS_DupValue(engine.context, input) else expression(engine, withScheme, .{input}));
    return expression(engine, removeTrailing, .{frame.get(.withScheme)});
}
fn credentialBody(o: *x.Ops, module: c.JSValue, credential: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "sanitizeRadiusGatewayConfig");
    const config = if (x.nullish(credential)) c.pi_js_undefined() else try o.get(credential, "gatewayConfig");
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{config}));
}
fn credentialCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, credentialBody, .{roots[0], x.arg(args, 0)});
}
fn mappedRecord(o: *x.Ops, model: c.JSValue, provider: c.JSValue, config: c.JSValue) !c.JSValue {
    const result = try o.object();
    try object_spread.copyInto(o.s, result, model);
    try o.put(result, "api", try o.text("pi-messages"));
    try o.put(result, "provider", provider);
    try o.put(result, "baseUrl", try value(o, property, .{config, @as([*:0]const u8, "baseUrl")}));
    return duplicate(o, result);
}
fn mapModelCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, mappedRecord, .{x.arg(args, 0), roots[0], roots[1]});
}
fn fromConfigBody(o: *x.Ops, provider: c.JSValue, config: c.JSValue) !c.JSValue {
    const receiver = try o.get(config, "models");
    const callable = try o.get(receiver, "map");
    const mapper = try o.own(try functions.createArrow(o.s.engine, "", 1, mapModelCall, &.{provider, config}));
    return duplicate(o, try o.call(callable, receiver, &.{mapper}));
}
fn fromConfigCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, fromConfigBody, .{x.arg(args, 0), x.arg(args, 1)});
}
fn invokePrivate(o: *x.Ops, module: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const callable = try o.get(module, name);
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), args));
}
fn emptyArray(o: *x.Ops) !c.JSValue {
    return duplicate(o, try array(o));
}
fn modelsBody(engine: *x.em.Engine, frame: *ModelsFrame, module: c.JSValue, args: []const c.JSValue) !c.JSValue {
    try frame.set(.config, expression(engine, invokePrivate, .{module, @as([*:0]const u8, "getRadiusCredentialConfig"), @as([]const c.JSValue, &.{x.arg(args, 1)})}));
    if (!h.truthy(engine, frame.get(.config))) return expression(engine, emptyArray, .{});
    return expression(engine, invokePrivate, .{module, @as([*:0]const u8, "getRadiusModelsFromConfig"), @as([]const c.JSValue, &.{x.arg(args, 0), frame.get(.config)})});
}
fn modelsCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var frame = ModelsFrame.init(engine);
    return frame.finish(modelsBody(engine, &frame, roots[0], args));
}
fn trim(o: *x.Ops, body: c.JSValue) !c.JSValue {
    return duplicate(o, try o.invoke(body, "trim", &.{}));
}
fn tooLong(o: *x.Ops, trimmed: c.JSValue) !c.JSValue {
    return boolean(o, o.truthy(try o.binary(6, try o.get(trimmed, "length"), integer(o, 512))));
}
fn sliceCall(o: *x.Ops, trimmed: c.JSValue) !c.JSValue {
    const callable = try o.get(trimmed, "slice");
    return duplicate(o, try o.call(callable, trimmed, &.{integer(o, 0), integer(o, 512)}));
}
fn sliceString(o: *x.Ops, trimmed: c.JSValue) !c.JSValue {
    return duplicate(o, try o.stringify(try value(o, sliceCall, .{trimmed})));
}
fn truncated(o: *x.Ops, trimmed: c.JSValue) !c.JSValue {
    const text = try value(o, sliceString, .{trimmed});
    return duplicate(o, try o.binary(0, text, try o.text("…")));
}
fn truncateBody(engine: *x.em.Engine, frame: *TrimFrame, body: c.JSValue) !c.JSValue {
    try frame.set(.trimmed, expression(engine, trim, .{body}));
    if (h.truthy(engine, try expression(engine, tooLong, .{frame.get(.trimmed)})))
        return expression(engine, truncated, .{frame.get(.trimmed)});
    return c.JS_DupValue(engine.context, frame.get(.trimmed));
}
fn truncateCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var frame = TrimFrame.init(engine);
    return frame.finish(truncateBody(engine, &frame, x.arg(args, 0)));
}
fn initialHeaders(o: *x.Ops) !c.JSValue {
    const result = try o.object();
    try o.put(result, "accept", try o.text("application/json"));
    return duplicate(o, result);
}
fn authorize(o: *x.Ops, headers: c.JSValue, api_key: c.JSValue) !void {
    const prefix = try o.text("Bearer ");
    const token = try value(o, stringifyValue, .{api_key});
    // Source assignment must honor inherited setters.
    try x.guest.set(o.s, headers, "authorization", try o.binary(0, prefix, token));
}
fn configUrl(o: *x.Ops, gateway: c.JSValue) !c.JSValue {
    const constructor = try o.global("URL");
    return duplicate(o, try x.guest.construct(o.s, constructor, &.{try o.text("/v1/config"), gateway}));
}
fn fetchConfig(o: *x.Ops, gateway: c.JSValue, headers: c.JSValue, signal: c.JSValue) !c.JSValue {
    const fetch = try o.global("fetch");
    const url = try value(o, configUrl, .{gateway});
    const init = try o.object();
    try o.put(init, "headers", headers);
    try o.put(init, "signal", signal);
    return duplicate(o, try o.call(fetch, c.pi_js_undefined(), &.{url, init}));
}
fn stage(o: *x.Ops, owner: c.JSValue, next: Stage) !void {
    return o.put(owner, "stage", integer(o, @intFromEnum(next)));
}
fn currentStage(o: *x.Ops, owner: c.JSValue) !Stage {
    const input = try o.get(owner, "stage");
    var number: i32 = 0;
    var boundary: x.guest.Boundary = .{ .engine = o.s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_ToInt32(o.s.engine.context, &number, input));
    return @enumFromInt(number);
}
fn invokeNoArgs(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(o, try o.invoke(receiver, name, &.{}));
}
fn failurePrefix(o: *x.Ops, gateway: c.JSValue, response: c.JSValue) !c.JSValue {
    const initial = try o.text("Could not load Radius config from ");
    const gateway_text = try value(o, stringifyValue, .{gateway});
    const first = try o.binary(0, initial, gateway_text);
    const status_prefix = try o.binary(0, first, try o.text(": "));
    const status_text = try value(o, propertyString, .{response, @as([*:0]const u8, "status")});
    const second = try o.binary(0, status_prefix, status_text);
    return duplicate(o, try o.binary(0, second, try o.text(": ")));
}
fn truncatedBodyString(o: *x.Ops, callable: c.JSValue, body: c.JSValue) !c.JSValue {
    const result = try o.call(callable, c.pi_js_undefined(), &.{body});
    return duplicate(o, try o.stringify(result));
}
fn finishFailure(o: *x.Ops, owner: c.JSValue, body: c.JSValue) !c.JSValue {
    const constructor = try o.get(owner, "errorConstructor");
    const prefix = try o.get(owner, "errorPrefix");
    const callable = try o.get(owner, "argumentCallable");
    const text = try value(o, truncatedBodyString, .{callable, body});
    const message = try o.binary(0, prefix, text);
    return duplicate(o, try x.guest.construct(o.s, constructor, &.{message}));
}
fn invalidConfig(o: *x.Ops, gateway: c.JSValue) !c.JSValue {
    const constructor = try o.global("Error");
    const prefix = try o.text("Invalid Radius config from ");
    const text = try value(o, stringifyValue, .{gateway});
    const message = try o.binary(0, prefix, text);
    return duplicate(o, try x.guest.construct(o.s, constructor, &.{message}));
}
fn raise(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    return o.s.engine.checked(c.JS_Throw(o.s.engine.context, reason));
}
fn clearOperands(o: *x.Ops, owner: c.JSValue) !void {
    inline for (.{ "argumentCallable", "errorPrefix", "errorConstructor" }) |name|
        try o.put(owner, name, c.pi_js_undefined());
}
fn loadBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return actionExpression(engine, loadAdvance, .{roots[0], args, state, completion, input});
}
fn loadAdvance(o: *x.Ops, module: c.JSValue, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try o.cell();
        af.replaceState(o.s.engine, state, duplicate(o, owner));
        inline for (.{ "headers", "response", "config", "errorConstructor", "errorPrefix", "argumentCallable" }) |name|
            try o.put(owner, name, c.pi_js_undefined());
        try o.put(owner, "headers", try value(o, initialHeaders, .{}));
        const headers = try o.get(owner, "headers");
        if (o.truthy(x.arg(args, 1))) try statement(o.s.engine, authorize, .{headers, x.arg(args, 1)});
        try stage(o, owner, .response);
        return .{ .awaited = try expression(o.s.engine, fetchConfig, .{x.arg(args, 0), headers, x.arg(args, 2)}) };
    }
    if (completion == .rejected) return .{ .thrown = duplicate(o, input) };
    switch (try currentStage(o, state.*)) {
        .response => {
            try o.put(state.*, "response", input);
            if (!try truth(o, propertyTruthy, .{input, @as([*:0]const u8, "ok")})) {
                try o.put(state.*, "errorConstructor", try o.global("Error"));
                try o.put(state.*, "errorPrefix", try value(o, failurePrefix, .{x.arg(args, 0), input}));
                try o.put(state.*, "argumentCallable", try o.get(module, "truncateHttpBody"));
                try stage(o, state.*, .text);
                return .{ .awaited = try expression(o.s.engine, invokeNoArgs, .{input, @as([*:0]const u8, "text")}) };
            }
            try o.put(state.*, "argumentCallable", try o.get(module, "sanitizeRadiusGatewayConfig"));
            try stage(o, state.*, .json);
            return .{ .awaited = try expression(o.s.engine, invokeNoArgs, .{input, @as([*:0]const u8, "json")}) };
        },
        .text => {
            const reason = try value(o, finishFailure, .{state.*, input});
            try clearOperands(o, state.*);
            return .{ .thrown = try raise(o, duplicate(o, reason)) };
        },
        .json => {
            const callable = try o.get(state.*, "argumentCallable");
            try o.put(state.*, "config", try o.call(callable, c.pi_js_undefined(), &.{input}));
            try clearOperands(o, state.*);
            const config = try o.get(state.*, "config");
            if (!o.truthy(config)) return .{ .thrown = try raise(o, try expression(o.s.engine, invalidConfig, .{x.arg(args, 0)})) };
            return .{ .returned = duplicate(o, config) };
        },
    }
}
const public_names = .{
    "DEFAULT_RADIUS_GATEWAY", "normalizeRadiusGatewayUrl", "getRadiusCredentialConfig",
    "getRadiusModelsFromConfig", "getRadiusModels", "loadRadiusGatewayConfig",
};
fn createModule(o: *x.Ops) !c.JSValue {
    const module = try o.cell();
    try o.put(module, "DEFAULT_RADIUS_GATEWAY", try o.text(default_gateway));
    try o.put(module, "isRadiusGatewayModel", try o.own(try functions.create(o.s.engine, "isRadiusGatewayModel", 1, modelCall, &.{})));
    try o.put(module, "sanitizeRadiusGatewayConfig", try o.own(try functions.create(o.s.engine, "sanitizeRadiusGatewayConfig", 1, sanitizeCall, &.{module})));
    try o.put(module, "normalizeRadiusGatewayUrl", try o.own(try functions.create(o.s.engine, "normalizeRadiusGatewayUrl", 1, normalizeCall, &.{})));
    try o.put(module, "getRadiusCredentialConfig", try o.own(try functions.create(o.s.engine, "getRadiusCredentialConfig", 1, credentialCall, &.{module})));
    try o.put(module, "getRadiusModelsFromConfig", try o.own(try functions.create(o.s.engine, "getRadiusModelsFromConfig", 2, fromConfigCall, &.{})));
    try o.put(module, "getRadiusModels", try o.own(try functions.create(o.s.engine, "getRadiusModels", 2, modelsCall, &.{module})));
    try o.put(module, "truncateHttpBody", try o.own(try functions.create(o.s.engine, "truncateHttpBody", 1, truncateCall, &.{})));
    try o.put(module, "loadRadiusGatewayConfig", try o.own(try af.createResumable(o.s.engine, "loadRadiusGatewayConfig", 3, loadBody, &.{module})));
    const namespace = try o.object();
    inline for (public_names) |name| try o.put(namespace, name, try o.get(module, name));
    try o.put(module, "namespace", namespace);
    return duplicate(o, module);
}
fn moduleValue(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(module_cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    const candidate = try expression(engine, createModule, .{});
    if (engine.native_module_values.get(module_cache_key)) |cached| {
        var selected = x.owned.Completion.initValue(engine, c.JS_DupValue(engine.context, cached));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = x.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(module_cache_key, candidate);
    return c.JS_DupValue(engine.context, candidate);
}
fn publicValue(o: *x.Ops) !c.JSValue {
    const module = try o.own(try moduleValue(o.s.engine));
    return duplicate(o, try o.get(module, "namespace"));
}
pub fn create(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    return x.finishInvocation(engine, &invocation, expression(engine, publicValue, .{}));
}
pub fn createTestInternals(engine: *x.em.Engine) !c.JSValue {
    if (!@import("builtin").is_test) @compileError("Radius private projection is only for native controls");
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    return x.finishInvocation(engine, &invocation, expression(engine, testProjection, .{}));
}
fn testProjection(o: *x.Ops) !c.JSValue {
    const module = try o.own(try moduleValue(o.s.engine));
    const result = try o.object();
    inline for (public_names ++ .{ "isRadiusGatewayModel", "sanitizeRadiusGatewayConfig", "truncateHttpBody" }) |name|
        try o.put(result, name, try o.get(module, name));
    return duplicate(o, result);
}
