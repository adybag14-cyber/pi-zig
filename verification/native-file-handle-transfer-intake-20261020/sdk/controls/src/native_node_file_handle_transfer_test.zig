//! Focused native FileHandle descriptor transfer controls.
//! The shared fixture supplies a real present-object FileHandle, Environment,
//! libuv descriptor, request graph and BindingData. These controls do not
//! publish the missing full FileHandle template or worker message broker.
//! Trace entrypoints below are explicit process-lifetime TEST observers of
//! actual close/status operations, not a production trace/bootstrap owner.
//! No control executes until Root authorizes its separate native build/run.
const std = @import("std");
const support = @import("native_node_file_handle_owner_test_support.zig");
const transfer = @import("extensions/native_node_file_handle_transfer.zig");
const a = support.a;
const c = support.c;
const Fixture = support.Fixture;
const File = support.File;
const physical = support.physical;

extern fn pi_node_diagnostic_context_enter(?*c.JSContext) ?*c.JSContext;
extern fn pi_node_diagnostic_context_leave(?*c.JSContext) void;
extern fn pi_node_diagnostic_context_current() ?*c.JSContext;

/// Only this serial test executable uses these observations. The two function
/// addresses are process-lifetime code; the transfer packet receives no test
/// pointer, Environment, Engine, service or JS value. Cross-thread observations
/// are read only after the real native thread joins.
const Observation = struct {
    descriptor: c_int = -1,
    begins: usize = 0,
    ends: usize = 0,
    order: u32 = 0,
    before_status: c_int = 12345,
    after_status: c_int = 12345,
    begin_context: usize = 0,
    end_context: usize = 0,
};
var observed: Observation = .{};
fn contextAddress() usize {
    const context = pi_node_diagnostic_context_current() orelse return 0;
    return @intFromPtr(context);
}
fn beginClose() callconv(.c) void {
    observed.begins += 1;
    observed.order = (observed.order << 4) | 1;
    observed.before_status = File.status(observed.descriptor);
    observed.begin_context = contextAddress();
}
fn endClose() callconv(.c) void {
    observed.ends += 1;
    observed.order = (observed.order << 4) | 2;
    observed.after_status = File.status(observed.descriptor);
    observed.end_context = contextAddress();
}
const observed_trace: transfer.Trace = .{
    .begin_sync_close = beginClose, .end_sync_close = endClose,
};
fn observe(descriptor: c_int) !void {
    // fd == 0 is deliberately not replaced or closed by this fixture.
    // The original strict > 0 destructor branch is pinned in the source map.
    try std.testing.expect(descriptor > 0);
    observed = .{ .descriptor = descriptor };
}
fn expectOneClose(context: ?*c.JSContext) !void {
    try std.testing.expectEqual(@as(usize, 1), observed.begins);
    try std.testing.expectEqual(@as(usize, 1), observed.ends);
    try std.testing.expectEqual(@as(u32, 0x12), observed.order);
    try std.testing.expectEqual(@as(c_int, 0), observed.before_status);
    try std.testing.expectEqual(@as(c_int, physical.UV_EBADF), observed.after_status);
    const address: usize = if (context) |actual| @intFromPtr(actual) else 0;
    try std.testing.expectEqual(address, observed.begin_context);
    try std.testing.expectEqual(address, observed.end_context);
}
fn send(f: *Fixture) !transfer.Owned {
    var output: transfer.Owned = .{};
    errdefer output.deinit(null);
    const ignored = try a.expression(f.engine, struct {
        fn body(s: *a.Scope, fixture: *Fixture, result: *transfer.Owned) !c.JSValue {
            result.* = try transfer.transferForMessaging(s, try fixture.handle(), observed_trace);
            return c.pi_js_undefined();
        }
    }.body, .{ f, &output });
    f.engine.freeValue(ignored);
    return output;
}
fn borrowedInputs(handle: *support.Handle) support.owner.Inputs {
    // The actual fixture separately retains these Controller/Queue/cache
    // owners. This borrowed copy may outlive the selected sender Handle.
    return .{
        .controller = handle.controller,
        .immediate_queue = handle.immediate_queue,
        .handle_string = handle.handle_string,
        .read_trace = handle.read_trace,
        .close_trace = handle.close_trace,
        .stream = handle.stream_operations,
    };
}
fn receive(f: *Fixture, packet: *transfer.Owned,
    inputs: support.owner.Inputs) !?transfer.StrongHandle
{
    var output: ?transfer.StrongHandle = null;
    errdefer if (output) |value| {
        var owned = value;
        owned.deinit() catch @panic("unexpected transfer receiver cleanup failed");
    };
    const ignored = try a.expression(f.engine, struct {
        fn body(s: *a.Scope, fixture: *Fixture, actual: *transfer.Owned,
            borrowed: support.owner.Inputs, result: *?transfer.StrongHandle) !c.JSValue
        {
            result.* = try actual.deserialize(s, fixture.registry(), borrowed);
            return c.pi_js_undefined();
        }
    }.body, .{ f, packet, inputs, &output });
    f.engine.freeValue(ignored);
    return output;
}

test "native FileHandle transfer changes only the live closed member and retains the real descriptor" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    const handle = try f.create(descriptor, 2, 4);
    const data = handle.binding_data;
    const wrapper = f.primary_wrapper.?;
    const stream_pointer = f.registry().streamPointer(wrapper);
    const async_id = handle.wrap.async_id;
    const trigger_id = handle.wrap.trigger_async_id;
    const native_references = handle.wrap.native_references;
    const data_references = data.?.pointer_data.?.strong_count;
    const context_frame = handle.wrap.context_frame;
    try std.testing.expectEqual(transfer.TransferMode.transferable,
        transfer.getTransferMode(handle));
    var packet = try send(&f); defer packet.deinit(null);
    try std.testing.expect(handle.read_state.closed);
    try std.testing.expect(!handle.read_state.closing and !handle.read_state.reading);
    try std.testing.expect(handle.read_state.current_read == null);
    try std.testing.expectEqual(descriptor, handle.getFD());
    try std.testing.expectEqual(@as(i64, 2), handle.read_state.read_offset);
    try std.testing.expectEqual(@as(i64, 4), handle.read_state.read_length);
    try std.testing.expect(handle.binding_data == data);
    try std.testing.expectEqual(data_references, data.?.pointer_data.?.strong_count);
    try std.testing.expectEqual(native_references, handle.wrap.native_references);
    try std.testing.expectEqual(async_id, handle.wrap.async_id);
    try std.testing.expectEqual(trigger_id, handle.wrap.trigger_async_id);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context,
        context_frame, handle.wrap.context_frame));
    try std.testing.expect(f.registry().unwrap(wrapper) == &handle.wrap);
    try std.testing.expect(f.registry().streamPointer(wrapper) == stream_pointer);
    try std.testing.expectEqual(@as(?c_int, descriptor), packet.descriptor(f.engine.context));
    try std.testing.expectEqual(@as(c_int, 0), File.status(descriptor));
    try std.testing.expectEqual(transfer.TransferMode.disallow_clone_and_transfer,
        transfer.getTransferMode(handle));
    try std.testing.expectEqual(@as(usize, 0), observed.begins);
    try std.testing.expectEqual(@as(usize, 0), f.sync_begins);
    try std.testing.expectEqual(@as(usize, 0), f.close_begins);
    try std.testing.expectEqual(@as(usize, 0), f.read_callbacks);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
    packet.deinit(f.engine.context);
    try expectOneClose(f.engine.context);
}

test "native FileHandle transfer admission follows real ReadStart and ReadStop with the original pending request" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    const handle = try f.create(descriptor, 0, 4);
    try std.testing.expectEqual(@as(c_int, 0), try f.start());
    const request = handle.read_state.current_read.?;
    const actual = request.actual.?;
    try std.testing.expectEqual(transfer.TransferMode.disallow_clone_and_transfer,
        transfer.getTransferMode(handle));
    // Finish physical I/O before inspecting its queued, unconsumed completion.
    try f.waitNativeQueued(1);
    try std.testing.expectEqual(@as(c_int, 0), handle.readStop());
    try std.testing.expect(handle.read_state.current_read == request);
    try std.testing.expectEqual(transfer.TransferMode.transferable,
        transfer.getTransferMode(handle));
    var packet = try send(&f); defer packet.deinit(null);
    try std.testing.expect(handle.read_state.current_read == request);
    try std.testing.expect(request.actual == actual);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try std.testing.expectEqual(@as(usize, 0), f.read_callbacks);
    try f.pumpIo();
    try std.testing.expect(handle.read_state.current_read == null);
    try std.testing.expect(handle.read_state.closed and !handle.read_state.reading);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expectEqual(@as(usize, 1), f.read_begins);
    try std.testing.expectEqual(@as(usize, 1), f.read_ends);
    try std.testing.expectEqual(@as(usize, 1), f.read_callbacks);
    try std.testing.expectEqualStrings("ABCD", f.read_bytes[0..f.last_read_length]);
    try std.testing.expectEqual(@as(c_int, 0), File.status(descriptor));
    packet.deinit(f.engine.context);
    try expectOneClose(f.engine.context);
}

test "native FileHandle transfer rejects real closing and closed state without weakening the close request" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    const handle = try f.create(descriptor, null, null);
    const promise = try handle.closePromise();
    defer f.engine.freeValue(promise);
    c.JS_PromiseMarkAsHandled(f.engine.context, promise);
    try std.testing.expect(handle.read_state.closing and !handle.read_state.closed);
    try std.testing.expectEqual(transfer.TransferMode.disallow_clone_and_transfer,
        transfer.getTransferMode(handle));
    try std.testing.expect((try f.pendingClose()).actual != null);
    try f.pumpIo();
    try std.testing.expect(handle.read_state.closed and !handle.read_state.closing);
    try std.testing.expectEqual(transfer.TransferMode.disallow_clone_and_transfer,
        transfer.getTransferMode(handle));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED,
        c.JS_PromiseState(f.engine.context, promise));
    try std.testing.expectEqual(@as(c_int, physical.UV_EBADF), File.status(descriptor));
    try std.testing.expectEqual(@as(usize, 1), f.close_begins);
    try std.testing.expectEqual(@as(usize, 1), f.close_ends);
    try std.testing.expectEqual(@as(usize, 0), observed.begins);
}

test "native FileHandle transfer admission excludes the real released descriptor state" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    const handle = try f.create(descriptor, null, null);
    file.descriptor = try f.releaseDescriptor();
    try std.testing.expectEqual(descriptor, file.descriptor);
    try std.testing.expectEqual(@as(c_int, -1), handle.getFD());
    try std.testing.expectEqual(transfer.TransferMode.disallow_clone_and_transfer,
        transfer.getTransferMode(handle));
    try std.testing.expectEqual(@as(c_int, 0), File.status(descriptor));
    try std.testing.expectEqual(@as(usize, 0), observed.begins);
    try file.close();
}

test "native FileHandle transfer packet move preserves one native allocation and closes once" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    _ = try f.create(descriptor, null, null);
    const used_before = c.pi_js_native_memory_used(f.engine.native_memory_owner);
    var first = try send(&f); defer first.deinit(null);
    const charged = c.pi_js_native_memory_used(f.engine.native_memory_owner);
    try std.testing.expect(charged > used_before);
    var second = first.move(); defer second.deinit(null);
    try std.testing.expect(first.packet == null);
    try std.testing.expectEqual(@as(?c_int, null), first.descriptor(null));
    first.deinit(f.engine.context);
    try std.testing.expectEqual(charged, c.pi_js_native_memory_used(f.engine.native_memory_owner));
    try std.testing.expectEqual(@as(usize, 0), observed.begins);
    try std.testing.expectEqual(@as(?c_int, descriptor), second.descriptor(null));
    second.deinit(f.engine.context);
    try expectOneClose(f.engine.context);
    try std.testing.expectEqual(used_before, c.pi_js_native_memory_used(f.engine.native_memory_owner));
    second.deinit(null);
    try expectOneClose(f.engine.context);
}

test "native FileHandle transfer packet survives actual sender GC and weak BindingData retirement" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    _ = try f.create(descriptor, null, null);
    var packet = try send(&f); defer packet.deinit(null);
    f.dropBindingTarget();
    f.collectHandle();
    try std.testing.expect(support.binding.get(f.registry()) == null);
    try std.testing.expectEqual(@as(c_int, 0), File.status(descriptor));
    try std.testing.expectEqual(@as(usize, 0), f.sync_begins);
    try std.testing.expectEqual(@as(usize, 0), f.close_begins);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
    packet.deinit(f.engine.context);
    try expectOneClose(f.engine.context);
}

test "native FileHandle transfer allocation alone retains its native memory domain after Engine teardown" {
    const owners_before = c.pi_js_native_memory_owners();
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    _ = try f.create(descriptor, null, null);
    var packet = try send(&f); defer packet.deinit(null);
    const memory = f.engine.native_memory_owner;
    f.deinit();
    try std.testing.expect(!f.engine_alive and f.environment == null);
    try std.testing.expectEqual(owners_before + 1, c.pi_js_native_memory_owners());
    try std.testing.expect(c.pi_js_native_memory_used(memory) > 0);
    try std.testing.expectEqual(@as(?c_int, descriptor), packet.descriptor(null));
    try std.testing.expectEqual(@as(c_int, 0), File.status(descriptor));
    packet.deinit(null);
    try expectOneClose(null);
    try std.testing.expectEqual(owners_before, c.pi_js_native_memory_owners());
}

const NativeDestroy = struct {
    packet: transfer.Owned,
    entered_empty: bool = false,
    left_empty: bool = false,
    fn run(self: *NativeDestroy) void {
        self.entered_empty = pi_node_diagnostic_context_current() == null;
        self.packet.deinit(null);
        self.left_empty = pi_node_diagnostic_context_current() == null;
    }
};

test "native FileHandle transfer abandoned on a real different thread closes after sender Engine retirement" {
    const owners_before = c.pi_js_native_memory_owners();
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    _ = try f.create(descriptor, null, null);
    var packet = try send(&f); defer packet.deinit(null);
    f.deinit();
    try std.testing.expectEqual(owners_before + 1, c.pi_js_native_memory_owners());
    var worker: NativeDestroy = .{ .packet = packet.move() };
    defer worker.packet.deinit(null);
    const thread = try std.Thread.spawn(.{}, NativeDestroy.run, .{&worker});
    thread.join();
    try std.testing.expect(worker.entered_empty and worker.left_empty);
    try std.testing.expect(worker.packet.packet == null and packet.packet == null);
    try expectOneClose(null);
    try std.testing.expectEqual(owners_before, c.pi_js_native_memory_owners());
    try std.testing.expect(pi_node_diagnostic_context_current() == null);
}

test "native FileHandle transfer destructor null admission masks and restores an outer real context" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    _ = try f.create(descriptor, null, null);
    var packet = try send(&f); defer packet.deinit(null);
    const previous = pi_node_diagnostic_context_enter(f.engine.context);
    defer pi_node_diagnostic_context_leave(previous);
    try std.testing.expectEqual(@as(?c_int, descriptor), packet.descriptor(null));
    try std.testing.expect(pi_node_diagnostic_context_current() == f.engine.context);
    packet.deinit(null);
    try expectOneClose(null);
    try std.testing.expect(pi_node_diagnostic_context_current() == f.engine.context);
}

test "native FileHandle transfer native member and destructor calls preserve an actual current exception" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    _ = try f.create(descriptor, null, null);
    var packet = try send(&f); defer packet.deinit(null);
    const reason = try f.value("({ nativeTransferPending: true })");
    defer f.engine.freeValue(reason);
    _ = c.JS_Throw(f.engine.context, a.duplicate(f.engine, reason));
    defer if (c.JS_HasException(f.engine.context)) {
        const remaining = c.JS_GetException(f.engine.context);
        f.engine.freeValue(remaining);
    };
    try std.testing.expect(c.JS_HasException(f.engine.context));
    try std.testing.expectEqual(@as(?c_int, descriptor), packet.descriptor(f.engine.context));
    packet.deinit(f.engine.context);
    try std.testing.expect(c.JS_HasException(f.engine.context));
    const actual = c.JS_GetException(f.engine.context);
    defer f.engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, actual, reason));
    try std.testing.expect(!c.JS_IsUncatchableError(actual));
    try std.testing.expect(!c.JS_HasException(f.engine.context));
    try expectOneClose(f.engine.context);
    try std.testing.expect(pi_node_diagnostic_context_current() == null);
}

test "native FileHandle transfer missing real BindingData consumes the packet and closes its descriptor" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    const handle = try f.create(descriptor, null, null);
    const inputs = borrowedInputs(handle);
    var packet = try send(&f); defer packet.deinit(null);
    f.dropBindingTarget();
    f.collectHandle();
    try std.testing.expect(support.binding.get(f.registry()) == null);
    if (try receive(&f, &packet, inputs)) |value| {
        var unexpected = value;
        try unexpected.deinit();
        return error.UnexpectedFileHandleTransferReceiverWithoutBindingData;
    }
    try std.testing.expect(packet.packet == null);
    try expectOneClose(f.engine.context);
    try std.testing.expectEqual(@as(c_int, physical.UV_EBADF), File.status(descriptor));
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
}

test "native FileHandle transfer disowns before the explicit missing full template boundary without inventing a receiver" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    const handle = try f.create(descriptor, null, null);
    const inputs = borrowedInputs(handle);
    const data = handle.binding_data;
    var packet = try send(&f); defer packet.deinit(null);
    if (receive(&f, &packet, inputs)) |value| {
        if (value) |result| {
            var unexpected = result;
            try unexpected.deinit();
        }
        return error.UnexpectedFullFileHandleTemplateInSelectedTransferSlice;
    } else |err| {
        try std.testing.expect(err == error.ActualFileHandleCallbackTemplateRequired);
    }
    try std.testing.expect(packet.packet == null);
    try std.testing.expect(handle.binding_data == data);
    try std.testing.expectEqual(@as(c_int, 0), File.status(descriptor));
    // Original fd_ = -1 precedes FileHandle::New. The failed construction
    // does not restore packet ownership. The fixture explicitly adopts and
    // closes this observed abandoned descriptor; production does not do so.
    file.descriptor = descriptor;
    try std.testing.expectEqual(@as(usize, 0), observed.begins);
    try std.testing.expectEqual(@as(usize, 0), observed.ends);
    try std.testing.expectEqual(@as(usize, 0), handle.wrap.native_references);
    try std.testing.expect(handle.read_state.closed);
    try std.testing.expect(!c.JS_HasException(f.engine.context));
    try file.close();
}

test "native FileHandle transfer strong result edges clone and move over the same actual weak wrapper" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const descriptor = file.take(); try observe(descriptor);
    const handle = try f.create(descriptor, null, null);
    const data = handle.getBindingData();
    var packet = try send(&f); defer packet.deinit(null);
    // Exercise the selected BaseObjectPtr edge directly over the actual
    // present-object constructor. This does not claim successful Deserialize
    // through the still-missing full FileHandle template.
    try handle.wrap.retainNative();
    var first: transfer.StrongHandle = .{ .handle = handle };
    defer first.deinit() catch @panic("first transfer strong edge cleanup failed");
    var second = try first.clone();
    defer second.deinit() catch @panic("second transfer strong edge cleanup failed");
    try std.testing.expectEqual(@as(usize, 2), handle.wrap.native_references);
    try std.testing.expect(handle.wrap.strong_wrapper != null);
    f.collectHandle();
    try std.testing.expect(first.get() == handle and second.get() == handle);
    try std.testing.expectEqual(@as(c_uint, 1), data.pointer_data.?.strong_count);
    try first.deinit();
    try std.testing.expectEqual(@as(usize, 1), handle.wrap.native_references);
    var moved = second.move();
    defer moved.deinit() catch @panic("moved transfer strong edge cleanup failed");
    try std.testing.expect(second.get() == null and moved.get() == handle);
    try second.deinit();
    try std.testing.expectEqual(@as(usize, 1), handle.wrap.native_references);
    try moved.deinit();
    c.JS_RunGC(f.engine.runtime);
    // The Handle is gone; only the independently live BindingData is read.
    try std.testing.expectEqual(@as(c_uint, 0), data.pointer_data.?.strong_count);
    try std.testing.expectEqual(@as(c_int, 0), File.status(descriptor));
    try std.testing.expectEqual(@as(usize, 0), f.sync_begins);
    try std.testing.expectEqual(@as(usize, 0), f.queue.?.count);
    packet.deinit(f.engine.context);
    try expectOneClose(f.engine.context);
}
