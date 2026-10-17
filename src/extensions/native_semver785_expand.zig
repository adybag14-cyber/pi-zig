//! Default (loose=false, includePrerelease=false)7.8.5 replacement callbacks.
const em = @import("engine.zig");
const Scope = @import("native_semver785_scope.zig").Scope;
const v = @import("native_semver785_version.zig");
const functions = @import("native_node_function.zig");
const c = em.c;
pub const Kind = enum { caret, tilde, xrange, hyphen };
pub fn callback(engine: *em.Engine, comptime kind: Kind) !c.JSValue {
    const Adapter = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var scope: Scope = .{ .engine = host };
            defer scope.deinit();
    errdefer |err| scope.failed(err);
            const result = try switch (kind) {
                .caret => caret(&scope, args),
                .tilde => tilde(&scope, args),
                .xrange => xrange(&scope, args),
                .hyphen => hyphen(&scope, args),
            };
            return scope.finish(c.JS_DupValue(host.context, result));
        }
    };
    // Original replacement callbacks have these actual formal arities.
    return functions.createArrow(engine, "", if (kind == .hyphen) 12 else if (kind == .xrange) 6 else 5, Adapter.call, &.{});
}
fn arg(args: []const c.JSValue, position: usize) c.JSValue {
    return if (position < args.len) args[position] else c.pi_js_undefined();
}
fn isX(scope: *Scope, value: c.JSValue) !bool {
    return !scope.truthy(value) or scope.equal(try scope.invoke(value, "toLowerCase", &.{}), try scope.text("x")) or scope.equal(value, try scope.text("*"));
}
fn increment(scope: *Scope, value: c.JSValue) !c.JSValue {
    const number = try scope.number(value);
    return scope.binary(.add, number, c.JS_NewInt32(scope.engine.context, 1));
}
fn tilde(scope: *Scope, args: []const c.JSValue) !c.JSValue {
    const major = arg(args, 1);
    const minor = arg(args, 2);
    const patch = arg(args, 3);
    const pre = arg(args, 4);
    if (try isX(scope, major)) return scope.text("");
    if (try isX(scope, minor)) return v.join(scope, &.{ try scope.text(">="), major, try scope.text(".0.0 <"), try increment(scope, major), try scope.text(".0.0-0") });
    if (try isX(scope, patch)) return v.join(scope, &.{ try scope.text(">="), major, try scope.text("."), minor, try scope.text(".0 <"), major, try scope.text("."), try increment(scope, minor), try scope.text(".0-0") });
    const lower = try v.join(scope, &.{ try scope.text(">="), major, try scope.text("."), minor, try scope.text("."), patch });
    const qualified = if (scope.truthy(pre)) try v.join(scope, &.{ lower, try scope.text("-"), pre }) else lower;
    return v.join(scope, &.{ qualified, try scope.text(" <"), major, try scope.text("."), try increment(scope, minor), try scope.text(".0-0") });
}
fn caret(scope: *Scope, args: []const c.JSValue) !c.JSValue {
    const major = arg(args, 1);
    const minor = arg(args, 2);
    const patch = arg(args, 3);
    const pre = arg(args, 4);
    if (try isX(scope, major)) return scope.text("");
    if (try isX(scope, minor)) return v.join(scope, &.{ try scope.text(">="), major, try scope.text(".0.0 <"), try increment(scope, major), try scope.text(".0.0-0") });
    if (try isX(scope, patch)) {
        if (scope.equal(major, try scope.text("0"))) return v.join(scope, &.{ try scope.text(">="), major, try scope.text("."), minor, try scope.text(".0 <"), major, try scope.text("."), try increment(scope, minor), try scope.text(".0-0") });
        return v.join(scope, &.{ try scope.text(">="), major, try scope.text("."), minor, try scope.text(".0 <"), try increment(scope, major), try scope.text(".0.0-0") });
    }
    const lower = try v.join(scope, &.{ try scope.text(">="), major, try scope.text("."), minor, try scope.text("."), patch });
    const qualified = if (scope.truthy(pre)) try v.join(scope, &.{ lower, try scope.text("-"), pre }) else lower;
    if (scope.equal(major, try scope.text("0"))) {
        if (scope.equal(minor, try scope.text("0"))) return v.join(scope, &.{ qualified, try scope.text(" <"), major, try scope.text("."), minor, try scope.text("."), try increment(scope, patch), try scope.text("-0") });
        return v.join(scope, &.{ qualified, try scope.text(" <"), major, try scope.text("."), try increment(scope, minor), try scope.text(".0-0") });
    }
    return v.join(scope, &.{ qualified, try scope.text(" <"), try increment(scope, major), try scope.text(".0.0-0") });
}
fn xrange(scope: *Scope, args: []const c.JSValue) !c.JSValue {
    const original = arg(args, 0);
    var operator = arg(args, 1);
    var major = arg(args, 2);
    var minor = arg(args, 3);
    var patch = arg(args, 4);
    // This rejection is intentionally only in replaceXRange, not caret/tilde.
    if ((try isX(scope, major) and !try isX(scope, minor)) or (try isX(scope, minor) and scope.truthy(patch) and !try isX(scope, patch))) return original;
    const major_x = try isX(scope, major);
    const minor_x = major_x or try isX(scope, minor);
    const patch_x = minor_x or try isX(scope, patch);
    if (scope.equal(operator, try scope.text("=")) and patch_x) operator = try scope.text("");
    if (major_x) return scope.text(if (scope.equal(operator, try scope.text(">")) or scope.equal(operator, try scope.text("<"))) "<0.0.0-0" else "*");
    if (scope.truthy(operator) and patch_x) {
        if (minor_x) minor = c.JS_NewInt32(scope.engine.context, 0);
        patch = c.JS_NewInt32(scope.engine.context, 0);
        if (scope.equal(operator, try scope.text(">"))) {
            operator = try scope.text(">=");
            if (minor_x) {
                major = try increment(scope, major);
                minor = c.JS_NewInt32(scope.engine.context, 0);
            } else minor = try increment(scope, minor);
        } else if (scope.equal(operator, try scope.text("<="))) {
            operator = try scope.text("<");
            if (minor_x) major = try increment(scope, major) else minor = try increment(scope, minor);
        }
        return v.join(scope, &.{ operator, major, try scope.text("."), minor, try scope.text("."), patch, try scope.text(if (scope.equal(operator, try scope.text("<"))) "-0" else "") });
    }
    if (minor_x) return v.join(scope, &.{ try scope.text(">="), major, try scope.text(".0.0 <"), try increment(scope, major), try scope.text(".0.0-0") });
    if (patch_x) return v.join(scope, &.{ try scope.text(">="), major, try scope.text("."), minor, try scope.text(".0 <"), major, try scope.text("."), try increment(scope, minor), try scope.text(".0-0") });
    return original;
}
fn hyphen(scope: *Scope, args: []const c.JSValue) !c.JSValue {
    var from = arg(args, 1);
    const from_major = arg(args, 2);
    const from_minor = arg(args, 3);
    const from_patch = arg(args, 4);
    const from_pre = arg(args, 5);
    var to = arg(args, 7);
    const to_major = arg(args, 8);
    const to_minor = arg(args, 9);
    const to_patch = arg(args, 10);
    const to_pre = arg(args, 11);
    if (try isX(scope, from_major)) from = try scope.text("") else if (try isX(scope, from_minor)) {
        from = try v.join(scope, &.{ try scope.text(">="), from_major, try scope.text(".0.0") });
    } else if (try isX(scope, from_patch)) {
        from = try v.join(scope, &.{ try scope.text(">="), from_major, try scope.text("."), from_minor, try scope.text(".0") });
    } else if (scope.truthy(from_pre)) {
        from = try v.join(scope, &.{ try scope.text(">="), from });
    } else from = try v.join(scope, &.{ try scope.text(">="), from });
    if (try isX(scope, to_major)) to = try scope.text("") else if (try isX(scope, to_minor)) {
        to = try v.join(scope, &.{ try scope.text("<"), try increment(scope, to_major), try scope.text(".0.0-0") });
    } else if (try isX(scope, to_patch)) {
        to = try v.join(scope, &.{ try scope.text("<"), to_major, try scope.text("."), try increment(scope, to_minor), try scope.text(".0-0") });
    } else if (scope.truthy(to_pre)) {
        to = try v.join(scope, &.{ try scope.text("<="), to_major, try scope.text("."), to_minor, try scope.text("."), to_patch, try scope.text("-"), to_pre });
    } else to = try v.join(scope, &.{ try scope.text("<="), to });
    return scope.invoke(try v.join(scope, &.{ from, try scope.text(" "), to }), "trim", &.{});
}
