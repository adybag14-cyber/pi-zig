//! import-meta-resolve4.2.0 resolver error messages and own field descriptors.
//! V8 stack-frame filtering is a separate, unqualified runtime surface.
const m = @import("native_mlly_values.zig");
const c = m.c;
const Scope = m.Scope;
pub const Code = enum {
    ERR_INVALID_MODULE_SPECIFIER, ERR_INVALID_PACKAGE_CONFIG,
    ERR_INVALID_PACKAGE_TARGET, ERR_MODULE_NOT_FOUND,
    ERR_PACKAGE_IMPORT_NOT_DEFINED, ERR_PACKAGE_PATH_NOT_EXPORTED,
    ERR_UNSUPPORTED_DIR_IMPORT, ERR_UNSUPPORTED_RESOLVE_REQUEST, ERR_UNKNOWN_FILE_EXTENSION,
};
fn arg(args: []const c.JSValue, i: usize) c.JSValue { return if (i < args.len) args[i] else c.pi_js_undefined(); }
/// Template interpolation uses ToString, rather than binary+'s default hint.
pub fn template(s: *Scope, parts: []const c.JSValue) !c.JSValue {
    var result = try s.text("");
    for (parts) |part| result = try s.concat(result, try s.stringify(part));
    return result;
}
fn imported(s: *Scope, base: c.JSValue) !c.JSValue { return if (s.truthy(base)) template(s, &.{try s.text(" imported from "), base}) else s.text(""); }
fn json(s: *Scope, value: c.JSValue) !c.JSValue { return s.invoke(try s.global("JSON"), "stringify", &.{value}); }
fn message(s: *Scope, code: Code, args: []const c.JSValue) !c.JSValue {
    const a = arg(args, 0); const b = arg(args, 1); const d = arg(args, 2);
    return switch (code) {
        .ERR_INVALID_MODULE_SPECIFIER => template(s, &.{try s.text("Invalid module \""), a, try s.text("\" "), b, try imported(s, d)}),
        .ERR_INVALID_PACKAGE_CONFIG => template(s, &.{try s.text("Invalid package config "), a,
            if (s.truthy(b)) try template(s, &.{try s.text(" while importing "), b}) else try s.text(""),
            if (s.truthy(d)) try template(s, &.{try s.text(". "), d}) else try s.text("")}),
        .ERR_MODULE_NOT_FOUND => template(s, &.{try s.text("Cannot find "), try s.text(if (s.truthy(d)) "module" else "package"), try s.text(" '"), a, try s.text("' imported from "), b}),
        .ERR_PACKAGE_IMPORT_NOT_DEFINED => template(s, &.{try s.text("Package import specifier \""), a, try s.text("\" is not defined"),
            if (s.truthy(b)) try template(s, &.{try s.text(" in package "), b, try s.text("package.json")}) else try s.text(""), try s.text(" imported from "), d}),
        .ERR_PACKAGE_PATH_NOT_EXPORTED => if (try m.equal(s, b, ".")) template(s, &.{try s.text("No \"exports\" main defined in "), a, try s.text("package.json"), try imported(s, d)}) else
            template(s, &.{try s.text("Package subpath '"), b, try s.text("' is not defined by \"exports\" in "), a, try s.text("package.json"), try imported(s, d)}),
        .ERR_UNSUPPORTED_DIR_IMPORT => template(s, &.{try s.text("Directory import '"), a, try s.text("' is not supported resolving ES modules imported from "), b}),
        .ERR_UNSUPPORTED_RESOLVE_REQUEST => template(s, &.{try s.text("Failed to resolve module specifier \""), a, try s.text("\" from \""), b, try s.text("\": Invalid relative URL or base scheme is not hierarchical.")}),
        .ERR_UNKNOWN_FILE_EXTENSION => template(s,&.{try s.text("Unknown file extension \""),a,try s.text("\" for "),b}),
        .ERR_INVALID_PACKAGE_TARGET => blk: {
            const internal = s.truthy(arg(args, 3)); const base = arg(args, 4);
            const related = c.JS_IsString(d) and !internal and s.truthy(try m.binary(s, 6, try s.get(d, "length"), m.integer(s, 0))) and !s.truthy(try s.invoke(d, "startsWith", &.{try s.text("./")}));
            if (try m.equal(s, b, ".")) break :blk try template(s, &.{try s.text("Invalid \"exports\" main target "), try json(s, d), try s.text(" defined in the package config "), a, try s.text("package.json"), try imported(s, base), try s.text(if (related) "; targets must start with \"./\"" else "")});
            break :blk try template(s, &.{try s.text("Invalid \""), try s.text(if (internal) "imports" else "exports"), try s.text("\" target "), try json(s, d), try s.text(" defined for '"), b, try s.text("' in the package config "), a, try s.text("package.json"), try imported(s, base), try s.text(if (related) "; targets must start with \"./\"" else "")});
        },
    };
}
fn textCall(engine: *m.v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return textBody(engine, receiver, roots) catch |err| return m.exact(engine, err, generation);
}
fn textBody(engine: *m.v.em.Engine, receiver: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    // The message getter runs after name's template coercion in Source.
    const prefix = try template(&s, &.{try s.get(receiver, "name"), try s.text(" ["), roots[0], try s.text("]: ")});
    return c.JS_DupValue(engine.context, try s.concat(prefix, try s.stringify(try s.get(receiver, "message"))));
}
fn descriptor(s: *Scope, value: c.JSValue) !c.JSValue {
    const result = try s.object();
    try m.define(s, result, "value", value); try m.define(s, result, "enumerable", c.pi_js_bool(s.engine.context, 0));
    try m.define(s, result, "writable", c.pi_js_bool(s.engine.context, 1)); try m.define(s, result, "configurable", c.pi_js_bool(s.engine.context, 1)); return result;
}
/// Creates the actual Error/TypeError before rendering the Source message.
/// Dynamic strings remain JS values (including embedded NUL/lone surrogates).
pub fn create(context: m.Context, s: *Scope, code: Code, args: []const c.JSValue) !c.JSValue {
    const base = try context.get(s, switch (code) { .ERR_INVALID_MODULE_SPECIFIER, .ERR_PACKAGE_IMPORT_NOT_DEFINED, .ERR_UNSUPPORTED_RESOLVE_REQUEST, .ERR_UNKNOWN_FILE_EXTENSION => "baseTypeError", else => "baseError" });
    const result = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, base, 0, null)));
    const rendered = try message(s, code, args);
    const object = try s.global("Object"); const define_properties = try s.get(object, "defineProperties");
    const descriptors = try s.object();
    try m.define(s, descriptors, "message", try descriptor(s, rendered));
    const key = try s.text(@tagName(code));
    const to_string = try s.own(try m.functions.createMethod(s.engine, "value", 0, textCall, &.{key}));
    try m.define(s, descriptors, "toString", try descriptor(s, to_string));
    _ = try s.call(define_properties, object, &.{ result, descriptors });
    try s.set(result, "code", key);
    return result;
}
