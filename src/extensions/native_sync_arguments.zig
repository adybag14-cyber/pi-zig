//! Opt-in synchronous Source argument slots. The linked VM chooses alias versus
//! copied formals from the actual call flags; captures own real JSVarRef values.
const std = @import("std");
const em = @import("engine.zig");
const c = em.c;
const Scope = @import("native_models_stream_scope.zig").Scope;
const guest = @import("native_sdk_guest_operation.zig");
const owned = @import("native_sdk_owned_completion.zig");
const sdk = @import("native_sdk.zig");
const NodeScope = @import("native_node_operation_scope.zig").Scope;

pub const Callback = *const fn (*em.Engine, c.JSValue, *Arguments, []const c.JSValue) anyerror!c.JSValue;
pub const StateHook = *const fn (*em.Engine, c.JSValue) anyerror!void;
pub const Hooks = struct { detach: ?StateHook = null, retire: ?StateHook = null };
pub const Definition = struct {
    /// Declared parameter slots, including defaults, independent of .length.
    formal_count: u16,
    callback: Callback,
    strict: bool = true,
    hooks: Hooks = .{},
};

pub const Arguments = struct {
    engine: *em.Engine,
    frame: *c.JSPiSyncArgumentFrame,
    /// Borrowed actual call arguments. Only use these for the actual prologue
    /// (e.g. a rest producer); all mutable formal reads go through get().
    initial: []const c.JSValue,

    pub fn get(self: *const Arguments, index: u16) c.JSValue {
        return c.JS_PiSyncArgumentGet(self.frame, index);
    }
    /// Consumes the incoming completion. The VM publishes the new slot before
    /// retiring its previous value, including when that retirement reenters.
    pub fn take(self: *Arguments, index: u16, incoming: anyerror!c.JSValue) !void {
        const value = try incoming;
        var boundary: guest.Boundary = .{ .engine = self.engine };
        boundary.begin() catch |err| return discard(self.engine, value, err);
        return boundary.finishStatus(c.JS_PiSyncArgumentSet(self.engine.context, self.frame, index, value));
    }
    pub fn copy(self: *Arguments, index: u16, value: c.JSValue) !void {
        return self.take(index, c.JS_DupValue(self.engine.context, value));
    }
    /// Transfers one owned local-state root to the actual C terminal owner.
    /// The supplied hooks must close captures and locals in their two phases.
    pub fn installState(self: *Arguments, value: c.JSValue) void {
        c.JS_PiSyncArgumentInstallState(self.frame, value);
    }
    pub fn createFrame(self: *Arguments, scope: *Scope, comptime Frame: type) !*Frame {
        const frame = try Frame.createSync(scope);
        self.installState(c.JS_DupValue(self.engine.context, frame.owner));
        return frame;
    }
    /// Returns a Scope-borrowed private owner. Each successful capture adds
    /// one actual JSVarRef reference; its lookup in the live C frame is borrowed.
    pub fn capture(self: *Arguments, scope: *Scope, index: u16) !c.JSValue {
        var stage = NodeScope.init(self.engine);
        return owned.ownRoot(scope, try stage.finish(captureBody(&stage, self, index)));
    }
};

fn discard(engine: *em.Engine, value: c.JSValue, err: anyerror) !void {
    var completion = owned.Completion.initVoid(engine, err);
    completion.release(value);
    return completion.finishVoid();
}
fn captureFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const pointer = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
    c.JS_PiSyncArgumentRelease(runtime, @ptrCast(@alignCast(pointer)));
}
fn captureMark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const pointer = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
    c.JS_PiSyncArgumentMark(runtime, @ptrCast(@alignCast(pointer)), marker);
}
fn captureBody(stage: *NodeScope, arguments: *Arguments, index: u16) !c.JSValue {
    try stage.pending();
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(stage.engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{
        .class_name = "Private synchronous parameter reference",
        .finalizer = captureFinalizer,
        .gc_mark = captureMark,
    };
    if (c.JS_NewClass(stage.engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const object_generation = try stage.beforeAllocation();
    const owner = try stage.checkedAllocation(c.JS_NewObjectClass(stage.engine.context, id), object_generation);
    const generation = try stage.beforeAllocation();
    const ref = c.JS_PiSyncArgumentCapture(stage.engine.context, arguments.frame, index);
    // Attach before any failure reduction/retirement. The successful C capture
    // is now owned even if a subsequent pending check rejects this expression.
    if (ref) |pointer| _ = c.JS_SetOpaque(owner, pointer);
    try stage.boundary.checkPendingSince(generation);
    if (ref == null) return error.MissingActualSyncArgumentCaptureReason;
    return c.JS_DupValue(stage.engine.context, owner);
}
fn reference(binding: c.JSValue) *c.JSPiSyncArgumentRef {
    // Only a native closure's own capture from Arguments.capture is accepted.
    return @ptrCast(@alignCast(c.JS_GetOpaque(binding, c.JS_GetClassID(binding)).?));
}
pub fn read(scope: *Scope, binding: c.JSValue) !c.JSValue {
    var boundary: guest.Boundary = .{ .engine = scope.engine }; try boundary.begin();
    return boundary.finishValue(scope, c.JS_PiSyncArgumentRead(scope.engine.context, reference(binding)));
}
/// Consumes an assigned parameter value through the original VM reference,
/// while the frame is open or after its capture has been detached.
pub fn assign(engine: *em.Engine, binding: c.JSValue, incoming: anyerror!c.JSValue) !void {
    const value = try incoming;
    var boundary: guest.Boundary = .{ .engine = engine };
    boundary.begin() catch |err| return discard(engine, value, err);
    return boundary.finishStatus(c.JS_PiSyncArgumentWrite(engine.context, reference(binding), value));
}

pub fn frameHooks(comptime Frame: type) Hooks {
    return .{ .detach = struct {
        fn close(engine: *em.Engine, state: c.JSValue) anyerror!void {
            if (!c.JS_IsLiveObject(engine.runtime, state)) return;
            const pointer = c.JS_GetOpaque(state, c.JS_GetClassID(state)) orelse return;
            const frame: *Frame = @ptrCast(@alignCast(pointer));
            var completion = owned.Completion.initVoid(engine, {});
            frame.detachCaptures(&completion);
            return completion.finishVoid();
        }
    }.close, .retire = struct {
        fn close(engine: *em.Engine, state: c.JSValue) anyerror!void {
            if (!c.JS_IsLiveObject(engine.runtime, state)) return;
            const pointer = c.JS_GetOpaque(state, c.JS_GetClassID(state)) orelse return;
            const frame: *Frame = @ptrCast(@alignCast(pointer));
            var completion = owned.Completion.initVoid(engine, {});
            frame.close(&completion);
            return completion.finishVoid();
        }
    }.close };
}

const Call = struct {
    engine: *em.Engine,
    definition: Definition,
    roots: []const c.JSValue,
    ignore_receiver: bool,
};
/// The caller supplies the original JSClassCall argc/argv/flags, and keeps its
/// real NativeInvocation alive until this whole operation has returned.
/// receiver is the effective Source object for constructor calls. For arrows,
/// ignore_receiver affects only the body; the C frame retains the call receiver.
pub fn invoke(engine: *em.Engine, function: c.JSValue, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int, definition: Definition, roots: []const c.JSValue, ignore_receiver: bool) c.JSValue {
    var call: Call = .{ .engine = engine, .definition = definition, .roots = roots, .ignore_receiver = ignore_receiver };
    return c.JS_PiCallSyncArguments(engine.context, function, receiver, argc, argv, flags,
        definition.formal_count, definition.strict, body, detach, retire, &call);
}
fn body(_: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, frame: ?*c.JSPiSyncArgumentFrame, pointer: ?*anyopaque) callconv(.c) c.JSValue {
    const call: *Call = @ptrCast(@alignCast(pointer.?));
    var arguments: Arguments = .{ .engine = call.engine, .frame = frame.?, .initial = if (argc > 0) argv[0..@intCast(argc)] else &.{} };
    const result = call.definition.callback(call.engine, if (call.ignore_receiver) c.pi_js_undefined() else receiver, &arguments, call.roots) catch |err| sdk.fail(call.engine, err);
    return call.engine.nativeCallbackResult(result);
}
fn detach(_: ?*c.JSContext, state: c.JSValue, pointer: ?*anyopaque) callconv(.c) void {
    const call: *Call = @ptrCast(@alignCast(pointer.?));
    if (call.definition.hooks.detach) |hook| hook(call.engine, state) catch |err| { _ = sdk.fail(call.engine, err); };
    _ = call.engine.nativeCallbackResult(c.pi_js_undefined());
}
fn retire(_: ?*c.JSContext, state: c.JSValue, pointer: ?*anyopaque) callconv(.c) void {
    const call: *Call = @ptrCast(@alignCast(pointer.?));
    if (call.definition.hooks.retire) |hook| hook(call.engine, state) catch |err| { _ = sdk.fail(call.engine, err); };
    _ = call.engine.nativeCallbackResult(c.pi_js_undefined());
}
