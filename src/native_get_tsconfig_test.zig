//! Prepared controls. Full comparison needs the retained original physical root,
//! original JSON and the real fs/path/Module/process assembly; no fake inputs.
const std = @import("std");
const em = @import("extensions/engine.zig");
const h = @import("extensions/native_tsconfig_values.zig");
const jsonc = @import("extensions/native_tsconfig_jsonc.zig");
const library = @import("extensions/native_get_tsconfig.zig");
const c = em.c;
fn actual(engine: *em.Engine, name: []const u8, value: c.JSValue) !void {
    const installed = engine.native_module_values.get(name) orelse return error.RequiredActualTsconfigDependencyAssembly;
    if (c.JS_IsStrictEqual(engine.context, installed, value)) return;
    const default = try h.v.js.get(engine, installed, "default"); defer engine.freeValue(default);
    if (!c.JS_IsStrictEqual(engine.context, default, value)) return error.RequiredSameTsconfigDependencyIdentity;
}
pub fn compareOriginal(engine: *em.Engine, inputs: library.Inputs, original_json: []const u8) !void {
    try actual(engine, "node:fs", inputs.fs); try actual(engine, "node:path", inputs.path); try actual(engine, "node:module", inputs.module);
    var s: h.Scope = .{ .engine = engine }; defer s.deinit();
    const terminated = try engine.gpa.dupeZ(u8, original_json); defer engine.gpa.free(terminated);
    const original = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, original_json.len, "original-get-tsconfig4.14.0.json")));
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    const bindings = try s.own(try library.create(engine, inputs));
    try s.put(global, "nativeTsconfigSubject", bindings); try s.put(global, "nativeTsconfigRoot", try s.get(original, "root")); try s.put(global, "originalTsconfigObservation", original);
    const result = try engine.evalModule(@embedFile("extensions/fixtures/get-tsconfig-4.14.0.input.mjs") ++
        \\if(nativeTsconfigObservation.count!==originalTsconfigObservation.count)throw Error('Complete original tsconfig census required');for(let i=0;i<nativeTsconfigObservation.rows.length;i++)if(JSON.stringify(nativeTsconfigObservation.rows[i])!==JSON.stringify(originalTsconfigObservation.rows[i]))throw Error(JSON.stringify({i,actual:nativeTsconfigObservation.rows[i],original:originalTsconfigObservation.rows[i]}));
    , "native-get-tsconfig-original.mjs"); engine.freeValue(result);
}
pub fn retainedMatcher(engine: *em.Engine, inputs: library.Inputs, original_json: []const u8) !void {
    try actual(engine, "node:fs", inputs.fs); try actual(engine, "node:path", inputs.path); try actual(engine, "node:module", inputs.module);
    const bindings = try library.create(engine, inputs);
    {
        defer engine.freeValue(bindings);
        var s: h.Scope = .{ .engine = engine }; defer s.deinit();
        const text = try engine.gpa.dupeZ(u8, original_json); defer engine.gpa.free(text);
        const original = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, text.ptr, original_json.len, "original-tsconfig-retention.json")));
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        try s.put(global, "nativeTsconfigSubject", bindings); try s.put(global, "nativeTsconfigRoot", try s.get(original, "root")); try s.put(global, "retainedOriginalTsconfig", original);
        const value = try engine.evalModule(
            \\globalThis.retainedTsconfigMatcher=nativeTsconfigSubject.createPathsMatcher(nativeTsconfigSubject.getTsconfig(nativeTsconfigRoot+'/simple'));delete globalThis.nativeTsconfigSubject;
        , "native-tsconfig-before-gc.mjs"); engine.freeValue(value);
    }
    c.JS_RunGC(engine.runtime);
    const value = try engine.evalModule(
        \\const original=retainedOriginalTsconfig.rows.find(row=>row.name==='matcher-simple').value.matches;for(const row of original)if(JSON.stringify(retainedTsconfigMatcher(row.specifier))!==JSON.stringify(row.paths))throw Error('Retained native matcher differs from original');delete globalThis.retainedTsconfigMatcher;delete globalThis.retainedOriginalTsconfig;
    , "native-tsconfig-after-gc.mjs"); engine.freeValue(value); c.JS_RunGC(engine.runtime);
}
test "native get-tsconfig JSONC preserves isolated UTF16 code units" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: h.Scope = .{ .engine = engine }; defer s.deinit();
    const value = try s.own(try jsonc.parse(engine, try s.text("{\"unit\":\"\\ud800\"}")));
    var length: usize = 0; const units = c.JS_ToCStringLenUTF16(engine.context, &length, try s.get(value, "unit"));
    if (units == null) return h.v.js.capture(engine); defer c.JS_FreeCStringUTF16(engine.context, units);
    try std.testing.expectEqual(@as(usize, 1), length); try std.testing.expectEqual(@as(u16, 0xd800), units[0]);
}
test "native get-tsconfig JSONC native nesting quota is uncatchable" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var text: [600]u8 = undefined; @memset(text[0..300], '['); @memset(text[300..], ']');
    var s: h.Scope = .{ .engine = engine }; defer s.deinit();
    try std.testing.expectError(error.JavaScriptException, jsonc.parse(engine, try s.text(&text)));
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception orelse return error.MissingTsconfigQuota));
}
test "native get-tsconfig JSONC all Zig allocation failures release scanner buffers and partial values" {
    const Probe = struct { fn run(gpa: std.mem.Allocator) !void {
        const engine = try em.Engine.init(gpa, .{}); defer engine.deinit();
        const generation = engine.native_allocation_generation;
        var s: h.Scope = .{ .engine = engine }; defer s.deinit();
        const input = try s.text("{/* comment */\"compilerOptions\":{\"paths\":{\"@/*\":[\"./source/*\"]}},\"unicode\":\"\\ud800\",\"partial\":");
        const result = jsonc.parse(engine, input) catch |err| return engine.nativeAllocationError(err, generation); engine.freeValue(result); c.JS_RunGC(engine.runtime);
    } };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
