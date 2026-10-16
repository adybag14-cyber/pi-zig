//! Latest Source replay over the actual native compat/provider/Models graph.
//! Public caller stream callbacks are the unchanged fixture's owned inputs.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;

fn setup(engine: *em.Engine) !void {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"latest4dd-summary-replay"});
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/native_bigint_host.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const apis = try scope.own(try @import("extensions/native_ai_builtin_apis.zig").create(engine));
    const providers = try scope.own(try @import("extensions/native_ai_provider_factories.zig").create(engine, apis));
    const all = try scope.own(try @import("extensions/native_ai_provider_factories.zig").all(engine, providers));
    const compat = try scope.own(try @import("extensions/native_ai_compat.zig").namespace(engine, try scope.get(all, "builtinModels")));
    const shared = try scope.own(try @import("extensions/native_sdk_session_ai_assembly.zig").create(engine, compat));
    const generation = try scope.object();
    inline for (.{ "generateSummaryWithUsage", "generateSummary", "compact" }) |name| try scope.put(generation, name, try scope.get(shared, name));
    const files = try scope.own(try @import("extensions/native_sdk_compaction_files.zig").exports(engine));
    const global = try scope.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));
    try scope.put(global, "summaryGenerationAPI", generation);
    try scope.put(global, "createSummaryFileOps", try scope.get(files, "createFileOps"));
    const latest = try scope.object();
    inline for (.{ "generateSummary", "generateSummaryWithUsage", "compact" }) |name| try scope.put(latest, name, try scope.get(shared, name));
    try scope.put(latest, "generateBranchSummary", try scope.get(try scope.get(shared, "branchSummary"), "generateBranchSummary"));
    try scope.put(latest, "createFileOps", try scope.get(files, "createFileOps"));
    try scope.put(latest, "defaultModelPerProvider", try scope.own(try @import("extensions/native_sdk_factory_model.zig").defaultModelPerProvider(engine)));
    try scope.put(global, "latestSummaryAPI", latest);
}

fn expected(engine: *em.Engine, name: [*:0]const u8, source: [:0]const u8) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));
    try scope.put(global, name, try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "genuine-latest4dd-Source.json"))));
}

test "native latest4dd summary45 preserves all original45 caller observations and assertions" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    try expected(engine, "summaryGenerationSource", @embedFile("extensions/fixtures/sdk-summary-original45-latest4dd.expected.json"));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-summary-generation-b45.input.txt") ++
        "\nif(summaryGenerationRows.length!==45||summaryGenerationSource.rows.length!==45)throw Error('all45 required');for(let i=0;i<45;i++)if(JSON.stringify(summaryGenerationRows[i])!==JSON.stringify(summaryGenerationSource.rows[i]))throw Error(JSON.stringify({case:i,actual:summaryGenerationRows[i],expected:summaryGenerationSource.rows[i]}));", "native-latest4dd-summary-original45.mjs") catch |err| {
        std.debug.print("Latest summary45 Source: {s}\n", .{engine.last_error orelse "none"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native latest4dd summary30 compares all original latest getter option and default-map observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    try expected(engine, "latestSummarySource", @embedFile("extensions/fixtures/sdk-summary-latest4dd.expected.json"));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-summary-latest4dd.input.txt") ++
        "\nif(latestSummaryRows.length!==30||latestSummarySource.rows.length!==30)throw Error('all30 required');for(let i=0;i<30;i++)if(JSON.stringify(latestSummaryRows[i])!==JSON.stringify(latestSummarySource.rows[i]))throw Error(JSON.stringify({case:i,actual:latestSummaryRows[i],expected:latestSummarySource.rows[i]}));", "native-latest4dd-summary-default30.mjs") catch |err| {
        std.debug.print("Latest summary30 Source: {s}\n", .{engine.last_error orelse "none"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
