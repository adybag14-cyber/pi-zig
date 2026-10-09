//! Cached AgentTool projections keep definition identity and execution ownership
//! independent. The C function data participates in the VM's cycle tracing.
const engine_mod = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = engine_mod.c;
pub fn wrap(owner: *sdk.State, definition: c.JSValue) !c.JSValue {
    const engine = owner.engine;
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ "name", "label", "description", "parameters", "outputSchema", "constrainedSampling", "prepareArguments", "executionMode" }) |name| try sdk.put(engine, result, name, try sdk.get(engine, definition, name));
    const session = try sdk.sessionDataSessionValue(engine, owner.data);
    defer engine.freeValue(session);
    const lease = try sdk.sessionModelLease(owner);
    const generation = try engine.checked(c.JS_NewBigUint64(engine.context, lease.generation));
    defer engine.freeValue(generation);
    const runtime_id = try engine.checked(c.JS_NewBigUint64(engine.context, lease.runtime_id));
    defer engine.freeValue(runtime_id);
    var data = [_]c.JSValue{ definition, session, generation, runtime_id };
    try sdk.put(engine, result, "execute", try engine.checked(c.JS_NewCFunctionData2(engine.context, execute, "execute", 5, 0, data.len, &data)));
    return result;
}
fn execute(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return executeOwned(engine, argc, argv, data) catch |err| sdk.fail(engine, err);
}
fn executeOwned(engine: *engine_mod.Engine, argc: c_int, argv: [*c]c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 5;
    for (args[0..@min(@as(usize, @intCast(argc)), args.len)], 0..) |*arg, index| arg.* = argv[index];
    const supplied = !c.JS_IsUndefined(args[4]) and !c.JS_IsNull(args[4]);
    const actual = if (supplied) c.JS_DupValue(engine.context, args[4]) else try @import("native_sdk_tool_context.zig").create(engine, data[1], data[2], data[3], args[0], args[2]);
    defer engine.freeValue(actual);
    args[4] = actual;
    // Property lookup and receiver are taken from the original definition on
    // every call, including its raw synchronous return or thrown JS value.
    return sdk.invoke(engine, data[0], "execute", &args);
}

test "ToolInfo cached SDK AgentTool projections and original session tool contexts match genuine Source identity and lifetime" {
    const std = @import("std");
    const group_mod = @import("native_group.zig");
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const main = try group.add("<main>");
    try main.installSchemas();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var cwd_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cwd_size = try temporary.dir.realPath(std.testing.io, &cwd_buffer);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "wrapperCwd", try sdk.text(engine, cwd_buffer[0..cwd_size]));
    inline for (.{ .{ "wrapperIdentitySource", "../durable/fixtures/sdk-agent-tool-wrapper-identity-1ced.json" }, .{ "wrapperContextSource", "../durable/fixtures/sdk-agent-tool-context-1ced.json" } }) |fixture| {
        const text = @embedFile(fixture[1]);
        try sdk.put(engine, global, fixture[0], try engine.checked(c.JS_ParseJSON(engine.context, text, text.len, "actual-source-sdk-wrapper")));
    }
    const output = try engine.evalModule(@embedFile("../durable/fixtures/sdk-agent-tool-wrapper-context.mjs"), "sdk-agent-tool-wrapper-context.mjs");
    defer engine.freeValue(output);
    const proof = try sdk.get(engine, output, "proof");
    defer engine.freeValue(proof);
    try std.testing.expect(c.JS_ToBool(engine.context, proof) == 1);
}
