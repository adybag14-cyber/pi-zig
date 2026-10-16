//! Actual package source parsing and offline predicates over required concrete
//! semver, Git URL and path collaborators. No approximate parser is supplied.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const f = @import("native_node_function.zig");
pub const Inputs = struct { process: c.JSValue, is_local_path: c.JSValue, parse_git_url: c.JSValue, valid: c.JSValue, valid_range: c.JSValue };
pub const methods = .{ "parseSource", "parseNpmSpec" };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const imports = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try s.put(imports, "process", inputs.process);
    inline for (.{ .{ "isLocalPath", inputs.is_local_path }, .{ "parseGitUrl", inputs.parse_git_url }, .{ "valid", inputs.valid }, .{ "validRange", inputs.valid_range } }) |entry| {
        if (!c.JS_IsFunction(engine.context, entry[1])) return error.RequiredActualPackageSourceParserImport;
        try s.put(imports, entry[0], entry[1]);
    }
    const exports = try s.object();
    inline for (.{ "isOfflineModeEnabled", "isExactNpmVersion", "getNpmVersionRange" }, 0..) |name, index| try s.put(exports, name, try s.own(try f.create(engine, name, if (index == 0) 0 else 1, predicate, &.{ imports, c.JS_NewInt32(engine.context, @intCast(index)) })));
    inline for (methods, 0..) |name, index| {
        const value = try s.own(try f.createMethod(engine, name, 1, parse, &.{ imports, exports, c.JS_NewInt32(engine.context, @intCast(index)) }));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, c.JS_DupValue(engine.context, value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
    }
    return c.JS_DupValue(engine.context, exports);
}
fn predicate(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine);
    if (raw == 0) {
        const value = try s.get(try s.get(try s.get(roots[0], "process"), "env"), "PI_OFFLINE");
        if (!s.truthy(value)) return c.pi_js_bool(engine.context, 0);
        const result = try v.eq(&s, value, "1") or try v.eq(&s, try s.invoke(value, "toLowerCase", &.{}), "true") or try v.eq(&s, try s.invoke(value, "toLowerCase", &.{}), "yes");
        return c.pi_js_bool(engine.context, @intFromBool(result));
    }
    const value = arg(args, 0);
    if (raw == 1) {
        const parsed = try s.call(try s.get(roots[0], "valid"), c.pi_js_undefined(), &.{if (v.nullish(value)) try s.text("") else value});
        return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsNull(parsed)));
    }
    if (!s.truthy(value)) return c.pi_js_undefined();
    const range = try s.call(try s.get(roots[0], "validRange"), c.pi_js_undefined(), &.{value});
    return c.JS_DupValue(engine.context, if (v.nullish(range)) c.pi_js_undefined() else range);
}
fn npmSpec(s: *Scope, spec: c.JSValue) !c.JSValue {
    const match_method = try s.get(spec, "match");
    var args = [_]c.JSValue{ try s.text("^(@?[^@]+(?:/[^@]+)?)(?:@(.+))?$"), try s.text("") };
    const regexp = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, 2, &args)));
    const matched = try s.call(match_method, spec, &.{regexp}); const result = try s.object();
    if (!s.truthy(matched)) { try s.put(result, "name", spec); return result; }
    const name = try v.at(s, matched, 1); try s.put(result, "name", if (v.nullish(name)) spec else name); try s.put(result, "version", try v.at(s, matched, 2)); return result;
}
fn source(s: *Scope, manager: c.JSValue, text: c.JSValue, imports: c.JSValue, predicates: c.JSValue) !c.JSValue {
    if (s.truthy(try s.invoke(text, "startsWith", &.{try s.text("npm:")}))) {
        const spec = try s.invoke(try s.invoke(text, "slice", &.{c.JS_NewInt32(s.engine.context, 4)}), "trim", &.{});
        const parsed = try s.invoke(manager, "parseNpmSpec", &.{spec}); const name = try s.get(parsed, "name"); const version = try s.get(parsed, "version");
        const result = try s.object(); try s.put(result, "type", try s.text("npm")); try s.put(result, "spec", spec); try s.put(result, "name", name); try s.put(result, "version", version);
        try s.put(result, "range", try s.call(try s.get(predicates, "getNpmVersionRange"), c.pi_js_undefined(), &.{version}));
        try s.put(result, "pinned", try s.call(try s.get(predicates, "isExactNpmVersion"), c.pi_js_undefined(), &.{version})); return result;
    }
    if (!s.truthy(try s.call(try s.get(imports, "isLocalPath"), c.pi_js_undefined(), &.{text}))) {
        const git = try s.call(try s.get(imports, "parseGitUrl"), c.pi_js_undefined(), &.{text}); if (s.truthy(git)) return git;
    }
    const result = try s.object(); try s.put(result, "type", try s.text("local")); try s.put(result, "path", text); return result;
}
fn parse(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[2]) < 0) return v.js.capture(engine);
    return c.JS_DupValue(engine.context, if (raw == 1) try npmSpec(&s, arg(args, 0)) else try source(&s, manager, arg(args, 0), roots[0], roots[1]));
}
