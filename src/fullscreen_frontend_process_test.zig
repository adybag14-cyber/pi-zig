//! Persistent fullscreen behavior observed in real offline CLI PTY screens.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/platform_pty.zig");
const vt = @import("test_support/terminal_screen.zig");
const Io = std.Io;

const Fixture = struct {
    scratch: pty.Scratch,
    environment: std.process.Environ.Map,
    binary: []u8,
    mock: []u8,
    history: []u8,
    fn init(mode: []const u8) !Fixture {
        const gpa = std.testing.allocator;
        const io = std.testing.io;
        var scratch = try pty.Scratch.init(gpa, io, "fullscreen");
        errdefer scratch.deinit();
        for ([_][]const u8{ "agent", "sessions", "home" }) |name| try scratch.dir.createDir(io, name, .default_dir);
        const settings = try std.fmt.allocPrint(gpa, "{{\"tuiMode\":\"{s}\",\"quietStartup\":true,\"enableInstallTelemetry\":false,\"retry\":{{\"enabled\":false}}}}", .{mode});
        defer gpa.free(settings);
        try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = settings });
        try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"stream-first\\nstream-second\\nstream-final\",\"stream_chunks\":[\"stream-first\\n\",\"stream-second\\n\",\"stream-final\"],\"stream_chunk_delay_ms\":400},{\"content\":\"second-first\\nsecond-final\",\"stream_chunks\":[\"second-first\\n\",\"second-final\"],\"stream_chunk_delay_ms\":1000}]" });
        var json: Io.Writer.Allocating = .init(gpa);
        defer json.deinit();
        try json.writer.writeAll("{\"type\":\"session\",\"version\":3,\"id\":\"fullscreen-history\",\"timestamp\":\"2026-10-05T00:00:00.000Z\",\"cwd\":");
        try std.json.Stringify.value(scratch.path, .{}, &json.writer);
        try json.writer.writeAll(",\"tipId\":\"entry59\"}\n");
        for (0..60) |index| {
            try json.writer.print("{{\"type\":\"message\",\"id\":\"entry{d}\",\"parentId\":", .{index});
            if (index == 0) try json.writer.writeAll("null") else try json.writer.print("\"entry{d}\"", .{index - 1});
            try json.writer.print(",\"timestamp\":\"2026-10-05T00:00:00.000Z\",\"message\":{{\"role\":\"user\",\"content\":[{{\"type\":\"text\",\"text\":\"history-row-{d:0>3}\"}}]}}}}\n", .{index});
        }
        // This inactive sibling must never appear in the active transcript.
        try json.writer.writeAll("{\"type\":\"message\",\"id\":\"inactive\",\"parentId\":\"entry0\",\"timestamp\":\"2026-10-05T00:00:00.000Z\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"inactive-history-forbidden\"}]}}\n");
        try scratch.dir.writeFile(io, .{ .sub_path = "history.jsonl", .data = json.written() });
        var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
        errdefer environment.deinit();
        const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse if (builtin.os.tag == .windows) "zig-out/bin/pi.exe" else "zig-out/bin/pi");
        errdefer gpa.free(binary);
        const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
        errdefer gpa.free(mock);
        const history = try std.fs.path.join(gpa, &.{ scratch.path, "history.jsonl" });
        errdefer gpa.free(history);
        const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
        defer gpa.free(agent);
        const home = try std.fs.path.join(gpa, &.{ scratch.path, "home" });
        defer gpa.free(home);
        try environment.put("PI_AGENT_DIR", agent);
        try environment.put("HOME", home);
        try environment.put("TERM", "xterm-256color");
        try environment.put("NO_COLOR", "1");
        try environment.put("PI_SKIP_VERSION_CHECK", "1");
        try environment.put("PI_TELEMETRY", "0");
        // Actual offline frontend must start and work with no Node on PATH.
        try environment.put("PATH", "/nonexistent-fullscreen-fixture-path");
        return .{ .scratch = scratch, .environment = environment, .binary = binary, .mock = mock, .history = history };
    }
    fn deinit(self: *Fixture) void {
        const gpa = std.testing.allocator;
        gpa.free(self.binary);
        gpa.free(self.mock);
        gpa.free(self.history);
        self.environment.deinit();
        self.scratch.deinit();
    }
    fn spawn(self: *Fixture, errors: Io.File) !pty.Session {
        return pty.spawn(std.testing.allocator, std.testing.io, .{
            .argv = &.{ self.binary, "--offline", "--mock-script", self.mock, "--session", self.history, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-extensions", "--no-tools", "--approve" },
            .cwd = .{ .path = self.scratch.path },
            .environ_map = &self.environment,
            .stderr = .{ .file = errors },
        }, 90_000);
    }
    fn spawnExtension(self: *Fixture, errors: Io.File, source: []const u8) !pty.Session {
        try self.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "component.mjs", .data = source });
        const path = try std.fs.path.join(std.testing.allocator, &.{ self.scratch.path, "component.mjs" });
        defer std.testing.allocator.free(path);
        try self.environment.put("PI_EXTENSION_BACKEND", "native");
        return pty.spawn(std.testing.allocator, std.testing.io, .{
            .argv = &.{ self.binary, "--offline", "--mock-script", self.mock, "--session", self.history, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-tools", "--approve", "-e", path },
            .cwd = .{ .path = self.scratch.path },
            .environ_map = &self.environment,
            .stderr = .{ .file = errors },
        }, 90_000);
    }
};

const custom_extension =
    \\export default function(pi) {
    \\ let starts=0,ends=0;
    \\ pi.on('ui_prompt_start',(_,ctx)=>{starts++;ctx.ui.setStatus('custom-life','start'+starts+'-end'+ends)});
    \\ pi.on('ui_prompt_end',(_,ctx)=>{ends++;ctx.ui.setStatus('custom-life','start'+starts+'-end'+ends)});
    \\ pi.registerCommand('component', {handler: async (_,ctx) => {
    \\  ctx.ui.setEditorText('component-draft');
    \\  let disposed=0;
    \\  const result=await ctx.ui.custom(async(tui,theme,keys,done) => {
    \\   await new Promise(resolve=>setTimeout(resolve,10));
    \\   let input='',count=0,paste=false;
    \\   return {render(width){return ['CUSTOM_WIDTH:'+width,'CUSTOM_INPUT:'+input,'CUSTOM_COUNT:'+count,'CUSTOM_PASTE:'+paste]},
    \\    handleInput(data){if(data==='q')done('selected');else{count++;paste=data.startsWith('\x1b[200~')&&data.endsWith('\x1b[201~');input+=paste?data.slice(6,-6):data;tui.requestRender();}},
    \\    dispose(){disposed++;}};
    \\  });
    \\  ctx.ui.notify('CUSTOM_RESULT:'+result+':DISPOSED:'+disposed);
    \\ }});
    \\ pi.registerCommand('component-error', {handler: async (_,ctx) => {
    \\  const original=new Error('component-original-error');
    \\  try {await ctx.ui.custom(()=>({render(){throw original;}}));}
    \\  catch(error){ctx.ui.notify('CUSTOM_ERROR_IDENTITY:'+(error===original));}
    \\ }});
    \\ pi.registerCommand('dialog-cancel',{handler:async(_,ctx)=>{
    \\  ctx.ui.setEditorText('cancel-dialog-draft');const cancel=new AbortController();
    \\  setTimeout(()=>cancel.abort(),150);const selected=await ctx.ui.select('NATIVE_CANCEL_DIALOG',['one','two'],{signal:cancel.signal});
    \\  ctx.ui.notify('NATIVE_DIALOG_CANCELLED:'+(selected===undefined));
    \\ }});
    \\}
;

test "native CLI custom scene owns input resize close ACK and restores draft viewport without Node" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnExtension(errors, custom_extension);
    defer child.deinit();
    errdefer {
        const trace = fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536)) catch null;
        if (trace) |bytes| {
            defer std.testing.allocator.free(bytes);
            std.debug.print("Native CLI child stderr:\n{s}\n", .{bytes});
        }
    }
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "\x1b[1;5H", "history-row-000");
    try observed.send(&child, "/component\r", "CUSTOM_WIDTH:100");
    try std.testing.expect(!try observed.screen.contains("> component-draft"));
    try observed.send(&child, "\x1b[120;1:3ux", "CUSTOM_INPUT:x");
    try std.testing.expect(try observed.screen.contains("CUSTOM_COUNT:1"));
    try observed.send(&child, "\x1b[200~Ω🦊\x1b[201~", "CUSTOM_PASTE:true");
    if (!try observed.screen.contains("CUSTOM_INPUT:xΩ🦊")) {
        const cells = try observed.screen.textAlloc(std.testing.allocator);
        defer std.testing.allocator.free(cells);
        std.debug.print("Custom paste actual cells:\n{s}\n", .{cells});
        return error.NativeCustomPasteChanged;
    }
    const resize_frame = observed.screen.frames;
    try observed.screen.resize(70, 22);
    try child.resize(70, 22);
    try observed.wait(&child, "CUSTOM_WIDTH:70", resize_frame);
    try observed.send(&child, "q", "> component-draft");
    try std.testing.expect(try observed.screen.contains("> component-draft"));
    try std.testing.expect(try observed.screen.contains("history-row-000"));
    try std.testing.expect(!try observed.screen.contains("CUSTOM_WIDTH:"));
    try observed.send(&child, "\x1b[1;5F", "CUSTOM_RESULT:selected:DISPOSED:1");
    try observed.wait(&child, "custom-life=start1-end1", 0);
    try observed.send(&child, "\x15/component-error\r", "CUSTOM_ERROR_IDENTITY:true");
    try std.testing.expect(!try observed.screen.contains("CUSTOM_WIDTH:"));
    try observed.send(&child, "\x15/dialog-cancel\r", "NATIVE_DIALOG_CANCELLED:true");
    try std.testing.expect(try observed.screen.contains("> cancel-dialog-draft"));
    try observed.send(&child, "\x15/reload\r", "Reloaded");
    try observed.send(&child, "\x15/component\r", "CUSTOM_WIDTH:70");
    try observed.send(&child, "q", "> component-draft");
    try observed.wait(&child, "CUSTOM_RESULT:selected:DISPOSED:1", 0);
    try cleanExit(&fixture, &child, &observed);
}

const overlay_extension =
    \\export default function(pi){pi.registerCommand('overlay',{async handler(_,ctx){
    \\ ctx.ui.setEditorText('overlay-draft');let handle,events=0,disposed=0,bounds;
    \\ const selected=await ctx.ui.custom((tui,theme,keys,done)=>({wantsKeyRelease:true,
    \\  render(width){return ['OVERLAY_WIDTH:'+width,'OVERLAY_EVENTS:'+events,'OVERLAY_SCREEN:'+tui.terminal.columns+'x'+tui.terminal.rows,'OVERLAY_CLIPPED_FORBIDDEN']},
    \\  handleInput(data){events++;if(data==='q'){bounds=handle.getBounds();done('selected')}else if(data==='h'){handle.setHidden(true);handle.unfocus();setTimeout(()=>{handle.setHidden(false);handle.focus();tui.requestRender()},1000)}else tui.requestRender()},
    \\  dispose(){disposed++}}),{overlay:true,overlayOptions:{width:'50%',maxHeight:3,margin:1,anchor:'bottom-right'},onHandle(value){handle=value;value.focus()}});
    \\ ctx.ui.notify('OVERLAY_DONE:'+selected+':EVENTS:'+events+':DISPOSED:'+disposed);
    \\ ctx.ui.notify('OVERLAY_BOUNDS:'+bounds.row+':'+bounds.col);
    \\ ctx.ui.notify('OVERLAY_STALE:'+handle.isHidden()+':'+handle.isFocused());
    \\}})}
;

const focus_extension =
    \\export default function(pi){pi.registerCommand('focus',{async handler(_,ctx){
    \\ ctx.ui.setEditorText('focus-draft');let phase='root',rootInput='',oneInput='',twoInput='',h,disposed=0;
    \\ const result=await ctx.ui.custom((tui,theme,keys,done)=>{
    \\  const one={focused:false,wantsKeyRelease:true,handleInput(data){if(this!==one||!one.focused)throw Error('focus-one-receiver');oneInput+=data==='\x1b[120;1:3u'?'RELEASE':data;if(data==='y'){phase='two';h.unfocus({target:two})}}};
    \\  const two={focused:false,handleInput(data){if(this!==two||!two.focused)throw Error('focus-two-receiver');twoInput+=data;if(data==='z'){phase='none';tui.setFocus(null);setTimeout(()=>{phase='root-again';tui.setFocus(root);tui.requestRender()},1000)}}};
    \\  const root={focused:false,render(width){return ['FOCUS_PHASE:'+phase,'FOCUS_ROOT:'+root.focused+':'+rootInput,'FOCUS_ONE:'+one.focused+':'+oneInput,'FOCUS_TWO:'+two.focused+':'+twoInput]},handleInput(data){rootInput+=data;if(data==='x'){phase='one';h.unfocus({target:one})}else if(data==='q')done('selected')},dispose(){disposed++}};
    \\  return root;
    \\ },{overlay:true,overlayOptions:{width:60,nonCapturing:true,anchor:'top-left'},onHandle(handle){h=handle;handle.focus()}});
    \\ ctx.ui.notify('FOCUS_DONE:'+result+':DISPOSED:'+disposed);
    \\}})}
;

const focus_restore_extension =
    \\export default function(pi){pi.registerCommand('restore-focus',{async handler(_,ctx){
    \\ let h,rootInput='',baseInput='',phase='root';ctx.ui.setEditorText('restore-draft');
    \\ const result=await ctx.ui.custom((tui,theme,keys,done)=>{
    \\  const base={focused:false,handleInput(data){baseInput+=data;if(data==='b'){phase='cleared';h.unfocus({target:null});setTimeout(()=>{phase='root-again';h.focus();tui.requestRender()},1000)}}};
    \\  const root={focused:false,render(){return ['RESTORE_PHASE:'+phase,'RESTORE_ROOT:'+rootInput+':'+root.focused,'RESTORE_BASE:'+baseInput+':'+base.focused]},handleInput(data){rootInput+=data;if(data==='s'){phase='stolen';tui.setFocus(base)}else if(data==='n'){phase='blocked-null';tui.setFocus(base);setTimeout(()=>{tui.setFocus(null);phase='root-null-restored';tui.requestRender()},300)}else if(data==='d'){phase='deferred';tui.setFocus(base);h.unfocus({target:null});setTimeout(()=>{tui.setFocus(null);phase='deferred-cleared';tui.requestRender();setTimeout(()=>{h.focus();phase='root-deferred-returned';tui.requestRender()},700)},300)}else if(data==='u'){phase='base';h.unfocus({target:base})}else if(data==='q')done('done')}};
    \\  return root;
    \\ },{overlay:true,overlayOptions:{width:60,nonCapturing:true,anchor:'top-left'},onHandle(handle){h=handle;h.focus()}});
    \\ ctx.ui.notify('RESTORE_RESULT:'+result);
    \\}})}
;

test "actual native explicit passive focus restores unmounted base steal while unfocus null remains clear" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("regular");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnExtension(errors, focus_restore_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.waitAny(&child, ">");
    try child.send("/restore-focus\r");
    try observed.waitAny(&child, "RESTORE_ROOT::true");
    try observed.send(&child, "s", "RESTORE_PHASE:stolen");
    try observed.send(&child, "x", "RESTORE_ROOT:sx:true");
    try std.testing.expect(try observed.screen.contains("RESTORE_BASE::false"));
    try observed.send(&child, "n", "RESTORE_PHASE:blocked-null");
    try std.testing.expect(try observed.screen.contains("RESTORE_BASE::true"));
    try observed.wait(&child, "RESTORE_PHASE:root-null-restored", observed.screen.frames);
    try std.testing.expect(try observed.screen.contains("RESTORE_ROOT:sxn:true"));
    try observed.send(&child, "d", "RESTORE_PHASE:deferred");
    try std.testing.expect(try observed.screen.contains("RESTORE_BASE::true"));
    try observed.wait(&child, "RESTORE_PHASE:deferred-cleared", observed.screen.frames);
    try std.testing.expect(try observed.screen.contains("RESTORE_ROOT:sxnd:false"));
    try std.testing.expect(try observed.screen.contains("RESTORE_BASE::false"));
    const no_resume_frame = observed.screen.frames;
    try child.send("LOST");
    try observed.wait(&child, "RESTORE_PHASE:root-deferred-returned", no_resume_frame);
    try std.testing.expect(!try observed.screen.contains("LOST"));
    try observed.send(&child, "u", "RESTORE_PHASE:base");
    try observed.send(&child, "b", "RESTORE_PHASE:cleared");
    const clear_frame = observed.screen.frames;
    try child.send("LOST");
    try observed.wait(&child, "RESTORE_PHASE:root-again", clear_frame);
    try std.testing.expect(try observed.screen.contains("RESTORE_BASE:b:false"));
    try std.testing.expect(!try observed.screen.contains("LOST"));
    const leaves = observed.screen.leaves;
    try child.send("q");
    try observed.waitAny(&child, "RESTORE_RESULT:done");
    try observed.waitPrimary(&child, "> restore-draft", leaves);
    try child.send("\x15/quit\r");
    const term = try child.wait(5000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const stderr = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

test "actual native focused passive overlay routes rooted targets key releases explicit null and unfocus target" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("regular");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnExtension(errors, focus_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.waitAny(&child, ">");
    try child.send("/focus\r");
    try observed.waitAny(&child, "FOCUS_ROOT:true:");
    try observed.send(&child, "x", "FOCUS_PHASE:one");
    try std.testing.expect(try observed.screen.contains("FOCUS_ROOT:false:x"));
    try observed.send(&child, "\x1b[120;1:3u", "FOCUS_ONE:true:RELEASE");
    try observed.send(&child, "y", "FOCUS_PHASE:two");
    try std.testing.expect(try observed.screen.contains("FOCUS_ONE:false:RELEASEy"));
    try observed.send(&child, "z", "FOCUS_PHASE:none");
    try std.testing.expect(try observed.screen.contains("FOCUS_TWO:false:z"));
    const no_target_frame = observed.screen.frames;
    try child.send("LOST");
    try observed.wait(&child, "FOCUS_PHASE:root-again", no_target_frame);
    try std.testing.expect(try observed.screen.contains("FOCUS_ROOT:true:x"));
    try std.testing.expect(!try observed.screen.contains("LOST"));
    const leaves = observed.screen.leaves;
    try child.send("q");
    try observed.waitAny(&child, "FOCUS_DONE:selected:DISPOSED:1");
    try observed.waitPrimary(&child, "> focus-draft", leaves);
    try child.send("\x15/quit\r");
    const term = try child.wait(5000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const stderr = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

test "native CLI overlay paints real geometry releases hidden focus and restores edited background with fenced close" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnExtension(errors, overlay_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "/overlay\r", "OVERLAY_WIDTH:50");
    try observed.wait(&child, "OVERLAY_SCREEN:100x40", 0);
    try std.testing.expectEqual(@as(u21, 'O'), observed.screen.cells()[36 * 100 + 49].scalar);
    try std.testing.expect(try observed.screen.contains("history-row-059"));
    try std.testing.expect(!try observed.screen.contains("OVERLAY_CLIPPED_FORBIDDEN"));
    try observed.send(&child, "\x1b[120;1:3u", "OVERLAY_EVENTS:1");
    const resize_frame = observed.screen.frames;
    try observed.screen.resize(70, 22);
    try child.resize(70, 22);
    try observed.wait(&child, "OVERLAY_WIDTH:35", resize_frame);
    try std.testing.expectEqual(@as(u21, 'O'), observed.screen.cells()[18 * 70 + 34].scalar);
    const hide_frame = observed.screen.frames;
    try child.send("h");
    try observed.waitAbsent(&child, "OVERLAY_WIDTH:", hide_frame);
    try std.testing.expect(try observed.screen.contains("> overlay-draft"));
    try std.testing.expect(!try observed.screen.contains("OVERLAY_WIDTH:"));
    try observed.send(&child, "z", "> overlay-draftz");
    try observed.wait(&child, "OVERLAY_WIDTH:35", observed.screen.frames);
    try std.testing.expect(try observed.screen.contains("OVERLAY_EVENTS:2"));
    try observed.send(&child, "q", "OVERLAY_DONE:selected:EVENTS:3:DISPOSED:1");
    try observed.wait(&child, "OVERLAY_BOUNDS:18:34", 0);
    try observed.wait(&child, "OVERLAY_STALE:true:false", 0);
    try std.testing.expect(try observed.screen.contains("> overlay-draftz"));
    try std.testing.expect(!try observed.screen.contains("OVERLAY_WIDTH:"));
    try cleanExit(&fixture, &child, &observed);
}
const Observer = struct {
    screen: vt.Screen,
    consumed: usize = 0,
    fn init() !Observer {
        return .{ .screen = try vt.Screen.init(std.testing.allocator, 100, 40) };
    }
    fn deinit(self: *Observer) void {
        self.screen.deinit();
    }
    fn drain(self: *Observer, child: *pty.Session) !void {
        try child.drain();
        try self.screen.feed(child.output.items[self.consumed..]);
        self.consumed = child.output.items.len;
    }
    fn wait(self: *Observer, child: *pty.Session, marker: []const u8, after_frame: usize) !void {
        const end = Io.Clock.awake.now(child.io).toMilliseconds() + 5000;
        while (Io.Clock.awake.now(child.io).toMilliseconds() < end) {
            try self.drain(child);
            if (!self.screen.synchronized_update and self.screen.frames > after_frame and try self.screen.contains(marker)) return;
            if (try child.exited()) break;
            try child.io.sleep(.fromMilliseconds(10), .awake);
        }
        const text = try self.screen.textAlloc(std.testing.allocator);
        defer std.testing.allocator.free(text);
        std.debug.print("Fullscreen cells missing {s}; frames={d}; cells:\n{s}\n", .{ marker, self.screen.frames, text });
        return error.FullscreenCellAssertionFailed;
    }
    fn send(self: *Observer, child: *pty.Session, input: []const u8, marker: []const u8) !void {
        const frame = self.screen.frames;
        try child.send(input);
        try self.wait(child, marker, frame);
    }
    fn waitAbsent(self: *Observer, child: *pty.Session, marker: []const u8, after_frame: usize) !void {
        const end = Io.Clock.awake.now(child.io).toMilliseconds() + 5000;
        while (Io.Clock.awake.now(child.io).toMilliseconds() < end) {
            try self.drain(child);
            if (!self.screen.synchronized_update and self.screen.frames > after_frame and !try self.screen.contains(marker)) return;
            if (try child.exited()) break;
            try child.io.sleep(.fromMilliseconds(10), .awake);
        }
        return error.NativeOverlayDidNotDisappear;
    }
    fn waitAny(self: *Observer, child: *pty.Session, marker: []const u8) !void {
        const end = Io.Clock.awake.now(child.io).toMilliseconds() + 5000;
        while (Io.Clock.awake.now(child.io).toMilliseconds() < end) {
            try self.drain(child);
            if (!self.screen.synchronized_update and try self.screen.contains(marker)) return;
            if (try child.exited()) break;
            try child.io.sleep(.fromMilliseconds(10), .awake);
        }
        const cells = try self.screen.textAlloc(std.testing.allocator);
        defer std.testing.allocator.free(cells);
        std.debug.print("Regular cells missing {s}:\n{s}\n", .{ marker, cells });
        return error.RegularCustomCellAssertionFailed;
    }
    fn waitPrimary(self: *Observer, child: *pty.Session, marker: []const u8, previous_leaves: usize) !void {
        const end = Io.Clock.awake.now(child.io).toMilliseconds() + 5000;
        while (Io.Clock.awake.now(child.io).toMilliseconds() < end) {
            try self.drain(child);
            if (!self.screen.synchronized_update and !self.screen.in_alternate and self.screen.leaves > previous_leaves and try self.screen.contains(marker)) return;
            if (try child.exited()) break;
            try child.io.sleep(.fromMilliseconds(10), .awake);
        }
        return error.RegularCustomPrimaryRestoreFailed;
    }
};

test "actual regular native custom owner restores primary screen draft stdin modes after resize cancel error and reuse" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("regular");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnExtension(errors, custom_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.waitAny(&child, ">");
    try std.testing.expect(!observed.screen.in_alternate);
    try child.send("/component\r");
    try observed.waitAny(&child, "CUSTOM_WIDTH:100");
    try std.testing.expect(observed.screen.in_alternate);
    try observed.send(&child, "\x1b[120;1:3ux", "CUSTOM_COUNT:1");
    try observed.send(&child, "\x1b[200~Ω🦊\x1b[201~", "CUSTOM_INPUT:xΩ🦊");
    const resize_frame = observed.screen.frames;
    try observed.screen.resize(70, 22);
    try child.resize(70, 22);
    try observed.wait(&child, "CUSTOM_WIDTH:70", resize_frame);
    try child.send("q");
    try observed.waitAny(&child, "CUSTOM_RESULT:selected:DISPOSED:1");
    try observed.waitAny(&child, "> component-draft");
    try std.testing.expect(!observed.screen.in_alternate);
    try child.send("\x15/component-error\r");
    try observed.waitAny(&child, "CUSTOM_ERROR_IDENTITY:true");
    try std.testing.expect(!observed.screen.in_alternate);
    try child.send("\x15/dialog-cancel\r");
    try observed.waitAny(&child, "NATIVE_DIALOG_CANCELLED:true");
    try observed.waitAny(&child, "> cancel-dialog-draft");
    try std.testing.expect(!observed.screen.in_alternate);
    try child.send("\x15/reload\r");
    try observed.waitAny(&child, "Reloaded");
    const second_enter = observed.screen.enters;
    try child.send("\x15/component\r");
    try observed.waitAny(&child, "CUSTOM_WIDTH:70");
    try std.testing.expect(observed.screen.enters > second_enter);
    const second_leave = observed.screen.leaves;
    try child.send("q");
    try observed.waitPrimary(&child, "> component-draft", second_leave);
    try std.testing.expect(!observed.screen.in_alternate);
    try child.send("\x15/quit\r");
    const term = try child.wait(5000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const stderr = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

fn cleanExit(fixture: *Fixture, child: *pty.Session, observed: *Observer) !void {
    try child.send("\x15/quit\r");
    const term = try child.wait(5000);
    try observed.drain(child);
    try std.testing.expect(term == .exited and term.exited == 0);
    try std.testing.expect(!observed.screen.in_alternate);
    const errors = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(errors);
    try std.testing.expectEqualStrings("", errors);
}

test "real fullscreen CLI keeps Home End in editor and Ctrl Home End pages in retained branch viewport" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try std.testing.expect(observed.screen.in_alternate);
    try std.testing.expect(!try observed.screen.contains("inactive-history-forbidden"));
    try observed.send(&child, "draft", "> draft");
    try observed.send(&child, "\x1b[HX", "> Xdraft");
    try std.testing.expect(try observed.screen.contains("history-row-059"));
    try observed.send(&child, "\x1b[FY", "> XdraftY");
    try std.testing.expect(try observed.screen.contains("history-row-059"));
    try observed.send(&child, "\x1b[1;5H", "history-row-000");
    try std.testing.expect(!try observed.screen.contains("history-row-059"));
    try observed.send(&child, "\x1b[H\x1b[F", "> XdraftY");
    try std.testing.expect(try observed.screen.contains("history-row-000"));
    try observed.send(&child, "\x1b[6~", "history-row-030");
    try std.testing.expect(!try observed.screen.contains("history-row-000"));
    try observed.send(&child, "\x1b[5~", "history-row-000");
    try observed.send(&child, "\x1b[1;5F", "history-row-059");
    const resize_frame = observed.screen.frames;
    try observed.screen.resize(70, 22);
    try child.resize(70, 22);
    try observed.wait(&child, "history-row-059", resize_frame);
    try std.testing.expect(try observed.screen.contains("> XdraftY"));
    try observed.send(&child, "\x1b[200~\nsecond-line Ω🦊\x1b[201~", "second-line Ω🦊");
    try child.send("\x15\x7f\x15/quit\r");
    const term = try child.wait(5000);
    try std.testing.expect(term == .exited and term.exited == 0);
    try observed.drain(&child);
    try std.testing.expect(!observed.screen.in_alternate);
    const stderr = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

test "real fullscreen CLI coalesces an available input burst before publishing its command" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    const before = observed.screen.frames;
    try observed.send(&child, "abcdefghijklmnopqrstuvwxyz012345", "> abcdefghijklmnopqrstuvwxyz012345");
    // A ready keyboard burst is one editor transaction, rather than thirty-two
    // expensive paints competing with the provider or a queued modal command.
    try std.testing.expect(observed.screen.frames - before <= 4);
    try cleanExit(&fixture, &child, &observed);
}

test "real fullscreen CLI routes remapped viewport keys and ignores Kitty releases while accepting repeats" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "agent/keybindings.json", .data = "{\"tui.altScreen.top\":[\"alt+home\"],\"tui.altScreen.bottom\":[\"alt+end\"]}" });
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "\x1b[1;5Htext", "> text");
    try std.testing.expect(try observed.screen.contains("history-row-059"));
    try observed.send(&child, "\x1b[57423;3:3u!", "> text!");
    try std.testing.expect(try observed.screen.contains("history-row-059"));
    try observed.send(&child, "\x1b[57423;3:2u", "history-row-000");
    try observed.send(&child, "\x1b[57424;3:3u!", "> text!!");
    try std.testing.expect(try observed.screen.contains("history-row-000"));
    try observed.send(&child, "\x1b[57424;3:2u", "history-row-059");
    try cleanExit(&fixture, &child, &observed);
}

test "real fullscreen CLI exits quietly and joins its owner after actual PTY hangup" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    child.hangup();
    const term = try child.wait(5000);
    // Closing ConPTY input closes its private console with native CTRL_C_EXIT;
    // POSIX PTY disappearance follows the CLI's quiet SIGHUP-style contract.
    if (comptime builtin.os.tag == .windows) {
        try std.testing.expect(term == .exited);
        try std.testing.expectEqual(@as(?u32, 0xc000013a), child.native_exit_code);
    } else try std.testing.expect(term == .exited and term.exited == 129);
    const stderr = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

test "real fullscreen CLI streams intermediate cells retains scroll anchor and draft through queued settings modal" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "run\r", "stream-first");
    try std.testing.expect(!try observed.screen.contains("stream-final"));
    try observed.send(&child, "draft-survives", "> draft-survives");
    try observed.send(&child, "\x1b[1;5H", "history-row-000");
    try std.testing.io.sleep(.fromMilliseconds(950), .awake);
    try observed.drain(&child);
    try std.testing.expect(try observed.screen.contains("history-row-000"));
    try std.testing.expect(try observed.screen.contains("> draft-survives"));
    try std.testing.expect(!try observed.screen.contains("stream-final"));
    try observed.send(&child, "\x1b[1;5F", "stream-final");
    try std.testing.expect(try observed.screen.contains("> draft-survives"));
    const cells = try observed.screen.textAlloc(std.testing.allocator);
    defer std.testing.allocator.free(cells);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, cells, "stream-final"));
    // Queue a command while the next provider turn is running, then leave a
    // draft in the independent editor before the main owner opens the dialog.
    try observed.send(&child, "\x15/reload\r", "Reloaded:");
    try observed.send(&child, "run-again\r", "second-first");
    const modal_start = child.output.items.len;
    try observed.send(&child, "/settings\rpreserved-modal-draft", "> preserved-modal-draft");
    _ = try child.waitFor("Settings", modal_start, 5000);
    try observed.drain(&child);
    try std.testing.expect(try observed.screen.contains("Settings"));
    try child.send("\x1b");
    try observed.wait(&child, "> preserved-modal-draft", observed.screen.frames);
    try std.testing.expect(observed.screen.in_alternate);
    try cleanExit(&fixture, &child, &observed);
}

test "explicit regular CLI retains ordinary editor behavior and does not enter persistent alternate screen" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("regular");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    // ConPTY coalesces blank cells into cursor movement; inspect its screen.
    _ = try child.waitFor(">", 0, 5000);
    try observed.drain(&child);
    try std.testing.expect(try observed.screen.contains(">"));
    try child.send("draft\x1b[HX\x1b[FY");
    const end = Io.Clock.awake.now(child.io).toMilliseconds() + 5000;
    while (Io.Clock.awake.now(child.io).toMilliseconds() < end) {
        try observed.drain(&child);
        if (try observed.screen.contains("XdraftY")) break;
        try child.io.sleep(.fromMilliseconds(10), .awake);
    }
    try std.testing.expect(try observed.screen.contains("XdraftY"));
    try std.testing.expect(std.mem.indexOf(u8, child.output.items, "\x1b[?1049h") == null);
    try child.send("\x15/quit\r");
    const term = try child.wait(5000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const stderr = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

test "real fullscreen Escape aborts a live turn without clearing the independent draft and next turn works" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "run\r", "stream-first");
    try observed.send(&child, "abort-draft", "> abort-draft");
    try child.send("\x1b");
    const end = Io.Clock.awake.now(std.testing.io).toMilliseconds() + 3000;
    var aborted = false;
    while (Io.Clock.awake.now(std.testing.io).toMilliseconds() < end) {
        const durable = try Io.Dir.cwd().readFileAlloc(std.testing.io, fixture.history, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(durable);
        aborted = std.mem.indexOf(u8, durable, "\"stopReason\":\"aborted\"") != null;
        if (aborted) break;
        try std.testing.io.sleep(.fromMilliseconds(10), .awake);
    }
    try std.testing.expect(aborted);
    try observed.drain(&child);
    try std.testing.expect(try observed.screen.contains("> abort-draft"));
    try observed.send(&child, "\x15again\r", "second-first");
    try observed.wait(&child, "second-final", observed.screen.frames);
    try cleanExit(&fixture, &child, &observed);
}
