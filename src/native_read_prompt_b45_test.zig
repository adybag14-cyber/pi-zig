//! Genuine b45 export rows. Prompt bindings below are fixture-only adapters to
//! the existing native algorithms, not production SDK exports or guest ports.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const js = @import("extensions/native_js_values.zig");
const prompts = @import("coding_agent/prompts.zig");
const range = @import("extensions/native_sdk_read_line_range.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;

fn adapter(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, magic, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn invoke(engine: *em.Engine, kind: c_int, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const text = try engine.toString(if (args.len > 0) args[0] else c.pi_js_undefined());
    defer engine.gpa.free(text);
    if (kind == 0) {
        const parsed = try prompts.parseCommandArgs(engine.gpa, text);
        defer prompts.freeCommandArgs(engine.gpa, parsed);
        const result = try scope.array();
        for (parsed, 0..) |value, index| try scope.index(result, @intCast(index), try scope.text(value));
        return c.JS_DupValue(engine.context, result);
    }
    const values = if (args.len > 1) args[1] else c.pi_js_undefined();
    const count = try sdk.length(engine, values);
    if (kind == 1) {
        const owned = try engine.gpa.alloc([]const u8, count);
        defer engine.gpa.free(owned);
        var initialized: usize = 0;
        defer for (owned[0..initialized]) |value| engine.gpa.free(value);
        for (owned, 0..) |*value, index| {
            value.* = try engine.toString(try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index)))));
            initialized += 1;
        }
        const result = try prompts.substituteArgs(engine.gpa, text, owned);
        defer engine.gpa.free(result);
        return sdk.text(engine, result);
    }
    const templates = try engine.gpa.alloc(prompts.PromptTemplate, count);
    defer engine.gpa.free(templates);
    var initialized: usize = 0;
    defer for (templates[0..initialized]) |template| {
        engine.gpa.free(template.name);
        engine.gpa.free(template.content);
    };
    for (templates, 0..) |*template, index| {
        const value = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index))));
        const name = try engine.toString(try scope.get(value, "name"));
        errdefer engine.gpa.free(name);
        const content = try engine.toString(try scope.get(value, "content"));
        template.* = .{ .name = name, .content = content, .path = "", .description = "" };
        initialized += 1;
    }
    const expanded = try prompts.expandInvocation(engine.gpa, text, templates);
    defer if (expanded) |result| engine.gpa.free(result);
    return sdk.text(engine, expanded orelse text);
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const api = try scope.object();
    try range.install(engine, api);
    inline for (.{ "parseCommandArgs", "substituteArgs", "expandPromptTemplate" }, 0..) |name, index| {
        try scope.put(api, name, try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, adapter, name, if (index == 0) 1 else 2, @intCast(index)))));
    }
    try scope.put(global, "readPromptAPI", api);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-read-prompt-b45.input.txt"), "read-prompt-b45-original54.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const actual = try engine.stringify(try scope.get(global, "sdkReadPromptRows"));
    defer gpa.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-read-prompt-b45.json");
    const parsed = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "read-prompt-b45-original54.json")));
    const expected = try engine.stringify(parsed);
    defer gpa.free(expected);
    if (!std.mem.eql(u8, actual, expected)) {
        std.debug.print("Actual b45 read/prompt54:\n{s}\nExpected:\n{s}\n", .{ actual, expected });
        return error.ReadPromptSourceMismatch;
    }
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "b45 read range and native prompts match genuine Original54 callbacks errors empty arguments and Unicode" {
    try exercise(std.testing.allocator);
}
test "b45 read range and native prompt Original54 release each full probe allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "read-prompt-b45", exercise, .{});
}
