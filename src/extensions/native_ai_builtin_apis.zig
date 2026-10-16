//! Actual fourteen builtin API constructors over their native implementation
//! modules. Each constructor creates Source's fresh lazy wrapper; each module
//! initialization promise is retained once per Engine, including rejections.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const lazy = @import("native_ai_lazy_api.zig");
pub const Kind = enum {
    anthropicMessagesApi,
    openAICompletionsApi,
    openAIResponsesApi,
    openAICodexResponsesApi,
    azureOpenAIResponsesApi,
    googleGenerativeAIApi,
    googleVertexApi,
    mistralConversationsApi,
    bedrockConverseStreamApi,
    piMessagesApi,
    openAIDecisionsApi,
    typesafeSystemOneApi,
    cloudflareWorkersAISystemOneApi,
    openrouterImagesApi,
};
pub const chat_api_ids = [_][]const u8{ "anthropic-messages", "openai-completions", "openai-responses", "openai-codex-responses", "azure-openai-responses", "google-generative-ai", "google-vertex", "mistral-conversations", "bedrock-converse-stream", "pi-messages" };
fn raw(engine: *v.em.Engine, comptime kind: Kind) !c.JSValue {
    return switch (kind) {
        .anthropicMessagesApi => @import("native_ai_anthropic_factory.zig").create(engine),
        .openAICompletionsApi => @import("native_ai_openai_factory.zig").create(engine),
        .openAIResponsesApi => @import("native_ai_responses_factory.zig").create(engine),
        .openAICodexResponsesApi => @import("native_ai_responses_factory.zig").createMode(engine, .codex),
        .azureOpenAIResponsesApi => @import("native_ai_responses_factory.zig").createMode(engine, .azure),
        .googleGenerativeAIApi => @import("native_ai_google_mistral_factory.zig").create(engine, .google),
        .googleVertexApi => @import("native_ai_google_mistral_factory.zig").create(engine, .vertex),
        .mistralConversationsApi => @import("native_ai_google_mistral_factory.zig").create(engine, .mistral),
        .bedrockConverseStreamApi => @import("native_ai_bedrock_factory.zig").create(engine),
        .piMessagesApi => @import("native_ai_pi_messages_factory.zig").create(engine),
        .openAIDecisionsApi => @import("native_ai_classifier_factory.zig").create(engine, .decisions),
        .typesafeSystemOneApi => @import("native_ai_classifier_factory.zig").create(engine, .typesafe),
        .cloudflareWorkersAISystemOneApi => @import("native_ai_classifier_factory.zig").create(engine, .cloudflare),
        .openrouterImagesApi => @import("native_ai_images_factory.zig").create(engine),
    };
}
fn modules(engine: *v.em.Engine) !c.JSValue {
    if (engine.native_ai_builtin_modules) |cached| return c.JS_DupValue(engine.context, cached);
    const result = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
    engine.native_ai_builtin_modules = c.JS_DupValue(engine.context, result);
    return result;
}
fn load(engine: *v.em.Engine, comptime kind: Kind) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const cache = try scope.own(try modules(engine));
    const previous = try scope.get(cache, @tagName(kind));
    if (!c.JS_IsUndefined(previous)) return c.JS_DupValue(engine.context, previous);
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try scope.put(cache, @tagName(kind), pending.promise);
    const implementation = raw(engine, kind) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    defer engine.freeValue(implementation);
    try flow.settle(engine, pending.owner, false, implementation);
    return pending.promise;
}
pub fn api(engine: *v.em.Engine, comptime kind: Kind) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const Loader = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return load(host, kind);
        }
    };
    const loader = try scope.own(try functions.createArrow(engine, "", 0, Loader.call, &.{}));
    if (@intFromEnum(kind) < chat_api_ids.len) return lazy.create(engine, loader, c.pi_js_undefined());
    const output = try scope.object();
    const method = if (kind == .openrouterImagesApi) "generateImages" else "classify";
    try scope.put(output, method, try scope.own(try lazy.asyncOperation(engine, loader, method)));
    return c.JS_DupValue(engine.context, output);
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    if (engine.native_ai_builtin_apis) |cached| return c.JS_DupValue(engine.context, cached);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const output = try scope.object();
    inline for (@typeInfo(Kind).@"enum".fields) |field| {
        const kind: Kind = @enumFromInt(field.value);
        const Constructor = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                return api(host, kind);
            }
        };
        try scope.put(output, field.name, try scope.own(try functions.createArrow(engine, field.name, 0, Constructor.call, &.{})));
    }
    engine.native_ai_builtin_apis = c.JS_DupValue(engine.context, output);
    return c.JS_DupValue(engine.context, output);
}
