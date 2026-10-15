//! Actual models.ts runtime exports over the existing native configurable core.
//! One lexical module instance retains error/store constructors and callbacks.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
pub fn create(engine: *v.em.Engine) !c.JSValue {
    if (engine.native_ai_models_namespace) |cached| return c.JS_DupValue(engine.context, cached);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const core = try s.object();
    try @import("native_models.zig").populateExports(engine, core);
    const module_exports = try s.object();
    try s.put(module_exports, "ModelsError", try s.get(core, "ModelsError"));
    inline for (.{ "createModels", "createProvider" }) |name| try s.put(module_exports, name, try s.get(core, name));
    const operation_exports = engine.native_ai_model_operations_namespace.?;
    inline for (.{ "getModelType", "isModelType" }) |name| try s.put(module_exports, name, try s.get(operation_exports, name));
    const Narrow = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            const model = if (args.len > 0) args[0] else c.pi_js_undefined();
            const api = if (args.len > 1) args[1] else c.pi_js_undefined();
            const raw = try local.get(model, "type");
            const kind = if (v.nullish(raw)) try local.text("chat") else raw;
            return c.JS_NewBool(host.context, (try v.eq(&local, kind, "chat")) and local.equal(try local.get(model, "api"), api));
        }
    };
    try s.put(module_exports, "hasApi", try s.own(try functions.create(engine, "hasApi", 2, Narrow.call, &.{})));
    try s.put(module_exports, "calculateCost", try s.own(try @import("native_ai_cost.zig").create(engine)));
    const utilities = try s.own(try @import("native_ai_model_values.zig").bindings(engine));
    inline for (.{ "getSupportedThinkingLevels", "clampThinkingLevel", "modelsAreEqual" }) |name| try s.put(module_exports, name, try s.get(utilities, name));
    engine.native_ai_models_namespace = c.JS_DupValue(engine.context, module_exports);
    return c.JS_DupValue(engine.context, module_exports);
}
pub fn operations(engine: *v.em.Engine) !c.JSValue {
    if (engine.native_ai_model_operations_namespace) |cached| return c.JS_DupValue(engine.context, cached);
    const initialized = try create(engine);
    defer engine.freeValue(initialized);
    return c.JS_DupValue(engine.context, engine.native_ai_model_operations_namespace.?);
}
