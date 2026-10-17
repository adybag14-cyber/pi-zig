//! mlly1.8.2 src/utils.ts file URL wrappers. The imported Node operations are
//! actual captured node:url bindings, not interchangeable path normalizers.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const functions = @import("native_mlly_function.zig");
const allocation = @import("native_async_body.zig");
pub const Imports = struct { file_url_to_path: c.JSValue, path_to_file_url: c.JSValue };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn literalRegex(s: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    const args = [_]c.JSValue{ try s.text(pattern), try s.text(flags) };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, @constCast(&args))));
}
fn exact(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| allocation.rethrowRecognizedAllocation(engine, reason, functions.trustedGeneration(engine, generation)) catch |fatal| return fatal;
    return err;
}
pub fn normalizeSlash(s: *Scope, path: c.JSValue) !c.JSValue {
    // Source resolves the method before constructing its fresh regexp literal.
    const replace = try s.get(path, "replace");
    const regex = try literalRegex(s, "\\\\", "g");
    return s.call(replace, path, &.{ regex, try s.text("/") });
}
pub fn fileURLToPath(s: *Scope, imported: c.JSValue, id: c.JSValue) !c.JSValue {
    if (c.JS_IsString(id)) {
        const starts = try s.get(id, "startsWith");
        if (!s.truthy(try s.call(starts, id, &.{try s.text("file://")}))) return normalizeSlash(s, id);
    }
    const converted = try s.call(imported, c.pi_js_undefined(), &.{id});
    return normalizeSlash(s, converted);
}
pub fn pathToFileURL(s: *Scope, imports: Imports, id: c.JSValue) !c.JSValue {
    const path = try fileURLToPath(s, imports.file_url_to_path, id);
    const url = try s.call(imports.path_to_file_url, c.pi_js_undefined(), &.{path});
    return s.invoke(url, "toString", &.{});
}
pub fn normalizeId(s: *Scope, builtin_set: c.JSValue, input: c.JSValue) !c.JSValue {
    const id = if (c.JS_IsString(input)) input else try s.invoke(input, "toString", &.{});
    const protocol = try literalRegex(s, "(?:node|data|http|https|file):", "");
    if (s.truthy(try s.invoke(protocol, "test", &.{id}))) return id;
    if (s.truthy(try s.invoke(builtin_set, "has", &.{id}))) return s.concat(try s.text("node:"), id);
    const encode = try s.global("encodeURI");
    const slashed = try normalizeSlash(s, id);
    const encoded = try s.call(encode, c.pi_js_undefined(), &.{slashed});
    return s.concat(try s.text("file://"), encoded);
}
fn fileCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return fileBody(engine, args, roots) catch |err| return exact(engine, err, generation);
}
fn fileBody(engine: *v.em.Engine, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    return c.JS_DupValue(engine.context, try fileURLToPath(&s, roots[0], arg(args, 0)));
}
fn pathCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return pathBody(engine, args, roots) catch |err| return exact(engine, err, generation);
}
fn pathBody(engine: *v.em.Engine, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    return c.JS_DupValue(engine.context, try pathToFileURL(&s, .{ .file_url_to_path = roots[0], .path_to_file_url = roots[1] }, arg(args, 0)));
}
/// Component bindings only. Callers pass the actual node:url named functions;
/// this does not register a partial mlly facade or select an import fallback.
pub fn create(engine: *v.em.Engine, imports: Imports) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, imports.file_url_to_path) or !c.JS_IsFunction(engine.context, imports.path_to_file_url)) return error.NativeMllyActualNodeUrlBindingsRequired;
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const result = try s.object();
    try v.js.define(engine, result, "fileURLToPath", try functions.create(engine, "fileURLToPath", 1, fileCall, &.{imports.file_url_to_path}));
    try v.js.define(engine, result, "pathToFileURL", try functions.create(engine, "pathToFileURL", 1, pathCall, &.{ imports.file_url_to_path, imports.path_to_file_url }));
    return c.JS_DupValue(engine.context, result);
}
