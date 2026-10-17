//! Actual AI imports consumed by the coding-agent1.3 SDK assembly.
//! This private graph is not the full public pi-ai namespace or a selection.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const cache_key = "pi-private:sdk-ai-imports";

fn copy(s: *Scope, target: c.JSValue, namespace: c.JSValue, comptime names: anytype) !void {
    inline for (names) |name| try s.put(target, name, try s.get(namespace, name));
}

/// Owned graph retaining real canonical module values. No caller-supplied
/// ModelsError, provider factory, compat registry or completion substitute.
pub fn create(engine: *v.em.Engine) !c.JSValue {
    if (engine.native_module_values.get(cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const models = try s.own(try @import("native_ai_models_namespace.zig").create(engine));
    const operations = try s.own(try @import("native_ai_models_namespace.zig").operations(engine));
    const apis = try s.own(try @import("native_ai_builtin_apis.zig").create(engine));
    const factories = try s.own(try @import("native_ai_provider_factories.zig").create(engine, apis));
    // The actual compat body registers its ten API instances before calling
    // this exact providers/all builtinModels binding, as Source compat.ts does.
    const compat = try s.own(try @import("native_ai_compat.zig").namespace(engine, try s.get(factories, "builtinModels")));
    const lazy = try s.own(try @import("native_ai_lazy_api.zig").namespace(engine));
    const transcript = try s.own(try @import("native_ai_transcript_context.zig").exports(engine));
    const ai = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)));
    try copy(&s, ai, models, .{ "createModels", "createProvider", "ModelsError", "getModelType", "isModelType", "clampThinkingLevel" });
    try copy(&s, ai, operations, .{ "assertChatModel", "assertImageModel", "assertClassifierModel", "assertClassifierInputSupported", "imageErrorResult", "classifierErrorResult" });
    try copy(&s, ai, lazy, .{"lazyStream"});
    try copy(&s, ai, transcript, .{"normalizeContext"});
    const graph = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)));
    try s.put(graph, "ai", ai);
    try s.put(graph, "compat", compat);
    try s.put(graph, "providerFactories", factories);
    try s.put(graph, "models", models);
    try s.put(graph, "modelOperations", operations);
    try s.put(graph, "apis", apis);
    try s.put(graph, "transcript", transcript);
    const retained = c.JS_DupValue(engine.context, graph);
    engine.native_module_values.put(engine.gpa, cache_key, retained) catch |err| {
        engine.freeValue(retained);
        return err;
    };
    return c.JS_DupValue(engine.context, graph);
}
