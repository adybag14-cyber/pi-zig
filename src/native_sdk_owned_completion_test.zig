//! Prepared real native-finalizer and allocator controls for SDK completion.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const owned = @import("extensions/native_sdk_owned_completion.zig");
const af = @import("extensions/native_async_function.zig");
const Prompt = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const Provider = @import("extensions/native_models_stream_scope.zig").Scope;
const Emission = struct { engine: *em.Engine, reason: c.JSValue, calls: usize = 0, capture: bool = false, transfer: bool = false, await_data: bool = false, private_data: bool = false, raw_oom: bool = false, caught_data: bool = false, initially_marked: bool = false };
fn finalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Emission = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    state.calls += 1;
    if (state.raw_oom) {
        _ = state.engine.throwNativeOutOfMemory(); // Actual pending private producer.
        state.reason = state.engine.native_allocation_exception.?;
        state.initially_marked = c.JS_IsUncatchableError(state.reason);
        return;
    }
    if (state.await_data) {
        if (state.private_data) {
            _ = state.engine.throwNativeOutOfMemory();
            const reason = c.JS_GetException(state.engine.context);
            c.JS_SetUncatchableError(state.engine.context, reason);
            state.reason = state.engine.native_allocation_exception.?;
            state.engine.freeValue(reason);
        }
        var resolving: [2]c.JSValue = undefined;
        const promise = c.JS_NewPromiseCapability(state.engine.context, &resolving);
        if (c.JS_IsException(promise)) return;
        var arguments = [_]c.JSValue{state.reason};
        const rejected = c.JS_Call(state.engine.context, resolving[1], c.pi_js_undefined(), 1, &arguments);
        state.engine.freeValue(rejected);
        state.engine.freeValue(resolving[0]); state.engine.freeValue(resolving[1]);
        const value = state.engine.awaitValueOnly(promise) catch |err| {
            state.caught_data = err == error.JavaScriptException;
            state.engine.freeValue(promise);
            return;
        };
        state.engine.freeValue(value); state.engine.freeValue(promise);
        return;
    }
    const reason = if (state.transfer) blk: { const owned_reason = state.reason; state.reason = c.pi_js_undefined(); break :blk owned_reason; } else c.JS_DupValue(state.engine.context, state.reason);
    const result = c.JS_Throw(state.engine.context, reason);
    if (state.capture) _ = state.engine.checked(result) catch {};
}
fn token(state: *Emission) !c.JSValue {
    var class: c.JSClassID = 0; _ = c.JS_NewClassID(state.engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Owned SDK completion cleanup", .finalizer = finalizer };
    if (c.JS_NewClass(state.engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const result = try state.engine.checked(c.JS_NewObjectClass(state.engine.context, class));
    _ = c.JS_SetOpaque(result, state);
    return result;
}
fn same(engine: *em.Engine, left: c.JSValue, right: c.JSValue) !void { try std.testing.expect(c.JS_IsStrictEqual(engine.context, left, right)); }

test "SDK owned completion both actual Scope shapes preserve ordinary DATA over per-root cleanup" {
    inline for (.{ Prompt, Provider }) |Scope| {
        for ([_]bool{ false, true }) |fatal_cleanup| {
            for ([_]bool{ false, true }) |captured_cleanup| {
                const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
                var outer: Prompt = .{ .engine = engine }; defer outer.deinit();
                const source_reason = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
                const cleanup = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
                const old_data = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
                c.JS_SetUncatchableError(engine.context, source_reason); // Initial action is DATA.
                c.JS_SetUncatchableError(engine.context, old_data);
                if (fatal_cleanup) c.JS_SetUncatchableError(engine.context, cleanup);
                var emission: Emission = .{ .engine = engine, .reason = cleanup, .capture = captured_cleanup };
                var scope: Scope = .{ .engine = engine };
                // Provider exceeds inline32; both real root stores retire.
                for (0..37) |index| _ = try scope.own(if (index == 35) try token(&emission) else c.pi_js_undefined());
                engine.captured_exception = c.JS_DupValue(engine.context, old_data);
                const action: af.Action = .{ .thrown = c.JS_DupValue(engine.context, source_reason) };
                if (fatal_cleanup) {
                    try std.testing.expectError(error.JavaScriptException, owned.finishAction(&scope, action));
                    try same(engine, cleanup, engine.captured_exception orelse return error.RequiredActualCleanup);
                } else {
                    const result = try owned.finishAction(&scope, action);
                    try std.testing.expect(result == .thrown);
                    defer engine.freeValue(result.thrown);
                    try same(engine, source_reason, result.thrown);
                    try std.testing.expect(engine.captured_exception == null);
                }
                try std.testing.expectEqual(@as(usize, 1), emission.calls);
                try std.testing.expectEqual(@as(usize, 0), scope.values.items.len);
                if (comptime @hasField(Scope, "inline_count")) try std.testing.expectEqual(@as(usize, 0), scope.inline_count);
                try std.testing.expect(!c.JS_HasException(engine.context));
                try std.testing.expect(c.JS_IsUncatchableError(source_reason) and c.JS_IsUncatchableError(old_data));
            }
        }
    }
}

test "SDK owned completion captures actual failed operation before root cleanup and void Source finally" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    var outer: Prompt = .{ .engine = engine }; defer outer.deinit();
    const original = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
    const cleanup = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
    var emission: Emission = .{ .engine = engine, .reason = cleanup };
    var scope: Prompt = .{ .engine = engine };
    _ = try scope.own(try token(&emission));
    const outcome = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, original)));
    try std.testing.expectError(error.JavaScriptException, owned.finishValue(&scope, outcome));
    try same(engine, original, engine.captured_exception orelse return error.RequiredOriginalFailure);
    try std.testing.expectEqual(@as(usize, 1), emission.calls);
    const caught = engine.captured_exception.?; engine.captured_exception = null; engine.freeValue(caught);
    // A later real Source finally/catch has independent ordinary precedence.
    var next: Provider = .{ .engine = engine };
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, cleanup));
    const actual: anyerror!void = @import("extensions/native_js_values.zig").capture(engine);
    try std.testing.expectError(error.JavaScriptException, owned.finishVoid(&next, actual));
    try same(engine, cleanup, engine.captured_exception orelse return error.RequiredLaterReplacement);
}

test "SDK owned completion returned native result cleanup promotes first actual fatal only" {
    for ([_]bool{ false, true }) |first_fatal| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var outer: Prompt = .{ .engine = engine }; defer outer.deinit();
        const first = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
        const second = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
        if (first_fatal) c.JS_SetUncatchableError(engine.context, first);
        c.JS_SetUncatchableError(engine.context, second);
        var root_emission: Emission = .{ .engine = engine, .reason = first };
        var result_emission: Emission = .{ .engine = engine, .reason = second };
        var scope: Prompt = .{ .engine = engine };
        _ = try scope.own(try token(&root_emission));
        const result: af.Action = .{ .returned = try token(&result_emission) };
        try std.testing.expectError(error.JavaScriptException, owned.finishAction(&scope, result));
        try same(engine, if (first_fatal) first else second, engine.captured_exception orelse return error.RequiredFirstActualFatal);
        try std.testing.expectEqual(@as(usize, 1), root_emission.calls);
        try std.testing.expectEqual(@as(usize, 1), result_emission.calls);
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}
fn actualGpaFailure(engine: *em.Engine, failing: *std.testing.FailingAllocator) anyerror!af.Action {
    failing.fail_index = failing.alloc_index; defer failing.fail_index = std.math.maxInt(usize);
    const bytes = try engine.gpa.alloc(u8, 1); defer engine.gpa.free(bytes);
    return .{ .returned = c.pi_js_undefined() };
}
test "SDK owned completion actual GPA failure never promotes historical captured DATA" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    var outer: Prompt = .{ .engine = engine }; defer outer.deinit();
    const history = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
    const cleanup = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
    c.JS_SetUncatchableError(engine.context, history);
    var emission: Emission = .{ .engine = engine, .reason = cleanup };
    var scope: Provider = .{ .engine = engine };
    _ = try scope.own(try token(&emission));
    engine.captured_exception = c.JS_DupValue(engine.context, history);
    try std.testing.expectError(error.JavaScriptException, owned.finishAction(&scope, actualGpaFailure(engine, &failing)));
    try std.testing.expect(failing.has_induced_failure);
    const current = engine.captured_exception orelse return error.RequiredActualAllocatorFailure;
    try std.testing.expect(c.JS_IsUncatchableError(current));
    try same(engine, current, engine.native_allocation_exception.?);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, current, history));
    try std.testing.expectEqual(@as(usize, 1), emission.calls);
}
test "SDK owned completion recorded AF throw remains DATA through ordinary cleanup" {
    inline for (.{ Prompt, Provider }) |Scope| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var outer: Prompt = .{ .engine = engine }; defer outer.deinit();
        const data = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
        const cleanup = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
        c.JS_SetUncatchableError(engine.context, data);
        var emission: Emission = .{ .engine = engine, .reason = cleanup };
        var scope: Scope = .{ .engine = engine };
        var state = c.pi_js_undefined(); defer engine.freeValue(state);
        const job = try @import("extensions/native_async_body.zig").init(&scope, &state);
        try @import("extensions/native_async_body.zig").reject(&scope, job, data);
        _ = try scope.own(try token(&emission));
        const success: anyerror!void = {};
        try owned.finishRecorded(&scope, success, job);
        const actual = try @import("extensions/native_async_body.zig").action(&outer, state);
        defer switch (actual) { .returned, .awaited, .thrown => |value| engine.freeValue(value) };
        try std.testing.expect(actual == .thrown);
        try same(engine, data, actual.thrown);
        try std.testing.expect(c.JS_IsUncatchableError(data));
        try std.testing.expect(engine.captured_exception == null and !c.JS_HasException(engine.context));
        try std.testing.expectEqual(@as(usize, 1), emission.calls);
    }
}
test "SDK owned completion individual native releases preserve fatal through sole Source reason cleanup chain" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var outer: Prompt = .{ .engine = engine }; defer outer.deinit();
    const ordinary = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
    const fatal = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
    const final = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
    c.JS_SetUncatchableError(engine.context, fatal);
    var first: Emission = .{ .engine = engine, .reason = ordinary };
    var second: Emission = .{ .engine = engine, .reason = fatal };
    var last: Emission = .{ .engine = engine, .reason = final };
    const intermediate = try engine.checked(c.JS_NewError(engine.context));
    if (c.JS_DefinePropertyValueStr(engine.context, intermediate, "cleanup", try token(&last), c.JS_PROP_C_W_E) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    var displaced: Emission = .{ .engine = engine, .reason = intermediate, .transfer = true };
    const source = try engine.checked(c.JS_NewError(engine.context));
    c.JS_SetUncatchableError(engine.context, source); // Still initial Action DATA.
    if (c.JS_DefinePropertyValueStr(engine.context, source, "cleanup", try token(&displaced), c.JS_PROP_C_W_E) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    const one = try token(&first);
    const two = try token(&second);
    // No retained alias owns source/intermediate at the promotion point.
    var completion = owned.Completion.initAction(engine, .{ .thrown = source });
    completion.release(one); // ordinary B cannot replace initial Source A.
    completion.release(two); // fatal C frees A -> sole D -> cleanup E.
    try std.testing.expectError(error.JavaScriptException, completion.finishAction());
    try same(engine, fatal, engine.captured_exception orelse return error.RequiredFirstFatalChain);
    try std.testing.expectEqual(@as(usize, 1), first.calls);
    try std.testing.expectEqual(@as(usize, 1), second.calls);
    try std.testing.expectEqual(@as(usize, 1), displaced.calls);
    try std.testing.expectEqual(@as(usize, 1), last.calls);
    try std.testing.expect(c.JS_IsUndefined(displaced.reason));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
test "SDK owned completion cleanup caught Await rejection is DATA even when newly private" {
    for ([_]bool{ false, true }) |fresh_private| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var outer: Prompt = .{ .engine = engine }; defer outer.deinit();
        const data = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
        c.JS_SetUncatchableError(engine.context, data);
        const marker = try outer.text("actual normal result");
        var emission: Emission = .{ .engine = engine, .reason = data, .await_data = true, .private_data = fresh_private };
        var scope: Provider = .{ .engine = engine };
        _ = try scope.own(try token(&emission));
        const result = try owned.finishAction(&scope, .{ .returned = c.JS_DupValue(engine.context, marker) });
        try std.testing.expect(result == .returned);
        defer engine.freeValue(result.returned);
        try same(engine, marker, result.returned);
        try std.testing.expect(emission.caught_data);
        try std.testing.expect(c.JS_IsUncatchableError(emission.reason));
        if (fresh_private) try std.testing.expect(c.pi_js_native_allocation_error_generation(emission.reason) != 0);
        try std.testing.expect(engine.captured_exception == null and !c.JS_HasException(engine.context));
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 1), emission.calls);
    }
}

test "SDK owned completion exact native free recognizes newly born private pending OOM" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var outer: Prompt = .{ .engine = engine }; defer outer.deinit();
    const source = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
    var emission: Emission = .{ .engine = engine, .reason = c.pi_js_undefined(), .raw_oom = true };
    var scope: Prompt = .{ .engine = engine };
    _ = try scope.own(try token(&emission));
    try std.testing.expectError(error.JavaScriptException, owned.finishAction(&scope, .{ .thrown = c.JS_DupValue(engine.context, source) }));
    try std.testing.expect(!emission.initially_marked);
    try std.testing.expect(c.JS_IsUncatchableError(emission.reason));
    try same(engine, emission.reason, engine.captured_exception orelse return error.RequiredActualRawOOM);
    try std.testing.expect(c.pi_js_native_allocation_error_generation(emission.reason) != 0);
    try std.testing.expect(engine.native_fatal_invocation == null and !c.JS_HasException(engine.context));
    try std.testing.expectEqual(@as(usize, 1), emission.calls);
}