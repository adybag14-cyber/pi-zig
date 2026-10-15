//! Source WebCrypto PKCE body. Randomness/digest remain real native host APIs;
//! supplied guest crypto, encoder, iterator and string hooks stay observable.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
pub fn create(engine: *v.em.Engine) !c.JSValue {
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return generate(host);
        }
    };
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.object();
    try scope.put(exports, "generatePKCE", try scope.own(try @import("native_ai_auth_helpers.zig").asyncArrow(engine, "generatePKCE", 0, Adapter.call, &.{})));
    return c.JS_DupValue(engine.context, exports);
}
fn literal(scope: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try scope.text(pattern), try scope.text("g") };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn encode(scope: *Scope, bytes: c.JSValue) !c.JSValue {
    var binary = try scope.text("");
    var iterator = try v.iterator(scope, bytes);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |byte| {
        defer scope.engine.freeValue(byte);
        binary = try scope.concat(binary, try scope.invoke(try scope.global("String"), "fromCharCode", &.{byte}));
    }
    const b64 = try scope.call(try scope.global("btoa"), c.pi_js_undefined(), &.{binary});
    const first = try scope.invoke(b64, "replace", &.{ try literal(scope, "\\+"), try scope.text("-") });
    const second = try scope.invoke(first, "replace", &.{ try literal(scope, "/"), try scope.text("_") });
    return scope.invoke(second, "replace", &.{ try literal(scope, "="), try scope.text("") });
}
pub fn generate(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(&scope, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(scope: *Scope, owner: c.JSValue) !void {
    const bytes = try scope.own(try v.js.builtin(scope.engine, "Uint8Array", &.{c.JS_NewInt32(scope.engine.context, 32)}));
    _ = try scope.invoke(try scope.global("crypto"), "getRandomValues", &.{bytes});
    const verifier = try encode(scope, bytes);
    try scope.put(owner, "verifier", verifier);
    const encoder = try scope.own(try v.js.builtin(scope.engine, "TextEncoder", &.{}));
    const data = try scope.invoke(encoder, "encode", &.{verifier});
    const digest = try scope.invoke(try scope.get(try scope.global("crypto"), "subtle"), "digest", &.{ try scope.text("SHA-256"), data });
    return flow.wait(continued, scope.engine, owner, digest, 0);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    complete(&scope, owner, value) catch |err| try flow.rejectError(engine, owner, err);
}
fn complete(scope: *Scope, owner: c.JSValue, hash: c.JSValue) !void {
    const bytes = try scope.own(try v.js.builtin(scope.engine, "Uint8Array", &.{hash}));
    const challenge = try encode(scope, bytes);
    const result = try scope.object();
    try scope.put(result, "verifier", try scope.get(owner, "verifier"));
    try scope.put(result, "challenge", challenge);
    return flow.settle(scope.engine, owner, false, result);
}
