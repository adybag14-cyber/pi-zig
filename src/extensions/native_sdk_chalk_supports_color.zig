//! Private Chalk 6.0.0 supports-color stdout/stderr initialization.
//! MIT Sindre Sorhus. Source/provenance and license in verification/sdk-chalk6.
//! No public node:tty shim. Only real host descriptor 1/2 capability is read.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const Scope = @import("native_sdk_chalk_scope.zig").Scope;
const owned = @import("native_sdk_owned_completion.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const functions = @import("native_node_function.zig");
const c = em.c;
const Win = struct {
    extern "c" fn _get_osfhandle(c_int) isize;
    extern "kernel32" fn GetConsoleMode(std.os.windows.HANDLE, *u32) callconv(.winapi) c_int;
};
const Posix = struct { extern "c" fn isatty(c_int) c_int; };
fn terminal(fd: c_int) bool {
    if (builtin.os.tag == .windows) {
        const raw = Win._get_osfhandle(fd);
        if (raw == -1 or raw == -2 or raw == 0) return false;
        var mode: u32 = 0;
        return Win.GetConsoleMode(@ptrFromInt(@as(usize, @bitCast(raw))), &mode) != 0;
    }
    return Posix.isatty(fd) == 1;
}
fn key(s: *Scope, value: c.JSValue, name: []const u8) !c.JSValue { return s.getKey(value, try s.text(name)); }
fn has(s: *Scope, value: c.JSValue, name: []const u8) !bool { return s.hasKey(value, try s.text(name)); }
fn equal(s: *Scope, value: c.JSValue, text: []const u8) !bool { return s.equal(value, try s.text(text)); }
fn compare(s: *Scope, op: arithmetic.Operation, a: c.JSValue, b: c.JSValue) !bool { return s.compare(op, a, b); }
fn regex(s: *Scope, pattern: []const u8, flags: []const u8, input: c.JSValue) !bool {
    const args = [_]c.JSValue{ try s.text(pattern), try s.text(flags) };
    const expression = try s.construct(s.engine.intrinsic_regexp_constructor, &args);
    return s.truthy(try s.invoke(expression, "test", &.{input}));
}
fn hasFlag(s: *Scope, process: c.JSValue, comptime flag: []const u8) !bool {
    const deno = try s.get(try s.global("globalThis"), "Deno");
    const argv = if (s.truthy(deno)) try s.get(try s.get(try s.global("globalThis"), "Deno"), "args") else try s.get(process, "argv");
    const flag_text = try s.text(flag);
    const prefix = try s.text(if (s.truthy(try s.invoke(flag_text, "startsWith", &.{try s.text("-")}))) "" else if (flag.len == 1) "-" else "--");
    const position = try s.invoke(argv, "indexOf", &.{try s.concat(prefix, flag_text)});
    const end = try s.invoke(argv, "indexOf", &.{try s.text("--")});
    const minus = c.JS_NewInt32(s.engine.context, -1);
    return !s.equal(position, minus) and (s.equal(end, minus) or try compare(s, .less, position, end));
}
fn numeric(s: *Scope, env: c.JSValue) !bool { return regex(s, "^\\d+$", "", try s.get(env, "FORCE_COLOR")); }
fn envMembership(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, envMembershipBody(&s, args, roots));
}
fn envMembershipBody(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(s.engine.context, @intFromBool(try s.hasKey(roots[0], if (args.len == 0) c.pi_js_undefined() else args[0])));
}
fn someEnv(s: *Scope, env: c.JSValue, names: []const []const u8) !bool {
    const names_array = try s.array();
    for (names, 0..) |name, i| try s.index(names_array, @intCast(i), try s.text(name));
    // Preserve the source's live Array.prototype.some access/call. The arrow
    // captures the actual env and performs the VM's real `key in env` operation.
    const method = try s.get(names_array, "some");
    const predicate = try s.own(try functions.createArrow(s.engine, "", 1, envMembership, &.{env}));
    return s.truthy(try s.call(method, names_array, &.{predicate}));
}
fn envForce(s: *Scope, env: c.JSValue) !c.JSValue {
    if (!try has(s, env, "FORCE_COLOR")) return c.pi_js_undefined();
    if (try equal(s, try s.get(env, "FORCE_COLOR"), "false")) return c.JS_NewInt32(s.engine.context, 0);
    if (try equal(s, try s.get(env, "FORCE_COLOR"), "true") or s.equal(try s.get(try s.get(env, "FORCE_COLOR"), "length"), c.JS_NewInt32(s.engine.context, 0))) return c.JS_NewInt32(s.engine.context, 1);
    if (!try numeric(s, env)) return c.pi_js_undefined();
    // Source obtains Math.min before Number.parseInt and the final env getter.
    const math = try s.global("Math"); const min = try s.get(math, "min");
    const number = try s.global("Number"); const parse = try s.get(number, "parseInt");
    const parsed = try s.call(parse, number, &.{ try s.get(env, "FORCE_COLOR"), c.JS_NewInt32(s.engine.context, 10) });
    return s.call(min, math, &.{ parsed, c.JS_NewInt32(s.engine.context, 3) });
}
fn level(s: *Scope, process: c.JSValue, os: c.JSValue, env: c.JSValue, flag: *c.JSValue, tty: bool) !c.JSValue {
    const from_env = try envForce(s, env);
    if (!c.JS_IsUndefined(from_env)) flag.* = from_env;
    const force = flag.*;
    const zero = c.JS_NewInt32(s.engine.context, 0);
    if (s.equal(force, zero)) return zero;
    inline for (.{ "color=16m", "color=full", "color=truecolor" }) |name| if (try hasFlag(s, process, name)) return c.JS_NewInt32(s.engine.context, 3);
    if (try hasFlag(s, process, "color=256")) return c.JS_NewInt32(s.engine.context, 2);
    if (!c.JS_IsUndefined(force) and try numeric(s, env)) return force;
    if (try has(s, env, "TF_BUILD") and try has(s, env, "AGENT_NAME")) return c.JS_NewInt32(s.engine.context, 1);
    if (!tty and c.JS_IsUndefined(force)) return zero;
    const minimum = if (s.truthy(force)) force else zero;
    if (try equal(s, try s.get(env, "TERM"), "dumb")) return minimum;
    if (try equal(s, try s.get(process, "platform"), "win32")) {
        const release = try s.invoke(try s.invoke(os, "release", &.{}), "split", &.{try s.text(".")});
        const major = try s.call(try s.global("Number"), c.pi_js_undefined(), &.{try key(s, release, "0")});
        if (try compare(s, .greater_equal, major, c.JS_NewInt32(s.engine.context, 10))) {
            const build = try s.call(try s.global("Number"), c.pi_js_undefined(), &.{try key(s, release, "2")});
            if (try compare(s, .greater_equal, build, c.JS_NewInt32(s.engine.context, 10586))) {
                const again = try s.call(try s.global("Number"), c.pi_js_undefined(), &.{try key(s, release, "2")});
                return c.JS_NewInt32(s.engine.context, if (try compare(s, .greater_equal, again, c.JS_NewInt32(s.engine.context, 14931))) 3 else 2);
            }
        }
        return c.JS_NewInt32(s.engine.context, 1);
    }
    if (try has(s, env, "CI")) {
        if (try someEnv(s, env, &.{ "GITHUB_ACTIONS", "GITEA_ACTIONS", "CIRCLECI" })) return c.JS_NewInt32(s.engine.context, 3);
        if (try someEnv(s, env, &.{ "TRAVIS", "APPVEYOR", "GITLAB_CI", "BUILDKITE", "DRONE" }) or try equal(s, try s.get(env, "CI_NAME"), "codeship")) return c.JS_NewInt32(s.engine.context, 1);
        return minimum;
    }
    if (try has(s, env, "TEAMCITY_VERSION")) return c.JS_NewInt32(s.engine.context, if (try regex(s, "^(?:9\\.0*[1-9]\\d*\\.|\\d{2,}\\.)", "", try s.get(env, "TEAMCITY_VERSION"))) 1 else 0);
    if (try equal(s, try s.get(env, "COLORTERM"), "truecolor")) return c.JS_NewInt32(s.engine.context, 3);
    inline for (.{ "xterm-kitty", "xterm-ghostty", "wezterm" }) |name| if (try equal(s, try s.get(env, "TERM"), name)) return c.JS_NewInt32(s.engine.context, 3);
    if (try has(s, env, "TERM_PROGRAM")) {
        const number = try s.global("Number"); const parse = try s.get(number, "parseInt");
        const version_text = try s.get(env, "TERM_PROGRAM_VERSION");
        const pieces = try s.invoke(if (s.truthy(version_text)) version_text else try s.text(""), "split", &.{ try s.text("."), c.JS_NewInt32(s.engine.context, 1) });
        const version = try s.call(parse, number, &.{ try key(s, pieces, "0"), c.JS_NewInt32(s.engine.context, 10) });
        const program = try s.get(env, "TERM_PROGRAM");
        if (try equal(s, program, "iTerm.app")) return c.JS_NewInt32(s.engine.context, if (try compare(s, .greater_equal, version, c.JS_NewInt32(s.engine.context, 3))) 3 else 2);
        if (try equal(s, program, "Apple_Terminal")) return c.JS_NewInt32(s.engine.context, 2);
    }
    if (try regex(s, "-256(?:color)?$", "i", try s.get(env, "TERM"))) return c.JS_NewInt32(s.engine.context, 2);
    if (try regex(s, "^screen|^xterm|^vt100|^vt220|^rxvt|color|ansi|cygwin|linux", "i", try s.get(env, "TERM"))) return c.JS_NewInt32(s.engine.context, 1);
    if (try has(s, env, "COLORTERM")) return c.JS_NewInt32(s.engine.context, 1);
    return minimum;
}
fn translate(s: *Scope, value: c.JSValue) !c.JSValue {
    if (s.equal(value, c.JS_NewInt32(s.engine.context, 0))) return c.pi_js_bool(s.engine.context, 0);
    const result = try s.object(); try s.put(result, "level", value); try s.put(result, "hasBasic", c.pi_js_bool(s.engine.context, 1));
    try s.put(result, "has256", c.pi_js_bool(s.engine.context, @intFromBool(try compare(s, .greater_equal, value, c.JS_NewInt32(s.engine.context, 2)))));
    try s.put(result, "has16m", c.pi_js_bool(s.engine.context, @intFromBool(try compare(s, .greater_equal, value, c.JS_NewInt32(s.engine.context, 3)))));
    return result;
}
pub fn create(engine: *em.Engine, process: c.JSValue, os: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, createBody(&s, process, os));
}
fn createBody(s: *Scope, process: c.JSValue, os: c.JSValue) !c.JSValue {
    const engine = s.engine;
    const env = try s.get(process, "env");
    var force = c.pi_js_undefined();
    inline for (.{ "no-color", "no-colors", "color=false", "color=never" }) |name| if (c.JS_IsUndefined(force) and try hasFlag(s, process, name)) { force = c.JS_NewInt32(engine.context, 0); };
    if (c.JS_IsUndefined(force)) inline for (.{ "color", "colors", "color=true", "color=always" }) |name| if (c.JS_IsUndefined(force) and try hasFlag(s, process, name)) { force = c.JS_NewInt32(engine.context, 1); };
    const result = try s.object();
    try s.put(result, "stdout", try translate(s, try level(s, process, os, env, &force, terminal(1))));
    try s.put(result, "stderr", try translate(s, try level(s, process, os, env, &force, terminal(2))));
    return c.JS_DupValue(engine.context, result);
}
