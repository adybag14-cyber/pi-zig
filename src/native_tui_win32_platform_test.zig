//! Focused installed controls for the consumed Win32 TUI helper.
//! Clipboard observations are read-only; neither content nor images are logged.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const worker = @import("extensions/native_worker.zig");
const resources = @import("extensions/native_tui_platform_resources.zig");
const queue = @import("extensions/native_tui_win32_clipboard_promise.zig");
const values = @import("extensions/native_tui_win32_value.zig");
const streams = @import("extensions/native_process_streams.zig");
const gpa = std.testing.allocator;

const Fixture = struct {
    engine: *js.Engine,
    loader: worker.Loader,
    resource_root: []u8,
    fn init(self: *Fixture) !void {
        if (builtin.os.tag != .windows or (builtin.cpu.arch != .x86_64 and builtin.cpu.arch != .aarch64))
            return error.SkipZigTest;
        const engine = try js.Engine.init(gpa, .{ .host_await_timeout_ms = 110000 });
        errdefer engine.deinit();
        const executable = try std.process.executablePathAlloc(std.testing.io, gpa);
        defer gpa.free(executable);
        const directory = std.fs.path.dirname(executable) orelse return error.MissingTestExecutableDirectory;
        const root = try std.fs.path.join(gpa, &.{ directory, resources.relative_root });
        errdefer gpa.free(root);
        self.* = .{ .engine = engine, .loader = .{ .io = std.testing.io, .engine = engine }, .resource_root = root };
        self.loader.bind();
        var environment: std.process.Environ.Map = .init(gpa);
        defer environment.deinit();
        try @import("extensions/timers.zig").install(engine, std.testing.io);
        try @import("extensions/node_path.zig").install(engine, std.testing.io);
        try @import("extensions/node_url.zig").install(engine);
        try @import("extensions/node_fs.zig").install(engine, std.testing.io);
        try @import("extensions/commonjs.zig").install(engine);
        try @import("extensions/node_buffer.zig").install(engine);
        try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-tui-platform-test"});
        try resources.bindRoot(engine, std.testing.io, root);
        try @import("extensions/native_tui.zig").install(engine);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try js.define(engine, global, "nativeTuiTestResourceRoot",
            try engine.checked(c.JS_NewStringLen(engine.context, root.ptr, root.len)));
    }
    fn deinit(self: *Fixture) void {
        self.engine.deinit();
        gpa.free(self.resource_root);
    }
    fn run(self: *Fixture, source: []const u8, name: [:0]const u8) !void {
        const pending = try self.engine.evalModule(source, name);
        defer self.engine.freeValue(pending);
        const completed = try self.engine.awaitValue(pending);
        self.engine.freeValue(completed);
    }
};

test "native TUI Win32 real installed helper exports and primitive validation" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.run(
        \\import {getNativeClipboard} from "pi-tui";
        \\const h=getNativeClipboard();
        \\if(!h || getNativeClipboard()!==h) throw Error("missing or unstable real helper");
        \\for(const name of ["enableVirtualTerminalInput","isModifierPressed","getText","setText","getImage"]){
        \\  const d=Object.getOwnPropertyDescriptor(h,name);
        \\  if(!d || typeof d.value!=="function" || !d.writable || !d.enumerable || !d.configurable || d.value.name!==name || d.value.length!==0) throw Error("native helper function metadata");
        \\}
        \\for(const bad of [undefined,null,0,true,{},new String("x")]){
        \\  let failed=false;
        \\  try { h.setText(bad); } catch(error) { failed=error instanceof Error && error.message==="setText requires a string"; }
        \\  if(!failed) throw Error("primitive setText validation");
        \\}
        \\if(h.isModifierPressed()!==false || h.isModifierPressed({toString(){throw Error("coercion ran")}})!==false) throw Error("modifier primitive validation");
    , "tui-installed-helper.mjs");
    try std.testing.expect(!queue.hasPending(f.engine));
}

test "native TUI Win32 real options getters and cache precede host admission" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.run(@embedFile("extensions/fixtures/native-tui-candidate-options-cache.input.txt"), "tui-candidate-options-cache.mjs");
    try std.testing.expect(!queue.hasPending(f.engine));
}

test "native TUI Win32 export assignment observes inherited setter and caches miss" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.run(
        \\import {getNativeClipboard} from "pi-tui";
        \\let calls=0,receiver,assigned;
        \\Object.defineProperty(Object.prototype,"getText",{configurable:true,set(value){calls++;receiver=this;assigned=value;}});
        \\try {
        \\  if(getNativeClipboard()!==undefined) throw Error("ordinary setter must affect helper shape");
        \\  if(calls!==1 || typeof assigned!=="function" || Object.hasOwn(receiver,"getText") || typeof receiver.getImage!=="function") throw Error("native ordinary assignment");
        \\} finally { delete Object.prototype.getText; }
        \\if(getNativeClipboard()!==undefined || calls!==1) throw Error("undefined helper miss was not cached");
    , "tui-native-export-setter.mjs");
}

const BridgeProbe = struct {
    calls: usize = 0,
    enabled: usize = 0,
    fn guard(_: ?*anyopaque) !void {}
    fn control(_: ?*anyopaque, _: streams.Control) !void {}
    fn write(_: ?*anyopaque, _: streams.Output, _: []const u8) !void {}
    fn modifier(raw: ?*anyopaque, name: []const u8) !bool {
        const self: *BridgeProbe = @ptrCast(@alignCast(raw.?));
        const expected = [_][]const u8{ "shift", "control", "option", "alt", "command", "super", "win", "shift" };
        if (self.calls >= expected.len or !std.mem.eql(u8, name, expected[self.calls])) return error.UnexpectedModifierRoute;
        self.calls += 1;
        return std.mem.eql(u8, name, "shift");
    }
    fn enable(raw: ?*anyopaque) !bool {
        const self: *BridgeProbe = @ptrCast(@alignCast(raw.?));
        self.enabled += 1;
        return true;
    }
};
test "native TUI Win32 modifier helper uses actual guarded console bridge" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    var probe: BridgeProbe = .{};
    const lease = try streams.bind(f.engine, .{ .context = &probe, .guard_fn = BridgeProbe.guard, .control_fn = BridgeProbe.control, .write_fn = BridgeProbe.write,
        .is_modifier_pressed_fn = BridgeProbe.modifier, .enable_vt_input_fn = BridgeProbe.enable });
    defer _ = streams.unbind(f.engine, lease);
    try f.run(
        \\import {getNativeClipboard} from "pi-tui";
        \\const h=getNativeClipboard();
        \\for(const key of ["shift","control","option","alt","command","super","win","shift\0ignored"]){
        \\  const expected=key==="shift" || key.startsWith("shift\0");
        \\  if(h.isModifierPressed(key)!==expected) throw Error("modifier bridge result");
        \\}
        \\for(const key of ["SHIFT","unknown","12345678901234é","",{},17]){
        \\  if(h.isModifierPressed(key)!==false) throw Error("invalid modifier must not query parent");
        \\}
        \\if(h.enableVirtualTerminalInput()!==true) throw Error("VT input bridge result");
    , "tui-guarded-modifier.mjs");
    try std.testing.expectEqual(@as(usize, 8), probe.calls);
    try std.testing.expectEqual(@as(usize, 1), probe.enabled);
}

test "native TUI Win32 private asynchronous clipboard survives public timer clearing and GC" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const namespace = try f.engine.evalModule(
        \\import {getNativeClipboard} from "pi-tui";
        \\const h=getNativeClipboard();
        \\function text(value){if(value!==null && value!==undefined && typeof value!=="string")throw Error("clipboard text type");}
        \\function image(value){if(value!==null && value!==undefined && !Buffer.isBuffer(value))throw Error("clipboard image type");}
        \\function failure(error){if(!(error instanceof Error))throw Error("clipboard error type");}
        \\const jobs=[h.getImage().then(image,failure),h.getText().then(text,failure),h.getText().then(text,failure),h.getText().then(text,failure),h.getText().then(text,failure)];
        \\for(let id=0;id<128;id++){clearTimeout(id);clearInterval(id);}
        \\export const completion=Promise.all(jobs);
    , "tui-private-clipboard-queue.mjs");
    defer f.engine.freeValue(namespace);
    const pending = try f.engine.checked(c.JS_GetPropertyStr(f.engine.context, namespace, "completion"));
    defer f.engine.freeValue(pending);
    try std.testing.expect(queue.hasPending(f.engine));
    c.JS_RunGC(f.engine.runtime);
    const completed = try f.engine.awaitValue(pending);
    f.engine.freeValue(completed);
    try std.testing.expect(!queue.hasPending(f.engine));
    try std.testing.expect(!queue.hasFailed(f.engine));
}

test "native TUI Win32 value construction preserves Buffer and actual VM OOM provenance" {
    const engine = try js.Engine.init(gpa, .{});
    defer engine.deinit();
    try @import("extensions/node_buffer.zig").install(engine);
    const text = try values.fromUtf16(engine, &.{ 'a', 0, 0x03bb });
    defer engine.freeValue(text);
    const bytes = try values.fromBytes(engine, &.{ 0, 1, 127, 255 });
    defer engine.freeValue(bytes);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "tuiCopiedText", c.JS_DupValue(engine.context, text));
    try js.define(engine, global, "tuiCopiedBytes", c.JS_DupValue(engine.context, bytes));
    const checked = try engine.eval(
        "if(tuiCopiedText.length!==3||tuiCopiedText.charCodeAt(1)!==0||tuiCopiedText.charCodeAt(2)!==955||!Buffer.isBuffer(tuiCopiedBytes)||tuiCopiedBytes.length!==4||tuiCopiedBytes[3]!==255)throw Error('clipboard copied value');",
        "tui-value-copy.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(checked);
    const saved_limit = engine.options.memory_limit;
    engine.options.memory_limit = 1;
    try std.testing.expectError(error.BufferRange, values.fromBytes(engine, &.{ 1, 2 }));
    engine.options.memory_limit = saved_limit;
    const generation = engine.native_allocation_generation;
    const occurrence = c.JS_PiOutOfMemoryOccurrence(engine.runtime);
    c.JS_SetMemoryLimit(engine.runtime, 1);
    defer c.JS_SetMemoryLimit(engine.runtime, saved_limit);
    if (values.fromUtf16(engine, &.{ 0x100, 0x101, 0x102, 0x103 })) |unexpected| {
        engine.freeValue(unexpected);
        return error.RequiredActualVmAllocationFailure;
    } else |err| {
        try std.testing.expect(err == error.OutOfMemory or err == error.JavaScriptException);
    }
    try std.testing.expect(c.JS_PiOutOfMemoryOccurrence(engine.runtime) != occurrence);
    try std.testing.expect(engine.native_allocation_generation != generation);
    try std.testing.expect(engine.captured_exception != null);
    // The actual producer's policy is independent of its unallocatable Error.
    // End-to-end callback regressions below check the live fatal channel.
    try std.testing.expect(c.JS_IsNull(engine.captured_exception.?));
    try std.testing.expect(!c.JS_IsUncatchableError(engine.captured_exception.?));
    try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(engine.captured_exception.?));
    try std.testing.expect(engine.native_fatal_invocation == null);
}

test "native TUI Win32 engine teardown joins outstanding private work and releases memory owner" {
    const owners = c.pi_js_native_memory_owners();
    {
        var f: Fixture = undefined;
        try f.init();
        defer f.deinit();
        const pending = try f.engine.evalModule(
            \\import {getNativeClipboard} from "pi-tui";
            \\const h=getNativeClipboard();
            \\for(let i=0;i<5;i++)h.getText().then(()=>{},()=>{});
        , "tui-private-clipboard-retire.mjs");
        f.engine.freeValue(pending);
        try std.testing.expect(queue.hasPending(f.engine));
        c.JS_RunGC(f.engine.runtime);
    }
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}

const PrimitiveFatalFixture = struct {
    var calls: usize = 0;
    var actual_vm_failures: usize = 0;

    fn callback(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
        calls += 1;
        const before = c.JS_PiOutOfMemoryOccurrence(engine.runtime);
        c.JS_SetMemoryLimit(engine.runtime, 1);
        // Restore before the real C callback returns: a broken ordinary catch
        // has enough heap to run, so allocation pressure cannot hide it.
        const result = values.fromUtf16(engine, &.{ 0x100, 0x101, 0x102, 0x103 });
        c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
        if (c.JS_PiOutOfMemoryOccurrence(engine.runtime) != before) actual_vm_failures += 1;
        return result;
    }
    fn install(engine: *js.Engine) !void {
        calls = 0;
        actual_vm_failures = 0;
        const function = try @import("extensions/native_node_module_callable.zig").create(
            engine, "nativePrimitiveFatal", 0, false, callback, &.{});
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try js.define(engine, global, "nativePrimitiveFatal", function);
    }
    fn runToPending(engine: *js.Engine, source: []const u8) !void {
        const text = try gpa.dupeZ(u8, source);
        defer gpa.free(text);
        const result = c.JS_Eval(engine.context, text.ptr, source.len,
            "native-tui-primitive-fatal.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(result);
        var turns: usize = 0;
        while (!c.JS_HasException(engine.context) and turns < 16) : (turns += 1) {
            var context: ?*c.JSContext = null;
            const status = c.JS_ExecutePendingJob(engine.runtime, &context);
            if (status < 0 or status == 0) break;
        }
        try std.testing.expect(c.JS_HasException(engine.context));
        try std.testing.expect(c.JS_PiIsPendingUncatchable(engine.context));
        try std.testing.expectEqual(@as(usize, 1), calls);
        try std.testing.expectEqual(@as(usize, 1), actual_vm_failures);
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
    fn takePrimitive(engine: *js.Engine) !c.JSValue {
        var generic_fatal: bool = false;
        const reason = c.JS_PiGetExceptionWithFatal(engine.context, &generic_fatal);
        errdefer engine.freeValue(reason);
        try std.testing.expect(generic_fatal);
        try std.testing.expect(c.JS_IsNull(reason));
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
        try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(reason));
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expect(!c.JS_PiIsPendingUncatchable(engine.context));
        return reason;
    }
    fn counter(engine: *js.Engine, expected: i32) !void {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const value = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "primitiveReached"));
        defer engine.freeValue(value);
        var count: i32 = -1;
        if (c.JS_ToInt32(engine.context, &count, value) < 0) return error.JavaScriptException;
        try std.testing.expectEqual(expected, count);
    }
};

test "native TUI Win32 exhausted heap fatal survives real callback pop and bypasses guest catch" {
    const engine = try js.Engine.init(gpa, .{});
    defer engine.deinit();
    try PrimitiveFatalFixture.install(engine);
    try PrimitiveFatalFixture.runToPending(engine,
        "globalThis.primitiveReached=0;try{nativePrimitiveFatal();primitiveReached+=1}catch(e){primitiveReached+=10}finally{primitiveReached+=100}");
    const reason = try PrimitiveFatalFixture.takePrimitive(engine);
    defer engine.freeValue(reason);
    try PrimitiveFatalFixture.counter(engine, 0);
    // An ordinary primitive null is still catchable after the actual event
    // was taken and all caller-stable invocations have popped.
    const control = try engine.eval(
        "try{throw null}catch(e){if(e!==null)throw Error('ordinary null');primitiveReached++}",
        "tui-ordinary-null.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(control);
    try PrimitiveFatalFixture.counter(engine, 1);
}

test "native TUI Win32 exhausted heap fatal escapes Promise and async continuation conversion" {
    const cases = [_][]const u8{
        "globalThis.primitiveReached=0;new Promise(()=>nativePrimitiveFatal()).catch(()=>primitiveReached++)",
        "globalThis.primitiveReached=0;Promise.resolve().then(()=>nativePrimitiveFatal()).catch(()=>primitiveReached++)",
        "globalThis.primitiveReached=0;Promise.resolve({then(){nativePrimitiveFatal()}}).catch(()=>primitiveReached++)",
        "globalThis.primitiveReached=0;(async()=>{try{nativePrimitiveFatal()}catch(e){primitiveReached++}finally{primitiveReached+=10}})().catch(()=>primitiveReached+=100)",
        "globalThis.primitiveReached=0;(async()=>{await 0;try{nativePrimitiveFatal()}catch(e){primitiveReached++}finally{primitiveReached+=10}})().catch(()=>primitiveReached+=100)",
        "globalThis.primitiveReached=0;Promise.try(()=>nativePrimitiveFatal()).catch(()=>primitiveReached++)",
    };
    for (cases) |source| {
        const engine = try js.Engine.init(gpa, .{});
        defer engine.deinit();
        try PrimitiveFatalFixture.install(engine);
        try PrimitiveFatalFixture.runToPending(engine, source);
        const reason = try PrimitiveFatalFixture.takePrimitive(engine);
        engine.freeValue(reason);
        try PrimitiveFatalFixture.counter(engine, 0);
    }
    const engine = try js.Engine.init(gpa, .{});
    defer engine.deinit();
    const pending = try engine.eval(
        "globalThis.primitiveReached=0;(async()=>{try{await Promise.reject(null)}catch(e){if(e!==null)throw Error('ordinary rejection');primitiveReached++}})()",
        "tui-ordinary-rejection.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(pending);
    const completed = try engine.awaitValue(pending);
    engine.freeValue(completed);
    try PrimitiveFatalFixture.counter(engine, 1);
}

test "native TUI Win32 actual pending classification clears on take and DATA publication" {
    const engine = try js.Engine.init(gpa, .{});
    defer engine.deinit();
    try PrimitiveFatalFixture.install(engine);
    try PrimitiveFatalFixture.runToPending(engine,
        "globalThis.primitiveReached=0;nativePrimitiveFatal()");
    const actual = try PrimitiveFatalFixture.takePrimitive(engine);
    _ = c.JS_PiThrowNativePending(engine.context, actual, true);
    try std.testing.expect(c.JS_PiIsPendingUncatchable(engine.context));
    // Plain take is the explicit conversion to value-only DATA.
    const data = c.JS_GetException(engine.context);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_PiIsPendingUncatchable(engine.context));
    _ = c.JS_PiThrowExceptionData(engine.context, data);
    try std.testing.expect(!c.JS_PiIsPendingUncatchable(engine.context));
    var ordinary: bool = true;
    const ordinary_null = c.JS_PiGetExceptionWithFatal(engine.context, &ordinary);
    engine.freeValue(ordinary_null);
    try std.testing.expect(!ordinary);
    // Public Error flags are mutable DATA properties, not native authority.
    const flagged = try engine.checked(c.JS_NewError(engine.context));
    c.JS_SetUncatchableError(engine.context, flagged);
    _ = c.JS_PiThrowExceptionData(engine.context, flagged);
    try std.testing.expect(!c.JS_PiIsPendingUncatchable(engine.context));
    const flagged_data = c.JS_PiGetExceptionWithFatal(engine.context, &ordinary);
    defer engine.freeValue(flagged_data);
    try std.testing.expect(!ordinary);
    try std.testing.expect(c.JS_IsUncatchableError(flagged_data));
}

test "native TUI Win32 genuine first fatal and private cancellation keep distinct priority" {
    const engine = try js.Engine.init(gpa, .{});
    defer engine.deinit();
    try PrimitiveFatalFixture.install(engine);
    try PrimitiveFatalFixture.runToPending(engine,
        "globalThis.primitiveReached=0;nativePrimitiveFatal()");
    const actual = try PrimitiveFatalFixture.takePrimitive(engine);
    // Service a real private request only while the pending slot is empty.
    c.JS_PiRequestExecutionTermination(engine.runtime);
    try std.testing.expect(c.JS_PiCheckExecutionTermination(engine.context) < 0);
    var private_generic: bool = true;
    const private = c.JS_PiGetExceptionWithFatal(engine.context, &private_generic);
    try std.testing.expect(c.JS_PiIsExecutionTermination(private));
    try std.testing.expect(!private_generic);
    // The earlier genuine primitive fatal wins equal priority. Discarding the
    // later private event retires its lease without inventing another request.
    _ = c.JS_PiThrowNativePending(engine.context, private, private_generic);
    _ = c.JS_PiThrowNativePending(engine.context, actual, true);
    const selected = try PrimitiveFatalFixture.takePrimitive(engine);
    engine.freeValue(selected);
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(engine.runtime));

    c.JS_PiRequestExecutionTermination(engine.runtime);
    try std.testing.expect(c.JS_PiCheckExecutionTermination(engine.context) < 0);
    const cancelled = c.JS_PiGetExceptionWithFatal(engine.context, &private_generic);
    // Cancel acts on an actual published private event. Republish the same
    // in-flight token before cancellation; detached identity alone is not it.
    try std.testing.expect(c.JS_PiCheckExecutionTermination(engine.context) < 0);
    c.JS_PiCancelExecutionTermination(engine.runtime);
    // A detached cancelled token still unwinds, but an actual later ordinary
    // cleanup reason has greater priority. The class remains ordinary.
    _ = c.JS_PiThrowNativePending(engine.context, cancelled, private_generic);
    try std.testing.expect(c.JS_PiIsPendingUncatchable(engine.context));
    const detached = c.JS_PiGetExceptionWithFatal(engine.context, &private_generic);
    _ = c.JS_ThrowTypeError(engine.context, "later actual cleanup");
    _ = c.JS_PiThrowNativePending(engine.context, detached, private_generic);
    var selected_generic: bool = true;
    const cleanup = c.JS_PiGetExceptionWithFatal(engine.context, &selected_generic);
    defer engine.freeValue(cleanup);
    try std.testing.expect(!selected_generic);
    try std.testing.expect(c.JS_IsError(cleanup));
    try std.testing.expect(!c.JS_PiIsExecutionTermination(cleanup));

    // This borrowed Source object makes guest string conversion observable.
    const text_probe = try engine.eval(
        "globalThis.nativeTextHistoryCalls=0;({toString(){nativeTextHistoryCalls++;return 'text-entry'}})",
        "tui-native-text-entry-history.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(text_probe);

    // A raw pending guard observes private history before normalization's
    // cleanup can cancel or replace its selected reason. No checked() capture
    // or inherited producer supplies this new frame's observation.
    const pending_owner = @import("extensions/native_pending_owner.zig");
    var frame = pending_owner.Frame.init(engine);
    try frame.enter();
    c.JS_PiRequestExecutionTermination(engine.runtime);
    try std.testing.expect(c.JS_PiCheckExecutionTermination(engine.context) < 0);
    try std.testing.expectError(error.ExecutionTerminated, pending_owner.checkFatal(engine));
    c.JS_PiCancelExecutionTermination(engine.runtime);
    _ = c.JS_Throw(engine.context, c.pi_js_null());
    // Historical abort prevents guest entry without consuming the actual
    // ordinary pair or converting it into captured diagnostic DATA.
    try std.testing.expectError(error.ExecutionTerminated, engine.checkNativeEntry());
    try std.testing.expectError(error.ExecutionTerminated, engine.checked(c.pi_js_undefined()));
    if (engine.toString(text_probe)) |unexpected| {
        engine.gpa.free(unexpected);
        return error.ExpectedHistoryFailure;
    } else |err| try std.testing.expect(err == error.ExecutionTerminated);
    try std.testing.expect(c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_PiIsPendingUncatchable(engine.context));
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expectError(error.ExecutionTerminated,
        frame.finishValue(@as(anyerror!c.JSValue, error.JavaScriptException)));
    try std.testing.expect(frame.invocation.terminated);
    try std.testing.expect(!engine.nativeTerminationObserved());
    var frame_generic: bool = true;
    const frame_cleanup = c.JS_PiGetExceptionWithFatal(engine.context, &frame_generic);
    defer engine.freeValue(frame_cleanup);
    try std.testing.expect(!frame_generic);
    try std.testing.expect(c.JS_IsNull(frame_cleanup));

    // checked() can itself first observe an actual private event under a live
    // owner. Its typed completion must retain that history and pending tuple.
    var normalize_frame = pending_owner.Frame.init(engine);
    try normalize_frame.enter();
    c.JS_PiRequestExecutionTermination(engine.runtime);
    try std.testing.expect(c.JS_PiCheckExecutionTermination(engine.context) < 0);
    try std.testing.expectError(error.ExecutionTerminated, engine.checked(c.pi_js_undefined()));
    try std.testing.expect(normalize_frame.terminated());
    try std.testing.expect(c.JS_HasException(engine.context));
    try std.testing.expect(engine.captured_exception == null);
    c.JS_PiCancelExecutionTermination(engine.runtime);
    try std.testing.expectError(error.ExecutionTerminated,
        normalize_frame.finishVoid(@as(anyerror!void, error.ExecutionTerminated)));
    try std.testing.expect(!engine.nativeTerminationObserved());
    try std.testing.expect(!c.JS_HasException(engine.context));

    const CheckedRetirement = struct {
        fn finalized(_: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
            const calls: *usize = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
            calls.* += 1;
        }
        fn create(host: *js.Engine, calls: *usize) !c.JSValue {
            var class: c.JSClassID = 0;
            _ = c.JS_NewClassID(host.runtime, &class);
            const definition: c.JSClassDef = .{ .class_name = "Checked history owned result", .finalizer = finalized };
            if (c.JS_NewClass(host.runtime, class, &definition) < 0) return error.OutOfMemory;
            const object = try host.checked(c.JS_NewObjectClass(host.context, class));
            _ = c.JS_SetOpaque(object, calls);
            return object;
        }
    };
    // The raw C exit must preserve observed history after Cancel empties the
    // slot. A later request is only a request until an explicit checkpoint.
    // Exercise the actual return marker both with an empty slot and after an
    // independent later ordinary producer has populated that slot.
    for ([_]bool{ false, true }) |ordinary_after_pop| {
        var finalizer_calls: usize = 0;
        var retire_owned: ?c.JSValue = try CheckedRetirement.create(engine, &finalizer_calls);
        defer { if (retire_owned) |value| engine.freeValue(value); }
        var raw_frame = pending_owner.Frame.init(engine);
        try raw_frame.enter();
        c.JS_PiRequestExecutionTermination(engine.runtime);
        try std.testing.expect(c.JS_PiCheckExecutionTermination(engine.context) < 0);
        try std.testing.expectError(error.ExecutionTerminated, pending_owner.checkFatal(engine));
        c.JS_PiCancelExecutionTermination(engine.runtime);
        try std.testing.expect(raw_frame.terminated());
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(engine.runtime));
        try std.testing.expectError(error.ExecutionTerminated, engine.checkNativeEntry());
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expect(engine.captured_exception == null);
        const raw_generation = c.JS_PiExecutionTerminationGeneration(engine.runtime);
        c.JS_PiRequestExecutionTermination(engine.runtime);
        // An already-aborted entry cannot service this new request. A normal
        // owned result must also retire exactly once while its owner is live.
        try std.testing.expectError(error.ExecutionTerminated, engine.checkNativeEntry());
        if (engine.toString(text_probe)) |unexpected| {
            engine.gpa.free(unexpected);
            return error.ExpectedHistoryFailure;
        } else |err| try std.testing.expect(err == error.ExecutionTerminated);
        const owned_value = retire_owned.?;
        retire_owned = null;
        if (engine.checked(owned_value)) |unexpected| {
            engine.freeValue(unexpected);
            return error.ExpectedHistoryFailure;
        } else |err| try std.testing.expect(err == error.ExecutionTerminated);
        try std.testing.expectEqual(@as(usize, 1), finalizer_calls);
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expect(engine.captured_exception == null);
        try std.testing.expectEqual(raw_generation, c.JS_PiExecutionTerminationGeneration(engine.runtime));

        // A diagnostic fallback must not publish DATA or a new error during
        // actual private history, even when retained diagnostic DATA exists.
        if (ordinary_after_pop) engine.captured_exception = c.JS_DupValue(engine.context, text_probe);
        const forwarded_history = engine.throwCaptured();
        try std.testing.expect(c.JS_IsException(forwarded_history));
        try std.testing.expect(c.JS_PiIsExecutionTermination(forwarded_history));
        try std.testing.expect(!c.JS_HasException(engine.context));
        if (ordinary_after_pop) {
            const diagnostic = engine.captured_exception orelse return error.ExpectedRetainedDiagnostic;
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, diagnostic, text_probe));
            engine.captured_exception = null;
            engine.releaseNativeValue(diagnostic);
        } else try std.testing.expect(engine.captured_exception == null);
        try std.testing.expectEqual(raw_generation, c.JS_PiExecutionTerminationGeneration(engine.runtime));

        const raw_result = raw_frame.finishCallback(c.pi_js_undefined());
        // This is the existing native return sentinel for genuine history,
        // never an empty generic JS_EXCEPTION, guest DATA, or pending event.
        try std.testing.expect(c.JS_IsException(raw_result));
        try std.testing.expect(c.JS_PiIsExecutionTermination(raw_result));
        try std.testing.expect(raw_frame.terminated());
        try std.testing.expect(!raw_frame.invocation.active);
        try std.testing.expect(raw_frame.invocation.first == null);
        try std.testing.expect(!engine.nativeTerminationObserved());
        try std.testing.expect(!c.JS_HasException(engine.context));
        if (ordinary_after_pop) _ = c.JS_Throw(engine.context, c.pi_js_null());
        try std.testing.expectError(error.ExecutionTerminated, engine.checked(raw_result));
        try std.testing.expect(engine.captured_exception == null);
        if (ordinary_after_pop) {
            try std.testing.expect(c.JS_HasException(engine.context));
            try std.testing.expect(!c.JS_PiIsPendingUncatchable(engine.context));
            var later_generic: bool = true;
            const later = c.JS_PiGetExceptionWithFatal(engine.context, &later_generic);
            defer engine.freeValue(later);
            try std.testing.expect(!later_generic);
            try std.testing.expect(c.JS_IsNull(later));
        }
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(engine.runtime));
        try std.testing.expectEqual(raw_generation, c.JS_PiExecutionTerminationGeneration(engine.runtime));
        // Only this explicit checkpoint now services the still-pending request.
        try std.testing.expect(c.JS_PiCheckExecutionTermination(engine.context) < 0);
        try std.testing.expectEqual(raw_generation +% 1, c.JS_PiExecutionTerminationGeneration(engine.runtime));
        try std.testing.expect(c.JS_PiIsExecutionTerminating(engine.runtime));
        c.JS_PiCancelExecutionTermination(engine.runtime);
        try std.testing.expect(!c.JS_HasException(engine.context));
    }

    const no_conversions = try engine.eval("nativeTextHistoryCalls===0",
        "tui-native-text-history-no-conversion.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(no_conversions);
    try std.testing.expect(c.JS_ToBool(engine.context, no_conversions) != 0);
    const converted_text = try engine.toString(text_probe);
    defer engine.gpa.free(converted_text);
    try std.testing.expectEqualStrings("text-entry", converted_text);
    const one_conversion = try engine.eval("nativeTextHistoryCalls===1",
        "tui-native-text-history-normal-conversion.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(one_conversion);
    try std.testing.expect(c.JS_ToBool(engine.context, one_conversion) != 0);

    const CancelledCleanup = struct {
        fn run(host: *js.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            c.JS_PiRequestExecutionTermination(host.runtime);
            _ = c.JS_PiCheckExecutionTermination(host.context);
            var completion = @import("extensions/native_sdk_owned_completion.zig").Completion.initValue(
                host, @as(anyerror!c.JSValue, error.ExecutionTerminated));
            // initValue detached the original event. Publish that same active
            // event before Cancel, then introduce an actual ordinary cleanup.
            _ = c.JS_PiCheckExecutionTermination(host.context);
            c.JS_PiCancelExecutionTermination(host.runtime);
            _ = c.JS_Throw(host.context, c.pi_js_null());
            return completion.finishValue();
        }
    };
    const function = try @import("extensions/native_async_function.zig").create(
        engine, "nativeCancelledCleanup", 0, CancelledCleanup.run, &.{});
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeCancelledCleanup", function);
    const source = "globalThis.primitiveReached=0;nativeCancelledCleanup().catch(()=>primitiveReached++);primitiveReached+=10";
    const aborted = c.JS_Eval(engine.context, source, source.len,
        "tui-native-abort-ordinary-cleanup.js", c.JS_EVAL_TYPE_GLOBAL);
    try std.testing.expect(c.JS_IsException(aborted));
    try std.testing.expect(c.JS_HasException(engine.context));
    var ordinary_cleanup: bool = true;
    const actual_cleanup = c.JS_PiGetExceptionWithFatal(engine.context, &ordinary_cleanup);
    defer engine.freeValue(actual_cleanup);
    try std.testing.expect(!ordinary_cleanup);
    try std.testing.expect(c.JS_IsNull(actual_cleanup));
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try PrimitiveFatalFixture.counter(engine, 0);
}

test "native TUI Win32 SDK completion transfers genuine primitive fatal through owned retirement" {
    const engine = try js.Engine.init(gpa, .{});
    defer engine.deinit();
    try PrimitiveFatalFixture.install(engine);
    try PrimitiveFatalFixture.runToPending(engine,
        "globalThis.primitiveReached=0;nativePrimitiveFatal()");
    // initValue detaches the actual slot before its stable invocation starts.
    // It must retain the policy independently of the primitive reason.
    var completion = @import("extensions/native_sdk_owned_completion.zig").Completion.initValue(
        engine, @as(anyerror!c.JSValue, error.JavaScriptException));
    // Start a NEW empty observer only after initValue detached the event.
    // No inherited first producer can mask a lost pending_generic_fatal bit.
    var outer: js.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&outer);
    completion.release(c.pi_js_undefined());
    try std.testing.expectError(error.JavaScriptException, completion.finishValue());
    _ = engine.leaveNativeInvocation(&outer, c.pi_js_undefined());
    try std.testing.expect(engine.native_fatal_invocation == null);
    const restored = try PrimitiveFatalFixture.takePrimitive(engine);
    engine.freeValue(restored);

    // Both reducers must publish actual private history to every active
    // owner even when an earlier generic fatal skips their normalizer. The
    // ordinary branch separately protects the selected cleanup identity.
    const OwnedCompletion = @import("extensions/native_sdk_owned_completion.zig").Completion;
    const OwnedBoundary = @import("extensions/native_node_commonjs_owned_boundary.zig").Boundary;
    const pending_owner = @import("extensions/native_pending_owner.zig");
    inline for (.{ true, false }) |with_first_fatal| {
        inline for (.{ false, true }) |use_boundary| {
            const host = try js.Engine.init(gpa, .{});
            defer host.deinit();
            const ordinary = try host.checked(c.JS_NewObject(host.context));
            defer host.freeValue(ordinary);
            if (with_first_fatal) {
                try PrimitiveFatalFixture.install(host);
                try PrimitiveFatalFixture.runToPending(host,
                    "globalThis.primitiveReached=0;nativePrimitiveFatal()");
            }
            var owned_completion: OwnedCompletion = if (use_boundary) undefined else
                OwnedCompletion.initValue(host, if (with_first_fatal)
                    @as(anyerror!c.JSValue, error.JavaScriptException)
                else @as(anyerror!c.JSValue, c.pi_js_undefined()));
            var owned_boundary: OwnedBoundary = if (use_boundary) OwnedBoundary.begin(host) else undefined;
            var enclosing: js.Engine.NativeInvocation = .{};
            host.enterNativeInvocation(&enclosing);
            defer if (enclosing.active) { _ = host.leaveNativeInvocation(&enclosing, c.pi_js_undefined()); };
            defer {
                if (use_boundary) {
                    if (!owned_boundary.finished) owned_boundary.finishRetiredPending(null, &.{}) catch {};
                } else {
                    if (!owned_completion.finished) owned_completion.finishVoid() catch {};
                }
            }
            if (use_boundary) {
                if (with_first_fatal)
                    try std.testing.expectError(error.JavaScriptException, owned_boundary.checkCurrent())
                else
                    try owned_boundary.checkCurrent();
            } else owned_completion.release(c.pi_js_undefined());
            try std.testing.expect(!c.JS_HasException(host.context));
            try std.testing.expect(!host.nativeTerminationObserved());

            const generation = c.JS_PiExecutionTerminationGeneration(host.runtime);
            c.JS_PiRequestExecutionTermination(host.runtime);
            try std.testing.expect(c.JS_PiCheckExecutionTermination(host.context) < 0);
            if (with_first_fatal) {
                // Keep a real owned token across cancellation without first
                // passing it through Engine. The reducer must observe it.
                var private_generic: bool = true;
                const private = c.JS_PiGetExceptionWithFatal(host.context, &private_generic);
                try std.testing.expect(c.JS_PiIsExecutionTermination(private));
                try std.testing.expect(!private_generic);
                _ = c.JS_PiThrowNativePending(host.context, c.JS_DupValue(host.context, private), private_generic);
                c.JS_PiCancelExecutionTermination(host.runtime);
                try std.testing.expect(!c.JS_HasException(host.context));
                _ = c.JS_PiThrowNativePending(host.context, private, private_generic);
                try std.testing.expect(!host.nativeTerminationObserved());
            } else {
                try std.testing.expectError(error.ExecutionTerminated, pending_owner.checkFatal(host));
                c.JS_PiCancelExecutionTermination(host.runtime);
                _ = c.JS_Throw(host.context, c.JS_DupValue(host.context, ordinary));
            }
            if (use_boundary) {
                try std.testing.expect(owned_boundary.failed(null));
                try std.testing.expect(owned_boundary.invocation.terminated);
            } else {
                owned_completion.release(c.pi_js_undefined());
                try std.testing.expect(owned_completion.invocation.terminated);
            }
            // Observation is complete before the next owned root retires.
            // Repeated collection must terminate without another request.
            try std.testing.expect(enclosing.terminated);
            try std.testing.expect(host.nativeTerminationObserved());
            try std.testing.expect(!c.JS_HasException(host.context));
            try std.testing.expect(!c.JS_PiIsExecutionTerminating(host.runtime));
            try std.testing.expectEqual(generation +% 1, c.JS_PiExecutionTerminationGeneration(host.runtime));
            _ = c.JS_Throw(host.context, c.JS_DupValue(host.context, ordinary));
            if (use_boundary) {
                var root = c.JS_DupValue(host.context, ordinary);
                owned_boundary.release(&root);
                try std.testing.expect(c.JS_IsUndefined(root));
                try std.testing.expectError(error.ExecutionTerminated, owned_boundary.finishRetiredPending(null, &.{}));
            } else {
                owned_completion.release(c.JS_DupValue(host.context, ordinary));
                try std.testing.expectError(error.ExecutionTerminated, owned_completion.finishValue());
            }
            try std.testing.expect(enclosing.terminated);
            const final = host.leaveNativeInvocation(&enclosing, c.pi_js_undefined());
            try std.testing.expect(c.JS_IsException(final));
            try std.testing.expect(host.native_fatal_invocation == null);
            try std.testing.expect(!host.nativeTerminationObserved());
            var selected_generic: bool = !with_first_fatal;
            const actual = c.JS_PiGetExceptionWithFatal(host.context, &selected_generic);
            defer host.freeValue(actual);
            try std.testing.expectEqual(with_first_fatal, selected_generic);
            if (with_first_fatal)
                try std.testing.expect(c.JS_IsNull(actual))
            else
                try std.testing.expect(c.JS_IsStrictEqual(host.context, actual, ordinary));
            try std.testing.expect(!c.JS_HasException(host.context));
            try std.testing.expect(host.captured_exception == null);
            try std.testing.expect(!c.JS_PiIsExecutionTerminating(host.runtime));
            try std.testing.expectEqual(generation +% 1, c.JS_PiExecutionTerminationGeneration(host.runtime));
        }
    }
}

test "native TUI Win32 fatal async generator retires queued requests and rejects later reuse" {
    const engine = try js.Engine.init(gpa, .{});
    defer engine.deinit();
    try PrimitiveFatalFixture.install(engine);
    try PrimitiveFatalFixture.runToPending(engine,
        "globalThis.primitiveReached=0;globalThis.primitiveGenerator=(async function*(){await 0;try{nativePrimitiveFatal();yield 1}catch(e){primitiveReached++}finally{primitiveReached+=10}})();primitiveGenerator.next().catch(()=>primitiveReached+=100);primitiveGenerator.next().catch(()=>primitiveReached+=1000)");
    const reason = try PrimitiveFatalFixture.takePrimitive(engine);
    engine.freeValue(reason);
    try PrimitiveFatalFixture.counter(engine, 0);
    // Reuse has a fresh ordinary invalid-state result, with no revival of the
    // retired queue and no fabricated historical fatal exception.
    const pending = try engine.eval(
        "primitiveGenerator.next().then(()=>{throw Error('terminated generator reused')},e=>{if(!(e instanceof TypeError))throw Error('terminated generator error');primitiveReached++})",
        "tui-terminated-generator-reuse.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(pending);
    const completed = try engine.awaitValue(pending);
    engine.freeValue(completed);
    try PrimitiveFatalFixture.counter(engine, 1);
}


test "native TUI Win32 Promise capability retires both outputs on genuine fatal init hook" {
    const Hook = struct {
        fn run(context: ?*c.JSContext, kind: c.JSPromiseHookType, _: c.JSValue, _: c.JSValue, _: ?*anyopaque) callconv(.c) void {
            if (kind != c.JS_PROMISE_HOOK_INIT) return;
            const host = js.Engine.fromContext(context.?);
            var invocation: js.Engine.NativeInvocation = .{};
            host.enterNativeInvocation(&invocation);
            const result = PrimitiveFatalFixture.callback(host, c.pi_js_undefined(), &.{}, &.{}) catch |err|
                @import("extensions/native_sdk.zig").fail(host, err);
            _ = host.leaveNativeInvocation(&invocation, result);
        }
    };
    const engine = try js.Engine.init(gpa, .{});
    defer engine.deinit();
    try PrimitiveFatalFixture.install(engine);
    c.JS_SetPromiseHook(engine.runtime, Hook.run, null);
    defer c.JS_SetPromiseHook(engine.runtime, null, null);
    var functions = [_]c.JSValue{ c.pi_js_null(), c.pi_js_null() };
    const result = c.JS_NewPromiseCapability(engine.context, &functions);
    defer engine.freeValue(result);
    defer for (functions) |function| engine.freeValue(function);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_IsUndefined(functions[0]));
    try std.testing.expect(c.JS_IsUndefined(functions[1]));
    try std.testing.expectEqual(@as(usize, 1), PrimitiveFatalFixture.calls);
    try std.testing.expectEqual(@as(usize, 1), PrimitiveFatalFixture.actual_vm_failures);
    try std.testing.expect(engine.native_fatal_invocation == null);
    const actual = try PrimitiveFatalFixture.takePrimitive(engine);
    engine.freeValue(actual);
}

test "native TUI Win32 native generator abort history survives selected ordinary cleanup" {
    const generator = @import("extensions/native_async_generator.zig");
    const Body = struct {
        fn step(host: *js.Engine, _: c.JSValue, _: generator.Completion, _: c.JSValue) anyerror!generator.Action {
            c.JS_PiRequestExecutionTermination(host.runtime);
            _ = c.JS_PiCheckExecutionTermination(host.context);
            var completion = @import("extensions/native_sdk_owned_completion.zig").Completion.initValue(
                host, @as(anyerror!c.JSValue, error.ExecutionTerminated));
            _ = c.JS_PiCheckExecutionTermination(host.context);
            c.JS_PiCancelExecutionTermination(host.runtime);
            _ = c.JS_Throw(host.context, c.pi_js_null());
            const unexpected = try completion.finishValue();
            host.freeValue(unexpected);
            return error.RequiredHistoricalNativeAbort;
        }
    };
    const engine = try js.Engine.init(gpa, .{});
    defer engine.deinit();
    const prototype = try generator.prototype(engine);
    defer engine.freeValue(prototype);
    const value = try generator.create(engine, c.pi_js_undefined(), Body.step, prototype);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeAbortedGenerator", value);
    const source = "globalThis.primitiveReached=0;nativeAbortedGenerator.next().catch(()=>primitiveReached++);primitiveReached+=10";
    const aborted = c.JS_Eval(engine.context, source, source.len,
        "tui-native-generator-ordinary-cleanup.js", c.JS_EVAL_TYPE_GLOBAL);
    try std.testing.expect(c.JS_IsException(aborted));
    try std.testing.expect(c.JS_HasException(engine.context));
    var generic_fatal: bool = true;
    const selected = c.JS_PiGetExceptionWithFatal(engine.context, &generic_fatal);
    defer engine.freeValue(selected);
    try std.testing.expect(!generic_fatal);
    try std.testing.expect(c.JS_IsNull(selected));
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try PrimitiveFatalFixture.counter(engine, 0);
    const pending = try engine.eval(
        "nativeAbortedGenerator.next().then(()=>{throw Error('aborted native generator reused')},e=>{if(!(e instanceof TypeError))throw Error('native generator error');primitiveReached++})",
        "tui-native-generator-reuse.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(pending);
    const completed = try engine.awaitValue(pending);
    engine.freeValue(completed);
    try PrimitiveFatalFixture.counter(engine, 1);
}
