//! Native module loader for the actual public auth/oauth/load.ts exports.
//! Registered bundled callbacks are real caller values. Default paths lazily
//! initialize actual native OAuth modules, retain their namespace/error promise,
//! and never substitute empty providers or host-language implementations.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const helpers = @import("native_ai_auth_helpers.zig");
pub const Kind = enum { anthropic, openaiCodex, openaiChatGPT, githubCopilot, openrouter, kimiCoding, meta, xai, radius };
const names = .{ "loadAnthropicOAuth", "loadOpenAICodexOAuth", "loadOpenAIChatGPTOAuth", "loadGitHubCopilotOAuth", "loadOpenRouterOAuth", "loadKimiCodingOAuth", "loadMetaOAuth", "loadXaiOAuth", "loadRadiusOAuth" };
const exports = .{ "anthropicOAuth", "openaiCodexOAuth", "openaiChatGPTOAuth", "githubCopilotOAuth", "openRouterOAuth", "kimiCodingOAuth", "metaOAuth", "xaiOAuth", "createRadiusOAuth" };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const catalog = try scope.own(try @import("native_ai_catalog_values.zig").providerChatCatalog(engine, try scope.text("github-copilot")));
    return createWithCatalog(engine, catalog);
}
pub fn createWithCatalog(engine: *v.em.Engine, github_models: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "bundledLoaders", c.pi_js_undefined());
    try scope.put(state, "modules", try scope.object());
    try scope.put(state, "githubModels", github_models);
    const namespace = try scope.object();
    const Register = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            try local.put(roots[0], "bundledLoaders", if (args.len > 0) args[0] else c.pi_js_undefined());
            return c.pi_js_undefined();
        }
    };
    try scope.put(namespace, "registerBundledOAuthFlowLoaders", try scope.own(try functions.create(engine, "registerBundledOAuthFlowLoaders", 1, Register.call, &.{state})));
    inline for (names, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return load(host, roots[0], @enumFromInt(index), if (args.len > 0) args[0] else c.pi_js_undefined());
            }
        };
        try scope.put(namespace, name, try scope.own(try helpers.asyncArrow(engine, name, if (index == 8) 1 else 0, Adapter.call, &.{state})));
    }
    return c.JS_DupValue(engine.context, namespace);
}
fn load(engine: *v.em.Engine, state: c.JSValue, kind: Kind, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, state);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startLoad(&scope, pending.owner, kind, options) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startLoad(scope: *Scope, owner: c.JSValue, kind: Kind, options: c.JSValue) !void {
    const state = try scope.get(owner, "agent");
    const bundled = try scope.get(state, "bundledLoaders");
    if (scope.truthy(bundled)) {
        const method = try scope.get(bundled, @tagName(kind));
        const result = if (kind == .radius) try scope.call(method, bundled, &.{options}) else try scope.call(method, bundled, &.{});
        // An async return adopts the actual loader result, including thenables.
        return flow.settle(scope.engine, owner, false, result);
    }
    try scope.put(owner, "kind", c.JS_NewInt32(scope.engine.context, @intCast(@intFromEnum(kind))));
    try scope.put(owner, "options", options);
    const modules = try scope.get(state, "modules");
    var promise = try scope.get(modules, @tagName(kind));
    if (c.JS_IsUndefined(promise)) {
        const module = try flow.create(scope.engine, state);
        defer scope.engine.freeValue(module.owner);
        promise = try scope.own(module.promise);
        try scope.put(module.owner, "kind", c.JS_NewInt32(scope.engine.context, @intCast(@intFromEnum(kind))));
        try scope.put(modules, @tagName(kind), promise);
        // Dynamic import evaluates its module asynchronously. Keep that boundary
        // and cache failed initialization exactly like a real module import.
        try flow.wait(imported, scope.engine, module.owner, c.pi_js_undefined(), 0);
    }
    return flow.wait(loaded, scope.engine, owner, promise, 0);
}
fn ownerKind(scope: *Scope, owner: c.JSValue) !Kind {
    var index: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &index, try scope.get(owner, "kind")) < 0) return v.js.capture(scope.engine);
    return @enumFromInt(index);
}
fn imported(engine: *v.em.Engine, owner: c.JSValue, _: c.JSValue, _: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    initialize(&scope, owner) catch |err| try flow.rejectError(engine, owner, err);
}
fn initialize(scope: *Scope, owner: c.JSValue) !void {
    const kind = try ownerKind(scope, owner);
    const namespace = try scope.object();
    const value = switch (kind) {
        .anthropic => try @import("native_ai_oauth_anthropic.zig").create(scope.engine),
        .openaiCodex => try @import("native_ai_oauth_codex.zig").create(scope.engine),
        .openaiChatGPT => try @import("native_ai_oauth_openai_chatgpt.zig").create(scope.engine),
        .githubCopilot => try @import("native_ai_oauth_copilot.zig").createWithCatalog(scope.engine, try scope.get(try scope.get(owner, "agent"), "githubModels")),
        .openrouter => try @import("native_ai_oauth_openrouter.zig").create(scope.engine),
        .kimiCoding => try @import("native_ai_oauth_kimi.zig").create(scope.engine),
        .meta => try @import("native_ai_oauth_meta.zig").create(scope.engine),
        .xai => try @import("native_ai_oauth_xai.zig").create(scope.engine),
        .radius => try @import("native_ai_oauth_radius.zig").factory(scope.engine),
    };
    _ = try scope.own(value);
    inline for (exports, 0..) |name, index| if (@intFromEnum(kind) == index) try scope.put(namespace, name, value);
    return flow.settle(scope.engine, owner, false, namespace);
}
fn loaded(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    completeLoad(&scope, owner, value) catch |err| try flow.rejectError(engine, owner, err);
}
fn completeLoad(scope: *Scope, owner: c.JSValue, namespace: c.JSValue) !void {
    const kind = try ownerKind(scope, owner);
    var value = c.pi_js_undefined();
    inline for (exports, 0..) |name, index| if (@intFromEnum(kind) == index) {
        value = try scope.get(namespace, name);
    };
    if (kind == .radius) value = try scope.call(value, namespace, &.{try scope.get(owner, "options")});
    return flow.settle(scope.engine, owner, false, value);
}
