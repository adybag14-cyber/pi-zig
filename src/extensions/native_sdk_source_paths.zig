//! Actual Source utils/paths.ts normalization, resolution and display algorithms.
//! Native Node path primitives retain their own live cwd fallback evaluation.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temporary = @import("native_sdk_prompt_scope.zig");
const Scope = temporary.Scope;
const c = em.c;

fn node(scope: *Scope, name: [*:0]const u8, arguments: []const c.JSValue) !c.JSValue {
    if (!scope.engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(scope.engine, scope.engine.native_io orelse return error.NativeSourcePathsRequireIo);
    const exports = scope.engine.native_module_values.get("node:path").?;
    return scope.call(try scope.get(exports, name), c.pi_js_undefined(), arguments);
}
fn current(scope: *Scope) !c.JSValue {
    return scope.invoke(try scope.global("process"), "cwd", &.{});
}
fn regex(scope: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    var arguments = [_]c.JSValue{ try scope.text(pattern), try scope.text(flags) };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, arguments.len, &arguments)));
}
fn unicodeSpaces(scope: *Scope) !c.JSValue {
    const name = "pi-native:source-path-unicode-spaces";
    if (!scope.engine.native_module_values.contains(name)) {
        const exports = try scope.object();
        try scope.put(exports, "expression", try regex(scope, "[\\u00A0\\u2000-\\u200A\\u202F\\u205F\\u3000]", "g"));
        try scope.engine.registerValueModule(name, exports);
    }
    return scope.get(scope.engine.native_module_values.get(name).?, "expression");
}
fn windows(scope: *Scope) !bool {
    return scope.equal(try scope.get(try scope.global("process"), "platform"), try scope.text("win32"));
}
fn shellPath(scope: *Scope, input: c.JSValue) !c.JSValue {
    if (!scope.truthy(try scope.invoke(input, "startsWith", &.{try scope.text("/")})) or scope.truthy(try scope.invoke(input, "startsWith", &.{try scope.text("//")})) or scope.truthy(try scope.invoke(input, "includes", &.{try scope.text("\\")}))) return input;
    const match_method = try scope.get(input, "match");
    const matched = try scope.call(match_method, input, &.{try regex(scope, "^/(?:mnt/|cygdrive/)?([a-z])(?:/(.*))?$", "i")});
    if (!scope.truthy(matched)) return input;
    const tail = try scope.own(try js.getKey(scope.engine, matched, c.JS_NewInt32(scope.engine.context, 2)));
    const suffix = if (temporary.nullish(tail)) c.pi_js_undefined() else try scope.invoke(tail, "replaceAll", &.{ try scope.text("/"), try scope.text("\\") });
    const drive = try scope.own(try js.getKey(scope.engine, matched, c.JS_NewInt32(scope.engine.context, 1)));
    return scope.concat(try scope.concat(try scope.stringify(try scope.invoke(drive, "toUpperCase", &.{})), try scope.text(":\\")), try scope.stringify(if (temporary.nullish(suffix)) try scope.text("") else suffix));
}
pub fn windowsShell(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try shellPath(&scope, input));
}
pub fn normalize(engine: *em.Engine, input: c.JSValue, supplied_options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = if (c.JS_IsUndefined(supplied_options)) try scope.object() else supplied_options;
    var value = if (scope.truthy(try scope.get(options, "trim"))) try scope.invoke(input, "trim", &.{}) else input;
    if (scope.truthy(try scope.get(options, "normalizeUnicodeSpaces"))) {
        const replace = try scope.get(value, "replace");
        value = try scope.call(replace, value, &.{ try unicodeSpaces(&scope), try scope.text(" ") });
    }
    if (scope.truthy(try scope.get(options, "stripAtPrefix")) and scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("@")}))) value = try scope.invoke(value, "slice", &.{c.JS_NewInt32(engine.context, 1)});
    if (try windows(&scope)) value = try shellPath(&scope, value);
    const expand = try scope.get(options, "expandTilde");
    if (temporary.nullish(expand) or scope.truthy(expand)) {
        const supplied = try scope.get(options, "homeDir");
        const home = if (temporary.nullish(supplied)) try scope.own(try @import("native_home.zig").get(engine)) else supplied;
        if (scope.equal(value, try scope.text("~"))) return c.JS_DupValue(engine.context, home);
        if (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("~/")})) or ((try windows(&scope)) and scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("~\\")})))) {
            const joined = try node(&scope, "join", &.{ home, try scope.invoke(value, "slice", &.{c.JS_NewInt32(engine.context, 2)}) });
            return c.JS_DupValue(engine.context, joined);
        }
    }
    // Source uses a fresh literal RegExp and its live test method here.
    if (scope.truthy(try scope.invoke(try regex(&scope, "^file://", ""), "test", &.{value}))) {
        try @import("node_url.zig").install(engine);
        const exports = engine.native_module_values.get("node:url").?;
        return c.JS_DupValue(engine.context, try scope.call(try scope.get(exports, "fileURLToPath"), c.pi_js_undefined(), &.{value}));
    }
    return c.JS_DupValue(engine.context, value);
}
pub fn resolve(engine: *em.Engine, input: c.JSValue, supplied_base: c.JSValue, supplied_options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // Default parameter evaluation precedes normalization, even for an absolute
    // input. The actual Node resolver itself only falls back when necessary.
    const base = if (c.JS_IsUndefined(supplied_base)) try current(&scope) else supplied_base;
    const options = if (c.JS_IsUndefined(supplied_options)) try scope.object() else supplied_options;
    const normalized = try scope.own(try normalize(engine, input, options));
    const normalized_base = try scope.own(try normalize(engine, base, c.pi_js_undefined()));
    const result = if (scope.truthy(try node(&scope, "isAbsolute", &.{normalized}))) try node(&scope, "resolve", &.{normalized}) else try node(&scope, "resolve", &.{ normalized_base, normalized });
    return c.JS_DupValue(engine.context, result);
}
pub fn cwdRelative(engine: *em.Engine, file_path: c.JSValue, cwd: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const resolved_cwd = try scope.own(try resolve(engine, cwd, c.pi_js_undefined(), c.pi_js_undefined()));
    const resolved_path = try scope.own(try resolve(engine, file_path, resolved_cwd, c.pi_js_undefined()));
    const relative = try node(&scope, "relative", &.{ resolved_cwd, resolved_path });
    const empty = scope.equal(relative, try scope.text(""));
    if (empty) return sdk.text(engine, ".");
    if (scope.equal(relative, try scope.text(".."))) return c.pi_js_undefined();
    const exports = engine.native_module_values.get("node:path").?;
    if (scope.truthy(try scope.invoke(relative, "startsWith", &.{try scope.concat(try scope.text(".."), try scope.stringify(try scope.get(exports, "sep")))})) or scope.truthy(try node(&scope, "isAbsolute", &.{relative}))) return c.pi_js_undefined();
    return c.JS_DupValue(engine.context, relative);
}
pub fn display(engine: *em.Engine, file_path: c.JSValue, cwd: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const absolute = try scope.own(try resolve(engine, file_path, cwd, c.pi_js_undefined()));
    const relative = try scope.own(try cwdRelative(engine, absolute, cwd));
    const value = if (temporary.nullish(relative)) absolute else relative;
    const exports = engine.native_module_values.get("node:path").?;
    const result = try scope.invoke(try scope.invoke(value, "split", &.{try scope.get(exports, "sep")}), "join", &.{try scope.text("/")});
    return c.JS_DupValue(engine.context, result);
}
