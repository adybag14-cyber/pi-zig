//! Focused controls for the actual FileHandle/CloseReq/GC ownership graph.
//! These are source controls until a separately authorized native build/run.
//! The fixture selects the real present-object constructor; complete public
//! FileHandle templates, native tracing/allocation retry and hook/uncaught
//! policy bootstrap remain explicit separate production dependencies.
const std = @import("std");
const support = @import("native_node_file_handle_owner_test_support.zig");
const a = support.a;
const c = support.c;
const uv = support.uv;
const physical = support.physical;
const Fixture = support.Fixture;
const File = support.File;
const Handle = support.Handle;

// Avoid libuv Windows' fd <= 2 close branch and any recycled real descriptor.
const invalid_descriptor: c_int = std.math.maxInt(c_int);

fn expectClosed(f: *Fixture, descriptor: c_int) !void {
    const handle = try f.handle();
    try std.testing.expect(handle.read_state.closed and !handle.read_state.closing);
    try std.testing.expectEqual(@as(c_int, -1), handle.getFD());
    try std.testing.expect(!handle.isAlive() and !handle.isClosing());
    try std.testing.expectEqual(@as(c_int, physical.UV_EBADF), File.status(descriptor));
}
fn closeAndPump(f: *Fixture) !void {
    const promise = try (try f.handle()).closePromise();
    defer f.engine.freeValue(promise);
    c.JS_PromiseMarkAsHandled(f.engine.context, promise);
    try f.pumpIo();
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED,
        c.JS_PromiseState(f.engine.context, promise));
}
fn retainCloseStorage(f: *Fixture) !*uv.PiUvFsRequest {
    const actual = (try f.pendingClose()).actual.?;
    uv.pi_uv_fs_request_retain(actual);
    return actual;
}
fn warningRecorder(f: *Fixture) !void {
    try f.evaluate(
        \\globalThis.ownerWarnings = [];
        \\process.emitWarning = function(...args) {
        \\  ownerWarnings.push([args, actualOwnerWarningFlag()]);
        \\};
    );
}
fn expectDrainedClose(f: *Fixture, actual: *uv.PiUvFsRequest) !void {
    const info = uv.pi_uv_fs_request_info(actual);
    try std.testing.expectEqual(@as(c_int, 1), info.accepted);
    try std.testing.expectEqual(@as(c_int, 1), info.cleaned);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
    try std.testing.expectEqual(f.close_actual, f.close_end_actual);
    try std.testing.expectEqual(@as(usize, 1), f.close_end_references);
    try std.testing.expect(f.close_end_uncounted and f.close_end_accepted_uncleaned);
}

test "native FileHandle owner constructor attaches the same native stream and transfers the real descriptor on release" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take();
    const handle = try f.create(descriptor, null, null);
    const data = handle.getBindingData();
    try std.testing.expect(handle.constructed and handle.stream_initialized and handle.attached);
    try std.testing.expectEqual(@as(u32, 4), handle.wrap.provider);
    try std.testing.expect(handle.wrap.wants_weak and handle.wrap.strong_wrapper == null);
    try std.testing.expectEqual(@as(usize, 0), handle.wrap.native_references);
    try std.testing.expect(f.registry().unwrap(f.primary_wrapper.?) == &handle.wrap);
    try std.testing.expect(f.registry().streamPointer(f.primary_wrapper.?) ==
        @as(*anyopaque, @ptrCast(&handle.stream)));
    try std.testing.expectEqual(@as(c_uint, 1), data.pointer_data.?.strong_count);
    try std.testing.expectEqual(@as(c_int, descriptor), handle.getFD());
    try std.testing.expect(handle.isAlive() and !handle.isClosing());
    try std.testing.expectEqual(@as(i64, -1), handle.read_state.read_offset);
    try std.testing.expectEqual(@as(i64, -1), handle.read_state.read_length);
    try std.testing.expect(!handle.read_state.reading and handle.read_state.current_read == null);
    file.descriptor = try f.releaseDescriptor();
    try std.testing.expectEqual(descriptor, file.descriptor);
    try std.testing.expectEqual(@as(c_int, 0), File.status(file.descriptor));
    try std.testing.expect(handle.read_state.closed and !handle.read_state.closing);
    try std.testing.expectEqual(@as(c_int, physical.UV_EOF), try f.start());
    f.collectHandle();
    try std.testing.expectEqual(@as(c_uint, 0), data.pointer_data.?.strong_count);
    try std.testing.expectEqual(@as(usize, 0), f.sync_begins);
    try std.testing.expectEqual(@as(usize, 0), f.close_begins);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
    try file.close();
    try std.testing.expectEqual(@as(c_int, physical.UV_EBADF), File.status(descriptor));
}

test "native FileHandle owner optional Number IntegerValue follows pinned V8 truncation and saturation" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const Case = struct { offset: f64, length: f64, want_offset: i64, want_length: i64 };
    const cases = [_]Case{
        .{ .offset = std.math.nan(f64), .length = -0.0, .want_offset = 0, .want_length = 0 },
        .{ .offset = std.math.inf(f64), .length = -std.math.inf(f64),
            .want_offset = std.math.maxInt(i64), .want_length = std.math.minInt(i64) },
        .{ .offset = 0x1p63, .length = -0x1p63,
            .want_offset = std.math.maxInt(i64), .want_length = std.math.minInt(i64) },
        .{ .offset = 1.75, .length = -1.75, .want_offset = 1, .want_length = -1 },
        .{ .offset = 0.75, .length = -0.75, .want_offset = 0, .want_length = 0 },
    };
    for (cases) |item| {
        const handle = try f.create(file.take(), item.offset, item.length);
        try std.testing.expectEqual(item.want_offset, handle.read_state.read_offset);
        try std.testing.expectEqual(item.want_length, handle.read_state.read_length);
        file.descriptor = try f.releaseDescriptor();
        f.collectHandle();
    }
    try std.testing.expectEqual(@as(c_int, 0), File.status(file.descriptor));
    try std.testing.expectEqual(@as(usize, 0), f.sync_begins);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
}

test "native FileHandle owner non Number optional arguments perform no guest coercion" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\globalThis.ownerCoercions = 0;
        \\globalThis.ownerNotNumber = { valueOf() { ++ownerCoercions; throw Error("coercion"); },
        \\  toString() { ++ownerCoercions; throw Error("coercion"); } };
    );
    const argument = try f.global("ownerNotNumber");
    defer f.engine.freeValue(argument);
    const args = [_]c.JSValue{ c.JS_NewInt32(f.engine.context, file.take()), argument, argument };
    const handle = try f.createArgs(&args);
    try std.testing.expectEqual(@as(i64, -1), handle.read_state.read_offset);
    try std.testing.expectEqual(@as(i64, -1), handle.read_state.read_length);
    try f.expect("ownerCoercions === 0");
    file.descriptor = try f.releaseDescriptor();
    f.collectHandle();
}

test "native FileHandle owner keeps the full public method template an explicit dependency" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try std.testing.expectError(error.ActualFileHandleCallbackTemplateRequired,
        support.templates.constructor(f.engine, f.template_owner.?, .filehandle));
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
    try std.testing.expectEqual(@as(usize, 0), f.sync_begins);
    try std.testing.expectEqual(@as(usize, 0), f.close_begins);
}

test "native FileHandle owner explicit close keeps one Promise and one actual CLOSE request through cleanup" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take();
    const handle = try f.create(descriptor, null, null);
    const promise = try handle.closePromise();
    defer f.engine.freeValue(promise);
    const again = try handle.closePromise();
    defer f.engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, promise, again));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, promise));
    try std.testing.expect(handle.read_state.closing and !handle.read_state.closed);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try std.testing.expectEqual(@as(usize, 1), f.queueCount());
    try std.testing.expectEqual(@as(usize, 1), f.close_begins);
    try std.testing.expectEqual(@as(u32, 5), f.close_begin_provider);
    try std.testing.expectEqual(@as(c_int, uv.PI_UV_FS_CLOSE), f.close_begin_kind);
    try std.testing.expect(f.close_begin_unsubmitted and f.close_begin_globals);
    const actual = try retainCloseStorage(&f);
    defer uv.pi_uv_fs_request_release(actual);
    try f.pumpIo();
    try expectClosed(&f, descriptor);
    try expectDrainedClose(&f, actual);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.engine.context, promise));
    const result = c.JS_PromiseResult(f.engine.context, promise);
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsUndefined(result));
    const after = try handle.closePromise();
    defer f.engine.freeValue(after);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, promise, after));
    f.collectHandle();
    try std.testing.expectEqual(@as(usize, 0), f.sync_begins);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
}

test "native FileHandle owner accepted bad descriptor close rejects the real UVException after AfterClose" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.create(invalid_descriptor, null, null);
    const promise = try handle.closePromise();
    defer f.engine.freeValue(promise);
    c.JS_PromiseMarkAsHandled(f.engine.context, promise);
    const actual = try retainCloseStorage(&f);
    defer uv.pi_uv_fs_request_release(actual);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try f.pumpIo();
    try expectClosed(&f, invalid_descriptor);
    try expectDrainedClose(&f, actual);
    try std.testing.expectEqual(@as(i64, physical.UV_EBADF), uv.pi_uv_fs_request_info(actual).result);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(f.engine.context, promise));
    const reason = c.JS_PromiseResult(f.engine.context, promise);
    defer f.engine.freeValue(reason);
    try f.expose("ownerRejected", reason);
    try f.expose("ownerEBADF", c.JS_NewInt32(f.engine.context, physical.UV_EBADF));
    try f.expect("ownerRejected instanceof Error && ownerRejected.code === 'EBADF' && " ++
        "ownerRejected.errno === ownerEBADF && ownerRejected.syscall === 'close'");
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expect(!c.JS_HasException(f.engine.context) and f.engine.captured_exception == null);
}

test "native FileHandle owner real stopped service admission rejects without fabricating completion or closing the descriptor" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take();
    const handle = try f.create(descriptor, null, null);
    // Stop the real native worker, while the real Controller/Hub remains live.
    // Storage creation succeeds; actual command admission returns ECANCELED.
    try std.testing.expectEqual(@as(c_int, 0), uv.pi_uv_service_stop(f.controller.?.service));
    const promise = try handle.closePromise();
    defer f.engine.freeValue(promise);
    c.JS_PromiseMarkAsHandled(f.engine.context, promise);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(f.engine.context, promise));
    try std.testing.expect(handle.read_state.closing and !handle.read_state.closed);
    try std.testing.expectEqual(descriptor, handle.getFD());
    try std.testing.expectEqual(@as(c_int, 0), File.status(descriptor));
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
    try std.testing.expectEqual(@as(usize, 1), f.close_begins);
    try std.testing.expectEqual(@as(usize, 0), f.close_ends);
    const reason = c.JS_PromiseResult(f.engine.context, promise);
    defer f.engine.freeValue(reason);
    try f.expose("ownerAdmissionError", reason);
    try f.expect("ownerAdmissionError instanceof Error && ownerAdmissionError.code === 'ECANCELED' && " ++
        "ownerAdmissionError.syscall === 'close'");
    const repeated = try handle.closePromise();
    defer f.engine.freeValue(repeated);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, promise, repeated));
    // Original Release resets flags through AfterClose and transfers the fd;
    // it is necessary before the original destructor CHECK(!closing_).
    file.descriptor = try f.releaseDescriptor();
    try std.testing.expectEqual(descriptor, file.descriptor);
    f.collectHandle();
    try std.testing.expectEqual(@as(usize, 0), f.sync_begins);
    try file.close();
}

test "native FileHandle owner retained CloseReq wrapper loses native state after both callback references retire" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.installInitRecorder();
    _ = try f.create(file.take(), null, null);
    const promise = try (try f.handle()).closePromise();
    defer f.engine.freeValue(promise);
    const wrapper = try f.value("ownerCloseResources[0]");
    defer f.engine.freeValue(wrapper);
    try std.testing.expect(f.registry().unwrap(wrapper) == &(try f.pendingClose()).wrap);
    const actual = try retainCloseStorage(&f);
    defer uv.pi_uv_fs_request_release(actual);
    try f.pumpIo();
    try expectDrainedClose(&f, actual);
    try std.testing.expect(f.registry().unwrap(wrapper) == null);
    try std.testing.expectEqual(f.registry().classId(.filehandleclosereq), c.JS_GetClassID(wrapper));
    try f.expect("ownerInitEvents.length === 2 && ownerInitEvents[0][0] === 'FILEHANDLE' && " ++
        "ownerInitEvents[1][0] === 'FILEHANDLECLOSEREQ' && " ++
        "ownerInitEvents[0][1] !== ownerInitEvents[1][1]");
}

test "native FileHandle owner CloseReq Global keeps the handle and weak BindingData alive until actual completion" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take();
    const handle = try f.create(descriptor, null, null);
    const data = handle.getBindingData();
    const promise = try handle.closePromise();
    defer f.engine.freeValue(promise);
    f.dropBindingTarget();
    f.collectHandle();
    try std.testing.expect(support.binding.get(f.registry()) == data);
    try std.testing.expectEqual(@as(c_uint, 1), data.pointer_data.?.strong_count);
    try std.testing.expect(handle.read_state.closing);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    const actual = try retainCloseStorage(&f);
    defer uv.pi_uv_fs_request_release(actual);
    try f.pumpIo();
    c.JS_RunGC(f.engine.runtime);
    // Neither native pointer is dereferenced after their actual last owners die.
    try std.testing.expect(support.binding.get(f.registry()) == null);
    try std.testing.expectEqual(@as(c_int, physical.UV_EBADF), File.status(descriptor));
    try expectDrainedClose(&f, actual);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.engine.context, promise));
    try std.testing.expectEqual(@as(usize, 0), f.sync_begins);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
}

test "native FileHandle owner GC closes synchronously and the warning ticket retains no handle or BindingData" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take();
    _ = try f.create(descriptor, null, null);
    f.dropBindingTarget();
    f.collectHandle();
    try std.testing.expectEqual(@as(c_int, physical.UV_EBADF), File.status(descriptor));
    try std.testing.expect(support.binding.get(f.registry()) == null);
    try std.testing.expectEqual(@as(usize, 1), f.sync_begins);
    try std.testing.expectEqual(@as(usize, 1), f.sync_ends);
    try std.testing.expectEqual(@as(usize, 0), f.close_begins);
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
    try std.testing.expectEqual(@as(usize, 1), f.queue.?.count);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.refed_count);
    try std.testing.expect(!f.queue.?.referenced());
}

test "native FileHandle owner GC warnings use the live process function and consume the Environment deprecation flag once" {
    var first: File = undefined; try first.init(); defer first.deinit();
    var second: File = undefined; try second.init(); defer second.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd1 = first.take();
    const fd2 = second.take();
    _ = try f.create(fd1, null, null);
    f.collectHandle();
    // Install after publication: the ticket must use the live function at run.
    try warningRecorder(&f);
    try f.expose("ownerFirstFd", c.JS_NewInt32(f.engine.context, fd1));
    try f.expose("ownerSecondFd", c.JS_NewInt32(f.engine.context, fd2));
    try std.testing.expect(f.env().emit_filehandle_warning);
    try std.testing.expect(try f.queue.?.drain(f.engine, .check));
    try std.testing.expect(!f.env().emit_filehandle_warning);
    _ = try f.create(fd2, null, null);
    f.collectHandle();
    try std.testing.expect(try f.queue.?.drain(f.engine, .check));
    try f.expect(
        \\ownerWarnings.length === 3 &&
        \\ownerWarnings[0][0].length === 1 &&
        \\ownerWarnings[0][0][0] === "Closing file descriptor " + ownerFirstFd + " on garbage collection" &&
        \\ownerWarnings[0][1] === true &&
        \\ownerWarnings[1][0].length === 3 &&
        \\ownerWarnings[1][0][1] === "DeprecationWarning" &&
        \\ownerWarnings[1][0][2] === "DEP0137" && ownerWarnings[1][1] === false &&
        \\ownerWarnings[2][0][0] === "Closing file descriptor " + ownerSecondFd + " on garbage collection" &&
        \\ownerWarnings[2][1] === false
    );
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
    try std.testing.expectEqual(@as(usize, 0), f.caught_count);
}

test "native FileHandle owner ordinary GC warning throw still reaches deprecation and preserves the exact caught reason" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.evaluate(
        \\globalThis.ownerWarningReason = { ordinaryWarning: true };
        \\globalThis.ownerWarningCalls = [];
        \\process.emitWarning = function(...args) {
        \\  ownerWarningCalls.push([args, actualOwnerWarningFlag()]);
        \\  if (ownerWarningCalls.length === 1) throw ownerWarningReason;
        \\};
    );
    const reason = try f.global("ownerWarningReason");
    defer f.engine.freeValue(reason);
    _ = try f.create(file.take(), null, null);
    f.collectHandle();
    try std.testing.expect(try f.queue.?.drain(f.engine, .check));
    try std.testing.expectEqual(@as(usize, 1), f.caught_count);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, reason, f.caught[0]));
    try std.testing.expect(!f.env().emit_filehandle_warning);
    try f.expect("ownerWarningCalls.length === 2 && ownerWarningCalls[0][1] === true && " ++
        "ownerWarningCalls[1][0][2] === 'DEP0137' && ownerWarningCalls[1][1] === false");
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
}

test "native FileHandle owner failed GC close queues one refed actual UVException ticket" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try warningRecorder(&f);
    _ = try f.create(invalid_descriptor, null, null);
    f.collectHandle();
    try std.testing.expectEqual(@as(usize, 1), f.sync_begins);
    try std.testing.expectEqual(@as(usize, 1), f.sync_ends);
    try std.testing.expectEqual(@as(usize, 1), f.queue.?.count);
    try std.testing.expectEqual(@as(usize, 1), f.queue.?.refed_count);
    try std.testing.expect(f.queue.?.referenced());
    try std.testing.expect(try f.queue.?.drain(f.engine, .check));
    try std.testing.expectEqual(@as(usize, 1), f.caught_count);
    try f.expose("ownerGcError", f.caught[0]);
    try f.expect("ownerGcError instanceof Error && ownerGcError.code === 'EBADF' && " ++
        "ownerGcError.syscall === 'close' && ownerGcError.message === " ++
        "'EBADF: Closing file descriptor 2147483647 on garbage collection failed, close' && " ++
        "ownerWarnings.length === 0");
    try std.testing.expect(f.env().emit_filehandle_warning);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.refed_count);
}

test "native FileHandle owner cleanup skips unrefed GC warning execution and destroys its native capture" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try warningRecorder(&f);
    const descriptor = file.take();
    _ = try f.create(descriptor, null, null);
    f.collectHandle();
    try std.testing.expectEqual(@as(usize, 1), f.queue.?.count);
    f.env().can_call_into_js = false;
    try f.queue.?.close(f.engine);
    try std.testing.expect(f.queue.?.engine == null);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.refed_count);
    try std.testing.expectEqual(@as(usize, 0), f.caught_count);
    try std.testing.expect(f.env().emit_filehandle_warning);
    try std.testing.expectEqual(@as(c_int, physical.UV_EBADF), File.status(descriptor));
    try f.expect("ownerWarnings.length === 0");
}

test "native FileHandle owner GC uses the retained real service for synchronous close after worker join" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take();
    _ = try f.create(descriptor, null, null);
    f.stopIo();
    try std.testing.expect(f.controller == null);
    try std.testing.expectEqual(@as(c_int, 0), File.status(descriptor));
    f.collectHandle();
    try std.testing.expectEqual(@as(c_int, physical.UV_EBADF), File.status(descriptor));
    try std.testing.expectEqual(@as(usize, 1), f.sync_begins);
    try std.testing.expectEqual(@as(usize, 1), f.sync_ends);
    try std.testing.expectEqual(@as(usize, 1), f.queue.?.count);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.refed_count);
}

test "native FileHandle owner consumes the real read engine and reuses its physical ReadWrap across concrete handles" {
    var first: File = undefined; try first.init(); defer first.deinit();
    var second: File = undefined; try second.init(); defer second.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle1 = try f.create(first.take(), 1, 2);
    const data = handle1.getBindingData();
    try std.testing.expectEqual(@as(c_int, 0), try f.start());
    const read = handle1.read_state.current_read.?;
    const actual = read.actual.?;
    try f.pumpIo();
    try std.testing.expectEqual(@as(i32, 2), f.last_nread);
    try std.testing.expectEqualSlices(u8, "BC", f.read_bytes[0..f.last_read_length]);
    try std.testing.expect(!handle1.read_state.reading and handle1.read_state.current_read == null);
    try std.testing.expect(data.file_handle_read_wrap_freelist.items[0] == &read.wrap);
    try closeAndPump(&f);
    f.collectHandle();
    try std.testing.expectEqual(@as(c_uint, 0), data.pointer_data.?.strong_count);
    const handle2 = try f.create(second.take(), 4, 2);
    try std.testing.expectEqual(@as(c_int, 0), try f.start());
    try std.testing.expect(handle2.read_state.current_read == read);
    try std.testing.expect(read.file_handle == handle2);
    try std.testing.expect(read.actual == actual);
    try f.pumpIo();
    try std.testing.expectEqualSlices(u8, "EF", f.read_bytes[0..f.last_read_length]);
    try std.testing.expectEqual(@as(usize, 2), f.read_begins);
    try std.testing.expectEqual(@as(usize, 2), f.read_ends);
    try std.testing.expect(f.read_ids[0] != f.read_ids[1]);
    try std.testing.expectEqual(f.read_requests[0], f.read_requests[1]);
    try std.testing.expect(f.read_member_exact);
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
    try std.testing.expectEqual(@as(usize, 2), f.before_read_callbacks);
    try std.testing.expectEqual(@as(usize, 2), f.after_read_callbacks);
    try closeAndPump(&f);
    f.collectHandle();
    try std.testing.expectEqual(@as(usize, 0), f.sync_begins);
}

test "native FileHandle owner real throwing before hook still settles close and runs after with the original pending identity" {
    for ([_]bool{ false, true }) |reject| {
        var file: File = undefined; try file.init(); defer file.deinit();
        var f: Fixture = undefined; try f.init(); defer f.deinit();
        try f.installThrowingBeforeHook();
        const descriptor = if (reject) invalid_descriptor else file.take();
        const handle = try f.create(descriptor, null, null);
        const promise = try handle.closePromise();
        defer f.engine.freeValue(promise);
        c.JS_PromiseMarkAsHandled(f.engine.context, promise);
        const id = (try f.pendingClose()).wrap.async_id;
        const actual = try retainCloseStorage(&f);
        defer uv.pi_uv_fs_request_release(actual);
        try std.testing.expectError(error.JavaScriptException, f.pumpIo());
        const caught = try f.takeCaught();
        defer f.engine.freeValue(caught);
        try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, caught, f.selected_hook_reason.?));
        try std.testing.expectEqual(@as(usize, 1), f.hook_rethrows);
        try std.testing.expectEqual(if (reject) c.JS_PROMISE_REJECTED else c.JS_PROMISE_FULFILLED,
            c.JS_PromiseState(f.engine.context, promise));
        try std.testing.expectEqual(@as(usize, 1), f.env().callback_depth);
        try std.testing.expectEqual(@as(u32, 1), f.env().field(.stack_length).*);
        try expectClosed(&f, descriptor);
        try expectDrainedClose(&f, actual);
        try f.expose("ownerCloseId", c.JS_NewFloat64(f.engine.context, id));
        try f.expect("ownerBeforeIds.length === 1 && ownerAfterIds.length === 1 && " ++
            "ownerBeforeIds[0] === ownerCloseId && ownerAfterIds[0] === ownerCloseId");
        if (reject) {
            const result = c.JS_PromiseResult(f.engine.context, promise);
            defer f.engine.freeValue(result);
            try std.testing.expect(!c.JS_IsStrictEqual(f.engine.context, result, caught));
            try f.expose("ownerRejectedAfterBefore", result);
            try f.expect("ownerRejectedAfterBefore.code === 'EBADF' && " ++
                "ownerRejectedAfterBefore.syscall === 'close'");
        }
    }
}

test "native FileHandle owner real Hub shutdown drains accepted close without settling its guest Promise" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take();
    const handle = try f.create(descriptor, null, null);
    const promise = try handle.closePromise();
    defer f.engine.freeValue(promise);
    const actual = try retainCloseStorage(&f);
    defer uv.pi_uv_fs_request_release(actual);
    // Wait only for the real worker's close event; do not deliver it to JS.
    // This removes shutdown cancellation timing from the selected control.
    try f.waitNativeQueued(1);
    try std.testing.expectEqual(@as(i64, 0), uv.pi_uv_fs_request_info(actual).result);
    f.stopIo();
    try expectClosed(&f, descriptor);
    try expectDrainedClose(&f, actual);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.engine.context, promise));
    try std.testing.expectEqual(@as(usize, 0), f.sync_begins);
    f.collectHandle();
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
}
