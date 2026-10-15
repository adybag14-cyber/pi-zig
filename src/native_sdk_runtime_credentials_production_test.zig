//! Source-only RuntimeCredentials qualification entry. Reference bytes are
//! supplied only after genuine Source20 terminal success and complete posthash0.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn compareActual(engine: *em.Engine, reference_bytes: []const u8) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const root = try scope.own(c.JS_GetGlobalObject(engine.context));
    const api = try scope.object();
    try scope.put(api, "RuntimeCredentials", try scope.own(try @import("extensions/native_sdk_runtime_credentials_production.zig").constructor(engine)));
    try scope.put(root, "runtimeCredentialsAPI", api);
    const module = try engine.evalModule(@embedFile("extensions/fixtures/sdk-runtime-credentials-4954.input.txt"), "actual-runtime-credentials-source20.mjs");
    engine.freeValue(module);
    const reference = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, reference_bytes.ptr, reference_bytes.len, "actual-credentials-source20.json")));
    if (!scope.equal(try scope.get(reference, "cases"), c.JS_NewInt32(engine.context, 20))) return error.IncompleteRuntimeCredentialsSourceReference;
    const expected = try engine.stringify(try scope.get(reference, "rows"));
    defer engine.gpa.free(expected);
    const actual = try engine.stringify(try scope.get(root, "credentialRows"));
    defer engine.gpa.free(actual);
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("RuntimeCredentials Source20 mismatch\nexpected={s}\nactual={s}\n", .{ expected, actual });
        return error.RuntimeCredentialsSourceMismatch;
    }
}
pub fn pendingActualOwnership(engine: *em.Engine) !void {
    const ctor = try @import("extensions/native_sdk_runtime_credentials_production.zig").constructor(engine);
    defer engine.freeValue(ctor);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "CredentialOwnershipClass", ctor);
    const ready = try engine.evalModule(
        \\(()=>{const store={list(){return new Promise(resolve=>{globalThis.credentialOwnershipRelease=resolve})}},r=new CredentialOwnershipClass(store);r.setRuntimeApiKey('owned','key');globalThis.credentialOwnershipWeak=new WeakRef(r);globalThis.credentialOwnershipPending=r.list()})();export const ready=true;
    , "credential-ownership-ready.mjs");
    engine.freeValue(ready);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("credentialOwnershipWeak.deref()!==undefined", "credential-ownership-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(retained);
    try std.testing.expect(c.JS_ToBool(engine.context, retained) == 1);
    engine.finishJob();
    const complete = try engine.evalModule(
        \\credentialOwnershipRelease([]);const result=await credentialOwnershipPending;if(result.length!==1||result[0].providerId!=='owned')throw Error('Actual credential pending graph lost');delete globalThis.credentialOwnershipPending;delete globalThis.credentialOwnershipRelease;export const complete=true;
    , "credential-ownership-complete.mjs");
    engine.freeValue(complete);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const released = try engine.eval("credentialOwnershipWeak.deref()===undefined", "credential-ownership-released.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(released);
    try std.testing.expect(c.JS_ToBool(engine.context, released) == 1);
}

test "native actual RuntimeCredentials class agrees with genuine latest Source20" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try compareActual(engine, @embedFile("extensions/fixtures/sdk-runtime-credentials-4954.json"));
}
test "native actual RuntimeCredentials pending list retains and releases its receiver graph" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try pendingActualOwnership(engine);
}
