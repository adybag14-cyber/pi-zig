//! Prepared C3-only roots. Not compiled/run; full profile needs real bootstrap.
const std = @import("std");
const em = @import("extensions/engine.zig");
const controls = @import("native_jiti_public_factory_controls.zig");
const c = em.c;
test "jiti nativeImport actual arrow captures physical base and queued Graph0 identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try engine.registerModule("C:/jiti-real/lib/dep.mjs", "await Promise.resolve();export const marker=73;");
    const base = try engine.checked(c.JS_NewString(engine.context, "C:/jiti-real/lib/jiti.mjs")); defer engine.freeValue(base);
    const relative = try engine.checked(c.JS_NewString(engine.context, "./dep.mjs")); defer engine.freeValue(relative);
    try controls.verifyCapturedQueue(engine, base, relative);
}
