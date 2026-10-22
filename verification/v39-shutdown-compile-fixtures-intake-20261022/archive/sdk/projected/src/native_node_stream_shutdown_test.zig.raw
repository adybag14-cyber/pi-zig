//! Source-only controls for the actual shutdown owner graph. These controls
//! require separate compiler/native admission; no runtime result is implied.
const std = @import("std");
const t = @import("native_node_stream_shutdown_test_support.zig");
const a = t.a;
const c = t.c;
const Fixture = t.Fixture;
const File = t.base_support.File;
const templates = t.base_support.templates;
const requests = t.requests;
const resources = @import("extensions/native_node_stream_resource.zig");

const SimplePointer = struct {
    state: *t.native.State,
    active: bool = true,
    fn release(self: *SimplePointer) !void {
        if (!self.active) return;
        self.active = false;
        try self.state.releaseNative();
    }
    fn deinit(self: *SimplePointer) void {
        self.release() catch @panic("shutdown control native pointer retirement failed");
    }
};

fn expectReason(f: *Fixture) !void {
    const actual = try f.base.takeCaught();
    defer f.base.engine.freeValue(actual);
    const expected = try f.base.global("shutdownReason");
    defer f.base.engine.freeValue(expected);
    try std.testing.expect(c.JS_IsStrictEqual(f.base.engine.context, actual, expected));
    try std.testing.expect(!c.JS_IsUncatchableError(actual));
}
fn ordinaryFile(f: *Fixture, file: *File) !*t.Handle {
    try file.init();
    // The selected ordinary descriptor must not be a Windows CRT std handle:
    // libuv intentionally treats fd <= 2 differently from an ordinary file.
    try std.testing.expect(file.descriptor > 2);
    return f.create(file.take());
}

test "native Stream shutdown actual constructor owns original null fields and independent empty slots" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const constructor = try templates.constructor(f.base.engine, f.base.template_owner.?, .shutdownwrap);
    defer f.base.engine.freeValue(constructor);
    try f.base.expose("ActualShutdownWrap", constructor);
    try f.base.evaluate("globalThis.shutdownRequest=new ActualShutdownWrap();");
    try f.base.expect("Object.keys(shutdownRequest).join(',')==='oncomplete,callback,handle' && " ++
        "['oncomplete','callback','handle'].every(k=>{const d=Object.getOwnPropertyDescriptor(shutdownRequest,k);" ++
        "return d.value===null&&d.writable&&d.enumerable&&d.configurable;}) && " ++
        "Object.getPrototypeOf(shutdownRequest)===ActualShutdownWrap.prototype");
    const wrapper = try f.base.global("shutdownRequest"); defer f.base.engine.freeValue(wrapper);
    try std.testing.expect(f.base.registry().unwrap(wrapper) == null);
    try std.testing.expect(requests.Request.fromObject(f.base.registry(), wrapper) == null);
}

test "native Stream shutdown genuine Simple wrapper clears request slot before last native pointer retirement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try f.createClosed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const request = try f.simple(wrapper);
    const state = request.request.asyncWrap();
    var pointer: SimplePointer = .{ .state = state }; defer pointer.deinit();
    try std.testing.expectEqual(t.native.Provider.shutdownwrap, state.provider);
    try std.testing.expect(requests.Request.fromObject(f.base.registry(), wrapper) == &request.request);
    try std.testing.expectEqual(@as(usize, 1), state.native_references);
    try request.request.dispose();
    try std.testing.expect(requests.Request.fromObject(f.base.registry(), wrapper) == null);
    try std.testing.expect(f.base.registry().unwrap(wrapper) == state);
    try std.testing.expect(state.detached);
    try pointer.release();
    try f.expectRetired(wrapper);
}

test "native Stream shutdown physical close reports after trace end cleanup and AfterClose with borrowed handle" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; defer file.deinit();
    const handle = try ordinaryFile(&f, &file);
    const descriptor = handle.read_state.fd;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    const references = handle.wrap.native_references;
    try std.testing.expectEqual(@as(c_int, 0), try f.run(wrapper));
    try std.testing.expect(handle.read_state.closing and !handle.read_state.closed);
    try std.testing.expectEqual(@as(c_int, 1), f.base.env().requests.waiting);
    try std.testing.expectEqual(references, handle.wrap.native_references);
    try std.testing.expect(f.begin_unsubmitted and f.begin_stream_exact);
    try std.testing.expectEqual(t.native.Provider.shutdownwrap, f.begin_provider);
    try std.testing.expectEqual(references, f.begin_handle_references);
    try f.base.pumpIo();
    try std.testing.expect(f.end_closing and f.end_uncounted and f.end_accepted_uncleaned);
    try std.testing.expectEqual(@as(usize, 1), f.end_native_references);
    try std.testing.expectEqual(@as(c_int, 0), f.end_result);
    try std.testing.expect(f.callback_cleaned and f.callback_uncounted);
    try std.testing.expect(handle.read_state.closed and !handle.read_state.closing and handle.read_state.fd == -1);
    try std.testing.expect(File.status(descriptor) < 0);
    try f.base.expect("shutdownCalls.length===1 && shutdownCalls[0][0]===shutdownRequest && " ++
        "shutdownCalls[0][1]===0 && shutdownCalls[0][2]===shutdownHandle && " ++
        "shutdownCalls[0][3]===undefined && shutdownCalls[0][4]===1");
    try f.expectRetired(wrapper);
}

test "native Stream shutdown real accepted bad descriptor still performs AfterClose and reports negative status" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.create(std.math.maxInt(c_int));
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    try std.testing.expectEqual(@as(c_int, 0), try f.run(wrapper));
    try f.base.pumpIo();
    try std.testing.expectEqual(@as(c_int, t.base_support.physical.UV_EBADF), f.end_result);
    try std.testing.expect(handle.read_state.closed and handle.read_state.fd == -1);
    try f.base.expect("shutdownCalls.length===1 && shutdownCalls[0][1]<0 && shutdownCalls[0][4]===1");
    try f.expectRetired(wrapper);
}

test "native Stream shutdown closed fast path completes synchronously and restores the prior trigger" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try f.createClosed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    f.base.env().uidField(.default_trigger).* = 91;
    try std.testing.expectEqual(@as(c_int, 1), try f.run(wrapper));
    try std.testing.expectEqual(@as(f64, 91), f.base.env().uidField(.default_trigger).*);
    try std.testing.expectEqual(@as(usize, 0), f.begins);
    try std.testing.expectEqual(@as(usize, 0), f.ends);
    try f.base.expect("shutdownCalls.length===1 && shutdownCalls[0][1]===0 && shutdownCalls[0][4]===1");
    try f.expectRetired(wrapper);
}

test "native Stream shutdown closing fast path retires its own request while real first close stays queued" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; defer file.deinit();
    _ = try ordinaryFile(&f, &file);
    const first = try f.request(); defer f.base.engine.freeValue(first);
    try std.testing.expectEqual(@as(c_int, 0), try f.run(first));
    const second = try f.request(); defer f.base.engine.freeValue(second);
    try f.publishRequest(second);
    try std.testing.expectEqual(@as(c_int, 1), try f.run(second));
    try std.testing.expect(f.base.registry().unwrap(second) == null);
    try std.testing.expect(requests.Request.fromObject(f.base.registry(), second) == null);
    try std.testing.expectEqual(@as(c_int, 1), f.base.env().requests.waiting);
    try f.base.expect("shutdownCalls.length===1 && shutdownCalls[0][4]===2");
    try f.base.pumpIo();
    try f.expectRetired(first);
}

test "native Stream shutdown nonfunction oncomplete yields undefined without invoking trace or callback" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try f.createClosed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    try f.base.evaluate("shutdownRequest.oncomplete=42;");
    const before = f.base.before_read_callbacks;
    try std.testing.expectEqual(@as(c_int, 1), try f.run(wrapper));
    try std.testing.expectEqual(before, f.base.before_read_callbacks);
    try f.base.expect("shutdownCalls.length===0");
    try f.expectRetired(wrapper);
}

test "native Stream shutdown absent oncomplete skips the ordinary Get and native callback" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try f.createClosed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    try f.base.evaluate("delete shutdownRequest.oncomplete;");
    try std.testing.expectEqual(@as(c_int, 1), try f.run(wrapper));
    try f.base.expect("shutdownCalls.length===0");
    try f.expectRetired(wrapper);
}

test "native Stream shutdown throwing oncomplete getter preserves actual reason and still disposes native request" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try f.createClosed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    try f.base.evaluate("Object.defineProperty(shutdownRequest,'oncomplete',{get(){throw shutdownReason;}});");
    try std.testing.expectError(error.JavaScriptException, f.run(wrapper));
    try std.testing.expectEqual(@as(c_int, 1), f.last_status);
    try expectReason(&f);
    try f.expectRetired(wrapper);
}

test "native Stream shutdown real close callback exception survives actual Wrapper and event destruction" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; defer file.deinit();
    _ = try ordinaryFile(&f, &file);
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    try f.base.evaluate("shutdownRequest.oncomplete=function(){throw shutdownReason;};");
    try std.testing.expectEqual(@as(c_int, 0), try f.run(wrapper));
    try std.testing.expectError(error.JavaScriptException, f.base.pumpIo());
    try expectReason(&f);
    try f.expectRetired(wrapper);
    try std.testing.expect((try f.base.handle()).read_state.closed);
}

test "native Stream shutdown disabled JavaScript returns before oncomplete getter while native close retires" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; defer file.deinit();
    _ = try ordinaryFile(&f, &file);
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    try f.base.evaluate("globalThis.shutdownGetterCount=0;" ++
        "Object.defineProperty(shutdownRequest,'oncomplete',{get(){++shutdownGetterCount;throw shutdownReason;}});");
    try std.testing.expectEqual(@as(c_int, 0), try f.run(wrapper));
    f.base.env().can_call_into_js = false;
    try f.base.pumpIo();
    f.base.env().can_call_into_js = true;
    try f.base.expect("shutdownGetterCount===0 && shutdownCalls.length===0");
    try f.expectRetired(wrapper);
}

test "native Stream shutdown live listener head uses original predecessor forwarding into real reporter" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.createClosed();
    var first: resources.Listener = .{};
    handle.stream.resource.push(&first);
    defer first.deinit();
    var second: resources.Listener = .{};
    handle.stream.resource.push(&second);
    defer second.deinit();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    try std.testing.expectEqual(@as(c_int, 1), try f.run(wrapper));
    try f.base.expect("shutdownCalls.length===1");
    try std.testing.expect(handle.stream.resource.listener == &second);
    try f.expectRetired(wrapper);
}

test "native StreamReq Done stores actual Latin1 error bytes then reports and clears request field" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try f.createClosed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    const request = try f.simple(wrapper);
    const state = request.request.asyncWrap();
    var pointer: SimplePointer = .{ .state = state }; defer pointer.deinit();
    try request.request.done(7, "a\x80\xff");
    try f.base.expect("shutdownRequest.error.length===3 && shutdownRequest.error.charCodeAt(1)===128 && " ++
        "shutdownRequest.error.charCodeAt(2)===255 && shutdownCalls.length===1 && " ++
        "shutdownCalls[0][1]===7 && shutdownCalls[0][3]===undefined");
    try std.testing.expect(requests.Request.fromObject(f.base.registry(), wrapper) == null);
    try pointer.release();
    try f.expectRetired(wrapper);
}

test "native StreamReq Done failing ordinary error setter returns before OnDone and preserves both native slots" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try f.createClosed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    try f.base.evaluate("Object.defineProperty(shutdownRequest,'error',{set(){throw shutdownReason;}});");
    const request = try f.simple(wrapper);
    const state = request.request.asyncWrap();
    var pointer: SimplePointer = .{ .state = state }; defer pointer.deinit();
    try std.testing.expectError(error.JavaScriptException, request.request.done(0, "error"));
    try expectReason(&f);
    try std.testing.expect(requests.Request.fromObject(f.base.registry(), wrapper) == &request.request);
    try std.testing.expect(f.base.registry().unwrap(wrapper) == state and !state.detached);
    try f.base.expect("shutdownCalls.length===0");
    try request.request.dispose();
    try pointer.release();
    try f.expectRetired(wrapper);
}

test "native StreamReq Done false nonwritable Set still continues to OnDone" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try f.createClosed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    try f.base.evaluate("Object.defineProperty(shutdownRequest,'error',{value:'fixed',writable:false});");
    const request = try f.simple(wrapper);
    const state = request.request.asyncWrap();
    var pointer: SimplePointer = .{ .state = state }; defer pointer.deinit();
    try request.request.done(3, "ignored");
    try f.base.expect("shutdownRequest.error==='fixed' && shutdownCalls.length===1 && shutdownCalls[0][1]===3");
    try pointer.release();
    try f.expectRetired(wrapper);
}

test "native Stream shutdown reporter converts Latin1 error then clears original stream error" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try f.createClosed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.publishRequest(wrapper);
    try f.installMessage();
    try std.testing.expectEqual(@as(c_int, 1), try f.run(wrapper));
    try std.testing.expectEqual(@as(usize, 1), f.error_clears);
    try f.base.expect("shutdownCalls.length===1 && shutdownCalls[0][3]==='native-\\x80\\xff'");
    try f.expectRetired(wrapper);
}

test "native Stream shutdown missing caller object uses actual stored InstanceTemplate then real native close" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var file: File = undefined; defer file.deinit();
    _ = try ordinaryFile(&f, &file);
    try std.testing.expectEqual(@as(c_int, 0), try f.run(null));
    const observed = f.observed_request orelse return error.ActualShutdownTemplateObjectRequired;
    try std.testing.expectEqual(f.base.registry().classId(.shutdownwrap), c.JS_GetClassID(observed));
    try f.base.pumpIo();
    try f.expectRetired(observed);
    try std.testing.expectEqual(@as(usize, 0), f.base.before_read_callbacks);
}

test "native Stream shutdown request init inherits actual handle async ID and restores prior trigger" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.createClosed();
    try f.base.installInitRecorder();
    try f.base.expose("shutdownHandleId", c.JS_NewFloat64(f.base.engine.context, handle.wrap.async_id));
    f.base.env().uidField(.default_trigger).* = 123;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try std.testing.expectEqual(@as(c_int, 1), try f.run(wrapper));
    try std.testing.expectEqual(@as(f64, 123), f.base.env().uidField(.default_trigger).*);
    try f.base.expect("ownerInitEvents.length===1 && ownerInitEvents[0][0]==='SHUTDOWNWRAP' && " ++
        "ownerInitEvents[0][2]===shutdownHandleId");
    try f.expectRetired(wrapper);
}
