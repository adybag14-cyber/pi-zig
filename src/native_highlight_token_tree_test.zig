//! Thin private algorithm wrappers, not a public Source class metadata certificate.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const tree = @import("extensions/native_highlight_token_tree.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const Method = enum(c_int) { add, openNode, closeNode, closeAllNodes, toJSON, addKeyword, addText, addSublanguage, toHTML, finalize };

fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn methodCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..3]) catch |err| sdk.fail(engine, err);
}
fn invoke(engine: *em.Engine, method: Method, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // The C closure owns these VM roots. This temporary facade borrows them;
    // no heap pointer or native frame survives a call into caller code.
    var emitter: tree.Emitter = .{ .engine = engine, .root = roots[0], .stack = roots[1], .options = roots[2] };
    switch (method) {
        .add => try emitter.add(arg(args, 0)),
        .openNode => try emitter.openNode(arg(args, 0)),
        .closeNode => return emitter.closeNode(),
        .closeAllNodes => try emitter.closeAllNodes(),
        .toJSON => return emitter.toJson(),
        .addKeyword => try emitter.addKeyword(arg(args, 0), arg(args, 1)),
        .addText => try emitter.addText(arg(args, 0)),
        .addSublanguage => {
            const sub_root = try scope.get(arg(args, 0), "root");
            const other: tree.Emitter = .{ .engine = engine, .root = sub_root, .stack = c.pi_js_undefined(), .options = c.pi_js_undefined() };
            try emitter.addSublanguage(&other, arg(args, 1));
        },
        .toHTML => return emitter.toHtml(),
        .finalize => return c.pi_js_bool(engine.context, @intFromBool(emitter.finalize())),
    }
    return c.pi_js_undefined();
}
fn makeCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return make(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn make(engine: *em.Engine, options: c.JSValue) !c.JSValue {
    var emitter = try tree.Emitter.init(engine, options);
    defer emitter.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const facade = try scope.object();
    try scope.put(facade, "root", emitter.root);
    var roots = [_]c.JSValue{ emitter.root, emitter.stack, emitter.options };
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const arity: c_int = switch (method) {
            .add, .openNode, .addText => 1,
            .addKeyword, .addSublanguage => 2,
            else => 0,
        };
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, field.name, arity, @intCast(field.value), roots.len, &roots));
        try sdk.put(engine, facade, field.name, function);
    }
    return c.JS_DupValue(engine.context, facade);
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const maker = try engine.checked(c.JS_NewCFunction(engine.context, makeCall, "makeTokenTreeEmitter", 1));
    sdk.put(engine, global, "makeTokenTreeEmitter", maker) catch |err| return engine.nativeAllocationError(err, generation);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-highlight-tree-1692.input.txt"), "highlight-token-tree-original24.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const rows = try sdk.get(engine, global, "sdkTokenTreeRows");
    defer engine.freeValue(rows);
    const raw = try engine.stringify(rows);
    defer gpa.free(raw);
    const expected_bytes = @embedFile("extensions/fixtures/sdk-highlight-tree-1692.json");
    const expected = try engine.checked(c.JS_ParseJSON(engine.context, expected_bytes, expected_bytes.len, "highlight-token-tree-original24.json"));
    defer engine.freeValue(expected);
    const expected_raw = try engine.stringify(expected);
    defer gpa.free(expected_raw);
    if (!std.mem.eql(u8, raw, expected_raw)) {
        std.debug.print("Actual token tree Source mismatch:\n{s}\nExpected:\n{s}\n", .{ raw, expected_raw });
        return error.TokenTreeSourceMismatch;
    }
    const released = try engine.eval("delete globalThis.sdkTokenTreeRows;delete globalThis.makeTokenTreeEmitter;", "token-tree-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native highlight token tree matches actual Source24 alias identity HTML escapes nested scopes and retained callbacks" {
    try exercise(std.testing.allocator);
}
test "native highlight token tree releases every original full-probe allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "highlight-token-tree", exercise, .{});
}
