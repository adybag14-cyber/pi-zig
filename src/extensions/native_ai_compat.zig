//! Original global pi-ai compat dispatch, separate from configurable Models.
//! The captured dependencies must be actual module implementations in production.
//! This private boundary does not claim native builtin transport qualification.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const temp = @import("native_models_stream_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub const builtin_api_ids = [_][]const u8{ "anthropic-messages", "openai-completions", "openai-responses", "openai-codex-responses", "azure-openai-responses", "google-generative-ai", "google-vertex", "mistral-conversations", "bedrock-converse-stream", "pi-messages" };
pub const BuiltinApi = struct {
    api: []const u8,
    streams: ?c.JSValue = null,
    /// Production calls the actual API constructor once while creating the
    /// module's BUILTIN_APIS table. Resets retain those same lazy wrappers.
    factory: ?c.JSValue = null,
};
pub const Dependencies = struct {
    builtin_apis: []const BuiltinApi,
    compat_models: c.JSValue,
    get_env_api_key: c.JSValue,
};
/// Assemble the actual compat dispatch module from all ten native API
/// constructors and the real providers/all builtinModels export. The latter
/// is supplied by the provider/Models module owner; no empty registry fallback
/// is accepted here. This exports the dispatch surface, not all index.ts APIs.
pub fn namespace(engine: *em.Engine, builtin_models: c.JSValue) !c.JSValue {
    if (engine.native_ai_compat_exports) |cached| return c.JS_DupValue(engine.context, cached);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const apis = try scope.own(try @import("native_ai_builtin_apis.zig").create(engine));
    const env = try scope.own(try @import("native_ai_env_keys.zig").namespace(engine));
    var entries: [builtin_api_ids.len]BuiltinApi = undefined;
    const constructors = .{ "anthropicMessagesApi", "openAICompletionsApi", "openAIResponsesApi", "openAICodexResponsesApi", "azureOpenAIResponsesApi", "googleGenerativeAIApi", "googleVertexApi", "mistralConversationsApi", "bedrockConverseStreamApi", "piMessagesApi" };
    // Source's constant BUILTIN_APIS is evaluated before builtinModels().
    inline for (constructors, 0..) |name, i| entries[i] = .{
        .api = builtin_api_ids[i],
        .streams = try scope.call(try scope.get(apis, name), c.pi_js_undefined(), &.{}),
    };
    const models = try scope.call(builtin_models, c.pi_js_undefined(), &.{});
    const output = try scope.own(try create(engine, .{
        .builtin_apis = &entries,
        .compat_models = models,
        .get_env_api_key = try scope.get(env, "getEnvApiKey"),
    }));
    engine.native_ai_compat_exports = c.JS_DupValue(engine.context, output);
    return c.JS_DupValue(engine.context, output);
}
const Method = enum { registerApiProvider, getApiProvider, getApiProviders, unregisterApiProviders, registerBuiltInApiProviders, resetApiProviders, stream, streamSimple, complete, completeSimple };
pub fn create(engine: *em.Engine, dependencies: Dependencies) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "registry", try scope.own(try js.builtin(engine, "Map", &.{})));
    try scope.put(owner, "instances", try scope.own(try js.builtin(engine, "Map", &.{})));
    try scope.put(owner, "models", dependencies.compat_models);
    try scope.put(owner, "env", dependencies.get_env_api_key);
    const builtins = try scope.array();
    for (dependencies.builtin_apis, 0..) |entry, i| {
        if (entry.streams == null and entry.factory == null) return error.NativeBuiltinApiImplementationUnavailable;
        const pair = try scope.array();
        const api = try scope.text(entry.api);
        try scope.index(pair, 0, api);
        const streams = if (entry.factory) |factory| try scope.call(factory, c.pi_js_undefined(), &.{}) else entry.streams.?;
        try scope.index(pair, 1, streams);
        try scope.index(builtins, @intCast(i), pair);
    }
    try scope.put(owner, "builtins", builtins);
    try registerBuiltins(&scope, owner);
    const exports = try scope.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                return dispatch(host, roots[0], method, args);
            }
            fn asyncCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
                const host = em.Engine.fromContext(context.?);
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                return dispatch(host, roots[0], method, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(host, err);
            }
        };
        const length = switch (method) {
            .registerApiProvider => 2,
            .getApiProvider, .unregisterApiProviders => 1,
            .stream, .streamSimple, .complete, .completeSimple => 3,
            else => 0,
        };
        const function = if (method == .complete or method == .completeSimple) async_function: {
            var data = [_]c.JSValue{owner};
            const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, Adapter.asyncCall, field.name, length, 0, data.len, &data)));
            const prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return js.capture(engine);
            break :async_function function;
        } else try scope.own(try @import("native_node_function.zig").create(engine, field.name, length, Adapter.call, &.{owner}));
        try scope.put(exports, field.name, function);
    }
    return c.JS_DupValue(engine.context, exports);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn at(scope: *Scope, value: c.JSValue, index: u32) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, index)));
}
fn lookup(scope: *Scope, owner: c.JSValue, api: c.JSValue) !c.JSValue {
    const entry = try scope.invoke(try scope.get(owner, "registry"), "get", &.{api});
    return if (temp.nullish(entry)) c.pi_js_undefined() else scope.get(entry, "provider");
}
fn iterator(scope: *Scope, iterable: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, iterable, try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context))));
}
fn wrapped(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return wrapper(engine, roots[0], roots[1], if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn errorMessage(scope: *Scope, prefix: []const u8, first: c.JSValue, middle: []const u8, second: ?c.JSValue) !c.JSValue {
    var text = try scope.concat(try scope.text(prefix), try scope.stringify(first));
    if (second) |value| text = try scope.concat(try scope.concat(text, try scope.text(middle)), try scope.stringify(value));
    const failure = try scope.own(try js.builtin(scope.engine, "Error", &.{text}));
    return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, failure)));
}
fn wrapper(engine: *em.Engine, api: c.JSValue, function: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.equal(try scope.get(argument(args, 0), "api"), api)) return errorMessage(&scope, "Mismatched api: ", try scope.get(argument(args, 0), "api"), " expected ", api);
    return js.call(engine, function, c.pi_js_undefined(), &.{ argument(args, 0), argument(args, 1), argument(args, 2) });
}
fn wrap(scope: *Scope, api: c.JSValue, function: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{ api, function };
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, wrapped, "", 3, 0, data.len, &data)));
}
fn register(scope: *Scope, owner: c.JSValue, provider: c.JSValue, source_id: c.JSValue) !void {
    const registry = try scope.get(owner, "registry");
    const setter = try scope.get(registry, "set");
    const key = try scope.get(provider, "api");
    const entry = try scope.object();
    const internal = try scope.object();
    try scope.put(internal, "api", try scope.get(provider, "api"));
    try scope.put(internal, "stream", try wrap(scope, try scope.get(provider, "api"), try scope.get(provider, "stream")));
    try scope.put(internal, "streamSimple", try wrap(scope, try scope.get(provider, "api"), try scope.get(provider, "streamSimple")));
    try scope.put(entry, "provider", internal);
    try scope.put(entry, "sourceId", source_id);
    _ = try scope.call(setter, registry, &.{ key, entry });
}
fn registerBuiltins(scope: *Scope, owner: c.JSValue) !void {
    var items = try iterator(scope, try scope.get(owner, "builtins"));
    defer items.deinit();
    errdefer items.closePreserving();
    while (try items.next()) |pair| {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        _ = try row.own(pair);
        const fields = try js.pair(scope.engine, pair, try row.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context))));
        defer for (fields) |field| scope.engine.freeValue(field);
        const api = fields[0];
        if (!row.truthy(try lookup(&row, owner, api))) {
            const streams = fields[1];
            const provider = try row.object();
            try row.put(provider, "api", api);
            try row.put(provider, "stream", try row.get(streams, "stream"));
            try row.put(provider, "streamSimple", try row.get(streams, "streamSimple"));
            try register(&row, owner, provider, c.pi_js_undefined());
        }
        const instances = try row.get(owner, "instances");
        const setter = try row.get(instances, "set");
        _ = try row.call(setter, instances, &.{ api, try lookup(&row, owner, api) });
    }
}
fn mapProvider(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "provider") catch |err| sdk.fail(engine, err);
}
fn dispatch(engine: *em.Engine, owner: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    if (method == .complete or method == .completeSimple) {
        const pending = try flow.create(engine, owner);
        defer engine.freeValue(pending.owner);
        errdefer engine.freeValue(pending.promise);
        complete(engine, owner, method == .completeSimple, args, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    }
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (method) {
        .registerApiProvider => try register(&scope, owner, argument(args, 0), argument(args, 1)),
        .getApiProvider => return c.JS_DupValue(engine.context, try lookup(&scope, owner, argument(args, 0))),
        .getApiProviders => {
            const values = try scope.invoke(try scope.get(owner, "registry"), "values", &.{});
            const function = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, mapProvider, "", 1)));
            return js.invoke(engine, try scope.global("Array"), "from", &.{ values, function });
        },
        .unregisterApiProviders => {
            const registry = try scope.get(owner, "registry");
            var entries = try iterator(&scope, try scope.invoke(registry, "entries", &.{}));
            defer entries.deinit();
            errdefer entries.closePreserving();
            while (try entries.next()) |pair| {
                var row: Scope = .{ .engine = engine };
                defer row.deinit();
                _ = try row.own(pair);
                const fields = try js.pair(engine, pair, try row.own(try engine.checked(JS_GetIteratorSymbol(engine.context))));
                defer for (fields) |field| engine.freeValue(field);
                if (row.equal(try row.get(fields[1], "sourceId"), argument(args, 0))) _ = try row.invoke(registry, "delete", &.{fields[0]});
            }
        },
        .registerBuiltInApiProviders => try registerBuiltins(&scope, owner),
        .resetApiProviders => {
            _ = try scope.invoke(try scope.get(owner, "registry"), "clear", &.{});
            _ = try scope.invoke(try scope.get(owner, "instances"), "clear", &.{});
            try registerBuiltins(&scope, owner);
        },
        .stream, .streamSimple => return stream(engine, owner, method == .streamSimple, args),
        else => unreachable,
    }
    return c.pi_js_undefined();
}
fn complete(engine: *em.Engine, owner: c.JSValue, simple: bool, args: []const c.JSValue, pending: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = try scope.own(try stream(engine, owner, simple, args));
    try flow.settle(engine, pending, false, try scope.invoke(value, "result", &.{}));
}
fn explicitKey(scope: *Scope, key: c.JSValue) !bool {
    if (!c.JS_IsString(key)) return false;
    const trimmed = try scope.invoke(key, "trim", &.{});
    return scope.positive(try scope.get(trimmed, "length"));
}
fn optional(scope: *Scope, value: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(value)) c.pi_js_undefined() else scope.get(value, key);
}
fn envOptions(scope: *Scope, owner: c.JSValue, model: c.JSValue, options: c.JSValue) !c.JSValue {
    if (try explicitKey(scope, try optional(scope, options, "apiKey"))) return options;
    const api_key = try scope.call(try scope.get(owner, "env"), c.pi_js_undefined(), &.{ try scope.get(model, "provider"), try optional(scope, options, "env") });
    if (!scope.truthy(api_key) or scope.equal(api_key, try scope.text("<authenticated>"))) return options;
    const output = try scope.own(try js.spread(scope.engine, options));
    try scope.put(output, "apiKey", api_key);
    return output;
}
fn matchingApi(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return matches(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn matches(engine: *em.Engine, candidate: c.JSValue, model: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(candidate, "api"), try scope.get(model, "api"))));
}
fn builtinProvider(scope: *Scope, owner: c.JSValue, model: c.JSValue) !c.JSValue {
    const current = try lookup(scope, owner, try scope.get(model, "api"));
    const expected = try scope.invoke(try scope.get(owner, "instances"), "get", &.{try scope.get(model, "api")});
    if (!scope.equal(current, expected)) return c.pi_js_undefined();
    const provider = try scope.invoke(try scope.get(owner, "models"), "getProvider", &.{try scope.get(model, "provider")});
    if (temp.nullish(provider)) return c.pi_js_undefined();
    const models = try scope.invoke(provider, "getModels", &.{});
    const some = try scope.get(models, "some");
    var roots = [_]c.JSValue{model};
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, matchingApi, "", 1, 0, roots.len, &roots)));
    return if (scope.truthy(try scope.call(some, models, &.{callback}))) provider else c.pi_js_undefined();
}
fn stream(engine: *em.Engine, owner: c.JSValue, simple: bool, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const model = argument(args, 0);
    const options = argument(args, 2);
    const transcript = try scope.own(try @import("native_ai_transcript_context.zig").normalize(engine, argument(args, 1)));
    const builtin = try builtinProvider(&scope, owner, model);
    const name: [*:0]const u8 = if (simple) "streamSimple" else "stream";
    if (scope.truthy(builtin)) {
        const cloudflare = scope.truthy(try scope.invoke(try scope.get(model, "provider"), "startsWith", &.{try scope.text("cloudflare-")}));
        if (cloudflare) {
            const explicit = try explicitKey(&scope, try optional(&scope, options, "apiKey"));
            const headers = if (explicit) c.pi_js_undefined() else try optional(&scope, options, "headers");
            if (!explicit and !c.JS_IsString(try optional(&scope, headers, "cf-aig-authorization"))) return js.invoke(engine, try scope.get(owner, "models"), name, &.{ model, transcript, options });
        }
        return js.invoke(engine, builtin, name, &.{ model, transcript, try envOptions(&scope, owner, model, options) });
    }
    const provider = try lookup(&scope, owner, try scope.get(model, "api"));
    if (!scope.truthy(provider)) return errorMessage(&scope, "No API provider registered for api: ", try scope.get(model, "api"), "", null);
    return js.invoke(engine, provider, name, &.{ model, transcript, try envOptions(&scope, owner, model, options) });
}
