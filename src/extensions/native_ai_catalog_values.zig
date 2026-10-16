//! One retained actual generated catalog graph per Engine. Query namespaces,
//! provider factories and OAuth policy filters share these same model objects.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const c = em.c;
const group_order = @import("native_ai_catalog_group_order.zig");
pub const provider_ids = [_][]const u8{ "amazon-bedrock", "ant-ling", "anthropic", "azure", "baseten", "cerebras", "cloudflare-ai-gateway", "cloudflare-workers-ai", "deepseek", "fireworks", "github-copilot", "google", "google-vertex", "groq", "huggingface", "kimi-coding", "meta", "minimax", "minimax-cn", "mistral", "moonshotai", "moonshotai-cn", "nvidia", "openai", "openai-codex", "opencode", "opencode-go", "openrouter", "qwen-token-plan", "qwen-token-plan-cn", "qwen-token-plan-individual", "radius", "together", "typesafe", "vercel-ai-gateway", "xai", "xiaomi", "xiaomi-token-plan-ams", "xiaomi-token-plan-cn", "xiaomi-token-plan-sgp", "zai", "zai-coding-cn" };
const Method = enum {
    getBuiltinModel,
    getBuiltinModels,
    getBuiltinProviders,
    getBuiltinImageModel,
    getBuiltinImageModels,
    getBuiltinClassifierModel,
    getBuiltinClassifierModels,
    getAllBuiltinModels,
    getBuiltinModelDataGeneratedAt,
    getImageModel,
    getImageModels,
    getImageProviders,
};
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn parse(scope: *Scope, text: [:0]const u8, name: [*:0]const u8) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_ParseJSON(scope.engine.context, text.ptr, text.len, name)));
}
fn property(scope: *Scope, object: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const atom = try js.atom(scope.engine, key);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, object, atom, c.JS_DupValue(scope.engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(scope.engine);
}
fn group(scope: *Scope, owner: c.JSValue, kind: [*:0]const u8, provider: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, try scope.get(owner, kind), provider));
}
fn values(scope: *Scope, owner: c.JSValue, kind: [*:0]const u8, provider: c.JSValue) !c.JSValue {
    const models = try group(scope, owner, kind, provider);
    return scope.invoke(try scope.global("Object"), "values", &.{if (c.JS_IsUndefined(models) or c.JS_IsNull(models)) try scope.object() else models});
}
fn dispatch(engine: *em.Engine, owner: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const provider = argument(args, 0);
    switch (method) {
        .getBuiltinModel, .getBuiltinImageModel, .getBuiltinClassifierModel => {
            const kind: [*:0]const u8 = switch (method) {
                .getBuiltinModel => "chat",
                .getBuiltinImageModel => "image",
                else => "classifier",
            };
            const models = try group(&scope, owner, kind, provider);
            return if (c.JS_IsUndefined(models) or c.JS_IsNull(models)) c.pi_js_undefined() else js.getKey(engine, models, argument(args, 1));
        },
        .getBuiltinModels, .getBuiltinImageModels, .getBuiltinClassifierModels => return c.JS_DupValue(engine.context, try values(&scope, owner, switch (method) {
            .getBuiltinModels => "chat",
            .getBuiltinImageModels => "image",
            else => "classifier",
        }, provider)),
        .getBuiltinProviders => return js.invoke(engine, try scope.global("Object"), "keys", &.{try scope.get(owner, "chat")}),
        .getAllBuiltinModels => {
            const result = try scope.array();
            const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
            var index: u32 = 0;
            inline for (.{ "chat", "image", "classifier" }) |kind| {
                var row: Scope = .{ .engine = engine };
                defer row.deinit();
                var iterator = try js.Iterator.init(engine, try values(&row, owner, kind, provider), symbol);
                defer iterator.deinit();
                errdefer iterator.closePreserving();
                while (try iterator.next()) |value| {
                    defer engine.freeValue(value);
                    try scope.index(result, index, value);
                    index += 1;
                }
            }
            return c.JS_DupValue(engine.context, result);
        },
        .getBuiltinModelDataGeneratedAt => {
            const parsed = try scope.invoke(try scope.global("Date"), "parse", &.{try scope.get(owner, "generatedAt")});
            const invalid = try scope.invoke(try scope.global("Number"), "isNaN", &.{parsed});
            return if (scope.truthy(invalid)) c.pi_js_undefined() else c.JS_DupValue(engine.context, parsed);
        },
        .getImageModel => {
            const models = try scope.invoke(try scope.get(owner, "imageMap"), "get", &.{provider});
            return if (c.JS_IsUndefined(models) or c.JS_IsNull(models)) c.pi_js_undefined() else js.invoke(engine, models, "get", &.{argument(args, 1)});
        },
        .getImageModels, .getImageProviders => {
            const map = try scope.get(owner, "imageMap");
            const models = if (method == .getImageModels) try scope.invoke(map, "get", &.{provider}) else map;
            if (method == .getImageModels and !scope.truthy(models)) return js.array(engine);
            const array = try scope.global("Array");
            const from = try scope.get(array, "from");
            const entries = try scope.invoke(models, if (method == .getImageModels) "values" else "keys", &.{});
            return js.call(engine, from, array, &.{entries});
        },
    }
}
fn build(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    const source_bytes = @embedFile("../ai/catalog_source.json");
    const manifest_bytes = @embedFile("../ai/catalog_builtin_manifest.json");
    try group_order.validateAuthority(source_bytes, manifest_bytes);
    const document = try parse(&scope, source_bytes, "builtin-catalog.json");
    const manifest = try parse(&scope, manifest_bytes, "builtin-catalog-manifest.json");
    try scope.put(owner, "generatedAt", try scope.get(manifest, "generatedAt"));
    inline for (.{ "chat", "image", "classifier" }) |kind| {
        const table = try scope.object();
        try scope.put(owner, kind, table);
        for (provider_ids) |provider| {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            try property(&row, table, try row.text(provider), try row.object());
        }
    }
    const models = try scope.get(document, "models");
    const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, models, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |model| {
        defer engine.freeValue(model);
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const provider = try engine.toString(try row.get(model, "provider"));
        defer engine.gpa.free(provider);
        if (group_order.grouped(provider)) {
            const api = try engine.toString(try row.get(model, "api"));
            defer engine.gpa.free(api);
            try group_order.requireDeclaredApi(provider, api);
        } else try insertModel(&row, owner, model);
    }
    // The normalized document sorts IDs across APIs. Source flattens each
    // provider's declared API groups in order; retain the same actual model
    // objects and last-group replacement behavior for duplicate IDs.
    for (group_order.entries) |entry| {
        for (entry.apis) |api| {
            var ordered = try js.Iterator.init(engine, models, symbol);
            defer ordered.deinit();
            errdefer ordered.closePreserving();
            while (try ordered.next()) |model| {
                defer engine.freeValue(model);
                var row: Scope = .{ .engine = engine };
                defer row.deinit();
                const provider = try engine.toString(try row.get(model, "provider"));
                defer engine.gpa.free(provider);
                if (!@import("std").mem.eql(u8, provider, entry.provider)) continue;
                const model_api = try engine.toString(try row.get(model, "api"));
                defer engine.gpa.free(model_api);
                if (@import("std").mem.eql(u8, model_api, api)) try insertModel(&row, owner, model);
            }
        }
    }
    const image_map = try scope.own(try js.builtin(engine, "Map", &.{}));
    try scope.put(owner, "imageMap", image_map);
    for (provider_ids) |provider| {
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const key = try row.text(provider);
        const image_models = try row.own(try js.builtin(engine, "Map", &.{}));
        var entries = try js.Iterator.init(engine, try values(&row, owner, "image", key), symbol);
        defer entries.deinit();
        errdefer entries.closePreserving();
        while (try entries.next()) |model| {
            defer engine.freeValue(model);
            var entry: Scope = .{ .engine = engine };
            defer entry.deinit();
            _ = try entry.invoke(image_models, "set", &.{ try entry.get(model, "id"), model });
        }
        if (try row.positive(try row.get(image_models, "size"))) _ = try row.invoke(image_map, "set", &.{ key, image_models });
    }
    const exports = try scope.object();
    try scope.put(owner, "namespace", exports);
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                return dispatch(host, roots[0], method, args);
            }
        };
        const length: c_int = switch (method) {
            .getBuiltinModel, .getBuiltinImageModel, .getBuiltinClassifierModel, .getImageModel => 2,
            .getBuiltinProviders, .getBuiltinModelDataGeneratedAt, .getImageProviders => 0,
            else => 1,
        };
        try scope.put(exports, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, length, Adapter.call, &.{owner})));
    }
    inline for (.{ .{ "getModel", "getBuiltinModel" }, .{ "getModels", "getBuiltinModels" }, .{ "getProviders", "getBuiltinProviders" } }) |alias| try scope.put(exports, alias[0], try scope.get(exports, alias[1]));
    return c.JS_DupValue(engine.context, owner);
}
fn insertModel(scope: *Scope, owner: c.JSValue, model: c.JSValue) !void {
    const kind = try scope.get(model, "type");
    const table = try scope.own(try js.getKey(scope.engine, owner, kind));
    const provider = try scope.get(model, "provider");
    const target = try scope.own(try js.getKey(scope.engine, table, provider));
    if (!c.JS_IsObject(target)) return error.InvalidCanonicalBuiltinCatalogProvider;
    try property(scope, target, try scope.get(model, "id"), model);
}
pub fn bindings(engine: *em.Engine) !c.JSValue {
    if (engine.native_ai_catalog_values) |cached| return c.JS_DupValue(engine.context, cached);
    const result = try build(engine);
    engine.native_ai_catalog_values = c.JS_DupValue(engine.context, result);
    return result;
}
pub fn namespace(engine: *em.Engine) !c.JSValue {
    const owner = try bindings(engine);
    defer engine.freeValue(owner);
    return js.get(engine, owner, "namespace");
}
pub fn providerChatCatalog(engine: *em.Engine, provider: c.JSValue) !c.JSValue {
    const owner = try bindings(engine);
    defer engine.freeValue(owner);
    const table = try js.get(engine, owner, "chat");
    defer engine.freeValue(table);
    return js.getKey(engine, table, provider);
}
pub fn providerImageCatalog(engine: *em.Engine, provider: c.JSValue) !c.JSValue {
    const owner = try bindings(engine);
    defer engine.freeValue(owner);
    const table = try js.get(engine, owner, "image");
    defer engine.freeValue(table);
    return js.getKey(engine, table, provider);
}
pub fn providerClassifierCatalog(engine: *em.Engine, provider: c.JSValue) !c.JSValue {
    const owner = try bindings(engine);
    defer engine.freeValue(owner);
    const table = try js.get(engine, owner, "classifier");
    defer engine.freeValue(table);
    return js.getKey(engine, table, provider);
}
