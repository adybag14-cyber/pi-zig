//! Actual Environment-owned abort toggle and shared intrinsic backing controls.
//! This does not publish a partial util namespace or implement native exit policy.
const std = @import("std");
const support = @import("native_node_file_handle_owner_test_support.zig");
const c = support.c;
const callbacks = support.callbacks;

test "native abort toggle is the original one-cell Uint32Array on the actual native backing" {
    var f: support.Fixture = undefined; try f.init(); defer f.deinit();
    const env = f.env();
    const view = try env.abortOnUncaughtToggle();
    try std.testing.expect(c.JS_GetTypedArrayType(view) == c.JS_TYPED_ARRAY_UINT32);
    try std.testing.expectEqual(@as(usize, 1), env.should_abort_on_uncaught_toggle.data.len);
    try std.testing.expectEqual(@as(u32, 1), env.should_abort_on_uncaught_toggle.data[0]);
    var offset: usize = 0;
    var length: usize = 0;
    var element_bytes: usize = 0;
    const buffer = try f.engine.checked(c.JS_GetTypedArrayBuffer(
        f.engine.context, view, &offset, &length, &element_bytes));
    defer f.engine.freeValue(buffer);
    var actual_bytes: usize = 0;
    const data = c.JS_GetArrayBuffer(f.engine.context, &actual_bytes, buffer);
    try std.testing.expect(data != null);
    try std.testing.expectEqual(@as(usize, 0), offset);
    try std.testing.expectEqual(@as(usize, 4), length);
    try std.testing.expectEqual(@as(usize, 4), element_bytes);
    try std.testing.expectEqual(@as(usize, 4), actual_bytes);
    try std.testing.expectEqual(@intFromPtr(data),
        @intFromPtr(env.should_abort_on_uncaught_toggle.data.ptr));
    try f.expose("abortToggle", view);
    try f.expect("abortToggle instanceof Uint32Array && abortToggle.length===1 && abortToggle[0]===1");
}

test "native abort toggle guest and native writes share the same full 32-bit cell" {
    var f: support.Fixture = undefined; try f.init(); defer f.deinit();
    const env = f.env();
    try f.expose("abortToggle", try env.abortOnUncaughtToggle());
    try f.evaluate("abortToggle[0]=0;");
    try std.testing.expectEqual(@as(u32, 0), env.should_abort_on_uncaught_toggle.data[0]);
    try f.evaluate("abortToggle[0]=1;");
    try std.testing.expectEqual(@as(u32, 1), env.should_abort_on_uncaught_toggle.data[0]);
    try f.evaluate("abortToggle[0]=0xfedcba98;");
    try std.testing.expectEqual(@as(u32, 0xfedcba98), env.should_abort_on_uncaught_toggle.data[0]);
    env.should_abort_on_uncaught_toggle.data[0] = 0x12345678;
    try f.expect("abortToggle[0]===0x12345678");
}

test "native abort toggle repeated acquisition and GC retain identity without resetting state" {
    var f: support.Fixture = undefined; try f.init(); defer f.deinit();
    const env = f.env();
    const first = try env.abortOnUncaughtToggle();
    try f.expose("abortToggle", first);
    try f.evaluate("abortToggle[0]=0;");
    c.JS_RunGC(f.engine.runtime);
    const second = try env.abortOnUncaughtToggle();
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, first, second));
    try std.testing.expectEqual(@as(u32, 0), env.should_abort_on_uncaught_toggle.data[0]);
    try f.expose("secondAbortToggle", second);
    try f.expect("abortToggle===secondAbortToggle && secondAbortToggle[0]===0");
}

test "native abort toggle belongs to each actual Environment rather than shared process-global storage" {
    var first: support.Fixture = undefined; try first.init(); defer first.deinit();
    var second: support.Fixture = undefined; try second.init(); defer second.deinit();
    try first.expose("abortToggle", try first.env().abortOnUncaughtToggle());
    try second.expose("abortToggle", try second.env().abortOnUncaughtToggle());
    try first.evaluate("abortToggle[0]=0;");
    try first.expect("abortToggle[0]===0");
    try second.expect("abortToggle[0]===1");
    second.env().should_abort_on_uncaught_toggle.data[0] = 42;
    try first.expect("abortToggle[0]===0");
    try second.expect("abortToggle[0]===42");
}

test "native abort toggle disarm clears native pointers while an independently retained VM view stays valid" {
    var f: support.Fixture = undefined; try f.init(); defer f.deinit();
    // A second real Environment needs no provider names or physical requests
    // for this alias-lifetime control. Other native operations remain unused.
    const env = try callbacks.Environment.create(f.engine, .{
        .provider_names = &.{},
        .resource_symbol = f.env().resource_symbol.?,
        .process_object = f.env().process_object.?,
        .async_context_frame = false,
        .operations = f.env().operations,
    });
    var disarmed = false;
    defer {
        if (!disarmed) env.disarm() catch @panic("abort toggle Environment teardown failed");
        env.release();
    }
    try f.expose("retainedAbortToggle", try env.abortOnUncaughtToggle());
    disarmed = true;
    try env.disarm();
    try std.testing.expectEqual(@as(usize, 0), env.should_abort_on_uncaught_toggle.data.len);
    try std.testing.expect(env.should_abort_on_uncaught_toggle.view == null);
    try std.testing.expectError(error.NativeNodeEnvironmentClosed, env.abortOnUncaughtToggle());
    c.JS_RunGC(f.engine.runtime);
    try f.expect("retainedAbortToggle instanceof Uint32Array && retainedAbortToggle[0]===1");
    try f.evaluate("retainedAbortToggle[0]=0xfedcba98;");
    try f.expect("retainedAbortToggle[0]===0xfedcba98");
}
