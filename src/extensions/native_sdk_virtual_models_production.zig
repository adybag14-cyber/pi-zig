//! Native bodies of coding-agent/src/core/virtual-models.ts at 4954d760.
//! Imports are actual pi-ai exports; this module owns no synthetic SDK runtime.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const scopes = @import("native_sdk_prompt_scope.zig");
const Scope = scopes.Scope;
const functions = @import("native_node_function.zig");
const flow = @import("native_agent_async.zig");
const c = em.c;
pub const VIRTUAL_MODEL_API = "pi-virtual";
pub const VIRTUAL_MODEL_STATE_ENTRY = "pi.virtual-model-state";
const levels = [_][:0]const u8{ "off", "minimal", "low", "medium", "high", "xhigh", "max" };

fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn eq(s: *Scope, value: c.JSValue, expected: []const u8) !bool {
    return s.equal(value, try s.text(expected));
}
fn at(s: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, array, @intCast(index))));
}
fn default(s: *Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const existing = try s.get(object, name);
    return if (scopes.nullish(existing)) value else existing;
}
fn selection(s: *Scope, provider: c.JSValue, id: c.JSValue) !c.JSValue {
    const result = try s.object();
    try s.put(result, "provider", provider);
    try s.put(result, "modelId", id);
    return result;
}
pub fn isVirtualModel(engine: *em.Engine, model: c.JSValue) !bool {
    if (scopes.nullish(model)) {
        _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot read properties of %s (reading 'api')", @as([*:0]const u8, if (c.JS_IsNull(model)) "null" else "undefined")));
        unreachable;
    }
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return eq(&s, try s.get(model, "api"), VIRTUAL_MODEL_API);
}
pub fn findLatestResponse(engine: *em.Engine, messages: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var index = try sdk.length(engine, messages);
    while (index > 0) {
        index -= 1;
        const message = try at(&s, messages, index);
        if (try eq(&s, try s.get(message, "role"), "assistant") and
            !try eq(&s, try s.get(message, "stopReason"), "error") and
            !try eq(&s, try s.get(message, "stopReason"), "aborted")) return c.JS_DupValue(engine.context, message);
    }
    return c.pi_js_undefined();
}
fn findLastModelChange(s: *Scope, branch: c.JSValue, before: usize) !c.JSValue {
    var index = before;
    while (index > 0) {
        index -= 1;
        const entry = try at(s, branch, index);
        if (try eq(s, try s.get(entry, "type"), "model_change")) return selection(s, try s.get(entry, "provider"), try s.get(entry, "modelId"));
    }
    return c.pi_js_undefined();
}
pub fn getBranchSelection(engine: *em.Engine, branch: c.JSValue, get_model: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var index = try sdk.length(engine, branch);
    while (index > 0) {
        index -= 1;
        const entry = try at(&s, branch, index);
        if (try eq(&s, try s.get(entry, "type"), "model_change")) {
            return c.JS_DupValue(engine.context, try selection(&s, try s.get(entry, "provider"), try s.get(entry, "modelId")));
        }
        if (try eq(&s, try s.get(entry, "type"), "message") and
            try eq(&s, try s.get(try s.get(entry, "message"), "role"), "assistant") and
            !try isVirtualModel(engine, try s.get(entry, "message")))
        {
            const response = try selection(&s, try s.get(try s.get(entry, "message"), "provider"), try s.get(try s.get(entry, "message"), "model"));
            const change = try findLastModelChange(&s, branch, index);
            const model = if (s.truthy(change)) try s.call(get_model, c.pi_js_undefined(), &.{ try s.get(change, "provider"), try s.get(change, "modelId") }) else change;
            return c.JS_DupValue(engine.context, if (s.truthy(change) and s.truthy(model) and try isVirtualModel(engine, model)) change else response);
        }
    }
    return c.pi_js_undefined();
}
pub fn getVirtualModelState(engine: *em.Engine, branch: c.JSValue, provider: c.JSValue, model_id: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var index = try sdk.length(engine, branch);
    while (index > 0) {
        index -= 1;
        const entry = try at(&s, branch, index);
        if (!try eq(&s, try s.get(entry, "type"), "custom") or !try eq(&s, try s.get(entry, "customType"), VIRTUAL_MODEL_STATE_ENTRY)) continue;
        const data = try s.get(entry, "data");
        const data_provider = if (scopes.nullish(data)) c.pi_js_undefined() else try s.get(data, "provider");
        if (s.equal(data_provider, provider) and s.equal(try s.get(data, "modelId"), model_id)) return c.JS_DupValue(engine.context, try s.get(data, "state"));
    }
    return c.pi_js_undefined();
}
fn notOff(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(!try eq(&s, arg(args, 0), "off")));
}
pub fn createVirtualModel(engine: *em.Engine, definition: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    // The nullish default is allocated only when the source takes that branch.
    var offered = try s.get(definition, "thinkingLevels");
    if (scopes.nullish(offered)) {
        offered = try s.array();
        try s.index(offered, 0, try s.text("off"));
    }
    const map = try s.object();
    for (levels) |level| {
        const name = try s.text(level);
        try s.set(map, level, if (s.truthy(try s.invoke(offered, "includes", &.{name}))) name else c.pi_js_null());
    }
    const result = try s.object();
    inline for (.{ "id", "name" }) |field| try s.put(result, field, try s.get(definition, field));
    try s.put(result, "api", try s.text(VIRTUAL_MODEL_API));
    try s.put(result, "provider", try s.get(definition, "provider"));
    try s.put(result, "baseUrl", try s.text(""));
    const predicate = try s.own(try functions.createArrow(engine, "", 1, notOff, &.{}));
    try s.put(result, "reasoning", try s.invoke(offered, "some", &.{predicate}));
    try s.put(result, "thinkingLevelMap", map);
    var input = try s.get(definition, "input");
    if (scopes.nullish(input)) {
        input = try s.array();
        try s.index(input, 0, try s.text("text"));
        try s.index(input, 1, try s.text("image"));
    }
    try s.put(result, "input", input);
    const cost = try s.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite" }) |field| try s.put(cost, field, c.JS_NewInt32(engine.context, 0));
    try s.put(result, "cost", cost);
    inline for (.{ "contextWindow", "maxTokens" }) |field| try s.put(result, field, try default(&s, definition, field, c.JS_NewInt32(engine.context, 0)));
    return c.JS_DupValue(engine.context, result);
}

// Actual lazyStream controls when the async body is entered and how failures
// become stream events. The native callback only supplies the original body.
fn lazyFailure(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    lazyFailureBody(engine, roots[0]) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    unreachable;
}
fn lazyFailureBody(engine: *em.Engine, model: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var message = try s.concat(try s.text("Virtual model "), try s.stringify(try s.get(model, "provider")));
    message = try s.concat(message, try s.text("/"));
    message = try s.concat(message, try s.stringify(try s.get(model, "id")));
    message = try s.concat(message, try s.text(" must be routed before streaming"));
    const failure = try s.own(try js.builtin(engine, "Error", &.{message}));
    _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure)));
    unreachable;
}
fn asyncArrow(s: *Scope, name: [*:0]const u8, length: c_int, callback: functions.Callback, roots: []const c.JSValue) !c.JSValue {
    const function = try s.own(try functions.createArrow(s.engine, name, length, callback, roots));
    const prototype = try s.own(try s.engine.checked(c.JS_GetAsyncFunctionPrototype(s.engine.context)));
    if (c.JS_SetPrototype(s.engine.context, function, prototype) < 0) return js.capture(s.engine);
    return function;
}
fn unroutedStream(engine: *em.Engine, lazy_stream: c.JSValue, model: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const body = try asyncArrow(&s, "", 0, lazyFailure, &.{model});
    return js.call(engine, lazy_stream, c.pi_js_undefined(), &.{ model, body });
}
fn resolveVirtual(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.object();
    try s.put(result, "auth", try s.object());
    try s.put(result, "source", try s.text("virtual"));
    try flow.settle(engine, pending.owner, false, result);
    return pending.promise;
}
fn modelId(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return js.get(engine, arg(args, 0), "id");
}
fn physicalPredicate(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const model = arg(args, 0);
    if (try isVirtualModel(engine, model)) return c.pi_js_bool(engine.context, 0);
    if (s.truthy(try s.call(roots[0], c.pi_js_undefined(), &.{ model, try s.text("chat") })) and
        s.truthy(try s.invoke(roots[1], "has", &.{try s.get(model, "id")}))) return c.pi_js_bool(engine.context, 0);
    return c.pi_js_bool(engine.context, 1);
}
fn virtualPredicate(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try isVirtualModel(engine, arg(args, 0))));
}
fn physicalFilter(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const predicate = try functions.createArrow(engine, "", 1, physicalPredicate, roots);
    defer engine.freeValue(predicate);
    return js.invoke(engine, arg(args, 0), "filter", &.{predicate});
}
fn virtualFilter(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const predicate = try functions.createArrow(engine, "", 1, virtualPredicate, &.{});
    defer engine.freeValue(predicate);
    return js.invoke(engine, arg(args, 0), "filter", &.{predicate});
}
fn appendIterable(s: *Scope, result: c.JSValue, iterable: c.JSValue) !void {
    const symbol = try s.get(try s.global("Symbol"), "iterator");
    var iterator = try js.Iterator.init(s.engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer s.engine.freeValue(item);
        const length = try sdk.length(s.engine, result);
        try s.index(result, length, item);
    }
}
const ProviderMethod = enum { getModels, getAllModels, filterModels, filterAllModels, stream, streamSimple, bareModels, bareStream };
fn method(comptime kind: ProviderMethod) functions.Callback {
    return struct {
        fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
            var s: Scope = .{ .engine = engine };
            defer s.deinit();
            if (kind == .bareModels) return c.JS_DupValue(engine.context, roots[0]);
            if (kind == .bareStream) return unroutedStream(engine, roots[0], arg(args, 0));
            const provider = roots[0];
            if (kind == .stream or kind == .streamSimple) {
                if (try isVirtualModel(engine, arg(args, 0))) return unroutedStream(engine, roots[1], arg(args, 0));
                return js.invoke(engine, provider, @tagName(kind), &.{ arg(args, 0), arg(args, 1), arg(args, 2) });
            }
            const physical = roots[1];
            const virtual = roots[2];
            const result = try s.array();
            if (kind == .getModels or kind == .getAllModels) {
                var models: c.JSValue = undefined;
                if (kind == .getAllModels) {
                    const getter = try s.get(provider, "getAllModels");
                    models = if (scopes.nullish(getter)) c.pi_js_undefined() else try s.call(getter, provider, &.{});
                    if (scopes.nullish(models)) models = try s.invoke(provider, "getModels", &.{});
                } else models = try s.invoke(provider, "getModels", &.{});
                const real = try s.call(physical, c.pi_js_undefined(), &.{models});
                try appendIterable(&s, result, real);
                try appendIterable(&s, result, virtual);
            } else {
                const real = try s.call(physical, c.pi_js_undefined(), &.{arg(args, 0)});
                const filter = roots[3];
                var filtered = if (kind == .filterModels and scopes.nullish(filter)) c.pi_js_undefined() else try s.call(filter, c.pi_js_undefined(), &.{ real, arg(args, 1) });
                if (kind == .filterModels and scopes.nullish(filtered)) filtered = real;
                try appendIterable(&s, result, filtered);
                const virtual_rows = try s.call(virtual, c.pi_js_undefined(), &.{arg(args, 0)});
                try appendIterable(&s, result, virtual_rows);
            }
            return c.JS_DupValue(engine.context, result);
        }
    }.call;
}
fn attach(s: *Scope, target: c.JSValue, comptime kind: ProviderMethod, length: c_int, roots: []const c.JSValue) !void {
    try s.put(target, @tagName(kind), try s.own(try functions.createArrow(s.engine, @tagName(kind), length, method(kind), roots)));
}
fn withVirtualModels(engine: *em.Engine, imports: c.JSValue, provider_id: c.JSValue, provider: c.JSValue, virtual_models: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const lazy_stream = try s.get(imports, "lazyStream");
    if (!s.truthy(provider)) {
        const result = try s.object();
        try s.put(result, "id", provider_id);
        try s.put(result, "name", provider_id);
        const auth = try s.object();
        const api_key = try s.object();
        try s.put(api_key, "name", try s.text("Virtual model"));
        try s.put(api_key, "resolve", try asyncArrow(&s, "resolve", 0, resolveVirtual, &.{}));
        try s.put(auth, "apiKey", api_key);
        try s.put(result, "auth", auth);
        try s.put(result, "getModels", try s.own(try functions.createArrow(engine, "getModels", 0, method(.bareModels), &.{virtual_models})));
        const stream = try s.get(imports, "unroutedStream");
        try s.put(result, "stream", stream);
        try s.put(result, "streamSimple", stream);
        return c.JS_DupValue(engine.context, result);
    }
    const id_mapper = try s.own(try functions.createArrow(engine, "", 1, modelId, &.{}));
    const ids = try s.own(try js.builtin(engine, "Set", &.{try s.invoke(virtual_models, "map", &.{id_mapper})}));
    const physical = try s.own(try functions.createArrow(engine, "physical", 1, physicalFilter, &.{ try s.get(imports, "isModelType"), ids }));
    const virtual = try s.own(try functions.createArrow(engine, "virtual", 1, virtualFilter, &.{}));
    // Destructure before spread, exactly as the source. The filters are plain
    // calls, whereas catalog and physical stream methods retain the provider.
    const filter_models = try s.get(provider, "filterModels");
    const filter_all = try s.get(provider, "filterAllModels");
    const result = try s.own(try js.spread(engine, provider));
    try attach(&s, result, .getModels, 0, &.{ provider, physical, virtual_models });
    try attach(&s, result, .getAllModels, 0, &.{ provider, physical, virtual_models });
    try attach(&s, result, .filterModels, 2, &.{ provider, physical, virtual, filter_models });
    if (s.truthy(filter_all)) {
        try attach(&s, result, .filterAllModels, 2, &.{ provider, physical, virtual, filter_all });
    } else try s.put(result, "filterAllModels", filter_all);
    try attach(&s, result, .stream, 3, &.{ provider, lazy_stream });
    try attach(&s, result, .streamSimple, 3, &.{ provider, lazy_stream });
    return c.JS_DupValue(engine.context, result);
}
const Export = enum { isVirtualModel, findLatestResponse, getBranchSelection, getVirtualModelState, createVirtualModel, withVirtualModels };
fn exported(comptime kind: Export) functions.Callback {
    return struct {
        fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
            return switch (kind) {
                .isVirtualModel => c.pi_js_bool(engine.context, @intFromBool(try isVirtualModel(engine, arg(args, 0)))),
                .findLatestResponse => findLatestResponse(engine, arg(args, 0)),
                .getBranchSelection => getBranchSelection(engine, arg(args, 0), arg(args, 1)),
                .getVirtualModelState => getVirtualModelState(engine, arg(args, 0), arg(args, 1), arg(args, 2)),
                .createVirtualModel => createVirtualModel(engine, arg(args, 0)),
                .withVirtualModels => withVirtualModels(engine, roots[0], arg(args, 0), arg(args, 1), arg(args, 2)),
            };
        }
    }.call;
}
/// Required imported functions must come from the actual pi-ai namespace.
/// Namespace capture snapshots imports as ESM bindings, independently of later
/// mutations to the caller's temporary import object.
pub fn create(engine: *em.Engine, actual_imports: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const imports = try s.object();
    inline for (.{ "isModelType", "lazyStream" }) |name| {
        const value = try s.get(actual_imports, name);
        if (!c.JS_IsFunction(engine.context, value)) return js.typeError(engine, "virtual-models requires actual pi-ai isModelType and lazyStream exports");
        try s.put(imports, name, value);
    }
    try s.put(imports, "unroutedStream", try s.own(try functions.create(engine, "unroutedStream", 1, method(.bareStream), &.{try s.get(imports, "lazyStream")})));
    const result = try s.object();
    try s.put(result, "VIRTUAL_MODEL_API", try s.text(VIRTUAL_MODEL_API));
    try s.put(result, "VIRTUAL_MODEL_STATE_ENTRY", try s.text(VIRTUAL_MODEL_STATE_ENTRY));
    inline for (@typeInfo(Export).@"enum".fields) |field| {
        const kind: Export = @enumFromInt(field.value);
        const length: c_int = switch (kind) {
            .getBranchSelection => 2,
            .getVirtualModelState, .withVirtualModels => 3,
            else => 1,
        };
        try s.put(result, field.name, try s.own(try functions.create(engine, field.name, length, exported(kind), &.{imports})));
    }
    return c.JS_DupValue(engine.context, result);
}
