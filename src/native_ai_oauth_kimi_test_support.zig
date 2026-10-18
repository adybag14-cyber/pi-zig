//! Control setup for real Source modules and native OAuth/env owners.
const std = @import("std");
pub const x = @import("extensions/native_ai_auth_helper_values.zig");
pub const c = x.c;
pub const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
pub fn publish(engine: *x.em.Engine, name: [*:0]const u8, input: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, input));
}
pub fn run(engine: *x.em.Engine, source: []const u8) !void {
    const namespace = try engine.evalModule(source, "actual-kimi-env-caller.mjs");
    engine.freeValue(namespace);
}
pub fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
pub fn prepareEnv(engine: *x.em.Engine) !void {
    engine.native_io = std.testing.io;
    const native = try @import("extensions/native_provider_env.zig").create(engine);
    defer engine.freeValue(native);
    try publish(engine, "envNative", native);
    const source = try engine.evalModule(@embedFile("extensions/fixtures/provider-env-c268-source.mjs"), "actual-provider-env-c268.mjs");
    defer engine.freeValue(source);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    try publish(engine, "envSource", try scope.get(source, "getProviderEnvValue"));
    const hooks = try retirement.createNativeRetirementHooks(engine);
    defer engine.freeValue(hooks);
    try publish(engine, "oauthHooks", hooks);
}
pub fn prepareKimi(engine: *x.em.Engine) !void {
    try prepareEnv(engine);
    const sleep_source = try engine.evalModule(@embedFile("extensions/fixtures/ai-sleep-c268-source.mjs"), "actual-kimi-sleep-c268.mjs");
    defer engine.freeValue(sleep_source);
    const device_source = try engine.evalModule(@embedFile("extensions/fixtures/oauth-device-code-c268-source.mjs"), "actual-kimi-device-c268.mjs");
    defer engine.freeValue(device_source);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.object();
    try @import("extensions/native_js_values.zig").define(engine, dependencies, "getProviderEnvValue", c.JS_DupValue(engine.context, try scope.global("envSource")));
    try @import("extensions/native_js_values.zig").define(engine, dependencies, "sleep", c.JS_DupValue(engine.context, try scope.get(sleep_source, "sleep")));
    try @import("extensions/native_js_values.zig").define(engine, dependencies, "pollOAuthDeviceCodeFlow", c.JS_DupValue(engine.context, try scope.get(device_source, "pollOAuthDeviceCodeFlow")));
    try publish(engine, "__kimiSourceDependencies", dependencies);
    const source = try engine.evalModule(@embedFile("extensions/fixtures/oauth-kimi-c268-source.mjs"), "actual-kimi-c268.mjs");
    defer engine.freeValue(source);
    try publish(engine, "kimiSource", try scope.get(source, "kimiCodingOAuth"));
    const native = try @import("extensions/native_ai_oauth_kimi.zig").create(engine);
    defer engine.freeValue(native);
    try publish(engine, "kimiNative", native);
}
pub fn selectKimi(engine: *x.em.Engine, native: bool) !void {
    try run(engine, if (native) "globalThis.selectedKimi=kimiNative;" else "globalThis.selectedKimi=kimiSource;");
}
pub fn selectEnv(engine: *x.em.Engine, native: bool) !void {
    try run(engine, if (native) "globalThis.selectedEnv=envNative;" else "globalThis.selectedEnv=envSource;");
}
pub const refreshAmbient =
    \\globalThis.process={env:{},versions:{}};
    \\globalThis.URLSearchParams=function(){return {toString(){return "controlled-body"}}};
    \\globalThis.AbortSignal={timeout(){return {}},any(values){return values[1]}};
    \\globalThis.controlledSignal={aborted:false,throwIfAborted(){},addEventListener(){},removeEventListener(){}};
    \\globalThis.setTimeout=callback=>{Promise.resolve().then(callback);return 1};globalThis.clearTimeout=()=>{};
;
