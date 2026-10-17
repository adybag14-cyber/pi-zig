//! Prepared complete comparison; actual production exports and original bytes
//! must be supplied by a separately granted bootstrap/reference gate.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn compareActualSource(engine: *em.Engine, actual_exports: c.JSValue, reference_bytes: []const u8) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const observer = try s.own(try engine.evalModule(@embedFile("../verification/agent-loop-genuine-af-sourceonly-20261017/observer.mjs"), "actual-agent-loop-observer.mjs"));
    const pending = try s.call(try s.get(observer, "observeAgentLoop"), c.pi_js_undefined(), &.{actual_exports});
    const observed = try s.own(try engine.awaitValue(pending));
    const terminated = try engine.gpa.dupeZ(u8, reference_bytes); defer engine.gpa.free(terminated);
    const reference = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, reference_bytes.len, "original-agent-loop.json")));
    try std.testing.expect(s.equal(try s.get(reference, "authority"), try s.text("actual-Pi1.3-8efd-Agent-low-level")));
    try std.testing.expect(s.equal(try s.get(try s.get(reference, "rows"), "length"), c.JS_NewInt32(engine.context, 22)));
    const json = try s.global("JSON"); const stringify = try s.get(json, "stringify");
    try std.testing.expect(s.equal(try s.call(stringify, json, &.{reference}), try s.call(stringify, json, &.{observed})));
    inline for (.{ "runAgentLoop", "runAgentLoopContinue", "runToolCall" }) |name| {
        const function = try s.get(actual_exports, name);
        try std.testing.expect(c.JS_IsAsyncFunction(function));
        try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
    }
}
