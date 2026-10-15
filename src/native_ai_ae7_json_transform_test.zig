const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
fn transform(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return @import("extensions/native_ai_transform_messages.zig").transform(engine, argument(args, 0), argument(args, 1), argument(args, 2));
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
test "native ae7 JSON39 and thinking DROP12 match fresh genuine Source51 complete records" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "aiJSONAPI", try @import("extensions/native_ai_json_parse.zig").create(engine));
    try sdk.put(engine, global, "nativeTransform", try @import("extensions/native_node_function.zig").create(engine, "transformMessages", 3, transform, &.{}));
    const original = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("extensions/fixtures/ai-json39-transform12-ae7-source51.json"), .{});
    defer original.deinit();
    const sections = original.value.object.get("sections").?.array.items;
    try std.testing.expectEqual(@as(usize, 3), sections.len);
    inline for (.{ "parse", "delegate", "thinking" }, 0..) |section, index| {
        const input = if (index == 2) @embedFile("extensions/fixtures/ai-transform-thinking-ae7-source51.input.txt") else @embedFile("extensions/fixtures/ai-json-" ++ section ++ "-ae7-source51.input.txt");
        const module = engine.evalModule(input, "ae7-source51-" ++ section ++ ".mjs") catch |err| {
            std.debug.print("ae7 Source51 {s}: {s}\n", .{ section, engine.last_error orelse "no diagnostic" });
            return err;
        };
        defer engine.freeValue(module);
        const rows = try js.get(engine, module, "default");
        defer engine.freeValue(rows);
        const actual = try engine.stringify(rows);
        defer engine.gpa.free(actual);
        const expected = try std.json.Stringify.valueAlloc(std.testing.allocator, sections[index].object.get("rows").?, .{});
        defer std.testing.allocator.free(expected);
        try std.testing.expectEqualStrings(expected, actual);
    }
    c.JS_RunGC(engine.runtime);
}
