//! Exact mlly1.8.2 hasESMSyntax export (MIT, Pooya Parsa).
//! Its primary algorithm is RegExp.test, not Acorn/tokenizer/parser inference.
//! Create once in the actual mlly module; retain/share the same declaration
//! and regex constants across consumers, never once per jiti factory call.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const functions = @import("native_node_module_callable.zig");
const body = @import("native_async_body.zig");
const esm_pattern = "(?:[\\s;]|^)(?:import[\\s\\w*,{}]*from|import\\s*[\"'*{]|export\\b\\s*(?:[*{]|default|class|type|function|const|var|let|async function)|import\\.meta\\b)";
const comment_pattern = "\\/\\*.+?\\*\\/|\\/\\/.*(?=[nr])";
fn literal(engine: *v.em.Engine, pattern: [*:0]const u8, flags: [*:0]const u8) !c.JSValue {
    const source = try engine.checked(c.JS_NewString(engine.context, pattern)); defer engine.freeValue(source);
    const options = try engine.checked(c.JS_NewString(engine.context, flags)); defer engine.freeValue(options);
    var arguments = [_]c.JSValue{source, options};
    return engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, 2, &arguments));
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    const esm = try literal(engine, esm_pattern, "m"); defer engine.freeValue(esm);
    const comments = try literal(engine, comment_pattern, "g"); defer engine.freeValue(comments);
    return functions.create(engine, "hasESMSyntax", 1, true, invoke, &.{esm, comments});
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn invoke(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return hasESMSyntax(engine, roots[0], roots[1], arg(args, 0), arg(args, 1));
}
/// Borrowed original module-scope regex objects. Direct host calls preserve
/// the same diagnostic/fresh-fatal boundary as the actual exported declaration.
pub fn hasESMSyntax(engine: *v.em.Engine, esm: c.JSValue, comments: c.JSValue, code: c.JSValue, requested_options: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return inner(engine, esm, comments, code, requested_options) catch |err| {
        if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
            if (!c.JS_IsUncatchableError(reason)) try body.rethrowRecognizedAllocation(engine, reason, generation);
        };
        return err;
    };
}
fn strip(engine: *v.em.Engine, code: c.JSValue, comments: c.JSValue) !c.JSValue {
    // Source retrieves code.replace before constructing its argument list.
    const replace = try v.js.get(engine, code, "replace"); defer engine.freeValue(replace);
    const empty = try engine.checked(c.JS_NewString(engine.context, "")); defer engine.freeValue(empty);
    return v.js.call(engine, replace, code, &.{comments, empty});
}
fn inner(engine: *v.em.Engine, esm: c.JSValue, comments: c.JSValue, code: c.JSValue, requested_options: c.JSValue) !c.JSValue {
    const options = if (c.JS_IsUndefined(requested_options)) try v.js.object(engine) else c.JS_DupValue(engine.context, requested_options);
    defer engine.freeValue(options);
    const enabled = try v.js.get(engine, options, "stripComments");
    const strip_comments = c.JS_ToBool(engine.context, enabled) != 0; engine.freeValue(enabled);
    const input = if (strip_comments) try strip(engine, code, comments) else c.JS_DupValue(engine.context, code);
    defer engine.freeValue(input);
    // Preserve the exact raw result of the live test call. Replaced prototype
    // methods may return arbitrary objects rather than a native bool.
    return v.js.invoke(engine, esm, "test", &.{input});
}
