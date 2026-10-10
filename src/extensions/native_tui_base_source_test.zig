//! Internal complete TuiBase replay; does not certify public Main/Alt renderers.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
fn setup() !*js.Engine {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    errdefer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"tui-base-source"});
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    const exports = engine.native_module_values.get("pi-tui") orelse return error.NativeTuiUnavailable;
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "internalTuiBase", try @import("native_tui_base.zig").create(engine, exports));
    return engine;
}
test "Source6fb internal TuiBase genuine constructor full metadata overlay lifetime layout composite and normalization" {
    const engine = try setup();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const expected = @embedFile("fixtures/tui-base-original-6fb.json");
    try js.define(engine, root, "internalBaseSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-base-original-6fb.json")));
    const result = engine.evalModule(
        "import * as tui from 'pi-tui';const TuiBase=globalThis.internalTuiBase;\n" ++ @embedFile("fixtures/tui-base-original-6fb.input.txt") ++
            "\nif(JSON.stringify(tuiBaseCases)!==JSON.stringify(internalBaseSource.cases))throw Error(JSON.stringify({actual:tuiBaseCases,expected:internalBaseSource.cases}));",
        "tui-base-source-replay.mjs",
    ) catch |err| {
        if (engine.last_error) |message| std.debug.print("Native internal TuiBase Source mismatch: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb internal TuiBase startup clock live elapsed ignores Date override and retains mutable now lookup" {
    const engine = try setup();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "internalPerformance", try @import("native_process_clock.zig").performance(engine));
    const beginning = try engine.eval("globalThis.clockBefore=internalPerformance.now();globalThis.savedDateNow=Date.now;Date.now=()=>-123456789;", "tui-clock-before.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(beginning);
    try std.testing.io.sleep(.fromMilliseconds(5), .awake);
    const ending = try engine.eval("globalThis.clockAfter=internalPerformance.now();Date.now=savedDateNow;if(!(clockAfter>clockBefore&&clockBefore>=0&&clockAfter!==-123456789))throw Error('native monotonic elapsed');", "tui-clock-after.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(ending);
    try @import("native_process_clock.zig").install(engine, std.testing.io);
    const again = try @import("native_process_clock.zig").performance(engine);
    defer engine.freeValue(again);
    const captured = try js.get(engine, root, "internalPerformance");
    defer engine.freeValue(captured);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, captured, again));
    const result = try engine.eval(
        \\const clockTrace=[],clockScreen=new internalTuiBase({columns:40,rows:12},false);
        \\clockScreen.doRender=()=>clockTrace.push('render:'+clockScreen.lastRenderAt);clockScreen.cancelRenderTimer=()=>clockTrace.push('cancel');
        \\internalPerformance.now=function(){clockTrace.push('now:this='+String(this===internalPerformance));return 7.5};clockScreen.renderNow();
        \\internalPerformance.now=function(){clockTrace.push('now:new');return 19.25};clockScreen.renderNow();
        \\if(JSON.stringify(clockTrace)!==JSON.stringify(['cancel','now:this=true','render:7.5','cancel','now:new','render:19.25']))throw Error(JSON.stringify(clockTrace));
    , "tui-clock-source-replay.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
}
test "Source6fb internal TuiBase genuine Node terminal reports partial full duplicate late scheme and cell lifecycle" {
    const engine = try setup();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const expected = @embedFile("fixtures/tui-base-reports-original-6fb.json");
    try js.define(engine, root, "internalBaseReportSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-base-reports-original-6fb.json")));
    const promise = engine.evalModule(
        "import{getCellDimensions,setCellDimensions}from'pi-tui';const TuiBase=globalThis.internalTuiBase;\n" ++ @embedFile("fixtures/tui-base-reports-original-6fb.input.txt") ++
            "\nif(JSON.stringify(tuiBaseReports)!==JSON.stringify(internalBaseReportSource.cases))throw Error(JSON.stringify({actual:tuiBaseReports,expected:internalBaseReportSource.cases}));",
        "tui-base-reports-source-replay.mjs",
    ) catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TuiBase report Source mismatch: {s}\n", .{message});
        return err;
    };
    defer engine.freeValue(promise);
    const result = engine.awaitValue(promise) catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TuiBase report continuation mismatch: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}

test "Source6fb internal TuiBase focused hardware cursor Sourceea captures preserve wide astral truncated and unfocused text" {
    const engine = try setup();
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const expected = @embedFile("fixtures/tui-focused-fake-cursor-original-ea.json");
    try js.define(engine, root, "internalFocusedCursorSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-focused-fake-cursor-original-ea.json")));
    const result = engine.evalModule(
        "import * as tui from 'pi-tui';const TuiBase=globalThis.internalTuiBase;\n" ++ @embedFile("fixtures/tui-focused-fake-cursor-original-ea.input.txt") ++
            "\nif(tuiFocusedFakeCursorCases.length!==53)throw Error('focused cursor Source case count');for(let index=0;index<tuiFocusedFakeCursorCases.length;index++){const actual=tuiFocusedFakeCursorCases[index],expected=internalFocusedCursorSource.cases[index];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index,actual,expected}));}",
        "tui-focused-fake-cursor-source-replay.mjs",
    ) catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TuiBase focused cursor Source mismatch: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
