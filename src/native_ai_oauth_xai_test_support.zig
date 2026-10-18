//! Real Source DeviceCode/xAI modules and native xAI test setup.
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
    const namespace = try engine.evalModule(source, "actual-xai-caller.mjs");
    engine.freeValue(namespace);
}
pub fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
pub fn prepareXai(engine: *x.em.Engine) !void {
    engine.native_io = std.testing.io;
    const hooks = try retirement.createNativeRetirementHooks(engine);
    defer engine.freeValue(hooks);
    try publish(engine, "oauthHooks", hooks);
    const device_source = try engine.evalModule(@embedFile("extensions/fixtures/oauth-device-code-c268-source.mjs"), "actual-xai-device-c268.mjs");
    defer engine.freeValue(device_source);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.object();
    try @import("extensions/native_js_values.zig").define(engine, dependencies, "pollOAuthDeviceCodeFlow", c.JS_DupValue(engine.context, try scope.get(device_source, "pollOAuthDeviceCodeFlow")));
    try publish(engine, "__xaiSourceDependencies", dependencies);
    const source = try engine.evalModule(@embedFile("extensions/fixtures/oauth-xai-c268-source.mjs"), "actual-xai-c268.mjs");
    defer engine.freeValue(source);
    try publish(engine, "xaiSource", try scope.get(source, "xaiOAuth"));
    const native = try @import("extensions/native_ai_oauth_xai.zig").create(engine);
    defer engine.freeValue(native);
    try publish(engine, "xaiNative", native);
}
pub fn selectXai(engine: *x.em.Engine, native: bool) !void {
    try run(engine, if (native) "globalThis.selectedXai=xaiNative;" else "globalThis.selectedXai=xaiSource;");
}
pub const requestAmbient =
    \\globalThis.URLSearchParams=function(){return {toString(){return "controlled-body"}}};
    \\globalThis.AbortSignal={timeout(){return {}},any(values){return values[1]}};
    \\globalThis.controlledSignal={aborted:false,throwIfAborted(){},addEventListener(){},removeEventListener(){}};
    \\globalThis.setTimeout=callback=>{Promise.resolve().then(callback);return 1};globalThis.clearTimeout=()=>{};
;
