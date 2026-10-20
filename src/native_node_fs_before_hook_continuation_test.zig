//! Real FS read completions exercising the original void before-hook tail.
//! The explicitly selected test policy rethrows the same actual current
//! pending JavaScript reason. Complete native hook/fatal bootstrap remains
//! separate; these controls do not replace it with a returned Error shortcut.
const std = @import("std");
const support = @import("native_node_file_handle_owner_test_support.zig");
const c = support.c;
const uv = support.uv;
const Fixture = support.Fixture;
const File = support.File;

fn read(f: *Fixture, descriptor: c_int) !c.JSValue {
    try f.expose("ownerFsFd", c.JS_NewInt32(f.engine.context, descriptor));
    return f.value(
        "actualOwnerFsRead(ownerFsFd, new Uint8Array(4), 0, 4, 1, actualOwnerUsePromises)");
}
fn retainStorage(f: *Fixture) !*uv.PiUvFsRequest {
    const actual = (try f.pendingFs()).native_request.?;
    uv.pi_uv_fs_request_retain(actual);
    return actual;
}
fn expectActualContinuation(f: *Fixture, id: f64, actual: *uv.PiUvFsRequest) !void {
    try std.testing.expectError(error.JavaScriptException, f.pumpIo());
    const reason = try f.takeCaught();
    defer f.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, f.selected_hook_reason.?));
    try std.testing.expectEqual(@as(usize, 1), f.hook_rethrows);
    try std.testing.expectEqual(@as(usize, 1), f.env().callback_depth);
    try std.testing.expectEqual(@as(u32, 1), f.env().field(.stack_length).*);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
    const info = uv.pi_uv_fs_request_info(actual);
    try std.testing.expectEqual(@as(c_int, 1), info.accepted);
    try std.testing.expectEqual(@as(c_int, 1), info.cleaned);
    try f.expose("ownerFsId", c.JS_NewFloat64(f.engine.context, id));
    try f.expect("ownerBeforeIds.length === 1 && ownerAfterIds.length === 1 && " ++
        "ownerBeforeIds[0] === ownerFsId && ownerAfterIds[0] === ownerFsId");
}

test "native FS before hook actual read fulfills after the same ordinary hook rethrow" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.installFsRead();
    try f.installThrowingBeforeHook();
    const promise = try read(&f, file.descriptor);
    defer f.engine.freeValue(promise);
    c.JS_PromiseMarkAsHandled(f.engine.context, promise);
    const id = (try f.pendingFs()).wrap.async_id;
    const actual = try retainStorage(&f);
    defer uv.pi_uv_fs_request_release(actual);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, promise));
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try expectActualContinuation(&f, id, actual);
    try std.testing.expectEqual(@as(i64, 4), uv.pi_uv_fs_request_info(actual).result);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.engine.context, promise));
    const result = c.JS_PromiseResult(f.engine.context, promise);
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsNumber(result));
    var bytes: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.engine.context, &bytes, result));
    try std.testing.expectEqual(@as(i32, 4), bytes);
    try std.testing.expectEqual(@as(c_int, 0), File.status(file.descriptor));
}

test "native FS before hook actual EBADF read rejects with UVException while the hook reason propagates separately" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.installFsRead();
    try f.installThrowingBeforeHook();
    const promise = try read(&f, -1);
    defer f.engine.freeValue(promise);
    c.JS_PromiseMarkAsHandled(f.engine.context, promise);
    const id = (try f.pendingFs()).wrap.async_id;
    const actual = try retainStorage(&f);
    defer uv.pi_uv_fs_request_release(actual);
    try expectActualContinuation(&f, id, actual);
    try std.testing.expectEqual(@as(i64, support.physical.UV_EBADF),
        uv.pi_uv_fs_request_info(actual).result);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(f.engine.context, promise));
    const result = c.JS_PromiseResult(f.engine.context, promise);
    defer f.engine.freeValue(result);
    try std.testing.expect(!c.JS_IsStrictEqual(f.engine.context, result, f.selected_hook_reason.?));
    try f.expose("ownerFsRejection", result);
    try f.expect("ownerFsRejection instanceof Error && ownerFsRejection.code === 'EBADF' && " ++
        "ownerFsRejection.syscall === 'read'");
    try std.testing.expect(!c.JS_IsUncatchableError(result));
}

test "native FS before hook continuation performs the original live Promise Get before settlement" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.installFsRead();
    try f.installThrowingBeforeHook();
    const original = try read(&f, file.descriptor);
    defer f.engine.freeValue(original);
    const request = try f.pendingFs();
    const id = request.wrap.async_id;
    try f.expose("ownerFsRequest", try request.object());
    try f.evaluate(
        \\globalThis.ownerReplacementPromise = new Promise(() => {});
        \\globalThis.ownerLivePromiseGets = 0;
        \\Object.defineProperty(ownerFsRequest, "promise", { configurable: true, get() {
        \\  ++ownerLivePromiseGets;
        \\  if (ownerBeforeIds.length !== 1) throw Error("live Get ran before real before hook");
        \\  return ownerReplacementPromise;
        \\}});
    );
    const replacement = try f.global("ownerReplacementPromise");
    defer f.engine.freeValue(replacement);
    const actual = try retainStorage(&f);
    defer uv.pi_uv_fs_request_release(actual);
    try expectActualContinuation(&f, id, actual);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, original));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.engine.context, replacement));
    try f.expect("ownerLivePromiseGets === 1");
    const retained = try f.global("ownerFsRequest");
    defer f.engine.freeValue(retained);
    try std.testing.expect(f.registry().unwrap(retained) == null);
    const result = c.JS_PromiseResult(f.engine.context, replacement);
    defer f.engine.freeValue(result);
    var bytes: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.engine.context, &bytes, result));
    try std.testing.expectEqual(@as(i32, 4), bytes);
}
