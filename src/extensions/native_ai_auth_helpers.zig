//! Actual auth/helpers.ts factories use genuine native AsyncFunction bodies.
//! defaultProviderAuthContextAt also uses the actual queued import operation.
//! The old no-URL file context and public asyncArrow remain legacy/unqualified.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const bodies = @import("native_ai_auth_helper_bodies.zig");
const x = @import("native_ai_auth_helper_values.zig");
const Stage = enum(c_int) { file_module, file_os, file_access };

/// Legacy branding adapter retained unchanged for external OAuth/provider
/// consumers. Their distinct Source Await bodies require separate migrations.
pub fn asyncArrow(engine: *v.em.Engine, name: [*:0]const u8, length: c_int, callback: functions.Callback, roots: []const c.JSValue) !c.JSValue {
    const value = try functions.createArrow(engine, name, length, callback, roots);
    errdefer engine.freeValue(value);
    const prototype = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(prototype);
    if (c.JS_SetPrototype(engine.context, value, prototype) < 0) return v.js.capture(engine);
    return value;
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: v.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var scope: Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &scope };
    return x.finishInvocation(engine, &invocation, x.owned.finishValue(&scope, createBody(&o)));
}
fn createBody(o: *x.Ops) !c.JSValue {
    const exports = try o.object();
    try o.put(exports, "envApiKeyAuth", try o.own(try functions.create(o.s.engine, "envApiKeyAuth", 2, bodies.envFactory, &.{})));
    try o.put(exports, "lazyOAuth", try o.own(try functions.create(o.s.engine, "lazyOAuth", 1, bodies.lazyFactory, &.{})));
    return c.JS_DupValue(o.s.engine.context, exports);
}
pub fn envApiKeyAuth(engine: *v.em.Engine, name: c.JSValue, env_vars: c.JSValue) !c.JSValue {
    return bodies.envFactory(engine, c.pi_js_undefined(), &.{ name, env_vars }, &.{});
}
pub fn lazyOAuth(engine: *v.em.Engine, input: c.JSValue) !c.JSValue {
    return bodies.lazyFactory(engine, c.pi_js_undefined(), &.{input}, &.{});
}
/// Complete Source context route. The AI module owner must supply the real
/// physical auth/context.ts URL; Graph0 admission/qualification is external.
pub fn defaultProviderAuthContextAt(engine: *v.em.Engine, physical_auth_context_url: c.JSValue) !c.JSValue {
    return bodies.contextAt(engine, physical_auth_context_url);
}
/// Compatibility route pending actual AI module-owner URL wiring. env is
/// genuine zero-Await AF; fileExists retains its explicitly legacy transport.
pub fn defaultProviderAuthContext(engine: *v.em.Engine) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: v.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var scope: Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &scope };
    return x.finishInvocation(engine, &invocation, x.owned.finishValue(&scope, defaultContextBody(&o)));
}
fn defaultContextBody(o: *x.Ops) !c.JSValue {
    const result = try o.object();
    try o.put(result, "env", try o.own(try x.af.create(o.s.engine, "env", 1, bodies.contextEnv, &.{})));
    try o.put(result, "fileExists", try o.own(try asyncArrow(o.s.engine, "fileExists", 1, fileExists, &.{})));
    return c.JS_DupValue(o.s.engine.context, result);
}

// Preserved legacy fileExists only. No shared caller silently opts into the
// additive physical-URL route or receives a transferred qualification claim.
fn fileExists(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const generation = engine.native_allocation_generation;
    startFileExists(&scope, pending.owner, if (args.len > 0) args[0] else c.pi_js_undefined()) catch |err| {
        try @import("native_ai_partial_json.zig").discard(engine, err, generation);
        try flow.settle(engine, pending.owner, false, c.pi_js_bool(engine.context, 0));
    };
    return pending.promise;
}
fn startFileExists(scope: *Scope, owner: c.JSValue, path: c.JSValue) !void {
    try scope.put(owner, "path", path);
    const module = scope.engine.native_module_values.get("node:fs/promises") orelse return error.NativeAuthFilesystemUnavailable;
    return flow.wait(continued, scope.engine, owner, module, @intFromEnum(Stage.file_module));
}
fn osModule(scope: *Scope) !c.JSValue {
    if (scope.engine.native_module_values.get("node:os")) |module| return module;
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return @import("native_home.zig").get(engine); }
    };
    const module = try scope.object();
    try scope.put(module, "homedir", try scope.own(try functions.create(scope.engine, "homedir", 0, Adapter.call, &.{})));
    return module;
}
fn accessFile(scope: *Scope, owner: c.JSValue, path: c.JSValue) !void {
    return flow.wait(continued, scope.engine, owner, try scope.invoke(try scope.get(owner, "fs"), "access", &.{path}), @intFromEnum(Stage.file_access));
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (rejected) return flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
    const generation = engine.native_allocation_generation;
    advance(&scope, owner, value, @enumFromInt(raw)) catch |err| {
        try @import("native_ai_partial_json.zig").discard(engine, err, generation);
        return flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
    };
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .file_module => {
            try scope.put(owner, "fs", value); const path = try scope.get(owner, "path");
            if (scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("~")}))) return flow.wait(continued, scope.engine, owner, try osModule(scope), @intFromEnum(Stage.file_os));
            return accessFile(scope, owner, path);
        },
        .file_os => return accessFile(scope, owner, try scope.concat(try scope.invoke(value, "homedir", &.{}), try scope.invoke(try scope.get(owner, "path"), "slice", &.{c.JS_NewInt32(scope.engine.context, 1)}))),
        .file_access => return flow.settle(scope.engine, owner, false, c.pi_js_bool(scope.engine.context, 1)),
    }
}
