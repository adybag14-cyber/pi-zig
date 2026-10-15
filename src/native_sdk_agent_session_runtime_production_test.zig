//! Source-only replay entry point. The production assembler must supply actual
//! factory imports and the genuine ordinary AgentSession constructor. No fake
//! default factory/services or legacy session-runtime class are provided.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const lifecycle = @import("extensions/native_sdk_agent_session_runtime_production.zig");
const c = em.c;

pub fn installActualGraph(engine: *em.Engine, imports: c.JSValue, ordinary_session: c.JSValue, fixture_cwd: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.own(try lifecycle.create(engine, imports));
    const factory_imports = try scope.own(try js.spread(engine, imports));
    try scope.put(factory_imports, "AgentSessionRuntime", try scope.get(runtime, "AgentSessionRuntime"));
    try scope.put(factory_imports, "assertSessionCwdExists", try scope.get(runtime, "assertSessionCwdExists"));
    const factory = try scope.own(try @import("extensions/native_sdk_factory_production.zig").create(engine, factory_imports, ordinary_session));
    const api = try scope.own(try js.spread(engine, factory));
    try js.spreadInto(engine, api, runtime);
    try scope.put(api, "AgentSession", ordinary_session);
    inline for (.{ "SessionManager", "SettingsManager", "ModelRuntime", "fs", "path" }) |name| try scope.put(api, name, try scope.get(imports, name));
    try scope.put(api, "fixtureCwd", fixture_cwd);
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "runtimeAPI", api);
}

/// Expected bytes must come from the admitted genuine Source capture. They are
/// deliberately not fabricated or embedded before that capture has occurred.
pub fn replay(engine: *em.Engine, genuine_source_json: []const u8) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, genuine_source_json.ptr, genuine_source_json.len, "actual-agent-session-runtime-4954.json")));
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "runtimeSource", expected);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-agent-session-runtime-production-4954.input.txt") ++
        "\nif(runtimeRows.length!==34||runtimeSource.rows.length!==34)throw Error('All34 genuine runtime cases required');for(let i=0;i<34;i++)if(JSON.stringify(runtimeRows[i])!==JSON.stringify(runtimeSource.rows[i]))throw Error(JSON.stringify({case:i,name:runtimeRows[i].name,actual:runtimeRows[i],expected:runtimeSource.rows[i]}));", "native-agent-session-runtime-production-4954.mjs") catch |err| {
        std.debug.print("Actual runtime class replay failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(result);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
