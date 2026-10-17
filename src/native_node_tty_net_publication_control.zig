//! Prepared actual canonical-net publication controls; not a TCP provider.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
pub fn preexisting(comptime ActualAssembly: type, engine: *v.em.Engine, actual: ActualAssembly.Inputs, legacy_bare_module: bool) !void {
    const record = try engine.defaultExports(actual.actual_net); defer engine.freeValue(record);
    try engine.registerValueModule("node:net", record);
    if (legacy_bare_module) try engine.registerValueModule("net", record) else try engine.registerBuiltinAlias("net", "node:net");
    const exports = try ActualAssembly.install(engine, actual); defer exports.deinit(engine);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, record, exports.net_exports));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, record, engine.native_module_values.get("node:net").?));
    if (legacy_bare_module) {
        try std.testing.expect(!engine.native_builtin_aliases.contains("net"));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, record, engine.native_module_values.get("net").?));
    } else try std.testing.expectEqualStrings("node:net", engine.native_builtin_aliases.get("net").?);
    const bare = (try engine.requireBuiltin("net")) orelse return error.MissingActualNet; defer engine.freeValue(bare);
    const prefixed = (try engine.requireBuiltin("node:net")) orelse return error.MissingActualNet; defer engine.freeValue(prefixed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, bare, actual.actual_net));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, bare, prefixed));
}
/// A genuine other builtin record is not relabeled/replaced as canonical net.
/// This is an explicit negative input, never a substitute positive namespace.
pub fn conflict(comptime ActualAssembly: type, engine: *v.em.Engine, actual: ActualAssembly.Inputs) !void {
    const genuine_events_record = engine.native_module_values.get("node:events") orelse return error.RequiredActualEvents;
    try engine.registerValueModule("node:net", genuine_events_record);
    const unexpected = ActualAssembly.create(engine, actual) catch |err| {
        try std.testing.expect(err == error.ActualTtyNetCarrierMismatch);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, genuine_events_record, engine.native_module_values.get("node:net").?));
        try std.testing.expect(!engine.native_builtin_aliases.contains("net"));
        return;
    };
    unexpected.deinit(engine); return error.ExpectedActualNetCarrierConflict;
}
