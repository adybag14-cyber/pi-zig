//! Genuine-input owner profiles. These are callable profiles, not discovered
//! tests or fake Completed values; Root must supply its real bound frontend,
//! loader and physical config inputs and qualify the exact dependency union.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const js = @import("extensions/native_js_values.zig");
const actual = @import("extensions/native_sdk_application_owner.zig");
const owned = @import("extensions/native_sdk_owned_completion.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;

fn get(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return owned.ownRoot(s, try @import("extensions/native_agent_af_values.zig").guard(s.engine, generation, js.get(s.engine, object, name)));
}

/// Executes the actual aggregate owner, real AuthStorage.inMemory constructor
/// and real completed factory export reads. No child process is substituted.
pub fn verifyActualOwner(engine: *em.Engine, inputs: actual.Inputs) !void {
    var owner = try actual.create(engine, inputs);
    var scope: Scope = .{ .engine = engine };
    var completion = owned.Completion.initVoid(engine, ownerBody(&owner, &scope));
    completion.releaseScope(&scope);
    owner.retireInto(&completion);
    return completion.finishVoid();
}
fn ownerBody(owner: *actual.Owner, s: *Scope) !void {
    const factory = try owned.ownRoot(s, try owner.factoryExports());
    inline for (.{ "createAgentSession", "createAgentSessionServices", "createAgentSessionFromServices", "createAgentSessionRuntime" }) |name| {
        const function = try get(s, factory, name);
        try std.testing.expect(c.JS_IsAsyncFunction(function));
        try std.testing.expect(!c.JS_IsConstructor(s.engine.context, function));
    }
    const namespace = try owned.ownRoot(s, try owner.authStorage());
    const core = if (owner.auth) |*value| value else return error.RequiredActualAuthOwner;
    const memory = try owned.ownRoot(s, try core.inMemory());
    const auth_constructor = try get(s, namespace, "AuthStorage");
    const instance = c.JS_IsInstanceOf(s.engine.context, memory, auth_constructor);
    if (instance < 0) return js.capture(s.engine);
    try std.testing.expect(instance != 0);
    const runtime = core.runtime_imports;
    const actual_process = try get(s, runtime, "process");
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, actual_process, try owned.ownRoot(s, try js.global(s.engine, "process"))));
    const frontend = core.frontend orelse return error.RequiredActualFrontendOwner;
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, frontend.output_guard.is_stdout_taken_over, frontend.process_imports.is_stdout_taken_over));
}

/// Executes the genuine factory/session path with real user options (cwd,
/// managers, models/resources as the Source factory requires). The returned
/// result remains owned by the qualification caller; no expected fixture or
/// preconstructed session is used to bypass factory work.
pub fn createActualSession(engine: *em.Engine, inputs: actual.Inputs, user_options: c.JSValue) !c.JSValue {
    var owner = try actual.create(engine, inputs);
    var scope: Scope = .{ .engine = engine };
    var completion = owned.Completion.initValue(engine, sessionBody(&owner, &scope, user_options));
    completion.releaseScope(&scope);
    owner.retireInto(&completion);
    return completion.finishValue();
}
fn sessionBody(owner: *actual.Owner, s: *Scope, options: c.JSValue) !c.JSValue {
    const factory = try owned.ownRoot(s, try owner.factoryExports());
    const function = try get(s, factory, "createAgentSession");
    const generation = s.engine.native_allocation_generation;
    const pending = try owned.ownRoot(s, try @import("extensions/native_agent_af_values.zig").guard(s.engine, generation, js.call(s.engine, function, c.pi_js_undefined(), &.{options})));
    // This qualification host awaits the actual Source function result. It
    // neither inserts an Await into production code nor supplies a fake result.
    const result = try owned.ownRoot(s, try s.engine.awaitValue(pending));
    const session = try get(s, result, "session");
    const constructor = try get(s, factory, "AgentSession");
    const instance = c.JS_IsInstanceOf(s.engine.context, session, constructor);
    if (instance < 0) return js.capture(s.engine);
    try std.testing.expect(instance != 0);
    return c.JS_DupValue(s.engine.context, result);
}
