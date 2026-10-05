const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const bindings_mod = @import("extensions/native_bindings.zig");
const editor_protocol = @import("extensions/editor_protocol.zig");
const c = engine_mod.c;

test "native editor original upstream modal input retains exact source bytes" {
    const fixture = @import("test_support/upstream_modal_editor_031b.zig");
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(fixture.source, &digest, .{});
    const encoded = std.fmt.bytesToHex(digest, .lower);
    try std.testing.expectEqualStrings(fixture.source_sha256, &encoded);
}

test "native editor factory survives invocation GC forwards submit change restores draft and retires owner" {
    const gpa = std.testing.allocator;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const binding = try bindings_mod.Bindings.init(gpa, engine);
    var live = true;
    defer if (live) binding.deinit();
    try binding.installSchemas();
    const Capture = struct {
        records: std.ArrayList(editor_protocol.Record) = .empty,
        fn record(raw: ?*anyopaque, value: editor_protocol.Record) !void {
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
    binding.ui_manager.editors.record_fn = Capture.record;
    binding.ui_manager.editors.record_context = &capture;
    // These are user extension inputs, executed entirely in linked QuickJS.
    try binding.loadFactory(
        \\import {CustomEditor} from 'pi-coding-agent';import {Editor} from 'pi-tui';
        \\globalThis.disposed=0;globalThis.changed=0;
        \\class InputEditor extends CustomEditor {render(w){return ['CUSTOM:'+w,...super.render(w)]}dispose(){disposed++}}
        \\export default pi=>{pi.on('headless',(_,ctx)=>{globalThis.headlessContext=ctx;globalThis.headlessUi=ctx.ui});pi.on('install',(_,ctx)=>{globalThis.savedContext=ctx;globalThis.savedUi=ctx.ui;const factory=(t,th,k)=>{const editor=new InputEditor(t,th,k);globalThis.editor=editor;return editor};globalThis.createAgain=factory;ctx.ui.setEditorComponent(factory);if(ctx.ui.getEditorComponent()!==factory)throw Error('factory identity');if(!(editor instanceof Editor)||!(editor instanceof CustomEditor))throw Error('constructor chain');});}
    , "editor-owner-input.mjs");
    try binding.setContext("{\"hasUI\":false}");
    const captured_headless = try binding.invokeHook("headless", "{}");
    defer gpa.free(captured_headless);
    try binding.setContext("{\"hasUI\":true,\"editorText\":\"draft Ω\",\"width\":55,\"height\":22}");
    const response = try binding.invokeHook("install", "{}");
    defer gpa.free(response);
    const manager = &binding.ui_manager.editors;
    try std.testing.expect(!binding.invocation_active and manager.component != null);
    try std.testing.expectEqualStrings("draft Ω", capture.records.items[0].kind.frame.text);
    try std.testing.expectEqualStrings("CUSTOM:55", capture.records.items[0].kind.frame.frame.lines[0]);
    const headless_stays_headless = try engine.evalModule("headlessContext.ui.setEditorComponent(undefined);headlessUi.setEditorText('forbidden');headlessUi.pasteToEditor('forbidden');if(headlessContext.ui.getEditorComponent()!==undefined||headlessContext.ui.getEditorText()!==''||savedContext.ui.getEditorText()!=='draft Ω')throw Error('headless capability gained UI');", "headless-editor-capability-input.mjs");
    defer engine.freeValue(headless_stays_headless);
    c.JS_RunGC(engine.runtime);
    const fence = capture.records.items[0].fence;
    var input: editor_protocol.Control = .{ .gpa = gpa, .fence = fence, .kind = .{ .input = try gpa.dupe(u8, "🦊") } };
    defer input.deinit();
    try std.testing.expect(try manager.control(input));
    try std.testing.expectEqualStrings("draft Ω🦊", capture.records.items[capture.records.items.len - 1].kind.frame.text);
    var move_left: editor_protocol.Control = .{ .gpa = gpa, .fence = fence, .kind = .{ .input = try gpa.dupe(u8, "\x1b[D") } };
    defer move_left.deinit();
    try std.testing.expect(try manager.control(move_left));
    try std.testing.expectEqual(@as(usize, "draft Ω".len), capture.records.items[capture.records.items.len - 1].kind.frame.cursor);
    var submit: editor_protocol.Control = .{ .gpa = gpa, .fence = fence, .kind = .{ .input = try gpa.dupe(u8, "\r") } };
    defer submit.deinit();
    try std.testing.expect(try manager.control(submit));
    try std.testing.expectEqualStrings("draft Ω🦊", capture.records.items[capture.records.items.len - 2].kind.submit);
    try std.testing.expectEqualStrings("", capture.records.items[capture.records.items.len - 1].kind.frame.text);
    var paste: editor_protocol.Control = .{ .gpa = gpa, .fence = fence, .kind = .{ .paste = try gpa.dupe(u8, "restored Ω") } };
    defer paste.deinit();
    try std.testing.expect(try manager.control(paste));
    const restore = try engine.evalModule("globalThis.savedSubmit=editor.onSubmit;globalThis.savedTui=editor;savedUi.setEditorComponent(undefined);if(savedUi.getEditorComponent()!==undefined||disposed!==1)throw Error('restore/dispose');", "restore-editor-input.mjs");
    defer engine.freeValue(restore);
    try std.testing.expectEqualStrings("restored Ω", capture.records.items[capture.records.items.len - 1].kind.retire);
    try std.testing.expect(!try manager.control(input));
    const count = capture.records.items.len;
    const old_callback = try engine.evalModule("savedSubmit('late')", "late-editor-input.mjs");
    defer engine.freeValue(old_callback);
    try std.testing.expectEqual(count, capture.records.items.len);
    const reinstall = try engine.evalModule("savedUi.setEditorComponent(createAgain)", "reinstall-editor-input.mjs");
    defer engine.freeValue(reinstall);
    try std.testing.expectEqualStrings("restored Ω", capture.records.items[capture.records.items.len - 1].kind.frame.text);
    const retained_text = try engine.evalModule("savedUi.setEditorText('updated Ω');savedUi.pasteToEditor('🦊');if(savedUi.getEditorText()!=='updated Ω🦊')throw Error('retained UI text')", "retained-editor-text-input.mjs");
    defer engine.freeValue(retained_text);
    try std.testing.expectEqualStrings("updated Ω🦊", capture.records.items[capture.records.items.len - 1].kind.frame.text);
    try binding.setContext("{\"hasUI\":false}");
    const no_ui_event = try binding.invokeHook("other-context", "{}");
    defer gpa.free(no_ui_event);
    const retained_restore = try engine.evalModule("savedContext.ui.setEditorComponent(undefined);if(savedContext.ui.getEditorComponent()!==undefined||disposed!==2)throw Error('retained hasUI capability')", "retained-editor-ui-capability.mjs");
    defer engine.freeValue(retained_restore);
    try std.testing.expect(binding.ui_manager.editors.component == null);
    binding.deinit();
    live = false;
    c.JS_RunGC(engine.runtime);
    const stale = try engine.evalModule("let stale=false;try{savedUi.setEditorComponent(()=>savedTui)}catch(e){stale=true}if(!stale||disposed!==2)throw Error('stale editor owner/disposal');savedSubmit('after-destroy');", "destroyed-editor-input.mjs");
    defer engine.freeValue(stale);
}

fn editorProtocolAllocationCase(gpa: std.mem.Allocator) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, "{\"type\":\"editor_frame\",\"version\":1,\"ownerGeneration\":\"3\",\"extensionId\":\"2\",\"editorGeneration\":\"1\",\"sequence\":\"4\",\"width\":55,\"text\":\"owned Ω🦊\",\"lines\":[\"top\",\"owned Ω🦊\",\"bottom\"]}", .{});
    defer parsed.deinit();
    var record = try editor_protocol.read(gpa, &parsed.value.object);
    defer record.deinit();
    var copied = try record.clone(gpa);
    defer copied.deinit();
    var writer: std.Io.Writer.Allocating = .init(gpa);
    defer writer.deinit();
    editor_protocol.write(&writer.writer, copied) catch return error.OutOfMemory;
    var reparsed = try std.json.parseFromSlice(std.json.Value, gpa, writer.written(), .{});
    defer reparsed.deinit();
    var roundtrip = try editor_protocol.read(gpa, &reparsed.value.object);
    defer roundtrip.deinit();
    try std.testing.expectEqualStrings("owned Ω🦊", roundtrip.kind.frame.text);
    var controls = editor_protocol.ControlQueue.init(gpa, std.testing.io, 3);
    defer controls.deinit();
    var control: editor_protocol.Control = .{ .gpa = gpa, .fence = record.fence, .kind = .{ .input = try gpa.dupe(u8, "Ω🦊") } };
    var transferred = false;
    defer if (!transferred) control.deinit();
    try controls.send(control);
    transferred = true;
    var received = (try controls.next()).?;
    defer received.deinit();
    try std.testing.expectEqualStrings("Ω🦊", received.kind.input);
    controls.stop();
    try std.testing.expectError(error.EditorMailboxStopped, controls.send(received));
}
test "native editor protocol owns copied Unicode frames controls and every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, editorProtocolAllocationCase, .{});
    for ([_][]const u8{ "{\"version\":2}", "{\"version\":1,\"type\":\"editor_frame\",\"ownerGeneration\":0}", "{\"version\":1,\"type\":\"editor_submit\",\"ownerGeneration\":\"1\",\"extensionId\":\"2\",\"editorGeneration\":\"3\",\"sequence\":\"4\",\"text\":[]} " }) |raw| {
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, raw, .{});
        defer parsed.deinit();
        if (editor_protocol.read(std.testing.allocator, &parsed.value.object)) |value| {
            var owned = value;
            owned.deinit();
            return error.InvalidEditorRecordAdmitted;
        } else |_| {}
    }
}

test "native editor rejected factory and first render unwind component and factory roots exactly once" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const binding = try bindings_mod.Bindings.init(std.testing.allocator, engine);
    defer binding.deinit();
    try binding.installSchemas();
    try binding.loadFactory("globalThis.disposals=0;export default pi=>pi.on('fail',(_,ctx)=>{const original=new Error('editor-original');let saw=false;try{ctx.ui.setEditorComponent(()=>({getText(){return 'draft'},setText(){},handleInput(){},render(){throw original},dispose(){disposals++}}))}catch(error){saw=error===original}if(!saw||disposals!==1||ctx.ui.getEditorComponent()!==undefined)throw Error('editor setup unwind');return {message:'unwound'}})", "editor-failed-factory.mjs");
    try binding.setContext("{\"hasUI\":true}");
    const result = try binding.invokeHook("fail", "{}");
    defer std.testing.allocator.free(result);
    try std.testing.expect(binding.ui_manager.editors.component == null and binding.ui_manager.editors.factory == null);
    c.JS_RunGC(engine.runtime);
}

test "native editor branded methods subclass overrides callbacks Unicode movement and history" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/native_tui.zig").install(engine);
    const module = engine.evalModule(
        \\import {Editor} from 'pi-tui';import {CustomEditor} from 'pi-coding-agent';
        \\let changes=[];let submissions=[];class Derived extends CustomEditor{handleInput(v){if(v==='!')return super.handleInput('Ω');super.handleInput(v)}}
        \\const editor=new Derived({}, {}, {});editor.onChange=text=>changes.push(text);editor.onSubmit=text=>submissions.push(text);editor.setText('a🦊');editor.handleInput('\x1b[D');editor.handleInput('!');if(editor.getText()!=='aΩ🦊')throw Error('scalar movement');editor.handleInput('\r');if(submissions.join()!=='aΩ🦊'||editor.getText()!=='')throw Error('submit');editor.handleInput('\x1b[A');if(editor.getText()!=='aΩ🦊')throw Error('history');if(changes.length<3||editor.render(40).length<3)throw Error('change/render');let branded=false;try{Editor.prototype.getText.call({})}catch(e){branded=e instanceof TypeError}if(!branded)throw Error('brand');
    , "editor-class-input.mjs") catch |err| {
        std.debug.print("Editor class error: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
}
