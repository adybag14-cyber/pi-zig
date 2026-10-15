const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn json(engine: *em.Engine, value: []const u8) !c.JSValue {
    const terminated = try engine.gpa.dupeZ(u8, value);
    defer engine.gpa.free(terminated);
    return engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, terminated.len, "responses-source-fixture.json"));
}
fn install(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    if (engine.host_scheduler == null) try @import("extensions/timers.zig").install(engine, std.testing.io);
    if (engine.abort_signal_class == 0) try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/native_stream.zig").install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/node_url.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/node_base64.zig").install(engine, try scope.object());
    const DecodeFixture = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            if (args.len == 0) return error.ExpectedCompressedFixtureBody;
            var offset: usize = 0;
            var length: usize = 0;
            var element_size: usize = 0;
            const buffer = try host.checked(c.JS_GetTypedArrayBuffer(host.context, args[0], &offset, &length, &element_size));
            defer host.freeValue(buffer);
            var buffer_length: usize = 0;
            const data = c.JS_GetArrayBuffer(host.context, &buffer_length, buffer);
            if (data == null or offset > buffer_length or length > buffer_length - offset) return error.InvalidCompressedFixtureBody;
            var input: std.Io.Reader = .fixed(data[offset..][0..length]);
            var decoder: std.compress.zstd.Decompress = .init(&input, &.{}, .{});
            var output: std.Io.Writer.Allocating = .init(host.gpa);
            defer output.deinit();
            _ = try decoder.reader.streamRemaining(&output.writer);
            return sdk.text(host, output.written());
        }
    };
    try scope.put(global, "decodeCodexFixtureBody", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "decodeCodexFixtureBody", 1, DecodeFixture.call, &.{})));
    const Collect = struct {
        fn call(host: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            c.JS_RunGC(host.runtime);
            return c.pi_js_undefined();
        }
    };
    try scope.put(global, "collectResponsesRetryGraph", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "collectResponsesRetryGraph", 0, Collect.call, &.{})));
    try scope.put(global, "responsesAPI", try scope.own(try @import("extensions/native_ai_responses_factory.zig").create(engine)));
    try scope.put(global, "azureResponsesAPI", try scope.own(try @import("extensions/native_ai_responses_factory.zig").createMode(engine, .azure)));
    try scope.put(global, "codexResponsesAPI", try scope.own(try @import("extensions/native_ai_responses_factory.zig").createMode(engine, .codex)));
    try scope.put(global, "AssistantMessageEventStream", try scope.get(engine.native_module_values.get("@earendil-works/pi-ai").?, "AssistantMessageEventStream"));
    try scope.put(global, "responsesInput", try scope.own(try json(engine, @embedFile("extensions/fixtures/ai-responses18-5ab.input.json"))));
    try scope.put(global, "responsesSource", try scope.own(try json(engine, @embedFile("extensions/fixtures/ai-responses18-5ab.json"))));
    try scope.put(global, "responsesRetrySource", try scope.own(try json(engine, @embedFile("extensions/fixtures/ai-responses-retry14-5ab.json"))));
}

test "native Responses actual factory requests callbacks push snapshots consumer snapshots and alias identity against Source18" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-responses18-5ab.input.txt"), "native-responses18-source-differential.mjs") catch |err| {
        std.debug.print("Responses Source18: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native Responses retained factory graph survives collection before actual request" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const held = try engine.evalModule("globalThis.keptResponses=responsesAPI;delete globalThis.responsesAPI;globalThis.responsesAPI=keptResponses;export const held=true;", "native-responses-retained-prepare.mjs");
    engine.freeValue(held);
    c.JS_RunGC(engine.runtime);
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-responses18-5ab.input.txt"), "native-responses-retained-complete.mjs") catch |err| {
        std.debug.print("Responses retained graph: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native Responses every host allocation releases factory dependencies and closure roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const factory = @import("extensions/native_ai_responses_factory.zig").create(engine) catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(factory);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

test "native Responses direct HTTP and SDK retry callbacks reader failures and pre-abort match genuine SourceRetry14" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-responses-retry14-5ab.input.txt"), "native-responses-retry14-source-differential.mjs") catch |err| {
        std.debug.print("Responses SourceRetry14: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native Responses retry graph retains genuine callback and abort values after collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const enabled = try engine.evalModule("globalThis.responsesRetryGcBetweenHooks=true;export const enabled=true;", "native-responses-retry14-enable-gc.mjs");
    engine.freeValue(enabled);
    c.JS_RunGC(engine.runtime);
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-responses-retry14-5ab.input.txt"), "native-responses-retry14-retained-differential.mjs") catch |err| {
        std.debug.print("Responses retained SourceRetry14: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
