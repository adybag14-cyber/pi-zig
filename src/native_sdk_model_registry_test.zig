const std = @import("std");
const sdk = @import("extensions/native_sdk.zig");
const bridge = @import("extensions/native_sdk_model_bridge.zig");
const engine_mod = @import("extensions/engine.zig");
const c = engine_mod.c;
const Input = struct { schemaVersion: u32, sourceCommit: []const u8, inputSha256: []const u8, input: []const u8 };
fn induced(gpa: std.mem.Allocator, probe: bool) !void {
    if (!probe) return;
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    if (failing.has_induced_failure) return error.OutOfMemory;
}
fn evaluate(engine: *engine_mod.Engine, source: []const u8, name: [:0]const u8) !void {
    const evaluation = try engine.evalModule(source, name);
    defer engine.freeValue(evaluation);
    const settled = try engine.awaitValue(evaluation);
    engine.freeValue(settled);
}
fn equal(expected: std.json.Value, actual: std.json.Value) anyerror!void {
    try std.testing.expectEqual(@as(std.meta.Tag(std.json.Value), expected), @as(std.meta.Tag(std.json.Value), actual));
    switch (expected) {
        .object => |object| {
            try std.testing.expectEqual(object.count(), actual.object.count());
            var entries = object.iterator();
            while (entries.next()) |entry| try equal(entry.value_ptr.*, actual.object.get(entry.key_ptr.*) orelse return error.MissingSDKBridgeField);
        },
        .array => |array| {
            try std.testing.expectEqual(array.items.len, actual.array.items.len);
            for (array.items, actual.array.items) |a, b| try equal(a, b);
        },
        .string => |text| try std.testing.expectEqualStrings(text, actual.string),
        .integer => |value| try std.testing.expectEqual(value, actual.integer),
        .float => |value| try std.testing.expectEqual(value, actual.float),
        .bool => |value| try std.testing.expectEqual(value, actual.bool),
        .null => {},
        else => return error.InvalidSDKBridgeValue,
    }
}
fn exercise(gpa: std.mem.Allocator, directory: []const u8, probe: bool) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PI_AGENT_DIR", directory);
    try environment.put("HOME", directory);
    try environment.put("USERPROFILE", directory);
    try environment.put("PI_OFFLINE", "1");
    try environment.put("REGISTRY_FIXTURE", "fixture-env");
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{ "pi-sdk-test", "session-lease.mjs" });
    try @import("extensions/native_stream.zig").install(engine);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("@earendil-works/pi-coding-agent", exports);
    var input = try std.json.parseFromSlice(Input, gpa, @embedFile("extensions/fixtures/sdk-model-registry-6fb2e78.input.json"), .{});
    defer input.deinit();
    try std.testing.expectEqual(@as(u32, 1), input.value.schemaVersion);
    try std.testing.expectEqualStrings("6fb2e7815167e6b19006fc526d1a5d0f5f998787", input.value.sourceCommit);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input.value.input, &hash, .{});
    try std.testing.expectEqualStrings(&std.fmt.bytesToHex(hash, .lower), input.value.inputSha256);
    try evaluate(engine, input.value.input, "sdk-model-registry-source.mjs");
    try induced(gpa, probe);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const observed = try sdk.get(engine, global, "registryObserved");
    defer engine.freeValue(observed);
    const raw = try engine.stringify(observed);
    defer gpa.free(raw);
    var actual = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer actual.deinit();
    var expected = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/sdk-model-registry-6fb2e78.json"), .{});
    defer expected.deinit();
    equal(expected.value, actual.value) catch |err| {
        std.debug.print("registry actual {s}\n", .{raw});
        return err;
    };
    const session = try sdk.get(engine, global, "leaseSessionB");
    defer engine.freeValue(session);
    const owner = try sdk.state(engine, session);
    const rooted = try sdk.sessionDataSessionValue(engine, owner.data);
    defer engine.freeValue(rooted);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, session, rooted));
    const facade = try sdk.get(engine, owner.data, "modelRegistry");
    defer engine.freeValue(facade);
    const lease = try sdk.modelRegistryLease(engine, facade);
    const session_lease = try sdk.sessionModelLease(owner);
    try std.testing.expect(lease.generation != session_lease.generation);
    const mutation = try engine.eval("WeakRef.prototype.deref=function(){throw Error('mutable deref invoked')};globalThis.WeakRef=function(){throw Error('mutable constructor invoked')}", "intrinsic-tamper.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(mutation);
    const runtime = try bridge.borrowRuntime(engine, lease);
    defer engine.freeValue(runtime);
    const original = try sdk.get(engine, owner.data, "modelRuntime");
    defer engine.freeValue(original);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, runtime, original));
    const another = try sdk.newModelRegistry(engine, original);
    defer engine.freeValue(another);
    _ = try sdk.modelRegistryLease(engine, another);
    const disposed = try sdk.invoke(engine, session, "dispose", &.{});
    engine.freeValue(disposed);
    const retained = try bridge.borrowRuntime(engine, lease);
    defer engine.freeValue(retained);
    const collectible = try sdk.newModelRegistry(engine, original);
    const collectible_lease = try sdk.modelRegistryLease(engine, collectible);
    engine.freeValue(collectible);
    c.JS_RunGC(engine.runtime);
    const unexpected = bridge.borrowRuntime(engine, collectible_lease) catch |err| {
        if (err == error.OutOfMemory or err == error.JavaScriptException) return err;
        try std.testing.expectEqual(error.RetiredNativeSDKModelLease, err);
        try induced(gpa, probe);
        return;
    };
    engine.freeValue(unexpected);
    return error.CollectedModelRegistryLeaseAccepted;
}
test "SDK model registry exact Source facade and independent owner leases" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &path);
    try exercise(std.testing.allocator, path[0..count], false);
}
test "SDK model registry every host allocation releases facade auth anchors and rooted sessions" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &path);
    const Probe = struct {
        fn run(gpa: std.mem.Allocator, directory: []const u8) !void {
            exercise(gpa, directory, true) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.OutOfMemory or err == error.JavaScriptException)) return error.OutOfMemory;
                return err;
            };
        }
    };
    try @import("test_support/sdk_allocation_shards.zig").check("model-registry", Probe.run, .{path[0..count]});
}
