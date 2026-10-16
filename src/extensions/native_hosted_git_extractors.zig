//! Actual raw hosts.js extract arrows, before from-url's URI decoding.
const data = @import("native_sdk_package_data.zig");
const h = @import("native_hosted_git_template_values.zig");
const v = h.v; const c = v.c; const Scope = v.Scope;
fn eq(s: *Scope, value: c.JSValue, name: []const u8) !bool { return v.eq(s, value, name); }
fn strip(s: *Scope, project: c.JSValue) !c.JSValue { return if (s.truthy(try s.invoke(project, "endsWith", &.{try s.text(".git")}))) s.invoke(project, "slice", &.{ c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, -4) }) else project; }
fn result(s: *Scope, user: c.JSValue, project: c.JSValue, ref: c.JSValue) !c.JSValue { const value = try s.object(); try data.put(s.engine, value, "user", user); try data.put(s.engine, value, "project", project); try data.put(s.engine, value, "committish", ref); return value; }
fn hash(s: *Scope, url: c.JSValue) !c.JSValue { return s.invoke(try s.get(url, "hash"), "slice", &.{c.JS_NewInt32(s.engine.context, 1)}); }
pub fn extract(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const url = h.arg(args, 0); var kind: i32 = 0; if (c.JS_ToInt32(engine.context, &kind, roots[0]) < 0) return v.js.capture(engine);
    var user = c.pi_js_undefined(); var project = c.pi_js_undefined(); var ref = c.pi_js_undefined();
    if (kind == 2) {
        const path = try s.invoke(try s.get(url, "pathname"), "slice", &.{c.JS_NewInt32(engine.context, 1)});
        if (s.truthy(try s.invoke(path, "includes", &.{try s.text("/-/")})) or s.truthy(try s.invoke(path, "includes", &.{try s.text("/archive.tar.gz")}))) return c.pi_js_undefined();
        const segments = try s.invoke(path, "split", &.{try s.text("/")}); project = try strip(&s, try s.invoke(segments, "pop", &.{})); user = try s.invoke(segments, "join", &.{try s.text("/")}); if (!s.truthy(user) or !s.truthy(project)) return c.pi_js_undefined(); ref = try hash(&s, url);
    } else {
        const length: u32 = if (kind == 0) 5 else 4; const segments = try h.parts(&s, try s.invoke(try s.get(url, "pathname"), "split", &.{ try s.text("/"), c.JS_NewInt32(engine.context, @intCast(length)) }), length); user = try v.at(&s, segments, 1); project = try v.at(&s, segments, 2); const aux = try v.at(&s, segments, 3);
        if (kind == 0) { ref = try v.at(&s, segments, 4); if (s.truthy(aux) and !try eq(&s, aux, "tree")) return c.pi_js_undefined(); if (!s.truthy(aux)) ref = try hash(&s, url); }
        if (kind == 1 or kind == 4) { const rejected = try s.array(); try s.index(rejected, 0, try s.text(if (kind == 1) "get" else "archive")); if (s.truthy(try s.invoke(rejected, "includes", &.{aux}))) return c.pi_js_undefined(); }
        if (kind == 3) { if (try eq(&s, aux, "raw")) return c.pi_js_undefined(); if (!s.truthy(project)) { if (!s.truthy(user)) return c.pi_js_undefined(); project = user; user = c.pi_js_null(); } project = try strip(&s, project); }
        else { if (s.truthy(project)) project = try strip(&s, project); if (!s.truthy(user) or !s.truthy(project)) return c.pi_js_undefined(); }
        if (kind != 0) ref = try hash(&s, url);
    }
    return c.JS_DupValue(engine.context, try result(&s, user, project, ref));
}
