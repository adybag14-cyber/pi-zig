//! c268154 chord/sqlite/schema.ts. Original Pi MIT authority is retained.
const v = @import("native_ai_provider_values.zig");
const q = @import("native_chord_sqlite_values.zig");
const c = v.c;
pub fn create(engine: *v.em.Engine) !c.JSValue {
    try q.pending(engine);
    return @import("native_node_module_callable.zig").create(engine, "validateSqliteSchemaPrefix", 1, true, validate, &.{});
}
fn validate(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var captures = q.Captures.enter(engine); defer captures.deinit();
    try q.pending(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const prefix = q.arg(args, 0);
    // A fresh real RegExp literal instance on EACH Source call, with the
    // intrinsic constructor rather than the guest-replaceable global binding.
    var regexp_args = [_]c.JSValue{try s.text("^[A-Za-z_][A-Za-z0-9_]*$")};
    const regex = try s.own(try q.success(engine, try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, regexp_args.len, &regexp_args))));
    if (!s.truthy(try q.invoke(&s, regex, "test", &.{prefix}))) {
        const error_ctor = try s.own(try q.success(engine, try v.js.global(engine, "Error")));
        const json = try s.own(try q.success(engine, try v.js.global(engine, "JSON")));
        const message = try q.binary(&s, 0, try s.text("Invalid SQLite schema prefix "), try q.text(&s, try q.invoke(&s, json, "stringify", &.{prefix})));
        var constructor_args = [_]c.JSValue{message};
        const reason = try s.own(try q.success(engine, try engine.checked(c.JS_CallConstructor(engine.context, error_ctor, 1, &constructor_args))));
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        unreachable;
    }
    const lowered = try q.invoke(&s, prefix, "toLowerCase", &.{});
    if (s.truthy(try q.invoke(&s, lowered, "startsWith", &.{try s.text("sqlite_")}))) {
        const error_ctor = try s.own(try q.success(engine, try v.js.global(engine, "Error")));
        const json = try s.own(try q.success(engine, try v.js.global(engine, "JSON")));
        const head = try q.binary(&s, 0, try s.text("SQLite schema prefix "), try q.text(&s, try q.invoke(&s, json, "stringify", &.{prefix})));
        const message = try q.binary(&s, 0, head, try s.text(" is reserved"));
        var constructor_args = [_]c.JSValue{message};
        const reason = try s.own(try q.success(engine, try engine.checked(c.JS_CallConstructor(engine.context, error_ctor, 1, &constructor_args))));
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        unreachable;
    }
    return c.pi_js_undefined();
}
