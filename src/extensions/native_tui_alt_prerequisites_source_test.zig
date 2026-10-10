//! Genuine Source alternate-screen dependencies; no public Alt parity claim.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
fn flashSetup() !*js.Engine {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    errdefer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"tui-alt-prerequisites"});
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    const exports = engine.native_module_values.get("pi-tui") orelse return error.NativeTuiUnavailable;
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeAltScreenFlashContainer", try @import("native_alt_screen_flash.zig").create(engine, exports));
    return engine;
}
test "Source6fb alternate-screen prerequisite wheel gesture numeric coercion and actual callable state" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeWheelScrollAccelerator", try @import("native_wheel_scroll.zig").create(engine));
    const expected = @embedFile("fixtures/tui-wheel-scroll-original-6fb.json");
    try js.define(engine, root, "wheelSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-wheel-scroll-original-6fb.json")));
    const result = engine.evalModule("const WheelScrollAccelerator=nativeWheelScrollAccelerator;\n" ++ @embedFile("fixtures/tui-wheel-scroll-original-6fb.input.txt") ++ "\nif(JSON.stringify(tuiWheelCases)!==JSON.stringify(wheelSource.cases))throw Error(JSON.stringify({actual:tuiWheelCases,expected:wheelSource.cases}));", "tui-wheel-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native wheel Source mismatch: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb alternate-screen prerequisite flash scheduling rendering postfix identity expiry and disposal" {
    const engine = try flashSetup();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const expected = @embedFile("fixtures/tui-alt-flash-original-6fb.json");
    try js.define(engine, root, "flashSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-alt-flash-original-6fb.json")));
    const result = engine.evalModule("const AltScreenFlashContainer=nativeAltScreenFlashContainer;\n" ++ @embedFile("fixtures/tui-alt-flash-original-6fb.input.txt") ++ "\nif(JSON.stringify(tuiAltFlashCases)!==JSON.stringify(flashSource.cases))throw Error(JSON.stringify({actual:tuiAltFlashCases,expected:flashSource.cases}));", "tui-alt-flash-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native alternate-screen flash Source mismatch: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb alternate-screen prerequisite flash actual native timer unref expiry and cancellation" {
    const engine = try flashSetup();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const expected = @embedFile("fixtures/tui-alt-flash-timers-original-6fb.json");
    try js.define(engine, root, "flashTimersSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-alt-flash-timers-original-6fb.json")));
    const promise = engine.evalModule("const AltScreenFlashContainer=nativeAltScreenFlashContainer;\n" ++ @embedFile("fixtures/tui-alt-flash-timers-original-6fb.input.txt") ++ "\nif(JSON.stringify(tuiAltFlashTimerCases)!==JSON.stringify(flashTimersSource.cases))throw Error(JSON.stringify({actual:tuiAltFlashTimerCases,expected:flashTimersSource.cases}));", "tui-alt-flash-actual-timers-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native alternate-screen flash actual timer Source mismatch: {s}\n", .{message});
        return err;
    };
    defer engine.freeValue(promise);
    const result = engine.awaitValue(promise) catch |err| {
        if (engine.last_error) |message| std.debug.print("Native alternate-screen flash actual timer continuation: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb alternate-screen prerequisite search corpus Unicode17 spans regex matching cache and keys" {
    const engine = try flashSetup();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const exports = engine.native_module_values.get("pi-tui") orelse return error.NativeTuiUnavailable;
    try js.define(engine, root, "nativeAltSearch", try @import("native_alt_screen_search_index.zig").create(engine, exports));
    const expected = @embedFile("fixtures/tui-alt-search-original-6fb.json");
    try js.define(engine, root, "searchSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-alt-search-original-6fb.json")));
    const result = engine.evalModule("const{AltScreenSearchIndex,findAltScreenSearchMatches,getAltScreenSearchMatchKey}=nativeAltSearch;\n" ++ @embedFile("fixtures/tui-alt-search-original-6fb.input.txt") ++ "\nif(JSON.stringify(tuiAltSearchCases)!==JSON.stringify(searchSource.cases))throw Error(JSON.stringify({actual:tuiAltSearchCases,expected:searchSource.cases}));", "tui-alt-search-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native alternate-screen search Source mismatch: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb alternate-screen prerequisite search component actual Input focus editing render bounds and callbacks" {
    const engine = try flashSetup();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const exports = engine.native_module_values.get("pi-tui") orelse return error.NativeTuiUnavailable;
    try js.define(engine, root, "nativeAltScreenSearchComponent", try @import("native_alt_screen_search_component.zig").create(engine, exports));
    const expected = @embedFile("fixtures/tui-alt-search-component-original-6fb.json");
    try js.define(engine, root, "searchComponentSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-alt-search-component-original-6fb.json")));
    const result = engine.evalModule("const AltScreenSearchComponent=nativeAltScreenSearchComponent;\n" ++ @embedFile("fixtures/tui-alt-search-component-original-6fb.input.txt") ++ "\nif(JSON.stringify(tuiAltSearchComponentCases)!==JSON.stringify(searchComponentSource.cases))throw Error(JSON.stringify({actual:tuiAltSearchComponentCases,expected:searchComponentSource.cases}));", "tui-alt-search-component-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native alternate-screen search component Source mismatch: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
