const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
extern fn pi_js_test_allocator_fail_after(*anyopaque, usize) void;
extern fn pi_js_test_allocator_clear_failure(*anyopaque) void;
extern fn pi_js_test_allocator_attempts(*anyopaque) usize;
extern fn pi_js_test_allocator_failures(*anyopaque) usize;
extern fn pi_js_test_retain_memory_owner(*anyopaque) void;
const Counters = struct { reentries: usize = 0, collections: usize = 0 };

fn reenter(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context.?;
    const counters: *Counters = @ptrCast(@alignCast(c.JS_GetContextOpaque(ctx).?));
    counters.reentries += 1;
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    const nested = c.JS_PiJSONStringifyNode(ctx, value, c.pi_js_undefined(), c.pi_js_undefined());
    if (c.JS_IsException(nested)) return nested;
    c.JS_FreeValue(ctx, nested);
    c.JS_RunGC(c.JS_GetRuntime(ctx));
    counters.collections += 1;
    return c.pi_js_undefined();
}
fn text(ctx: *c.JSContext, value: c.JSValue) ![]u8 {
    var length: usize = 0;
    const bytes = c.JS_ToCStringLen(ctx, &length, value);
    if (bytes == null) return error.UnexpectedDiagnosticAllocationFailure;
    defer c.JS_FreeCString(ctx, bytes);
    return std.testing.allocator.dupe(u8, bytes[0..length]);
}
fn originalMessage(ctx: *c.JSContext) ![]u8 {
    const reason = c.JS_GetException(ctx);
    defer c.JS_FreeValue(ctx, reason);
    if (!c.JS_IsError(reason) or c.JS_IsUninitialized(reason)) return error.LostOriginalAllocationException;
    const message_value = c.JS_GetPropertyStr(ctx, reason, "message");
    defer c.JS_FreeValue(ctx, message_value);
    if (c.JS_IsException(message_value)) return error.InvalidOriginalAllocationException;
    return text(ctx, message_value);
}
const Outcome = struct {
    attempts: usize,
    message: []u8,
    fn deinit(self: Outcome) void {
        std.testing.allocator.free(self.message);
    }
};
fn attempt(source: []const u8, nth: ?usize, expected: ?[]const u8) !Outcome {
    const owners_before = c.pi_js_native_memory_owners();
    var owner_pointer: ?*anyopaque = null;
    const runtime = c.pi_js_new_runtime(64 * 1024 * 1024, &owner_pointer) orelse return error.OutOfMemory;
    const owner = owner_pointer.?;
    pi_js_test_retain_memory_owner(owner);
    // The runtime and the retained test reference release the same real owner.
    defer c.pi_js_release_memory_owner(owner);
    defer c.pi_js_release_memory_owner(owner);
    var runtime_live = true;
    defer if (runtime_live) c.JS_FreeRuntime(runtime);
    c.JS_SetMaxStackSize(runtime, 1024 * 1024);
    const ctx = c.JS_NewContext(runtime) orelse return error.OutOfMemory;
    var counters: Counters = .{};
    c.JS_SetContextOpaque(ctx, &counters);
    var context_live = true;
    defer if (context_live) c.JS_FreeContext(ctx);
    const root = c.JS_GetGlobalObject(ctx);
    const defined = c.JS_DefinePropertyValueStr(ctx, root, "reviewReenter", c.JS_NewCFunction(ctx, reenter, "reviewReenter", 1), c.JS_PROP_C_W_E);
    c.JS_FreeValue(ctx, root);
    if (defined < 0) return error.SetupFailed;
    // Compilation, object creation and native callback installation finish
    // before any injected allocation. O's compiler draft is not used here.
    const value = c.JS_Eval(ctx, source.ptr, source.len, "genuine-json-path-cmalloc-input.js", c.JS_EVAL_TYPE_GLOBAL);
    if (c.JS_IsException(value)) return error.SetupFailed;
    const before = pi_js_test_allocator_attempts(owner);
    if (nth) |index| {
        std.debug.print("JSON C allocation index={d}\n", .{index});
        pi_js_test_allocator_fail_after(owner, index);
    }
    const result = c.JS_PiJSONStringifyNode(ctx, value, c.pi_js_undefined(), c.pi_js_undefined());
    const count = pi_js_test_allocator_attempts(owner) - before;
    const failures = pi_js_test_allocator_failures(owner);
    pi_js_test_allocator_clear_failure(owner);
    c.JS_FreeValue(ctx, value);
    if (!c.JS_IsException(result)) {
        c.JS_FreeValue(ctx, result);
        return error.MissingOriginalCircularException;
    }
    const message = try originalMessage(ctx);
    errdefer std.testing.allocator.free(message);
    if (nth) |index| {
        try std.testing.expectEqual(@as(usize, 1), failures);
        // A shrink allocation is optional. Its failure may retain the exact
        // original diagnostic; every mandatory failure must retain real OOM.
        if (!std.mem.eql(u8, message, "out of memory") and !std.mem.eql(u8, message, expected.?)) {
            std.debug.print("JSON C negative index={d} original message={s}\n", .{ index, message });
            return error.UnexpectedCAllocationException;
        }
    } else try std.testing.expect(std.mem.startsWith(u8, message, "Converting circular structure to JSON\n"));
    const global = c.JS_GetGlobalObject(ctx);
    const gets = c.JS_GetPropertyStr(ctx, global, "reviewGets");
    c.JS_FreeValue(ctx, global);
    if (c.JS_IsNumber(gets)) {
        var getter_count: i32 = 0;
        const status = c.JS_ToInt32(ctx, &getter_count, gets);
        c.JS_FreeValue(ctx, gets);
        if (status < 0) return error.InvalidGetterCount;
        try std.testing.expect(getter_count >= 0 and getter_count <= 1);
        try std.testing.expectEqual(@as(usize, @intCast(getter_count)), counters.reentries);
        if (nth == null) {
            try std.testing.expectEqual(@as(i32, 1), getter_count);
            try std.testing.expectEqual(@as(usize, 1), counters.collections);
        }
    } else c.JS_FreeValue(ctx, gets);
    c.JS_RunGC(runtime);
    c.JS_FreeContext(ctx);
    context_live = false;
    c.JS_FreeRuntime(runtime);
    runtime_live = false;
    try std.testing.expectEqual(@as(usize, 0), c.pi_js_native_memory_used(owner));
    try std.testing.expectEqual(owners_before + 1, c.pi_js_native_memory_owners());
    return .{ .attempts = count, .message = message };
}
fn sweep(source: []const u8) !void {
    const owners_before = c.pi_js_native_memory_owners();
    const baseline = try attempt(source, null, null);
    defer baseline.deinit();
    std.debug.print("JSON C allocation baseline attempts={d}\n", .{baseline.attempts});
    for (0..baseline.attempts) |index| {
        const outcome = try attempt(source, index, baseline.message);
        outcome.deinit();
    }
    try std.testing.expectEqual(owners_before, c.pi_js_native_memory_owners());
}
test "native JSON path Cmalloc Unicode constructor name every allocation preserves exception and releases owner bytes" {
    try sweep("(()=>{class Κατασκευαστής{};const x=new Κατασκευαστής;x.self=x;return x})()");
}
test "native JSON path Cmalloc deep array object path every allocation preserves original exception and releases keys" {
    try sweep("(()=>{const x=[];let p={parent:x};x.push(p);for(let i=0;i<8;i++)p=p['child'+i]={};p.back=x;return x})()");
}
test "native JSON path Cmalloc getter native stringify reentry and GC keep ancestor and edge roots live" {
    try sweep("globalThis.reviewGets=0;globalThis.reviewNested={stable:'nested Ω'};(()=>{const x={get self(){reviewGets++;reviewReenter(reviewNested);return x}};return x})()");
}
