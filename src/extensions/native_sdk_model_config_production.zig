//! Actual immutable latest4954 ModelConfig and its actual TypeBox schema.
//! Schema construction consumes one shared production Type/Compiler/provider
//! schema graph; validation never uses the legacy hand-written JSON checker.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const flow = @import("native_sdk_async_actions.zig");
const functions = @import("native_node_function.zig");
const class = @import("native_class.zig");
const c = em.c;
pub const required_functions = .{ "readFile", "normalizePath", "stripBom", "stripJsonComments" };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn imported(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(bindings, name), c.pi_js_undefined(), args);
}
fn typeCall(scope: *Scope, types: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.invoke(types, name, args);
}
fn option(scope: *Scope, types: c.JSValue, value: c.JSValue) !c.JSValue {
    return typeCall(scope, types, "Optional", &.{value});
}
fn record(scope: *Scope, types: c.JSValue, value: c.JSValue) !c.JSValue {
    return typeCall(scope, types, "Record", &.{ try typeCall(scope, types, "String", &.{}), value });
}
fn positive(scope: *Scope, types: c.JSValue, name: [*:0]const u8, key: [*:0]const u8, count: i32) !c.JSValue {
    const options = try scope.object();
    try scope.put(options, key, c.JS_NewInt32(scope.engine.context, count));
    return typeCall(scope, types, name, &.{options});
}
/// Replays the Source schema declarations in their original field order.
pub fn schema(engine: *em.Engine, graph: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const types = try scope.get(graph, "Type");
    const schemas = try scope.get(graph, "Schemas");
    const model = try scope.get(schemas, "model");
    const compat = try scope.get(schemas, "compat");
    const sampling = try record(&scope, types, try typeCall(&scope, types, "Unknown", &.{}));
    const sampling_levels = try scope.object();
    inline for (.{ "off", "minimal", "low", "medium", "high", "xhigh", "max" }) |name| try scope.put(sampling_levels, name, try option(&scope, types, sampling));
    const by_level = try typeCall(&scope, types, "Object", &.{sampling_levels});
    const token_count = try positive(&scope, types, "Number", "exclusiveMinimum", 0);
    var definitions: [2]c.JSValue = undefined;
    inline for (0..2) |index| {
        const properties = try scope.object();
        if (index == 0) try scope.put(properties, "id", try positive(&scope, types, "String", "minLength", 1));
        try scope.put(properties, "name", try option(&scope, types, try positive(&scope, types, "String", "minLength", 1)));
        if (index == 0) {
            try scope.put(properties, "api", try option(&scope, types, try positive(&scope, types, "String", "minLength", 1)));
            try scope.put(properties, "baseUrl", try option(&scope, types, try positive(&scope, types, "String", "minLength", 1)));
        }
        try scope.put(properties, "reasoning", try option(&scope, types, try typeCall(&scope, types, "Boolean", &.{})));
        try scope.put(properties, "thinkingLevelMap", try option(&scope, types, try scope.get(model, "ThinkingLevelMapSchema")));
        try scope.put(properties, "input", try option(&scope, types, try typeCall(&scope, types, "Array", &.{try scope.get(model, "ModelInputModalitySchema")})));
        try scope.put(properties, "inputLimits", try option(&scope, types, try scope.get(model, "ModelInputLimitsSchema")));
        const cost = try scope.get(model, "ModelCostSchema");
        try scope.put(properties, "cost", try option(&scope, types, if (index == 0) cost else try typeCall(&scope, types, "Partial", &.{cost})));
        try scope.put(properties, "promptCache", try option(&scope, types, try scope.get(model, "ModelPromptCacheSchema")));
        try scope.put(properties, "contextWindow", try option(&scope, types, token_count));
        try scope.put(properties, "maxTokens", try option(&scope, types, token_count));
        try scope.put(properties, "samplingParams", try option(&scope, types, sampling));
        try scope.put(properties, "samplingParamsByThinkingLevel", try option(&scope, types, by_level));
        try scope.put(properties, "headers", try option(&scope, types, try record(&scope, types, try typeCall(&scope, types, "String", &.{}))));
        try scope.put(properties, "compat", try option(&scope, types, try scope.get(compat, "ProviderCompatSchema")));
        definitions[index] = try typeCall(&scope, types, "Object", &.{properties});
    }
    const provider_properties = try scope.object();
    inline for (.{ "name", "baseUrl", "apiKey", "api" }) |name| try scope.put(provider_properties, name, try option(&scope, types, try positive(&scope, types, "String", "minLength", 1)));
    try scope.put(provider_properties, "oauth", try option(&scope, types, try typeCall(&scope, types, "Literal", &.{try scope.text("radius")})));
    try scope.put(provider_properties, "headers", try option(&scope, types, try record(&scope, types, try typeCall(&scope, types, "String", &.{}))));
    try scope.put(provider_properties, "compat", try option(&scope, types, try scope.get(compat, "ProviderCompatSchema")));
    try scope.put(provider_properties, "authHeader", try option(&scope, types, try typeCall(&scope, types, "Boolean", &.{})));
    try scope.put(provider_properties, "models", try option(&scope, types, try typeCall(&scope, types, "Array", &.{definitions[0]})));
    try scope.put(provider_properties, "modelOverrides", try option(&scope, types, try record(&scope, types, definitions[1])));
    const providers = try record(&scope, types, try typeCall(&scope, types, "Object", &.{provider_properties}));
    const properties = try scope.object();
    try scope.put(properties, "$schema", try option(&scope, types, try typeCall(&scope, types, "String", &.{})));
    try scope.put(properties, "providers", providers);
    return c.JS_DupValue(engine.context, try typeCall(&scope, types, "Object", &.{properties}));
}
pub fn create(engine: *em.Engine, actual_imports: c.JSValue, graph: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.object();
    inline for (required_functions) |name| {
        const value = try scope.get(actual_imports, name);
        if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualModelConfigImport;
        try scope.put(bindings, name, value);
    }
    const models_schema = try scope.own(try schema(engine, graph));
    const validator = try scope.invoke(try scope.get(graph, "Compiler"), "Compile", &.{models_schema});
    inline for (.{ "Check", "Errors" }) |name| if (!c.JS_IsFunction(engine.context, try scope.get(validator, name))) return error.RequiredActualModelConfigValidator;
    try scope.put(bindings, "validateModelsConfig", validator);
    const prototype = try scope.object();
    const ctor = try scope.own(try class.constructor(engine, "ModelConfig", 2, prototype, construct, &.{}));
    try scope.put(bindings, "ModelConfig", ctor);
    inline for (.{ "getProvider", "getProviderIds", "getError" }, 0..) |name, index| {
        const function = try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, getter, name, if (index == 0) 1 else 0, index)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const load = try scope.own(try flow.native.createResumable(engine, "load", 1, loadBody, &.{bindings}));
    if (c.JS_DefinePropertyValueStr(engine.context, ctor, "load", c.JS_DupValue(engine.context, load), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const result = try scope.object();
    try scope.put(result, "ModelConfig", ctor);
    try scope.put(result, "ModelsConfigSchema", models_schema);
    return c.JS_DupValue(engine.context, result);
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const self = try scope.own(try class.object(engine, target));
    try scope.put(self, "providers", c.pi_js_undefined());
    try scope.put(self, "error", c.pi_js_undefined());
    try scope.set(self, "providers", arg(args, 0));
    try scope.set(self, "error", arg(args, 1));
    return c.JS_DupValue(engine.context, self);
}
fn getter(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = getBody(&scope, receiver, if (argc > 0) argv[0] else c.pi_js_undefined(), magic) catch |err| return sdk.fail(engine, err);
    return c.JS_DupValue(engine.context, result);
}
fn getBody(scope: *Scope, receiver: c.JSValue, id: c.JSValue, magic: c_int) !c.JSValue {
    return switch (magic) {
        0 => scope.invoke(try scope.get(receiver, "providers"), "get", &.{id}),
        1 => ids(scope, receiver),
        else => scope.get(receiver, "error"),
    };
}
fn ids(scope: *Scope, receiver: c.JSValue) !c.JSValue {
    const keys = try scope.invoke(try scope.get(receiver, "providers"), "keys", &.{});
    return scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(scope.engine, keys, null));
}
fn newConfig(scope: *Scope, bindings: c.JSValue, providers: c.JSValue, failure: c.JSValue) !c.JSValue {
    const args = [_]c.JSValue{ providers, failure };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, "ModelConfig"), args.len, @constCast(&args))));
}
fn emptyConfig(scope: *Scope, bindings: c.JSValue, failure: c.JSValue) !c.JSValue {
    return newConfig(scope, bindings, try scope.own(try js.builtin(scope.engine, "Map", &.{})), failure);
}
fn loadBody(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: flow.native.Completion, input: c.JSValue) !flow.native.Action {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (completion == .rejected and c.pi_js_native_allocation_error_generation(input) != 0) return error.OutOfMemory;
    if (completion == .start) {
        const owner = try flow.body.init(&scope, state);
        start(engine, owner, roots[0], arg(args, 0)) catch |err| try flow.rejectError(engine, owner, err);
    } else loaded(engine, state.*, input, completion == .rejected, 0) catch |err| try flow.rejectError(engine, state.*, err);
    return flow.body.action(&scope, state.*);
}
fn start(engine: *em.Engine, owner: c.JSValue, bindings: c.JSValue, path: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "bindings", bindings);
    if (!scope.truthy(path)) return flow.settle(engine, owner, false, try emptyConfig(&scope, bindings, c.pi_js_undefined()));
    try scope.put(owner, "path", try imported(&scope, bindings, "normalizePath", &.{path}));
    const generation = engine.native_allocation_generation;
    const pending = imported(&scope, bindings, "readFile", &.{ try scope.get(owner, "path"), try scope.text("utf-8") }) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        return readFailure(engine, owner, try scope.own(flow.reason(engine, err)));
    };
    try flow.wait(loaded, engine, owner, pending, 0);
}
fn failureText(scope: *Scope, reason: c.JSValue) !c.JSValue {
    const is_error = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (is_error < 0) return js.capture(scope.engine);
    return if (is_error != 0) scope.get(reason, "message") else reason;
}
fn failureConfig(scope: *Scope, owner: c.JSValue, prefix: []const u8, reason: c.JSValue) !c.JSValue {
    const message = try scope.concat(try scope.concat(try scope.text(prefix), try scope.stringify(try failureText(scope, reason))), try scope.concat(try scope.text("\n\nFile: "), try scope.stringify(try scope.get(owner, "path"))));
    return emptyConfig(scope, try scope.get(owner, "bindings"), message);
}
fn readFailure(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // Source's catch reads error.code even for a raw thrown value.
    const missing = scope.equal(try scope.get(reason, "code"), try scope.text("ENOENT"));
    const config = if (missing) try emptyConfig(&scope, try scope.get(owner, "bindings"), c.pi_js_undefined()) else try failureConfig(&scope, owner, "Failed to load models.json: ", reason);
    try flow.settle(engine, owner, false, config);
}
fn loaded(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    (if (rejected) readFailure(engine, owner, value) else loadedBody(engine, owner, value)) catch |err| try flow.rejectError(engine, owner, err);
}
fn parse(scope: *Scope, bindings: c.JSValue, content: c.JSValue) !c.JSValue {
    // JSON.parse member lookup precedes the imported text transformations.
    const json = try scope.global("JSON");
    const parser = try scope.get(json, "parse");
    return scope.call(parser, json, &.{try imported(scope, bindings, "stripJsonComments", &.{try imported(scope, bindings, "stripBom", &.{content})})});
}
fn loadedBody(engine: *em.Engine, owner: c.JSValue, content: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.get(owner, "bindings");
    const generation = engine.native_allocation_generation;
    const parsed = parse(&scope, bindings, content) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        const reason = try scope.own(flow.reason(engine, err));
        return flow.settle(engine, owner, false, try failureConfig(&scope, owner, "Failed to parse models.json: ", reason));
    };
    const validator = try scope.get(bindings, "validateModelsConfig");
    if (!scope.truthy(try scope.invoke(validator, "Check", &.{parsed}))) {
        const errors = try scope.invoke(validator, "Errors", &.{parsed});
        const mapper = try scope.own(try functions.createArrow(engine, "", 1, formatError, &.{}));
        const mapped = try scope.invoke(errors, "map", &.{mapper});
        const lines = try scope.invoke(mapped, "join", &.{try scope.text("\n")});
        const message = try scope.concat(try scope.concat(try scope.text("Invalid models.json schema:\n"), if (scope.truthy(lines)) lines else try scope.text("Unknown schema error")), try scope.concat(try scope.text("\n\nFile: "), try scope.stringify(try scope.get(owner, "path"))));
        return flow.settle(engine, owner, false, try emptyConfig(&scope, bindings, message));
    }
    const providers = try scope.own(try js.builtin(engine, "Map", &.{}));
    const object = try scope.global("Object");
    const entries_function = try scope.get(object, "entries");
    const entries = try scope.call(entries_function, object, &.{try scope.get(parsed, "providers")});
    var iterator = try js.Iterator.init(engine, entries, try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context))));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        var pair = try js.Iterator.init(engine, entry, try row.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context))));
        defer pair.deinit();
        errdefer pair.closePreserving();
        const provider_id = try row.own((try pair.next()) orelse c.pi_js_undefined());
        const provider = try row.own((try pair.next()) orelse c.pi_js_undefined());
        try pair.close();
        const set = try row.get(providers, "set");
        const copy = try row.call(try row.global("structuredClone"), c.pi_js_undefined(), &.{provider});
        _ = try row.call(set, providers, &.{ provider_id, try deepFreeze(&row, copy) });
    }
    try flow.settle(engine, owner, false, try newConfig(&scope, bindings, providers, c.pi_js_undefined()));
}
fn deepFreeze(scope: *Scope, value: c.JSValue) anyerror!c.JSValue {
    if (!c.JS_IsObject(value) or c.JS_IsFunction(scope.engine.context, value) or c.JS_IsNull(value)) return value;
    if (scope.truthy(try scope.invoke(try scope.global("Object"), "isFrozen", &.{value}))) return value;
    const children = try scope.invoke(try scope.global("Object"), "values", &.{value});
    var iterator = try js.Iterator.init(scope.engine, children, try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context))));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |child| {
        defer scope.engine.freeValue(child);
        _ = try deepFreeze(scope, child);
    }
    return scope.invoke(try scope.global("Object"), "freeze", &.{value});
}
fn pathText(scope: *Scope, error_value: c.JSValue) !c.JSValue {
    const first_args = [_]c.JSValue{try scope.text("^/")};
    const first = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, first_args.len, @constCast(&first_args))));
    const all_args = [_]c.JSValue{ try scope.text("/"), try scope.text("g") };
    const all = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, all_args.len, @constCast(&all_args))));
    return scope.invoke(try scope.invoke(try scope.get(error_value, "instancePath"), "replace", &.{ first, try scope.text("") }), "replace", &.{ all, try scope.text(".") });
}
fn formatPath(scope: *Scope, error_value: c.JSValue) !c.JSValue {
    if (scope.equal(try scope.get(error_value, "keyword"), try scope.text("required"))) {
        const properties = try scope.get(try scope.get(error_value, "params"), "requiredProperties");
        const property = if (temp.nullish(properties)) c.pi_js_undefined() else try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, properties, 0)));
        if (scope.truthy(property)) {
            const base = try pathText(scope, error_value);
            return if (scope.truthy(base)) scope.concat(try scope.concat(base, try scope.text(".")), try scope.stringify(property)) else property;
        }
    }
    const path = try pathText(scope, error_value);
    return if (scope.truthy(path)) path else scope.text("root");
}
fn formatError(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const error_value = arg(args, 0);
    const path = try formatPath(&scope, error_value);
    return c.JS_DupValue(engine.context, try scope.concat(try scope.concat(try scope.concat(try scope.text("  - "), try scope.stringify(path)), try scope.text(": ")), try scope.stringify(try scope.get(error_value, "message"))));
}
