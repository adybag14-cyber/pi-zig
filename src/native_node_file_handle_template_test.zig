//! Declared source controls for the COMPLETE FileHandle/StreamBase template.
//! Uses the existing real native Controller, BindingData, Queue and libuv File
//! fixture. Its trace/allocation hooks observe the native path; they do not
//! qualify the separate production bootstrap policies. No execution claimed.
const std = @import("std");
const support = @import("native_node_file_handle_owner_test_support.zig");
const template = @import("extensions/native_node_file_handle_template.zig");
const external = @import("extensions/native_node_external_value.zig");
const templates = support.templates;
const a = support.a;
const c = support.c;
const Fixture = support.Fixture;
const File = support.File;
const Handle = support.Handle;
const uv = support.uv;

fn actualInputs(handle: *Handle) template.Inputs {
    return .{
        .controller = handle.controller, .immediate_queue = handle.immediate_queue,
        .read_trace = handle.read_trace, .close_trace = handle.close_trace,
        .allocation = handle.stream_operations.allocation,
        .trace = handle.stream_operations.trace,
        .heap_diagnostics = handle.stream_operations.heap_diagnostics,
    };
}
fn configure(f: *Fixture) !template.Inputs {
    // This donor selects the fixture's real native infrastructure before
    // retiring its present-object Handle. No donor callback is published.
    const seed = try f.create(-1, null, null);
    const inputs = actualInputs(seed);
    try templates.configureFileHandle(f.engine, f.template_owner.?, inputs);
    try std.testing.expectEqual(@as(c_int, -1), try f.releaseDescriptor());
    f.collectHandle();
    return inputs;
}
fn install(f: *Fixture) !template.Inputs {
    const inputs = try configure(f);
    try templates.publishFileHandle(f.engine, f.template_owner.?, f.binding_target.?);
    try f.expose("binding", f.binding_target.?);
    try f.evaluate("globalThis.FileHandle = binding.FileHandle;");
    try f.expose("EINVAL", c.JS_NewInt32(f.engine.context, uv.UV_EINVAL));
    try f.expose("ENOSYS", c.JS_NewInt32(f.engine.context, uv.UV_ENOSYS));
    return inputs;
}
fn adopt(f: *Fixture, expression: []const u8) !*Handle {
    if (f.primary_wrapper != null) return error.PreviousPublicFileHandleStillOwned;
    f.primary_wrapper = try f.value(expression);
    try f.expose("h", f.primary_wrapper.?);
    return f.handle();
}
fn release(f: *Fixture) !void {
    try f.expect("h.releaseFD() === undefined");
}
fn exposeConstructor(f: *Fixture, name: [*:0]const u8, kind: support.native.Kind) !void {
    const function = try templates.constructor(f.engine, f.template_owner.?, kind);
    defer f.engine.freeValue(function);
    try f.expose(name, function);
}

test "native FileHandle template refuses constructor and instance publication without genuine configured inputs" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try std.testing.expectError(error.ActualFileHandleCallbackTemplateRequired,
        templates.constructor(f.engine, f.template_owner.?, .filehandle));
    try std.testing.expectError(error.ActualFileHandleCallbackTemplateRequired,
        templates.newInstance(f.engine, f.template_owner.?, .filehandle));
    try std.testing.expectError(error.ActualFileHandleCallbackTemplateRequired,
        templates.publishFileHandle(f.engine, f.template_owner.?, f.binding_target.?));
    try f.expose("binding", f.binding_target.?);
    try f.expect("!Object.hasOwn(binding, 'FileHandle')");
}

test "native FileHandle template retains infrastructure once and rejects replacement configuration" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const inputs = try install(&f);
    const controller_references = f.controller.?.references;
    const queue_references = f.queue.?.references.load(.monotonic);
    try templates.configureFileHandle(f.engine, f.template_owner.?, inputs);
    try std.testing.expectEqual(controller_references, f.controller.?.references);
    try std.testing.expectEqual(queue_references, f.queue.?.references.load(.monotonic));
    var changed = inputs;
    changed.trace.raw = null;
    try std.testing.expectError(error.ActualFileHandleTemplateInputsMismatch,
        templates.configureFileHandle(f.engine, f.template_owner.?, changed));
    try std.testing.expectEqual(controller_references, f.controller.?.references);
    try std.testing.expectEqual(queue_references, f.queue.?.references.load(.monotonic));
    const plain = try f.value("({})"); defer f.engine.freeValue(plain);
    try std.testing.expectError(error.ActualFileHandleFSBindingTargetRequired,
        templates.publishFileHandle(f.engine, f.template_owner.?, plain));
    _ = try adopt(&f, "new FileHandle(-1)");
    try release(&f);
}

test "native FileHandle template rejects genuine collaborators from another Environment" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var other: Fixture = undefined; try other.init(); defer other.deinit();
    const inputs = try configure(&other);
    try std.testing.expectError(error.ActualFileHandleTemplateEnvironmentMismatch,
        templates.configureFileHandle(f.engine, f.template_owner.?, inputs));
    try std.testing.expectError(error.ActualFileHandleCallbackTemplateRequired,
        templates.constructor(f.engine, f.template_owner.?, .filehandle));
}

test "native FileHandle template publishes exact own property order and AsyncWrap inheritance" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    try exposeConstructor(&f, "AsyncWrap", .async_wrap);
    try f.expect(
        \\(() => {
        \\ const names = ['close','releaseFD','fd','external_stream','bytesRead',
        \\   'bytesWritten','readStart','readStop','shutdown','useUserBuffer','writev',
        \\   'writeBuffer','writeAsciiString','writeUtf8String','writeUcs2String',
        \\   'writeLatin1String','isStreamBase','onread','constructor'];
        \\ const p = FileHandle.prototype;
        \\ const d = Object.getOwnPropertyDescriptor(binding, 'FileHandle');
        \\ const cp = Object.getOwnPropertyDescriptor(FileHandle, 'prototype');
        \\ const pc = Object.getOwnPropertyDescriptor(p, 'constructor');
        \\ return JSON.stringify(Reflect.ownKeys(p)) === JSON.stringify(names) &&
        \\   Object.getPrototypeOf(p) === AsyncWrap.prototype &&
        \\   FileHandle.name === 'FileHandle' && FileHandle.length === 0 &&
        \\   d.value === FileHandle && d.writable && d.configurable && d.enumerable &&
        \\   cp.value === p && cp.writable && !cp.configurable && !cp.enumerable &&
        \\   pc.value === FileHandle && pc.writable && pc.configurable && !pc.enumerable &&
        \\   !Object.hasOwn(binding, 'read') && !Object.hasOwn(binding, 'open');
        \\})()
    );
}

test "native FileHandle template method and accessor descriptors have original names flags and lengths" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    try f.expect(
        \\(() => {
        \\ const p = FileHandle.prototype;
        \\ const methods = ['close','releaseFD','readStart','readStop','shutdown',
        \\   'useUserBuffer','writev','writeBuffer','writeAsciiString',
        \\   'writeUtf8String','writeUcs2String','writeLatin1String'];
        \\ for (const name of methods) {
        \\   const d = Object.getOwnPropertyDescriptor(p, name);
        \\   if (!d.writable || !d.configurable || !d.enumerable ||
        \\       d.value.name !== name || d.value.length !== 0 ||
        \\       Object.hasOwn(d.value, 'prototype')) return false;
        \\   try { Reflect.construct(d.value, []); return false; }
        \\   catch (e) { if (!(e instanceof TypeError)) return false; }
        \\ }
        \\ for (const name of ['fd','external_stream','bytesRead','bytesWritten','onread']) {
        \\   const d = Object.getOwnPropertyDescriptor(p, name);
        \\   if (d.enumerable || d.configurable || 'value' in d || 'writable' in d ||
        \\       d.get.length !== 0 || d.get.name !== '' || Object.hasOwn(d.get,'prototype') ||
        \\       Object.getOwnPropertyDescriptor(p, name).get !== d.get) return false;
        \\   if (name === 'onread') {
        \\     if (typeof d.set !== 'function' || d.set.length !== 0 || d.set.name !== '' ||
        \\         Object.hasOwn(d.set, 'prototype')) return false;
        \\   } else if (d.set !== undefined) return false;
        \\ }
        \\ const flag = Object.getOwnPropertyDescriptor(p, 'isStreamBase');
        \\ return flag.value === true && flag.writable && flag.configurable && flag.enumerable;
        \\})()
    );
}

test "native FileHandle template constructor uses the actual descriptor and Number optional ranges" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    const descriptor = file.take();
    try f.expose("descriptor", c.JS_NewInt32(f.engine.context, descriptor));
    const actual = try adopt(&f, "new FileHandle(descriptor, 2.75, 4.9)");
    try std.testing.expectEqual(descriptor, actual.getFD());
    try std.testing.expectEqual(@as(i64, 2), actual.read_state.read_offset);
    try std.testing.expectEqual(@as(i64, 4), actual.read_state.read_length);
    try std.testing.expectEqual(@as(u32, 4), actual.wrap.provider);
    try std.testing.expect(actual.constructed and actual.stream_initialized and actual.attached);
    try f.expect("h.fd === descriptor && h instanceof FileHandle && h.isStreamBase");
    try release(&f);
    try std.testing.expectEqual(@as(c_int, 0), File.status(descriptor));
    file.descriptor = descriptor;
}

test "native FileHandle template optional non Numbers are not coerced" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    try f.evaluate("globalThis.coercions=0; globalThis.poison={valueOf(){++coercions;throw Error('coercion')}};");
    const actual = try adopt(&f, "new FileHandle(-1, poison, new Number(3))");
    try std.testing.expectEqual(@as(i64, -1), actual.read_state.read_offset);
    try std.testing.expectEqual(@as(i64, -1), actual.read_state.read_length);
    try f.expect("coercions === 0");
    try release(&f);
}

test "native FileHandle template derived constructors keep the genuine native class and live newTarget prototype" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    try f.evaluate("globalThis.Derived = class Derived extends FileHandle {};");
    const actual = try adopt(&f, "new Derived(-1, 3, 5)");
    try std.testing.expectEqual(@as(i64, 3), actual.read_state.read_offset);
    try std.testing.expectEqual(@as(i64, 5), actual.read_state.read_length);
    try f.expect("Object.getPrototypeOf(h)===Derived.prototype && h instanceof FileHandle && h instanceof Derived && h.getProviderType()===4");
    try release(&f);
}

test "native FileHandle template all signatures reject prototype impostors before callback CHECKs" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    try f.expect(
        \\(() => {
        \\ const p=FileHandle.prototype, fake=Object.create(p);
        \\ const receivers=[fake,{},null,undefined,1,'x',true,Symbol('x'),1n];
        \\ const methods=['close','releaseFD','readStart','readStop','shutdown','useUserBuffer',
        \\   'writev','writeBuffer','writeAsciiString','writeUtf8String','writeUcs2String','writeLatin1String'];
        \\ for(const receiver of receivers) {
        \\   for(const name of methods) {
        \\     try { Reflect.apply(p[name],receiver,[]); return false; }
        \\     catch(e){ if(!(e instanceof TypeError)||e.message!=='Illegal invocation')return false; }
        \\   }
        \\   for(const name of ['fd','external_stream','bytesRead','bytesWritten','onread']) {
        \\     const d=Object.getOwnPropertyDescriptor(p,name);
        \\     try { Reflect.apply(d.get,receiver,[]); return false; }
        \\     catch(e){ if(!(e instanceof TypeError)||e.message!=='Illegal invocation')return false; }
        \\     if(d.set) {
        \\       try { Reflect.apply(d.set,receiver,[0]); return false; }
        \\       catch(e){ if(!(e instanceof TypeError)||e.message!=='Illegal invocation')return false; }
        \\     }
        \\   }
        \\ }
        \\ return true;
        \\})()
    );
}

test "native FileHandle template Proxy receivers never execute traps or unwrap the target" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    _ = try adopt(&f, "new FileHandle(-1)");
    try f.expect(
        \\(() => {
        \\ let traps=0;
        \\ const receiver=new Proxy(h,{get(){++traps;throw 1},getPrototypeOf(){++traps;throw 2}});
        \\ const p=FileHandle.prototype, calls=[
        \\   ()=>p.readStart.call(receiver),
        \\   ()=>p.writeBuffer.call(receiver),
        \\   ()=>p.releaseFD.call(receiver),
        \\   ()=>Object.getOwnPropertyDescriptor(p,'fd').get.call(receiver),
        \\   ()=>Object.getOwnPropertyDescriptor(p,'onread').set.call(receiver,0)];
        \\ for(const call of calls) { try{call();return false}catch(e){if(!(e instanceof TypeError))return false} }
        \\ return traps===0;
        \\})()
    );
    try release(&f);
}

test "native FileHandle template rejects other AsyncWrap kinds while retaining inherited AsyncWrap methods" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    try exposeConstructor(&f, "AsyncWrap", .async_wrap);
    try exposeConstructor(&f, "WriteWrap", .writewrap);
    _ = try adopt(&f, "new FileHandle(-1)");
    try f.expect(
        \\(() => {
        \\ if(AsyncWrap.prototype.getProviderType.call(h)!==4 || h.getAsyncId()<0)return false;
        \\ for(const receiver of [new AsyncWrap(),new WriteWrap()]) {
        \\   try{FileHandle.prototype.releaseFD.call(receiver);return false}
        \\   catch(e){if(!(e instanceof TypeError))return false}
        \\ }
        \\ return true;
        \\})()
    );
    try release(&f);
}

test "native FileHandle template onread remains an internal function slot after native Handle retirement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    const actual = try adopt(&f, "new FileHandle(-1)");
    try f.expect("h.onread===undefined && (h.onread=function first(){}, h.onread.name==='first') && !Object.hasOwn(h,'onread')");
    try release(&f);
    try actual.wrap.retire(false);
    try std.testing.expect(f.registry().unwrap(f.primary_wrapper.?) == null);
    try f.expect(
        \\(() => {
        \\ const d=Object.getOwnPropertyDescriptor(FileHandle.prototype,'onread');
        \\ const before=h.onread, after=function after(){};
        \\ return before.name==='first' && d.set.call(h,after)===undefined &&
        \\   d.get.call(h)===after && !Object.hasOwn(h,'onread') &&
        \\   !Reflect.deleteProperty(FileHandle.prototype,'onread');
        \\})()
    );
}

test "native FileHandle template dead streams return EINVAL and retired native slots return undefined before arguments" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    const actual = try adopt(&f, "new FileHandle(-1)");
    const old_trigger = f.env().uidField(.default_trigger).*;
    try release(&f);
    try f.expect(
        \\(() => {
        \\ const names=['readStart','readStop','shutdown','useUserBuffer','writev',
        \\ 'writeBuffer','writeAsciiString','writeUtf8String','writeUcs2String','writeLatin1String'];
        \\ globalThis.streamMethodNames=names;
        \\ return names.every(name=>h[name](null,null,null)===EINVAL) && h.fd===EINVAL &&
        \\   typeof h.external_stream==='object';
        \\})()
    );
    try std.testing.expectEqual(old_trigger, f.env().uidField(.default_trigger).*);
    try actual.wrap.retire(false);
    try f.expect(
        \\streamMethodNames.every(name=>h[name](null,null,null)===undefined) &&
        \\ h.close()===undefined && h.releaseFD()===undefined && h.fd===EINVAL &&
        \\ h.external_stream===undefined && h.bytesRead===0 && h.bytesWritten===0
    );
    try std.testing.expectEqual(old_trigger, f.env().uidField(.default_trigger).*);
}

test "native FileHandle template live accessors retain uint64 Number conversion and fresh borrowed Externals" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    const descriptor = file.take();
    try f.expose("descriptor", c.JS_NewInt32(f.engine.context, descriptor));
    const actual = try adopt(&f, "new FileHandle(descriptor)");
    actual.stream.resource.bytes_read = 9007199254740993;
    actual.stream.resource.bytes_written = std.math.maxInt(u64);
    const native_references = actual.wrap.native_references;
    try f.evaluate("globalThis.firstExternal=h.external_stream;globalThis.secondExternal=h.external_stream;");
    try f.expect(
        \\h.fd===descriptor && h.bytesRead===9007199254740992 && h.bytesWritten===2**64 &&
        \\ firstExternal!==secondExternal && Object.getPrototypeOf(firstExternal)===null &&
        \\ !Object.isExtensible(firstExternal) && Reflect.ownKeys(firstExternal).length===0
    );
    const value = try f.global("firstExternal"); defer f.engine.freeValue(value);
    try std.testing.expect(external.isExternal(value));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&actual.stream)), external.value(value));
    try std.testing.expectEqual(native_references, actual.wrap.native_references);
    try release(&f);
    try f.expect("h.fd===EINVAL && h.bytesRead===9007199254740992 && h.bytesWritten===2**64 && h.external_stream!==firstExternal");
    file.descriptor = descriptor;
}

test "native FileHandle template all six write dispatches reach real WriteWrap and original FileHandle ENOSYS" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    try f.installInitRecorder();
    try exposeConstructor(&f, "WriteWrap", .writewrap);
    const actual = try adopt(&f, "new FileHandle(-1)");
    const trigger = f.env().uidField(.default_trigger).*;
    try f.expect(
        \\(() => {
        \\ globalThis.writeRequests=[];
        \\ const req=()=>{const r=new WriteWrap();writeRequests.push(r);return r};
        \\ const statuses=[
        \\   h.writeBuffer(req(),new Uint8Array([1,2])),
        \\   h.writeAsciiString(req(),'AZ'),
        \\   h.writeUtf8String(req(),'\u00e9'),
        \\   h.writeUcs2String(req(),'A'),
        \\   h.writeLatin1String(req(),'\u00e9A'),
        \\   h.writev(req(),[new Uint8Array([3,4])],true)];
        \\ const writes=ownerInitEvents.filter(row=>row[0]==='WRITEWRAP');
        \\ return statuses.every(value=>value===ENOSYS) && h.bytesWritten===12 &&
        \\   writes.length===6 && writes.every(row=>row[2]===h.getAsyncId());
        \\})()
    );
    try std.testing.expectEqual(@as(u64, 12), actual.stream.resource.bytes_written);
    try std.testing.expectEqual(trigger, f.env().uidField(.default_trigger).*);
    const values = try f.global("writeRequests"); defer f.engine.freeValue(values);
    for (0..6) |index| {
        const request = try f.engine.checked(c.JS_GetPropertyUint32(f.engine.context, values, @intCast(index)));
        defer f.engine.freeValue(request);
        try std.testing.expect(f.registry().unwrap(request) == null);
    }
    try release(&f);
}

test "native FileHandle template public user buffer read uses real libuv and restores trigger scope" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    const descriptor = file.take();
    try f.expose("descriptor", c.JS_NewInt32(f.engine.context, descriptor));
    const actual = try adopt(&f, "new FileHandle(descriptor,2,4)");
    const trigger = f.env().uidField(.default_trigger).*;
    try f.evaluate(
        \\globalThis.userBuffer=new Uint8Array(8);globalThis.readEvents=[];
        \\h.onread=function(value){readEvents.push([this===h,value===undefined]);h.readStop();};
    );
    try f.expect("h.useUserBuffer(userBuffer)===0 && h.readStart()===0");
    try std.testing.expectEqual(trigger, f.env().uidField(.default_trigger).*);
    try f.pumpIo();
    try f.expect(
        \\JSON.stringify(readEvents)==='[[true,true]]' &&
        \\ JSON.stringify(Array.from(userBuffer))==='[67,68,69,70,0,0,0,0]' &&
        \\ h.bytesRead===4 && h.readStop()===0
    );
    try std.testing.expectEqual(@as(i32, 4), f.env().streamBaseField(.read_bytes_or_error).*);
    try std.testing.expectEqual(@as(usize, 1), f.read_begins);
    try std.testing.expectEqual(@as(usize, 1), f.read_ends);
    try std.testing.expect(!actual.read_state.reading);
    try release(&f);
    file.descriptor = descriptor;
}

// The shared fixture's close observations select CloseReq's layout. This one
// control supplies observation callbacks for the actual different ShutdownReq
// layout; it still dispatches the SAME native Controller/uv_fs_t and Handle.
fn beginShutdownTrace(raw: ?*anyopaque, value: *anyopaque) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    const request: *Handle.ShutdownReq = @ptrCast(@alignCast(value));
    f.close_begins += 1;
    f.close_actual = @intFromPtr(request.actual.?);
    f.close_begin_provider = request.wrap.provider;
    std.debug.assert(!request.entry.dispatched and !request.entry.counted);
}
fn endShutdownTrace(raw: ?*anyopaque, value: *anyopaque, result: c_int) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    const request: *Handle.ShutdownReq = @ptrCast(@alignCast(value));
    f.close_ends += 1;
    f.close_result = result;
    f.close_end_actual = @intFromPtr(request.actual.?);
    f.close_end_uncounted = !request.entry.counted;
}
fn installShutdown(f: *Fixture) !void {
    const seed = try f.create(-1, null, null);
    var inputs = actualInputs(seed);
    inputs.close_trace.begin_async = beginShutdownTrace;
    inputs.close_trace.end_async = endShutdownTrace;
    try templates.configureFileHandle(f.engine, f.template_owner.?, inputs);
    _ = try f.releaseDescriptor();
    f.collectHandle();
    try templates.publishFileHandle(f.engine, f.template_owner.?, f.binding_target.?);
    try f.expose("binding", f.binding_target.?);
    try f.evaluate("globalThis.FileHandle=binding.FileHandle;");
    try f.expose("EINVAL", c.JS_NewInt32(f.engine.context, uv.UV_EINVAL));
}

test "native FileHandle template shutdown dispatches the genuine native close request and oncomplete" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try installShutdown(&f);
    try exposeConstructor(&f, "ShutdownWrap", .shutdownwrap);
    const descriptor = file.take();
    try f.expose("descriptor", c.JS_NewInt32(f.engine.context, descriptor));
    _ = try adopt(&f, "new FileHandle(descriptor)");
    const trigger = f.env().uidField(.default_trigger).*;
    try f.evaluate(
        \\globalThis.shutdownRows=[];globalThis.request=new ShutdownWrap();
        \\request.oncomplete=function(status){shutdownRows.push([this===request,status]);};
    );
    try f.expect("h.shutdown(request)===0");
    try std.testing.expectEqual(trigger, f.env().uidField(.default_trigger).*);
    try f.pumpIo();
    try f.expect("JSON.stringify(shutdownRows)==='[[true,0]]' && h.fd===EINVAL");
    try std.testing.expectEqual(@as(c_int, support.physical.UV_EBADF), File.status(descriptor));
    try std.testing.expectEqual(@as(usize, 1), f.close_begins);
    try std.testing.expectEqual(@as(usize, 1), f.close_ends);
    try std.testing.expectEqual(f.close_actual, f.close_end_actual);
    const request = try f.global("request"); defer f.engine.freeValue(request);
    try std.testing.expect(f.registry().unwrap(request) == null);
}

test "native FileHandle template close returns the same real Promise and closes its actual descriptor once" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    const descriptor = file.take();
    try f.expose("descriptor", c.JS_NewInt32(f.engine.context, descriptor));
    _ = try adopt(&f, "new FileHandle(descriptor)");
    try f.evaluate("globalThis.closing=h.close();");
    try f.expect("closing instanceof Promise && h.close()===closing");
    const promise = try f.global("closing"); defer f.engine.freeValue(promise);
    c.JS_PromiseMarkAsHandled(f.engine.context, promise);
    try f.pumpIo();
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.engine.context, promise));
    try f.expect("h.close()===closing && h.fd===EINVAL");
    try std.testing.expectEqual(@as(c_int, support.physical.UV_EBADF), File.status(descriptor));
    try std.testing.expectEqual(@as(usize, 1), f.close_begins);
    try std.testing.expectEqual(@as(usize, 1), f.close_ends);
}

test "native FileHandle template absent object native factory uses complete instance template without a second callback" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    const source = try adopt(&f, "new FileHandle(-1)");
    const inputs: support.owner.Inputs = .{
        .controller = source.controller, .immediate_queue = source.immediate_queue,
        .handle_string = source.handle_string, .read_trace = source.read_trace,
        .close_trace = source.close_trace, .stream = source.stream_operations,
    };
    try release(&f);
    try f.evaluate("h=null;");
    f.collectHandle();
    try f.installInitRecorder();
    f.primary_wrapper = try a.expression(f.engine, struct {
        fn body(s: *a.Scope, fixture: *Fixture, input: support.owner.Inputs) !c.JSValue {
            const data = support.binding.get(fixture.registry()) orelse return error.ActualBindingDataRequired;
            const actual = try Handle.create(s, data, -1, null, 6, 7, input);
            return a.duplicate(s.engine, actual.wrap.object().?);
        }
    }.body, .{ &f, inputs });
    try f.expose("h", f.primary_wrapper.?);
    const actual = try f.handle();
    try std.testing.expectEqual(@as(i64, 6), actual.read_state.read_offset);
    try std.testing.expectEqual(@as(i64, 7), actual.read_state.read_length);
    try f.expect("Object.getPrototypeOf(h)===FileHandle.prototype && h.isStreamBase && ownerInitEvents.length===1 && ownerInitEvents[0][0]==='FILEHANDLE'");
    try release(&f);
}

test "native FileHandle template simple instance cache preserves the first prototype after constructor mutation" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    _ = try adopt(&f, "new FileHandle(-1)");
    try f.expect(
        \\(() => {
        \\ const original=Object.getPrototypeOf(h);
        \\ FileHandle.prototype={replacement:true};
        \\ const next=new FileHandle(-1);
        \\ const same=Object.getPrototypeOf(next)===original && next.isStreamBase;
        \\ next.releaseFD();
        \\ return same && Object.getPrototypeOf(h)===original;
        \\})()
    );
    try release(&f);
}

test "native FileHandle template newTarget fallback keeps real brand without borrowing FileHandle prototype" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    try f.evaluate("globalThis.Target=function Target(){};Target.prototype=7;");
    _ = try adopt(&f, "Reflect.construct(FileHandle,[-1],Target)");
    try f.expect(
        \\Object.getPrototypeOf(h)===Object.prototype && !('isStreamBase' in h) &&
        \\ FileHandle.prototype.releaseFD.call(h)===undefined
    );
}

test "native FileHandle template init reentry sees a complete constructor and preserves original pre StreamBase attachment" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    try f.evaluate(
        \\globalThis.initRows=[];globalThis.entered=false;
        \\globalThis.initObserver=function(id,type,trigger,resource){
        \\ if(type!=='FILEHANDLE')throw Error('unexpected provider');
        \\ initRows.push([resource.isStreamBase,resource.fd,resource.readStart(),resource.onread]);
        \\ if(!entered){entered=true;const nested=new FileHandle(-1);nested.releaseFD();}
        \\};
        \\globalThis.unselectedHook=function(){throw Error('unselected hook')};
    );
    const init_hook = try f.global("initObserver"); defer f.engine.freeValue(init_hook);
    const other = try f.global("unselectedHook"); defer f.engine.freeValue(other);
    try f.env().installHooks(.{ .init = init_hook, .before = other, .after = other,
        .destroy = other, .promise_resolve = other }, f.binding_target.?);
    f.env().field(.init).* = 1;
    _ = try adopt(&f, "new FileHandle(-1)");
    try f.expect("initRows.length===2 && initRows.every(row=>row[0]===true && row[1]===EINVAL && row[2]===undefined && row[3]===undefined) && h.getProviderType()===4");
    try release(&f);
}

test "native FileHandle template ordinary publication setter reenters only the completed constructor" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try configure(&f);
    try f.expose("binding", f.binding_target.?);
    try f.evaluate(
        \\globalThis.setterRows=[];
        \\Object.defineProperty(binding,'FileHandle',{configurable:true,
        \\ set(value){const temporary=new value(-1);setterRows.push([this===binding,value,temporary.isStreamBase]);temporary.releaseFD();}});
    );
    try templates.publishFileHandle(f.engine, f.template_owner.?, f.binding_target.?);
    const function = try templates.constructor(f.engine, f.template_owner.?, .filehandle);
    defer f.engine.freeValue(function);
    try f.expose("completeConstructor", function);
    try f.expect("setterRows.length===1 && setterRows[0][0] && setterRows[0][1]===completeConstructor && setterRows[0][2] && !('value' in Object.getOwnPropertyDescriptor(binding,'FileHandle'))");
}

test "native FileHandle template ordinary publication accepts false Set and does not replace the native constructor cache" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    try f.evaluate("Object.defineProperty(binding,'FileHandle',{value:123,writable:false,configurable:false});");
    try templates.publishFileHandle(f.engine, f.template_owner.?, f.binding_target.?);
    const function = try templates.constructor(f.engine, f.template_owner.?, .filehandle);
    defer f.engine.freeValue(function);
    const original = try f.global("FileHandle"); defer f.engine.freeValue(original);
    try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, function, original));
    try f.expect("binding.FileHandle===123");
}

test "native FileHandle template traced constructor keeps real native inputs after private cache root retirement" {
    var file: File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    _ = try install(&f);
    const cache_key = "\x00native.node.AsyncWrap.actual-templates.v24.13";
    const removed = f.engine.native_module_values.fetchRemove(cache_key) orelse
        return error.ActualTemplateCacheRootRequired;
    f.engine.freeValue(removed.value);
    const former_owner = f.template_owner.?;
    f.template_owner = null;
    f.engine.freeValue(former_owner);
    c.JS_RunGC(f.engine.runtime);

    const descriptor = file.take();
    try f.expose("descriptor", c.JS_NewInt32(f.engine.context, descriptor));
    const actual = try adopt(&f, "new FileHandle(descriptor)");
    try std.testing.expect(actual.binding_data != null);
    try std.testing.expect(actual.stream_operations.shutdown != null);
    try std.testing.expect(actual.stream_operations.write != null);
    c.JS_RunGC(f.engine.runtime);
    try f.evaluate("globalThis.retainedClose=h.close();");
    const promise = try f.global("retainedClose"); defer f.engine.freeValue(promise);
    c.JS_PromiseMarkAsHandled(f.engine.context, promise);
    try f.pumpIo();
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.engine.context, promise));
    try std.testing.expectEqual(@as(c_int, support.physical.UV_EBADF), File.status(descriptor));
    try std.testing.expect(!f.engine.native_module_values.contains(cache_key));
    try f.expect("h.fd===EINVAL && h.close()===retainedClose");
}
