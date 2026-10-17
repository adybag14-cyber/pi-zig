//! Prepared actual configuration control. No build registration or fake imports.
const std = @import("std");
const config = @import("config.zig");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const configuration = @import("extensions/native_sdk_configuration_production.zig");

/// Caller must supply actual native process/filesystem/path/OS/URL namespaces,
/// a real config module URL and physical target package metadata. In particular
/// no successful readFileSync shim or hard-coded configuration VERSION is used.
pub fn verifyActualNativeConfiguration(engine: *em.Engine, actual: configuration.Inputs) !void {
    var inputs = actual;
    inputs.user_agent_runtime = .native_zig;
    const namespace = try configuration.create(engine, inputs);
    defer engine.freeValue(namespace);
    const version = try js.get(engine, namespace, "VERSION");
    defer engine.freeValue(version);
    const header = try js.invoke(engine, namespace, "getPiUserAgent", &.{version});
    defer engine.freeValue(header);
    var version_len: usize = 0;
    const version_bytes = em.c.JS_ToCStringLen(engine.context, &version_len, version) orelse return js.capture(engine);
    defer em.c.JS_FreeCString(engine.context, version_bytes);
    const expected = try config.nativeUserAgent(std.testing.allocator, version_bytes[0..version_len]);
    defer std.testing.allocator.free(expected);
    const expected_value = try engine.checked(em.c.JS_NewStringLen(engine.context, expected.ptr, expected.len));
    defer engine.freeValue(expected_value);
    try std.testing.expect(em.c.JS_IsStrictEqual(engine.context, expected_value, header));
    const units = [_]u16{ 0xd800, 0, 0xdc00 };
    const unusual_version = try engine.checked(em.c.JS_NewStringUTF16(engine.context, &units, units.len));
    defer engine.freeValue(unusual_version);
    const unusual_header = try js.invoke(engine, namespace, "getPiUserAgent", &.{unusual_version});
    defer engine.freeValue(unusual_header);
    for (units, 0..) |unit, index| {
        const code = try js.invoke(engine, unusual_header, "charCodeAt", &.{em.c.JS_NewUint32(engine.context, @intCast(3 + index))});
        defer engine.freeValue(code);
        var actual_unit: u32 = undefined;
        if (em.c.JS_ToUint32(engine.context, &actual_unit, code) < 0) return js.capture(engine);
        try std.testing.expectEqual(@as(u32, unit), actual_unit);
    }
    // Native header dispatch must not poison the original Source-profile cache.
    inputs.user_agent_runtime = .source;
    const source_namespace = try configuration.create(engine, inputs);
    defer engine.freeValue(source_namespace);
    try std.testing.expect(!em.c.JS_IsStrictEqual(engine.context, namespace, source_namespace));
    const again = try configuration.create(engine, actualWithNativeProfile(actual));
    defer engine.freeValue(again);
    try std.testing.expect(em.c.JS_IsStrictEqual(engine.context, namespace, again));
}
fn actualWithNativeProfile(actual: configuration.Inputs) configuration.Inputs {
    var inputs = actual;
    inputs.user_agent_runtime = .native_zig;
    return inputs;
}
