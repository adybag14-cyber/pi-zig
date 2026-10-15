//! Actual static-create composition entry; the completed ordinary runtime class
//! and collaborator namespaces must be supplied by their production assemblers.
const std = @import("std");
const em = @import("extensions/engine.zig");
const create = @import("extensions/native_sdk_model_runtime_create_production.zig");
const c = em.c;
pub fn installActual(engine: *em.Engine, runtime_class: c.JSValue, actual_imports: c.JSValue) !void {
    try create.install(engine, runtime_class, actual_imports);
}
test "actual ModelRuntime create requires the real runtime class rather than synthesizing a facade" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try std.testing.expectError(error.RequiredActualModelRuntimeConstructor, create.install(engine, c.pi_js_undefined(), c.pi_js_undefined()));
}
