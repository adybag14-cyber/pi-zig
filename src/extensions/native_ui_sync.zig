//! Correlation before VM allocation for blocking native frontend requests.
const std = @import("std");
const em = @import("engine.zig");
const protocol = @import("native_ui_service_protocol.zig");
const c = em.c;
pub fn matches(header: protocol.Header, value: std.json.Value) bool {
    if (value != .object) return false;
    const kind = value.object.get("kind") orelse return false;
    if (kind != .string or !std.mem.eql(u8, kind.string, "native_ui_service_response")) return false;
    const candidate = protocol.Header.read(value.object) catch return false;
    return header.matches(candidate);
}
pub fn response(engine: *em.Engine, header: protocol.Header, value: std.json.Value) !?c.JSValue {
    if (!matches(header, value)) return null;
    const ok = value.object.get("ok") orelse return null;
    if (ok != .bool) return null;
    if (ok.bool) return try engine.fromJsonValue(value.object.get("result") orelse .null);
    const reason = value.object.get("error") orelse std.json.Value{ .string = "Native UI request failed" };
    const text = if (reason == .string) try engine.gpa.dupe(u8, reason.string) else try std.json.Stringify.valueAlloc(engine.gpa, reason, .{});
    defer engine.gpa.free(text);
    const exception = try engine.checked(c.JS_NewError(engine.context));
    var transferred = false;
    defer if (!transferred) engine.freeValue(exception);
    const message = try engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
    if (c.JS_DefinePropertyValueStr(engine.context, exception, "message", message, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    transferred = true;
    _ = try engine.checked(c.JS_Throw(engine.context, exception));
    unreachable;
}

test "native Main UI sync response rejects every foreign identity before host or VM allocation" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"kind\":\"native_ui_service_response\",\"version\":1,\"ownerGeneration\":\"1\",\"serviceId\":\"2\",\"serviceGeneration\":\"3\",\"extensionId\":\"4\",\"requestId\":\"5\",\"ok\":true,\"result\":{\"original\":true}}", .{});
    defer parsed.deinit();
    const actual = try protocol.Header.read(parsed.value.object);
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = 0 });
    engine.gpa = failing.allocator();
    defer engine.gpa = std.testing.allocator;
    for (0..5) |field| {
        var foreign = actual;
        switch (field) {
            0 => foreign.lease.owner_generation += 1,
            1 => foreign.lease.service_id += 1,
            2 => foreign.lease.service_generation += 1,
            3 => foreign.lease.extension_id += 1,
            4 => foreign.request_id += 1,
            else => unreachable,
        }
        try std.testing.expect((try response(engine, foreign, parsed.value)) == null);
    }
    try std.testing.expectEqual(@as(usize, 0), failing.alloc_index);
    engine.gpa = std.testing.allocator;
    const result = (try response(engine, actual, parsed.value)).?;
    defer engine.freeValue(result);
    const original = try engine.checked(c.JS_GetPropertyStr(engine.context, result, "original"));
    defer engine.freeValue(original);
    try std.testing.expect(c.JS_ToBool(engine.context, original) != 0);
    try parsed.value.object.put(std.testing.allocator, "ok", .{ .bool = false });
    try parsed.value.object.put(std.testing.allocator, "error", .{ .string = "actual-settings-failure" });
    try std.testing.expectError(error.JavaScriptException, response(engine, actual, parsed.value));
    const reason = try engine.toString(engine.captured_exception.?);
    defer engine.gpa.free(reason);
    try std.testing.expectEqualStrings("Error: actual-settings-failure", reason);
}

fn allocationResponse(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, "{\"kind\":\"native_ui_service_response\",\"version\":1,\"ownerGeneration\":\"1\",\"serviceId\":\"2\",\"serviceGeneration\":\"3\",\"extensionId\":\"4\",\"requestId\":\"5\",\"ok\":true,\"result\":{\"owned\":[\"settings\",true]}}", .{});
    defer parsed.deinit();
    const header = try protocol.Header.read(parsed.value.object);
    const result = (try response(engine, header, parsed.value)).?;
    defer engine.freeValue(result);
    try parsed.value.object.put(gpa, "ok", .{ .bool = false });
    try parsed.value.object.put(gpa, "error", .{ .string = "owned-frontend-error" });
    _ = response(engine, header, parsed.value) catch |err| {
        if (err != error.JavaScriptException) return err;
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure) return error.OutOfMemory;
        return;
    };
    return error.MissingFrontendError;
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    allocationResponse(gpa) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
        return err;
    };
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    if (failing.has_induced_failure) return error.OutOfMemory;
}
test "native Main UI sync response exhaustive host and QuickJS allocation ownership for success and actual frontend failure" {
    try @import("../test_support/sdk_allocation_shards.zig").check("main-ui-sync-response", allocationProbe, .{});
}
