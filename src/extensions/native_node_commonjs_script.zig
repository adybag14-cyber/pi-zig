//! Real patched-Module.wrap script compilation over the linked VM.
//! This deliberately accepts a script, not an unvalidated CJS function body.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub const Prepared = struct {
    engine: *v.em.Engine,
    bytecode: c.JSValue,
    pub fn deinit(self: Prepared) void { self.engine.freeValue(self.bytecode); }
};
/// Primitive strings match the internal compiler input contract. No user
/// coercion, body execution, metadata invention or compile-cache result occurs.
pub fn prepare(engine: *v.em.Engine, code: c.JSValue, filename: c.JSValue) !Prepared {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return prepareBody(engine, code, filename) catch |err| return exactFailure(engine, err, generation);
}
fn prepareBody(engine: *v.em.Engine, code: c.JSValue, filename: c.JSValue) !Prepared {
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    if (!c.JS_IsString(code) or !c.JS_IsString(filename)) return error.ActualCommonJSScriptPrimitiveStringsRequired;
    var code_length: usize = 0;
    const source = c.JS_ToCStringLen(engine.context, &code_length, code);
    if (source == null) return v.js.capture(engine);
    defer c.JS_FreeCString(engine.context, source);
    var filename_length: usize = 0;
    const name = c.JS_ToCStringLen(engine.context, &filename_length, filename);
    if (name == null) return v.js.capture(engine);
    defer c.JS_FreeCString(engine.context, name);
    // Existing VM filename C APIs cannot carry embedded NUL. Reject rather than
    // silently compiling under a truncated physical origin; no parity claim here.
    if (@import("std").mem.indexOfScalar(u8, name[0..filename_length], 0) != null) return error.CommonJSScriptFilenameNulUnsupported;
    var options: c.JSEvalOptions = .{
        .version = c.JS_EVAL_OPTIONS_VERSION,
        .eval_flags = c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_COMPILE_ONLY,
        .filename = name,
        .line_num = 1,
    };
    return .{ .engine = engine, .bytecode = try checkedCompletion(engine, c.JS_Eval2(engine.context, source, code_length, &options)) };
}
/// Run only after compilation succeeded. A patched Module.wrap can deliberately
/// return an arbitrary script; its actual raw completion is preserved here.
pub fn run(prepared: *const Prepared) !c.JSValue {
    const engine = prepared.engine;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    return checkedCompletion(engine, c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, prepared.bytecode))) catch |err| return exactFailure(engine, err, generation);
}
fn checkedCompletion(engine: *v.em.Engine, owned: c.JSValue) !c.JSValue {
    if (c.JS_IsException(owned)) return v.js.capture(engine);
    if (c.JS_HasException(engine.context)) {
        const reason = c.JS_GetException(engine.context); // Own before value cleanup.
        engine.freeValue(owned);
        return engine.checked(c.JS_Throw(engine.context, reason));
    }
    return owned;
}
fn exactFailure(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| return fatal;
    };
    return err;
}
