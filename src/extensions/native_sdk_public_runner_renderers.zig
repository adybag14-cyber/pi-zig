//! Renderer chains retain their actual flattened array across deferred next.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
pub fn resolve(engine: *em.Engine, runner: c.JSValue, name: c.JSValue, base: c.JSValue) !c.JSValue {
    const extensions = try sdk.get(engine, runner, "extensions");
    defer engine.freeValue(extensions);
    const flattened = try flatten(engine, extensions, false);
    defer engine.freeValue(flattened);
    return at(engine, flattened, name, base, c.JS_NewInt32(engine.context, 0));
}
pub fn markdown(engine: *em.Engine, extensions: c.JSValue) !c.JSValue {
    return flatten(engine, extensions, true);
}
fn flatten(engine: *em.Engine, extensions: c.JSValue, markdown_value: bool) !c.JSValue {
    const method = try sdk.get(engine, extensions, "flatMap");
    defer engine.freeValue(method);
    const mapper = try engine.checked(c.pi_js_function_magic(engine.context, project, "", 1, @intFromBool(markdown_value)));
    defer engine.freeValue(mapper);
    return js.call(engine, method, extensions, &.{mapper});
}
fn project(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return projection(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic != 0) catch |err| sdk.fail(engine, err);
}
fn projection(engine: *em.Engine, extension: c.JSValue, markdown_value: bool) !c.JSValue {
    const raw = try sdk.get(engine, extension, if (markdown_value) "markdownTransformer" else "toolRenderers");
    defer engine.freeValue(raw);
    if (!markdown_value) return if (c.JS_IsNull(raw) or c.JS_IsUndefined(raw)) sdk.array(engine) else c.JS_DupValue(engine.context, raw);
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    if (c.JS_ToBool(engine.context, raw) == 1) {
        // The Source conditional and array element each read the getter.
        if (c.JS_DefinePropertyValueUint32(engine.context, result, 0, try sdk.get(engine, extension, "markdownTransformer"), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    return result;
}
fn at(engine: *em.Engine, resolvers: c.JSValue, name: c.JSValue, base: c.JSValue, index: c.JSValue) !c.JSValue {
    const length = try sdk.get(engine, resolvers, "length");
    defer engine.freeValue(length);
    const present = try engine.checked(c.JS_PiBinaryOperator(engine.context, 4, index, length));
    defer engine.freeValue(present);
    if (c.JS_ToBool(engine.context, present) != 1) return js.call(engine, base, c.pi_js_undefined(), &.{});
    const function = try js.getKey(engine, resolvers, index);
    defer engine.freeValue(function);
    var roots = [_]c.JSValue{ resolvers, name, base, index };
    const continuation = try engine.checked(c.JS_NewCFunctionData2(engine.context, next, "", 0, 0, roots.len, &roots));
    defer engine.freeValue(continuation);
    return js.call(engine, function, resolvers, &.{ name, continuation });
}
fn next(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return advance(engine, roots) catch |err| sdk.fail(engine, err);
}
fn advance(engine: *em.Engine, roots: [*c]c.JSValue) !c.JSValue {
    const index = try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, roots[3], c.JS_NewInt32(engine.context, 1)));
    defer engine.freeValue(index);
    return at(engine, roots[0], roots[1], roots[2], index);
}
