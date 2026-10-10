const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const group_mod = @import("extensions/native_group.zig");
const json = @import("mcp/protocol.zig").json;
const c = engine_mod.c;

fn emitInput(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return emitInputValue(engine, args[0..@intCast(argc)]) catch |err| sdk.fail(engine, err);
}
fn emitInputValue(engine: *engine_mod.Engine, args: []const c.JSValue) !c.JSValue {
    if (args.len < 4) return error.MissingInputArguments;
    const session = try sdk.state(engine, args[0]);
    const resources = try sdk.get(engine, session.data, "resourceLoader");
    defer engine.freeValue(resources);
    const payload = try sdk.object(engine);
    defer engine.freeValue(payload);
    inline for (.{ "text", "images", "source", "streamingBehavior" }, 1..) |name, index| try sdk.put(engine, payload, name, if (args.len > index) c.JS_DupValue(engine.context, args[index]) else c.pi_js_undefined());
    return @import("extensions/native_sdk_resources.zig").emitValue(engine, resources, session.data, "input", payload);
}
fn exercise(gpa: std.mem.Allocator, comptime capture: []const u8, allocation_probe: bool) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-input436-root");
    try root.installSchemas();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "sdkNativeInput", try engine.checked(c.JS_NewCFunction2(engine.context, emitInput, "sdkNativeInput", 5, c.JS_CFUNC_generic, 0)));
    const loaded = try engine.evalModule(@embedFile("extensions/fixtures/sdk-input-reducers-" ++ capture ++ ".txt"), "sdk-input436.mjs");
    defer engine.freeValue(loaded);
    const pending = try engine.eval("runSdkInputs((...args)=>sdkNativeInput(sdkInputSession,...args))", "sdk-input436-run.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(pending);
    const actual_value = try engine.awaitValue(pending);
    defer engine.freeValue(actual_value);
    if (allocation_probe) {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure) return error.OutOfMemory;
    }
    const raw = try engine.stringify(actual_value);
    defer gpa.free(raw);
    var actual = try json.Owned.parse(gpa, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/sdk-input-reducers-" ++ capture ++ ".json"));
    defer expected.deinit();
    if (!json.equal(expected.value, actual.value)) std.debug.print("SDK input436 actual={s}\n", .{raw});
    try std.testing.expect(json.equal(expected.value, actual.value));
    c.JS_RunGC(engine.runtime);
}
test "native SDK input reducers preserve Source transforms snapshots handled identity errors and stale contexts" {
    try exercise(std.testing.allocator, "436", false);
}
test "native SDK input reducers preserve repeated observable Source action getter lookups" {
    try exercise(std.testing.allocator, "437", false);
}
test "native SDK input reducers release every failed host allocation" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa, "437", true) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure) return error.OutOfMemory;
                return err;
            };
        }
    };
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try Probe.run(baseline.allocator());
    try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
    const count = baseline.alloc_index;
    std.debug.print("SDK_ALLOCATION_RANGE sdk-input-reducers 0/1 range=[0,{d}) total={d}\n", .{ count, count });
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
    std.debug.print("SDK_ALLOCATION_COMPLETE sdk-input-reducers 0/1 range=[0,{d}) total={d}\n", .{ count, count });
}
