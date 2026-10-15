//! Exact models.json schema composition through actual TypeBox/model schemas.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
fn t(scope: *Scope, types: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.invoke(types, name, args);
}
fn optional(scope: *Scope, types: c.JSValue, value: c.JSValue) !c.JSValue {
    return t(scope, types, "Optional", &.{value});
}
fn textType(scope: *Scope, types: c.JSValue) !c.JSValue {
    const options = try scope.object();
    try scope.put(options, "minLength", c.JS_NewInt32(scope.engine.context, 1));
    return t(scope, types, "String", &.{options});
}
fn record(scope: *Scope, types: c.JSValue, value: c.JSValue) !c.JSValue {
    return t(scope, types, "Record", &.{ try t(scope, types, "String", &.{}), value });
}
fn fields(scope: *Scope, imports: c.JSValue, types: c.JSValue, sampling: c.JSValue, by_level: c.JSValue, positive: c.JSValue, override: bool) !c.JSValue {
    const object = try scope.object();
    if (!override) try scope.put(object, "id", try textType(scope, types));
    try scope.put(object, "name", try optional(scope, types, try textType(scope, types)));
    if (!override) inline for (.{ "api", "baseUrl" }) |name| try scope.put(object, name, try optional(scope, types, try textType(scope, types)));
    try scope.put(object, "reasoning", try optional(scope, types, try t(scope, types, "Boolean", &.{})));
    try scope.put(object, "thinkingLevelMap", try optional(scope, types, try scope.get(imports, "ThinkingLevelMapSchema")));
    try scope.put(object, "input", try optional(scope, types, try t(scope, types, "Array", &.{try scope.get(imports, "ModelInputModalitySchema")})));
    try scope.put(object, "inputLimits", try optional(scope, types, try scope.get(imports, "ModelInputLimitsSchema")));
    const cost = try scope.get(imports, "ModelCostSchema");
    try scope.put(object, "cost", try optional(scope, types, if (override) try t(scope, types, "Partial", &.{cost}) else cost));
    try scope.put(object, "promptCache", try optional(scope, types, try scope.get(imports, "ModelPromptCacheSchema")));
    inline for (.{ "contextWindow", "maxTokens" }) |name| try scope.put(object, name, try optional(scope, types, positive));
    try scope.put(object, "samplingParams", try optional(scope, types, sampling));
    try scope.put(object, "samplingParamsByThinkingLevel", try optional(scope, types, by_level));
    try scope.put(object, "headers", try optional(scope, types, try record(scope, types, try t(scope, types, "String", &.{}))));
    try scope.put(object, "compat", try optional(scope, types, try scope.get(imports, "ProviderCompatSchema")));
    return t(scope, types, "Object", &.{object});
}
pub fn create(engine: *v.em.Engine, imports: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const types = try scope.get(imports, "Type");
    const sampling = try record(&scope, types, try t(&scope, types, "Unknown", &.{}));
    const levels = try scope.object();
    inline for (.{ "off", "minimal", "low", "medium", "high", "xhigh", "max" }) |name| try scope.put(levels, name, try optional(&scope, types, sampling));
    const by_level = try t(&scope, types, "Object", &.{levels});
    const options = try scope.object();
    try scope.put(options, "exclusiveMinimum", c.JS_NewInt32(engine.context, 0));
    const positive = try t(&scope, types, "Number", &.{options});
    const model = try fields(&scope, imports, types, sampling, by_level, positive, false);
    const model_override = try fields(&scope, imports, types, sampling, by_level, positive, true);
    const provider = try scope.object();
    inline for (.{ "name", "baseUrl", "apiKey", "api" }) |name| try scope.put(provider, name, try optional(&scope, types, try textType(&scope, types)));
    try scope.put(provider, "oauth", try optional(&scope, types, try t(&scope, types, "Literal", &.{try scope.text("radius")})));
    try scope.put(provider, "headers", try optional(&scope, types, try record(&scope, types, try t(&scope, types, "String", &.{}))));
    try scope.put(provider, "compat", try optional(&scope, types, try scope.get(imports, "ProviderCompatSchema")));
    try scope.put(provider, "authHeader", try optional(&scope, types, try t(&scope, types, "Boolean", &.{})));
    try scope.put(provider, "models", try optional(&scope, types, try t(&scope, types, "Array", &.{model})));
    try scope.put(provider, "modelOverrides", try optional(&scope, types, try record(&scope, types, model_override)));
    const root = try scope.object();
    try scope.put(root, "$schema", try optional(&scope, types, try t(&scope, types, "String", &.{})));
    try scope.put(root, "providers", try record(&scope, types, try t(&scope, types, "Object", &.{provider})));
    return c.JS_DupValue(engine.context, try t(&scope, types, "Object", &.{root}));
}
