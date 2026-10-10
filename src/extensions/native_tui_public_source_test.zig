const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
fn stdinEndEnterData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    // Test the effect of Source AsyncLocalStorage.enterWith inside final data.
    // The native producer's outer guard restores its prior caller afterward.
    const guard = @import("native_async_scope.zig").enter(engine, data[0]);
    engine.freeValue(guard.previous);
    return c.pi_js_undefined();
}
test "Source6fb public TUI slice actual Node pipe EOF decoder tail pause and async owner checkpoints" {
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/node-stdin-eof-startup-original-24.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items, 0..) |sample, index| {
        const engine = try js.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        var environment: std.process.Environ.Map = .init(std.testing.allocator);
        defer environment.deinit();
        try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"stdin-end-source"});
        const streams = @import("native_process_streams.zig");
        var probe: TerminalBridgeProbe = .{};
        defer probe.deinit();
        const lease = try streams.bind(engine, probe.bridge());
        defer _ = streams.unbind(engine, lease);
        const scopes = @import("native_async_scope.zig");
        var registration: EventOwnerProbe = .{ .engine = engine, .id = 1 };
        var data_owner: EventOwnerProbe = .{ .engine = engine, .id = 2 };
        const registration_token = try scopes.create(engine, &registration, EventOwnerProbe.activate, EventOwnerProbe.deactivate);
        defer engine.freeValue(registration_token);
        const data_token = try scopes.create(engine, &data_owner, EventOwnerProbe.activate, EventOwnerProbe.deactivate);
        defer engine.freeValue(data_token);
        const root = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(root);
        try js.define(engine, root, "eventOwnerProbe", c.JS_NewInt32(engine.context, 0));
        const mode = sample.object.get("mode").?.string;
        try js.define(engine, root, "stdinEndMode", try engine.checked(c.JS_NewStringLen(engine.context, mode.ptr, mode.len)));
        var callback_data = [_]c.JSValue{data_token};
        try js.define(engine, root, "stdinEndEnterData", try engine.checked(c.JS_NewCFunctionData2(engine.context, stdinEndEnterData, "enterWith", 0, 0, 1, &callback_data)));
        const expected = try std.json.Stringify.valueAlloc(std.testing.allocator, sample.object.get("value").?, .{});
        defer std.testing.allocator.free(expected);
        try js.define(engine, root, "stdinEndExpected", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "stdin-end-source-value.json")));
        {
            const guard = scopes.enter(engine, registration_token);
            defer guard.restore();
            const setup = try engine.evalModule(@embedFile("fixtures/node-stdin-eof-native-replay.input.txt"), "stdin-end-register.mjs");
            engine.freeValue(setup);
        }
        _ = try engine.drainReadyJobs();
        var input: [16]u8 = undefined;
        const bytes = sample.object.get("bytes").?.array.items;
        if (bytes.len > input.len) return error.StdinEndFixtureLimit;
        for (bytes, 0..) |byte, offset| input[offset] = @intCast(byte.integer);
        {
            const guard = scopes.enter(engine, c.pi_js_undefined());
            defer guard.restore();
            try streams.deliverInput(engine, input[0..bytes.len]);
        }
        _ = try engine.drainReadyJobs();
        if (!std.mem.eql(u8, mode, "paused")) {
            const guard = scopes.enter(engine, c.pi_js_undefined());
            defer guard.restore();
            try streams.deliverEnd(engine);
            try streams.deliverEnd(engine);
        }
        _ = try engine.drainReadyJobs();
        if (std.mem.eql(u8, mode, "paused") or std.mem.eql(u8, mode, "prefetched")) {
            const resumed = try engine.eval("stdinEndSeen.push(['before-resume',stdinEndSeen.length,stdinEndScope()]);process.stdin.resume();", "stdin-end-resume.js", c.JS_EVAL_TYPE_GLOBAL);
            engine.freeValue(resumed);
            _ = try engine.drainReadyJobs();
        }
        if (std.mem.eql(u8, mode, "paused")) {
            // Actual pipe IO resumes its producer before a later EOF turn.
            // The separate prefetched Readable case delivers EOF beforehand.
            const guard = scopes.enter(engine, c.pi_js_undefined());
            defer guard.restore();
            try streams.deliverEnd(engine);
            try streams.deliverEnd(engine);
            _ = try engine.drainReadyJobs();
        }
        const checked = engine.eval(
            \\const observed={seen:stdinEndSeen,paused:process.stdin.isPaused()};if(JSON.stringify(observed)!==JSON.stringify(stdinEndExpected))throw Error(JSON.stringify({mode:stdinEndMode,actual:observed,expected:stdinEndExpected}));if(stdinEndSeen.filter(entry=>entry[0]==='end').length!==1)throw Error('native EOF emitted twice');
        , "stdin-end-compare.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
            if (engine.last_error) |message| std.debug.print("Native stdin EOF Source case {d}: {s}\n", .{ index, message });
            return err;
        };
        engine.freeValue(checked);
        try std.testing.expectError(error.NativeTerminalInputAfterEnd, streams.deliverInput(engine, "after EOF"));
        {
            const guard = scopes.enter(engine, registration_token);
            defer guard.restore();
            const manual = try engine.eval("process.stdin.emit('end');if(JSON.stringify(stdinEndSeen.at(-1))!==JSON.stringify(['end','registration']))throw Error('manual end adopted producer scope');", "stdin-end-manual.js", c.JS_EVAL_TYPE_GLOBAL);
            engine.freeValue(manual);
        }
        const restored = scopes.capture(engine);
        defer engine.freeValue(restored);
        try std.testing.expect(c.JS_IsUndefined(restored));
    }
}
const StdinRebindProbe = struct {
    bridge: *TerminalBridgeProbe,
    lease: ?@import("native_process_streams.zig").Lease = null,
    fn call(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = js.Engine.fromContext(context.?);
        const self: *@This() = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], c.JS_GetClassID(data[0])).?));
        self.lease = @import("native_process_streams.zig").bind(engine, self.bridge.bridge()) catch |err| {
            if (err == error.JavaScriptException) return engine.throwCaptured();
            if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
            return c.JS_ThrowTypeError(context, "Native test rebind: %s", @as([*:0]const u8, @errorName(err)));
        };
        return c.pi_js_undefined();
    }
};
test "Source6fb public TUI slice native stdin exact lease admission drops stale same-context input resize and EOF" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"stdin-end-generation"});
    const streams = @import("native_process_streams.zig");
    var probe: TerminalBridgeProbe = .{};
    defer probe.deinit();
    const first = try streams.bind(engine, probe.bridge());
    var rebinding: StdinRebindProbe = .{ .bridge = &probe };
    var helper_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &helper_class);
    const helper_definition: c.JSClassDef = .{ .class_name = "Test owner-thread stdin rebind" };
    if (c.JS_NewClass(engine.runtime, helper_class, &helper_definition) < 0) return error.OutOfMemory;
    const holder = try engine.checked(c.JS_NewObjectClass(engine.context, helper_class));
    defer engine.freeValue(holder);
    _ = c.JS_SetOpaque(holder, &rebinding);
    var helper_data = [_]c.JSValue{holder};
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "stdinLeaseRebind", try engine.checked(c.JS_NewCFunctionData2(engine.context, StdinRebindProbe.call, "rebind", 0, 0, 1, &helper_data)));
    const setup = try engine.eval("var leaseEnds=0,leaseData=[],leaseResize=0,leaseShouldRebind=true;process.stdin.setEncoding('utf8');process.stdin.on('data',value=>{leaseData.push(value);if(leaseShouldRebind){leaseShouldRebind=false;stdinLeaseRebind();}});process.stdin.on('end',()=>leaseEnds++);process.stdout.on('resize',()=>leaseResize++);", "stdin-lease-setup.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(setup);
    _ = try engine.drainReadyJobs();
    try streams.deliverInput(engine, &.{ 0xe7, 0x95 });
    // EOF first queues end, then its final decoder-tail data listener replaces
    // the binding synchronously. The host checkpoint must drop that old end.
    try streams.deliverEnd(engine);
    const second = rebinding.lease orelse return error.NativeStdinRebindDidNotRun;
    defer _ = streams.unbind(engine, second);
    const boundary = try engine.eval("if(leaseEnds!==0||JSON.stringify(leaseData)!=='[\"�\"]')throw Error(JSON.stringify({leaseEnds,leaseData}));leaseData=[];", "stdin-lease-pending-boundary.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(boundary);
    try std.testing.expect(!streams.ownsLease(engine, first));
    try std.testing.expect(streams.ownsLease(engine, second));
    try std.testing.expect(!streams.ownsLease(engine, .{ .context = second.context, .generation = second.generation + (@as(u64, 1) << 53) }));
    // This is the SDK producer's native admission pattern for queued records.
    if (streams.ownsLease(engine, first)) {
        try streams.deliverInput(engine, "stale");
        try streams.deliverResize(engine, 999, 999);
        try streams.deliverEnd(engine);
    }
    _ = try engine.drainReadyJobs();
    const resumed = try engine.eval("process.stdin.resume();", "stdin-lease-resume.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(resumed);
    _ = try engine.drainReadyJobs();
    try streams.deliverInput(engine, "current");
    try streams.deliverResize(engine, 40, 12);
    try streams.deliverEnd(engine);
    _ = try engine.drainReadyJobs();
    const checked = try engine.eval("if(leaseEnds!==1||JSON.stringify(leaseData)!=='[\"current\"]'||leaseResize!==1)throw Error(JSON.stringify({leaseEnds,leaseData,leaseResize}));", "stdin-lease-result.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(checked);
    probe.live = false;
    try std.testing.expectError(error.NativeProcessStreamLeaseStale, streams.deliverEnd(engine));
}
test "Source6fb public TUI slice actual Node UTF8 StringDecoder fragmented invalid groups and EOF replacement" {
    try verifyStdinDecoder(@embedFile("fixtures/node-stdin-decoder-original-24.json"), "original fragments");
    try verifyStdinDecoder(@embedFile("fixtures/node-stdin-decoder-invalid-leads-original-24.json"), "invalid leading bytes");
}
fn verifyStdinDecoder(fixture_bytes: []const u8, label: []const u8) !void {
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, fixture_bytes, .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items, 0..) |sample, index| {
        const engine = try js.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        var environment: std.process.Environ.Map = .init(std.testing.allocator);
        defer environment.deinit();
        try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"stdin-decoder-source"});
        const streams = @import("native_process_streams.zig");
        var probe: TerminalBridgeProbe = .{};
        defer probe.deinit();
        const lease = try streams.bind(engine, probe.bridge());
        defer _ = streams.unbind(engine, lease);
        const setup = try engine.eval("var decoderData=[],decoderEnds=0;process.stdin.setEncoding('utf8');process.stdin.on('data',value=>decoderData.push(value));process.stdin.on('end',()=>decoderEnds++);", "stdin-decoder-setup.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(setup);
        _ = try engine.drainReadyJobs();
        for (sample.object.get("frames").?.array.items) |frame| {
            var bytes: [16]u8 = undefined;
            if (frame.array.items.len > bytes.len) return error.StdinDecoderFixtureLimit;
            for (frame.array.items, 0..) |value, offset| bytes[offset] = @intCast(value.integer);
            try streams.deliverInput(engine, bytes[0..frame.array.items.len]);
            _ = try engine.drainReadyJobs();
        }
        try streams.deliverEnd(engine);
        _ = try engine.drainReadyJobs();
        const expected = try std.json.Stringify.valueAlloc(std.testing.allocator, sample.object.get("data").?, .{});
        defer std.testing.allocator.free(expected);
        const root = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(root);
        try js.define(engine, root, "decoderExpected", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "stdin-decoder-source-value.json")));
        const checked = engine.eval("if(decoderEnds!==1||JSON.stringify(decoderData)!==JSON.stringify(decoderExpected))throw Error(JSON.stringify({decoderEnds,actual:decoderData,expected:decoderExpected}));", "stdin-decoder-compare.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
            if (engine.last_error) |message| std.debug.print("Native stdin decoder {s} Source case {d}: {s}\n", .{ label, index, message });
            return err;
        };
        engine.freeValue(checked);
    }
}
fn resourceContextFence(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    @import("native_async_scope.zig").requireBindingLive(engine, true) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowTypeError(context, "Native captured ctx: %s", @as([*:0]const u8, @errorName(err)));
    };
    return c.pi_js_bool(context, 1);
}
test "Source6fb public TUI slice genuine SDK dispose retains resource pure code and global stdout while captured ctx stales" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"resource-post-dispose"});
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/sdk-global-stdio-scope-source-20261010-a.json");
    try js.define(engine, root, "resourceLifecycleSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "sdk-global-stdio-scope-source-20261010-a.json")));
    try js.define(engine, root, "resourceCapturedIsIdle", try engine.checked(c.JS_NewCFunction2(engine.context, resourceContextFence, "isIdle", 0, c.JS_CFUNC_generic, 0)));
    var result = try engine.evalModule(
        \\import{EventEmitterAsyncResource}from'node:events';globalThis.ResourceLifecycleEmitter=EventEmitterAsyncResource;
        \\globalThis.resourceLifecycleSeen=[];globalThis.resourceLifecycleExpected=resourceLifecycleSource.stdioScope.filter(record=>record.kind.startsWith('resource-')||(record.kind==='write'&&record.text==='resource-output'));
        \\globalThis.resourceStaleContextMessage=resourceLifecycleExpected.find(record=>record.kind==='resource-context-error').message;
        \\process.stdout={write(value){resourceLifecycleSeen.push({kind:'write',text:String(value),receiver:this===process.stdout});return true;}};
    , "resource-lifecycle-setup.mjs");
    engine.freeValue(result);
    const scopes = @import("native_async_scope.zig");
    var owner: EventOwnerProbe = .{ .engine = engine, .id = 1 };
    const token = try scopes.create(engine, &owner, EventOwnerProbe.activate, EventOwnerProbe.deactivate);
    defer engine.freeValue(token);
    scopes.markSdk(engine, token);
    {
        const guard = scopes.enter(engine, token);
        defer guard.restore();
        result = try engine.eval("var resourceLifecycleValue=new ResourceLifecycleEmitter('source-sdk-callback');resourceLifecycleValue.on('probe',()=>{resourceLifecycleSeen.push({kind:'resource-pure'});process.stdout.write('resource-output');try{resourceLifecycleSeen.push({kind:'resource-context',idle:resourceCapturedIsIdle()});}catch(error){resourceLifecycleSeen.push({kind:'resource-context-error',name:error.name,message:error.message});}});", "resource-lifecycle-original-owner.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(result);
    }
    const message_value = try js.get(engine, root, "resourceStaleContextMessage");
    defer engine.freeValue(message_value);
    const message = try engine.toString(message_value);
    defer engine.gpa.free(message);
    try scopes.denyWithMessage(engine, token, message);
    scopes.retire(engine, token);
    result = engine.eval("resourceLifecycleValue.emit('probe');if(JSON.stringify(resourceLifecycleSeen)!==JSON.stringify(resourceLifecycleExpected))throw Error(JSON.stringify({actual:resourceLifecycleSeen,expected:resourceLifecycleExpected}));", "resource-lifecycle-after-dispose.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
        if (engine.last_error) |failure| std.debug.print("Native resource post-dispose: {s}\n", .{failure});
        return err;
    };
    engine.freeValue(result);
    try std.testing.expect(!scopes.isSdkScope(engine));
}

const TerminalBridgeProbe = struct {
    engine: ?*js.Engine = null,
    live: bool = true,
    bytes: std.ArrayList(u8) = .empty,
    controls: std.ArrayList(u8) = .empty,
    fn guard(raw: ?*anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (!self.live) return error.NativeProcessStreamLeaseStale;
    }
    fn control(raw: ?*anyopaque, value: @import("native_process_streams.zig").Control) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        try self.controls.append(std.testing.allocator, switch (value) {
            .raw_mode => |enabled| if (enabled) 'T' else 'F',
            .@"resume" => 'R',
            .pause => 'P',
            .encoding => 'U',
        });
    }
    fn write(raw: ?*anyopaque, output: @import("native_process_streams.zig").Output, bytes: []const u8) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (output == .stderr) try self.bytes.append(std.testing.allocator, 'E');
        try self.bytes.appendSlice(std.testing.allocator, bytes);
    }
    fn bridge(self: *@This()) @import("native_process_streams.zig").Bridge {
        return .{ .context = self, .guard_fn = guard, .control_fn = control, .write_fn = write, .is_shift_pressed_fn = if (self.engine != null) shift else null, .enable_vt_input_fn = if (self.engine != null) enableVT else null };
    }
    fn helperFailure(self: *@This()) !void {
        const engine = self.engine.?;
        const reason = try js.global(engine, "terminalHelperError");
        defer engine.freeValue(reason);
        if (c.JS_ToBool(engine.context, reason) != 0) {
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
            unreachable;
        }
    }
    fn shift(raw: ?*anyopaque) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const engine = self.engine.?;
        const calls = try js.global(engine, "terminalHelperCalls");
        defer engine.freeValue(calls);
        const pair = try js.array(engine);
        defer engine.freeValue(pair);
        if (c.JS_DefinePropertyValueUint32(engine.context, pair, 0, try engine.checked(c.JS_NewString(engine.context, "modifier")), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        if (c.JS_DefinePropertyValueUint32(engine.context, pair, 1, try engine.checked(c.JS_NewString(engine.context, "shift")), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        try js.push(engine, calls, pair);
        try self.helperFailure();
        const pressed = try js.global(engine, "terminalHelperShift");
        defer engine.freeValue(pressed);
        return c.JS_IsStrictEqual(engine.context, pressed, c.pi_js_bool(engine.context, 1));
    }
    fn enableVT(raw: ?*anyopaque) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const engine = self.engine.?;
        const calls = try js.global(engine, "terminalHelperCalls");
        defer engine.freeValue(calls);
        const value = try engine.checked(c.JS_NewString(engine.context, "vt"));
        defer engine.freeValue(value);
        try js.push(engine, calls, value);
        try self.helperFailure();
        return true;
    }
    fn deinit(self: *@This()) void {
        self.bytes.deinit(std.testing.allocator);
        self.controls.deinit(std.testing.allocator);
    }
};
test "Source6fb public TUI slice actual Source pipe terminal startup skips raw mode and preserves missing metadata" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"source-actual-pipe"});
    try @import("native_tui.zig").install(engine);
    const streams = @import("native_process_streams.zig");
    var probe: TerminalBridgeProbe = .{};
    defer probe.deinit();
    const lease = try streams.bind(engine, probe.bridge());
    defer _ = streams.unbind(engine, lease);
    try streams.hydrateInput(engine, false, false);
    try streams.hydrateOutput(engine, false, false, null, null);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/process-terminal-actual-pipe-original-6fb.json");
    try js.define(engine, root, "actualPipeSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "process-terminal-actual-pipe-original-6fb.json")));
    const result = engine.evalModule(@embedFile("fixtures/process-terminal-actual-pipe-original-6fb.input.txt") ++
        \\if(JSON.stringify(observed)!==JSON.stringify(actualPipeSource.value))throw Error(JSON.stringify({actual:observed,expected:actualPipeSource.value}));
    , "process-terminal-actual-pipe.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native actual Source pipe terminal: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
    try std.testing.expectEqualStrings("URRP", probe.controls.items);
}
test "Source6fb public TUI slice terminal metadata restores raw identity and independent output availability" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"source-stream-metadata"});
    try @import("native_tui.zig").install(engine);
    const streams = @import("native_process_streams.zig");
    var result = try engine.eval("var savedRawMethod=process.stdin.setRawMode;", "stream-raw-method.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    try streams.hydrateInput(engine, false, false);
    try streams.hydrateOutput(engine, false, true, null, null);
    result = try engine.eval("if('setRawMode' in process.stdin||'isRaw' in process.stdin||'isTTY' in process.stdin||'isTTY' in process.stdout||process.stderr.isTTY!==true||'columns' in process.stdout||'rows' in process.stdout)throw Error('pipe stream metadata');", "stream-pipe-metadata.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    try streams.hydrateInput(engine, true, true);
    try streams.hydrateOutput(engine, true, false, 0, 0);
    result = try engine.evalModule("import{ProcessTerminal}from'pi-tui';const t=new ProcessTerminal();if(process.stdin.setRawMode!==savedRawMethod||process.stdin.isRaw!==true||process.stdin.isTTY!==true||process.stdout.isTTY!==true||'isTTY' in process.stderr||process.stdout.columns!==0||process.stdout.rows!==0||t.columns!==80||t.rows!==24)throw Error('console stream metadata');", "stream-console-metadata.mjs");
    engine.freeValue(result);
}
test "Source6fb public TUI slice genuine ProcessTerminal source class fields negotiation status timers drain and IO" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"process-terminal-source"});
    try @import("node_fs.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    const streams = @import("native_process_streams.zig");
    var probe: TerminalBridgeProbe = .{ .engine = engine };
    defer probe.deinit();
    const lease = try streams.bind(engine, probe.bridge());
    defer _ = streams.unbind(engine, lease);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    try js.define(engine, root, "terminalLogDirectory", try engine.checked(c.JS_NewStringLen(engine.context, &path_buffer, path_length)));
    const bytes = @embedFile("fixtures/process-terminal-original-6fb.json");
    try js.define(engine, root, "processTerminalSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "process-terminal-original-6fb.json")));
    const result = engine.evalModule("import{ProcessTerminal,setKittyProtocolActive,isKittyProtocolActive}from'pi-tui';import{EventEmitter}from'node:events';import*as fixtureFs from'node:fs';\n" ++ @embedFile("fixtures/process-terminal-original-6fb.input.txt") ++
        \\for(let i=0;i<processTerminalSource.cases.length;i++){const actual=processTerminalResults[i],expected=processTerminalSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected,...(typeof processTerminalLastError!=='undefined'?{stack:processTerminalLastError.stack}:{})}));}
    , "process-terminal-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native ProcessTerminal Source: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice native terminal streams exact leases buffered UTF8 and deferred resume" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"terminal-stream-probe"});
    const streams = @import("native_process_streams.zig");
    var probe: TerminalBridgeProbe = .{};
    defer probe.deinit();
    const old = try streams.bind(engine, probe.bridge());
    try streams.deliverInput(engine, "old generation input");
    const current = try streams.bind(engine, probe.bridge());
    try std.testing.expect(!streams.unbind(engine, old));
    try streams.hydrateDimensions(engine, 120, 40);
    try streams.hydrateInput(engine, true, true);
    var result = try engine.eval("var streamSeen=[],resizeSeen=[];process.stdin.pause();process.stdin.setEncoding('utf8');process.stdin.on('data',value=>streamSeen.push(value));process.stdout.on('resize',()=>resizeSeen.push([process.stdout.columns,process.stdout.rows]));", "terminal-stream-setup.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    try streams.deliverInput(engine, "queued");
    result = try engine.eval("process.stdin.resume();process.stdin.on('data',value=>streamSeen.push('late:'+value));if(streamSeen.length)throw Error('resume must defer pending delivery');", "terminal-stream-resume.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    _ = try engine.drainReadyJobs();
    try streams.deliverInput(engine, "\xe7");
    try streams.deliverInput(engine, "\x95\x8c");
    try streams.deliverResize(engine, 90, 30);
    result = try engine.eval("if(JSON.stringify(streamSeen)!==JSON.stringify(['queued','late:queued','界','late:界'])||JSON.stringify(resizeSeen)!=='[[90,30]]')throw Error(JSON.stringify({streamSeen,resizeSeen}));", "terminal-stream-result.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    try std.testing.expect(streams.unbind(engine, current));
    try std.testing.expectError(error.NativeTerminalStreamsNotBound, streams.deliverInput(engine, "not delivered"));
}
test "Source6fb public TUI slice native terminal bridge and global stdout ignore unrelated retired SDK scope" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"terminal-stream-owner"});
    const streams = @import("native_process_streams.zig");
    var probe: TerminalBridgeProbe = .{};
    defer probe.deinit();
    const lease = try streams.bind(engine, probe.bridge());
    defer _ = streams.unbind(engine, lease);
    var result = try engine.eval("var ownedInput=[];process.stdin.setEncoding('utf8');process.stdin.on('data',value=>ownedInput.push(value));process.stdin.resume();", "terminal-stream-owner-setup.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    _ = try engine.drainReadyJobs();
    const scopes = @import("native_async_scope.zig");
    var retired_probe: EventOwnerProbe = .{ .engine = engine, .id = 77 };
    const retired = try scopes.create(engine, &retired_probe, EventOwnerProbe.activate, EventOwnerProbe.deactivate);
    defer engine.freeValue(retired);
    scopes.retire(engine, retired);
    {
        const guard = scopes.enter(engine, retired);
        defer guard.restore();
        try streams.deliverInput(engine, "authenticated");
        result = try engine.eval("if(process.stdout.write('process-global')!==true)throw Error('global process output incorrectly revoked by SDK scope');", "terminal-stream-global-output.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(result);
    }
    probe.live = false;
    try std.testing.expectError(error.NativeProcessStreamLeaseStale, streams.deliverInput(engine, "rejected"));
    result = try engine.eval("if(JSON.stringify(ownedInput)!=='[\"authenticated\"]')throw Error(JSON.stringify(ownedInput));", "terminal-stream-owner-result.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    try std.testing.expectEqualStrings("process-global", probe.bytes.items);
}
test "Source6fb public TUI slice native terminal byte output queued callbacks and unbound rejection" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"terminal-stream-output"});
    const streams = @import("native_process_streams.zig");
    var probe: TerminalBridgeProbe = .{};
    defer probe.deinit();
    var result = try engine.eval("let unbound=false;try{process.stdout.write('wrong');}catch(error){unbound=error.message.includes('NativeTerminalStreamsNotBound');}if(!unbound)throw Error('unbound stdout bypass');", "terminal-stream-unbound.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    const lease = try streams.bind(engine, probe.bridge());
    defer _ = streams.unbind(engine, lease);
    result = try engine.eval("var writesDone=[];if(process.stdout.write(Buffer.from([0,255,27]),()=>writesDone.push('callback'))!==true)throw Error('write return');process.stderr.write('error');writesDone.push('sync');", "terminal-stream-output.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    _ = try engine.drainReadyJobs();
    result = try engine.eval("if(JSON.stringify(writesDone)!=='[\"sync\",\"callback\"]')throw Error(JSON.stringify(writesDone));", "terminal-stream-callback.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    try std.testing.expectEqualSlices(u8, "\x00\xff\x1bEerror", probe.bytes.items);
}
fn nodeFunctionAllocatorCallback(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return c.JS_DupValue(engine.context, values[0]);
}
fn nodeFunctionAllocatorCase(gpa: std.mem.Allocator) !void {
    const engine = try js.Engine.init(gpa, .{});
    defer engine.deinit();
    const callback = try @import("native_node_function.zig").create(engine, "HostOrdinary", 0, nodeFunctionAllocatorCallback, &.{c.JS_NewInt32(engine.context, 7)});
    defer engine.freeValue(callback);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "HostOrdinary", c.JS_DupValue(engine.context, callback));
    const result = try engine.eval("if(HostOrdinary()!==7||Object.getPrototypeOf(new HostOrdinary)!==HostOrdinary.prototype||HostOrdinary.prototype.constructor!==HostOrdinary)throw Error('native ordinary function constructor');", "node-function-allocator-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "Source6fb public TUI slice native ordinary Node function allocation cleanup and genuine construction" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, nodeFunctionAllocatorCase, .{});
    try nodeFunctionAllocatorCase(std.testing.allocator);
}
const EventOwnerProbe = struct {
    engine: *js.Engine,
    id: i32,
    fn activate(raw: ?*anyopaque) void {
        const self: *EventOwnerProbe = @ptrCast(@alignCast(raw.?));
        self.publish(self.id);
    }
    fn deactivate(raw: ?*anyopaque) void {
        const self: *EventOwnerProbe = @ptrCast(@alignCast(raw.?));
        self.publish(0);
    }
    fn publish(self: *EventOwnerProbe, id: i32) void {
        const root = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(root);
        _ = c.JS_SetPropertyStr(self.engine.context, root, "eventOwnerProbe", c.JS_NewInt32(self.engine.context, id));
    }
    fn run(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = js.Engine.fromContext(context.?);
        if (argc < 2) return c.JS_ThrowTypeError(context, "Expected test owner and callback");
        var id: i32 = 0;
        if (c.JS_ToInt32(context, &id, argv[0]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
        const guard = @import("native_async_scope.zig").enter(engine, data[if (id == 1) @as(usize, 0) else 1]);
        defer guard.restore();
        return c.JS_Call(context, argv[1], c.pi_js_undefined(), 0, null);
    }
    fn getStore(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
        const root = c.JS_GetGlobalObject(context);
        defer c.JS_FreeValue(context, root);
        return c.JS_GetPropertyStr(context, root, "eventOwnerProbe");
    }
};
test "Source6fb public TUI slice Node24 tick batches retain separate private original owner scopes" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"node-owner-scope"});
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const exports = engine.native_module_values.get("node:events").?;
    try js.define(engine, root, "OwnerEmitter", try js.get(engine, exports, "EventEmitter"));
    const bytes = @embedFile("fixtures/node-events-owner-scope-24.json");
    try js.define(engine, root, "eventOwnerSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-owner-scope-24.json")));
    const setup = try engine.eval("var ownerSeen=[];function queueOwner(id){process.nextTick(()=>{ownerSeen.push(['tick',eventOwnerProbe]);if(id===1)process.nextTick(()=>ownerSeen.push(['nested',eventOwnerProbe]));});const e=new OwnerEmitter({captureRejections:true});e[OwnerEmitter.captureRejectionSymbol]=()=>ownerSeen.push(['reject',eventOwnerProbe]);e.on('x',()=>Promise.reject('reason'));e.emit('x');}", "node-owner-setup.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(setup);
    const scope = @import("native_async_scope.zig");
    var first: EventOwnerProbe = .{ .engine = engine, .id = 1 };
    var second: EventOwnerProbe = .{ .engine = engine, .id = 2 };
    const first_token = try scope.create(engine, &first, EventOwnerProbe.activate, EventOwnerProbe.deactivate);
    defer engine.freeValue(first_token);
    const second_token = try scope.create(engine, &second, EventOwnerProbe.activate, EventOwnerProbe.deactivate);
    defer engine.freeValue(second_token);
    {
        const guard = scope.enter(engine, first_token);
        defer guard.restore();
        const queued = try engine.eval("queueOwner(1)", "node-owner-first.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(queued);
    }
    {
        const guard = scope.enter(engine, second_token);
        defer guard.restore();
        const queued = try engine.eval("queueOwner(2)", "node-owner-second.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(queued);
    }
    try std.testing.expect(try engine.drainReadyJobs());
    const result = engine.eval("if(eventOwnerProbe!==0||JSON.stringify(ownerSeen)!==JSON.stringify(eventOwnerSource.seen))throw Error(JSON.stringify({owner:eventOwnerProbe,actual:ownerSeen,expected:eventOwnerSource.seen}));", "node-owner-result.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| {
        if (engine.last_error) |message| std.debug.print("Native tick owner scopes: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice StdinBuffer fragments UTF16 paste timeouts emitter and ordinary fields" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/stdin-buffer-original-6fb.json");
    try js.define(engine, root, "stdinBufferSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "stdin-buffer-original-6fb.json")));
    const result = engine.evalModule("import{StdinBuffer}from'pi-tui';import{EventEmitter}from'node:events';\n" ++ @embedFile("fixtures/stdin-buffer-original-6fb.input.txt") ++
        \\for(let i=0;i<stdinBufferSource.cases.length;i++){const actual=stdinBufferResults[i],expected=stdinBufferSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "stdin-buffer-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native StdinBuffer: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice Node24 EventEmitter synchronous listener core and ordinary field authority" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("node_events.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-events-original-24.json");
    try js.define(engine, root, "nodeEventsSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-original-24.json")));
    const result = engine.evalModule("import{EventEmitter}from'node:events';\n" ++ @embedFile("fixtures/node-events-original-24.input.txt") ++
        \\for(let i=0;i<nodeEventsSource.cases.length;i++){const actual=nodeEventResults[i],expected=nodeEventsSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "node-events-sync-core-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native EventEmitter core: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice Node24 EventEmitter static queries capture defaults and validation" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-events-statics-24.json");
    try js.define(engine, root, "eventStaticSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-statics-24.json")));
    const result = engine.evalModule("import{EventEmitter}from'node:events';\n" ++ @embedFile("fixtures/node-events-statics-24.input.txt") ++
        \\for(let i=0;i<eventStaticSource.cases.length;i++){const actual=eventStaticResults[i],expected=eventStaticSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "node-events-static-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native EventEmitter statics: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}

test "Source6fb public TUI slice Node24 EventEmitter rejection capture thenables and checkpoint ordering" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-events-rejections-24.json");
    try js.define(engine, root, "eventRejectionSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-rejections-24.json")));
    const result = engine.evalModule("import{EventEmitter}from'node:events';\n" ++ @embedFile("fixtures/node-events-rejections-24.input.txt") ++
        \\for(let i=0;i<eventRejectionSource.cases.length;i++){const actual=eventRejectionResults[i],expected=eventRejectionSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "node-events-rejection-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native EventEmitter rejections: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}

test "Source6fb public TUI slice Node24 EventEmitter unhandled reasons and dynamic warning diagnostics" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"node-events-diagnostics"});
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-events-diagnostics-24.json");
    try js.define(engine, root, "eventDiagnosticSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-diagnostics-24.json")));
    const result = engine.evalModule("import{EventEmitter}from'node:events';\n" ++ @embedFile("fixtures/node-events-diagnostics-24.input.txt") ++
        \\for(let i=0;i<eventDiagnosticSource.cases.length;i++){const actual=eventDiagnosticResults[i],expected=eventDiagnosticSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "node-events-diagnostics-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native EventEmitter diagnostics: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}

test "Source6fb public TUI slice Node24 process warning producer overloads identity and queued order" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"node-process-events"});
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-process-events-24.json");
    try js.define(engine, root, "processEventSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-process-events-24.json")));
    const result = engine.evalModule("process.removeAllListeners('warning');\n" ++ @embedFile("fixtures/node-process-events-24.input.txt") ++
        \\for(let i=0;i<processEventSource.cases.length;i++){const actual=processEventResults[i],expected=processEventSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "node-process-events-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native process events: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}

test "Source6fb public TUI slice Node24 nextTick timer phase and promise rejection phase" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"node-events-timer-phase"});
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-events-timer-phase-24.json");
    try js.define(engine, root, "eventTimerPhaseSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-timer-phase-24.json")));
    const result = engine.evalModule("import{EventEmitter}from'node:events';\n" ++ @embedFile("fixtures/node-events-timer-phase-24.input.txt") ++
        \\for(let i=0;i<eventTimerPhaseSource.cases.length;i++){const actual=eventTimerPhaseResults[i],expected=eventTimerPhaseSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "node-events-timer-phase-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native nextTick timer phase: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}

test "Source6fb public TUI slice Node24 asynchronous once signal error identity and virtual subscriptions" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("abort_signal.zig").install(engine);
    try @import("node_events.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-events-once-24.json");
    try js.define(engine, root, "eventOnceSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-once-24.json")));
    const result = engine.evalModule("import{EventEmitter}from'node:events';\n" ++ @embedFile("fixtures/node-events-once-24.input.txt") ++
        \\for(let i=0;i<eventOnceSource.cases.length;i++){const actual=eventOnceResults[i],expected=eventOnceSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "node-events-once-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native asynchronous once: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}

test "Source6fb public TUI slice Node24 abort listener queued callback disposal and genuine signal" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("abort_signal.zig").install(engine);
    try @import("node_events.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-events-abort-listener-24.json");
    try js.define(engine, root, "eventAbortSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-abort-listener-24.json")));
    const result = engine.evalModule("import{EventEmitter}from'node:events';\n" ++ @embedFile("fixtures/node-events-abort-listener-24.input.txt") ++
        \\for(let i=0;i<eventAbortSource.cases.length;i++){const actual=eventAbortResults[i],expected=eventAbortSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "node-events-abort-listener-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native abort listener: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}

test "Source6fb public TUI slice Node24 async on intrinsic iterator queues error cleanup and watermarks" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("abort_signal.zig").install(engine);
    try @import("node_events.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-events-on-24.json");
    try js.define(engine, root, "eventOnSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-on-24.json")));
    const result = engine.evalModule("import{EventEmitter}from'node:events';\n" ++ @embedFile("fixtures/node-events-on-24.input.txt") ++
        \\for(let i=0;i<eventOnSource.cases.length;i++){const actual=eventOnResults[i],expected=eventOnSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "node-events-on-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native async on: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice Node24 EventEmitterAsyncResource hierarchy IDs constructor owner and virtual scope" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("node_events.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-events-resource-24.json");
    try js.define(engine, root, "eventResourceSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-resource-24.json")));
    try js.define(engine, root, "executionAsyncId", try @import("node_events_resource.zig").executionIdFunction(engine));
    const scope_module = @import("native_async_scope.zig");
    var first: EventOwnerProbe = .{ .engine = engine, .id = 1 };
    var second: EventOwnerProbe = .{ .engine = engine, .id = 2 };
    const first_token = try scope_module.create(engine, &first, EventOwnerProbe.activate, EventOwnerProbe.deactivate);
    defer engine.freeValue(first_token);
    const second_token = try scope_module.create(engine, &second, EventOwnerProbe.activate, EventOwnerProbe.deactivate);
    defer engine.freeValue(second_token);
    var data = [_]c.JSValue{ first_token, second_token };
    const owner = try js.object(engine);
    defer engine.freeValue(owner);
    try js.define(engine, owner, "run", try engine.checked(c.JS_NewCFunctionData2(engine.context, EventOwnerProbe.run, "run", 2, 0, 2, &data)));
    try js.define(engine, owner, "getStore", try engine.checked(c.JS_NewCFunction2(engine.context, EventOwnerProbe.getStore, "getStore", 0, c.JS_CFUNC_generic, 0)));
    try js.define(engine, root, "owner", c.JS_DupValue(engine.context, owner));
    const result = engine.evalModule("import{EventEmitter}from'node:events';\n" ++ @embedFile("fixtures/node-events-resource-24.input.txt") ++
        \\for(let i=0;i<eventResourceSource.cases.length;i++){const actual=eventResourceResults[i],expected=eventResourceSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "node-events-resource-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native event resource: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice Node24 EventEmitter exact metadata namespace and ordinary constructors" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("node_events.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-events-metadata-24.json");
    try js.define(engine, root, "eventMetadataSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-metadata-24.json")));
    const result = engine.evalModule("import*as eventsNamespace from'node:events';const{EventEmitter}=eventsNamespace;\n" ++ @embedFile("fixtures/node-events-metadata-24.input.txt") ++
        \\for(let i=0;i<eventMetadataSource.cases.length;i++){const actual=eventMetadataResults[i],expected=eventMetadataSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "node-events-metadata-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native event metadata: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI final Node24 EventEmitter static surface remains explicit" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("node_events.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/node-events-original-24.json");
    try js.define(engine, root, "nodeEventsSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "node-events-original-24.json")));
    const result = engine.evalModule(
        \\import{EventEmitter}from'node:events';const expected=nodeEventsSource.cases.find(x=>x.name==='shape').value.ctor.keys,actual=Object.getOwnPropertyNames(EventEmitter);if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({nodeEventStaticMissing:expected.filter(x=>!actual.includes(x)),actual,expected}));
    , "node-events-full-static-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native EventEmitter full static audit: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice ScrollView field authority follow chaining scrollbar lifecycle and layout hook" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/scroll-view-original-6fb.json");
    try js.define(engine, root, "scrollViewSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "scroll-view-original-6fb.json")));
    const result = engine.evalModule("import{ScrollView,Container}from'pi-tui';\n" ++ @embedFile("fixtures/scroll-view-original-6fb.input.txt") ++
        \\for(let i=0;i<scrollViewSource.cases.length;i++){const actual=scrollViewResults[i],expected=scrollViewSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-scroll-view-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native ScrollView: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice Stack HStack VStack genuine hierarchy ordinary entries and layout behavior" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/stack-components-original-6fb.json");
    try js.define(engine, root, "stackSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "stack-components-original-6fb.json")));
    const result = engine.evalModule("import{HStack,VStack,Container}from'pi-tui';\n" ++ @embedFile("fixtures/stack-components-original-6fb.input.txt") ++
        \\for(let i=0;i<stackSource.cases.length;i++){const actual=stackResults[i],expected=stackSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-stack-components-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Stack components: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice column clipping style links markers and exact line composition" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/tui-columns-original-6fb.json");
    try js.define(engine, root, "tuiColumnSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "tui-columns-original-6fb.json")));
    const result = engine.evalModule("import{stripTerminalSequences,getOsc8LinkAtColumn,sliceByColumn,compositeTuiLine}from'pi-tui';\n" ++ @embedFile("fixtures/tui-columns-original-6fb.input.txt") ++
        \\for(let i=0;i<tuiColumnSource.cases.length;i++){const actual=tuiColumnResults[i],expected=tuiColumnSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-columns-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TUI columns: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice helper regex literals ignore replaced global constructor" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("node_buffer.zig").install(engine);
    const replace = try engine.eval("globalThis.RegExp=function(){throw Error('global RegExp constructor used for literal')};", "tui-literal-global-input.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(replace);
    const exports = try js.object(engine);
    defer engine.freeValue(exports);
    try @import("native_tui_public_helpers.zig").install(engine, exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "literalHelperApi", c.JS_DupValue(engine.context, exports));
    const bytes = @embedFile("fixtures/tui-helper-literal-regexp-original-6fb.json");
    try js.define(engine, root, "literalHelperSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "tui-helper-literal-regexp-original-6fb.json")));
    const result = try engine.eval("const value={scheme:literalHelperApi.parseTerminalColorSchemeReport('\\x1b[?997;2n'),status:literalHelperApi.formatProgramStatus({state:'blocked',app:'pi',kind:'question',message:' a\\x00b '})};if(JSON.stringify(value)!==JSON.stringify(literalHelperSource.value))throw Error(JSON.stringify({value,expected:literalHelperSource.value}));", "tui-literal-global-result.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
}
test "Source6fb public TUI slice Image protocol rendering identity transcoder retry and bounded cache" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"tui-image-component"});
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/image-component-original-6fb.json");
    try js.define(engine, root, "imageComponentSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "image-component-original-6fb.json")));
    const result = engine.evalModule("import{Image,setImageTranscoder,setCapabilities,setCellDimensions}from'pi-tui';\n" ++ @embedFile("fixtures/image-component-original-6fb.input.txt") ++
        \\for(let i=0;i<imageComponentSource.cases.length;i++){const actual=imageComponentResults[i],expected=imageComponentSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-image-component-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Image component: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice guards color scheme status UTF8 and public LaTeX entry point" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/tui-public-helpers-original-6fb.json");
    try js.define(engine, root, "tuiHelperSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "tui-public-helpers-original-6fb.json")));
    const result = engine.evalModule("import{isFocusable,isViewportTUI,parseTerminalColorSchemeReport,formatProgramStatus,renderLatex,isAppleTerminalSession}from'pi-tui';\n" ++ @embedFile("fixtures/tui-public-helpers-original-6fb.input.txt") ++
        \\for(let i=0;i<tuiHelperSource.cases.length;i++){const actual=tuiHelperResults[i],expected=tuiHelperSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-public-helpers-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TUI helpers: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice Loader actual native timer owner callback stops and completes" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/loader-real-timer-original-6fb.json");
    try js.define(engine, root, "loaderRealSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "loader-real-timer-original-6fb.json")));
    const result = engine.evalModule("import{Loader}from'pi-tui';\n" ++ @embedFile("fixtures/loader-real-timer-original-6fb.input.txt") ++
        \\if(JSON.stringify(loaderRealTimerResult)!==JSON.stringify(loaderRealSource.result))throw Error(JSON.stringify({actual:loaderRealTimerResult,expected:loaderRealSource.result}));
    , "tui-loader-real-timer-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Loader timer: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
    try std.testing.expect(!(try @import("timers.zig").pumpReady(engine)));
}
test "Source6fb public TUI slice Loader cancellation timers ordinary fields and inherited methods" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/loader-original-6fb.json");
    try js.define(engine, root, "loaderSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "loader-original-6fb.json")));
    const result = engine.evalModule("import{Loader,CancellableLoader,Text,getKeybindings,setKeybindings,KeybindingsManager,TUI_KEYBINDINGS}from'pi-tui';\n" ++ @embedFile("fixtures/loader-original-6fb.input.txt") ++
        \\for(let i=0;i<loaderSource.cases.length;i++){const actual=loaderResults[i],expected=loaderSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-loader-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Loader: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice TruncatedText fields first line clipping padding and receivers" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/truncated-text-original-6fb.json");
    try js.define(engine, root, "truncatedTextSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "truncated-text-original-6fb.json")));
    const result = engine.evalModule("import{TruncatedText}from'pi-tui';\n" ++ @embedFile("fixtures/truncated-text-original-6fb.input.txt") ++
        \\for(let i=0;i<truncatedTextSource.cases.length;i++){const actual=truncatedTextResults[i],expected=truncatedTextSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-truncated-text-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TruncatedText: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI final namespace and prototype shape" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/tui-public-surface-original-6fb.json");
    try js.define(engine, root, "tuiSurfaceSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "tui-public-surface-original-6fb.json")));
    const result = engine.evalModule(
        \\import*as tui from'pi-tui';const missing=[],differences=[],extra=Object.keys(tui).filter(n=>!tuiSurfaceSource.exports.some(x=>x.name===n));for(const item of tuiSurfaceSource.exports){const value=tui[item.name];if(value===undefined){missing.push(item.name);continue;}if(typeof value!==item.type)differences.push({name:item.name,type:typeof value,expected:item.type});if(item.type==='function'&&value.length!==item.length)differences.push({name:item.name,length:value.length,expected:item.length});if(item.prototype){const actual=value.prototype?Object.getOwnPropertyNames(value.prototype):null;const expected=item.prototype.map(x=>x.name);if(JSON.stringify(actual)!==JSON.stringify(expected))differences.push({name:item.name,prototype:actual,expected});}}if(missing.length||differences.length||extra.length)throw Error(JSON.stringify({missing,differences,extra}));
    , "tui-public-shape-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("TUI surface audit: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
