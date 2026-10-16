//! Shared native value operations for the actual pinned host template bodies.
pub const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const f = @import("native_node_function.zig");
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn identity(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.JS_DupValue(engine.context, arg(args, 0)); }
pub fn join(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const args = try s.array(); for (values, 0..) |value, i| try s.index(args, @intCast(i), value);
    const all = try s.invoke(args, "every", &.{try s.own(try f.createArrow(s.engine, "", 1, identity, &.{}))}); return if (s.truthy(all)) s.invoke(args, "join", &.{try s.text("")}) else s.text("");
}
pub fn encode(s: *Scope, value: c.JSValue) !c.JSValue { return if (s.truthy(value)) s.call(try s.global("encodeURIComponent"), c.pi_js_undefined(), &.{value}) else s.text(""); }
fn replace(s: *Scope, value: c.JSValue, pattern: []const u8, replacement: []const u8) !c.JSValue {
    const method = try s.get(value, "replace"); var args = [_]c.JSValue{ try s.text(pattern), try s.text("g") }; const regex = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, 2, &args))); return s.call(method, value, &.{ regex, try s.text(replacement) });
}
pub fn format(s: *Scope, value: c.JSValue) !c.JSValue {
    var result = try s.invoke(value, "toLowerCase", &.{}); result = try replace(s, result, "^\\W+", ""); result = try replace(s, result, "(?<!\\W)\\W+$", ""); result = try replace(s, result, "/", ""); return replace(s, result, "\\W+", "-");
}
pub fn hash(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { var s: Scope = .{ .engine = engine }; defer s.deinit(); return c.JS_DupValue(engine.context, try format(&s, arg(args, 0))); }
pub fn gistHash(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { var s: Scope = .{ .engine = engine }; defer s.deinit(); const fragment = arg(args, 0); return c.JS_DupValue(engine.context, if (s.truthy(fragment)) try s.concat(try s.text("file-"), try format(&s, fragment)) else fragment); }
pub fn noBugs(_: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_null(); }
pub fn parts(s: *Scope, values: c.JSValue, length: u32) !c.JSValue { const result = try s.array(); var iterator = try v.iterator(s, values); defer iterator.deinit(); errdefer iterator.closePreserving(); var i: u32 = 0; while (i < length) : (i += 1) { const value = if (try iterator.next()) |item| try s.own(item) else c.pi_js_undefined(); try s.index(result, i, value); } try iterator.close(); return result; }
