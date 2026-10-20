//! Source controls for the actual FileHandle read engine and owner composition.
//! No control substitutes its constructor template, uv request, queue or buffer.
//! The fixture's derived Handle is not full FileHandle close/GC qualification.
const std = @import("std");
const support = @import("native_node_file_handle_read_test_support.zig");
const a = support.a;
const c = support.c;
const uv = support.uv;
const native_uv = @import("extensions/native_node_stream_resource.zig").uv;
const Fixture = support.Fixture;
const File = support.File;
const Read = support.Read;

fn expectOutput(observed: support.Observation, result: i32, bytes: []const u8) !void {
    try std.testing.expectEqual(result, observed.nread);
    try std.testing.expectEqual(bytes.len, observed.length);
    try std.testing.expectEqualSlices(u8, bytes, observed.bytes[0..observed.length]);
    try std.testing.expect(observed.current_empty);
    try std.testing.expectEqual(@as(c_int, 0), observed.waiting);
}
fn expectDrained(f: *Fixture) !void {
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expectEqual(@as(usize, 0), f.env().managed_buffers.count());
    try std.testing.expect(f.handle.?.read_state.current_read == null);
    try std.testing.expect(f.begin_saw_member and f.begin_saw_undispatched);
    try std.testing.expect(f.end_saw_member and f.end_saw_uncounted and f.end_saw_uncleaned);
    try std.testing.expectEqual(f.begin_count, f.end_count);
}
fn resource(s: *a.Scope, f: *Fixture, wrapper: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine,
        try s.getKey(wrapper, try f.env().resourceSymbol()));
}
fn expectResourceHandle(s: *a.Scope, f: *Fixture, owner: c.JSValue,
    wrapper: c.JSValue) !c.JSValue
{
    const borrowed = try s.getKey(owner, f.handle_key.?);
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, borrowed, wrapper));
    return c.pi_js_undefined();
}

test "native FileHandle read closed and closing return EOF before read admission" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const state = &f.handle.?.read_state;
    state.closed = true;
    try std.testing.expectEqual(@as(c_int, native_uv.UV_EOF), try f.start());
    try std.testing.expect(!state.reading);
    state.closed = false;
    state.closing = true;
    try std.testing.expectEqual(@as(c_int, native_uv.UV_EOF), try f.start());
    try std.testing.expect(!state.reading);
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
    try std.testing.expectEqual(@as(usize, 0), f.read_count);
    try std.testing.expectEqual(@as(usize, 0), f.allocation_count);
    try expectDrained(&f);
}

test "native FileHandle zero length emits actual stream EOF without allocating a request" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.handle.?.read_state.read_length = 0;
    try std.testing.expectEqual(@as(c_int, 0), try f.start());
    try std.testing.expectEqual(@as(usize, 1), f.read_count);
    try expectOutput(f.observations[0], native_uv.UV_EOF, "");
    try std.testing.expectEqual(@as(usize, 0), f.observations[0].freelist);
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
    try std.testing.expectEqual(@as(usize, 0), f.allocation_count);
    try std.testing.expectEqual(@as(usize, 1), f.before_count);
    try std.testing.expectEqual(@as(usize, 1), f.after_count);
    try expectDrained(&f);
}

test "native FileHandle first read bypasses FSReqCallback construction and retains the real ReadWrap" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    try std.testing.expectEqual(@as(c_int, 0), try f.start());
    const actual = f.handle.?.read_state.current_read.?;
    const pointer = @intFromPtr(actual.actual.?);
    try std.testing.expectEqual(@as(usize, 1), f.queueCount());
    try std.testing.expectEqual(@as(u32, 8), actual.wrap.provider);
    try std.testing.expectEqual(f.registry().classId(.fsreqcallback),
        c.JS_GetClassID(actual.wrap.object().?));
    try std.testing.expect(support.callback_request.Request.unwrap(
        f.registry(), actual.wrap.object().?) == null);
    try std.testing.expect(actual.entry.counted and actual.wrap.detached);
    try std.testing.expectEqual(@as(usize, 1), actual.wrap.native_references);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try std.testing.expectEqual(@as(usize, 1), f.env().managed_buffers.count());
    try f.pump();
    try std.testing.expectEqual(@as(usize, 1), f.read_count);
    try expectOutput(f.observations[0], 8, "ABCDEFGH");
    try std.testing.expectEqual(@as(u64, 8), f.observations[0].stream_bytes);
    try std.testing.expectEqual(@as(usize, 1), f.observations[0].freelist);
    try std.testing.expectEqual(pointer, @intFromPtr(actual.actual.?));
    try std.testing.expect(f.data.?.file_handle_read_wrap_freelist.items[0] == &actual.wrap);
    try std.testing.expectEqual(@as(usize, 2), f.end_references[0]);
    try std.testing.expectEqual(@as(usize, 1), actual.wrap.native_references);
    try std.testing.expect(!actual.entry.dispatched and !actual.entry.counted);
    try std.testing.expect(actual.entry.original_callback == null);
    try std.testing.expectEqualSlices(usize, &.{65536, 8},
        f.allocation_lengths[0..f.allocation_count]);
    try expectDrained(&f);
}

test "native FileHandle repeated start and ReadStop preserve the accepted completion" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    _ = try f.start();
    const actual = f.handle.?.read_state.current_read.?;
    _ = try f.start();
    try std.testing.expectEqual(@as(usize, 1), f.begin_count);
    try std.testing.expectEqual(@as(usize, 1), f.allocation_count);
    try std.testing.expectEqual(@as(c_int, 0), Read.stop(f.handle.?));
    try std.testing.expect(!f.handle.?.read_state.reading);
    try std.testing.expect(f.handle.?.read_state.current_read == actual);
    try std.testing.expect(actual.entry.counted);
    try f.pump();
    try expectOutput(f.observations[0], 8, "ABCDEFGH");
    try std.testing.expectEqual(@as(usize, 1), f.begin_count);
    try expectDrained(&f);
}

test "native FileHandle bounded offset advances by emitted bytes before inline EOF" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    f.action = .until_eof;
    f.handle.?.read_state.read_offset = 2;
    f.handle.?.read_state.read_length = 3;
    _ = try f.start();
    try f.pump();
    try std.testing.expectEqual(@as(usize, 2), f.read_count);
    try expectOutput(f.observations[0], 3, "CDE");
    try expectOutput(f.observations[1], native_uv.UV_EOF, "");
    try std.testing.expectEqual(@as(i64, 5), f.handle.?.read_state.read_offset);
    try std.testing.expectEqual(@as(i64, 0), f.handle.?.read_state.read_length);
    try std.testing.expectEqual(@as(usize, 1), f.begin_count);
    try std.testing.expectEqualSlices(usize, &.{3},
        f.allocation_lengths[0..f.allocation_count]);
    try expectDrained(&f);
}

test "native FileHandle completion uses the live length and preserves the raw trace result" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    f.handle.?.read_state.read_offset = 0;
    f.handle.?.read_state.read_length = 8;
    _ = try f.start();
    f.handle.?.read_state.read_length = 2;
    try f.pump();
    try expectOutput(f.observations[0], 2, "AB");
    try std.testing.expectEqual(@as(c_int, 8), f.end_results[0]);
    try std.testing.expectEqual(@as(u64, 2), f.observations[0].stream_bytes);
    try std.testing.expectEqual(@as(i64, 2), f.handle.?.read_state.read_offset);
    try std.testing.expectEqual(@as(i64, 0), f.handle.?.read_state.read_length);
    try std.testing.expectEqualSlices(usize, &.{8, 2},
        f.allocation_lengths[0..f.allocation_count]);
    try expectDrained(&f);
}

test "native FileHandle unbounded restart recycles the same native request through actual EOF" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    f.action = .until_eof;
    _ = try f.start();
    try f.pump();
    try std.testing.expectEqual(@as(usize, 2), f.begin_count);
    try std.testing.expectEqual(@as(usize, 2), f.read_count);
    try expectOutput(f.observations[0], 8, "ABCDEFGH");
    try expectOutput(f.observations[1], native_uv.UV_EOF, "");
    try std.testing.expectEqual(f.begin_pointers[0], f.begin_pointers[1]);
    try std.testing.expect(f.begin_ids[1] > f.begin_ids[0]);
    try std.testing.expectEqualSlices(c_int, &.{8, 0}, f.end_results[0..f.end_count]);
    try std.testing.expectEqual(@as(i64, -1), f.handle.?.read_state.read_offset);
    try std.testing.expectEqual(@as(i64, -1), f.handle.?.read_state.read_length);
    try std.testing.expectEqual(@as(usize, 1), f.queueCount());
    try expectDrained(&f);
}

test "native FileHandle reentrant onread restarts before old Wrapper and event retirement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    f.action = .restart_once;
    _ = try f.start();
    try f.pump();
    try std.testing.expectEqual(@as(usize, 2), f.begin_count);
    try std.testing.expectEqual(@as(usize, 2), f.read_count);
    try std.testing.expectEqual(@as(c_int, 1), f.reentrant_waiting);
    try std.testing.expectEqual(f.begin_pointers[0], f.begin_pointers[1]);
    try std.testing.expect(f.begin_ids[1] > f.begin_ids[0]);
    try std.testing.expectEqualSlices(usize, &.{2, 2},
        f.end_references[0..f.end_count]);
    try expectOutput(f.observations[0], 8, "ABCDEFGH");
    try expectOutput(f.observations[1], native_uv.UV_EOF, "");
    try expectDrained(&f);
}

test "native FileHandle reuse creates a fresh resource and restores the default trigger" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    f.handle.?.read_state.read_offset = 0;
    f.handle.?.read_state.read_length = 1;
    _ = try f.start();
    try f.pump();
    const old_id = f.begin_ids[0];
    f.env().uidField(.default_trigger).* = 77;
    f.handle.?.read_state.read_length = 1;
    _ = try f.start();
    const actual = f.handle.?.read_state.current_read.?;
    const wrapper = actual.wrap.object().?;
    const first_resource = try a.expression(f.engine, resource, .{ &f, wrapper });
    defer f.engine.freeValue(first_resource);
    const ignored = try a.expression(f.engine, expectResourceHandle,
        .{ &f, first_resource, wrapper });
    f.engine.freeValue(ignored);
    try std.testing.expect(actual.wrap.async_id > old_id);
    try std.testing.expectEqual(f.handle.?.state.async_id, actual.wrap.trigger_async_id);
    try std.testing.expectEqual(@as(f64, 77), f.env().uidField(.default_trigger).*);
    try f.pump();
    try expectOutput(f.observations[1], 1, "B");
    f.handle.?.read_state.read_length = 1;
    _ = try f.start();
    const second_resource = try a.expression(f.engine, resource, .{ &f, wrapper });
    defer f.engine.freeValue(second_resource);
    try std.testing.expect(!c.JS_IsStrictEqual(f.engine.context, first_resource, second_resource));
    try f.pump();
    try expectOutput(f.observations[2], 1, "C");
    try expectDrained(&f);
}

test "native FileHandle ignored resource Set exception continues reset and real admission" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    try f.seed(1);
    const cached = f.data.?.file_handle_read_wrap_freelist.items[0];
    const old_id = cached.async_id;
    try f.expose("fileReadSentinel", f.reason.?);
    try f.evaluate(
        \\Object.defineProperty(Object.prototype, 'handle', {
        \\  configurable: true, set(value) {
        \\    globalThis.fileReadSavedWrapper = value;
        \\    throw fileReadSentinel;
        \\  }
        \\});
    );
    f.env().uidField(.default_trigger).* = 77;
    f.handle.?.read_state.read_offset = 0;
    f.handle.?.read_state.read_length = 3;
    try std.testing.expectError(error.JavaScriptException, f.start());
    const caught = try f.takeCaught(); defer f.engine.freeValue(caught);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, caught, f.reason.?));
    const actual = f.handle.?.read_state.current_read.?;
    try std.testing.expect(&actual.wrap == cached);
    try std.testing.expect(actual.wrap.async_id > old_id);
    try std.testing.expect(actual.file_handle == f.handle.?);
    try std.testing.expect(actual.entry.counted);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try std.testing.expectEqual(@as(f64, 77), f.env().uidField(.default_trigger).*);
    _ = Read.stop(f.handle.?);
    try f.evaluate("delete Object.prototype.handle;");
    try f.pump();
    try expectOutput(f.observations[0], 3, "ABC");
    try expectDrained(&f);
}

test "native FileHandle ordinary onread reason survives restart and the actual second completion" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    f.action = .throw_once_continue;
    _ = try f.start();
    try std.testing.expectError(error.JavaScriptException, f.pump());
    const caught = try f.takeCaught(); defer f.engine.freeValue(caught);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, caught, f.reason.?));
    try std.testing.expectEqual(@as(usize, 1), f.read_count);
    try std.testing.expectEqual(@as(usize, 2), f.begin_count);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try std.testing.expect(f.handle.?.read_state.current_read != null);
    try f.pump();
    try std.testing.expectEqual(@as(usize, 2), f.read_count);
    try expectOutput(f.observations[1], native_uv.UV_EOF, "");
    try std.testing.expectEqual(f.begin_pointers[0], f.begin_pointers[1]);
    try expectDrained(&f);
}

test "native FileHandle full freelist releases the completed local after EmitRead" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    try f.seed(100);
    _ = try f.start();
    const actual = f.handle.?.read_state.current_read.?;
    const wrapper = a.duplicate(f.engine, actual.wrap.object().?);
    defer f.engine.freeValue(wrapper);
    try std.testing.expectEqual(@as(usize, 99),
        f.data.?.file_handle_read_wrap_freelist.items.len);
    try f.seed(1);
    _ = Read.stop(f.handle.?);
    try f.pump();
    try expectOutput(f.observations[0], 8, "ABCDEFGH");
    try std.testing.expectEqual(@as(usize, 100), f.observations[0].freelist);
    try std.testing.expectEqual(@as(usize, 100), f.queueCount());
    try std.testing.expect(f.registry().unwrap(wrapper) == null);
    try expectDrained(&f);
}

test "native FileHandle joined service drains the accepted buffer after JavaScript is disabled" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    _ = try f.start();
    f.stopIo();
    try std.testing.expectEqual(@as(usize, 0), f.read_count);
    try std.testing.expectEqual(@as(usize, 1), f.begin_count);
    try std.testing.expectEqual(@as(usize, 1),
        f.data.?.file_handle_read_wrap_freelist.items.len);
    try expectDrained(&f);
}

test "native FileHandle AfterClose shares the actual flags and emits EOF through StreamBase" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; try file.init(&f); defer file.deinit();
    f.handle.?.read_state.reading = true;
    f.handle.?.read_state.closing = true;
    try file.close();
    try Read.afterClose(f.handle.?);
    try std.testing.expect(f.handle.?.read_state.closed);
    try std.testing.expect(!f.handle.?.read_state.closing);
    try std.testing.expectEqual(@as(c_int, -1), f.handle.?.read_state.fd);
    try std.testing.expectEqual(@as(usize, 1), f.read_count);
    try expectOutput(f.observations[0], native_uv.UV_EOF, "");
    try std.testing.expectEqual(@as(c_int, native_uv.UV_EOF), try f.start());
    try std.testing.expectEqual(@as(usize, 0), f.allocation_count);
    try expectDrained(&f);
}
