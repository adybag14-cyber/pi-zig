const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
fn defaultClone(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return @import("native_structured_clone.zig").clone(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowOutOfMemory(context);
    };
}
test "Source6fb public Editor full input dispatch paste kitty history completion and global bindings" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-full-input-original-6fb.json");
    try js.define(engine, global, "editorFullInputSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-full-input-original-6fb.json")));
    const result = engine.evalModule("import{Editor,getKeybindings,setKeybindings}from'pi-tui';\n" ++ @embedFile("fixtures/editor-full-input-original-6fb.input.txt") ++
        \\for(let i=0;i<editorFullInputSource.cases.length;i++){const actual=editorFullInputResult[i],expected=editorFullInputSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-full-input.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor full input: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor CustomEditor exact shape working status app overrides and callback receivers" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/custom-editor-original-6fb.json");
    try js.define(engine, global, "customEditorSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "custom-editor-original-6fb.json")));
    const result = engine.evalModule("import{CustomEditor}from'pi-coding-agent';\n" ++ @embedFile("fixtures/custom-editor-original-6fb.input.txt") ++
        \\for(let i=0;i<customEditorSource.cases.length;i++){const actual=customEditorResult[i],expected=customEditorSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-custom.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public CustomEditor: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor deletion graphemes marker renumber word kills and undo coalescing" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-deletion-original-6fb.json");
    try js.define(engine, global, "editorDeletionSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-deletion-original-6fb.json")));
    const result = engine.evalModule("import {Editor} from 'pi-tui';\n" ++ @embedFile("fixtures/editor-deletion-original-6fb.input.txt") ++
        \\for(let i=0;i<editorDeletionSource.cases.length;i++){const actual=editorDeletionResult[i],expected=editorDeletionSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-deletion.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor deletion: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor movement words graphemes jumps and virtual segmenters" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-movement-original-6fb.json");
    try js.define(engine, global, "editorMovementSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-movement-original-6fb.json")));
    const result = engine.evalModule("import {Editor} from 'pi-tui';\n" ++ @embedFile("fixtures/editor-movement-original-6fb.input.txt") ++
        \\for(let i=0;i<editorMovementSource.cases.length;i++){const actual=editorMovementResult[i],expected=editorMovementSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-movement.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor movement: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor autocomplete original async serialization abort stale results and selection" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-autocomplete-original-6fb.json");
    try js.define(engine, global, "editorAutocompleteSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-autocomplete-original-6fb.json")));
    const result = engine.evalModule("import {Editor} from 'pi-tui';\n" ++ @embedFile("fixtures/editor-autocomplete-original-6fb.input.txt") ++
        \\for(let i=0;i<editorAutocompleteSource.cases.length;i++){const actual=editorAutocompleteResult[i],expected=editorAutocompleteSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-autocomplete.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor autocomplete: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor navigation mouse hit testing vertical snap and page scroll" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-navigation-original-6fb.json");
    try js.define(engine, global, "editorNavigationSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-navigation-original-6fb.json")));
    const result = engine.evalModule("import {Editor} from 'pi-tui';\n" ++ @embedFile("fixtures/editor-navigation-original-6fb.input.txt") ++
        \\for(let i=0;i<editorNavigationSource.cases.length;i++){const actual=editorNavigationResult[i],expected=editorNavigationSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-navigation.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor navigation: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
fn retireCursorCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var class: u32 = 0;
    if (c.JS_ToUint32(context, &class, data[1]) < 0) return engine.throwCaptured();
    const manager: *@import("native_editor.zig").Manager = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], class).?));
    manager.retire() catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowOutOfMemory(context);
    };
    return c.pi_js_undefined();
}
test "Source6fb public Editor render manager publishes ordinary cursor and rejects retired getter frame" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-owner"});
    try @import("native_tui.zig").install(engine);
    const protocol = @import("editor_protocol.zig");
    const Capture = struct {
        records: std.ArrayList(protocol.Record) = .empty,
        fn record(raw: ?*anyopaque, value: protocol.Record) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var owned = try value.clone(std.testing.allocator);
            errdefer owned.deinit();
            try self.records.append(std.testing.allocator, owned);
        }
        fn deinit(self: *@This()) void {
            for (self.records.items) |*value| value.deinit();
            self.records.deinit(std.testing.allocator);
        }
    };
    var capture: Capture = .{};
    defer capture.deinit();
    var manager = try @import("native_editor.zig").Manager.init(engine);
    defer manager.deinit();
    manager.attach();
    try manager.addOwner(1);
    manager.record_fn = Capture.record;
    manager.record_context = &capture;
    const setup = try engine.evalModule("import{Editor}from'pi-tui';globalThis.editorFactory=(t,th)=>{globalThis.ownedEditor=new Editor(t,th);return ownedEditor;};", "editor-owner-source-setup.mjs");
    engine.freeValue(setup);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const factory = try js.get(engine, global, "editorFactory");
    defer engine.freeValue(factory);
    const draft = try engine.checked(c.JS_NewString(engine.context, "A界B\nXY"));
    defer engine.freeValue(draft);
    try manager.setFactory(1, factory, draft, c.pi_js_undefined(), c.pi_js_undefined(), 20, 10);
    try std.testing.expectEqual(@as(usize, "A界B\nXY".len), capture.records.items[0].kind.frame.cursor);
    const move = try engine.evalModule("ownedEditor.state.cursorLine=0;ownedEditor.state.cursorCol=1;", "editor-owner-source-move.mjs");
    engine.freeValue(move);
    manager.dirty = true;
    try std.testing.expect(try manager.pumpDirty());
    try std.testing.expectEqual(@as(usize, 1), capture.records.items[capture.records.items.len - 1].kind.frame.cursor);
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Editor cursor owner test", .finalizer = null, .gc_mark = null, .call = null, .exotic = null };
    try std.testing.expect(c.JS_NewClass(engine.runtime, class, &definition) >= 0);
    const token = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(class)));
    defer engine.freeValue(token);
    _ = c.JS_SetOpaque(token, &manager);
    var data = [_]c.JSValue{ token, c.JS_NewInt64(engine.context, class) };
    try js.define(engine, global, "retireCursor", try engine.checked(c.JS_NewCFunctionData2(engine.context, retireCursorCallback, "retireCursor", 0, 0, data.len, &data)));
    const hook = try engine.evalModule("const original=ownedEditor.render;ownedEditor.render=function(width){const frame=original.call(this,width);Object.defineProperty(this.state,'cursorCol',{configurable:true,get(){retireCursor();return 0;}});return frame;};", "editor-owner-source-getter.mjs");
    engine.freeValue(hook);
    const before = capture.records.items.len;
    manager.dirty = true;
    try std.testing.expect(!try manager.pumpDirty());
    try std.testing.expect(manager.component == null);
    try std.testing.expectEqual(before + 1, capture.records.items.len);
    try std.testing.expect(std.meta.activeTag(capture.records.items[capture.records.items.len - 1].kind) == .retire);
}
test "Source6fb public Editor render border padding scroll cursor and virtual list" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-render-original-6fb.json");
    try js.define(engine, global, "editorRenderSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-render-original-6fb.json")));
    const result = engine.evalModule("import {Editor} from 'pi-tui';\n" ++ @embedFile("fixtures/editor-render-original-6fb.input.txt") ++
        \\for(let i=0;i<editorRenderSource.cases.length;i++){const actual=editorRenderResult[i],expected=editorRenderSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-render.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor render: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor visual wrap layout maps lookup and sticky columns" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-visual-original-6fb.json");
    try js.define(engine, global, "editorVisualSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-visual-original-6fb.json")));
    const result = engine.evalModule("import {Editor} from 'pi-tui';\n" ++ @embedFile("fixtures/editor-visual-original-6fb.input.txt") ++
        \\for(let i=0;i<editorVisualSource.cases.length;i++){const actual=editorVisualResult[i],expected=editorVisualSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-visual.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor visual: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor kills line boundaries ordinary ring and yank callbacks" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-kills-original-6fb.json");
    try js.define(engine, global, "editorKillsSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-kills-original-6fb.json")));
    const result = engine.evalModule("import {Editor} from 'pi-tui';\n" ++ @embedFile("fixtures/editor-kills-original-6fb.input.txt") ++
        \\for(let i=0;i<editorKillsSource.cases.length;i++){const actual=editorKillsResult[i],expected=editorKillsSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-kills.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor kills: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor segments native iterables containing and atomic markers" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-segments-original-6fb.json");
    try js.define(engine, global, "editorSegmentsSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-segments-original-6fb.json")));
    const result = engine.evalModule("import {Editor} from 'pi-tui';\n" ++ @embedFile("fixtures/editor-segments-original-6fb.input.txt") ++
        \\for(let i=0;i<editorSegmentsSource.cases.length;i++){const actual=editorSegmentsResult[i],expected=editorSegmentsSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-segments.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor segments: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor paste cleanup markers newline and ordered submission" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-paste-original-6fb.json");
    try js.define(engine, global, "editorPasteSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-paste-original-6fb.json")));
    const result = engine.evalModule("import {Editor} from 'pi-tui';\n" ++ @embedFile("fixtures/editor-paste-original-6fb.input.txt") ++
        \\for(let i=0;i<editorPasteSource.cases.length;i++){const actual=editorPasteResult[i],expected=editorPasteSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-paste.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor paste: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor history draft cursor clone callbacks and undo" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeDefaultClone", try engine.checked(c.pi_js_function_magic(engine.context, defaultClone, "structuredClone", 1, 0)));
    const bytes = @embedFile("fixtures/editor-history-original-6fb.json");
    try js.define(engine, global, "editorHistorySource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-history-original-6fb.json")));
    const result = engine.evalModule("import {Editor} from 'pi-tui';\n" ++ @embedFile("fixtures/editor-history-original-6fb.input.txt") ++
        \\for(let i=0;i<editorHistorySource.cases.length;i++){const actual=editorHistoryResult[i],expected=editorHistorySource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-history.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor history: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor core ordinary fields aliases callbacks and undo" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-core-fields-original-6fb.json");
    try js.define(engine, global, "editorCoreSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-core-fields-original-6fb.json")));
    const result = engine.evalModule("import {Editor} from 'pi-tui';\n" ++ @embedFile("fixtures/editor-core-fields-original-6fb.input.txt") ++
        \\for(let i=0;i<editorCoreSource.cases.length;i++){const actual=editorCoreResult[i],expected=editorCoreSource.cases[i];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index:i,actual,expected}));}
    , "editor-source-core-fields.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor core fields: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Editor core normalization options and UTF16 edit snapshots" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-public-original-6fb.json");
    try js.define(engine, global, "editorSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-public-original-6fb.json")));
    const result = engine.evalModule(
        \\import{Editor}from'pi-tui';const make=options=>{let requests=0;const tui={terminal:{columns:80,rows:24},requestRender(){requests++}},identity=text=>text,theme={borderColor:identity,selectList:{selectedPrefix:identity,selectedText:identity,description:identity,scrollInfo:identity,noMatch:identity}},editor=new Editor(tui,theme,options);return{editor,requests:()=>requests}},snapshot=(editor,requests)=>({text:editor.getText(),expanded:editor.getExpandedText(),lines:editor.getLines(),cursor:editor.getCursor(),padding:editor.getPaddingX(),maxVisible:editor.getAutocompleteMaxVisible(),requests:requests()});for(const[index,item]of editorSource.cases.entries()){const{editor,requests}=make({}),changes=[],snapshots=[snapshot(editor,requests)];editor.onChange=value=>changes.push(value);for(const[name,arg]of item.operations){try{editor[name](arg);snapshots.push(snapshot(editor,requests))}catch(error){snapshots.push({errorName:error.name,errorMessage:error.message})}}if(JSON.stringify(snapshots)!==JSON.stringify(item.snapshots)||JSON.stringify(changes)!==JSON.stringify(item.changes))throw Error(JSON.stringify({index,snapshots,changes,expected:item}));}for(const[index,item]of editorSource.options.entries()){const value=item.value?.undefined?undefined:item.value?.nan?NaN:item.value?.infinity?Infinity:item.value,{editor,requests}=make({paddingX:value,autocompleteMaxVisible:value}),initial=snapshot(editor,requests);editor.setPaddingX(value);editor.setAutocompleteMaxVisible(value);const after=snapshot(editor,requests);if(JSON.stringify(initial)!==JSON.stringify(item.snapshot)||JSON.stringify(after)!==JSON.stringify(item.after))throw Error(JSON.stringify({option:index,initial,after,expected:item}));}
    , "editor-source-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}

test "Source6fb public Editor final class shape" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{"editor-source"});
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const bytes = @embedFile("fixtures/editor-public-original-6fb.json");
    try js.define(engine, global, "editorSource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "editor-public-original-6fb.json")));
    const result = engine.evalModule(
        \\import{Editor}from'pi-tui';const identity=text=>text,make=()=>({editor:new Editor({terminal:{columns:80,rows:24},requestRender(){}},{borderColor:identity})});const editor=make({}).editor,shape={name:Editor.name,length:Editor.length,own:Object.keys(editor),methods:Object.fromEntries(Object.getOwnPropertyNames(Editor.prototype).filter(k=>k!=='constructor').map(k=>[k,{name:Editor.prototype[k].name,length:Editor.prototype[k].length,enumerable:Object.getOwnPropertyDescriptor(Editor.prototype,k).enumerable}]))};if(JSON.stringify(shape)!==JSON.stringify(editorSource.shape))throw Error(JSON.stringify({shape,expected:editorSource.shape}));
    , "editor-source-final-shape.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native public Editor final shape: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
