//! Native default jiti2.7 transformer for an explicit consumed module profile.
//! Real syntax/type/module/meta generation; no identity transform or JS Babel
//! host. Source formatting/diagnostic parity is not inferred from semantics.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const functions = @import("native_node_module_callable.zig");
const allocation = @import("native_async_body.zig");
const lowering = @import("native_jiti_cjs_lower.zig");
const meta = @import("native_jiti_import_meta.zig");
pub const Imports = meta.Imports;
pub fn create(engine: *v.em.Engine, imports: Imports) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, imports.path_to_file_url) or !c.JS_IsFunction(engine.context, imports.file_url_to_path) or !c.JS_IsFunction(engine.context, imports.dirname)) return error.RequiredActualJitiDefaultPathImport;
    return functions.create(engine, "transform", 1, true, call, &.{ imports.path_to_file_url, imports.file_url_to_path, imports.dirname });
}
fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return transform(engine, .{ .path_to_file_url = roots[0], .file_url_to_path = roots[1], .dirname = roots[2] }, if (args.len > 0) args[0] else c.pi_js_undefined());
}
pub fn transform(engine: *v.em.Engine, imports: Imports, options: c.JSValue) anyerror!c.JSValue {
    const generation = engine.native_allocation_generation;
    return values(engine, imports, options) catch |err| {
        if (err == error.JavaScriptException) if (engine.captured_exception) |reason| try allocation.rethrowRecognizedAllocation(engine, reason, generation);
        return err;
    };
}
fn values(engine: *v.em.Engine, imports: Imports, options: c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    // babel.ts option preparation precedes its transformSync try. Preserve
    // these live reads and ordinary raw failures before native compilation.
    const first_retain = try s.get(options, "retainLines");
    const retain = if (c.JS_IsBool(first_retain)) try s.get(options, "retainLines") else c.pi_js_bool(engine.context, 1);
    const babel = try s.object();
    try v.js.spreadInto(engine, babel, try s.get(options, "babel"));
    _ = s.truthy(try s.get(options, "interopDefault")); // named-only imports need no interop wrapper in either mode
    const asynchronous = s.truthy(try s.get(options, "async"));
    const filename = try s.get(options, "filename");
    if (s.truthy(try s.get(options, "jsx"))) return unsupported(engine, "JSX transformer/plugins are outside the native jiti default profile", null);
    const typescript = s.truthy(try s.get(options, "ts"));
    if (typescript and s.truthy(try s.get(options, "jsx"))) return unsupported(engine, "TSX/decorator metadata extensions are outside the native jiti default profile", null);
    if (s.truthy(try s.get(options, "babel"))) {
        const array = try s.global("Array"); const is_array = try s.get(array, "isArray");
        const plugins = try s.get(try s.get(options, "babel"), "plugins");
        if (s.truthy(try s.call(is_array, array, &.{plugins}))) return unsupported(engine, "Custom Babel plugins are outside the native jiti default profile", null);
    }
    if (!s.equal(retain, c.pi_js_bool(engine.context, 1))) return unsupported(engine, "Only default retainLines:true is admitted by the native jiti compiler profile", null);
    var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, babel, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK | c.JS_GPN_ENUM_ONLY) < 0) return v.js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    if (count != 0) return unsupported(engine, "Source maps/config/parser/generator/custom Babel options are outside the native jiti default profile", null);
    // This consumed path receives a data source field from the actual outer
    // transform spread. Direct accessor/malformed source diagnostics remain an
    // explicit frontier rather than fabricated BABEL_PARSE_ERROR markers.
    const atom = c.JS_NewAtom(engine.context, "source"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    const present = c.JS_GetOwnProperty(engine.context, &descriptor, options, atom);
    if (present < 0) return v.js.capture(engine);
    if (present == 0) return unsupported(engine, "Native jiti default profile requires an own string source field", null);
    defer engine.freeValue(descriptor.value); defer engine.freeValue(descriptor.getter); defer engine.freeValue(descriptor.setter);
    if (!c.JS_IsUndefined(descriptor.getter) or !c.JS_IsUndefined(descriptor.setter) or !c.JS_IsString(descriptor.value)) return unsupported(engine, "Accessor/non-string source diagnostics are outside the native jiti default profile", null);
    const source = try engine.toString(descriptor.value); defer engine.gpa.free(source);
    const compile_generation = engine.native_allocation_generation;
    const rewritten = meta.rewrite(engine, imports, source, filename) catch |err| return rejectedCompilation(engine, err, compile_generation);
    defer engine.gpa.free(rewritten);
    const code = lowering.lower(engine.gpa, rewritten, .{ .typescript = typescript, .async_mode = asynchronous }) catch |err| return rejectedCompilation(engine, err, compile_generation);
    defer engine.gpa.free(code);
    const result = try s.object(); try s.put(result, "code", try s.text(code));
    return c.JS_DupValue(engine.context, result);
}
fn rejectedCompilation(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.OutOfMemory or err == error.TypeScriptParseFailed or err == error.WriteFailed) return error.OutOfMemory;
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        if (c.JS_IsUncatchableError(reason)) return err;
        allocation.rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| return fatal;
        const held = c.JS_DupValue(engine.context, reason); defer engine.freeValue(held);
        return unsupported(engine, "Babel-compatible failure formatting is outside the native jiti compiler profile", held);
    };
    return unsupported(engine, (@errorName(err)).ptr, null);
}
fn unsupported(engine: *v.em.Engine, message: [*:0]const u8, cause: ?c.JSValue) anyerror {
    _ = engine.checked(c.JS_ThrowTypeError(engine.context, "%s", message)) catch |err| {
        if (err != error.JavaScriptException) return err;
        const value = engine.captured_exception orelse return err;
        const held = c.JS_DupValue(engine.context, value); defer engine.freeValue(held);
        const code = engine.checked(c.JS_NewString(engine.context, "PI_UNSUPPORTED_JITI_DEFAULT_TRANSFORM")) catch |failure| return failure;
        v.js.define(engine, held, "code", code) catch |failure| return failure;
        if (cause) |reason| if (c.JS_DefinePropertyValueStr(engine.context, held, "cause", c.JS_DupValue(engine.context, reason), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
        _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, held))) catch |failure| return failure;
        unreachable;
    };
    unreachable;
}
