//! Controls for the genuine FSReqCallback constructor and stored InstanceTemplate.
//! Generic FSReqBase operation/settlement algorithms remain separate source work.
//! The last control observes a real dispatched request without substituting those
//! algorithms: its selected native observer stores only the actual read result.
const std = @import("std");
const support = @import("native_node_file_handle_read_test_support.zig");
const a = support.a;
const c = support.c;
const uv = support.uv;
const Fixture = support.Fixture;
const Request = support.callback_request.Request;
const templates = support.templates;
const request_state = @import("extensions/native_node_request_state.zig");

fn construct(f: *Fixture, arguments: []const c.JSValue) !c.JSValue {
    return a.expression(f.engine, struct {
        fn body(s: *a.Scope, fixture: *Fixture, args: []const c.JSValue) !c.JSValue {
            const constructor = try s.own(try templates.constructor(
                s.engine, fixture.templates_owner.?, .fsreqcallback));
            return a.duplicate(s.engine, try s.construct(constructor, args));
        }
    }.body, .{ f, arguments });
}
fn blank(f: *Fixture) !c.JSValue {
    return a.expression(f.engine, struct {
        fn body(s: *a.Scope, owner: c.JSValue) !c.JSValue {
            return a.duplicate(s.engine, try templates.newFSReqCallbackInstance(s, owner));
        }
    }.body, .{f.templates_owner.?});
}
fn exposeConstructor(f: *Fixture) !void {
    const function = try templates.constructor(f.engine, f.templates_owner.?, .fsreqcallback);
    defer f.engine.freeValue(function);
    try f.expose("FSReqCallbackControl", function);
}
fn eval(f: *Fixture, source: []const u8) !c.JSValue {
    return f.engine.eval(source, "actual-fsreqcallback-control.js", c.JS_EVAL_TYPE_GLOBAL);
}
fn get(s: *a.Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return a.duplicate(s.engine, try s.get(value, name));
}
fn expectNative(f: *Fixture, wrapper: c.JSValue) !*Request {
    const native = Request.unwrap(f.registry(), wrapper) orelse
        return error.ActualFSReqCallbackNativeOwnerRequired;
    try std.testing.expect(native.actual != null and native.attached and native.entry_initialized);
    try std.testing.expect(native.binding_data == f.data.?);
    try std.testing.expectEqual(@as(u32, 8), native.wrap.provider);
    try std.testing.expect(native.wrap.init_hook_ran and native.wrap.wants_weak);
    try std.testing.expect(native.wrap.strong_wrapper == null and !native.wrap.detached);
    try std.testing.expectEqual(@as(usize, 0), native.wrap.native_references);
    try std.testing.expect(!native.entry.dispatched and !native.entry.counted);
    try std.testing.expect(native.entry.original_callback == null);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    return native;
}

test "native FSReqCallback no argument initializes the actual selected FSReqBase defaults" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const wrapper = try construct(&f, &.{}); defer f.engine.freeValue(wrapper);
    const request = try expectNative(&f, wrapper);
    try std.testing.expect(!request.use_bigint and !request.has_data);
    try std.testing.expect(!request.is_plain_open and !request.with_file_types);
    try std.testing.expect(request.encoding == .utf8 and request.syscall == null);
    try std.testing.expectEqual(@as(usize, 0), request.buffer_length);
    try std.testing.expectEqual(@as(usize, 64), request.inline_buffer.len);
    try std.testing.expectEqual(@as(usize, 1), f.queueCount());
    const promise = try a.expression(f.engine, get, .{ wrapper, "promise" });
    defer f.engine.freeValue(promise);
    try std.testing.expect(c.JS_IsUndefined(promise));
}

test "native FSReqCallback IsTrue accepts only literal true and never coerces an argument" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const values = [_][]const u8{
        "true", "false", "1", "'true'", "null", "undefined",
        "new Boolean(true)", "({ valueOf() { throw new Error('must not coerce'); } })",
    };
    for (values, 0..) |source, index| {
        const input = try eval(&f, source); defer f.engine.freeValue(input);
        const wrapper = try construct(&f, &.{input});
        const request = try expectNative(&f, wrapper);
        try std.testing.expectEqual(index == 0, request.use_bigint);
        f.engine.freeValue(wrapper);
        try std.testing.expectEqual(@as(usize, 0), f.queueCount());
        try std.testing.expect(!c.JS_HasException(f.engine.context) and f.engine.captured_exception == null);
    }
}

test "native FSReqCallback caller local owns a weak actual request and one BindingData pointer" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const native_roots = f.data.?.pointer_data.?.strong_count;
    const wrapper = try construct(&f, &.{c.pi_js_bool(f.engine.context, 1)}); defer f.engine.freeValue(wrapper);
    const request = try expectNative(&f, wrapper);
    try std.testing.expectEqual(native_roots + 1, f.data.?.pointer_data.?.strong_count);
    try std.testing.expect(f.env().requests.head == &request.entry);
    try std.testing.expectEqual(f.registry().classId(.fsreqcallback), c.JS_GetClassID(wrapper));
    try std.testing.expectEqual(@as(c_int, 0), uv.pi_uv_fs_request_reset(request.actual.?));
}

test "native FSReqCallback weak finalization removes its actual Entry and releases BindingData" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const native_roots = f.data.?.pointer_data.?.strong_count;
    const wrapper = try construct(&f, &.{});
    _ = try expectNative(&f, wrapper);
    try std.testing.expectEqual(@as(usize, 1), f.queueCount());
    f.engine.freeValue(wrapper);
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
    try std.testing.expectEqual(native_roots, f.data.?.pointer_data.?.strong_count);
    try std.testing.expectEqual(@as(c_int, 0), f.env().requests.waiting);
    try std.testing.expect(support.binding.get(f.registry()) == f.data.?);
}

test "native FSReqCallback stored InstanceTemplate creates a real blank brand without calling its constructor" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const counter = f.env().uidField(.counter).*;
    const native_roots = f.data.?.pointer_data.?.strong_count;
    const wrapper = try blank(&f); defer f.engine.freeValue(wrapper);
    const other = try blank(&f); defer f.engine.freeValue(other);
    try std.testing.expectEqual(f.registry().classId(.fsreqcallback), c.JS_GetClassID(wrapper));
    try std.testing.expect(!c.JS_IsStrictEqual(f.engine.context, wrapper, other));
    try std.testing.expect(f.registry().unwrap(wrapper) == null);
    try std.testing.expect(Request.unwrap(f.registry(), wrapper) == null);
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
    try std.testing.expectEqual(counter, f.env().uidField(.counter).*);
    try std.testing.expectEqual(native_roots, f.data.?.pointer_data.?.strong_count);
}

test "native FSReqCallback stored brand distinguishes the actual FileHandleReadWrap native allocation" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.seed(1);
    const actual = f.data.?.file_handle_read_wrap_freelist.items[0];
    const wrapper = actual.object().?;
    try std.testing.expectEqual(f.registry().classId(.fsreqcallback), c.JS_GetClassID(wrapper));
    try std.testing.expect(f.registry().unwrap(wrapper) == actual);
    try std.testing.expect(Request.unwrap(f.registry(), wrapper) == null);
    try std.testing.expectEqual(@as(u32, 8), actual.provider);
    try std.testing.expect(actual.detached and actual.wants_weak);
    try std.testing.expectEqual(@as(usize, 1), actual.native_references);
    try std.testing.expectEqual(@as(usize, 1), f.queueCount());
}

test "native FSReqCallback inherits actual AsyncWrap methods and constructor descriptors" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try exposeConstructor(&f);
    const wrapper = try eval(&f,
        \\(() => {
        \\  const value = new FSReqCallbackControl();
        \\  const ctor = Object.getOwnPropertyDescriptor(FSReqCallbackControl.prototype, 'constructor');
        \\  if (FSReqCallbackControl.name !== 'FSReqCallback' || FSReqCallbackControl.length !== 0)
        \\    throw new Error('actual constructor shape');
        \\  if (ctor.value !== FSReqCallbackControl || !ctor.writable || !ctor.configurable || ctor.enumerable)
        \\    throw new Error('actual constructor descriptor');
        \\  if (value.getProviderType() !== 8 || !(value.getAsyncId() > 0))
        \\    throw new Error('actual AsyncWrap inheritance');
        \\  return value;
        \\})()
    );
    defer f.engine.freeValue(wrapper);
    _ = try expectNative(&f, wrapper);
}

test "native FSReqCallback subclass prototype is selected before its genuine native constructor" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try exposeConstructor(&f);
    const wrapper = try eval(&f,
        \\(() => {
        \\  class Derived extends FSReqCallbackControl {}
        \\  const value = Reflect.construct(FSReqCallbackControl, [true], Derived);
        \\  if (Object.getPrototypeOf(value) !== Derived.prototype ||
        \\      !(value instanceof Derived) || value.getProviderType() !== 8)
        \\    throw new Error('actual derived prototype');
        \\  return value;
        \\})()
    );
    defer f.engine.freeValue(wrapper);
    try std.testing.expect((try expectNative(&f, wrapper)).use_bigint);
}

test "native FSReqCallback throwing new target prototype preserves the reason before native allocation" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try exposeConstructor(&f);
    try f.expose("fsCallbackSentinel", f.reason.?);
    const counter = f.env().uidField(.counter).*;
    const native_roots = f.data.?.pointer_data.?.strong_count;
    try std.testing.expectError(error.JavaScriptException, eval(&f,
        \\Reflect.construct(FSReqCallbackControl, [], new Proxy(function () {}, {
        \\  get(target, key, receiver) {
        \\    if (key === 'prototype') throw fsCallbackSentinel;
        \\    return Reflect.get(target, key, receiver);
        \\  }
        \\}))
    ));
    const caught = try f.takeCaught(); defer f.engine.freeValue(caught);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, caught, f.reason.?));
    try std.testing.expectEqual(counter, f.env().uidField(.counter).*);
    try std.testing.expectEqual(native_roots, f.data.?.pointer_data.?.strong_count);
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
}

test "native FSReqCallback configuration retains the actual shared Controller once and rejects retired Hub entry" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const controller = f.controller.?;
    const references = controller.references;
    try templates.configureFSReqCallback(f.engine, f.templates_owner.?, controller);
    try templates.configureFSReqCallback(f.engine, f.templates_owner.?, controller);
    try std.testing.expectEqual(references, controller.references);
    try std.testing.expectEqual(@as(usize, 0), controller.busy);
    f.stopIo();
    try std.testing.expect(controller.stopping);
    try std.testing.expectEqual(references - 1, controller.references);
    try std.testing.expectError(error.NativeEnvClosed,
        templates.configureFSReqCallback(f.engine, f.templates_owner.?, controller));
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
}

fn storageRead(entry: *request_state.Entry, raw: *anyopaque) !void {
    const request: *uv.PiUvFsRequest = @ptrCast(@alignCast(raw));
    const info = uv.pi_uv_fs_request_info(request);
    uv.pi_uv_fs_request_cleanup(request);
    try std.testing.expectEqual(@as(c_int, uv.PI_UV_FS_READ), info.kind);
    try std.testing.expectEqual(@as(i64, 8), info.result);
    try std.testing.expect(!entry.counted and entry.wrap.detached);
    try std.testing.expectEqual(@as(usize, 1), entry.wrap.native_references);
    const engine = try entry.wrap.registry.environment.requireEngine();
    const ignored = try a.expression(engine, struct {
        fn body(s: *a.Scope, wrapper: c.JSValue, result: i64) !c.JSValue {
            try s.put(wrapper, "actualStorageResult", c.JS_NewInt64(s.engine.context, result));
            return c.pi_js_undefined();
        }
    }.body, .{ entry.wrap.object().?, info.result });
    engine.freeValue(ignored);
}

test "native FSReqCallback generic storage admits the actual read and retires through the real Wrapper" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: support.File = undefined; try file.init(&f); defer file.deinit();
    const native_roots = f.data.?.pointer_data.?.strong_count;
    const wrapper = try construct(&f, &.{}); defer f.engine.freeValue(wrapper);
    const request = try expectNative(&f, wrapper);
    // Invalid span/path requests fail before choosing or admitting an operation.
    try std.testing.expectEqual(@as(c_int, uv.UV_EINVAL),
        uv.pi_uv_fs_read_buffer(request.actual.?, file.descriptor, null, 1, 0));
    try std.testing.expectEqual(@as(c_int, uv.UV_EINVAL),
        uv.pi_uv_fs_open(request.actual.?, null, support.physical.O_RDONLY, 0));
    try std.testing.expectEqual(@as(c_int, 0), uv.pi_uv_fs_request_reset(request.actual.?));
    try std.testing.expect(!request.entry.dispatched and !request.entry.counted);
    var bytes: [8]u8 = undefined;
    const ignored = try a.expression(f.engine, struct {
        fn body(s: *a.Scope, fixture: *Fixture, actual: *Request,
            descriptor: c_int, output: *[8]u8) !c.JSValue
        {
            const status = try fixture.controller.?.dispatchRawRead(s, &actual.entry,
                actual.actual.?, descriptor, output, output.len, 0, storageRead);
            try std.testing.expectEqual(@as(c_int, 0), status);
            return c.pi_js_undefined();
        }
    }.body, .{ &f, request, file.descriptor, &bytes });
    f.engine.freeValue(ignored);
    try std.testing.expectEqual(@as(c_int, 1), f.env().requests.waiting);
    try f.pump();
    try std.testing.expectEqualSlices(u8, "ABCDEFGH", &bytes);
    try std.testing.expect(Request.unwrap(f.registry(), wrapper) == null);
    try std.testing.expect(f.registry().unwrap(wrapper) == null);
    try std.testing.expectEqual(@as(usize, 0), f.queueCount());
    try std.testing.expectEqual(native_roots, f.data.?.pointer_data.?.strong_count);
    const observed = try a.expression(f.engine, get, .{ wrapper, "actualStorageResult" });
    defer f.engine.freeValue(observed);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context,
        observed, c.JS_NewInt32(f.engine.context, 8)));
}
