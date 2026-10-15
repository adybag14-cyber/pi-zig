const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const sdk = @import("extensions/native_sdk.zig");
const env_keys = @import("extensions/native_ai_env_keys.zig");
const c = em.c;
fn install(engine: *em.Engine, exists: ?c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "envKeysAPI", try env_keys.create(engine, .{ .exists_sync = exists }));
}
test "native AI env keys matches72 original provider mappings env getters ambient credentials explicit ADC and Bun observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    const fs = try js.get(engine, engine.native_module_values.get("node:fs").?, "default");
    defer engine.freeValue(fs);
    const exists = try js.get(engine, fs, "existsSync");
    defer engine.freeValue(exists);
    try install(engine, exists);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "adc.fixture", .data = "caller-owned path fixture only, no credentials" });
    const path = try temporary.dir.realPathFileAlloc(std.testing.io, "adc.fixture", std.testing.allocator);
    defer std.testing.allocator.free(path);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "envVertexExistingPath", try sdk.text(engine, path));
    const source = @embedFile("extensions/fixtures/ai-env-keys-b45.json");
    try sdk.put(engine, global, "envKeysSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "ai-env-keys-b45.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-env-keys-b45.input.txt") ++
        "\nif(envKeysRows.length!==72||envKeysSource.rows.length!==72||envKeysSource.sourceHead!=='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb')throw Error('all72 required');for(let i=0;i<72;i++)if(JSON.stringify(envKeysRows[i])!==JSON.stringify(envKeysSource.rows[i]))throw Error(JSON.stringify({case:i,actual:envKeysRows[i],expected:envKeysSource.rows[i]}));", "native-ai-env-keys-original.mjs") catch |err| {
        std.debug.print("Env keys Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native AI env keys every host allocation releases discovery filters env maps and cached Bun readers" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine, null) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\globalThis.process={versions:{node:'24'},env:{OPENAI_API_KEY:'process'}};const env={ANTHROPIC_AUTH_TOKEN:'bearer',ANTHROPIC_OAUTH_TOKEN:'oauth',ANTHROPIC_API_KEY:'key'};
                \\if(envKeysAPI.getEnvApiKey('anthropic',env)!=='oauth'||envKeysAPI.findEnvKeys('anthropic',env).length!==3||envKeysAPI.getEnvApiKey('openai')!=='process'||envKeysAPI.getEnvApiKey('amazon-bedrock',{AWS_PROFILE:'p'})!=='<authenticated>')throw Error('native env graph');
                \\process.versions={bun:'1'};process.env={};globalThis.require=()=>({readFileSync(){return 'OPENAI_API_KEY=proc\0OTHER=a=b\0'}});if(envKeysAPI.getEnvApiKey('openai')!=='proc'||envKeysAPI.getProviderEnvValue('OTHER')!=='a=b'||envKeysAPI.getEnvApiKey('anthropic',{ANTHROPIC_AUTH_TOKEN:'bearer'})!==undefined)throw Error('Bun cache graph');delete globalThis.process;delete globalThis.require;export const proof=true;
            , "native-ai-env-keys-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
