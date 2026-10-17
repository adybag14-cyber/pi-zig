//! Prepared full Source routing observer over the real native Agent constructor.
//! The observer is guest fixture code, never the implementation under test.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn compareActualSource(engine: *em.Engine, actual_agent: c.JSValue, original_reference: []const u8) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const observer = try s.own(try engine.evalModule(@embedFile("../verification/agent-routing-genuine-af-sourceonly-20261017/observer.mjs"), "actual-agent-routing-observer.mjs"));
    const pending = try s.call(try s.get(observer, "observeAgentRouting"), c.pi_js_undefined(), &.{actual_agent});
    const result = try s.own(try engine.awaitValue(pending));
    const terminated_reference = try engine.gpa.dupeZ(u8, original_reference);
    defer engine.gpa.free(terminated_reference);
    const reference = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, terminated_reference.ptr, original_reference.len, "original-agent-routing.json")));
    try std.testing.expect(s.equal(try s.get(reference, "authority"), try s.text("actual-Pi1.3-8efd-Agent-routing")));
    try std.testing.expect(s.equal(try s.get(try s.get(reference, "rows"), "length"), c.JS_NewInt32(engine.context, 15)));
    const json = try s.global("JSON"); const stringify = try s.get(json, "stringify");
    const expected = try s.call(stringify, json, &.{reference});
    const observed = try s.call(stringify, json, &.{result});
    try std.testing.expect(s.equal(expected, observed));
    const prototype = try s.get(actual_agent, "prototype");
    inline for (.{ "prompt", "continue" }) |name| {
        const function = try s.get(prototype, name);
        try std.testing.expect(c.JS_IsAsyncFunction(function));
        try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
    }
}
