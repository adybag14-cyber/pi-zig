//! Pinned Node24 default throw policy. Private candidate, not globally installed.
//! Native V8 diagnostic formatter is shared with the qualified Intl binding.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Frame = @import("native_tui_alt_frame.zig").Frame;
const diagnostic = @import("native_v8_diagnostics.zig");
const scopes = @import("native_async_scope.zig");
const rejection_mod = @import("native_promise_rejections.zig");
pub const Origin = enum { unhandledRejection, uncaughtException };
pub const Fatal = struct {
    reason: c.JSValue,
    scope: c.JSValue,
    origin: Origin,
    exit_code: u8 = 1,
    pub fn deinit(self: Fatal, engine: *js.Engine) void {
        engine.freeValue(self.reason);
        engine.freeValue(self.scope);
    }
};
const rejection_prefix = "This error originated either by throwing inside of an async function without a catch block, or by rejecting a promise which was not handled with .catch(). The promise rejected with the reason \"";
fn wrapper(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var f: Frame = .{ .engine = engine, .object = target, .bindings = values[0] };
    defer f.deinit();
    const reason = if (args.len != 0) args[0] else c.pi_js_undefined();
    const message = try f.concat(&.{ try f.text(rejection_prefix), try diagnostic.noSideEffectsString(&f, reason), try f.text("\".") });
    const result = try f.construct(try f.get(f.bindings, "errorConstructor"), &.{message});
    const prototype = try f.get(target, "prototype");
    if (c.JS_IsObject(prototype) and c.JS_SetPrototype(engine.context, result, prototype) < 0) return js.capture(engine);
    try js.define(engine, result, "code", f.result(try f.text("ERR_UNHANDLED_REJECTION")));
    try js.define(engine, result, "name", f.result(try f.text("UnhandledPromiseRejection")));
    return f.result(result);
}
fn capturedException(engine: *js.Engine, origin: Origin, exit_code: u8, scope: c.JSValue) !Fatal {
    const reason = engine.captured_exception orelse return error.MissingCapturedOriginalException;
    return .{ .reason = c.JS_DupValue(engine.context, reason), .scope = c.JS_DupValue(engine.context, scope), .origin = origin, .exit_code = exit_code };
}
pub const Policy = struct {
    engine: *js.Engine,
    bindings: c.JSValue,
    pub fn init(engine: *js.Engine) !Policy {
        const bindings = try js.object(engine);
        errdefer engine.freeValue(bindings);
        const symbol = try js.global(engine, "Symbol");
        defer engine.freeValue(symbol);
        try js.define(engine, bindings, "tagSymbol", try js.get(engine, symbol, "toStringTag"));
        inline for (.{ .{ "Symbol", "symbolToString" }, .{ "Function", "functionToString" }, .{ "Object", "objectToString" }, .{ "Error", "errorToString" } }) |entry| {
            const constructor = try js.global(engine, entry[0]);
            defer engine.freeValue(constructor);
            const prototype = try js.get(engine, constructor, "prototype");
            defer engine.freeValue(prototype);
            try js.define(engine, bindings, entry[1], try js.get(engine, prototype, "toString"));
            if (comptime std.mem.eql(u8, entry[0], "Object"))
                try js.define(engine, bindings, "hasOwnProperty", try js.get(engine, prototype, "hasOwnProperty"));
        }
        const base = try js.global(engine, "Error");
        defer engine.freeValue(base);
        try js.define(engine, bindings, "errorConstructor", c.JS_DupValue(engine.context, base));
        const base_prototype = try js.get(engine, base, "prototype");
        defer engine.freeValue(base_prototype);
        const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, base_prototype));
        defer engine.freeValue(prototype);
        const constructor = try @import("native_class.zig").constructor(engine, "UnhandledPromiseRejection", 1, prototype, wrapper, &.{bindings});
        defer engine.freeValue(constructor);
        if (c.JS_SetPrototype(engine.context, constructor, base) < 0) return js.capture(engine);
        try js.define(engine, bindings, "rejectionConstructor", c.JS_DupValue(engine.context, constructor));
        return .{ .engine = engine, .bindings = bindings };
    }
    pub fn deinit(self: *Policy) void {
        self.engine.freeValue(self.bindings);
    }
    pub fn reportUnhandled(self: *Policy, process: c.JSValue, rejection: rejection_mod.Rejection) !?Fatal {
        const engine = self.engine;
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        const guard = scopes.enter(engine, rejection.scope);
        defer guard.restore();
        var f: Frame = .{ .engine = engine, .object = process, .bindings = self.bindings };
        defer f.deinit();
        const event = try f.text("unhandledRejection");
        const emit_generation = engine.native_allocation_generation;
        const emitted = f.method(process, "emit", &.{ event, rejection.reason, rejection.promise }) catch |err| {
            const restored = engine.nativeAllocationError(err, emit_generation);
            if (restored != error.JavaScriptException) return restored;
            return try capturedException(engine, .uncaughtException, 1, guard.previous);
        };
        if (c.JS_ToBool(engine.context, emitted) != 0) return null;
        const reason_generation = engine.native_allocation_generation;
        const reason = self.fatalReason(&f, rejection.reason) catch |err| {
            const restored = engine.nativeAllocationError(err, reason_generation);
            if (restored != error.JavaScriptException) return restored;
            return try capturedException(engine, .uncaughtException, 1, guard.previous);
        };
        return .{ .reason = c.JS_DupValue(engine.context, reason), .scope = c.JS_DupValue(engine.context, rejection.scope), .origin = .unhandledRejection };
    }
    fn fatalReason(self: *Policy, f: *Frame, reason: c.JSValue) !c.JSValue {
        // Node isErrorLike excludes functions and reads only an own-property
        // descriptor. Captured primordial hasOwnProperty invokes proxy descriptor
        // traps exactly as Node does; it does not read stack's value.
        const is_object = c.JS_IsObject(reason) and !c.JS_IsNull(reason) and !c.JS_IsFunction(self.engine.context, reason);
        const is_error_like = is_object and c.JS_ToBool(self.engine.context, try f.call(try f.get(f.bindings, "hasOwnProperty"), reason, &.{try f.text("stack")})) != 0;
        return if (is_error_like) reason else f.construct(try f.get(f.bindings, "rejectionConstructor"), &.{reason});
    }
    fn exitEvent(self: *Policy, f: *Frame, process: c.JSValue) !void {
        if (c.JS_ToBool(self.engine.context, try f.get(process, "_exiting")) != 0) return;
        try f.set(process, "_exiting", c.pi_js_bool(self.engine.context, 1));
        try f.set(process, "exitCode", c.JS_NewInt32(self.engine.context, 1));
        _ = try f.method(process, "emit", &.{ try f.text("exit"), c.JS_NewInt32(self.engine.context, 1) });
    }
    /// Returns null if a caller handles it, or the raw fatal outcome. Source CLI
    /// installs its prepended host exit handler separately; no process exit or
    /// private notification is invented by this dispatcher.
    pub fn reportUncaught(self: *Policy, process: c.JSValue, fatal: Fatal) !?Fatal {
        self.engine.native_exception_diagnostics_suppressed += 1;
        defer self.engine.native_exception_diagnostics_suppressed -= 1;
        const guard = scopes.enter(self.engine, fatal.scope);
        defer guard.restore();
        var f: Frame = .{ .engine = self.engine, .object = process, .bindings = self.bindings };
        defer f.deinit();
        const origin = try f.text(@tagName(fatal.origin));
        const monitor_generation = self.engine.native_allocation_generation;
        _ = f.method(process, "emit", &.{ try f.text("uncaughtExceptionMonitor"), fatal.reason, origin }) catch |err| {
            const restored = self.engine.nativeAllocationError(err, monitor_generation);
            if (restored != error.JavaScriptException) return restored;
            return try capturedException(self.engine, .uncaughtException, 7, fatal.scope);
        };
        const handled_generation = self.engine.native_allocation_generation;
        const handled = f.method(process, "emit", &.{ try f.text("uncaughtException"), fatal.reason, origin }) catch |err| {
            const restored = self.engine.nativeAllocationError(err, handled_generation);
            if (restored != error.JavaScriptException) return restored;
            return try capturedException(self.engine, .uncaughtException, 7, fatal.scope);
        };
        if (c.JS_ToBool(self.engine.context, handled) != 0) return null;
        // Original Node ignores guest errors while notifying exit during fatal
        // unwind. Host allocator failures remain owned native failures.
        const exit_generation = self.engine.native_allocation_generation;
        self.exitEvent(&f, process) catch |err| {
            const restored = self.engine.nativeAllocationError(err, exit_generation);
            if (restored != error.JavaScriptException) return restored;
        };
        return .{ .reason = c.JS_DupValue(self.engine.context, fatal.reason), .scope = c.JS_DupValue(self.engine.context, fatal.scope), .origin = fatal.origin, .exit_code = fatal.exit_code };
    }
};
