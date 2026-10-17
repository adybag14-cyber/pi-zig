//! Node24.14 internal/tty.js; Sindre Sorhus MIT, retained authority/license.
//! Lexical color methods operate on WriteStream.prototype and detached calls.
//! Real env/OS inputs, actual VM regex/string/arithmetic, no inferred terminal.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const f = @import("native_node_module_callable.zig");
const h = @import("native_node_tty_values.zig");
const math = @import("native_image_arithmetic.zig");
pub const Primordials = struct {
    string_split: c.JSValue, string_lower: c.JSValue,
    regexp_exec: c.JSValue, regexp_constructor: c.JSValue,
    has_own: c.JSValue, number_is_integer: c.JSValue,
    pub fn deinit(self: Primordials, engine: *v.em.Engine) void {
        inline for (.{ "string_split", "string_lower", "regexp_exec", "regexp_constructor", "has_own", "number_is_integer" }) |name| engine.freeValue(@field(self, name));
    }
};
/// Bootstrap-only capture, before any guest module is admitted. A caller that
/// initializes tty lazily must retain this result from the pristine bootstrap;
/// recapturing modified globals at the first colors call is not admitted.
pub fn capturePrimordials(engine: *v.em.Engine) !Primordials {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const string = try h.get(&s, try s.own(try engine.checked(c.JS_GetGlobalObject(engine.context))), "String");
    const string_prototype = try h.get(&s, string, "prototype");
    const regexp = try s.own(try h.success(engine, try v.js.global(engine, "RegExp")));
    const regexp_prototype = try h.get(&s, regexp, "prototype");
    const object = try s.own(try h.success(engine, try v.js.global(engine, "Object")));
    const object_prototype = try h.get(&s, object, "prototype");
    const number_type = try s.own(try h.success(engine, try v.js.global(engine, "Number")));
    // All failing reads precede ownership duplication.
    const split = try h.get(&s, string_prototype, "split");
    const lower = try h.get(&s, string_prototype, "toLowerCase");
    const exec = try h.get(&s, regexp_prototype, "exec");
    const has_own = try h.get(&s, object_prototype, "hasOwnProperty");
    const integer = try h.get(&s, number_type, "isInteger");
    return .{ .string_split = c.JS_DupValue(engine.context, split), .string_lower = c.JS_DupValue(engine.context, lower), .regexp_exec = c.JS_DupValue(engine.context, exec), .regexp_constructor = c.JS_DupValue(engine.context, regexp), .has_own = c.JS_DupValue(engine.context, has_own), .number_is_integer = c.JS_DupValue(engine.context, integer) };
}
pub const Inputs = struct {
    /// Actual module require, called lazily with 'os'; not a fake release value.
    require: c.JSValue,
    /// Genuine internal/validators validateInteger, captured at module load.
    validate_integer: c.JSValue,
    /// Captured raw builtin methods, BEFORE guest global/prototype mutation.
    /// These receive the receiver through JS_Call (not pre-uncurried wrappers).
    string_split: c.JSValue,
    string_lower: c.JSValue,
    regexp_exec: c.JSValue,
    regexp_constructor: c.JSValue,
    has_own: c.JSValue,
};
/// Native implementation of the exact validateInteger used by hasColors.
/// Error constructors must be the actual captured internal/errors exports;
/// validation neither coerces count nor formats an approximate ordinary Error.
pub fn createValidator(engine: *v.em.Engine, number_is_integer: c.JSValue, invalid_arg_type: c.JSValue, out_of_range: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    inline for (.{ number_is_integer, invalid_arg_type, out_of_range }) |function| {
        if (!c.JS_IsFunction(engine.context, function)) return error.RequiredActualTtyIntegerValidatorDependency;
    }
    return f.create(engine, "validateInteger", 2, false, validateInteger, &.{ number_is_integer, invalid_arg_type, out_of_range });
}
fn validateInteger(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const value = h.arg(args, 0);
    const name = h.arg(args, 1);
    if (!c.JS_IsNumber(value)) return h.throwValue(engine, try h.construct(&s, roots[1], &.{ name, try s.text("number"), value }));
    if (!s.truthy(try h.call(&s, roots[0], c.pi_js_undefined(), &.{value}))) return h.throwValue(engine, try h.construct(&s, roots[2], &.{ name, try s.text("an integer"), value }));
    const minimum = if (c.JS_IsUndefined(h.arg(args, 2))) c.JS_NewFloat64(engine.context, -9007199254740991) else h.arg(args, 2);
    const maximum = if (c.JS_IsUndefined(h.arg(args, 3))) c.JS_NewFloat64(engine.context, 9007199254740991) else h.arg(args, 3);
    const below = try math.compare(engine, .less, value, minimum);
    try h.pending(engine);
    const above = if (below) false else try math.compare(engine, .greater, value, maximum);
    try h.pending(engine);
    if (below or above) {
        var range = try s.concat(try s.text(">= "), try s.stringify(minimum));
        try h.pending(engine);
        range = try s.concat(range, try s.text(" && <= "));
        range = try s.concat(range, try s.stringify(maximum));
        try h.pending(engine);
        return h.throwValue(engine, try h.construct(&s, roots[2], &.{ name, range, value }));
    }
    return c.pi_js_undefined();
}
pub const Exports = struct {
    get_color_depth: c.JSValue,
    has_colors: c.JSValue,
    pub fn deinit(self: Exports, engine: *v.em.Engine) void {
        engine.freeValue(self.get_color_depth);
        engine.freeValue(self.has_colors);
    }
};
// Private lexical object/TERM_ENVS never escape through a module property.
// Each ordinary callable traces these captures and charges native ownership.
const R = enum(usize) { lexical, require, validate, split, lower, exec, terms, regexes, teamcity, iterm, truecolor, xterm };
fn root(roots: []const c.JSValue, index: R) c.JSValue { return roots[@intFromEnum(index)]; }
fn regex(s: *v.Scope, constructor: c.JSValue, source: []const u8) !c.JSValue {
    return h.construct(s, constructor, &.{try s.text(source)});
}
/// The assembler retains one completed Exports for this Source module lifetime.
/// This does not register a placeholder module or publish missing dependencies.
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    inline for (.{ inputs.require, inputs.validate_integer, inputs.string_split, inputs.string_lower, inputs.regexp_exec, inputs.regexp_constructor, inputs.has_own }) |function| {
        if (!c.JS_IsFunction(engine.context, function)) return error.RequiredActualTtyColorDependency;
    }
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const lexical = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try h.put(engine, lexical, "OSRelease", c.pi_js_undefined());
    try h.put(engine, lexical, "warned", c.pi_js_bool(engine.context, 0));
    const terms = try s.object();
    // Deliberately an ordinary object: inherited keys are observable in Source.
    inline for (.{ .{ "eterm", 4 }, .{ "cons25", 4 }, .{ "console", 4 }, .{ "cygwin", 4 }, .{ "dtterm", 4 }, .{ "gnome", 4 }, .{ "hurd", 4 }, .{ "jfbterm", 4 }, .{ "konsole", 4 }, .{ "kterm", 4 }, .{ "mlterm", 4 }, .{ "mosh", 24 }, .{ "putty", 4 }, .{ "st", 4 }, .{ "rxvt-unicode-24bit", 24 }, .{ "terminator", 24 }, .{ "xterm-kitty", 24 } }) |entry| try h.put(engine, terms, entry[0], c.JS_NewInt32(engine.context, entry[1]));
    const regexes = try s.array();
    inline for (.{ "ansi", "color", "linux", "direct", "^con[0-9]*x[0-9]", "^rxvt", "^screen", "^xterm", "^vt100", "^vt220" }, 0..) |source, index| {
        try s.index(regexes, @intCast(index), try regex(&s, inputs.regexp_constructor, source));
    }
    const roots = [_]c.JSValue{ lexical, inputs.require, inputs.validate_integer, inputs.string_split, inputs.string_lower, inputs.regexp_exec, terms, regexes,
        try regex(&s, inputs.regexp_constructor, "^(9\\.(0*[1-9]\\d*)\\.|\\d{2,}\\.)"), try regex(&s, inputs.regexp_constructor, "^[0-2]\\."),
        try regex(&s, inputs.regexp_constructor, "truecolor"), try regex(&s, inputs.regexp_constructor, "^xterm-256"), inputs.has_own };
    const depth_function = try f.create(engine, "getColorDepth", 0, true, getColorDepth, &roots);
    errdefer engine.freeValue(depth_function);
    const colors_function = try f.create(engine, "hasColors", 2, true, hasColors, &roots);
    return .{ .get_color_depth = depth_function, .has_colors = colors_function };
}
fn process(s: *v.Scope) !c.JSValue { return s.own(try h.success(s.engine, try v.js.global(s.engine, "process"))); }
fn propertyIs(s: *v.Scope, object: c.JSValue, name: [*:0]const u8, text: []const u8) !bool { return h.same(s, try h.get(s, object, name), text); }
fn disabled(s: *v.Scope, env: c.JSValue, name: [*:0]const u8) !bool {
    // Preserve BOTH property evaluations and short circuit, including Proxies.
    return !c.JS_IsUndefined(try h.get(s, env, name)) and !try propertyIs(s, env, name, "");
}
fn warning(s: *v.Scope, env: c.JSValue, roots: []const c.JSValue) !void {
    if (s.truthy(try h.get(s, root(roots, .lexical), "warned"))) return;
    const node = try disabled(s, env, "NODE_DISABLE_COLORS");
    const no = try disabled(s, env, "NO_COLOR");
    if (!node and !no) return;
    const name = if (node and no) "NODE_DISABLE_COLORS' and 'NO_COLOR" else if (node) "NODE_DISABLE_COLORS" else "NO_COLOR";
    const owner = try process(s);
    const emit = try h.get(s, owner, "emitWarning");
    const bytes = try @import("std").fmt.allocPrint(s.engine.gpa, "The '{s}' env is ignored due to the 'FORCE_COLOR' env being set.", .{name});
    defer s.engine.gpa.free(bytes);
    _ = try h.call(s, emit, owner, &.{ try s.text(bytes), try s.text("Warning") });
    // A throwing/reentrant warning does not publish warned early.
    try h.put(s.engine, root(roots, .lexical), "warned", c.pi_js_bool(s.engine.context, 1));
}
fn matches(s: *v.Scope, roots: []const c.JSValue, pattern: c.JSValue, value: c.JSValue) !bool {
    return !c.JS_IsNull(try h.call(s, root(roots, .exec), pattern, &.{value}));
}
fn hasOwn(s: *v.Scope, roots: []const c.JSValue, env: c.JSValue, name: []const u8) !bool {
    return s.truthy(try h.call(s, roots[12], env, &.{try s.text(name)}));
}
fn number(s: *v.Scope, value: c.JSValue) !f64 {
    // JS_ToFloat64 implements unary-plus numeric conversion, rejecting BigInt.
    var result: f64 = 0;
    if (c.JS_ToFloat64(s.engine.context, &result, value) < 0) return v.js.capture(s.engine);
    try h.pending(s.engine);
    return result;
}
fn depth(s: *v.Scope, supplied_env: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const engine = s.engine;
    const env = if (c.JS_IsUndefined(supplied_env)) try h.get(s, try process(s), "env") else supplied_env;
    if (!c.JS_IsUndefined(try h.get(s, env, "FORCE_COLOR"))) {
        const force = try h.get(s, env, "FORCE_COLOR");
        const level: i32 = if (try h.same(s, force, "") or try h.same(s, force, "1") or try h.same(s, force, "true")) 4 else if (try h.same(s, force, "2")) 8 else if (try h.same(s, force, "3")) 24 else 1;
        if (level != 1) try warning(s, env, roots);
        return c.JS_NewInt32(engine.context, level);
    }
    if (try disabled(s, env, "NODE_DISABLE_COLORS") or try disabled(s, env, "NO_COLOR") or try propertyIs(s, env, "TERM", "dumb")) return c.JS_NewInt32(engine.context, 1);
    if (try propertyIs(s, try process(s), "platform", "win32")) {
        var release = try h.get(s, root(roots, .lexical), "OSRelease");
        if (c.JS_IsUndefined(release)) {
            const os = try h.call(s, root(roots, .require), c.pi_js_undefined(), &.{try s.text("os")});
            const release_function = try h.get(s, os, "release");
            const raw = try h.call(s, release_function, c.pi_js_undefined(), &.{});
            release = try h.call(s, root(roots, .split), raw, &.{ try s.text("."), c.JS_NewInt32(engine.context, 3) });
            try h.put(engine, root(roots, .lexical), "OSRelease", release);
        }
        const major = try s.own(try h.success(engine, try engine.checked(c.JS_GetPropertyUint32(engine.context, release, 0))));
        if (try number(s, major) >= 10) {
            const build = try number(s, try s.own(try h.success(engine, try engine.checked(c.JS_GetPropertyUint32(engine.context, release, 2)))));
            if (build >= 14931) return c.JS_NewInt32(engine.context, 24);
            if (build >= 10586) return c.JS_NewInt32(engine.context, 8);
        }
        return c.JS_NewInt32(engine.context, 4);
    }
    if (s.truthy(try h.get(s, env, "TMUX"))) return c.JS_NewInt32(engine.context, 24);
    if (try hasOwn(s, roots, env, "TF_BUILD") and try hasOwn(s, roots, env, "AGENT_NAME")) return c.JS_NewInt32(engine.context, 4);
    if (try hasOwn(s, roots, env, "CI")) {
        inline for (.{ .{ "APPVEYOR", 8 }, .{ "BUILDKITE", 8 }, .{ "CIRCLECI", 24 }, .{ "DRONE", 8 }, .{ "GITEA_ACTIONS", 24 }, .{ "GITHUB_ACTIONS", 24 }, .{ "GITLAB_CI", 8 }, .{ "TRAVIS", 8 } }) |entry| {
            if (try hasOwn(s, roots, env, entry[0])) return c.JS_NewInt32(engine.context, entry[1]);
        }
        return c.JS_NewInt32(engine.context, if (try propertyIs(s, env, "CI_NAME", "codeship")) 8 else 1);
    }
    if (try v.js.hasKey(engine, env, try s.text("TEAMCITY_VERSION"))) {
        try h.pending(engine);
        return c.JS_NewInt32(engine.context, if (try matches(s, roots, root(roots, .teamcity), try h.get(s, env, "TEAMCITY_VERSION"))) 4 else 1);
    }
    try h.pending(engine);
    const program = try h.get(s, env, "TERM_PROGRAM");
    if (try h.same(s, program, "iTerm.app")) {
        if (!s.truthy(try h.get(s, env, "TERM_PROGRAM_VERSION")) or try matches(s, roots, root(roots, .iterm), try h.get(s, env, "TERM_PROGRAM_VERSION"))) return c.JS_NewInt32(engine.context, 8);
        return c.JS_NewInt32(engine.context, 24);
    }
    if (try h.same(s, program, "HyperTerm") or try h.same(s, program, "MacTerm")) return c.JS_NewInt32(engine.context, 24);
    if (try h.same(s, program, "Apple_Terminal")) return c.JS_NewInt32(engine.context, 8);
    if (try propertyIs(s, env, "COLORTERM", "truecolor") or try propertyIs(s, env, "COLORTERM", "24bit")) return c.JS_NewInt32(engine.context, 24);
    if (s.truthy(try h.get(s, env, "TERM"))) {
        if (try matches(s, roots, root(roots, .truecolor), try h.get(s, env, "TERM"))) return c.JS_NewInt32(engine.context, 24);
        if (try matches(s, roots, root(roots, .xterm), try h.get(s, env, "TERM"))) return c.JS_NewInt32(engine.context, 8);
        const term = try h.call(s, root(roots, .lower), try h.get(s, env, "TERM"), &.{});
        const first = try s.own(try h.success(engine, try v.js.getKey(engine, root(roots, .terms), term)));
        if (s.truthy(first)) return h.success(engine, try v.js.getKey(engine, root(roots, .terms), term));
        for (0..10) |index| {
            const pattern = try s.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, root(roots, .regexes), @intCast(index))));
            if (try matches(s, roots, pattern, term)) return c.JS_NewInt32(engine.context, 4);
        }
    }
    return c.JS_NewInt32(engine.context, if (s.truthy(try h.get(s, env, "COLORTERM"))) 4 else 1);
}
fn getColorDepth(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    return depth(&s, h.arg(args, 0), roots);
}
fn hasColors(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var count = h.arg(args, 0);
    var env = h.arg(args, 1);
    // typeof function is NOT object. Null follows integer validation.
    if (c.JS_IsUndefined(env) and (c.JS_IsUndefined(count) or (c.JS_IsObject(count) and !c.JS_IsFunction(engine.context, count)))) {
        env = count; count = c.JS_NewInt32(engine.context, 16);
    } else {
        _ = try h.call(&s, root(roots, .validate), c.pi_js_undefined(), &.{ count, try s.text("count"), c.JS_NewInt32(engine.context, 2) });
    }
    const actual_depth = try s.own(try depth(&s, env, roots));
    const capacity = try h.binary(&s, .power, c.JS_NewInt32(engine.context, 2), actual_depth);
    try h.pending(engine);
    return h.success(engine, try math.binary(engine, .less_equal, count, capacity));
}
