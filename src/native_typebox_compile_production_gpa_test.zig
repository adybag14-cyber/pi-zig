//! Selected host-GPA failures during genuine shared-graph Compile/Check.
//! Graph initialization is accounted for but not fault-injected; C malloc is unknown.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = js.c;
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const graph = try s.own(try @import("native_typebox_compile_production_test.zig").graph(engine));
    const type_namespace = try s.get(graph, "Type");
    const schema = try s.invoke(type_namespace, "Record", &.{
        try s.invoke(type_namespace, "String", &.{}),
        try s.invoke(type_namespace, "Number", &.{}),
    });
    const good = try s.object();
    try s.put(good, "alpha", c.JS_NewInt32(engine.context, 1));
    const bad = try s.object();
    try s.put(bad, "alpha", try s.text("invalid-number"));
    const state = try s.object();
    try s.put(state, "compiler", try s.get(graph, "Compiler"));
    try s.put(state, "schema", schema);
    try s.put(state, "good", good);
    try s.put(state, "bad", bad);
    try s.put(try s.own(c.JS_GetGlobalObject(engine.context)), "TypeBoxScopedAllocationCase", state);
    return engine;
}
fn exercise(engine: *em.Engine) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.global("TypeBoxScopedAllocationCase");
    const validator = try s.invoke(try s.get(state, "compiler"), "Compile", &.{try s.get(state, "schema")});
    const good = try s.invoke(validator, "Check", &.{try s.get(state, "good")});
    const bad = try s.invoke(validator, "Check", &.{try s.get(state, "bad")});
    try std.testing.expect(c.JS_IsBool(good) and c.JS_ToBool(engine.context, good) == 1);
    try std.testing.expect(c.JS_IsBool(bad) and c.JS_ToBool(engine.context, bad) == 0);
}
fn operation(engine: *em.Engine) !void {
    const generation = engine.native_allocation_generation;
    exercise(engine) catch |err| return engine.nativeAllocationError(err, generation);
    c.JS_RunGC(engine.runtime);
}
test "TypeBox scoped GPA actual shared graph Compile Check selected operation failures" {
    var measurement = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const measured_engine = try setup(measurement.allocator());
    const beginning = measurement.alloc_index;
    const baseline = operation(measured_engine);
    const allocations = measurement.alloc_index - beginning;
    measured_engine.deinit();
    try baseline;
    try std.testing.expect(allocations >= 5);
    try std.testing.expectEqual(measurement.allocated_bytes, measurement.freed_bytes);
    const offsets = [_]usize{ 0, allocations / 4, allocations / 2, allocations * 3 / 4, allocations - 1 };
    for (offsets) |offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try setup(failing.allocator());
        failing.fail_index = failing.alloc_index + offset;
        const result = operation(engine);
        engine.deinit();
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectError(error.OutOfMemory, result);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        std.debug.print("TYPEBOX_SCOPED_GPA_FAILURE offset={d}/{d} induced=true all_host_bytes_freed=true C_malloc_unknown=true\n", .{ offset, allocations });
    }
    std.debug.print("TYPEBOX_SCOPED_GPA_PASS selected=5 baseline=1 genuine_compile_check=true exhaustive_HOST_GPA=false C_malloc_unknown=true\n", .{});
}
