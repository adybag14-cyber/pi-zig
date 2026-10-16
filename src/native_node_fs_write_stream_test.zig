//! Prepared real-IO and completion ownership controls. No execution accepted.
const std = @import("std");
const em = @import("extensions/engine.zig"); const c = em.c;
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const hub_mod = @import("extensions/native_env_io.zig");
const raw = @import("extensions/native_node_fs_write_io.zig");
const Probe = struct { complete: usize = 0, destroy: usize = 0, worker_returned: bool = false, unadopted_retired: usize = 0 };
const Ticket = struct {
    task: hub_mod.Task,
    probe: *Probe,
    packet: raw.Packet,
    fn work(base: *hub_mod.Task) void { const self: *Ticket = @fieldParentPtr("task", base); self.packet.run(); base.finish(); }
    fn cancel(_: *hub_mod.Task) void {}
    fn complete(base: *hub_mod.Task) !void {
        const self: *Ticket = @fieldParentPtr("task", base); self.probe.complete += 1; self.probe.worker_returned = self.packet.completed;
        if (self.packet.failure) |err| return err;
        // Native state is published before guest callback, and the callback
        // slot is consumed before call. The Hub must not replay it as reject.
        self.packet.retireUnadopted(); self.probe.unadopted_retired += 1;
        var scope: Scope = .{ .engine = base.hub.engine }; defer scope.deinit(); const callback = try scope.own(c.JS_DupValue(scope.engine.context, base.resolve)); scope.engine.freeValue(base.resolve); base.resolve = c.pi_js_undefined();
        _ = try scope.call(callback, c.pi_js_undefined(), &.{});
    }
    fn destroy(base: *hub_mod.Task) void {
        const self: *Ticket = @fieldParentPtr("task", base); self.probe.destroy += 1; self.probe.worker_returned = self.packet.completed;
        if (self.packet.opened != null) { self.packet.retireUnadopted(); self.probe.unadopted_retired += 1; }
        base.releaseFunctions(); base.hub.engine.gpa.destroy(self);
    }
};
fn install(engine: *em.Engine) !void {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-write-stream-controls"}); try @import("extensions/timers.zig").install(engine, std.testing.io);
}
fn observeConstructCapture(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    if (engine.captured_exception != null) return error.HandledConstructExceptionWasRetained;
    return c.pi_js_undefined();
}
test "native classic construct ordinary throw transfers capture before original failure tick" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/native_node_stream.zig").install(engine, try scope.get(global, "process"));
    try scope.put(global, "observeConstructCapture", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "observeConstructCapture", 0, observeConstructCapture, &.{})));
    const result = try engine.evalModule("import {Writable} from 'node:stream';import {finished} from 'node:stream/promises';const marker={};const original=process.nextTick;let observed=0;process.nextTick=function(fn,...args){if(fn.name==='onConstruct'){observeConstructCapture();observed++}return original.call(this,fn,...args)};const w=new Writable({construct(){throw marker},write(c,e,cb){cb()}});const reason=await finished(w).then(()=>null,e=>e);process.nextTick=original;if(reason!==marker||observed!==1)throw Error('construct reason identity or transfer boundary');export const proof=true;", "native-construct-capture-transfer.mjs"); engine.freeValue(result);
}
test "native writer retry SystemError retains Source string context and property descriptors" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/native_node_stream.zig").install(engine, try scope.get(global, "process"));
    try @import("extensions/native_node_fs_system_error.zig").install(engine);
    const mutated = try engine.eval("Object.defineProperty(globalThis,'Function',{configurable:true,get(){throw Error('late Function lookup intercepted retry')}});", "native-writer-late-function.js", c.JS_EVAL_TYPE_GLOBAL); engine.freeValue(mutated);
    try scope.put(global, "scalarFailure", try scope.own(try @import("extensions/native_node_fs_system_error.zig").retryFailure(&scope, false)));
    try scope.put(global, "vectorFailure", try scope.own(try @import("extensions/native_node_fs_system_error.zig").retryFailure(&scope, true)));
    const result = try engine.eval("for(const [e,context]of [[scalarFailure,'write failed'],[vectorFailure,'writev failed']]){if(!(e instanceof Error)||e.name!=='SystemError'||e.code!=='ERR_SYSTEM_ERROR'||e.info!==context||e.message!=='A system error occurred: undefined returned undefined (undefined)'||String(e)!=='SystemError [ERR_SYSTEM_ERROR]: '+e.message)throw Error('Source SystemError context');const d=Object.getOwnPropertyDescriptors(e);if(d.info.writable||!d.info.enumerable||d.name.enumerable||d.message.enumerable||typeof d.errno.get!=='function'||typeof d.errno.set!=='function'||!d.errno.enumerable||!d.syscall.enumerable)throw Error('SystemError descriptors');let threw=false;try{e.errno=3}catch(x){threw=x instanceof TypeError}if(!threw||e.errno!==undefined)throw Error('strict captured primitive context');const C=e.constructor;if(C.name!=='NodeError'||Object.getPrototypeOf(C).name!=='SystemError'||new C({syscall:'write',code:'EIO',message:'failure',errno:5}).errno!==5)throw Error('actual SystemError constructor chain')}", "native-writer-source-system-error.js", c.JS_EVAL_TYPE_GLOBAL); engine.freeValue(result);
}
test "native filesystem operation captures survive exported registry mutation and holder collection" {
    if (@import("builtin").os.tag == .windows) return error.RequiredReviewedWindowsCrtDescriptorBridge;
    var temporary = std.testing.tmpDir(.{}); defer temporary.cleanup(); const directory = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator); defer std.testing.allocator.free(directory); const path = try std.fs.path.join(std.testing.allocator, &.{ directory, "registry.bin" }); defer std.testing.allocator.free(path);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context)); const fs = try scope.object();
    try @import("extensions/native_node_fs_write_ops.zig").install(engine, fs);
    const owner = engine.native_module_values.get("pi-native:node-write-filesystem-operations").?;
    // The formerly dangerous mutable property can hold a real, unrelated
    // opaque function. Native callbacks must only use their private captures.
    try scope.put(owner, "registry", try scope.get(fs, "write"));
    try scope.put(global, "ownedOps", fs); try scope.put(global, "registryPath", try scope.text(path));
    const opened = try engine.evalModule("globalThis.registryFd=await new Promise((resolve,reject)=>ownedOps.open(registryPath,'w',438,(e,fd)=>e?reject(e):resolve(fd)));export const proof=true;", "native-registry-open.mjs"); engine.freeValue(opened);
    inline for (.{ "open", "write", "writev", "fsync", "close" }) |name| try scope.put(owner, name, c.pi_js_null());
    c.JS_RunGC(engine.runtime);
    const closed = try engine.evalModule("await new Promise((resolve,reject)=>ownedOps.close(registryFd,e=>e?reject(e):resolve()));export const proof=true;", "native-registry-close.mjs"); engine.freeValue(closed);
}
fn submitProbe(engine: *em.Engine, probe: *Probe, path: []const u8) !*Ticket {
    const hub = try hub_mod.get(engine); const ticket = try engine.gpa.create(Ticket); errdefer engine.gpa.destroy(ticket);
    const success = try js.global(engine, "completion"); errdefer engine.freeValue(success); const reject = try js.global(engine, "rejection"); errdefer engine.freeValue(reject);
    ticket.* = .{ .task = .{ .hub = hub, .work = Ticket.work, .complete = Ticket.complete, .destroy = Ticket.destroy, .cancel = Ticket.cancel, .resolve = success, .reject = reject, .propagate_completion_errors = true }, .probe = probe, .packet = .{ .io = std.testing.io, .operation = .open, .path = path } };
    try hub.submit(&ticket.task);
    return ticket;
}
test "native classic writer Hub propagates exact thrown completion once after real IO and task retirement" {
    var temporary = std.testing.tmpDir(.{}); defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator); defer std.testing.allocator.free(directory); const path = try std.fs.path.join(std.testing.allocator, &.{ directory, "completion.bin" }); defer std.testing.allocator.free(path);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    const prepared = try engine.eval("globalThis.marker={};globalThis.calls=0;globalThis.rejects=0;globalThis.completion=()=>{calls++;throw marker};globalThis.rejection=()=>rejects++;", "write-callback-throw.js", c.JS_EVAL_TYPE_GLOBAL); engine.freeValue(prepared);
    var probe: Probe = .{}; _ = try submitProbe(engine, &probe, path);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule("await new Promise(()=>{});", "write-completion-owner.mjs"));
    const marker = try js.global(engine, "marker"); defer engine.freeValue(marker); try std.testing.expect(c.JS_IsStrictEqual(engine.context, marker, engine.captured_exception.?));
    try std.testing.expectEqual(@as(usize, 1), probe.complete); try std.testing.expectEqual(@as(usize, 1), probe.destroy); try std.testing.expectEqual(@as(usize, 1), probe.unadopted_retired); try std.testing.expect(probe.worker_returned); try std.testing.expectEqual(@as(usize, 0), (try hub_mod.get(engine)).tasks.items.len);
    const verified = try engine.eval("if(calls!==1||rejects!==0)throw Error('completion replayed or lost');", "write-callback-once.js", c.JS_EVAL_TYPE_GLOBAL); engine.freeValue(verified);
}
test "native classic writer shutdown retires unadopted real open after worker return without guest callback" {
    var temporary = std.testing.tmpDir(.{}); defer temporary.cleanup(); const directory = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator); defer std.testing.allocator.free(directory); const path = try std.fs.path.join(std.testing.allocator, &.{ directory, "shutdown.bin" }); defer std.testing.allocator.free(path);
    const engine = try em.Engine.init(std.testing.allocator, .{}); var alive = true; defer if (alive) engine.deinit(); try install(engine);
    const prepared = try engine.eval("globalThis.completion=()=>{throw Error('shutdown callback ran')};globalThis.rejection=()=>{throw Error('shutdown reject ran')};", "write-shutdown.js", c.JS_EVAL_TYPE_GLOBAL); engine.freeValue(prepared);
    var probe: Probe = .{}; const ticket = try submitProbe(engine, &probe, path);
    // Observe actual worker completion without pumping its guest callback, then
    // test shutdown's abandoned-ticket and unadopted-handle retirement path.
    var polls: usize = 0; while (!ticket.task.done.load(.acquire) and polls < 1000) : (polls += 1) try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    try std.testing.expect(ticket.task.done.load(.acquire)); if (ticket.packet.failure) |err| return err; try std.testing.expect(ticket.packet.opened != null);
    engine.deinit(); alive = false;
    try std.testing.expectEqual(@as(usize, 0), probe.complete); try std.testing.expectEqual(@as(usize, 1), probe.destroy); try std.testing.expect(probe.worker_returned);
    try std.testing.expectEqual(@as(usize, 1), probe.unadopted_retired);
}
test "native classic writer construct completion retains Node tick order and empty end finalization" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context)); try @import("extensions/native_node_stream.zig").install(engine, try scope.get(global, "process"));
    const result = try engine.evalModule("import {Writable} from 'node:stream';import {finished} from 'node:stream/promises';const trace=[];const w=new Writable({construct(cb){trace.push('construct');cb();trace.push('after-callback')},write(c,e,cb){trace.push('write');cb()}});w.on('finish',()=>trace.push('finish'));w.end('x');await finished(w);if(trace.join(',')!=='construct,after-callback,write,finish')throw Error('construct completion bypassed real onConstruct tick');const empty=new Writable({construct(cb){cb()},write(c,e,cb){cb()}});empty.end();await finished(empty);if(!empty.writableFinished||!empty.closed)throw Error('ending-before-construct never finalized');export const proof=true;", "native-writer-construct-order.mjs"); engine.freeValue(result); engine.finishJob(); c.JS_RunGC(engine.runtime);
}
test "native classic writer actual Web reader pipeline owns real output file and close" {
    var temporary = std.testing.tmpDir(.{}); defer temporary.cleanup(); const directory = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator); defer std.testing.allocator.free(directory); const path = try std.fs.path.join(std.testing.allocator, &.{ directory, "download.bin" }); defer std.testing.allocator.free(path);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/node_fs.zig").installWithStreams(engine, std.testing.io, try scope.get(global, "process")); try @import("extensions/native_node_stream_web.zig").install(engine); try scope.put(global, "outputPath", try scope.text(path));
    const result = try engine.evalModule("import {Readable,Writable} from 'node:stream';import {pipeline} from 'node:stream/promises';import {ReadableStream} from 'node:stream/web';import {createWriteStream,readFileSync} from 'node:fs';const trace=[];const source=new ReadableStream({start(c){c.enqueue(new Uint8Array([0,239,187]));c.enqueue(new Uint8Array([191,65,240,159,140,141]));c.close()}});const target=createWriteStream(outputPath);if(!(target instanceof Writable))throw Error('real Writable required');target.on('open',()=>trace.push('open'));target.on('ready',()=>trace.push('ready'));target.on('finish',()=>trace.push('finish'));target.on('close',()=>trace.push('close'));await pipeline(Readable.fromWeb(source),target);if(Array.from(readFileSync(outputPath)).join(',')!=='0,239,187,191,65,240,159,140,141'||target.bytesWritten!==9||!target.closed||target.fd!==null||trace.indexOf('finish')>trace.indexOf('close'))throw Error('real pipeline IO/retirement mismatch');export const proof=true;", "native-write-stream-real-download.mjs"); engine.freeValue(result); engine.finishJob(); c.JS_RunGC(engine.runtime);
}
test "native classic writer Source8 complete original packets required" {
    const marker = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("extensions/fixtures/node-fs-write-stream-node24.capture-pending.json"), .{}); defer marker.deinit();
    if (!marker.value.object.get("captureAccepted").?.bool) return error.GenuineNodeWriteStreamSource8NotCapturedOrAccepted;
    const cases = [_][]const u8{ "default-binary-web-pipeline", "custom-partial-write", "custom-cork-writev", "destroy-during-write", "flush-close-order", "autoClose-false-close", "monkey-open-override", "writer-namespace-metadata" };
    for (cases) |case_name| {
        var temporary = std.testing.tmpDir(.{}); defer temporary.cleanup(); const directory = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator); defer std.testing.allocator.free(directory); const path = try std.fs.path.join(std.testing.allocator, &.{ directory, "source-writer.bin" }); defer std.testing.allocator.free(path);
        const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
        var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        try @import("extensions/node_fs.zig").installWithStreams(engine, std.testing.io, try scope.get(global, "process")); try @import("extensions/native_node_stream_web.zig").install(engine); try scope.put(global, "outputPath", try scope.text(path)); try scope.put(global, "caseName", try scope.text(case_name));
        const expected = @embedFile("extensions/fixtures/node-fs-write-stream-node24.capture-pending.json"); try scope.put(global, "writerSource8", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "writer-source8-capture-state.json"))));
        const value = engine.evalModule(@embedFile("extensions/fixtures/node-fs-write-stream-node24.input.txt") ++ "\nif(JSON.stringify(packet)!==JSON.stringify(writerSource8.expectedPackets[caseName]))throw Error(JSON.stringify({case:caseName,actual:packet,expected:writerSource8.expectedPackets[caseName]}));export const proof=true;", "native-writer-source8.mjs") catch |err| { std.debug.print("Native writer Source8 {s}: {s}\n", .{ case_name, engine.last_error orelse "no diagnostic" }); return err; }; engine.freeValue(value); engine.finishJob(); c.JS_RunGC(engine.runtime);
    }
}
