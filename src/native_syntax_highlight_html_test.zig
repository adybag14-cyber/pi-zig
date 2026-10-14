const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const html = @import("extensions/native_syntax_highlight_html.zig");
const c = em.c;

fn argument(argc: c_int, argv: [*c]c.JSValue, position: usize) c.JSValue {
    return if (position < @as(usize, @intCast(argc))) argv[position] else c.pi_js_undefined();
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const result = switch (magic) {
        0 => html.renderHtml(engine, argument(argc, argv, 0), argument(argc, argv, 1)),
        1 => html.decodeEntity(engine, argument(argc, argv, 0)),
        2 => html.decodeEntityAt(engine, argument(argc, argv, 0), argument(argc, argv, 1)),
        else => unreachable,
    };
    return result catch |err| sdk.fail(engine, err);
}
fn setup(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const api = try sdk.object(engine);
    defer engine.freeValue(api);
    inline for (.{ "renderHighlightedHtml", "decodeHtmlEntity", "decodeHtmlEntityAt" }, 0..) |name, magic| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, callback, name, if (magic == 2) 2 else 1, @intCast(magic)));
        try sdk.put(engine, api, name, function);
    }
    try sdk.put(engine, global, "syntaxHTMLAPI", c.JS_DupValue(engine.context, api));
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    setup(engine) catch |err| return engine.nativeAllocationError(err, generation);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-syntax-html-1692.input.txt"), "syntax-html-original62.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const rows = try sdk.get(engine, global, "sdkSyntaxHtmlRows");
    defer engine.freeValue(rows);
    const raw = try engine.stringify(rows);
    defer gpa.free(raw);
    const expected_bytes = @embedFile("extensions/fixtures/sdk-syntax-html-1692.json");
    const expected = try engine.checked(c.JS_ParseJSON(engine.context, expected_bytes, expected_bytes.len, "syntax-html-original62.json"));
    defer engine.freeValue(expected);
    const expected_raw = try engine.stringify(expected);
    defer gpa.free(expected_raw);
    if (!std.mem.eql(u8, raw, expected_raw)) {
        std.debug.print("Actual syntax HTML Source mismatch:\n{s}\nExpected:\n{s}\n", .{ raw, expected_raw });
        return error.SyntaxHtmlSourceMismatch;
    }
    const released = try engine.eval("delete globalThis.sdkSyntaxHtmlRows;delete globalThis.syntaxHTMLAPI;", "syntax-html-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}

test "native syntax HTML matches full original62 nested spans entities callbacks metadata coercion and errors" {
    try exercise(std.testing.allocator);
}
test "native syntax HTML releases every original full-probe allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "syntax-html", exercise, .{});
}
