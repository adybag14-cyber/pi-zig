const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = js.c;
test "native Env stream foundation actual compiled inventory" {
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |function, *name| name.* = function.name;
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(text);
    std.debug.print("\nENV_STREAM_FOUNDATION_TEST_INVENTORY={s}\n", .{text});
}
fn consume(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return consumeValue(&scope, data[0], args) catch |err| @import("extensions/native_durable.zig").reject(engine, err);
}
fn consumeValue(scope: *Scope, bindings: c.JSValue, args: []const c.JSValue) !c.JSValue {
    if (args.len != 3 or !c.JS_IsNumber(args[0])) return error.InvalidStreamFoundationFixture;
    var count: f64 = undefined;
    if (c.JS_ToFloat64(scope.engine.context, &count, args[0]) < 0) return js.capture(scope.engine);
    if (!std.math.isFinite(count) or count < 0 or count > std.math.maxInt(u32) or @trunc(count) != count) return error.InvalidStreamFoundationFixture;
    const bits: u32 = if (scope.equal(args[2], try scope.text("object"))) 1 else if (scope.equal(args[2], try scope.text("string"))) 1 << 21 else 0;
    try js.setKey(scope.engine, args[1], try scope.get(bindings, "streamStateSymbol"), c.JS_NewUint32(scope.engine.context, bits));
    return c.JS_DupValue(scope.engine.context, try @import("extensions/native_node_readable_buffer.zig").fromList(scope, bindings, @intFromFloat(count), args[1]));
}
fn install(engine: *em.Engine) !void {
    try @import("extensions/node_buffer.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.object();
    try scope.put(bindings, "streamStateSymbol", try scope.own(try engine.checked(c.JS_NewSymbol(engine.context, "kState", false))));
    try scope.put(bindings, "streamBuffer", try scope.global("Buffer"));
    const typed_prototype = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, try scope.get(try scope.global("Uint8Array"), "prototype"))));
    try scope.put(bindings, "streamTypedArraySet", try scope.get(typed_prototype, "set"));
    var data = [_]c.JSValue{bindings};
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, consume, "consume", 3, 0, data.len, &data)));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "consume", function);
}
fn replay(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    try install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const source = @embedFile("extensions/fixtures/env-node-readable-buffer-source-24.json");
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "readableBufferSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-readable-buffer.json"))));
    const generation = engine.native_allocation_generation;
    const output = engine.evalModule(@embedFile("extensions/fixtures/env-node-readable-buffer-source-24.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(readableBufferSource))throw Error(JSON.stringify({actual:packet,expected:readableBufferSource}));export const proof=true;", "native-readable-buffer-source.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(output);
    c.JS_RunGC(engine.runtime);
}
test "native Env stream foundation actual Node24 queue identity views cross chunks strings surrogate compaction and length semantics" {
    try replay(std.testing.allocator);
}
test "native Env stream foundation all Source queue paths release roots at every host allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, replay, .{});
}
