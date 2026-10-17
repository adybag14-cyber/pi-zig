//! Source-only prospective roots for the exact independently reviewed SDK leaf.
const std = @import("std");
const em = @import("extensions/engine.zig");
const controls = @import("native_extension_graph0_binding_controls.zig");
const c = em.c;

test "actual Graph0 binding ordinary metadata and real queued module namespace cache" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.registerModule("C:/binding/dep.mjs", "await Promise.resolve();export const value=29;");
    const base = try engine.checked(c.JS_NewString(engine.context, "C:/binding/loader.js"));
    defer engine.freeValue(base);
    const specifier = try engine.checked(c.JS_NewString(engine.context, "C:/binding/dep.mjs"));
    defer engine.freeValue(specifier);
    try controls.verifyMetadataAndActualImport(engine, base, specifier);
}

test "actual Graph0 binding invalid basename is synchronous and uncoerced" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try controls.verifyNoBaseCoercion(engine);
}
