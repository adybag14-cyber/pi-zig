//! Interactive application crash lifecycle. Retain raw guest roots through
//! terminal release; neither the rejection hook nor the initial wire record
//! reads diagnostic getters. The worker alone owns this state and QuickJS.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const scopes = @import("native_async_scope.zig");
const rejections = @import("native_promise_rejections.zig");
const policy_mod = @import("native_promise_rejection_policy.zig");
const routing = @import("native_cli_crash_routing.zig");
pub const protocol = @import("native_fatal_protocol.zig");

pub const Pending = struct {
    reason: c.JSValue,
    scope: c.JSValue,
    plan: protocol.Plan,
};
pub const Manager = struct {
    engine: *js.Engine,
    queue: rejections.Queue,
    policy: policy_mod.Policy,
    process: c.JSValue,
    error_to_string: c.JSValue,
    exit_sentinel: c.JSValue,
    pending: ?Pending = null,
    is_shutting_down: bool = false,
    released: bool = false,
    report_finished: bool = false,

    pub fn init(engine: *js.Engine) !*Manager {
        if (engine.native_application_fatal != null) return error.NativeApplicationFatalAlreadyInstalled;
        const self = try engine.gpa.create(Manager);
        errdefer engine.gpa.destroy(self);
        var queue = try rejections.Queue.init(engine, engine.gpa);
        errdefer queue.deinit();
        var policy = try policy_mod.Policy.init(engine);
        errdefer policy.deinit();
        const process = try js.global(engine, "process");
        errdefer engine.freeValue(process);
        const constructor = try js.global(engine, "Error");
        defer engine.freeValue(constructor);
        const prototype = try js.get(engine, constructor, "prototype");
        defer engine.freeValue(prototype);
        const error_to_string = try js.get(engine, prototype, "toString");
        errdefer engine.freeValue(error_to_string);
        const sentinel = try engine.checked(c.JS_NewError(engine.context));
        errdefer engine.freeValue(sentinel);
        c.JS_SetUncatchableError(engine.context, sentinel);
        self.* = .{ .engine = engine, .queue = queue, .policy = policy, .process = process, .error_to_string = error_to_string, .exit_sentinel = sentinel };
        // This native function contains no raw manager pointer. A guest-retained
        // function becomes inert after deinit, while its Engine is still alive.
        engine.native_application_fatal = self;
        errdefer engine.native_application_fatal = null;
        const callback = try engine.checked(c.JS_NewCFunction(engine.context, uncaughtCrash, "uncaughtCrash", 2));
        defer engine.freeValue(callback);
        const event = try engine.checked(c.JS_NewString(engine.context, "uncaughtException"));
        defer engine.freeValue(event);
        const ignored = try js.invoke(engine, process, "prependListener", &.{ event, callback });
        engine.freeValue(ignored);
        engine.native_rejection_tracking = true;
        engine.native_exception_diagnostics_suppressed += 1;
        c.JS_SetHostPromiseRejectionTracker(engine.runtime, observe, self);
        return self;
    }
    pub fn deinit(self: *Manager) void {
        const engine = self.engine;
        c.JS_SetHostPromiseRejectionTracker(engine.runtime, null, null);
        engine.native_rejection_tracking = false;
        engine.native_application_fatal = null;
        engine.native_exception_diagnostics_suppressed -= 1;
        if (self.pending) |pending| {
            engine.freeValue(pending.reason);
            engine.freeValue(pending.scope);
        }
        self.queue.deinit();
        self.policy.deinit();
        engine.freeValue(self.process);
        engine.freeValue(self.error_to_string);
        engine.freeValue(self.exit_sentinel);
        engine.gpa.destroy(self);
    }
    fn observe(_: ?*c.JSContext, promise: c.JSValue, reason: c.JSValue, handled: bool, raw: ?*anyopaque) callconv(.c) void {
        const self: *Manager = @ptrCast(@alignCast(raw.?));
        if (self.pending == null) self.queue.observe(promise, reason, handled);
    }
    fn retain(self: *Manager, reason: c.JSValue, scope: c.JSValue, plan: protocol.Plan) void {
        if (self.pending != null) return;
        self.pending = .{ .reason = c.JS_DupValue(self.engine.context, reason), .scope = c.JS_DupValue(self.engine.context, scope), .plan = plan };
    }
    fn uncaughtCrash(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = js.Engine.fromContext(context.?);
        const self: *Manager = @ptrCast(@alignCast(engine.native_application_fatal orelse return c.pi_js_undefined()));
        if (self.pending == null) {
            const reason = if (argc > 0) argv[0] else c.pi_js_undefined();
            const plan = routing.classify(engine, reason, self.is_shutting_down) catch |err| {
                if (err == error.OutOfMemory) return engine.throwNativeOutOfMemoryFatal();
                if (err == error.JavaScriptException) return engine.throwCaptured();
                return c.JS_ThrowInternalError(context, "Native application crash classification failed");
            };
            const scope = scopes.capture(engine);
            defer engine.freeValue(scope);
            self.retain(reason, scope, switch (plan) {
                .uncaught_crash => .uncaught_crash,
                .emergency_terminal_exit => .emergency_terminal_exit,
                .already_shutting_down => .already_shutting_down,
            });
            self.is_shutting_down = true;
        }
        // Source's prepended handler calls process.exit, so later uncaught
        // listeners do not run. This private sentinel ends only this owned VM.
        return c.JS_Throw(context, c.JS_DupValue(context, self.exit_sentinel));
    }
    fn dispatch(self: *Manager, fatal: policy_mod.Fatal) !void {
        const outcome = try self.policy.reportUncaught(self.process, fatal);
        if (outcome) |unhandled| {
            defer unhandled.deinit(self.engine);
            // The prepended native exit interrupted event dispatch. Its raw
            // pending reason wins over the internal dispatch sentinel.
            if (self.pending == null) self.retain(unhandled.reason, unhandled.scope, if (unhandled.exit_code == 7) .handler_failure else .uncaught_crash);
        }
    }
    /// Complete jobs/nextTicks first and call only outside an active invocation.
    pub fn checkpoint(self: *Manager) !bool {
        if (self.pending != null) return true;
        if (c.JS_IsJobPending(self.engine.runtime) or scopes.isActive(self.engine)) return false;
        while (try self.queue.takeHandled()) |handled| {
            defer handled.deinit(self.engine.context);
            const neutral = scopes.enter(self.engine, c.pi_js_undefined());
            defer neutral.restore();
            const event = try self.engine.checked(c.JS_NewString(self.engine.context, "rejectionHandled"));
            defer self.engine.freeValue(event);
            const ignored = js.invoke(self.engine, self.process, "emit", &.{ event, handled.promise }) catch |err| {
                if (err != error.JavaScriptException) return err;
                try self.capturedUncaught();
                return self.pending != null;
            };
            self.engine.freeValue(ignored);
        }
        self.queue.checkpoint();
        while (try self.queue.take()) |rejection| {
            defer rejection.deinit(self.engine.context);
            try self.queue.noteReported(rejection);
            if (try self.policy.reportUnhandled(self.process, rejection)) |fatal| {
                defer fatal.deinit(self.engine);
                try self.dispatch(fatal);
                if (self.pending != null) return true;
            }
        }
        return false;
    }
    pub fn capturedUncaught(self: *Manager) !void {
        if (self.pending != null) return;
        const reason = self.engine.captured_exception orelse return error.MissingCapturedOriginalException;
        const scope = scopes.capture(self.engine);
        defer self.engine.freeValue(scope);
        try self.dispatch(.{ .reason = reason, .scope = scope, .origin = .uncaughtException });
    }
    pub fn header(self: *Manager, lease: protocol.Lease) !protocol.Record {
        const pending = self.pending orelse return error.NoNativeFatalRecord;
        return .{ .gpa = self.engine.gpa, .lease = lease, .sequence = 1, .plan = pending.plan, .diagnostic = null };
    }
    pub fn release(self: *Manager, ack: protocol.Ack) !void {
        const pending = self.pending orelse return error.NoNativeFatalRecord;
        if (self.released or ack.sequence != 1) return error.InvalidNativeFatalRelease;
        const expected: protocol.Release = switch (pending.plan) {
            .uncaught_crash, .handler_failure => .restored,
            .emergency_terminal_exit => .terminal_dead,
            .already_shutting_down => .already_released,
        };
        if (ack.release != expected) return error.InvalidNativeFatalRelease;
        self.released = true;
    }
    /// Node getStackString ignores a throwing stack getter and falls back to
    /// the captured Error.prototype.toString. It never calls reason.toString.
    fn errorText(self: *Manager, reason: c.JSValue) ![]u8 {
        const engine = self.engine;
        const generation = engine.native_allocation_generation;
        const stack = js.get(engine, reason, "stack") catch |err| blk: {
            const restored = engine.nativeAllocationError(err, generation);
            if (restored != error.JavaScriptException) return restored;
            break :blk c.pi_js_undefined();
        };
        defer engine.freeValue(stack);
        if (c.JS_IsString(stack) and c.JS_ToBool(engine.context, stack) != 0) return engine.toString(stack);
        const value = try js.call(engine, self.error_to_string, reason, &.{});
        defer engine.freeValue(value);
        return engine.toString(value);
    }
    /// This method is inaccessible until the real terminal owner sends ACK.
    /// The owned pipe carries bytes; Main prints them after restoring the UI.
    pub fn diagnostic(self: *Manager, lease: protocol.Lease) !?protocol.Diagnostic {
        if (!self.released) return error.NativeTerminalReleasePending;
        if (self.report_finished) return error.NativeFatalAlreadyReported;
        const pending = self.pending orelse return error.NoNativeFatalRecord;
        self.report_finished = true;
        const guard = scopes.enter(self.engine, pending.scope);
        defer guard.restore();
        const reporting = pending.plan == .uncaught_crash or pending.plan == .handler_failure;
        const text = if (reporting) try self.errorText(pending.reason) else try self.engine.gpa.dupe(u8, "");
        defer self.engine.gpa.free(text);
        const bytes = try std.fmt.allocPrint(self.engine.gpa, "{s}{s}\n", .{
            if (pending.plan == .uncaught_crash) "pi exiting due to uncaughtException:\n" else "",
            text,
        });
        errdefer self.engine.gpa.free(bytes);
        if (pending.plan != .handler_failure) {
            try js.define(self.engine, self.process, "_exiting", c.pi_js_bool(self.engine.context, 1));
            try js.define(self.engine, self.process, "exitCode", c.JS_NewInt32(self.engine.context, pending.plan.exitCode()));
            const event = try self.engine.checked(c.JS_NewString(self.engine.context, "exit"));
            defer self.engine.freeValue(event);
            const generation = self.engine.native_allocation_generation;
            const ignored = js.invoke(self.engine, self.process, "emit", &.{ event, c.JS_NewInt32(self.engine.context, pending.plan.exitCode()) }) catch |err| blk: {
                const restored = self.engine.nativeAllocationError(err, generation);
                if (restored != error.JavaScriptException) return restored;
                break :blk c.pi_js_undefined();
            };
            self.engine.freeValue(ignored);
        }
        if (!reporting) {
            self.engine.gpa.free(bytes);
            return null;
        }
        return .{ .gpa = self.engine.gpa, .lease = lease, .sequence = 1, .exit_code = pending.plan.exitCode(), .bytes = bytes };
    }
};
