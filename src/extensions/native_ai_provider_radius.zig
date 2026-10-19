//! Exact c268 radiusProvider declaration and genuine refreshModels AsyncFunction.
//! Imported configuration values come from the one actual Radius config module.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const sync = @import("native_sync_arguments.zig");
const functions = @import("native_node_function.zig");
const frames = @import("native_public_lexical_frame.zig");
const spread = @import("native_node_inspect_operations.zig");
const ProviderFrame = frames.Frame(enum { options, id, name, gateway, baselineModels, dynamicModels, streams });
const RefreshFrame = frames.Frame(enum { stored, restored, legacy, apiKey, config, refreshed, phase });
const Phase = enum(i32) { restored, legacy, config, published };
// Exact imports, in the retained Source fixture's injection order.
const Import = enum(usize) {
    piMessagesApi, envApiKeyAuth, lazyOAuth, loadRadiusOAuth, RADIUS_MODELS,
    DEFAULT_RADIUS_GATEWAY, getRadiusModels, getRadiusModelsFromConfig,
    loadRadiusGatewayConfig, normalizeRadiusGatewayUrl,
};
const import_names = .{
    "piMessagesApi", "envApiKeyAuth", "lazyOAuth", "loadRadiusOAuth", "RADIUS_MODELS",
    "DEFAULT_RADIUS_GATEWAY", "getRadiusModels", "getRadiusModelsFromConfig",
    "loadRadiusGatewayConfig", "normalizeRadiusGatewayUrl",
};
fn imported(roots: []const c.JSValue, comptime name: Import) c.JSValue {
    return roots[@intFromEnum(name)];
}
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
fn duplicate(o: *x.Ops, input: c.JSValue) c.JSValue { return c.JS_DupValue(o.s.engine.context, input); }
fn boolean(o: *x.Ops, input: bool) c.JSValue { return c.pi_js_bool(o.s.engine.context, @intFromBool(input)); }
fn predicate(engine: *x.em.Engine, comptime body: anytype, args: anytype) !bool {
    const result = try expression(engine, body, args);
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
fn array(o: *x.Ops) !c.JSValue {
    const generation = try o.beforeAllocation();
    return o.allocation(c.JS_NewArray(o.s.engine.context), generation);
}
fn emptyObject(o: *x.Ops) !c.JSValue { return duplicate(o, try o.object()); }
fn property(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(o, try o.get(receiver, name));
}
fn propertyTruthy(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return boolean(o, o.truthy(try o.get(receiver, name)));
}
fn option(o: *x.Ops, options: c.JSValue, name: [*:0]const u8, fallback: []const u8) !c.JSValue {
    const selected = try o.get(options, name);
    return duplicate(o, if (x.nullish(selected)) try o.text(fallback) else selected);
}
fn gateway(o: *x.Ops, options: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const callable = imported(roots, .normalizeRadiusGatewayUrl);
    const selected = try o.get(options, "gateway");
    return duplicate(o, try o.call(callable, c.pi_js_undefined(),
        &.{if (x.nullish(selected)) imported(roots, .DEFAULT_RADIUS_GATEWAY) else selected}));
}
fn defaultGateway(o: *x.Ops, current: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const normalized = try o.call(imported(roots, .normalizeRadiusGatewayUrl), c.pi_js_undefined(),
        &.{imported(roots, .DEFAULT_RADIUS_GATEWAY)});
    return boolean(o, c.JS_IsStrictEqual(o.s.engine.context, current, normalized));
}
fn catalogValues(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const receiver = try o.global("Object");
    const callable = try o.get(receiver, "values");
    return duplicate(o, try o.call(callable, receiver, &.{input}));
}
fn baselineModel(o: *x.Ops, input: c.JSValue, id: c.JSValue) !c.JSValue {
    const result = try o.object();
    try spread.copyInto(o.s, result, input);
    try o.put(result, "provider", try ProviderFrame.read(o.s, id));
    return duplicate(o, result);
}
fn baselineModelCall(engine: *x.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, baselineModel, .{args.get(0), roots[0]});
}
fn baseline(o: *x.Ops, frame: *ProviderFrame, roots: []const c.JSValue) !c.JSValue {
    if (!try predicate(o.s.engine, defaultGateway, .{frame.get(.gateway), roots}))
        return duplicate(o, try array(o));
    // Object.values is a completed call before the following .map lookup.
    const receiver = try value(o, catalogValues, .{imported(roots, .RADIUS_MODELS)});
    const callable = try o.get(receiver, "map");
    const id = try frame.capture(o.s, .id, "id");
    const callback = try o.own(try functions.createArrowWithArguments(o.s.engine, "", 1,
        .{ .formal_count = 1, .callback = baselineModelCall }, &.{id}));
    return duplicate(o, try o.call(callable, receiver, &.{callback}));
}
fn streams(o: *x.Ops, callable: c.JSValue) !c.JSValue {
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{}));
}
fn apiKeyAuth(o: *x.Ops, callable: c.JSValue) !c.JSValue {
    const label = try o.text("Radius API key");
    const names = try array(o);
    try x.guest.index(o.s, names, 0, try o.text("RADIUS_API_KEY"));
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{label, names}));
}
fn loadOAuth(o: *x.Ops, roots: []const c.JSValue) !c.JSValue {
    const input = try o.object();
    try o.put(input, "name", try ProviderFrame.read(o.s, roots[0]));
    try o.put(input, "gateway", try ProviderFrame.read(o.s, roots[1]));
    return duplicate(o, try o.call(roots[2], c.pi_js_undefined(), &.{input}));
}
fn loadOAuthCall(engine: *x.em.Engine, _: c.JSValue, _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, loadOAuth, .{roots});
}
fn lazyAuth(o: *x.Ops, frame: *ProviderFrame, roots: []const c.JSValue) !c.JSValue {
    const input = try o.object();
    try o.put(input, "name", frame.get(.name));
    const name = try frame.capture(o.s, .name, "name");
    const gateway_binding = try frame.capture(o.s, .gateway, "gateway");
    const load = try o.own(try functions.createArrowWithArguments(o.s.engine, "load", 0,
        .{ .formal_count = 0, .callback = loadOAuthCall }, &.{name, gateway_binding, imported(roots, .loadRadiusOAuth)}));
    try o.put(input, "load", load);
    return duplicate(o, try o.call(imported(roots, .lazyOAuth), c.pi_js_undefined(), &.{input}));
}
fn getModels(o: *x.Ops, roots: []const c.JSValue) !c.JSValue {
    const dynamic = try ProviderFrame.read(o.s, roots[0]);
    return duplicate(o, if (x.nullish(dynamic)) try ProviderFrame.read(o.s, roots[1]) else dynamic);
}
fn getModelsCall(engine: *x.em.Engine, _: c.JSValue, _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, getModels, .{roots});
}
fn stream(o: *x.Ops, args: *sync.Arguments, streams_binding: c.JSValue, comptime method: [*:0]const u8) !c.JSValue {
    const receiver = try ProviderFrame.read(o.s, streams_binding);
    const callable = try o.get(receiver, method);
    return duplicate(o, try o.call(callable, receiver, &.{args.get(0), args.get(1), args.get(2)}));
}
fn StreamCall(comptime method: [*:0]const u8) type {
    return struct {
        fn call(engine: *x.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
            return expression(engine, stream, .{args, roots[0], method});
        }
    };
}
fn providerObject(o: *x.Ops, frame: *ProviderFrame, roots: []const c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "id", frame.get(.id));
    try o.put(result, "name", frame.get(.name));
    const auth = try o.object();
    try o.put(auth, "apiKey", try value(o, apiKeyAuth, .{imported(roots, .envApiKeyAuth)}));
    try o.put(auth, "oauth", try value(o, lazyAuth, .{frame, roots}));
    try o.put(result, "auth", auth);
    const dynamic = try frame.capture(o.s, .dynamicModels, "dynamicModels");
    const baseline_binding = try frame.capture(o.s, .baselineModels, "baselineModels");
    const get = try o.own(try functions.createArrowWithArguments(o.s.engine, "getModels", 0,
        .{ .formal_count = 0, .callback = getModelsCall }, &.{dynamic, baseline_binding}));
    try o.put(result, "getModels", get);
    const id = try frame.capture(o.s, .id, "id");
    const gateway_binding = try frame.capture(o.s, .gateway, "gateway");
    const refresh = try o.own(try af.createResumableArrowWithClose(o.s.engine, "refreshModels", 1,
        refreshBody, &.{id, gateway_binding, dynamic, imported(roots, .getRadiusModels),
            imported(roots, .getRadiusModelsFromConfig), imported(roots, .loadRadiusGatewayConfig)},
        c.pi_js_undefined(), RefreshFrame.closeAtAsyncTerminal));
    try o.put(result, "refreshModels", refresh);
    const streams_binding = try frame.capture(o.s, .streams, "streams");
    inline for (.{ "stream", "streamSimple" }) |method| {
        const callable = try o.own(try functions.createArrowWithArguments(o.s.engine, method, 3,
            .{ .formal_count = 3, .callback = StreamCall(method).call }, &.{streams_binding}));
        try o.put(result, method, callable);
    }
    return duplicate(o, result);
}
fn providerBody(o: *x.Ops, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    const frame = try args.createFrame(o.s, ProviderFrame);
    // The actual default-parameter prologue retains its independent LET slot
    // in addition to the VM's original formal/caller argument owner.
    if (c.JS_IsUndefined(args.get(0))) try args.take(0, expression(o.s.engine, emptyObject, .{}));
    try frame.copy(.options, args.get(0));
    try frame.take(.id, expression(o.s.engine, option, .{frame.get(.options), @as([*:0]const u8, "id"), @as([]const u8, "radius")}));
    try frame.take(.name, expression(o.s.engine, option, .{frame.get(.options), @as([*:0]const u8, "name"), @as([]const u8, "Radius")}));
    try frame.take(.gateway, expression(o.s.engine, gateway, .{frame.get(.options), roots}));
    try frame.take(.baselineModels, expression(o.s.engine, baseline, .{frame, roots}));
    try frame.take(.dynamicModels, c.pi_js_undefined());
    try frame.take(.streams, expression(o.s.engine, streams, .{imported(roots, .piMessagesApi)}));
    return expression(o.s.engine, providerObject, .{frame, roots});
}
fn providerCall(engine: *x.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, providerBody, .{args, roots});
}
fn matchingModel(o: *x.Ops, input: c.JSValue, id: c.JSValue) !c.JSValue {
    const provider = try o.get(input, "provider");
    const expected = try ProviderFrame.read(o.s, id);
    return boolean(o, c.JS_IsStrictEqual(o.s.engine.context, provider, expected));
}
fn matchingModelCall(engine: *x.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, matchingModel, .{args.get(0), roots[0]});
}
fn restoredModels(o: *x.Ops, stored: c.JSValue, id: c.JSValue) !c.JSValue {
    // Source is exactly stored.models.filter(callback); there is no extra map.
    const receiver = try value(o, property, .{stored, @as([*:0]const u8, "models")});
    const callable = try o.get(receiver, "filter");
    const callback = try o.own(try functions.createArrowWithArguments(o.s.engine, "", 1,
        .{ .formal_count = 1, .callback = matchingModelCall }, &.{id}));
    return duplicate(o, try o.call(callable, receiver, &.{callback}));
}
fn updateModels(o: *x.Ops, roots: []const c.JSValue) !void {
    const current = try RefreshFrame.read(o.s, roots[1]);
    try ProviderFrame.assign(roots[0], duplicate(o, current));
}
fn updateCall(engine: *x.em.Engine, _: c.JSValue, _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, updateModels, .{roots});
    return c.pi_js_undefined();
}
fn dateNow(o: *x.Ops) !c.JSValue {
    const receiver = try o.global("Date");
    const callable = try o.get(receiver, "now");
    return duplicate(o, try o.call(callable, receiver, &.{}));
}
fn publish(o: *x.Ops, context: c.JSValue, frame: *RefreshFrame, dynamic: c.JSValue, comptime binding: @TypeOf(.enum_literal)) !c.JSValue {
    const callable = try o.get(context, "publish");
    const input = try o.object();
    if (comptime binding != .restored) {
        const persist = try o.object();
        try o.put(persist, "models", frame.get(binding));
        // The Date.now receiver/callee retire before the update arrow exists.
        try o.put(persist, "checkedAt", try value(o, dateNow, .{}));
        try o.put(input, "persist", persist);
    }
    const name: [*:0]const u8 = comptime @tagName(binding);
    const captured = try frame.capture(o.s, binding, name);
    const update = try o.own(try functions.createArrowWithArguments(o.s.engine, "update", 0,
        .{ .formal_count = 0, .callback = updateCall }, &.{dynamic, captured}));
    try o.put(input, "update", update);
    return duplicate(o, try o.call(callable, context, &.{input}));
}
fn credentialIsOAuth(o: *x.Ops, context: c.JSValue) !c.JSValue {
    const credential = try value(o, property, .{context, @as([*:0]const u8, "credential")});
    if (x.nullish(credential)) return boolean(o, false);
    return boolean(o, c.JS_IsStrictEqual(o.s.engine.context, try o.get(credential, "type"), try o.text("oauth")));
}
fn legacyModels(o: *x.Ops, context: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const id = try ProviderFrame.read(o.s, roots[0]);
    const credential = try o.get(context, "credential");
    return duplicate(o, try o.call(roots[3], c.pi_js_undefined(), &.{id, credential}));
}
fn nonempty(o: *x.Ops, models: c.JSValue) !c.JSValue {
    return boolean(o, o.truthy(try o.binary(6, try o.get(models, "length"), c.JS_NewInt32(o.s.engine.context, 0))));
}
fn aborted(o: *x.Ops, context: c.JSValue) !c.JSValue {
    const signal = try value(o, property, .{context, @as([*:0]const u8, "signal")});
    return boolean(o, o.truthy(try o.get(signal, "aborted")));
}
fn apiKey(o: *x.Ops, context: c.JSValue) !c.JSValue {
    const oauth = try predicate(o.s.engine, credentialIsOAuth, .{context});
    const credential = try value(o, property, .{context, @as([*:0]const u8, "credential")});
    if (!oauth and x.nullish(credential)) return c.pi_js_undefined();
    return duplicate(o, try o.get(credential, if (oauth) "access" else "key"));
}
fn loadConfig(o: *x.Ops, context: c.JSValue, frame: *RefreshFrame, roots: []const c.JSValue) !c.JSValue {
    const gateway_value = try ProviderFrame.read(o.s, roots[1]);
    const signal = try o.get(context, "signal");
    return duplicate(o, try o.call(roots[5], c.pi_js_undefined(), &.{gateway_value, frame.get(.apiKey), signal}));
}
fn refreshedModels(o: *x.Ops, config: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const id = try ProviderFrame.read(o.s, roots[0]);
    return duplicate(o, try o.call(roots[4], c.pi_js_undefined(), &.{id, config}));
}
fn setPhase(frame: *RefreshFrame, phase: Phase) !void {
    return frame.take(.phase, c.JS_NewInt32(frame.engine.context, @intFromEnum(phase)));
}
fn getPhase(o: *x.Ops, frame: *RefreshFrame) !Phase {
    var raw: c_int = 0;
    var boundary: x.guest.Boundary = .{ .engine = o.s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_ToInt32(o.s.engine.context, &raw, frame.get(.phase)));
    return @enumFromInt(raw);
}
fn closeBlock(frame: *RefreshFrame, comptime binding: @TypeOf(.enum_literal)) !void {
    var completion = x.owned.Completion.initVoid(frame.engine, {});
    frame.detach(binding, &completion);
    return completion.finishVoid();
}
fn afterLegacy(o: *x.Ops, context: c.JSValue, frame: *RefreshFrame, roots: []const c.JSValue) !af.Action {
    if (!try predicate(o.s.engine, propertyTruthy, .{context, @as([*:0]const u8, "allowNetwork")}) or
        try predicate(o.s.engine, aborted, .{context})) return .{ .returned = c.pi_js_undefined() };
    try frame.take(.apiKey, expression(o.s.engine, apiKey, .{context}));
    try setPhase(frame, .config);
    return .{ .awaited = try expression(o.s.engine, loadConfig, .{context, frame, roots}) };
}
fn afterStored(o: *x.Ops, context: c.JSValue, frame: *RefreshFrame, roots: []const c.JSValue) !af.Action {
    if (!o.truthy(frame.get(.stored)) and try predicate(o.s.engine, credentialIsOAuth, .{context})) {
        try frame.take(.legacy, expression(o.s.engine, legacyModels, .{context, roots}));
        if (try predicate(o.s.engine, nonempty, .{frame.get(.legacy)})) {
            try setPhase(frame, .legacy);
            return .{ .awaited = try expression(o.s.engine, publish, .{context, frame, roots[2], .legacy}) };
        }
        try closeBlock(frame, .legacy);
    }
    return afterLegacy(o, context, frame, roots);
}
fn refreshAdvance(o: *x.Ops, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const context = x.arg(args, 0);
    if (completion == .start) {
        const frame = try RefreshFrame.createAsync(o.s);
        af.replaceState(o.s.engine, state, duplicate(o, frame.owner));
        try frame.take(.stored, expression(o.s.engine, property, .{context, @as([*:0]const u8, "stored")}));
        if (o.truthy(frame.get(.stored))) {
            try frame.take(.restored, expression(o.s.engine, restoredModels, .{frame.get(.stored), roots[0]}));
            try setPhase(frame, .restored);
            return .{ .awaited = try expression(o.s.engine, publish, .{context, frame, roots[2], .restored}) };
        }
        return afterStored(o, context, frame, roots);
    }
    if (completion == .rejected) return .{ .thrown = duplicate(o, input) };
    const frame = RefreshFrame.from(state.*);
    switch (try getPhase(o, frame)) {
        .restored => {
            // Source's bare return leaves cells for the async terminal owner.
            // Only normal block fallthrough executes its OP_close_loc.
            if (!o.truthy(input)) return .{ .returned = c.pi_js_undefined() };
            try closeBlock(frame, .restored);
            return afterStored(o, context, frame, roots);
        },
        .legacy => {
            if (!o.truthy(input)) return .{ .returned = c.pi_js_undefined() };
            try closeBlock(frame, .legacy);
            return afterLegacy(o, context, frame, roots);
        },
        .config => {
            try frame.copy(.config, input);
            if (try predicate(o.s.engine, aborted, .{context})) return .{ .returned = c.pi_js_undefined() };
            try frame.take(.refreshed, expression(o.s.engine, refreshedModels, .{frame.get(.config), roots}));
            try setPhase(frame, .published);
            return .{ .awaited = try expression(o.s.engine, publish, .{context, frame, roots[2], .refreshed}) };
        },
        .published => return .{ .returned = c.pi_js_undefined() },
    }
}
fn refreshBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return actionExpression(engine, refreshAdvance, .{args, roots, state, completion, input});
}
fn factoryWithImports(o: *x.Ops, values: []const c.JSValue) !c.JSValue {
    return duplicate(o, try o.own(try functions.createWithArguments(o.s.engine, "radiusProvider", 0,
        .{ .formal_count = 1, .callback = providerCall, .hooks = sync.frameHooks(ProviderFrame) }, values)));
}
fn actualFactory(o: *x.Ops, dependencies: c.JSValue) !c.JSValue {
    const config = try o.own(try @import("native_ai_radius_config.zig").create(o.s.engine));
    const helpers = try o.own(try @import("native_ai_auth_helpers.zig").create(o.s.engine));
    const apis = try o.get(dependencies, "apis");
    const oauth = try o.get(dependencies, "oauth");
    const catalog = try o.own(try @import("native_ai_catalog_values.zig").providerChatCatalog(o.s.engine, try o.text("radius")));
    const values = [_]c.JSValue{
        try o.get(apis, "piMessagesApi"), try o.get(helpers, "envApiKeyAuth"),
        try o.get(helpers, "lazyOAuth"), try o.get(oauth, "loadRadiusOAuth"), catalog,
        try o.get(config, "DEFAULT_RADIUS_GATEWAY"), try o.get(config, "getRadiusModels"),
        try o.get(config, "getRadiusModelsFromConfig"), try o.get(config, "loadRadiusGatewayConfig"),
        try o.get(config, "normalizeRadiusGatewayUrl"),
    };
    return factoryWithImports(o, &values);
}
pub fn factory(engine: *x.em.Engine, dependencies: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    return x.finishInvocation(engine, &invocation, expression(engine, actualFactory, .{dependencies}));
}
fn testFactory(o: *x.Ops, imports: c.JSValue) !c.JSValue {
    var values: [import_names.len]c.JSValue = undefined;
    inline for (import_names, 0..) |name, index| values[index] = try o.get(imports, name);
    return factoryWithImports(o, &values);
}
pub fn createTestFactory(engine: *x.em.Engine, imports: c.JSValue) !c.JSValue {
    if (!@import("builtin").is_test) @compileError("Radius import injection is only for native controls");
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    return x.finishInvocation(engine, &invocation, expression(engine, testFactory, .{imports}));
}
