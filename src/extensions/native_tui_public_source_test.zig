const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
test "Source6fb public TUI slice column clipping style links markers and exact line composition" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/tui-columns-original-6fb.json");
    try js.define(engine, root, "tuiColumnSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "tui-columns-original-6fb.json")));
    const result = engine.evalModule("import{stripTerminalSequences,getOsc8LinkAtColumn,sliceByColumn,compositeTuiLine}from'pi-tui';\n" ++ @embedFile("fixtures/tui-columns-original-6fb.input.js") ++
        \\for(let i=0;i<tuiColumnSource.cases.length;i++){const actual=tuiColumnResults[i],expected=tuiColumnSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-columns-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TUI columns: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice helper regex literals ignore replaced global constructor" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("node_buffer.zig").install(engine);
    const replace = try engine.eval("globalThis.RegExp=function(){throw Error('global RegExp constructor used for literal')};", "tui-literal-global-input.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(replace);
    const exports = try js.object(engine);
    defer engine.freeValue(exports);
    try @import("native_tui_public_helpers.zig").install(engine, exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "literalHelperApi", c.JS_DupValue(engine.context, exports));
    const bytes = @embedFile("fixtures/tui-helper-literal-regexp-original-6fb.json");
    try js.define(engine, root, "literalHelperSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "tui-helper-literal-regexp-original-6fb.json")));
    const result = try engine.eval("const value={scheme:literalHelperApi.parseTerminalColorSchemeReport('\\x1b[?997;2n'),status:literalHelperApi.formatProgramStatus({state:'blocked',app:'pi',kind:'question',message:' a\\x00b '})};if(JSON.stringify(value)!==JSON.stringify(literalHelperSource.value))throw Error(JSON.stringify({value,expected:literalHelperSource.value}));", "tui-literal-global-result.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
}
test "Source6fb public TUI slice Image protocol rendering identity transcoder retry and bounded cache" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"tui-image-component"});
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/image-component-original-6fb.json");
    try js.define(engine, root, "imageComponentSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "image-component-original-6fb.json")));
    const result = engine.evalModule("import{Image,setImageTranscoder,setCapabilities,setCellDimensions}from'pi-tui';\n" ++ @embedFile("fixtures/image-component-original-6fb.input.js") ++
        \\for(let i=0;i<imageComponentSource.cases.length;i++){const actual=imageComponentResults[i],expected=imageComponentSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-image-component-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Image component: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice guards color scheme status UTF8 and public LaTeX entry point" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/tui-public-helpers-original-6fb.json");
    try js.define(engine, root, "tuiHelperSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "tui-public-helpers-original-6fb.json")));
    const result = engine.evalModule("import{isFocusable,isViewportTUI,parseTerminalColorSchemeReport,formatProgramStatus,renderLatex,isAppleTerminalSession}from'pi-tui';\n" ++ @embedFile("fixtures/tui-public-helpers-original-6fb.input.js") ++
        \\for(let i=0;i<tuiHelperSource.cases.length;i++){const actual=tuiHelperResults[i],expected=tuiHelperSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-public-helpers-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TUI helpers: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice Loader actual native timer owner callback stops and completes" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/loader-real-timer-original-6fb.json");
    try js.define(engine, root, "loaderRealSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "loader-real-timer-original-6fb.json")));
    const result = engine.evalModule("import{Loader}from'pi-tui';\n" ++ @embedFile("fixtures/loader-real-timer-original-6fb.input.js") ++
        \\if(JSON.stringify(loaderRealTimerResult)!==JSON.stringify(loaderRealSource.result))throw Error(JSON.stringify({actual:loaderRealTimerResult,expected:loaderRealSource.result}));
    , "tui-loader-real-timer-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Loader timer: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
    try std.testing.expect(!(try @import("timers.zig").pumpReady(engine)));
}
test "Source6fb public TUI slice Loader cancellation timers ordinary fields and inherited methods" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/loader-original-6fb.json");
    try js.define(engine, root, "loaderSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "loader-original-6fb.json")));
    const result = engine.evalModule("import{Loader,CancellableLoader,Text,getKeybindings,setKeybindings,KeybindingsManager,TUI_KEYBINDINGS}from'pi-tui';\n" ++ @embedFile("fixtures/loader-original-6fb.input.js") ++
        \\for(let i=0;i<loaderSource.cases.length;i++){const actual=loaderResults[i],expected=loaderSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-loader-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Loader: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI slice TruncatedText fields first line clipping padding and receivers" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/truncated-text-original-6fb.json");
    try js.define(engine, root, "truncatedTextSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "truncated-text-original-6fb.json")));
    const result = engine.evalModule("import{TruncatedText}from'pi-tui';\n" ++ @embedFile("fixtures/truncated-text-original-6fb.input.js") ++
        \\for(let i=0;i<truncatedTextSource.cases.length;i++){const actual=truncatedTextResults[i],expected=truncatedTextSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "tui-truncated-text-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native TruncatedText: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public TUI final namespace and prototype shape" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("fixtures/tui-public-surface-original-6fb.json");
    try js.define(engine, root, "tuiSurfaceSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "tui-public-surface-original-6fb.json")));
    const result = engine.evalModule(
        \\import*as tui from'pi-tui';const missing=[],differences=[],extra=Object.keys(tui).filter(n=>!tuiSurfaceSource.exports.some(x=>x.name===n));for(const item of tuiSurfaceSource.exports){const value=tui[item.name];if(value===undefined){missing.push(item.name);continue;}if(typeof value!==item.type)differences.push({name:item.name,type:typeof value,expected:item.type});if(item.type==='function'&&value.length!==item.length)differences.push({name:item.name,length:value.length,expected:item.length});if(item.prototype){const actual=value.prototype?Object.getOwnPropertyNames(value.prototype):null;const expected=item.prototype.map(x=>x.name);if(JSON.stringify(actual)!==JSON.stringify(expected))differences.push({name:item.name,prototype:actual,expected});}}if(missing.length||differences.length||extra.length)throw Error(JSON.stringify({missing,differences,extra}));
    , "tui-public-shape-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("TUI surface audit: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
