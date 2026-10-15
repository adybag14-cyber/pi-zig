const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const immediates = @import("extensions/native_immediates.zig");
const c = em.c;
const Poll = struct {
    engine: *em.Engine,
    records: std.ArrayList(c.JSValue) = .empty,
    real_reads: usize = 0,
    fn deinit(self: *Poll) void {
        for (self.records.items) |value| self.engine.freeValue(value);
        self.records.deinit(self.engine.gpa);
        self.engine.host_control_context = null;
        self.engine.host_control_pump = null;
    }
    fn dispatch(engine: *em.Engine) !bool {
        const self: *Poll = @ptrCast(@alignCast(engine.host_control_context.?));
        if (self.records.items.len == 0 or c.JS_IsJobPending(engine.runtime)) return false;
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const record = try scope.own(self.records.orderedRemove(0));
        _ = scope.call(try scope.get(record, "callback"), c.pi_js_undefined(), &.{try scope.text("immediate-phase-probe")}) catch |err| {
            const reason = try scope.own(@import("extensions/native_agent_async.zig").reason(engine, err));
            _ = try scope.call(try scope.get(record, "reject"), c.pi_js_undefined(), &.{reason});
            return true;
        };
        _ = try scope.call(try scope.get(record, "resolve"), c.pi_js_undefined(), &.{});
        return true;
    }
    fn run(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = em.Engine.fromContext(context.?);
        const self: *Poll = @ptrCast(@alignCast(engine.host_control_context.?));
        return self.exchange(if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("extensions/native_durable.zig").reject(engine, err);
    }
    fn exchange(self: *Poll, callback: c.JSValue) !c.JSValue {
        // This caller-owned adapter uses real kernel TCP bytes, then dispatches
        // its record on the VM owner after the microtask checkpoint. It does
        // not emulate or qualify a general node:net implementation.
        const io = std.testing.io;
        const address = try std.Io.net.IpAddress.parseLiteral("127.0.0.1:0");
        var listener = try address.listen(io, .{ .reuse_address = false });
        defer listener.deinit(io);
        const client = try listener.socket.address.connect(io, .{ .mode = .stream, .protocol = .tcp });
        defer client.close(io);
        const accepted = try listener.accept(io);
        defer accepted.close(io);
        var write_buffer: [128]u8 = undefined;
        var writer = client.writer(io, &write_buffer);
        try writer.interface.writeAll("immediate-phase-probe");
        try writer.interface.flush();
        var read_buffer: [128]u8 = undefined;
        var reader = accepted.reader(io, &read_buffer);
        var payload: [21]u8 = undefined;
        try reader.interface.readSliceAll(&payload);
        try std.testing.expectEqualStrings("immediate-phase-probe", &payload);
        self.real_reads += 1;
        const engine = self.engine;
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        var caps: [2]c.JSValue = undefined;
        const promise = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &caps)));
        defer for (caps) |value| engine.freeValue(value);
        const record = try scope.object();
        try scope.put(record, "callback", callback);
        try scope.put(record, "resolve", caps[0]);
        try scope.put(record, "reject", caps[1]);
        const queued = c.JS_DupValue(engine.context, record);
        errdefer engine.freeValue(queued);
        try self.records.append(engine.gpa, queued);
        em.Engine.notifyOwner(engine);
        return c.JS_DupValue(engine.context, promise);
    }
};
fn forceGC(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(em.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
fn install(engine: *em.Engine, poll: *Poll) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    poll.* = .{ .engine = engine };
    engine.host_control_context = poll;
    engine.host_control_pump = Poll.dispatch;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "runInPoll", try engine.checked(c.JS_NewCFunction(engine.context, Poll.run, "runInPoll", 1)));
    try js.define(engine, global, "forceGC", try engine.checked(c.JS_NewCFunction(engine.context, forceGC, "forceGC", 0)));
}
test "native immediates match actual Node24 FIFO check batches microtasks handles cancellation and real loopback poll" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var poll: Poll = undefined;
    try install(engine, &poll);
    defer poll.deinit();
    const expected = @embedFile("extensions/fixtures/immediates-node24.json");
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "immediateSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "immediates-node24.json")));
    const value = engine.evalModule(@embedFile("extensions/fixtures/immediates-node24.input.txt") ++
        "\nif(immediateSource.nodeVersion!=='v24.14.0'||immediateSource.realLoopbackPolls!==3||immediateRows.length!==immediateSource.count)throw Error('complete genuine Node immediate controls required');for(let i=0;i<immediateRows.length;i++)if(JSON.stringify(immediateRows[i])!==JSON.stringify(immediateSource.rows[i]))throw Error(JSON.stringify({case:i,actual:immediateRows[i],expected:immediateSource.rows[i]}));", "native-immediates-node24.mjs") catch |err| {
        std.debug.print("Immediate controls: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(value);
    try std.testing.expectEqual(@as(usize, 3), poll.real_reads);
    try std.testing.expect(!immediates.pending(engine));
    c.JS_RunGC(engine.runtime);
}
test "native immediates preserve callback throw identity outstanding batch and shutdown ownership" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try immediates.install(engine);
    const prepared = try engine.eval("globalThis.marker={};globalThis.trace=[];setImmediate(()=>{trace.push('throw');throw marker});setImmediate(()=>trace.push('after'));", "immediate-throw.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(prepared);
    try std.testing.expectError(error.JavaScriptException, immediates.pump(engine));
    const marker = try js.global(engine, "marker");
    defer engine.freeValue(marker);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, marker, engine.captured_exception.?));
    try std.testing.expect(try immediates.pump(engine));
    const checked = try engine.eval("if(trace.join(',')!=='throw,after')throw Error('outstanding check batch lost');setImmediate(()=>{throw Error('shutdown callback ran')});", "immediate-shutdown.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(checked);
    try std.testing.expect(immediates.pending(engine));
    c.JS_RunGC(engine.runtime);
}
