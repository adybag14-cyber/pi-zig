//! Twelve authored controls for actual filesystem writer I/O and ownership.
//! The public controls use the genuine process/Stream/Buffer/node:fs graph.
//! The native controls exercise the real packet, libuv descriptor and Env Hub.
//! These declarations are source-only; Root grants build and runtime separately.
//! The original WriteStream Source8 capture gate remains in its original root.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const raw = @import("extensions/native_node_fs_write_io.zig");
const hub_module = @import("extensions/native_env_io.zig");
const wake = @import("extensions/native_owner_wake.zig");
const wake_owner = @import("extensions/native_owner_completion.zig");
const uv = @cImport({
    @cInclude("uv.h");
    @cInclude("native_uv_fs_write.h");
});
const gpa = std.testing.allocator;
const io = std.testing.io;

fn fdStatus(fd: c_int) c_int {
    var request: uv.uv_fs_t = undefined;
    const status = uv.uv_fs_fstat(null, &request, fd, null);
    uv.uv_fs_req_cleanup(&request);
    return status;
}
fn checkDescriptor(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    var fd: c_int = -1;
    if (argc != 1 or !c.JS_IsNumber(argv[0]) or c.JS_ToInt32(context, &fd, argv[0]) < 0)
        return c.JS_ThrowTypeError(context, "Actual writer descriptor required");
    if (fd < 0 or fdStatus(fd) != 0)
        return c.JS_ThrowInternalError(context, "Writer did not publish a live libuv descriptor");
    return c.pi_js_undefined();
}
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(c.JS_GetRuntime(context));
    return c.pi_js_undefined();
}

const Fixture = struct {
    temporary: std.testing.TmpDir,
    root: []u8,
    environment: std.process.Environ.Map,
    engine: *a.v.em.Engine,
    fn init(self: *Fixture) !void {
        self.temporary = std.testing.tmpDir(.{});
        errdefer self.temporary.cleanup();
        self.root = try self.temporary.dir.realPathFileAlloc(io, ".", gpa);
        errdefer gpa.free(self.root);
        self.environment = .init(gpa);
        errdefer self.environment.deinit();
        self.engine = try a.v.em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
        errdefer self.engine.deinit();
        try @import("extensions/timers.zig").install(self.engine, io);
        try @import("extensions/native_process.zig").install(self.engine, io, &self.environment, &.{"native-actual-filesystem-writer"});
        try @import("extensions/node_path.zig").install(self.engine, io);
        try @import("extensions/node_url.zig").install(self.engine);
        try @import("extensions/native_node_os.zig").install(self.engine);
        const process = (try self.engine.requireBuiltin("node:process")) orelse return error.ActualWriterProcessRequired;
        defer self.engine.freeValue(process);
        try @import("extensions/node_fs.zig").installWithStreams(self.engine, io, process);
        try @import("extensions/native_node_stream_web.zig").install(self.engine);
        var s = a.Scope.init(self.engine);
        _ = try s.finish(self.publish(&s));
        try self.engine.bindFunction("actualWriterCheckDescriptor", checkDescriptor, 1);
        try self.engine.bindFunction("actualWriterCollect", collect, 0);
    }
    fn publish(self: *Fixture, s: *a.Scope) !c.JSValue {
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const fs = try s.own((try s.engine.requireBuiltin("node:fs")) orelse return error.ActualWriterFsRequired);
        const paths = try s.own((try s.engine.requireBuiltin("node:path")) orelse return error.ActualWriterPathRequired);
        const helpers = try s.own(try @import("extensions/native_node_fs_path_bootstrap.zig").prepare(s.engine));
        const registry = s.engine.native_module_values.get("pi-native:node-write-filesystem-operations") orelse return error.ActualWriterRegistryRequired;
        inline for (.{ "open", "write", "writev", "fsync", "close" }) |name|
            try std.testing.expect(s.equal(try s.get(fs, name), try s.get(registry, name)));
        try s.put(global, "actualWriterFs", fs);
        try s.put(global, "actualWriterPaths", paths);
        try s.put(global, "actualWriterBuffer", try s.get(helpers, "Buffer"));
        try s.put(global, "actualWriterRegistry", registry);
        try s.put(global, "actualWriterRoot", try s.text(self.root));
        return c.pi_js_undefined();
    }
    fn deinit(self: *Fixture) void {
        self.engine.deinit();
        self.environment.deinit();
        gpa.free(self.root);
        self.temporary.cleanup();
    }
    fn run(self: *Fixture, body: []const u8) !void {
        const text = try std.mem.concat(gpa, u8, &.{ prelude, "\n", body, "\nexport const proof=true;" });
        defer gpa.free(text);
        const result = self.engine.evalModule(text, "native-actual-filesystem-writer.mjs") catch |err| {
            std.debug.print("Actual filesystem writer: {s}: {s}\n", .{ @errorName(err), self.engine.last_error orelse "no captured diagnostic" });
            return err;
        };
        self.engine.freeValue(result);
        try std.testing.expect(self.engine.native_fatal_invocation == null);
        try std.testing.expect(!c.JS_HasException(self.engine.context));
        try std.testing.expect(!c.JS_IsJobPending(self.engine.runtime));
        try std.testing.expectEqual(@as(usize, 0), (try hub_module.get(self.engine)).tasks.items.len);
    }
    fn expectBytes(self: *Fixture, name: []const u8, expected: []const u8) !void {
        const bytes = try self.temporary.dir.readFileAlloc(io, name, gpa, .limited(65536));
        defer gpa.free(bytes);
        try std.testing.expectEqualSlices(u8, expected, bytes);
    }
};
const prelude =
    \\import {Writable,Readable} from 'node:stream';
    \\import {pipeline} from 'node:stream/promises';
    \\import {ReadableStream} from 'node:stream/web';
    \\const fs=actualWriterFs, Buffer=actualWriterBuffer;
    \\const path=name=>actualWriterPaths.join(actualWriterRoot,name);
    \\const check=(condition,message)=>{if(!condition)throw Error(message)};
    \\const open=(name,flags='w')=>new Promise((resolve,reject)=>fs.open(path(name),flags,438,(e,fd)=>e?reject(e):resolve(fd)));
    \\const close=fd=>new Promise((resolve,reject)=>fs.close(fd,e=>e?reject(e):resolve()));
    \\const sync=fd=>new Promise((resolve,reject)=>fs.fsync(fd,e=>e?reject(e):resolve()));
    \\const write=(fd,buffer,position=null)=>new Promise((resolve,reject)=>fs.write(fd,buffer,0,buffer.length,position,(e,count,returned)=>e?reject(e):resolve({count,returned})));
;

test "native actual filesystem writer retains genuine published operations through registry mutation" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.run(
        \\const names=['open','write','writev','fsync','close'];
        \\for(const name of names)check(fs[name]===actualWriterRegistry[name],'actual operation identity '+name);
        \\actualWriterRegistry.registry=fs.write;
        \\for(const name of names)actualWriterRegistry[name]=null;
        \\actualWriterCollect();
        \\const fd=await open('registry.bin');
        \\actualWriterCheckDescriptor(fd);
        \\const input=Buffer.from([0,17,255]);
        \\const result=await write(fd,input);
        \\check(result.count===3&&result.returned===input,'retained write callback');
        \\await close(fd);
    );
    try fixture.expectBytes("registry.bin", &.{ 0, 17, 255 });
}
test "native actual filesystem writer writes scalar vectors flushes and closes real binary bytes" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.run(
        \\const fd=await open('binary.bin');
        \\actualWriterCheckDescriptor(fd);
        \\const first=Buffer.from([0,239,187]);
        \\const one=await write(fd,first);
        \\check(one.count===first.length&&one.returned===first,'scalar result identity');
        \\const vectors=[Buffer.from([191,65]),Buffer.from([240,159,140,141])];
        \\const two=await new Promise((resolve,reject)=>fs.writev(fd,vectors,null,(e,count,returned)=>e?reject(e):resolve({count,returned})));
        \\check(two.count===6&&two.returned===vectors,'vector result identity');
        \\await sync(fd);
        \\await close(fd);
    );
    try fixture.expectBytes("binary.bin", &.{ 0, 239, 187, 191, 65, 240, 159, 140, 141 });
}
test "native actual filesystem writer append preserves prior content with explicit write position" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.temporary.dir.writeFile(io, .{ .sub_path = "append.bin", .data = "AB" });
    try fixture.run(
        \\const fd=await open('append.bin','a');
        \\const first=await write(fd,Buffer.from('XY'),0);
        \\const second=await write(fd,Buffer.from('Z'));
        \\check(first.count===2&&second.count===1,'append byte counts');
        \\await close(fd);
    );
    try fixture.expectBytes("append.bin", "ABXYZ");
}
test "native actual filesystem writer reports actual exclusive and missing path libuv errors asynchronously" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.temporary.dir.writeFile(io, .{ .sub_path = "existing.bin", .data = "keep" });
    try fixture.run(
        \\for(const [name,flags,code]of [['existing.bin','wx','EEXIST'],['missing/child.bin','w','ENOENT']]){
        \\  let inCall=true,visits=0;
        \\  const pending=new Promise((resolve,reject)=>fs.open(path(name),flags,438,(error,fd)=>{
        \\    visits++;
        \\    try{check(!inCall&&error instanceof Error&&error.code===code&&error.syscall==='open'&&error.path===path(name)&&fd===undefined,'actual open failure');resolve()}catch(e){reject(e)}
        \\  }));
        \\  inCall=false;await pending;check(visits===1,'one open failure');
        \\}
    );
    try fixture.expectBytes("existing.bin", "keep");
}
test "native actual filesystem writer real Web pipeline reaches Writable finish then close" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.run(
        \\const source=new ReadableStream({start(controller){controller.enqueue(new Uint8Array([0,1,2]));controller.enqueue(new Uint8Array([253,254,255]));controller.close()}});
        \\const target=fs.createWriteStream(path('pipeline.bin'));
        \\check(target instanceof Writable,'actual Writable constructor');
        \\const trace=[];
        \\target.on('open',fd=>{actualWriterCheckDescriptor(fd);trace.push('open')});
        \\target.on('ready',()=>trace.push('ready'));
        \\target.on('finish',()=>trace.push('finish'));
        \\target.on('close',()=>trace.push('close'));
        \\await pipeline(Readable.fromWeb(source),target);
        \\check(target.closed&&target.fd===null&&target.bytesWritten===6,'actual file owner closed');
        \\check(trace.join(',')==='open,ready,finish,close','actual stream completion order');
    );
    try fixture.expectBytes("pipeline.bin", &.{ 0, 1, 2, 253, 254, 255 });
}

const CallbackProbe = struct { reason: c.JSValue, calls: usize = 0 };
var active_callback: ?*CallbackProbe = null;
fn throwCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = active_callback.?;
    probe.calls += 1;
    return c.JS_Throw(context, c.JS_DupValue(context, probe.reason));
}
test "native actual filesystem writer propagates an actual completion throw once after task removal" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const reason = try fixture.engine.checked(c.JS_NewObject(fixture.engine.context));
    defer fixture.engine.freeValue(reason);
    var probe: CallbackProbe = .{ .reason = reason };
    active_callback = &probe;
    defer active_callback = null;
    try fixture.engine.bindFunction("actualWriterThrow", throwCallback, 2);
    const start = try fixture.engine.eval("actualWriterFs.open(actualWriterPaths.join(actualWriterRoot,'throw.bin'),'w',438,actualWriterThrow);", "actual-writer-start-throw.js", c.JS_EVAL_TYPE_GLOBAL);
    fixture.engine.freeValue(start);
    try std.testing.expectError(error.JavaScriptException, fixture.engine.evalModule("await new Promise(()=>{});", "actual-writer-completion-throw.mjs"));
    try std.testing.expect(fixture.engine.captured_exception != null);
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.engine.captured_exception.?));
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expectEqual(@as(usize, 0), (try hub_module.get(fixture.engine)).tasks.items.len);
}
test "native actual filesystem writer native open publishes a real borrowed CRT descriptor" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(root);
    const path = try std.fs.path.join(gpa, &.{root,"descriptor.bin"});
    defer gpa.free(path);
    const terminated = try gpa.dupeZ(u8, path);
    defer gpa.free(terminated);
    const engine = try a.v.em.Engine.init(gpa, .{});
    defer engine.deinit();
    const count = uv.pi_uv_file_live_handles();
    const used = c.pi_js_native_memory_used(engine.native_memory_owner);
    const opened = uv.pi_uv_file_open(engine.native_memory_owner, terminated.ptr, uv.pi_uv_fs_write_open_flags(0, 1), 0o666);
    try std.testing.expectEqual(@as(c_int, 0), opened.uv_status);
    try std.testing.expectEqual(@as(c_int, 0), opened.native_allocation_failure);
    const handle = opened.handle orelse return error.ActualUvOpenRequired;
    var alive = true;
    defer { if (alive) { _ = uv.pi_uv_file_release(handle); } }
    const descriptor = uv.pi_uv_file_descriptor(handle);
    try std.testing.expect(descriptor >= 0);
    try std.testing.expectEqual(@as(c_int, 0), fdStatus(descriptor));
    try std.testing.expectEqual(count + 1, uv.pi_uv_file_live_handles());
    try std.testing.expect(c.pi_js_native_memory_used(engine.native_memory_owner) > used);
    const closed = uv.pi_uv_file_release(handle);
    alive = false;
    try std.testing.expectEqual(@as(c_int, 1), closed.closed_by_release);
    try std.testing.expectEqual(descriptor, closed.descriptor);
    try std.testing.expectEqual(@as(c_int, 0), closed.uv_status);
    try std.testing.expectEqual(@as(c_int, uv.UV_EBADF), fdStatus(descriptor));
    try std.testing.expectEqual(count, uv.pi_uv_file_live_handles());
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(engine.native_memory_owner));
}
test "native actual filesystem writer canceled packet never enters physical open" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(root);
    const path = try std.fs.path.join(gpa, &.{root,"never-opened.bin"});
    defer gpa.free(path);
    const terminated = try gpa.dupeZ(u8, path);
    defer gpa.free(terminated);
    const engine = try a.v.em.Engine.init(gpa, .{});
    defer engine.deinit();
    const count = uv.pi_uv_file_live_handles();
    var packet: raw.Packet = .{ .io = io, .operation = .open, .path = path, .windows_path = terminated, .memory_owner = engine.native_memory_owner };
    defer packet.retireUnadopted();
    packet.cancel();
    packet.run();
    try std.testing.expect(packet.completed and !packet.ran);
    try std.testing.expect(packet.failure != null);
    try std.testing.expect(packet.failure.? == error.Canceled);
    try std.testing.expect(packet.opened == null);
    try std.testing.expectEqual(count, uv.pi_uv_file_live_handles());
    if (temporary.dir.openFile(io, "never-opened.bin", .{})) |file| {
        file.close(io);
        return error.CanceledPacketCreatedPhysicalFile;
    } else |err| try std.testing.expect(err == error.FileNotFound);
}
test "native actual filesystem writer unadopted real packet closes before its memory entitlement retires" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(root);
    const path = try std.fs.path.join(gpa, &.{root,"unadopted.bin"});
    defer gpa.free(path);
    const terminated = try gpa.dupeZ(u8, path);
    defer gpa.free(terminated);
    const engine = try a.v.em.Engine.init(gpa, .{});
    defer engine.deinit();
    const count = uv.pi_uv_file_live_handles();
    const used = c.pi_js_native_memory_used(engine.native_memory_owner);
    var packet: raw.Packet = .{ .io = io, .operation = .open, .path = path, .windows_path = terminated, .memory_owner = engine.native_memory_owner };
    defer packet.retireUnadopted();
    packet.run();
    if (packet.failure) |err| return err;
    try std.testing.expectEqual(@as(c_int, 0), packet.uv_status);
    const file = packet.opened orelse return error.ActualPacketOpenRequired;
    const descriptor: c_int = @intCast(try raw.descriptor(file));
    try std.testing.expectEqual(@as(c_int, 0), fdStatus(descriptor));
    packet.retireUnadopted();
    try std.testing.expect(packet.opened == null);
    try std.testing.expectEqual(@as(c_int, uv.UV_EBADF), fdStatus(descriptor));
    try std.testing.expectEqual(count, uv.pi_uv_file_live_handles());
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(engine.native_memory_owner));
}
test "native actual filesystem writer physical close precedes published close with one final release" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(root);
    const path = try std.fs.path.join(gpa, &.{root,"close-state.bin"});
    defer gpa.free(path);
    const terminated = try gpa.dupeZ(u8, path);
    defer gpa.free(terminated);
    const engine = try a.v.em.Engine.init(gpa, .{});
    defer engine.deinit();
    const count = uv.pi_uv_file_live_handles();
    const opened = uv.pi_uv_file_open(engine.native_memory_owner, terminated.ptr, uv.pi_uv_fs_write_open_flags(0, 1), 0o666);
    try std.testing.expectEqual(@as(c_int, 0), opened.uv_status);
    const handle = opened.handle orelse return error.ActualUvOpenRequired;
    var alive = true;
    defer { if (alive) { _ = uv.pi_uv_file_release(handle); } }
    const descriptor = uv.pi_uv_file_descriptor(handle);
    uv.pi_uv_file_retain(handle);
    const retained = uv.pi_uv_file_release(handle);
    try std.testing.expectEqual(@as(c_int, 0), retained.closed_by_release);
    try std.testing.expectEqual(@as(c_int, 0), fdStatus(descriptor));
    try std.testing.expectEqual(@as(c_int, 0), uv.pi_uv_file_close_work(handle));
    try std.testing.expectEqual(descriptor, uv.pi_uv_file_descriptor(handle));
    try std.testing.expectEqual(@as(c_int, uv.UV_EBADF), fdStatus(descriptor));
    uv.pi_uv_file_finish_close(handle);
    try std.testing.expectEqual(@as(c_int, -1), uv.pi_uv_file_descriptor(handle));
    try std.testing.expectEqual(count + 1, uv.pi_uv_file_live_handles());
    const released = uv.pi_uv_file_release(handle);
    alive = false;
    try std.testing.expectEqual(@as(c_int, 0), released.closed_by_release);
    try std.testing.expectEqual(count, uv.pi_uv_file_live_handles());
}

const TicketProbe = struct { complete: usize = 0, destroyed: usize = 0, worker_returned: bool = false, descriptor: c_int = -1 };
const Ticket = struct {
    task: hub_module.Task,
    packet: raw.Packet,
    path: [:0]u8,
    reference: wake.Ref,
    probe: *TicketProbe,
    fn work(base: *hub_module.Task) void {
        const self: *Ticket = @fieldParentPtr("task", base);
        const reference = self.reference;
        self.packet.run();
        if (self.packet.opened) |file| { self.probe.descriptor = @intCast(raw.descriptor(file) catch unreachable); }
        base.done.store(true, .release);
        wake.notify(reference);
    }
    fn cancel(base: *hub_module.Task) void { const self: *Ticket = @fieldParentPtr("task", base); self.packet.cancel(); }
    fn complete(base: *hub_module.Task) !void { const self: *Ticket = @fieldParentPtr("task", base); self.probe.complete += 1; return error.AbandonedWriterCallbackMustNotRun; }
    fn destroy(base: *hub_module.Task) void {
        const self: *Ticket = @fieldParentPtr("task", base);
        self.probe.destroyed += 1;
        self.probe.worker_returned = self.packet.completed;
        self.packet.retireUnadopted();
        const memory_owner = self.packet.memory_owner;
        wake.release(self.reference);
        gpa.free(self.path);
        gpa.destroy(self);
        c.pi_js_release_memory_owner(memory_owner);
    }
};
test "native actual filesystem writer Env shutdown joins and retires a real unadopted open" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(root);
    const path = try std.fs.path.join(gpa, &.{root,"abandoned.bin"});
    defer gpa.free(path);
    var probe: TicketProbe = .{};
    const engine = try a.v.em.Engine.init(gpa, .{});
    var alive = true;
    defer if (alive) engine.deinit();
    engine.native_io = io;
    const hub = try hub_module.get(engine);
    const reference = try wake_owner.acquireNativeWake(engine);
    var reference_moved = false;
    defer if (!reference_moved) wake.release(reference);
    const native_path = try gpa.dupeZ(u8, path);
    var path_moved = false;
    defer if (!path_moved) gpa.free(native_path);
    const ticket = try gpa.create(Ticket);
    var submitted = false;
    defer if (!submitted) gpa.destroy(ticket);
    c.pi_js_retain_memory_owner(engine.native_memory_owner);
    var memory_moved = false;
    defer if (!memory_moved) c.pi_js_release_memory_owner(engine.native_memory_owner);
    ticket.* = .{
        .task = .{ .hub = hub, .work = Ticket.work, .complete = Ticket.complete, .destroy = Ticket.destroy, .cancel = Ticket.cancel, .resolve = c.pi_js_undefined(), .reject = c.pi_js_undefined() },
        .packet = .{ .io = io, .operation = .open, .path = native_path, .windows_path = native_path, .memory_owner = engine.native_memory_owner },
        .path = native_path, .reference = reference, .probe = &probe,
    };
    const count = uv.pi_uv_file_live_handles();
    try hub.submit(&ticket.task);
    submitted = true; reference_moved = true; path_moved = true; memory_moved = true;
    var attempts: usize = 0;
    while (!ticket.task.done.load(.acquire) and attempts < 10000) : (attempts += 1)
        try io.sleep(.fromMilliseconds(1), .awake);
    try std.testing.expect(ticket.task.done.load(.acquire));
    if (ticket.packet.failure) |err| return err;
    try std.testing.expectEqual(@as(c_int, 0), ticket.packet.uv_status);
    try std.testing.expect(probe.descriptor >= 0);
    try std.testing.expectEqual(@as(c_int, 0), fdStatus(probe.descriptor));
    engine.deinit(); alive = false;
    try std.testing.expectEqual(@as(usize, 0), probe.complete);
    try std.testing.expectEqual(@as(usize, 1), probe.destroyed);
    try std.testing.expect(probe.worker_returned);
    try std.testing.expectEqual(@as(c_int, uv.UV_EBADF), fdStatus(probe.descriptor));
    try std.testing.expectEqual(count, uv.pi_uv_file_live_handles());
}
test "native actual filesystem writer invalid descriptor fails once through the real asynchronous task" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.run(
        \\let inCall=true,visits=0;
        \\const pending=new Promise((resolve,reject)=>fs.close(2147483647,error=>{
        \\  visits++;
        \\  try{check(!inCall&&error instanceof Error&&error.code==='EBADF','actual descriptor failure');resolve()}catch(e){reject(e)}
        \\}));
        \\inCall=false;await pending;check(visits===1,'one invalid descriptor completion');
    );
}
