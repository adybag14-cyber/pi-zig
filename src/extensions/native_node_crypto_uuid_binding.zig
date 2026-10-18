//! The actual node:crypto randomUUID binding consumed without options by
//! c268 session-manager. It shares secure generation with WebCrypto and never
//! consults a mutable global crypto object. This is a private named binding.
const v = @import("native_public_values.zig");
const uuid = @import("native_secure_uuid.zig");
const c = v.c;
const key = "\x00sdk-node-crypto-randomUUID-no-options";
pub fn create(engine: *v.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |cached| return c.JS_DupValue(engine.context, cached);
    var s: v.Scope = .{ .engine = engine };
    const candidate = try v.owned.finishValue(&s, createBody(&s));
    if (engine.native_module_values.get(key)) |cached| {
        var completion = v.owned.Completion.initValue(engine, c.JS_DupValue(engine.context, cached));
        completion.release(candidate);
        return completion.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = v.owned.Completion.initVoid(engine, err); completion.release(candidate);
        try completion.finishVoid(); unreachable;
    };
    const result = c.JS_DupValue(engine.context, candidate);
    engine.native_module_values.putAssumeCapacity(key, candidate);
    return result;
}
fn createBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.ordinary(s, "randomUUID", 1, randomUUID, &.{}));
}
fn randomUUID(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const bytes = try uuid.generate(engine.native_io orelse return error.NativeCryptoIoRequired);
    var s: v.Scope = .{ .engine = engine };
    const result: anyerror!c.JSValue = if (v.text(&s, &bytes)) |value| v.duplicate(&s, value) else |err| err;
    return v.owned.finishValue(&s, result);
}
