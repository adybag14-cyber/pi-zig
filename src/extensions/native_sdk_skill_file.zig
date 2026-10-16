//! Actual Source loadSkillFromFile, validation and SourceInfo over full native YAML.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Import = enum(usize) { read, basename, dirname };
pub fn create(engine: *em.Engine) !c.JSValue {
    const io = engine.native_io orelse return error.NativeSkillFileRequiresIo;
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const fs = engine.native_module_values.get("node:fs").?;
    const path = engine.native_module_values.get("node:path").?;
    return @import("native_node_function.zig").create(engine, "loadSkillFromFile", 2, invoke, &.{ try scope.get(fs, "readFileSync"), try scope.get(path, "basename"), try scope.get(path, "dirname") });
}
fn imported(scope: *Scope, roots: []const c.JSValue, kind: Import, args: []const c.JSValue) !c.JSValue {
    return scope.call(roots[@intFromEnum(kind)], c.pi_js_undefined(), args);
}
fn warning(scope: *Scope, diagnostics: c.JSValue, message: c.JSValue, path: c.JSValue) !void {
    const push = try scope.get(diagnostics, "push");
    const row = try scope.object();
    try scope.put(row, "type", try scope.text("warning"));
    try scope.put(row, "message", message);
    try scope.put(row, "path", path);
    _ = try scope.call(push, diagnostics, &.{row});
}
fn failure(scope: *Scope, diagnostics: c.JSValue, path: c.JSValue, err: anyerror, generation: u64, fallback: []const u8) !void {
    const original = scope.engine.nativeAllocationError(err, generation);
    if (original == error.OutOfMemory) return original;
    const reason = try scope.own(flow.reason(scope.engine, original));
    if (scope.engine.captured_exception) |value| scope.engine.freeValue(value);
    scope.engine.captured_exception = null;
    const constructor = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, constructor);
    if (instance < 0) return js.capture(scope.engine);
    try warning(scope, diagnostics, if (instance != 0) try scope.get(reason, "message") else try scope.text(fallback), path);
}
fn result(scope: *Scope, skill: c.JSValue, diagnostics: c.JSValue) !c.JSValue {
    const value = try scope.object();
    try scope.put(value, "skill", skill);
    try scope.put(value, "diagnostics", diagnostics);
    return value;
}
fn moreThan(scope: *Scope, value: c.JSValue, maximum: i32) !bool {
    return scope.truthy(try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 6, value, c.JS_NewInt32(scope.engine.context, maximum)))));
}
fn descriptionErrors(scope: *Scope, description: c.JSValue) !c.JSValue {
    const errors = try scope.array();
    if (!c.JS_IsString(description) or scope.equal(try scope.invoke(description, "trim", &.{}), try scope.text(""))) {
        _ = try scope.invoke(errors, "push", &.{try scope.text("description is required")});
    } else if (try moreThan(scope, try scope.get(description, "length"), 1024)) {
        const message = try scope.concat(try scope.concat(try scope.text("description exceeds 1024 characters ("), try scope.stringify(try scope.get(description, "length"))), try scope.text(")"));
        _ = try scope.invoke(errors, "push", &.{message});
    }
    return errors;
}
fn nameErrors(scope: *Scope, name: c.JSValue) !c.JSValue {
    const errors = try scope.array();
    if (try moreThan(scope, try scope.get(name, "length"), 64)) {
        const message = try scope.concat(try scope.concat(try scope.text("name exceeds 64 characters ("), try scope.stringify(try scope.get(name, "length"))), try scope.text(")"));
        _ = try scope.invoke(errors, "push", &.{message});
    }
    var regex_args = [_]c.JSValue{try scope.text("^[a-z0-9-]+$")};
    const regex = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, regex_args.len, &regex_args)));
    if (!scope.truthy(try scope.invoke(regex, "test", &.{name}))) _ = try scope.invoke(errors, "push", &.{try scope.text("name contains invalid characters (must be lowercase a-z, 0-9, hyphens only)")});
    if (scope.truthy(try scope.invoke(name, "startsWith", &.{try scope.text("-")})) or scope.truthy(try scope.invoke(name, "endsWith", &.{try scope.text("-")}))) _ = try scope.invoke(errors, "push", &.{try scope.text("name must not start or end with a hyphen")});
    if (scope.truthy(try scope.invoke(name, "includes", &.{try scope.text("--")}))) _ = try scope.invoke(errors, "push", &.{try scope.text("name must not contain consecutive hyphens")});
    return errors;
}
fn warnings(scope: *Scope, diagnostics: c.JSValue, errors: c.JSValue, path: c.JSValue) !void {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var it = try js.Iterator.init(scope.engine, errors, symbol);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |message| {
        defer scope.engine.freeValue(message);
        try warning(scope, diagnostics, message, path);
    }
}
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
fn sourceInfo(scope: *Scope, path: c.JSValue, base: c.JSValue, source: c.JSValue) !c.JSValue {
    const info = try scope.object();
    try scope.put(info, "path", path);
    const user = scope.equal(source, try scope.text("user"));
    const project = scope.equal(source, try scope.text("project"));
    const explicit = scope.equal(source, try scope.text("path"));
    try scope.put(info, "source", if (user or project or explicit) try scope.text("local") else source);
    try scope.put(info, "scope", try scope.text(if (user) "user" else if (project) "project" else "temporary"));
    try scope.put(info, "origin", try scope.text("top-level"));
    try scope.put(info, "baseDir", base);
    return info;
}
fn parsed(scope: *Scope, raw: c.JSValue) !c.JSValue {
    return (try @import("native_sdk_frontmatter_values.zig").parseValue(scope, raw)).frontmatter;
}
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = if (args.len > 0) args[0] else c.pi_js_undefined();
    const source = if (args.len > 1) args[1] else c.pi_js_undefined();
    const diagnostics = try scope.array();
    const declared = scope.equal(try imported(&scope, roots, .basename, &.{path}), try scope.text("SKILL.md"));
    const read_generation = engine.native_allocation_generation;
    const raw = imported(&scope, roots, .read, &.{ path, try scope.text("utf-8") }) catch |err| {
        try failure(&scope, diagnostics, path, err, read_generation, "failed to read skill file");
        return c.JS_DupValue(engine.context, try result(&scope, c.pi_js_null(), diagnostics));
    };
    const parse_generation = engine.native_allocation_generation;
    const frontmatter_value = parsed(&scope, raw) catch |err| {
        if (engine.nativeAllocationError(err, parse_generation) == error.OutOfMemory) return error.OutOfMemory;
        if (declared) try failure(&scope, diagnostics, path, err, parse_generation, "failed to parse skill file") else {
            if (engine.captured_exception) |value| engine.freeValue(value);
            engine.captured_exception = null;
        }
        return c.JS_DupValue(engine.context, try result(&scope, c.pi_js_null(), diagnostics));
    };
    const description = try scope.get(frontmatter_value, "description");
    const has_description = c.JS_IsString(description) and !scope.equal(try scope.invoke(description, "trim", &.{}), try scope.text(""));
    if (!declared and !has_description) return c.JS_DupValue(engine.context, try result(&scope, c.pi_js_null(), diagnostics));
    const directory = try imported(&scope, roots, .dirname, &.{path});
    const parent_name = try imported(&scope, roots, .basename, &.{directory});
    try warnings(&scope, diagnostics, try descriptionErrors(&scope, description), path);
    const maybe_name = try scope.get(frontmatter_value, "name");
    // Source reads the property again in the true branch of its typeof test.
    const frontmatter_name = if (c.JS_IsString(maybe_name)) try scope.get(frontmatter_value, "name") else c.pi_js_undefined();
    const name = if (scope.truthy(frontmatter_name)) frontmatter_name else parent_name;
    try warnings(&scope, diagnostics, try nameErrors(&scope, name), path);
    if (!has_description) return c.JS_DupValue(engine.context, try result(&scope, c.pi_js_null(), diagnostics));
    const skill = try scope.object();
    try scope.put(skill, "name", name);
    try scope.put(skill, "description", description);
    try scope.put(skill, "filePath", path);
    try scope.put(skill, "baseDir", directory);
    try scope.put(skill, "sourceInfo", try sourceInfo(&scope, path, directory, source));
    try scope.put(skill, "disableModelInvocation", c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(frontmatter_value, "disable-model-invocation"), c.pi_js_bool(engine.context, 1)))));
    return c.JS_DupValue(engine.context, try result(&scope, skill, diagnostics));
}
