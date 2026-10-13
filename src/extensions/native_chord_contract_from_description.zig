//! Source contractFromDescription: wire tokens retain their complete original description identity.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
pub fn fromDescription(engine: *h.Engine, bindings: c.JSValue, description: c.JSValue) !c.JSValue {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const name = try s.get(description, "name");
    const scope = try s.get(description, "scope");
    const version = try s.get(description, "version");
    const input = try s.get(description, "input");
    if (!c.JS_IsString(name) or (!try s.equal(scope, "remote") and !try s.equal(scope, "local")) or c.JS_ToBool(engine.context, try s.builtin("Number", "isInteger", &.{version})) == 0) return h.invalid(&s, bindings, "token", &.{try s.text("malformed contract token")});
    const result = try s.record();
    try h.field(&s, result, "name", name);
    try h.field(&s, result, "version", version);
    try h.field(&s, result, "input", input);
    try h.field(&s, result, "description", description);
    const canonical = @import("native_chord_canonical.zig");
    const encoded = try s.keep(try canonical.canonicalJson(engine, description));
    try h.field(&s, result, "fingerprint", try s.keep(try canonical.hash64(engine, encoded)));
    try h.field(&s, result, "scope", scope);
    const definition = try s.record();
    try h.field(&s, definition, "version", version);
    try h.field(&s, definition, "input", input);
    if (try s.equal(scope, "remote")) try h.field(&s, definition, "variants", try s.record());
    try h.field(&s, result, "def", definition);
    return s.result(result);
}
