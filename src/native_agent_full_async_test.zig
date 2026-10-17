//! Prepared complete full-method observer and real AF internal-brand checks.
//! Actual Agent/bootstrap/reference supplied by its independently owned gate.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn compareActualSource(engine: *em.Engine, actual_agent: c.JSValue, reference_bytes: []const u8) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const observer = try s.own(try engine.evalModule(@embedFile("../verification/agent-full-methods-genuine-af-sourceonly-20261017/observer.mjs"), "actual-agent-full-method-observer.mjs"));
    const pending = try s.call(try s.get(observer, "observeAgentFullMethods"), c.pi_js_undefined(), &.{actual_agent});
    const observed = try s.own(try engine.awaitValue(pending));
    const terminated = try engine.gpa.dupeZ(u8, reference_bytes); defer engine.gpa.free(terminated);
    const reference = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, reference_bytes.len, "original-agent-full-methods.json")));
    try std.testing.expect(s.equal(try s.get(reference, "authority"), try s.text("actual-Pi1.3-8efd-Agent-all-methods")));
    try std.testing.expect(s.equal(try s.get(try s.get(reference, "rows"), "length"), c.JS_NewInt32(engine.context, 32)));
    const json = try s.global("JSON"); const stringify = try s.get(json, "stringify");
    try std.testing.expect(s.equal(try s.call(stringify, json, &.{reference}), try s.call(stringify, json, &.{observed})));
    const prototype = try s.get(actual_agent, "prototype");
    inline for (.{ "prompt", "continue", "runPromptMessages", "runContinuation", "runWithLifecycle", "handleRunFailure", "processEvents" }) |name| {
        const function = try s.get(prototype, name);
        try std.testing.expect(c.JS_IsAsyncFunction(function) != 0);
        try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
    }
}
