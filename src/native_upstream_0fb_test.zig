//! Genuine latest-source observations; expected rows are never handwritten.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const durable = @import("extensions/native_durable.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;

fn policy(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("extensions/native_durable_compaction_policy.zig").resolve(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn retryable(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const result = @import("extensions/native_ai_error_classification.zig").retryable(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(context, @intFromBool(result));
}
fn install(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/native_stream.zig").install(engine);
    try durable.install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "latestPolicy", try engine.checked(c.JS_NewCFunction(engine.context, policy, "compactionPolicy", 2)));
    try sdk.put(engine, global, "latestRetry", try engine.checked(c.JS_NewCFunction(engine.context, retryable, "isRetryableAssistantError", 1)));
}
fn compare(name: []const u8, input: []const u8, field: [:0]const u8, count: usize) !void {
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/upstream-0fb-source.json"));
    defer source.deinit();
    try std.testing.expectEqualStrings("0fbdbd3f8ab1876ac260c0f08226a400759323b8", try json.asString(try json.required(source.value, "sourceHead")));
    const programs = (try json.required(source.value, "programs")).array.items;
    var expected: ?std.json.Value = null;
    for (programs) |program| {
        if (!std.mem.eql(u8, name, try json.asString(try json.required(program, "name")))) continue;
        const hash = std.crypto.hash.sha2.Sha256.hash;
        var digest: [32]u8 = undefined;
        hash(input, &digest, .{});
        const encoded = std.fmt.bytesToHex(digest, .lower);
        try std.testing.expectEqualStrings(try json.asString(try json.required(program, "inputSha256")), &encoded);
        expected = try json.required(program, "rows");
        try std.testing.expectEqual(count, expected.?.array.items.len);
    }
    if (expected == null) return error.MissingGenuineLatestSourceProgram;
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 20000 });
    defer engine.deinit();
    try install(engine);
    const result = engine.evalModule(input, name) catch |err| {
        std.debug.print("Latest0fb {s}: {s}\n", .{ name, engine.last_error orelse "no VM diagnostic" });
        @import("extensions/native_durable_tasks.zig").printFailureDiagnostics(engine);
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const rows = try sdk.get(engine, global, field);
    defer engine.freeValue(rows);
    var actual = try durable.owned(engine, rows);
    defer actual.deinit();
    if (!json.equal(actual.value, expected.?)) {
        const output = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(output);
        std.debug.print("Latest0fb {s} actual: {s}\n", .{ name, output });
        return error.LatestSourceObservationMismatch;
    }
    c.JS_RunGC(engine.runtime);
}
test "native upstream0fb genuine policy getters and retry classifier" {
    try compare("policy", @embedFile("extensions/fixtures/upstream-0fb-policy.input.txt"), "upstream0fbRows", 17);
}
test "native upstream0fb Zig retry classifier matches genuine new node-fetch and service wording" {
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/upstream-0fb-source.json"));
    defer source.deinit();
    var checked: usize = 0;
    for ((try json.required(source.value, "programs")).array.items) |program| {
        if (!std.mem.eql(u8, "policy", try json.asString(try json.required(program, "name")))) continue;
        for ((try json.required(program, "rows")).array.items) |row| {
            const name = try json.asString(try json.required(row, "name"));
            if (!std.mem.startsWith(u8, name, "retry:")) continue;
            try std.testing.expectEqual((try json.required(row, "retryable")).bool, @import("ai/retry.zig").isRetryableError(name[6..]));
            checked += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 10), checked);
}
test "native upstream0fb genuine public threshold overflow summary sizing and false tool control" {
    try compare("public", @embedFile("extensions/fixtures/upstream-0fb-public.input.txt"), "upstream0fbPublicRows", 6);
}
test "native upstream0fb genuine select settings and policy remain fixed across awaits and hooks" {
    try compare("select", @embedFile("extensions/fixtures/upstream-0fb-select.input.txt"), "upstream0fbSelectRows", 4);
}
test "native upstream0fb policy releases all getter symbol and override roots under allocation failure" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{});
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            sdk.put(engine, global, "latestPolicy", try engine.checked(c.JS_NewCFunction(engine.context, policy, "compactionPolicy", 2))) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const settings={compaction:{enabled:true,reserveTokens:100,keepRecentTokens:200,backgroundTokens:300,modelOverrides:{'p/m':{reserveTokens:0,enabled:false}},get [Symbol('extra')](){return {root:true}}}};const value=latestPolicy(settings,{provider:'p',modelId:'m'});if(value.reserveTokens!==0||value.enabled!==false)throw Error('policy fields');export const complete=true;
            , "latest0fb-policy-allocation") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
