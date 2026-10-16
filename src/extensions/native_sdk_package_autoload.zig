//! Actual project/user/.agents autoload ordering and project-trust gating over
//! the concrete discovery/path/pattern module bindings supplied by assembly.
const data = @import("native_sdk_package_data.zig");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const f = @import("native_node_function.zig");
pub const Inputs = struct { paths: c.JSValue, discovery: c.JSValue, is_enabled_by_overrides: c.JSValue };
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const imports = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    inline for (.{ "join", "dirname", "resolve" }) |name| { const value = try s.get(inputs.paths, name); if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualPackageAutoloadImport; try data.put(s.engine, imports, name, value); }
    inline for (.{ "collectAutoExtensionEntries", "collectAutoSkillEntries", "collectAutoPromptEntries", "collectAutoThemeEntries", "collectAncestorAgentsSkillDirs", "getHomeDir" }) |name| { const value = try s.get(inputs.discovery, name); if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualPackageAutoloadImport; try data.put(s.engine, imports, name, value); }
    if (!c.JS_IsFunction(engine.context, inputs.is_enabled_by_overrides)) return error.RequiredActualPackageAutoloadImport; try data.put(s.engine, imports, "isEnabledByOverrides", inputs.is_enabled_by_overrides);
    const function = try s.own(try f.createMethod(engine, "addAutoDiscoveredResources", 5, run, &.{imports}));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "addAutoDiscoveredResources", c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.call(try s.get(imports, name), c.pi_js_undefined(), args); }
fn metadata(s: *Scope, scope: []const u8, base: c.JSValue) !c.JSValue { const result = try s.object(); try data.put(s.engine, result, "source", try s.text("auto")); try data.put(s.engine, result, "scope", try s.text(scope)); try data.put(s.engine, result, "origin", try s.text("top-level")); try data.put(s.engine, result, "baseDir", base); return result; }
fn overrides(s: *Scope, settings: c.JSValue) !c.JSValue { const result = try s.object(); inline for (.{ "extensions", "skills", "prompts", "themes" }) |name| { const value = try s.get(settings, name); try data.put(s.engine, result, name, if (v.nullish(value)) try s.array() else value); } return result; }
fn directories(s: *Scope, imports: c.JSValue, base: c.JSValue) !c.JSValue { const result = try s.object(); inline for (.{ "extensions", "skills", "prompts", "themes" }) |name| try data.put(s.engine, result, name, try imported(s, imports, "join", &.{ base, try s.text(name) })); return result; }
fn notHome(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { var s: Scope = .{ .engine = engine }; defer s.deinit(); const left = try imported(&s, roots[0], "resolve", &.{arg(args, 0)}); const right = try imported(&s, roots[0], "resolve", &.{roots[1]}); return c.pi_js_bool(engine.context, @intFromBool(!s.equal(left, right))); }
fn add(s: *Scope, manager: c.JSValue, imports: c.JSValue, accumulator: c.JSValue, kind: [:0]const u8, paths: c.JSValue, info: c.JSValue, patterns: c.JSValue, base: c.JSValue) !void {
    const target = try s.invoke(manager, "getTargetMap", &.{ accumulator, try s.text(kind) }); var iterator = try v.iterator(s, paths); defer iterator.deinit(); errdefer iterator.closePreserving();
    while (try iterator.next()) |path| { defer s.engine.freeValue(path); const enabled = try imported(s, imports, "isEnabledByOverrides", &.{ path, patterns, base }); _ = try s.invoke(manager, "addResource", &.{ target, path, info, enabled }); }
}
fn ordinary(s: *Scope, manager: c.JSValue, imports: c.JSValue, accumulator: c.JSValue, kind: [:0]const u8, dirs: c.JSValue, info: c.JSValue, patterns: c.JSValue, base: c.JSValue) !void {
    const paths = if (stdEqual(kind, "skills")) try imported(s, imports, "collectAutoSkillEntries", &.{ try s.get(dirs, "skills"), try s.text("pi") }) else try imported(s, imports, if (stdEqual(kind, "extensions")) "collectAutoExtensionEntries" else if (stdEqual(kind, "prompts")) "collectAutoPromptEntries" else "collectAutoThemeEntries", &.{try s.get(dirs, kind.ptr)});
    try add(s, manager, imports, accumulator, kind, paths, info, try s.get(patterns, kind.ptr), base);
}
fn stdEqual(a: []const u8, b: []const u8) bool { return @import("std").mem.eql(u8, a, b); }
fn run(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const imports = roots[0]; const accumulator = arg(args, 0); const global_base = arg(args, 3); const project_base = arg(args, 4);
    const user_info = try metadata(&s, "user", global_base); const project_info = try metadata(&s, "project", project_base);
    const user_overrides = try overrides(&s, arg(args, 1)); const project_overrides = try overrides(&s, arg(args, 2)); const user_dirs = try directories(&s, imports, global_base); const project_dirs = try directories(&s, imports, project_base);
    const home_skills = try imported(&s, imports, "join", &.{ try imported(&s, imports, "getHomeDir", &.{}), try s.text(".agents"), try s.text("skills") });
    const trusted = s.truthy(try s.invoke(try s.get(manager, "settingsManager"), "isProjectTrusted", &.{}));
    const ancestor_skills = if (trusted) blk: { const dirs = try imported(&s, imports, "collectAncestorAgentsSkillDirs", &.{try s.get(manager, "cwd")}); break :blk try s.invoke(dirs, "filter", &.{try s.own(try f.createArrow(engine, "", 1, notHome, &.{ imports, home_skills }))}); } else try s.array();
    if (trusted) { try ordinary(&s, manager, imports, accumulator, "extensions", project_dirs, project_info, project_overrides, project_base); try ordinary(&s, manager, imports, accumulator, "skills", project_dirs, project_info, project_overrides, project_base); }
    var ancestors = try v.iterator(&s, ancestor_skills); defer ancestors.deinit(); errdefer ancestors.closePreserving(); while (try ancestors.next()) |dir| {
        defer engine.freeValue(dir); const base = try imported(&s, imports, "dirname", &.{dir}); const info = try v.spread(&s, project_info); try data.put(s.engine, info, "baseDir", base);
        try add(&s, manager, imports, accumulator, "skills", try imported(&s, imports, "collectAutoSkillEntries", &.{ dir, try s.text("agents") }), info, try s.get(project_overrides, "skills"), base);
    }
    if (trusted) { try ordinary(&s, manager, imports, accumulator, "prompts", project_dirs, project_info, project_overrides, project_base); try ordinary(&s, manager, imports, accumulator, "themes", project_dirs, project_info, project_overrides, project_base); }
    try ordinary(&s, manager, imports, accumulator, "extensions", user_dirs, user_info, user_overrides, global_base); try ordinary(&s, manager, imports, accumulator, "skills", user_dirs, user_info, user_overrides, global_base);
    const home_base = try imported(&s, imports, "dirname", &.{home_skills}); const home_info = try v.spread(&s, user_info); try data.put(s.engine, home_info, "baseDir", home_base);
    try add(&s, manager, imports, accumulator, "skills", try imported(&s, imports, "collectAutoSkillEntries", &.{ home_skills, try s.text("agents") }), home_info, try s.get(user_overrides, "skills"), home_base);
    try ordinary(&s, manager, imports, accumulator, "prompts", user_dirs, user_info, user_overrides, global_base); try ordinary(&s, manager, imports, accumulator, "themes", user_dirs, user_info, user_overrides, global_base);
    return c.pi_js_undefined();
}
