//! Prepared actual VM controls. Uncompiled/unqueried/unrun; not require(esm).
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
extern fn pi_test_module_link_allocation_positions(mode: c_int) c_int;
fn compile(engine: *em.Engine, code: []const u8, filename: [:0]const u8) !c.JSValue {
    return engine.eval(code, filename, c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
}
fn check(engine: *em.Engine, code: []const u8) !void {
    const value = try engine.eval(code, "C:/link/observer.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_ToBool(engine.context, value) == 1);
}
fn link(engine: *em.Engine, module: c.JSValue) !void {
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiLinkModuleGraph(engine.context, module));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
fn failure(engine: *em.Engine, module: c.JSValue) !c.JSValue {
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiLinkModuleGraph(engine.context, module));
    try std.testing.expect(c.JS_HasException(engine.context));
    return c.JS_GetException(engine.context);
}
fn evaluate(engine: *em.Engine, module: c.JSValue) !void {
    const result = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
    defer engine.freeValue(result);
    try std.testing.expect(!c.JS_IsException(result));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
const Capture = struct {
    error_value: c.JSValue = undefined,
    replacement: c.JSValue = undefined,
    inject_phase: ?c_int = null,
    calls: usize = 0,
    fn initialize(self: *Capture, engine: *em.Engine) void {
        self.* = .{ .error_value = c.pi_js_undefined(), .replacement = c.pi_js_undefined() };
        c.JS_SetNativeErrorStackHook(engine.runtime, hook, self);
    }
    fn deinit(self: *Capture, engine: *em.Engine) void {
        c.JS_SetNativeErrorStackHook(engine.runtime, null, null);
        engine.freeValue(self.error_value);
        engine.freeValue(self.replacement);
    }
    fn hook(context: ?*c.JSContext, value: c.JSValue, phase: c_int, _: c.JSValue, _: [*c]const u8, _: c_int, _: c_int, _: c_int, data: ?*anyopaque) callconv(.c) c_int {
        const self: *Capture = @ptrCast(@alignCast(data.?));
        self.calls += 1;
        if (self.inject_phase != null and self.inject_phase.? == phase) {
            self.inject_phase = null;
            _ = c.JS_Throw(context, c.JS_DupValue(context, self.replacement));
            return 0; // Genuine native success-with-pending producer boundary.
        }
        if (phase == c.JS_ERROR_STACK_CAPTURE and c.JS_IsUndefined(self.error_value))
            self.error_value = c.JS_DupValue(context, value);
        return 0; // Native capture-only fixture, no guest callback/formatting.
    }
};
test "module link transaction prepares declarations without body evaluation jobs or synthetic namespace result" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const module = try compile(engine, "globalThis.body=1;export function f(){return 3};export let x=4", "C:/link/simple.mjs"); defer engine.freeValue(module);
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    c.JS_RunGC(engine.runtime);
    try link(engine, module);
    try check(engine, "globalThis.body===undefined");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try link(engine, module); // Actual healthy linked no-op, not recreated.
    try evaluate(engine, module);
    try check(engine, "body===1");
}
test "module link transaction leaves syntactically unreachable TLA body unexecuted while preparing real bindings" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const module = try compile(engine, "if(false)await 0;globalThis.tlaBody=1;export const x=4", "C:/link/tla.mjs"); defer engine.freeValue(module);
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    try link(engine, module);
    try check(engine, "globalThis.tlaBody===undefined");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
test "module link transaction accepts healthy evaluated dependency without replacing namespace or cells" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const child = try compile(engine, "export let x=1;export function bump(){x++};globalThis.childBody=1", "fixture:healthy"); defer engine.freeValue(child);
    try evaluate(engine, child);
    const before = try engine.checked(c.JS_GetModuleNamespace(engine.context, c.pi_js_module(child))); defer engine.freeValue(before);
    const root = try compile(engine, "import{x,bump}from'fixture:healthy';bump();globalThis.rootValue=x;", "C:/link/healthy-parent.mjs"); defer engine.freeValue(root);
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    try link(engine, root);
    const after = try engine.checked(c.JS_GetModuleNamespace(engine.context, c.pi_js_module(child))); defer engine.freeValue(after);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, before, after));
    try check(engine, "childBody===1&&globalThis.rootValue===undefined");
    try evaluate(engine, root);
    try check(engine, "rootValue===2&&childBody===1");
}
test "module link transaction repeated ordinary missing binding preserves completed fresh dependency SCC" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const child = try compile(engine, "export function f(){return 3};globalThis.childBody=1", "fixture:completed"); defer engine.freeValue(child);
    const root = try compile(engine, "import{absent}from'fixture:completed';globalThis.failedBody=1", "C:/link/missing.mjs"); defer engine.freeValue(root);
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    const first = try failure(engine, root); defer engine.freeValue(first);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, capture.error_value));
    const ns1 = try engine.checked(c.JS_GetModuleNamespace(engine.context, c.pi_js_module(child))); defer engine.freeValue(ns1);
    const function1 = try engine.checked(c.JS_GetPropertyStr(engine.context, ns1, "f")); defer engine.freeValue(function1);
    c.JS_RunGC(engine.runtime);
    const second = try failure(engine, root); defer engine.freeValue(second);
    const ns2 = try engine.checked(c.JS_GetModuleNamespace(engine.context, c.pi_js_module(child))); defer engine.freeValue(ns2);
    const function2 = try engine.checked(c.JS_GetPropertyStr(engine.context, ns2, "f")); defer engine.freeValue(function2);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, ns1, ns2));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, function1, function2));
    try check(engine, "globalThis.failedBody===undefined&&globalThis.childBody===undefined");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try evaluate(engine, child); // Ordinary evaluator can use retained SCC.
    try check(engine, "childBody===1");
}
test "module link transaction ambiguous export remains genuine binding error before TLA policy or body" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const left = try compile(engine, "export const x=1", "fixture:left"); defer engine.freeValue(left);
    const right = try compile(engine, "export const x=2", "fixture:right"); defer engine.freeValue(right);
    const both = try compile(engine, "export * from'fixture:left';export * from'fixture:right'", "fixture:both"); defer engine.freeValue(both);
    const root = try compile(engine, "import{x}from'fixture:both';if(false)await 0;globalThis.ambiguousBody=1", "C:/link/ambiguous.mjs"); defer engine.freeValue(root);
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    const reason = try failure(engine, root); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, capture.error_value));
    try check(engine, "globalThis.ambiguousBody===undefined");
}
const Sources = struct {
    loads: usize = 0,
    fn load(data: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8) ![]u8 {
        const self: *Sources = @ptrCast(@alignCast(data.?)); self.loads += 1;
        const source = if (std.mem.eql(u8, name, "fixture:cycle-a")) "import{b}from'fixture:cycle-b';export function a(){return b()};" else if (std.mem.eql(u8, name, "fixture:cycle-b")) "import{a}from'fixture:cycle-a';export function b(){return 7};export{a};" else if (std.mem.eql(u8, name, "fixture:leaf")) "export const x=3" else if (std.mem.eql(u8, name, "fixture:branch-a")) "export{x}from'fixture:leaf'" else if (std.mem.eql(u8, name, "fixture:branch-b")) "export{x}from'fixture:leaf'" else return error.ActualLinkFixtureMissing;
        return allocator.dupe(u8, source);
    }
};
test "module link transaction genuine cycles and diamonds resolve once without invoking loader during preparation" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var sources: Sources = .{}; engine.setSourceLoader(.{ .context = &sources, .load = Sources.load });
    const cycle = try compile(engine, "import{a}from'fixture:cycle-a';globalThis.cycleValue=a()", "C:/link/cycle.mjs"); defer engine.freeValue(cycle);
    const diamond = try compile(engine, "import{x as a}from'fixture:branch-a';import{x as b}from'fixture:branch-b';globalThis.diamond=a+b", "C:/link/diamond.mjs"); defer engine.freeValue(diamond);
    const loads = sources.loads;
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    try link(engine, cycle); try link(engine, diamond);
    try std.testing.expectEqual(loads, sources.loads);
    try check(engine, "globalThis.cycleValue===undefined&&globalThis.diamond===undefined");
    try evaluate(engine, cycle); try evaluate(engine, diamond);
    try check(engine, "cycleValue===7&&diamond===6");
}
test "module link transaction refuses malformed and foreign tokens before dereference and permits subsequent healthy use" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const foreign = try em.Engine.init(std.testing.allocator, .{}); defer foreign.deinit();
    const token = try compile(foreign, "export const x=3", "C:/link/foreign.mjs"); defer foreign.freeValue(token);
    const own = try compile(engine, "export const x=4", "C:/link/own.mjs"); defer engine.freeValue(own);
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    const malformed = try failure(engine, c.JS_NewInt32(engine.context, 7)); defer engine.freeValue(malformed);
    const wrong_context = try failure(engine, token); defer engine.freeValue(wrong_context);
    try link(engine, own);
}
test "module link transaction incoming actual pending ordinary and fatal reasons remain identical before admission or polling" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const module = try compile(engine, "globalThis.pendingBody=1", "C:/link/pending.mjs"); defer engine.freeValue(module);
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    for ([_]bool{ false, true }) |fatal| {
        if (fatal) c.JS_SetUncatchableError(engine.context, reason);
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
        const returned = try failure(engine, module); defer engine.freeValue(returned);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, returned));
        try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(returned));
        try std.testing.expectEqual(@as(usize, 0), capture.calls);
        c.JS_ClearUncatchableError(engine.context, reason);
    }
    try link(engine, module);
    try check(engine, "globalThis.pendingBody===undefined");
}
test "module link transaction missing capture-only owner refuses without invoking eager guest prepareStackTrace" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const module = try compile(engine, "globalThis.noOwnerBody=1", "C:/link/no-owner.mjs"); defer engine.freeValue(module);
    try check(engine, "globalThis.prepareCalls=0;Object.defineProperty(Error,'prepareStackTrace',{get(){prepareCalls++;throw 'eager'},configurable:true});true");
    const reason = try failure(engine, module); defer engine.freeValue(reason);
    try check(engine, "prepareCalls===0&&globalThis.noOwnerBody===undefined");
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    try link(engine, module);
}
test "module link transaction native capture success with pending reason stops before further capture and preserves exact object" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const child = try compile(engine, "export const present=1", "fixture:pending-child"); defer engine.freeValue(child);
    const root = try compile(engine, "import{missing}from'fixture:pending-child';globalThis.pendingHookBody=1", "C:/link/pending-hook.mjs"); defer engine.freeValue(root);
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    capture.replacement = try engine.checked(c.JS_NewObject(engine.context));
    capture.inject_phase = c.JS_ERROR_STACK_PREPARE;
    const reason = try failure(engine, root); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, capture.replacement));
    try std.testing.expectEqual(@as(usize, 1), capture.calls);
    try check(engine, "globalThis.pendingHookBody===undefined");
    const again = try failure(engine, root); defer engine.freeValue(again);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, again, reason));
}
test "module link transaction real native Error stack owner defers guest formatting until host reads stack after return" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const child = try compile(engine, "export const present=1", "fixture:lazy-child"); defer engine.freeValue(child);
    const root = try compile(engine, "import{missing}from'fixture:lazy-child'", "C:/link/lazy-error.mjs"); defer engine.freeValue(root);
    const owner = try @import("extensions/native_error_stack.zig").install(engine);
    defer engine.freeValue(owner);
    defer @import("extensions/native_error_stack.zig").uninstall(engine);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try check(engine, "globalThis.formatted=0;Error.prepareStackTrace=function(error,frames){formatted++;return frames};true");
    const reason = try failure(engine, root); defer engine.freeValue(reason);
    try check(engine, "formatted===0");
    const stack = try engine.checked(c.JS_GetPropertyStr(engine.context, reason, "stack")); defer engine.freeValue(stack);
    try check(engine, "formatted===1");
}
test "module link transaction actual allocator sweep covers partial native cells namespace failure undo and ordinary evaluation retry" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_module_link_allocation_positions(0));
}
test "module link transaction actual allocator sweep covers parent then later script child creation and declaration closures" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_module_link_allocation_positions(1));
}
test "module link transaction actual allocator sweep covers numeric empty astral and BMP namespace keys and property construction" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_module_link_allocation_positions(2));
}
test "module link transaction actual allocator sweep retires failed cyclic namespace environments before retry" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_module_link_allocation_positions(3));
}
test "module link transaction actual partial native cell allocation failures permit ordinary default evaluator retry" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_module_link_allocation_positions(4));
}
test "module link transaction actual later script child creation failures permit ordinary default evaluator retry" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_module_link_allocation_positions(5));
}
test "module link transaction actual namespace allocation failures permit ordinary default evaluator retry" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_module_link_allocation_positions(6));
}
test "module link transaction actual cyclic namespace allocation failures permit ordinary default evaluator retry" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_module_link_allocation_positions(7));
}
const PrologueProbe = struct {
    context: *c.JSContext,
    frames: c.JSValue,
    reason: c.JSValue,
    pending_success: bool,
    triggered: bool = false,
    capture_failed: bool = false,
    fn poll(_: ?*c.JSRuntime, data: ?*anyopaque) callconv(.c) c_int {
        const self: *PrologueProbe = @ptrCast(@alignCast(data.?));
        if (self.triggered) return 0;
        // Native metadata capture only: no guest code, ModuleDef mutation,
        // filesystem, resolver, injected clock, or fabricated completion.
        const frames = c.JS_CaptureCurrentStackFrames(self.context, 16, c.pi_js_undefined(), null, 0, 0, 0);
        if (c.JS_IsException(frames)) { self.capture_failed = true; return 1; }
        var count: u32 = 0;
        const length = c.JS_GetPropertyStr(self.context, frames, "length");
        defer c.JS_FreeValue(self.context, length);
        if (c.JS_ToUint32(self.context, &count, length) < 0) {
            c.JS_FreeValue(self.context, frames); self.capture_failed = true; return 1;
        }
        for (0..count) |index| {
            const frame = c.JS_GetPropertyUint32(self.context, frames, @intCast(index));
            defer c.JS_FreeValue(self.context, frame);
            var filename: c.JSValue = undefined;
            var name: c.JSValue = undefined;
            var line: c_int = 0; var column: c_int = 0; var native: c_int = 0; var constructor: c_int = 0;
            if (c.JS_ReadCapturedStackFrame(self.context, frame, &filename, &name, &line, &column, &native, &constructor) < 0) {
                c.JS_FreeValue(self.context, frames); self.capture_failed = true; return 1;
            }
            defer c.JS_FreeValue(self.context, filename);
            defer c.JS_FreeValue(self.context, name);
            if (!c.JS_IsString(filename)) continue;
            const bytes = c.JS_ToCString(self.context, filename);
            if (bytes == null) { c.JS_FreeValue(self.context, frames); self.capture_failed = true; return 1; }
            defer c.JS_FreeCString(self.context, bytes);
            if (std.mem.eql(u8, std.mem.span(bytes), "C:/link/prologue.mjs")) {
                self.frames = frames;
                self.triggered = true;
                if (self.pending_success) {
                    _ = c.JS_Throw(self.context, c.JS_DupValue(self.context, self.reason));
                    return 0; // Actual callback success with actual pending reason.
                }
                return 1; // Actual VM interrupt creates/marks its actual reason.
            }
        }
        c.JS_FreeValue(self.context, frames);
        return 0;
    }
};
fn prologueSubject(pending_success: bool, default_retry: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var source: std.ArrayList(u8) = .empty; defer source.deinit(std.testing.allocator);
    try source.appendSlice(std.testing.allocator, "globalThis.prologueBody=1;");
    for (0..12000) |index| {
        const declaration = try std.fmt.allocPrint(std.testing.allocator, "export function f{d}(){{return {d}}};", .{ index, index });
        defer std.testing.allocator.free(declaration);
        try source.appendSlice(std.testing.allocator, declaration);
    }
    const module = try compile(engine, source.items, "C:/link/prologue.mjs"); defer engine.freeValue(module);
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    var probe: PrologueProbe = .{ .context = engine.context, .frames = c.pi_js_undefined(), .reason = try engine.checked(c.JS_NewObject(engine.context)), .pending_success = pending_success };
    defer engine.freeValue(probe.frames);
    defer engine.freeValue(probe.reason);
    c.JS_SetInterruptHandler(engine.runtime, PrologueProbe.poll, &probe);
    defer c.JS_SetInterruptHandler(engine.runtime, null, null);
    const reason = try failure(engine, module); defer engine.freeValue(reason);
    try std.testing.expect(probe.triggered and !probe.capture_failed);
    if (pending_success) {
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, probe.reason));
    } else {
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, capture.error_value));
        c.JS_ClearUncatchableError(engine.context, reason);
    }
    try check(engine, "globalThis.prologueBody===undefined");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    // Retain the actual captured prologue across GC and rollback. The corrected
    // strict/top-level CallSite contract hides the old callable and receiver.
    c.JS_RunGC(engine.runtime);
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context)); defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "prologueFrames", c.JS_DupValue(engine.context, probe.frames)) < 0) return error.PrologueFramePublicationFailed;
    try check(engine, "prologueFrames.some(f=>f.getFileName()==='C:/link/prologue.mjs'&&f.getFunction()===undefined&&f.getThis()===undefined)");
    if (!default_retry) try link(engine, module);
    try evaluate(engine, module);
    try check(engine, "prologueBody===1");
}
test "module link transaction actual prologue interruption retains private frames across GC undo and API retry" { try prologueSubject(false, false); }
test "module link transaction actual prologue interruption permits ordinary default evaluator retry after undo" { try prologueSubject(false, true); }
test "module link transaction actual prologue success with pending native reason is not mistaken for prepared success" { try prologueSubject(true, false); }
test "module link transaction genuinely unresolved deserialized root is refused then resolves and retries through public API" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const module = try compile(engine, "globalThis.unresolvedBody=1;export function f(){return 3}", "C:/link/unresolved.mjs"); defer engine.freeValue(module);
    var size: usize = 0;
    const bytes = c.JS_WriteObject(engine.context, &size, module, c.JS_WRITE_OBJ_BYTECODE);
    if (bytes == null) return error.ActualModuleSerializationFailed;
    defer c.js_free(engine.context, bytes);
    const unresolved = try engine.checked(c.JS_ReadObject(engine.context, bytes, size, c.JS_READ_OBJ_BYTECODE)); defer engine.freeValue(unresolved);
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    const reason = try failure(engine, unresolved); defer engine.freeValue(reason);
    try check(engine, "globalThis.unresolvedBody===undefined");
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ResolveModule(engine.context, unresolved));
    try link(engine, unresolved);
    try evaluate(engine, unresolved);
    try check(engine, "unresolvedBody===1");
}
const ActiveOwnerProbe = struct {
    module: c.JSValue,
    reason: c.JSValue,
    calls: usize = 0,
    status: c_int = 0,
    fn hook(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: c.JSValue, _: [*c]const u8, _: c_int, _: c_int, _: c_int, data: ?*anyopaque) callconv(.c) c_int {
        const self: *ActiveOwnerProbe = @ptrCast(@alignCast(data.?));
        self.calls += 1;
        self.status = c.JS_PiLinkModuleGraph(context, self.module);
        self.reason = c.JS_GetException(context);
        _ = c.JS_Throw(context, c.JS_DupValue(context, self.reason));
        return -1;
    }
};
test "module link transaction refuses active native Error owner rather than reentering module preparation" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const module = try compile(engine, "globalThis.activeOwnerBody=1", "C:/link/active-owner.mjs"); defer engine.freeValue(module);
    var probe: ActiveOwnerProbe = .{ .module = module, .reason = c.pi_js_undefined() };
    defer engine.freeValue(probe.reason);
    c.JS_SetNativeErrorStackHook(engine.runtime, ActiveOwnerProbe.hook, &probe);
    const result = c.JS_NewError(engine.context); defer engine.freeValue(result);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    c.JS_SetNativeErrorStackHook(engine.runtime, null, null);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expectEqual(@as(c_int, -1), probe.status);
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, probe.reason));
    try check(engine, "globalThis.activeOwnerBody===undefined");
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    try link(engine, module);
}
fn unusedNativeInit(_: ?*c.JSContext, _: ?*c.JSModuleDef) callconv(.c) c_int { return 0; }
test "module link transaction real Engine cancellation during charged graph preparation leaves clean reusable state" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const module = try compile(engine, "globalThis.cancelledBody=1", "C:/link/cancelled.mjs"); defer engine.freeValue(module);
    for (0..12000) |index| {
        var buffer: [80]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buffer, "C:/link/context-only-{d}.mjs", .{index});
        if (c.JS_NewCModule(engine.context, name.ptr, unusedNativeInit) == null) return error.ContextModuleSetupFailed;
    }
    var capture: Capture = undefined; capture.initialize(engine); defer capture.deinit(engine);
    engine.cancelled.store(true, .release);
    defer engine.cancelled.store(false, .release);
    const reason = try failure(engine, module); defer engine.freeValue(reason);
    engine.cancelled.store(false, .release);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, capture.error_value));
    c.JS_ClearUncatchableError(engine.context, reason);
    c.JS_RunGC(engine.runtime);
    try link(engine, module);
    try check(engine, "globalThis.cancelledBody===undefined");
    try evaluate(engine, module);
    try check(engine, "cancelledBody===1");
}
