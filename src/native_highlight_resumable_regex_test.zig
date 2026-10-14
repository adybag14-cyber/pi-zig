//! Genuine original ResumableMultiRegex replay; private compiler dependency qualification.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const multi = @import("extensions/native_highlight_resumable_regex.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;

fn makeCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return make(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0..2]) catch |err| sdk.fail(engine, err);
}
fn make(engine: *em.Engine, options: c.JSValue, constructors: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const insensitive = scope.truthy(try scope.get(options, "case_insensitive"));
    return engine.checked(c.JS_CallConstructor(engine.context, constructors[@intFromBool(insensitive)], 0, null));
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    var constructors: [2]c.JSValue = undefined;
    for (&constructors, 0..) |*constructor, index| {
        const language = try scope.object();
        try scope.put(language, "case_insensitive", c.pi_js_bool(engine.context, @intFromBool(index == 1)));
        constructor.* = try scope.own(try multi.constructor(engine, language));
    }
    const maker = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, makeCall, "makeResumableRegex", 1, 0, constructors.len, &constructors)));
    try scope.put(global, "makeResumableRegex", maker);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-highlight-resumable-regex-1692.input.txt"), "highlight-resumable-regex-original24.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const rows = try scope.get(global, "sdkResumableRegexRows");
    const raw = try engine.stringify(rows);
    defer gpa.free(raw);
    const expected_bytes = @embedFile("extensions/fixtures/sdk-highlight-resumable-regex-1692.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, expected_bytes, expected_bytes.len, "highlight-resumable-regex-original24.json")));
    const expected_raw = try engine.stringify(expected);
    defer gpa.free(expected_raw);
    if (!std.mem.eql(u8, raw, expected_raw)) {
        std.debug.print("Actual ResumableMultiRegex Source mismatch:\n{s}\nExpected:\n{s}\n", .{ raw, expected_raw });
        return error.ResumableMultiRegexSourceMismatch;
    }
    const released = engine.eval("globalThis.resumableWeak = new WeakRef(makeResumableRegex({}));delete globalThis.sdkResumableRegexRows;delete globalThis.makeResumableRegex;", "resumable-regex-release.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = engine.eval("resumableWeak.deref() === undefined", "resumable-regex-gc.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    defer engine.freeValue(collected);
    if (c.JS_ToBool(engine.context, collected) != 1) return error.ResumableMultiRegexOwnerRetained;
}
test "native ResumableMultiRegex matches genuine original24 cached resume fallback iterator close retained callbacks coercion and sentinel identity" {
    try exercise(std.testing.allocator);
}
test "native ResumableMultiRegex releases every full original probe allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "highlight-resumable-regex", exercise, .{});
}
