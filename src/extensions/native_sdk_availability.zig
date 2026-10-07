//! Cached SDK availability, published on the VM owner thread. Native readers
//! receive owned bytes and never execute credential or provider callbacks.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;

pub const protocol = @import("native_sdk_availability_protocol.zig");
pub const Model = protocol.Model;
pub const Snapshot = protocol.Snapshot;
pub const fromJson = protocol.fromJson;

/// Borrowed until the next owner-thread publication. For cross-thread or
/// longer-lived consumers use copySnapshot; it contains no VM values.
pub fn snapshot(engine: *engine_mod.Engine, runtime: c.JSValue) !?*const Snapshot {
    const owner = try sdk.state(engine, runtime);
    if (owner.kind != .model_runtime) return error.InvalidNativeSDKReceiver;
    return if (owner.availability_snapshot) |*value| value else null;
}
pub fn copySnapshot(engine: *engine_mod.Engine, runtime: c.JSValue, gpa: std.mem.Allocator) !?Snapshot {
    const value = try snapshot(engine, runtime) orelse return null;
    return try value.copy(gpa);
}

pub fn getAvailable(engine: *engine_mod.Engine, runtime: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, runtime);
    const catalog = try sdk.get(engine, owner.data, "models");
    defer engine.freeValue(catalog);
    // A provider-specific query does not refresh the aggregate SDK snapshot.
    if (args.len > 0 and !c.JS_IsUndefined(args[0]) and !c.JS_IsNull(args[0])) return sdk.invoke(engine, catalog, "getAvailable", args);
    owner.availability_sequence = std.math.add(u64, owner.availability_sequence, 1) catch return error.NativeSDKRevisionOverflow;
    if (owner.availability_sequence > 9007199254740991) return error.NativeSDKRevisionOverflow;
    const sequence = owner.availability_sequence;
    const pending = try sdk.invoke(engine, catalog, "getAvailable", args);
    defer engine.freeValue(pending);
    var captured = [_]c.JSValue{ runtime, c.JS_NewFloat64(engine.context, @floatFromInt(sequence)) };
    const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, completed, "availabilityCompleted", 1, 0, 2, &captured));
    defer engine.freeValue(done);
    return sdk.invoke(engine, pending, "then", &.{done});
}
pub fn registrationRefresh(engine: *engine_mod.Engine, runtime: c.JSValue) !void {
    var captured = [_]c.JSValue{runtime};
    if (c.JS_EnqueueJob(engine.context, registrationJob, 1, &captured) < 0) return error.OutOfMemory;
}
fn registrationJob(context: ?*c.JSContext, _: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    // The local catalog refresh and the SDK availability pass are distinct
    // asynchronous phases, as in Models.refresh followed by ModelRuntime.refresh.
    if (c.JS_EnqueueJob(context, registrationAvailabilityJob, 1, args) < 0) return c.JS_ThrowOutOfMemory(context);
    return c.pi_js_undefined();
}
fn registrationAvailabilityJob(context: ?*c.JSContext, _: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return startRegistrationRefresh(engine, args[0]) catch |err| sdk.fail(engine, err);
}
fn startRegistrationRefresh(engine: *engine_mod.Engine, runtime: c.JSValue) !c.JSValue {
    const pending = try getAvailable(engine, runtime, &.{});
    defer engine.freeValue(pending);
    const rejected = try engine.checked(c.pi_js_function_magic(engine.context, ignoreRefreshError, "availabilityRefreshError", 1, 0));
    defer engine.freeValue(rejected);
    const observed = try sdk.invoke(engine, pending, "catch", &.{rejected});
    engine.freeValue(observed);
    return c.pi_js_undefined();
}
fn ignoreRefreshError(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn completed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, captured: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return complete(engine, captured[0], captured[1], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn complete(engine: *engine_mod.Engine, runtime: c.JSValue, serial: c.JSValue, rows: c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, runtime);
    var number: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &number, serial) < 0) return error.JavaScriptException;
    const sequence: u64 = @intFromFloat(number);
    if (sequence != owner.availability_sequence) return sdk.get(engine, owner.data, "available");
    const catalog = try sdk.get(engine, owner.data, "models");
    defer engine.freeValue(catalog);
    const all = try sdk.invoke(engine, catalog, "getModels", &.{});
    defer engine.freeValue(all);
    const all_json = try rowsJson(engine, all);
    defer engine.gpa.free(all_json);
    const available_json = try rowsJson(engine, rows);
    defer engine.gpa.free(available_json);
    const revision = if (owner.availability_snapshot) |old| std.math.add(u64, old.revision, 1) catch return error.NativeSDKRevisionOverflow else 1;
    var next = try fromJson(engine.gpa, revision, all_json, available_json);
    errdefer next.deinit();
    next.runtime_id = owner.runtime_id;
    const group: ?*@import("native_group.zig").Group = if (engine.native_sdk_extension_group) |pointer| @ptrCast(@alignCast(pointer)) else null;
    next.owner_generation = if (group) |value| value.renderers.owner_generation else 1;
    var group_copy: ?Snapshot = if (group) |value| try value.sdk_availability.prepare(engine.gpa, &next) else null;
    defer if (group_copy) |*value| value.deinit();
    // Identity projection may invoke user getters. A newer refresh wins even when
    // started reentrantly during DTO preparation.
    if (sequence != owner.availability_sequence) {
        next.deinit();
        return sdk.get(engine, owner.data, "available");
    }
    try sdk.put(engine, owner.data, "available", c.JS_DupValue(engine.context, rows));
    if (owner.availability_snapshot) |*old| old.deinit();
    owner.availability_snapshot = next;
    if (group_copy) |value| {
        group.?.sdk_availability.commit(value);
        group_copy = null;
    }
    return c.JS_DupValue(engine.context, rows);
}
fn rowsJson(engine: *engine_mod.Engine, rows: c.JSValue) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const count = try sdk.length(engine, rows);
    if (count > 65536) return error.NativeSDKModelLimit;
    const result = try allocator.alloc(Model, count);
    for (result, 0..) |*output, index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const provider = try sdk.get(engine, row, "provider");
        defer engine.freeValue(provider);
        const id = try sdk.get(engine, row, "id");
        defer engine.freeValue(id);
        if (!c.JS_IsString(provider) or !c.JS_IsString(id)) return error.NativeSDKInvalidModelIdentity;
        var provider_length: usize = 0;
        const provider_text = c.JS_ToCStringLen(engine.context, &provider_length, provider) orelse return error.JavaScriptException;
        defer c.JS_FreeCString(engine.context, provider_text);
        var id_length: usize = 0;
        const id_text = c.JS_ToCStringLen(engine.context, &id_length, id) orelse return error.JavaScriptException;
        defer c.JS_FreeCString(engine.context, id_text);
        output.* = .{ .provider = try allocator.dupe(u8, provider_text[0..provider_length]), .id = try allocator.dupe(u8, id_text[0..id_length]) };
    }
    // Serialize the owned identity projection, never user model toJSON hooks
    // or arbitrary metadata getters that the SDK availability pass does not use.
    return std.json.Stringify.valueAlloc(engine.gpa, result, .{});
}

test "availability DTO copies survive replacement and allocation failure" {
    const raw = "[{\"provider\":\"p\",\"id\":\"m\",\"name\":\"Model\"}]";
    var original = try fromJson(std.testing.allocator, 7, raw, raw);
    defer original.deinit();
    var owned = try original.copy(std.testing.allocator);
    defer owned.deinit();
    try std.testing.expectEqualStrings("m", owned.available[0].id);
    try std.testing.expectEqual(@as(u64, 7), owned.revision);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    var value = try fromJson(gpa, 1, "[{\"provider\":\"p\",\"id\":\"m\"}]", "[]");
    defer value.deinit();
    var copy = try value.copy(gpa);
    defer copy.deinit();
}

test "native availability copy outlives its VM and does not invoke model toJSON" {
    var owned: ?Snapshot = null;
    defer if (owned) |*value| value.deinit();
    {
        const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try @import("native_stream.zig").install(engine);
        const exports = try sdk.object(engine);
        defer engine.freeValue(exports);
        try sdk.install(engine, exports);
        try engine.registerValueModule("sdk-availability-copy", exports);
        const evaluation = try engine.evalModule(
            "import {ModelRuntime} from 'sdk-availability-copy';const r=await ModelRuntime.create({refreshOnCreate:false});const m={id:'kept',provider:'copy',type:'chat',toJSON(){throw Error('must not serialize')}};" ++
                "r.registerNativeProvider({id:'copy',auth:{apiKey:{resolve:async()=>({auth:{apiKey:'key'},source:'fixture'})}},getModels:()=>[m],getAllModels:()=>[m]});await r.getAvailable();await r.getAvailable();globalThis.sdkAvailabilityCopy=r;",
            "sdk-availability-copy.mjs",
        );
        defer engine.freeValue(evaluation);
        const settled = try engine.awaitValue(evaluation);
        defer engine.freeValue(settled);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const runtime = try sdk.get(engine, global, "sdkAvailabilityCopy");
        defer engine.freeValue(runtime);
        owned = try copySnapshot(engine, runtime, std.testing.allocator);
        try std.testing.expect(owned != null);
        try std.testing.expect(owned.?.revision >= 1);
        c.JS_RunGC(engine.runtime);
    }
    try std.testing.expectEqualStrings("copy", owned.?.available[0].provider);
    try std.testing.expectEqualStrings("kept", owned.?.available[0].id);
}
