//! Owner-only delivery of an already observed native completion. No worker,
//! timer, nextTick substitution, fabricated I/O or Engine pointer leaves owner.
const js = @import("native_js_values.zig");
const std = @import("std");
const c = js.c;
const env = @import("native_env_io.zig");
const scheduler = @import("native_owner_completion.zig");
const local = @import("native_node_socket_scope.zig");
const wake = @import("native_owner_wake.zig");
var completion_tag: u8 = 0;
const Completion = struct {
    hub: *env.Hub, reference: wake.Ref,
    callback: c.JSValue, receiver: c.JSValue,
    arguments: []c.JSValue, stopped: bool = false,
    fn referenced(raw: *anyopaque) bool { return !@as(*Completion, @ptrCast(@alignCast(raw))).stopped; }
    fn poll(raw: *anyopaque) !bool {
        const self: *Completion = @ptrCast(@alignCast(raw)); if (self.stopped) return false;
        try self.hub.assertOwner(); self.stopped = true;
        self.hub.removeResource(self);
        defer self.release();
        const engine = self.hub.engine;
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        var scope: local.Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        _ = try scope.call(self.callback, self.receiver, self.arguments); return true;
    }
    fn stop(raw: *anyopaque) void { const self: *Completion = @ptrCast(@alignCast(raw)); self.stopped = true; }
    fn releaseStopped(raw: *anyopaque) void { const self: *Completion = @ptrCast(@alignCast(raw)); self.release(); }
    fn release(self: *Completion) void {
        const engine = self.hub.engine;
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        var cleanup: local.Cleanup = .{ .engine = engine, .generation = engine.native_allocation_generation };
        cleanup.captureEntry(null);
        for (self.arguments) |value| cleanup.release(value);
        engine.gpa.free(self.arguments); cleanup.release(self.callback); cleanup.release(self.receiver);
        const charged = @sizeOf(Completion) + self.arguments.len * @sizeOf(c.JSValue);
        wake.release(self.reference); engine.gpa.destroy(self);
        c.pi_js_native_memory_release(engine.native_memory_owner, charged);
        cleanup.collect(); cleanup.publish();
    }
};
/// Caller proves the native operation already completed. All values are borrowed;
/// this queue takes independent charged roots and enters VM only via actual Hub.
pub fn enqueue(engine: *js.Engine, callback: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !void {
    try engine.checkNativeEntry();
    const hub = try env.get(engine); try hub.assertOwner();
    if (hub.stopping) return error.NativeEnvClosed;
    var pending: usize = 0;
    for (hub.resources.items) |resource| if (resource.tag == @as(?*const anyopaque, &completion_tag)) { pending += 1; };
    if (pending >= 64) return error.NativeChildCompletionCapacity;
    const charged = std.math.add(usize, @sizeOf(Completion), std.math.mul(usize, args.len, @sizeOf(c.JSValue)) catch return error.OutOfMemory) catch return error.OutOfMemory;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, charged) == 0) return error.OutOfMemory;
    var admitted = false; errdefer if (!admitted) c.pi_js_native_memory_release(engine.native_memory_owner, charged);
    const reference = try scheduler.acquireNativeWake(engine); errdefer wake.release(reference);
    const arguments = try engine.gpa.alloc(c.JSValue, args.len); errdefer engine.gpa.free(arguments);
    const self = try engine.gpa.create(Completion); errdefer engine.gpa.destroy(self);
    for (args, arguments) |value, *slot| slot.* = c.JS_DupValue(engine.context, value);
    self.* = .{ .hub = hub, .reference = reference, .callback = c.JS_DupValue(engine.context, callback), .receiver = c.JS_DupValue(engine.context, receiver), .arguments = arguments };
    errdefer { for (arguments) |value| engine.freeValue(value); engine.freeValue(self.callback); engine.freeValue(self.receiver); }
    hub.addResource(.{ .raw = self, .tag = &completion_tag, .poll = Completion.poll, .referenced = Completion.referenced, .stop = Completion.stop, .stopped = Completion.releaseStopped }) catch |err| return @import("native_child_process_function.zig").directFailure(engine, err, engine.native_allocation_generation);
    admitted = true;
    wake.notify(reference);
}

test "stopped completion checked finalizer retains actual reason without diagnostic coercion" {
    const Fixture = struct {
        engine: *js.Engine, reason: c.JSValue, finalized: usize = 0, formatted: usize = 0,
        var current: ?*@This() = null;
        fn stringify(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            if (current) |self| self.formatted += 1;
            return c.JS_ThrowTypeError(context, "completion control must not format actual reason");
        }
        fn final(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
            self.finalized += 1;
            _ = self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, self.reason))) catch {};
        }
    };
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    engine.native_io = std.testing.io;
    const hub = try env.get(engine);
    const reason = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(reason);
    var fixture: Fixture = .{ .engine = engine, .reason = reason };
    Fixture.current = &fixture; defer Fixture.current = null;
    const poison = try engine.checked(c.JS_NewCFunction(engine.context, Fixture.stringify, "toString", 0)); defer engine.freeValue(poison);
    if (c.JS_DefinePropertyValueStr(engine.context, reason, "toString", c.JS_DupValue(engine.context, poison), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Stopped completion sole argument control", .finalizer = Fixture.final };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const witness = try engine.checked(c.JS_NewObjectClass(engine.context, id));
    var witness_owned = true; defer if (witness_owned) engine.freeValue(witness);
    _ = c.JS_SetOpaque(witness, &fixture);
    const reference = try scheduler.acquireNativeWake(engine);
    var reference_owned = true; defer if (reference_owned) wake.release(reference);
    const charged = @sizeOf(Completion) + @sizeOf(c.JSValue);
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, charged) == 0) return error.OutOfMemory;
    var admitted = false; defer if (!admitted) c.pi_js_native_memory_release(engine.native_memory_owner, charged);
    const arguments = try engine.gpa.alloc(c.JSValue, 1); errdefer if (!admitted) engine.gpa.free(arguments);
    const packet = try engine.gpa.create(Completion);
    arguments[0] = witness;
    packet.* = .{ .hub = hub, .reference = reference, .callback = c.pi_js_undefined(), .receiver = c.pi_js_undefined(), .arguments = arguments, .stopped = true };
    admitted = true; witness_owned = false; reference_owned = false;
    const before = engine.native_exception_diagnostics_suppressed;
    Completion.releaseStopped(packet);
    try std.testing.expectEqual(before, engine.native_exception_diagnostics_suppressed);
    try std.testing.expectEqual(@as(usize, 1), fixture.finalized);
    try std.testing.expectEqual(@as(usize, 0), fixture.formatted);
    try std.testing.expect(c.JS_HasException(engine.context));
    const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, reason));
}
