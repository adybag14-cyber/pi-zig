//! Exact decision order from Source InteractiveMode.uncaughtCrash.
//! This private host helper does not synthesize the public InteractiveMode class.
//! IO cleanup/reporting remains the actual Main owner responsibility.
const js = @import("native_js_values.zig");
const c = js.c;
pub const Plan = enum {
    emergency_terminal_exit,
    already_shutting_down,
    uncaught_crash,
    pub fn exitCode(self: Plan) u8 {
        return if (self == .emergency_terminal_exit) 129 else 1;
    }
    pub fn unregisterHandlers(self: Plan) bool {
        return self != .already_shutting_down;
    }
    pub fn stopUi(self: Plan) bool {
        return self == .uncaught_crash;
    }
    pub fn recordCrash(self: Plan) bool {
        return self == .uncaught_crash;
    }
};
pub fn classify(engine: *js.Engine, reason: c.JSValue, is_shutting_down: bool) !Plan {
    // Source tests the original reason for a dead terminal before the shutdown
    // guard. Native C capture retains original thrown values without ToString.
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    if (try isDeadTerminal(engine, reason)) return .emergency_terminal_exit;
    return if (is_shutting_down) .already_shutting_down else .uncaught_crash;
}
fn isDeadTerminal(engine: *js.Engine, reason: c.JSValue) !bool {
    // Source: !error || typeof error !== 'object' || !('code' in error).
    if (!c.JS_IsObject(reason) or c.JS_IsNull(reason) or c.JS_IsFunction(engine.context, reason)) return false;
    const atom = c.JS_NewAtom(engine.context, "code");
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    const present = c.JS_HasProperty(engine.context, reason, atom);
    if (present < 0) return js.capture(engine);
    if (present == 0) return false;
    const code = try engine.checked(c.JS_GetProperty(engine.context, reason, atom));
    defer engine.freeValue(code);
    // Source Set.has is strict key identity and never coerces code.
    if (!c.JS_IsString(code)) return false;
    inline for (.{ "EIO", "EPIPE", "ENOTCONN", "ENOTTY" }) |name| {
        const value = try engine.checked(c.JS_NewString(engine.context, name));
        defer engine.freeValue(value);
        if (c.JS_IsStrictEqual(engine.context, code, value)) return true;
    }
    return false;
}
