//! Actual latest Source TuiAltScreen method-body and lifecycle captures.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
fn setup(gpa: std.mem.Allocator) !*js.Engine {
    const engine = try js.Engine.init(gpa, .{});
    errdefer engine.deinit();
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"tui-alt-source"});
    // SDK startup wiring calls this same native host API. This private Source
    // target invokes it explicitly without modifying the SDK-owned producer.
    try @import("native_process_clock.zig").installDefaultGlobal(engine);
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    const exports = engine.native_module_values.get("pi-tui") orelse return error.NativeTuiUnavailable;
    const base = try @import("native_tui_base.zig").create(engine, exports);
    defer engine.freeValue(base);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeTuiAltScreen", try @import("native_tui_alt_screen.zig").create(engine, exports, base));
    try js.define(engine, root, "nativeTuiExports", c.JS_DupValue(engine.context, exports));
    return engine;
}
test "Sourceea native TuiAltScreen complete ordinary fields metadata lifecycle renderer mouse search Unicode and timers" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const expected = @embedFile("fixtures/tui-alt-screen-original-ea.json");
    try js.define(engine, root, "altSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-alt-screen-original-ea.json")));
    const result = engine.evalModule("const TuiAltScreen=nativeTuiAltScreen,tui=nativeTuiExports;\n" ++ @embedFile("fixtures/tui-alt-screen-original-ea.input.txt") ++ "\nfor(let i=0;i<tuiAltScreenCases.length;i++)if(JSON.stringify(tuiAltScreenCases[i])!==JSON.stringify(altSource.cases[i]))throw Error(JSON.stringify({case:i,actual:tuiAltScreenCases[i],expected:altSource.cases[i]}));if(tuiAltScreenCases.length!==altSource.cases.length)throw Error('case count');", "tui-alt-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Alt Source mismatch: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Sourceea native TuiAltScreen actual asynchronous clipboard native Buffer adoption and rejection identity" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const expected = @embedFile("fixtures/tui-alt-clipboard-original-ea.json");
    try js.define(engine, root, "clipboardSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-alt-clipboard-original-ea.json")));
    const pending = engine.evalModule("const TuiAltScreen=nativeTuiAltScreen;\n" ++ @embedFile("fixtures/tui-alt-clipboard-original-ea.input.txt") ++ "\nif(JSON.stringify(tuiAltClipboardCases)!==JSON.stringify(clipboardSource.cases))throw Error(JSON.stringify({actual:tuiAltClipboardCases,expected:clipboardSource.cases}));", "tui-alt-clipboard-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Alt clipboard Source mismatch: {s}\n", .{message});
        return err;
    };
    defer engine.freeValue(pending);
    const result = engine.awaitValue(pending) catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Alt clipboard continuation: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Sourceea native TuiAltScreen ordinary array method getter callback capture iterator close and ambient clock authority" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const expected = @embedFile("fixtures/tui-alt-array-authority-original-ea.json");
    try js.define(engine, root, "arrayAuthoritySource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "tui-alt-array-authority-original-ea.json")));
    const result = engine.evalModule("const TuiAltScreen=nativeTuiAltScreen,tui=nativeTuiExports;\n" ++ @embedFile("fixtures/tui-alt-array-authority-original-ea.input.txt") ++ "\nfor(let i=0;i<tuiAltArrayAuthorityCases.length;i++)if(JSON.stringify(tuiAltArrayAuthorityCases[i])!==JSON.stringify(arrayAuthoritySource.cases[i]))throw Error(JSON.stringify({case:i,actual:tuiAltArrayAuthorityCases[i],expected:arrayAuthoritySource.cases[i]}));if(tuiAltArrayAuthorityCases.length!==arrayAuthoritySource.cases.length)throw Error('case count');", "tui-alt-array-authority-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Alt array authority Source mismatch: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try setup(gpa);
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule("const t=new nativeTuiAltScreen({columns:12,rows:3,write(){}},false,undefined,{mouse:false});t.requestRender=()=>{};t.addChild({render(){return ['one','two','three','four']},invalidate(){}});t.beforeTerminalStart();t.doRender();t.selectionAnchor={row:0,col:0};t.selectionFocus={row:1,col:1};t.getActiveSelectionText();t.applySelection(t.previousScreen);t.beforeTerminalStop({});t.afterTerminalStop({preserveScreen:true});", "tui-alt-owned-allocation.mjs") catch |err| {
        const actual = engine.nativeAllocationError(err, generation);
        if (actual != error.OutOfMemory) {
            std.debug.print("Native Alt allocation probe unexpected {s}; native generation {d}->{d}\n", .{ @errorName(actual), generation, engine.native_allocation_generation });
            if (engine.captured_exception) |exception| {
                const original = c.JS_DupValue(engine.context, exception);
                defer engine.freeValue(original);
                // VM-owned C storage is independent of the induced Zig GPA
                // failure. This is diagnostic only; it never classifies OOM.
                const text = c.JS_ToCString(engine.context, original);
                if (text != null) {
                    defer c.JS_FreeCString(engine.context, text);
                    std.debug.print("Original captured exception: {s}\n", .{std.mem.span(text)});
                }
            }
            var allocator_type = std.testing.FailingAllocator.init(std.testing.allocator, .{});
            const known = allocator_type.allocator();
            if (gpa.vtable.alloc == known.vtable.alloc and gpa.vtable.free == known.vtable.free) {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                std.debug.print("Failing allocator index={d}, current={d}, induced={}\n", .{ failing.fail_index, failing.alloc_index, failing.has_induced_failure });
                if (failing.has_induced_failure) std.debug.print("Original failing allocation stack:\n{f}\n", .{std.debug.FormatStackTrace{ .stack_trace = failing.getStackTrace() }});
            }
        }
        return actual;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "Sourceea native TuiAltScreen original Node global clock ordinary accessors shared imported identity and replacement" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeImportedPerformance", try @import("native_process_clock.zig").performance(engine));
    const expected = @embedFile("fixtures/node-global-performance-original-24.json");
    try js.define(engine, root, "clockSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "node-global-performance-original-24.json")));
    const result = engine.evalModule("const imported=nativeImportedPerformance;\n" ++ @embedFile("fixtures/node-global-performance-original-24.input.txt") ++ "\nif(JSON.stringify(nodeGlobalPerformanceCases)!==JSON.stringify(clockSource.cases))throw Error(JSON.stringify({actual:nodeGlobalPerformanceCases,expected:clockSource.cases}));", "node-global-performance-original-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native global clock Source mismatch: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
    try @import("native_process_clock.zig").installDefaultGlobal(engine);
    const replaced = try engine.eval("if(globalThis.performance!==17)throw Error('startup API replaced guest value');delete globalThis.performance;", "clock-global-replacement.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(replaced);
    try @import("native_process_clock.zig").installDefaultGlobal(engine);
    const missing = try engine.eval("if(Object.hasOwn(globalThis,'performance'))throw Error('startup API recreated guest deletion');", "clock-global-deletion.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(missing);
}
test "Sourceea native TuiAltScreen constructor layout renderer selection and disposal release every induced allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
test "Sourceea native TuiAltScreen native OOM mapping rejects user lookalikes and stale native exceptions" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const before = engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, engine.checked(@import("native_tui_alt_frame.zig").fail(engine, error.OutOfMemory)));
    try std.testing.expectEqual(error.OutOfMemory, engine.nativeAllocationError(error.JavaScriptException, before));
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "savedNativeOom", c.JS_DupValue(engine.context, engine.captured_exception orelse return error.MissingNativeOom));
    const after = engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, engine.eval("throw savedNativeOom", "stale-native-oom.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(error.JavaScriptException, engine.nativeAllocationError(error.JavaScriptException, after));
    try std.testing.expectError(error.JavaScriptException, engine.eval("throw {name:'OutOfMemory',message:'out of memory'}", "user-oom-lookalike.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(error.JavaScriptException, engine.nativeAllocationError(error.JavaScriptException, after));
    try std.testing.expectEqual(after, engine.native_allocation_generation);
}
test "Sourceea native TuiAltScreen clock startup preserves intervening guest descriptors values and deletion" {
    for ([_][]const u8{
        "globalThis.performance={guest:true};globalThis.checkClock=()=>performance.guest===true",
        "const original=performance;const getter=()=>original;Object.defineProperty(globalThis,'performance',{get:getter,configurable:true,enumerable:false});globalThis.checkClock=()=>Object.getOwnPropertyDescriptor(globalThis,'performance').get===getter",
        "delete globalThis.performance;globalThis.checkClock=()=>!Object.hasOwn(globalThis,'performance')",
        "Object.defineProperty(globalThis,'performance',{enumerable:false});globalThis.checkClock=()=>Object.getOwnPropertyDescriptor(globalThis,'performance').enumerable===false",
    }) |source| {
        const engine = try js.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        var environment: std.process.Environ.Map = .init(std.testing.allocator);
        defer environment.deinit();
        try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"clock-startup-guest"});
        const changed = try engine.eval(source, "clock-before-default-install.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(changed);
        try @import("native_process_clock.zig").installDefaultGlobal(engine);
        const checked = try engine.eval("if(!checkClock())throw Error('startup replaced guest clock authority')", "clock-after-default-install.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(checked);
    }
}
