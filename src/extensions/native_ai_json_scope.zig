//! Scoped intrinsic-parser error diagnostics; preserves borrowed source/error.
//! Caller/reviver errors never enter the C parser-error hook. No global parser
//! replacement and no guest callback/JSON parse executes inside the hook.
const em = @import("engine.zig");
const diagnostics = @import("native_ai_json_diagnostics.zig");
const c = em.c;
pub const Guard = struct {
    engine: *em.Engine,
    previous: ?*const c.JSJSONParseErrorHook,
    pub fn enter(engine: *em.Engine) Guard {
        const previous = c.JS_PiSetJSONParseErrorHook(engine.context, translate);
        engine.native_json_diagnostic_depth += 1;
        return .{ .engine = engine, .previous = previous };
    }
    pub fn deinit(self: *Guard) void {
        self.engine.native_json_diagnostic_depth -= 1;
        _ = c.JS_PiSetJSONParseErrorHook(self.engine.context, self.previous);
    }
};
fn translate(context: ?*c.JSContext, source: c.JSValue, reason: c.JSValue) callconv(.c) c.JSValue {
    const ctx = context.?;
    const engine = em.Engine.fromContext(ctx);
    if (engine.native_json_diagnostic_depth == 0) return c.JS_DupValue(ctx, reason);
    var length: usize = 0;
    const characters = c.JS_ToCStringLenUTF16(ctx, &length, source);
    if (characters == null) return engine.throwNativeOutOfMemoryFatal();
    defer c.JS_FreeCStringUTF16(ctx, characters);
    const input = characters[0..length];
    const failure = diagnostics.diagnose(engine.gpa, input) catch return engine.throwNativeOutOfMemoryFatal();
    if (failure == null) return c.JS_DupValue(ctx, reason);
    const message = diagnostics.render(engine.gpa, input, failure.?) catch return engine.throwNativeOutOfMemoryFatal();
    defer engine.gpa.free(message);
    const text = c.JS_NewStringUTF16(ctx, message.ptr, message.len);
    if (c.JS_IsException(text)) return engine.throwNativeOutOfMemoryFatal();
    // The fresh intrinsic SyntaxError already owns a writable, non-enumerable
    // message. Assignment retains that descriptor and the actual error object.
    if (c.JS_SetPropertyStr(ctx, reason, "message", text) < 0) return engine.throwNativeOutOfMemoryFatal();
    return c.JS_DupValue(ctx, reason);
}
