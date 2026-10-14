const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const listing = @import("extensions/native_sdk_builtin_listing_renderers.zig");
const c = em.c;

fn setup(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    var environment = try std.testing.environ.createMap(engine.gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-tool-listing-renderers"});
    try @import("extensions/native_tui.zig").install(engine);
    const theme = try @import("extensions/native_theme.zig").fromJson(engine, @embedFile("extensions/fixtures/sdk-tool-renderers-e622-dark.json"), "C:/Users/adyba/pi-sdk-loadout-source-e6220e1-20261013/packages/coding-agent/src/modes/interactive/theme/dark.json", .truecolor);
    defer engine.freeValue(theme);
    try @import("extensions/native_theme.zig").setThemeInstance(engine, theme);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "actualRendererTheme", c.JS_DupValue(engine.context, theme));
    const renderers = try sdk.object(engine);
    defer engine.freeValue(renderers);
    inline for (.{ "find", "ls", "grep" }) |name| try sdk.put(engine, renderers, name, try listing.get(engine, name));
    try sdk.put(engine, global, "listingRenderers", c.JS_DupValue(engine.context, renderers));
    const configured = try engine.evalModule("import{setCapabilityOverrides}from'pi-tui';setCapabilityOverrides({images:null,hyperlinks:false});", "listing-renderers-capabilities.mjs");
    engine.freeValue(configured);
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    setup(engine) catch |err| return engine.nativeAllocationError(err, generation);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-tool-listing-renderers-e622.input.txt"), "listing-renderers-source-cases.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const rows = try sdk.get(engine, global, "sdkListingRendererRows");
    defer engine.freeValue(rows);
    const raw = try engine.stringify(rows);
    defer gpa.free(raw);
    var actual = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer actual.deinit();
    var expected = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/sdk-tool-listing-renderers-e622.json"), .{});
    defer expected.deinit();
    const actual_json = try std.json.Stringify.valueAlloc(gpa, actual.value, .{});
    defer gpa.free(actual_json);
    const expected_json = try std.json.Stringify.valueAlloc(gpa, expected.value, .{});
    defer gpa.free(expected_json);
    if (!std.mem.eql(u8, actual_json, expected_json)) {
        std.debug.print("Actual ListingRenderer Source mismatch:\n{s}\nExpected:\n{s}\n", .{ actual_json, expected_json });
        return error.ListingRendererSourceMismatch;
    }
    const cleared = try engine.eval("delete globalThis.sdkListingRendererRows;", "listing-renderers-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(cleared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native SDK tool listing renderers match full original59 calls results Theme image fallback metadata and getter order" {
    try exercise(std.testing.allocator);
}
test "native SDK tool listing renderers retain actual Theme and reused Text through collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const initial = try engine.evalModule("globalThis.listingHeld=listingRenderers.find.renderCall({pattern:'kept'},actualRendererTheme,{state:{}});globalThis.listingWeak=new WeakRef(listingHeld);", "listing-renderers-gc-setup.mjs");
    engine.freeValue(initial);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("if(listingRenderers.find.renderCall({pattern:'next'},actualRendererTheme,{state:{},lastComponent:listingHeld})!==listingHeld||!listingHeld.text.includes('next'))throw Error('listing renderer lost Text identity');delete globalThis.listingHeld;", "listing-renderers-gc-held.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(retained);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const released = try engine.eval("if(listingWeak.deref()!==undefined)throw Error('listing renderer retained disposed Text');delete globalThis.listingWeak;", "listing-renderers-gc-released.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
}
test "native SDK tool listing renderers release every original full-probe allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-tool-listing-renderers", exercise, .{});
}
