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
    // A provider-specific query updates error status, not the aggregate model snapshot.
    if (args.len > 0 and c.JS_ToBool(engine.context, args[0]) == 1) {
        owner.availability_error_sequence = std.math.add(u64, owner.availability_error_sequence, 1) catch return error.NativeSDKRevisionOverflow;
        const options = if (args.len > 1) args[1] else c.pi_js_undefined();
        const pending = try sdk.invoke(engine, catalog, "getAvailable", args);
        defer engine.freeValue(pending);
        var captured = [_]c.JSValue{ runtime, c.pi_js_undefined(), c.JS_NewFloat64(engine.context, @floatFromInt(owner.availability_error_sequence)), options };
        const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, queried, "providerAvailabilityCompleted", 1, 0, 4, &captured));
        defer engine.freeValue(done);
        const failed = try engine.checked(c.JS_NewCFunctionData2(engine.context, availabilityFailed, "providerAvailabilityFailed", 1, 0, 4, &captured));
        defer engine.freeValue(failed);
        return sdk.invoke(engine, pending, "then", &.{ done, failed });
    }
    try @import("native_sdk_refresh.zig").invalidateProviderQueries(engine, owner.data);
    owner.availability_sequence = std.math.add(u64, owner.availability_sequence, 1) catch return error.NativeSDKRevisionOverflow;
    if (owner.availability_sequence > 9007199254740991) return error.NativeSDKRevisionOverflow;
    const sequence = owner.availability_sequence;
    owner.availability_error_sequence = std.math.add(u64, owner.availability_error_sequence, 1) catch return error.NativeSDKRevisionOverflow;
    const error_sequence = owner.availability_error_sequence;
    const requested_options = if (args.len > 1) args[1] else c.pi_js_undefined();
    const requested_signal = if (c.JS_IsObject(requested_options)) try sdk.get(engine, requested_options, "signal") else c.pi_js_undefined();
    defer engine.freeValue(requested_signal);
    const signal = if (c.JS_IsObject(requested_signal)) c.JS_DupValue(engine.context, requested_signal) else try @import("abort_signal.zig").create(engine);
    defer engine.freeValue(signal);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "signal", c.JS_DupValue(engine.context, signal));
    const providers = try sdk.invoke(engine, catalog, "getProviders", &.{});
    defer engine.freeValue(providers);
    const checks = try sdk.array(engine);
    defer engine.freeValue(checks);
    const rows = try sdk.invoke(engine, catalog, "getAvailable", &.{ c.pi_js_undefined(), options });
    defer engine.freeValue(rows);
    for (0..try sdk.length(engine, providers)) |index| {
        const provider = try engine.checked(c.JS_GetPropertyUint32(engine.context, providers, @intCast(index)));
        defer engine.freeValue(provider);
        const id = try sdk.get(engine, provider, "id");
        defer engine.freeValue(id);
        const check = try sdk.invoke(engine, catalog, "checkAuth", &.{ id, options });
        defer engine.freeValue(check);
        var captured_id = [_]c.JSValue{id};
        const paired = try engine.checked(c.JS_NewCFunctionData2(engine.context, authPair, "providerAuthPair", 1, 0, 1, &captured_id));
        defer engine.freeValue(paired);
        try sdk.append(engine, checks, try sdk.invoke(engine, check, "then", &.{paired}));
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const promise = try sdk.get(engine, global, "Promise");
    defer engine.freeValue(promise);
    const all_checks = try sdk.invoke(engine, promise, "all", &.{checks});
    defer engine.freeValue(all_checks);
    const credentials = try @import("native_sdk_models.zig").listCredentials(engine, owner.data, options);
    defer engine.freeValue(credentials);
    const inputs = try sdk.array(engine);
    defer engine.freeValue(inputs);
    inline for (.{ rows, all_checks, credentials }) |input| try sdk.append(engine, inputs, c.JS_DupValue(engine.context, input));
    const pending = try sdk.invoke(engine, promise, "all", &.{inputs});
    defer engine.freeValue(pending);
    var captured = [_]c.JSValue{ runtime, c.JS_NewFloat64(engine.context, @floatFromInt(sequence)), c.JS_NewFloat64(engine.context, @floatFromInt(error_sequence)), options };
    const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, completed, "availabilityCompleted", 1, 0, 4, &captured));
    defer engine.freeValue(done);
    const failed = try engine.checked(c.JS_NewCFunctionData2(engine.context, availabilityFailed, "availabilityFailed", 1, 0, 4, &captured));
    defer engine.freeValue(failed);
    return sdk.invoke(engine, pending, "then", &.{ done, failed });
}
fn queried(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, captured: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    clearFailure(engine, captured[0], captured[2]) catch |err| return sdk.fail(engine, err);
    return if (argc > 0) c.JS_DupValue(context, args[0]) else c.pi_js_undefined();
}
pub fn clearFailure(engine: *engine_mod.Engine, runtime: c.JSValue, error_serial: c.JSValue) !void {
    const owner = try sdk.state(engine, runtime);
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, error_serial) < 0) return error.JavaScriptException;
    if (@as(u64, @intFromFloat(number)) == owner.availability_error_sequence) {
        const previous = try sdk.get(engine, owner.data, "availabilityError");
        defer engine.freeValue(previous);
        if (!c.JS_IsUndefined(previous)) try publishStatus(engine, runtime, c.pi_js_undefined());
        try sdk.put(engine, owner.data, "availabilityError", c.pi_js_undefined());
    }
}
fn authPair(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, captured: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const result = sdk.array(engine) catch |err| return sdk.fail(engine, err);
    sdk.append(engine, result, c.JS_DupValue(context, captured[0])) catch |err| {
        engine.freeValue(result);
        return sdk.fail(engine, err);
    };
    sdk.append(engine, result, if (argc > 0) c.JS_DupValue(context, args[0]) else c.pi_js_undefined()) catch |err| {
        engine.freeValue(result);
        return sdk.fail(engine, err);
    };
    return result;
}
fn availabilityFailed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, captured: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const reason = if (argc > 0) args[0] else c.pi_js_undefined();
    recordFailure(engine, captured[0], captured[2], captured[3], reason) catch |err| return sdk.fail(engine, err);
    return c.JS_Throw(context, c.JS_DupValue(context, reason));
}
pub fn recordFailure(engine: *engine_mod.Engine, runtime: c.JSValue, error_serial: c.JSValue, options: c.JSValue, reason: c.JSValue) !void {
    const owner = try sdk.state(engine, runtime);
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, error_serial) < 0) return error.JavaScriptException;
    if (@as(u64, @intFromFloat(number)) != owner.availability_error_sequence) return;
    const signal = if (c.JS_IsObject(options)) try sdk.get(engine, options, "signal") else c.pi_js_undefined();
    defer engine.freeValue(signal);
    if (c.JS_IsObject(signal)) {
        const aborted = try sdk.get(engine, signal, "aborted");
        defer engine.freeValue(aborted);
        if (c.JS_ToBool(engine.context, aborted) == 1) return;
    }
    const message = if (c.JS_IsError(reason)) try sdk.get(engine, reason, "message") else string: {
        const text = try engine.toString(reason);
        defer engine.gpa.free(text);
        break :string try sdk.text(engine, text);
    };
    defer engine.freeValue(message);
    try publishStatus(engine, runtime, message);
    try sdk.put(engine, owner.data, "availabilityError", c.JS_DupValue(engine.context, message));
}
fn publishStatus(engine: *engine_mod.Engine, runtime: c.JSValue, message: c.JSValue) !void {
    const owner = try sdk.state(engine, runtime);
    const old = if (owner.availability_snapshot) |*value| value else return;
    const expected_revision = old.revision;
    var next = try old.copy(engine.gpa);
    errdefer next.deinit();
    next.revision = std.math.add(u64, expected_revision, 1) catch return error.NativeSDKRevisionOverflow;
    const text = if (c.JS_IsString(message)) try engine.toString(message) else null;
    defer if (text) |value| engine.gpa.free(value);
    try next.setAuth(old.configured_providers, old.stored_providers, text);
    const group: ?*@import("native_group.zig").Group = if (engine.native_sdk_extension_group) |pointer| @ptrCast(@alignCast(pointer)) else null;
    var group_copy: ?Snapshot = if (group) |value| try value.sdk_availability.prepare(engine.gpa, &next) else null;
    defer if (group_copy) |*value| value.deinit();
    if (owner.availability_snapshot.?.revision != expected_revision) {
        next.deinit();
        return;
    }
    owner.availability_snapshot.?.deinit();
    owner.availability_snapshot = next;
    if (group_copy) |value| {
        group.?.sdk_availability.commit(value);
        group_copy = null;
    }
}
pub fn admit(engine: *engine_mod.Engine, runtime: c.JSValue, rows: c.JSValue) !void {
    try admitAuth(engine, runtime, rows, c.pi_js_undefined(), c.pi_js_undefined());
}
pub fn admitAuth(engine: *engine_mod.Engine, runtime: c.JSValue, rows: c.JSValue, prepared: c.JSValue, error_serial: c.JSValue) !void {
    const owner = try sdk.state(engine, runtime);
    if (owner.availability_sequence >= 9007199254740991) return error.NativeSDKRevisionOverflow;
    owner.availability_sequence += 1;
    const result = try complete(engine, runtime, c.JS_NewFloat64(engine.context, @floatFromInt(owner.availability_sequence)), rows, prepared, error_serial);
    engine.freeValue(result);
}
pub fn registrationRefresh(engine: *engine_mod.Engine, runtime: c.JSValue) !void {
    var captured = [_]c.JSValue{runtime};
    if (c.JS_EnqueueJob(engine.context, registrationJob, 1, &captured) < 0) return error.OutOfMemory;
}
fn registrationJob(context: ?*c.JSContext, _: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return startRegistrationRefresh(engine, args[0]) catch |err| sdk.fail(engine, err);
}
fn startRegistrationRefresh(engine: *engine_mod.Engine, runtime: c.JSValue) !c.JSValue {
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "allowNetwork", c.pi_js_bool(engine.context, 0));
    const pending = try @import("native_sdk_refresh.zig").start(engine, runtime, options);
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
    if (argc < 1) return sdk.fail(engine, error.NativeSDKInvalidAvailability);
    const rows = engine.checked(c.JS_GetPropertyUint32(context, args[0], 0)) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(rows);
    return complete(engine, captured[0], captured[1], rows, args[0], captured[2]) catch |err| sdk.fail(engine, err);
}
fn complete(engine: *engine_mod.Engine, runtime: c.JSValue, serial: c.JSValue, rows: c.JSValue, auth_values: c.JSValue, error_serial: c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, runtime);
    var number: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &number, serial) < 0) return error.JavaScriptException;
    const sequence: u64 = @intFromFloat(number);
    if (sequence != owner.availability_sequence) return sdk.get(engine, owner.data, "available");
    const replacement = c.JS_IsObject(auth_values);
    const auth = if (c.JS_IsArray(auth_values)) try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map") else try sdk.get(engine, if (replacement) auth_values else owner.data, "authSnapshot");
    defer engine.freeValue(auth);
    const configured = if (c.JS_IsArray(auth_values)) try @import("native_sdk_auth_snapshot.zig").collection(engine, "Set") else try sdk.get(engine, if (replacement) auth_values else owner.data, "configuredProviders");
    defer engine.freeValue(configured);
    const stored = if (c.JS_IsArray(auth_values)) try @import("native_sdk_auth_snapshot.zig").collection(engine, "Set") else try sdk.get(engine, if (replacement) auth_values else owner.data, "storedProviders");
    defer engine.freeValue(stored);
    if (c.JS_IsArray(auth_values)) {
        const checks = try engine.checked(c.JS_GetPropertyUint32(engine.context, auth_values, 1));
        defer engine.freeValue(checks);
        for (0..try sdk.length(engine, checks)) |index| {
            const pair = try engine.checked(c.JS_GetPropertyUint32(engine.context, checks, @intCast(index)));
            defer engine.freeValue(pair);
            const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 0));
            defer engine.freeValue(id);
            const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 1));
            defer engine.freeValue(value);
            const ignored = try sdk.invoke(engine, auth, "set", &.{ id, value });
            engine.freeValue(ignored);
            if (!c.JS_IsUndefined(value)) {
                const added = try sdk.invoke(engine, configured, "add", &.{id});
                engine.freeValue(added);
            }
        }
        const credentials = try engine.checked(c.JS_GetPropertyUint32(engine.context, auth_values, 2));
        defer engine.freeValue(credentials);
        for (0..try sdk.length(engine, credentials)) |index| {
            const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, credentials, @intCast(index)));
            defer engine.freeValue(entry);
            const id = try sdk.get(engine, entry, "providerId");
            defer engine.freeValue(id);
            const added = try sdk.invoke(engine, stored, "add", &.{id});
            engine.freeValue(added);
        }
    }
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
    const configured_ids = try setIds(engine, configured);
    defer engine.freeValue(configured_ids);
    const stored_ids = try setIds(engine, stored);
    defer engine.freeValue(stored_ids);
    var auth_arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer auth_arena.deinit();
    const configured_names = try stringArray(engine, auth_arena.allocator(), configured_ids);
    const stored_names = try stringArray(engine, auth_arena.allocator(), stored_ids);
    const previous_error = try sdk.get(engine, owner.data, "availabilityError");
    defer engine.freeValue(previous_error);
    var error_number: f64 = 0;
    if (!c.JS_IsUndefined(error_serial) and c.JS_ToFloat64(engine.context, &error_number, error_serial) < 0) return error.JavaScriptException;
    const clears_error = !c.JS_IsUndefined(error_serial) and @as(u64, @intFromFloat(error_number)) == owner.availability_error_sequence;
    const failure_text = if (!clears_error and c.JS_IsString(previous_error)) try engine.toString(previous_error) else null;
    defer if (failure_text) |value| engine.gpa.free(value);
    try next.setAuth(configured_names, stored_names, failure_text);
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
    if (replacement) {
        try sdk.put(engine, owner.data, "authSnapshot", c.JS_DupValue(engine.context, auth));
        try sdk.put(engine, owner.data, "configuredProviders", c.JS_DupValue(engine.context, configured));
        try sdk.put(engine, owner.data, "storedProviders", c.JS_DupValue(engine.context, stored));
        if (clears_error) try sdk.put(engine, owner.data, "availabilityError", c.pi_js_undefined());
    }
    if (owner.availability_snapshot) |*old| old.deinit();
    owner.availability_snapshot = next;
    if (group_copy) |value| {
        group.?.sdk_availability.commit(value);
        group_copy = null;
    }
    return c.JS_DupValue(engine.context, rows);
}
fn setIds(engine: *engine_mod.Engine, set: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const array = try sdk.get(engine, global, "Array");
    defer engine.freeValue(array);
    return sdk.invoke(engine, array, "from", &.{set});
}
fn stringArray(engine: *engine_mod.Engine, gpa: std.mem.Allocator, values: c.JSValue) ![]const []const u8 {
    const count = try sdk.length(engine, values);
    if (count > 65536) return error.NativeSDKProviderLimit;
    const output = try gpa.alloc([]const u8, count);
    for (output, 0..) |*item, index| {
        const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index)));
        defer engine.freeValue(value);
        if (!c.JS_IsString(value)) return error.NativeSDKInvalidProviderIdentity;
        var length: usize = 0;
        const text = c.JS_ToCStringLen(engine.context, &length, value) orelse return error.JavaScriptException;
        defer c.JS_FreeCString(engine.context, text);
        item.* = try gpa.dupe(u8, text[0..length]);
    }
    return output;
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
