//! Native default jiti2.7 transformer for an explicit consumed module profile.
//! Real syntax/type/module/meta generation; no identity transform or JS Babel
//! host. Source formatting/diagnostic parity is not inferred from semantics.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const functions = @import("native_node_module_callable.zig");
const allocation = @import("native_async_body.zig");
const lowering = @import("native_jiti_babel_modules.zig");
const meta = @import("native_jiti_babel_meta.zig");
const syntax = @import("native_jiti_babel_syntax.zig");
const generator = @import("native_jiti_babel_generator.zig");
pub const Imports = meta.Imports;
pub fn create(engine: *v.em.Engine, imports: Imports) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, imports.path_to_file_url) or !c.JS_IsFunction(engine.context, imports.file_url_to_path) or !c.JS_IsFunction(engine.context, imports.dirname)) return error.RequiredActualJitiDefaultPathImport;
    return functions.create(engine, "transform", 1, true, call, &.{ imports.path_to_file_url, imports.file_url_to_path, imports.dirname });
}
fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return transform(engine, .{ .path_to_file_url = roots[0], .file_url_to_path = roots[1], .dirname = roots[2] }, if (args.len > 0) args[0] else c.pi_js_undefined());
}
pub fn transform(engine: *v.em.Engine, imports: Imports, options: c.JSValue) anyerror!c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return completion(engine,imports,options) catch |err| {
        if (err == error.JavaScriptException) if (engine.captured_exception) |reason| try allocation.rethrowRecognizedAllocation(engine, reason, generation);
        return err;
    };
}
fn completion(engine:*v.em.Engine,imports:Imports,options:c.JSValue)!c.JSValue{
    if(c.JS_HasException(engine.context))return v.js.capture(engine);
    const value=try values(engine,imports,options);
    if(c.JS_HasException(engine.context)){
        const reason=c.JS_GetException(engine.context);engine.freeValue(value);
        return engine.checked(c.JS_Throw(engine.context,reason));
    }
    return value;
}
fn values(engine: *v.em.Engine, imports: Imports, options: c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    // babel.ts option preparation precedes its transformSync try. Preserve
    // these live reads and ordinary raw failures before native compilation.
    const first_retain = try s.get(options, "retainLines");
    const retain = if (c.JS_IsBool(first_retain)) try s.get(options, "retainLines") else c.pi_js_bool(engine.context, 1);
    const babel = try s.object();
    try v.js.spreadInto(engine, babel, try s.get(options, "babel"));
    const interop_default = s.truthy(try s.get(options, "interopDefault"));
    const asynchronous = s.truthy(try s.get(options, "async"));
    const filename = try s.get(options, "filename");
    const jsx = s.truthy(try s.get(options, "jsx"));
    const typescript = s.truthy(try s.get(options, "ts"));
    // Actual Babel parses TypeScript with isTSX only for a TSX filename. A .ts
    // JSX input therefore reaches the actual native TypeScript parser failure.
    if (jsx and !typescript) return unsupported(engine,"Native JSX code generation requires the actual TSX parser extension",null);
    if (jsx and c.JS_IsString(filename)) {
        const name = try engine.toString(filename); defer engine.gpa.free(name);
        if (@import("std").mem.endsWith(u8,name,"tsx")) return unsupported(engine,"Native TSX code generation requires the actual TSX parser extension",null);
    }
    if (try @import("native_jiti_babel_plugins.zig").nonempty(engine,options)) return unsupported(engine,"Custom Babel plugin execution requires its genuine native implementation",null);
    if (!c.JS_IsBool(retain)) return unsupported(engine,"Native generator requires the actual boolean retainLines result",null);
    var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, babel, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK | c.JS_GPN_ENUM_ONLY) < 0) return v.js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for(0..count)|i|{
        const name=try s.own(try engine.checked(c.JS_AtomToValue(engine.context,names[i].atom)));
        if(!try v.eq(&s,name,"plugins") and !try v.eq(&s,name,"sourceMaps"))return unsupported(engine,"Alternate Babel filename/config/parser/generator options require their genuine native implementation",null);
    }
    const source_maps=try s.get(babel,"sourceMaps");
    const inline_map=try v.eq(&s,source_maps,"inline") or try v.eq(&s,source_maps,"both");
    if(s.truthy(source_maps) and !inline_map and !s.equal(source_maps,c.pi_js_bool(engine.context,1)))return unsupported(engine,"Invalid sourceMaps option",null);
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
    const prepared = syntax.prepare(engine.gpa,source,typescript) catch |err| {
        if(err==error.InvalidTypeScriptInput)return @import("native_jiti_babel_diagnostics.zig").result(engine,source,filename);
        return rejectedCompilation(engine,err,compile_generation);
    };
    defer prepared.deinit(engine.gpa);
    const rewritten = meta.rewrite(engine, imports, prepared.source, filename) catch |err| return rejectedCompilation(engine, err, compile_generation);
    defer engine.gpa.free(rewritten);
    const code = lowering.lower(engine.gpa, rewritten, .{ .typescript = typescript, .async_mode = asynchronous, .no_interop = !interop_default, .resource=prepared.resource }) catch |err| return rejectedCompilation(engine, err, compile_generation);
    defer engine.gpa.free(code);
    const generated = if(s.truthy(retain)) try engine.gpa.dupe(u8,code) else generator.pretty(engine.gpa,code) catch|err|return rejectedCompilation(engine,err,compile_generation);
    defer engine.gpa.free(generated);
    var code_value=try s.text(generated);
    if(inline_map)code_value=try s.own(try generator.inlineMap(engine,code_value,descriptor.value));
    const result = try s.object(); try s.put(result, "code", code_value);
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
