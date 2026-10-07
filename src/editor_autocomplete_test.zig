const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const native_editor = @import("extensions/native_editor.zig");
const c = engine_mod.c;
fn completionOwnershipCase(gpa: std.mem.Allocator) !void {
    var editor = @import("tui/editor.zig").Editor.init(gpa);
    defer editor.deinit();
    try editor.setText("draft Ω🦊");
    editor.replaceWithUndo("replacement with substantially more bytes Ω🦊", 3) catch |err| {
        try std.testing.expectEqualStrings("draft Ω🦊", editor.slice());
        return err;
    };
    try editor.apply(.undo);
    try std.testing.expectEqualStrings("draft Ω🦊", editor.slice());
}
test "native autocomplete completion replacement preserves old draft and releases every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, completionOwnershipCase, .{});
    const conversion = @import("extensions/native_autocomplete.zig");
    try std.testing.expectEqual(@as(usize, 3), conversion.utf16Length("Ω🦊"));
    try std.testing.expectEqual(@as(usize, 2), try conversion.byteColumn("Ω🦊", 1));
    try std.testing.expectError(error.InvalidAutocompleteCursor, conversion.byteColumn("Ω🦊", 2));
    try std.testing.expectEqual(@as(usize, 6), try conversion.byteColumn("Ω🦊", 3));
}
fn input(engine: *engine_mod.Engine, source: []const u8, name: [:0]const u8) !void {
    const module = engine.evalModule(source, name) catch |err| {
        std.debug.print("Autocomplete input failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(module);
}
fn editorValue(engine: *engine_mod.Engine) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, "editor"));
}
test "native autocomplete async suggestions preserve UTF16 positions selection identity completion undo cancellation serial requests and retirement" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_tui.zig").install(engine);
    try input(engine,
        \\import {Editor} from 'pi-tui';globalThis.resolvers=[];globalThis.signals=[];globalThis.queries=[];globalThis.submits=[];globalThis.changes=[];globalThis.draws=0;
        \\globalThis.provider={getSuggestions(lines,line,col,options){queries.push([lines.join('\n'),line,col,options.force]);signals.push(options.signal);return new Promise(resolve=>resolvers.push(resolve))},applyCompletion(lines,line,col,item,prefix){globalThis.appliedItem=item;globalThis.appliedPrefix=prefix;const lineText='Ω🦊 '+item.value;return {lines:[lineText],cursorLine:0,cursorCol:lineText.length}}};
        \\globalThis.editor=new Editor({requestRender(){draws++}},{});editor.onSubmit=value=>submits.push(value);editor.onChange=value=>changes.push(value);editor.setAutocompleteProvider(provider);editor.setAutocompleteMaxVisible(2);editor.setText('@Ω🦊');editor.handleInput('\t');if(queries.length!==1||queries[0][2]!==4||!queries[0][3]||!(signals[0] instanceof AbortSignal))throw Error('query coordinates/signal');globalThis.first={value:'A',label:'Alpha'};globalThis.second={value:'B',label:'Beta',description:'two'};resolvers[0]({items:[first,second],prefix:'@'});
    , "autocomplete-query-input.mjs");
    _ = try engine.drainReadyJobs();
    const editor = try editorValue(engine);
    defer engine.freeValue(editor);
    try std.testing.expect(try native_editor.pollAutocomplete(engine, editor));
    try input(engine,
        \\if(!editor.isShowingAutocomplete()||!editor.render(40).join('|').includes('→ Alpha'))throw Error('menu');editor.handleInput('\x1b[B');if(!editor.render(40).join('|').includes('→ Beta'))throw Error('selection');editor.handleInput('\r');if(editor.getText()!=='Ω🦊 B'||editor.isShowingAutocomplete()||submits.length!==0||appliedItem!==second||appliedPrefix!=='@')throw Error('apply identity/submit');editor.handleInput('\x1b[45;5u');if(editor.getText()!=='@Ω🦊')throw Error('completion undo');editor.setText('race');editor.handleInput('\t');editor.setText('fresh');if(!signals[1].aborted)throw Error('abort');editor.handleInput('\t');if(queries.length!==2)throw Error('request overlap');resolvers[1]({items:[{value:'OLD',label:'Expired'}],prefix:''});
    , "autocomplete-selection-input.mjs");
    _ = try engine.drainReadyJobs();
    _ = try native_editor.pollAutocomplete(engine, editor);
    try input(engine,
        \\if(queries.length!==3||queries[2][0]!=='fresh'||editor.getText()!=='fresh'||editor.isShowingAutocomplete())throw Error('expired result');resolvers[2]({items:[{value:'C',label:'Current'}],prefix:''});
    , "autocomplete-stale-input.mjs");
    _ = try engine.drainReadyJobs();
    _ = try native_editor.pollAutocomplete(engine, editor);
    try input(engine,
        \\if(editor.getText()!=='Ω🦊 C'||editor.isShowingAutocomplete())throw Error('forced single');editor.setText('retire');editor.handleInput('\t');
    , "autocomplete-retirement-input.mjs");
    native_editor.retireAutocomplete(engine, editor);
    try input(engine,
        \\if(!signals[3].aborted)throw Error('retirement signal');resolvers[3]({items:[{value:'LATE',label:'Late'}],prefix:''});
    , "autocomplete-retired-result-input.mjs");
    _ = try engine.drainReadyJobs();
    try std.testing.expect(!try native_editor.pollAutocomplete(engine, editor));
    try input(engine, "if(editor.getText()!=='retire'||editor.isShowingAutocomplete())throw Error('retired mutation');", "autocomplete-retired-inspection.mjs");
    c.JS_RunGC(engine.runtime);
}

test "native autocomplete wrapper factories mount default editor preserve base commands and captured UI capabilities and remove owner roots" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const binding = try @import("extensions/native_bindings.zig").Bindings.init(std.testing.allocator, engine);
    var live = true;
    defer if (live) binding.deinit();
    try binding.installSchemas();
    try binding.loadFactory(
        \\export default pi=>{pi.on('headless',(_,ctx)=>{globalThis.headlessUi=ctx.ui});pi.on('setup',(_,ctx)=>{globalThis.savedUi=ctx.ui;ctx.ui.addAutocompleteProvider(current=>{globalThis.base=current;return {triggerCharacters:['%'],async getSuggestions(lines,line,col,options){if(lines[line].startsWith('%'))return {prefix:'%',items:[{value:'one',label:'Plugin One'},{value:'two',label:'Plugin Two'}]};return await current.getSuggestions(lines,line,col,options)},applyCompletion(...args){return current.applyCompletion(...args)}}});if(ctx.ui.getEditorComponent()!==undefined)throw Error('default factory facade')})};
    , "autocomplete-wrapper-input.mjs");
    try binding.setContext("{\"hasUI\":false}");
    const headless = try binding.invokeHook("headless", "{}");
    defer std.testing.allocator.free(headless);
    try binding.setContext("{\"hasUI\":true,\"width\":55,\"height\":22,\"editorText\":\"\",\"commands\":[{\"name\":\"alpha\",\"description\":\"base\"},{\"name\":\"alpine\"}]}");
    const installed = try binding.invokeHook("setup", "{}");
    defer std.testing.allocator.free(installed);
    const manager = &binding.ui_manager.editors;
    try std.testing.expect(manager.default_component and manager.component != null and manager.factory == null);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "editor", c.JS_DupValue(engine.context, manager.component.?)) < 0) return error.JavaScriptException;
    try input(engine, "globalThis.completed=[];editor.onSubmit=value=>completed.push(value);editor.setText('/a');editor.handleInput('\t');", "autocomplete-base-query.mjs");
    _ = try engine.drainReadyJobs();
    _ = try manager.pumpDirty();
    try input(engine, "if(!editor.isShowingAutocomplete()||!editor.render(55).join('|').includes('/alpha'))throw Error('base suggestions');editor.handleInput('\\x1b[B');editor.handleInput('\\r');if(completed[0]!=='/alpine')throw Error('slash completion submit');editor.setText('%');editor.handleInput('\\t');", "autocomplete-base-selection.mjs");
    _ = try engine.drainReadyJobs();
    _ = try manager.pumpDirty();
    try input(engine, "if(!editor.render(55).join('|').includes('Plugin One'))throw Error('wrapper menu');editor.handleInput('\x1b[B');editor.handleInput('\t');if(editor.getText()!=='two')throw Error('wrapped apply');headlessUi.addAutocompleteProvider(()=>{throw Error('headless gained UI')});", "autocomplete-wrapper-selection.mjs");
    try std.testing.expectEqual(@as(usize, 1), manager.autocomplete_wrappers.items.len);
    try binding.setContext("{\"hasUI\":false}");
    const unrelated = try binding.invokeHook("unrelated", "{}");
    defer std.testing.allocator.free(unrelated);
    try input(engine, "savedUi.setEditorText('retained');if(savedUi.getEditorText()!=='retained')throw Error('retained wrapped UI');", "autocomplete-retained-context.mjs");
    binding.deinit();
    live = false;
    try input(engine, "if(base.getSuggestions(['/a'],0,2,{})!==null)throw Error('retired base root');", "autocomplete-retired-base.mjs");
    c.JS_RunGC(engine.runtime);
}
