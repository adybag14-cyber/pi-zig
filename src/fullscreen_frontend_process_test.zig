//! Persistent fullscreen behavior observed in real offline CLI PTY screens.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/platform_pty.zig");
const vt = @import("test_support/terminal_screen.zig");
const Io = std.Io;

test "native extension confirm reports permission title while modal owns input and restores idle status" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    try fixture.environment.put("PI_PROGRAM_STATUS", "1");
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnExtension(errors, "export default pi=>pi.registerCommand('permission',{async handler(_,ctx){const accepted=await ctx.ui.confirm('Permission title','private permission body');return {message:'PERMISSION_DONE:'+accepted}}})");
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.waitInitialStartup(&child, ">");
    const start = child.output.items.len;
    try child.send("/permission\r");
    _ = try child.waitFor("\x1b]7501;state=blocked:app=pi:kind=permission:msg=UGVybWlzc2lvbiB0aXRsZQ==", start, 5000);
    try observed.waitAny(&child, "Permission title");
    try child.send("\x1b[B\r");
    try observed.waitAny(&child, "PERMISSION_DONE:false");
    _ = try child.waitFor("\x1b]7501;state=idle:app=pi", start, 5000);
    try cleanExit(&fixture, &child, &observed);
}

test "actual native extension dialogs use Source selector Escape cancel default Yes navigation and empty input" {
    if (!pty.supported()) return error.SkipZigTest;
    for ([_][]const u8{ "regular", "fullscreen" }) |mode| {
        var fixture = try Fixture.init(mode);
        defer fixture.deinit();
        const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
        defer errors.close(std.testing.io);
        const source =
            \\export default pi=>{let inputCall=0;pi.registerCommand('confirm',{async handler(_,ctx){const value=await ctx.ui.confirm('CONFIRM_DIALOG_TITLE','Message');return {message:'CONFIRM_RESULT:'+value}}});pi.registerCommand('select',{async handler(_,ctx){const value=await ctx.ui.select('SELECT_DIALOG_TITLE',['alpha','beta']);return {message:'SELECT_RESULT:'+value}}});pi.registerCommand('input',{async handler(_,ctx){const call=++inputCall,value=await ctx.ui.input('INPUT_DIALOG_TITLE:'+call,'SOURCE_IGNORES_PLACEHOLDER');return {message:'INPUT_RESULT:'+JSON.stringify(value)+':CALL:'+call}}})}
        ;
        var child = try fixture.spawnExtension(errors, source);
        defer child.deinit();
        var observed = try Observer.init();
        defer observed.deinit();
        try observed.waitInitialStartup(&child, ">");
        try child.send("/confirm\r");
        try observed.waitAny(&child, "CONFIRM_DIALOG_TITLE");
        try child.send("\x1b");
        try observed.waitAny(&child, "CONFIRM_RESULT:false");
        try child.send("/confirm\r");
        try observed.waitAny(&child, "CONFIRM_DIALOG_TITLE");
        try child.send("\r");
        try observed.waitAny(&child, "CONFIRM_RESULT:true");
        try child.send("/select\r");
        try observed.waitAny(&child, "SELECT_DIALOG_TITLE");
        try child.send("j\r");
        try observed.waitAny(&child, "SELECT_RESULT:beta");
        try child.send("/input\r");
        try observed.waitAny(&child, "INPUT_DIALOG_TITLE:1");
        try std.testing.expect(!try observed.screen.contains("SOURCE_IGNORES_PLACEHOLDER"));
        try child.send("\r");
        try observed.waitAny(&child, "INPUT_RESULT:\"\"");
        try child.send("/input\r");
        try observed.waitAny(&child, "INPUT_DIALOG_TITLE:2");
        try child.send("a界\x1b[DZ\r");
        try observed.waitAny(&child, "INPUT_RESULT:\"aZ界\":CALL:2");
        // Keep the original complete burst above, and split the same bytes at
        // every CSI boundary without accepting an earlier dialog's title/result.
        const burst = "a界\x1b[DZ\r";
        for (0..4) |csi_split| {
            const call = csi_split + 3;
            const title = try std.fmt.allocPrint(std.testing.allocator, "INPUT_DIALOG_TITLE:{d}", .{call});
            defer std.testing.allocator.free(title);
            const result = try std.fmt.allocPrint(std.testing.allocator, "INPUT_RESULT:\"aZ界\":CALL:{d}", .{call});
            defer std.testing.allocator.free(result);
            try child.send("/input\r");
            try observed.waitAny(&child, title);
            const boundary = "a界".len + csi_split;
            try child.send(burst[0..boundary]);
            try child.send(burst[boundary..]);
            try observed.waitAny(&child, result);
        }
        try observed.send(&child, "after-dialog", "> after-dialog");
        try cleanExit(&fixture, &child, &observed);
    }
}

test "native persistent terminal reports Pi program status lifecycle without prompt or assistant leakage" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    try fixture.environment.put("PI_PROGRAM_STATUS", "1");
    try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"private-assistant-answer\",\"stream_chunks\":[\"private-assistant-answer\"],\"stream_chunk_delay_ms\":200},{\"content\":\"failure-first-line\\nprivate-error-detail\",\"stop_reason\":\"error\"}]" });
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.waitInitialStartup(&child, ">");
    _ = try child.waitFor("\x1b]7501;state=idle:app=pi", 0, 5000);
    const first = child.output.items.len;
    try child.send("private-user-prompt\r");
    _ = try child.waitFor("\x1b]7501;state=working:app=pi", first, 5000);
    _ = try child.waitFor("\x1b]7501;state=done:app=pi", first, 5000);
    try observed.waitAny(&child, "private-assistant-answer");
    const second = child.output.items.len;
    try child.send("private-next-prompt\r");
    _ = try child.waitFor("\x1b]7501;state=error:app=pi:msg=ZmFpbHVyZS1maXJzdC1saW5l", second, 5000);
    try cleanExit(&fixture, &child, &observed);
    try std.testing.expect(std.mem.indexOf(u8, child.output.items, "\x1b]7501;state=clear\x1b\\") != null);
    var reports = std.mem.splitSequence(u8, child.output.items, "\x1b]7501;");
    _ = reports.next();
    while (reports.next()) |tail| {
        const end = std.mem.indexOf(u8, tail, "\x1b\\") orelse return error.MissingProgramStatusTerminator;
        try std.testing.expect(std.mem.indexOf(u8, tail[0..end], "private") == null);
        try std.testing.expect(std.mem.indexOf(u8, tail[0..end], "cHJpdmF0ZQ") == null);
    }
}

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
    fn spawnEditor(self: *Fixture, errors: Io.File, source: []const u8) !pty.Session {
        try self.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "editor.ts", .data = source });
        const path = try std.fs.path.join(std.testing.allocator, &.{ self.scratch.path, "editor.ts" });
        defer std.testing.allocator.free(path);
        try self.environment.put("PI_EXTENSION_BACKEND", "native");
        return pty.spawn(std.testing.allocator, std.testing.io, .{
            .argv = &.{ self.binary, "--offline", "--mock-script", self.mock, "--session", self.history, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-tools", "--approve", "-e", path },
            .cwd = .{ .path = self.scratch.path },
            .environ_map = &self.environment,
            .stderr = .{ .file = errors },
        }, 90_000);
    }
    fn spawnRenderer(self: *Fixture, errors: Io.File, source: []const u8) !pty.Session {
        try self.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "renderer.mjs", .data = source });
        try self.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"\",\"tool_calls\":[{\"id\":\"live-tool\",\"name\":\"animated\",\"arguments\":\"{\\\"value\\\":\\\"seed\\\"}\"}]},{\"content\":\"turn-complete\"},{\"content\":\"after-reload\"}]" });
        const path = try std.fs.path.join(std.testing.allocator, &.{ self.scratch.path, "renderer.mjs" });
        defer std.testing.allocator.free(path);
        try self.environment.put("PI_EXTENSION_BACKEND", "native");
        return pty.spawn(std.testing.allocator, std.testing.io, .{
            .argv = &.{ self.binary, "--offline", "--mock-script", self.mock, "--session", self.history, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-builtin-tools", "--approve", "--verbose", "-e", path },
            .cwd = .{ .path = self.scratch.path },
            .environ_map = &self.environment,
            .stderr = .{ .file = errors },
        }, 90_000);
    }
    fn spawnLateRegistration(self: *Fixture, errors: Io.File) !pty.Session {
        try self.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "late.mjs", .data = "import fs from 'node:fs';export default pi=>pi.registerCommand('seed',{handler(){pi.registerCommand('late',{handler(){return {message:'late-live-command'}}});pi.registerTool({name:'late-tool',parameters:{type:'object'},execute(){fs.writeFileSync('late-execute-witness','entered');pi.appendEntry('late-live-tool',{value:'late-live-tool-result'});fs.writeFileSync('late-execute-witness','append-returned/result-ready');return {content:'late-live-tool-result'}}});return {message:'late-live-seeded'}}})" });
        try self.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"\",\"tool_calls\":[{\"id\":\"late-live-call\",\"name\":\"late-tool\",\"arguments\":\"{}\"}]},{\"content\":\"late-live-turn-complete\"}]" });
        const path = try std.fs.path.join(std.testing.allocator, &.{ self.scratch.path, "late.mjs" });
        defer std.testing.allocator.free(path);
        try self.environment.put("PI_EXTENSION_BACKEND", "native");
        return pty.spawn(std.testing.allocator, std.testing.io, .{
            .argv = &.{ self.binary, "--offline", "--mock-script", self.mock, "--session", self.history, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-builtin-tools", "--approve", "--verbose", "-e", path },
            .cwd = .{ .path = self.scratch.path },
            .environ_map = &self.environment,
            .stderr = .{ .file = errors },
        }, 90_000);
    }
};

const renderer_extension =
    \\import fs from 'node:fs';import {Type} from '@earendil-works/pi-ai';export default pi=>{
    \\ pi.registerCommand('renderer-ready',{handler(_args,ctx){ctx.ui.notify('RENDERER_FIXTURE_READY:OWNER_INSTALLED')}});
    \\ pi.registerTool({name:'animated',label:'Animated',description:'Offline native renderer fixture',parameters:Type.Object({value:Type.String()}),
    \\  async execute(id,args,signal,update){update({content:[{type:'text',text:'partial:'+args.value}]});await new Promise(resolve=>setTimeout(resolve,500));return {content:[{type:'text',text:'done:'+args.value}]}},
    \\  renderCall(args,theme,ctx){ctx.state.label??='early';ctx.state.value=args.value;return {render(width){return ['ROW_CALL:'+ctx.state.label+':'+width+':'+ctx.state.value]}}},
    \\  renderResult(result,options,theme,ctx){if(!options.isPartial&&!ctx.state.scheduled){ctx.state.scheduled=true;const ack=setInterval(()=>{if(!fs.existsSync('renderer-phase-ack'))return;clearInterval(ack);setTimeout(()=>{ctx.state.label='late';ctx.invalidate()},0)},5)}return {render(width){if(ctx.state.label==='late')fs.writeFileSync('renderer-phase-rendered','late');return ['ROW_RESULT:'+ctx.state.label+':'+width+':'+result.content[0].text+':'+options.isPartial]}}}
    \\ });
    \\}
;

const persistent_ui_extension =
    \\import {VERSION} from 'pi-coding-agent';export default pi=>{
    \\ let header=0,footer=0,unsubscribe;pi.on('session_start',(_,ctx)=>{
    \\  if(ctx.mode!=='tui')throw Error('native mode');ctx.ui.setStatus('lane','alive');
    \\  ctx.ui.setHeader((tui,theme)=>({render(width){return ['PERSISTENT_HEADER:'+width+':'+VERSION]},dispose(){header++}}));
    \\  ctx.ui.setFooter((tui,theme,data)=>{const off=data.onBranchChange(()=>tui.requestRender());return {render(width){return ['PERSISTENT_FOOTER:'+width+':'+ctx.sessionManager.getSessionId()+':'+data.getExtensionStatuses().get('lane')]},dispose(){off();footer++}}});
    \\  unsubscribe=ctx.ui.onTerminalInput(data=>{if(data.startsWith('\x1b[200~')){ctx.ui.notify('PASTE_MARKERS_OBSERVED');return {data:data.replace('paste-original','paste-transformed')}}return data==='!'?{consume:true}:data==='x'?{data:'Ω'}:undefined});
    \\ });
    \\ pi.registerCommand('persistent-ready',{handler(_,ctx){ctx.ui.notify('PERSISTENT_FIXTURE_READY:OWNER_INSTALLED');return {}}});
    \\ pi.registerCommand('restore-surfaces',{handler(_,ctx){ctx.ui.setHeader(undefined);ctx.ui.setFooter(undefined);unsubscribe();ctx.ui.notify('SURFACES_DISPOSED:'+header+':'+footer);return {}}});
    \\ pi.registerCommand('indicator',{handler(_,ctx){ctx.ui.setWorkingIndicator({frames:['CUSTOM_INDICATOR'],intervalMs:40});return {}}});
    \\ pi.registerCommand('footer-factory-throw',{handler(_,ctx){const original={footerOriginal:true};try{ctx.ui.setFooter(()=>{throw original})}catch(error){if(error!==original)throw Error('footer identity');ctx.ui.notify('FOOTER_FACTORY_THROW_CAUGHT')}return {}}});
    \\}
;

test "actual native terminal OSC reports update cached Theme without leaking fragmented input into editor" {
    if (!pty.supported()) return error.SkipZigTest;
    // ConPTY's input layer consumes injected OSC replies. POSIX PTYs carry
    // these bytes to the real input owner; Windows parser/cache proofs run
    // separately without treating synthetic replies as console capabilities.
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    try fixture.environment.put("PI_TRUE_COLOR", "1");
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnExtension(errors,
        \\export default pi=>pi.registerCommand('theme-report',{handler(_,ctx){ctx.ui.notify('REPORT_FG:'+JSON.stringify([ctx.ui.theme.colors.text.r,ctx.ui.theme.colors.text.g,ctx.ui.theme.colors.text.b]));return {}}})
    );
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.waitAny(&child, ">");
    _ = try child.waitFor("\x1b]4;15;?\x07", 0, 5000);
    // Answer startup status/keyboard negotiation's first owed DA before the
    // color reports. The later DA below belongs to the color query batch.
    try child.send("\x1b[?1;2c\x1b]10;rgb:aaaa/");
    try child.send("bbbb/cccc\x1b\\\x1b]11;#010203\x07\x1b[?1;2c");
    try observed.send(&child, "/theme-report\r", "REPORT_FG:");
    observed.waitAny(&child, "REPORT_FG:[170,187,204]") catch |cause| {
        const trace = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
        defer std.testing.allocator.free(trace);
        std.debug.print("Theme report owned diagnostic:\n{s}\n", .{trace});
        return cause;
    };
    try std.testing.expect(!try observed.screen.contains("bbbb/cccc"));
    try observed.send(&child, "draft", "> draft");
    try cleanExit(&fixture, &child, &observed);
}
test "actual native retained header footer live context indicator and terminal input work across resize retirement" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnExtension(errors, persistent_ui_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.waitInitialStartup(&child, ">");
    const admitted_frame = observed.screen.frames;
    try child.send("/persistent-ready\r");
    try observed.waitStartupMarker(&child, "PERSISTENT_FIXTURE_READY:OWNER_INSTALLED", admitted_frame);
    try observed.wait(&child, "PERSISTENT_HEADER:100:", 0);
    try observed.wait(&child, "PERSISTENT_FOOTER:100:fullscreen-history:alive", 0);
    try observed.send(&child, "x!", "> Ω");
    try std.testing.expect(!try observed.screen.contains("> Ω!"));
    try observed.send(&child, "\x15\x1b[200~paste-original\x1b[201~", "> paste-transformed");
    try observed.waitAny(&child, "PASTE_MARKERS_OBSERVED");
    const frame = observed.screen.frames;
    try observed.screen.resize(70, 22);
    try child.resize(70, 22);
    try observed.wait(&child, "PERSISTENT_HEADER:70:", frame);
    try observed.wait(&child, "PERSISTENT_FOOTER:70:fullscreen-history:alive", 0);
    try observed.send(&child, "\x15/indicator\r", ">");
    try observed.send(&child, "run\r", "CUSTOM_INDICATOR");
    try observed.wait(&child, "stream-final", 0);
    try observed.send(&child, "/footer-factory-throw\r", "FOOTER_FACTORY_THROW_CAUGHT");
    try std.testing.expect(try observed.screen.contains("PERSISTENT_HEADER:"));
    try std.testing.expect(!try observed.screen.contains("PERSISTENT_FOOTER:"));
    // The source footer container is empty after its replacement factory
    // throws. This is distinct from clearing to the built-in status footer.
    const bottom = observed.screen.cells()[21 * 70 .. 22 * 70];
    var footer_text: [70]u8 = undefined;
    for (bottom, 0..) |cell, index| footer_text[index] = if (cell.scalar < 128) @intCast(cell.scalar) else '?';
    try std.testing.expect(std.mem.indexOf(u8, &footer_text, "fullscreen-history") == null);
    try observed.send(&child, "/restore-surfaces\r", "SURFACES_DISPOSED:1:2");
    try std.testing.expect(!try observed.screen.contains("PERSISTENT_HEADER:"));
    try std.testing.expect(!try observed.screen.contains("PERSISTENT_FOOTER:"));
    try observed.send(&child, "x!", "> x!");
    try cleanExit(&fixture, &child, &observed);
}

test "actual untouched upstream header footer and working indicator examples render continuously in regular and fullscreen without Node" {
    if (!pty.supported()) return error.SkipZigTest;
    var input_arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer input_arena.deinit();
    const arena = input_arena.allocator();
    for ([_][]const u8{ "regular", "fullscreen" }) |mode| {
        var fixture = try Fixture.init(mode);
        defer fixture.deinit();
        try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "original-header.ts", .data = try originalModuleInput(arena, @embedFile("extensions/fixtures/custom-header-original-7fb.input.json")) });
        try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "original-footer.ts", .data = try originalModuleInput(arena, @embedFile("extensions/fixtures/custom-footer-original-7fb.input.json")) });
        try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "original-indicator.ts", .data = try originalModuleInput(arena, @embedFile("extensions/fixtures/working-indicator-original-7fb.input.json")) });
        try fixture.scratch.dir.createDir(std.testing.io, ".git", .default_dir);
        try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = ".git/HEAD", .data = "ref: refs/heads/live-one\n" });
        const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
        defer errors.close(std.testing.io);
        var child = try fixture.spawnExtension(errors, "import header from './original-header.ts';import footer from './original-footer.ts';import indicator from './original-indicator.ts';export default pi=>{header(pi);footer(pi);indicator(pi)}");
        defer child.deinit();
        var observed = try Observer.init();
        defer observed.deinit();
        try observed.waitInitialStartup(&child, "shitty coding agent");
        try observed.waitAny(&child, "Indicator: custom spinner");
        try observed.send(&child, "/footer\r", "Custom footer enabled");
        try observed.waitAny(&child, "↑0 ↓0 $0.000");
        try observed.waitAny(&child, "(live-one)");
        try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = ".git/next", .data = "ref: refs/heads/live-two\n" });
        try fixture.scratch.dir.rename(".git/next", fixture.scratch.dir, ".git/HEAD", std.testing.io);
        try observed.waitAny(&child, "(live-two)");
        try std.testing.expect(!try observed.screen.contains("(live-one)"));
        try observed.send(&child, "/working-indicator dot\r", "Working indicator set to: static dot");
        try observed.send(&child, "run\r", "●");
        try observed.waitAny(&child, "stream-final");
        // The original footer reads its saved command context after that
        // command returned and again after the agent appended its response.
        try observed.waitAny(&child, "↑");
        try observed.send(&child, "draft", "> draft");
        const frame = observed.screen.frames;
        try observed.screen.resize(70, 22);
        try child.resize(70, 22);
        try observed.waitAllVisible(&child, &.{ "> draft", "shitty coding agent", "↑" }, frame);
        try std.testing.expect(try observed.screen.contains("shitty coding agent"));
        try std.testing.expect(try observed.screen.contains("↑"));
        try observed.send(&child, "\x15/footer\r", "Default footer restored");
        try observed.send(&child, "/builtin-header\r", "Built-in header restored");
        try std.testing.expect(!try observed.screen.contains("shitty coding agent"));
        try cleanExit(&fixture, &child, &observed);
    }
}

fn originalModuleInput(gpa: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    const ModuleInput = struct { schemaVersion: u32, sourceCommit: []const u8, inputSha256: []const u8, input: []const u8 };
    const parsed = try std.json.parseFromSlice(ModuleInput, gpa, bytes, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.schemaVersion);
    try std.testing.expectEqualStrings("7fb59f995b0a1db552001a8577b234e4105d7179", parsed.value.sourceCommit);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(parsed.value.input, &digest, .{});
    const actual = std.fmt.bytesToHex(digest, .lower);
    try std.testing.expectEqualStrings(parsed.value.inputSha256, &actual);
    return gpa.dupe(u8, parsed.value.input);
}

test "native MouseRegion real terminal pointer ACK precedes keyboard capture crosses overlay bounds and owner close restores input" {
    if (!pty.supported()) return error.SkipZigTest;
    for ([_][]const u8{ "regular", "fullscreen" }) |mode| {
        var fixture = try Fixture.init(mode);
        defer fixture.deinit();
        const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
        defer errors.close(std.testing.io);
        const source =
            \\import {MouseRegion,Text} from 'pi-tui';
            \\export default pi=>{pi.registerCommand('mouse-ready',{handler(_,ctx){ctx.ui.notify('MOUSE_FIXTURE_COMMAND_READY');return {}}});pi.registerCommand('mouse',{handler(_,ctx){return ctx.ui.custom((tui,theme,keys,done)=>{const text=new Text('MOUSE_REGION_READY',0,0);const root=new MouseRegion(text,function(event){text.setText('MOUSE:'+event.type+':'+event.x+':'+event.y+(event.clickCount?':'+event.clickCount:''));return {handled:true,capture:event.type==='press',focus:true,render:event.type==='release'?true:undefined}});root.focused=false;root.handleInput=data=>{if(data==='\x1b'){done('mouse-closed');return}text.setText('MOUSE_KEY:'+data);tui.requestRender()};tui.setFocus(null);return root},{overlay:true,overlayOptions:{width:30,height:4,row:5,col:7}}).then(value=>({message:value}))}})}
        ;
        var child = try fixture.spawnExtension(errors, source);
        defer child.deinit();
        var observed = try Observer.init();
        defer observed.deinit();
        try observed.waitAny(&child, ">");
        try observed.send(&child, "/mouse-ready\r", "MOUSE_FIXTURE_COMMAND_READY");
        try observed.send(&child, "/mouse\r", "MOUSE_REGION_READY");
        // A click and key in one input burst must settle the pointer's focus
        // generation before that following key is sent to its owner.
        try observed.send(&child, "\x1b[<0;10;6Mx", "MOUSE_KEY:x");
        try observed.send(&child, "\x1b[<32;90;21M", "MOUSE:drag:82:15");
        try observed.send(&child, "\x1b[<0;90;21m", "MOUSE:release:82:15");
        // The dragged release must not synthesize a click. A new stationary
        // press/release then synthesizes the Source click on its retained target.
        try observed.send(&child, "\x1b[<0;10;6M", "MOUSE:press:2:0");
        try observed.send(&child, "\x1b[<0;10;6m", "MOUSE:click:2:0:1");
        try observed.send(&child, "\x1b", "mouse-closed");
        try observed.send(&child, "after-mouse", "> after-mouse");
        try cleanExit(&fixture, &child, &observed);
    }
}

test "Source6fb public Text Box Spacer real native modal updates cache padding columns and restores both terminal modes" {
    if (!pty.supported()) return error.SkipZigTest;
    for ([_][]const u8{ "regular", "fullscreen" }) |mode| {
        var fixture = try Fixture.init(mode);
        defer fixture.deinit();
        const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
        defer errors.close(std.testing.io);
        const source =
            \\import{Text,Box,Spacer}from'pi-tui';export default pi=>pi.registerCommand('layout-proof',{async handler(_,ctx){const result=await ctx.ui.custom((tui,theme,keys,done)=>{const text=new Text('NATIVE_LAYOUT:one界😀 words',1,1,line=>'\x1b[41m'+line+'\x1b[49m'),spacer=new Spacer(1),box=new Box(2,1,line=>'\x1b[42m'+line+'\x1b[49m');box.addChild(text);box.addChild(spacer);box.handleInput=data=>{if(data==='c'){text.setText('NATIVE_LAYOUT:two界😀 words');box.setBgFn(line=>'\x1b[44m'+line+'\x1b[49m')}else if(data==='p'){text.setPaddingX(0);text.setText('NATIVE_LAYOUT:padding')}else if(data==='\x1b'){const textCached=text.render(20)===text.render(20),boxCached=box.render(60)===box.render(60),spacerFresh=spacer.render(20)!==spacer.render(20);done({textCached,boxCached,spacerFresh})}tui.requestRender()};return box},{overlay:true,overlayOptions:{width:60,height:14,row:4,col:5}});return{message:'LAYOUT_DONE:'+JSON.stringify(result)}}})
        ;
        var child = try fixture.spawnExtension(errors, source);
        defer child.deinit();
        var observed = try Observer.init();
        defer observed.deinit();
        try observed.waitInitialStartup(&child, ">");
        try observed.send(&child, "/layout-proof\r", "NATIVE_LAYOUT:one界😀 words");
        try std.testing.expectEqual(@as(u21, 'N'), observed.screen.cells()[6 * observed.screen.columns + 8].scalar);
        try observed.send(&child, "c", "NATIVE_LAYOUT:two界😀 words");
        try observed.send(&child, "p", "NATIVE_LAYOUT:padding");
        try std.testing.expectEqual(@as(u21, 'N'), observed.screen.cells()[6 * observed.screen.columns + 7].scalar);
        try observed.send(&child, "\x1b", "LAYOUT_DONE:{\"textCached\":true,\"boxCached\":true,\"spacerFresh\":true}");
        try observed.send(&child, "after-layout-proof", "> after-layout-proof");
        try cleanExit(&fixture, &child, &observed);
    }
}

test "Source6fb public SelectList SettingsList real native modal filters changes delegates submenu and restores both terminal modes" {
    if (!pty.supported()) return error.SkipZigTest;
    for ([_][]const u8{ "regular", "fullscreen" }) |mode| {
        var fixture = try Fixture.init(mode);
        defer fixture.deinit();
        const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
        defer errors.close(std.testing.io);
        const source =
            \\import{SelectList,SettingsList,Input}from'pi-tui';export default pi=>pi.registerCommand('lists-proof',{async handler(_,ctx){const result=await ctx.ui.custom((tui,theme,keys,done)=>{let stage='select',selection='alpha',changed='none';const listTheme={selectedText:x=>x,description:x=>x,scrollInfo:x=>x,noMatch:x=>x},select=new SelectList([{value:'alpha',label:'Alpha'},{value:'beta',label:'Beta'}],2,listTheme),settingsTheme={cursor:'→ ',label:x=>x,value:x=>x,description:x=>x,hint:x=>x};let settings;const items=[{id:'alpha',label:'Alpha',currentValue:'one',values:['one','two']},{id:'beta',label:'Beta',currentValue:'one',values:['one','two'],description:'Native settings description with wrapped words'},{id:'sub',label:'Submenu',currentValue:'old',submenu(value,close){const input=new Input({prompt:'SUBMENU_NATIVE:'});input.setValue(value);input.onSubmit=value=>close(value);input.onEscape=()=>close();return input}}];settings=new SettingsList(items,3,settingsTheme,(id,value)=>{changed=id+':'+value},()=>done({selection,beta:items[1].currentValue,sub:items[2].currentValue,query:settings.searchInput.getValue()}),{enableSearch:true});select.onSelectionChange=item=>{selection=item.value};select.onSelect=item=>{selection=item.value;stage='settings'};select.onCancel=()=>done(null);return{render(width){return stage==='select'?['LIST_SELECT:'+selection,...select.render(width)]:['LIST_SETTINGS:'+changed,...settings.render(width)]},handleInput(data){(stage==='select'?select:settings).handleInput(data);tui.requestRender()},handleMouse(event){return(stage==='select'?select:settings).handleMouse(event)},invalidate(){select.invalidate();settings.invalidate()}}},{overlay:true,overlayOptions:{width:60,height:15,row:4,col:5}});return{message:'LISTS_DONE:'+JSON.stringify(result)}}})
        ;
        var child = try fixture.spawnExtension(errors, source);
        defer child.deinit();
        var observed = try Observer.init();
        defer observed.deinit();
        try observed.waitInitialStartup(&child, ">");
        try observed.send(&child, "/lists-proof\r", "LIST_SELECT:alpha");
        try observed.send(&child, "\x1b[B", "LIST_SELECT:beta");
        try observed.send(&child, "\r", "LIST_SETTINGS:none");
        try observed.send(&child, "bet", "> bet");
        try observed.send(&child, "\r", "LIST_SETTINGS:beta:two");
        try observed.send(&child, "\x15sub", "> sub");
        try observed.send(&child, "\r", "SUBMENU_NATIVE:old");
        try observed.send(&child, "\x05\x15chosen\r", "LIST_SETTINGS:sub:chosen");
        try observed.send(&child, "\x1b", "LISTS_DONE:{\"selection\":\"beta\",\"beta\":\"two\",\"sub\":\"chosen\",\"query\":\"sub\"}");
        try observed.send(&child, "after-lists-proof", "> after-lists-proof");
        try cleanExit(&fixture, &child, &observed);
    }
}

test "Source6fb public Input real native word modifiers preserve all dictionary scripts and restoration" {
    if (!pty.supported()) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const oracle = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/input-words-original-6fb.json"), .{});
    defer oracle.deinit();
    const Sample = struct { mode: []const u8, seed: []const u8, expected: []u8, cursor: i64 };
    const Seeds = [_]struct { mode: []const u8, value: []const u8 }{
        .{ .mode = "cjk", .value = "中文测试语言" },
        .{ .mode = "thai", .value = "ภาษาไทยภาษาอังกฤษ" },
        .{ .mode = "lao", .value = "ຂ້ອຍຮຽນພາສາລາວ" },
        .{ .mode = "khmer", .value = "ខ្ញុំកំពុងរៀនភាសាខ្មែរ" },
        .{ .mode = "myanmar", .value = "ကျွန်ုပ်မြန်မာဘာသာလေ့လာနေသည်" },
    };
    var samples: std.ArrayList(Sample) = .empty;
    defer {
        for (samples.items) |sample| gpa.free(sample.expected);
        samples.deinit(gpa);
    }
    for (Seeds) |seed| {
        const units = try std.unicode.utf8ToUtf16LeAlloc(gpa, seed.value);
        defer gpa.free(units);
        var target: ?usize = null;
        for (oracle.value.object.get("cases").?.array.items) |item| {
            if (item.object.get("kitty").?.bool or !std.mem.eql(u8, item.object.get("key").?.string, "\x1bb") or item.object.get("cursor").?.integer != units.len) continue;
            const original = item.object.get("units").?.array.items;
            if (original.len != units.len) continue;
            var equal = true;
            for (original, units) |value, unit| if (value.integer != unit) {
                equal = false;
                break;
            };
            if (equal) {
                target = @intCast(item.object.get("first").?.object.get("cursor").?.integer);
                break;
            }
        }
        const at = target orelse return error.MissingSourceWordModifierGolden;
        const modified = try gpa.alloc(u16, units.len + 1);
        defer gpa.free(modified);
        @memcpy(modified[0..at], units[0..at]);
        modified[at] = '#';
        @memcpy(modified[at + 1 ..], units[at..]);
        const expected = try std.unicode.utf16LeToUtf8Alloc(gpa, modified);
        errdefer gpa.free(expected);
        try samples.append(gpa, .{ .mode = seed.mode, .seed = seed.value, .expected = expected, .cursor = @intCast(at + 1) });
    }
    var source: Io.Writer.Allocating = .init(gpa);
    defer source.deinit();
    try source.writer.writeAll("import{Input}from'pi-tui';const samples=");
    try std.json.Stringify.value(samples.items, .{}, &source.writer);
    try source.writer.writeAll(";export default pi=>{pi.registerCommand('word-proof',{async handler(mode,ctx){mode=mode.trim();const sample=samples.find(item=>item.mode===mode);if(!sample)throw Error('unknown word mode');const result=await ctx.ui.custom((tui,theme,keys,done)=>{const input=new Input({prompt:'WORD_NATIVE:'});input.setValue(sample.seed);input.onSubmit=value=>done({matches:value===sample.expected,cursor:input.cursor});input.onEscape=()=>done({matches:false,cursor:-1});return input},{overlay:true,overlayOptions:{width:80,height:3,row:5,col:7}});return{message:'WORD_MODE_DONE:'+mode+':'+result.matches+':'+result.cursor}}});pi.registerCommand('word-dialog',{async handler(_,ctx){const value=await ctx.ui.input('WORD_DIALOG_TITLE','');return{message:'WORD_DIALOG_DONE:'+(value==='中文测试#语言')}}});}");
    for ([_][]const u8{ "regular", "fullscreen" }) |mode| {
        var fixture = try Fixture.init(mode);
        defer fixture.deinit();
        const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
        defer errors.close(std.testing.io);
        var child = try fixture.spawnExtension(errors, source.written());
        defer child.deinit();
        var observed = try Observer.init();
        defer observed.deinit();
        try observed.waitInitialStartup(&child, ">");
        for (samples.items) |sample| {
            const command = try std.fmt.allocPrint(gpa, "/word-proof {s}\r", .{sample.mode});
            defer gpa.free(command);
            try observed.send(&child, command, "WORD_NATIVE:");
            const result = try std.fmt.allocPrint(gpa, "WORD_MODE_DONE:{s}:true:{d}", .{ sample.mode, sample.cursor });
            defer gpa.free(result);
            try observed.send(&child, "\x05\x1bb#\r", result);
        }
        try observed.send(&child, "/word-dialog\r", "WORD_DIALOG_TITLE");
        try observed.send(&child, "中文测试语言\x1bb#\r", "WORD_DIALOG_DONE:true");
        try observed.send(&child, "after-word-proof", "> after-word-proof");
        try observed.send(&child, "\x15中文测试语言", "> 中文测试语言");
        try observed.send(&child, "\x1bb#", "> 中文测试#语言");
        try observed.send(&child, "\x05\x15after-core-word", "> after-core-word");
        try cleanExit(&fixture, &child, &observed);
    }
}

test "Source6fb public Input real native modal preserves UTF16 edits paste undo cursor cells and restoration" {
    if (!pty.supported()) return error.SkipZigTest;
    for ([_][]const u8{ "regular", "fullscreen" }) |mode| {
        var fixture = try Fixture.init(mode);
        defer fixture.deinit();
        const settings = try std.fmt.allocPrint(std.testing.allocator, "{{\"tuiMode\":\"{s}\",\"showHardwareCursor\":false,\"quietStartup\":true,\"enableInstallTelemetry\":false}}", .{mode});
        defer std.testing.allocator.free(settings);
        try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "agent/settings.json", .data = settings });
        const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
        defer errors.close(std.testing.io);
        const source =
            \\import{Input}from'pi-tui';export default pi=>pi.registerCommand('public-input',{async handler(_,ctx){const value=await ctx.ui.custom((tui,theme,keys,done)=>{const input=new Input({prompt:'NATIVE_INPUT:',placeholder:'PLACEHOLDER'});input.setValue('界😀');input.onSubmit=text=>done(text);input.onEscape=()=>done('CANCELLED');return input},{overlay:true,overlayOptions:{width:40,height:3,row:5,col:7}});return{message:'PUBLIC_INPUT_DONE:'+JSON.stringify(value)}}})
        ;
        var child = try fixture.spawnExtension(errors, source);
        defer child.deinit();
        var observed = try Observer.init();
        defer observed.deinit();
        try observed.waitInitialStartup(&child, ">");
        try observed.send(&child, "/public-input\r", "NATIVE_INPUT:界😀");
        var reverse = false;
        for (observed.screen.cells()) |cell| if (cell.scalar == '界') {
            reverse = reverse or cell.reverse;
        };
        try std.testing.expect(reverse and !observed.screen.cursor_visible);
        try std.testing.expect(std.mem.indexOf(u8, child.output.items, "\x1b_pi:") == null);
        try observed.send(&child, "a", "NATIVE_INPUT:a界😀");
        try observed.send(&child, "\x1b[Db", "NATIVE_INPUT:ba界😀");
        try observed.send(&child, "\x05\x1b[200~ \tZ\r\n\x1b[201~", "ba界😀     Z");
        try observed.send(&child, "q", "ba界😀     Zq");
        // The actual app overrides standalone TUI undo to Ctrl+Z on Windows.
        // A prefix match for Z would also accept the still-visible Zq frame.
        const undo_frame = observed.screen.frames;
        try child.send(if (builtin.os.tag == .windows) "\x1a" else "\x1f");
        try observed.waitAbsent(&child, "ba界😀     Zq", undo_frame);
        try std.testing.expect(try observed.screen.contains("NATIVE_INPUT:ba界😀     Z"));
        try observed.send(&child, "\r", "PUBLIC_INPUT_DONE:\"ba界😀     Z\"");
        try observed.send(&child, "/public-input\r", "NATIVE_INPUT:界😀");
        try observed.send(&child, "\x1b", "PUBLIC_INPUT_DONE:\"CANCELLED\"");
        try observed.send(&child, "after-public-input", "> after-public-input");
        try cleanExit(&fixture, &child, &observed);
    }
}

test "native Source1ced fake cursor paints focused and unfocused real cells with hardware disabled" {
    if (!pty.supported()) return error.SkipZigTest;
    for ([_][]const u8{ "regular", "fullscreen" }) |mode| {
        var fixture = try Fixture.init(mode);
        defer fixture.deinit();
        const settings = try std.fmt.allocPrint(std.testing.allocator, "{{\"tuiMode\":\"{s}\",\"showHardwareCursor\":false,\"quietStartup\":true,\"enableInstallTelemetry\":false}}", .{mode});
        defer std.testing.allocator.free(settings);
        try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "agent/settings.json", .data = settings });
        const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
        defer errors.close(std.testing.io);
        const source =
            \\import {renderFakeCursor,CURSOR_MARKER} from 'pi-tui';
            \\export default pi=>pi.registerCommand('cursor-proof',{handler(_,ctx){return ctx.ui.custom((tui,theme,keys,done)=>({focused:true,render(){return ['CURSOR_FOCUSED:'+CURSOR_MARKER+renderFakeCursor('界')+':END','CURSOR_UNFOCUSED:'+renderFakeCursor('Ω')+':END']},handleInput(data){if(data==='\x1b')done('cursor-closed')},invalidate(){}}),{overlay:true,overlayOptions:{width:40,height:3,row:5,col:7}}).then(value=>({message:value}))}})
        ;
        var child = try fixture.spawnExtension(errors, source);
        defer child.deinit();
        var observed = try Observer.init();
        defer observed.deinit();
        try observed.waitAny(&child, ">");
        try observed.send(&child, "/cursor-proof\r", "CURSOR_FOCUSED:界:END");
        try observed.waitAny(&child, "CURSOR_UNFOCUSED:Ω:END");
        var focused = false;
        var unfocused = false;
        for (observed.screen.cells()) |cell| {
            if (cell.scalar == '界') focused = focused or cell.reverse;
            if (cell.scalar == 'Ω') unfocused = unfocused or cell.reverse;
        }
        try std.testing.expect(focused and unfocused);
        try std.testing.expect(!observed.screen.cursor_visible);
        try std.testing.expect(std.mem.indexOf(u8, child.output.items, "\x1b_pi:") == null);
        try observed.send(&child, "\x1b", "cursor-closed");
        try observed.send(&child, "after-cursor", "> after-cursor");
        try cleanExit(&fixture, &child, &observed);
    }
}

test "real custom editor original modal input replaces editor row changes submits resizes reloads and restores terminal" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnEditor(errors, @import("test_support/upstream_modal_editor_031b.zig").source);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.waitInitialStartup(&child, "INSERT");
    try observed.send(&child, "modal Ω🦊", "> modal Ω🦊");
    try observed.send(&child, "\x1b", "NORMAL");
    try observed.send(&child, "hiX", "> modal ΩX🦊");
    try std.testing.expect(try observed.screen.contains("INSERT"));
    try observed.send(&child, "\r", "stream-first");
    try observed.wait(&child, "stream-final", 0);
    try observed.send(&child, "retained-draft", "> retained-draft");
    const before_resize = observed.screen.frames;
    try observed.screen.resize(70, 22);
    try child.resize(70, 22);
    try observed.wait(&child, "INSERT", before_resize);
    try std.testing.expect(try observed.screen.contains("> retained-draft"));
    try observed.send(&child, "\x15/reload\r", "Reloaded:");
    try observed.wait(&child, "INSERT", 0);
    try observed.send(&child, "after-reload-draft", "> after-reload-draft");
    try cleanExit(&fixture, &child, &observed);
}

const owned_editor_extension =
    \\import {CustomEditor} from 'pi-coding-agent';import {matchesKey} from 'pi-tui';
    \\let disposed=0,installed=false;
    \\export default pi=>{
    \\ pi.on('session_start',(_,ctx)=>{
    \\  class OwnedEditor extends CustomEditor {
    \\   dispose(){disposed++}
    \\   handleInput(data){
    \\    this.lastKey=JSON.stringify(data);
    \\    if(matchesKey(data,'ctrl+r')){ctx.ui.setEditorComponent(undefined);return}
    \\    if(matchesKey(data,'ctrl+g')){this.tui.setFocus(null);setTimeout(()=>this.tui.setFocus(this),1200);return}
    \\    super.handleInput(data);
    \\   }
    \\   render(width){return ['OWNED_WIDTH:'+width+' FOCUS:'+this.focused+' KEY:'+this.lastKey,...super.render(width)]}
    \\  }
    \\  ctx.ui.setEditorComponent((tui,theme,kb)=>{installed=true;return new OwnedEditor(tui,theme,kb)});
    \\ });
    \\ pi.registerCommand('editor-dialog',{async handler(_,ctx){const accepted=await ctx.ui.confirm('EDITOR_MODAL','Resume owned editor?');ctx.ui.setEditorText(accepted?'modal-restored':'modal-rejected');return {}}});
    \\ pi.registerCommand('editor-inspect',{handler(_,ctx){ctx.ui.notify('EDITOR_DISPOSED:'+disposed);return {}}});
    \\ pi.registerCommand('owned-ready',{handler(_,ctx){if(!installed)throw Error('owned editor factory not installed');ctx.ui.notify('OWNED_FIXTURE_READY:OWNER_INSTALLED');return {}}});
    \\}
;

const autocomplete_extension =
    \\let aborts=0,installed=false;
    \\export default pi=>{
    \\ pi.on('session_start',(_,ctx)=>ctx.ui.addAutocompleteProvider(current=>{installed=true;return {
    \\  triggerCharacters:['%'],
    \\  async getSuggestions(lines,line,col,options){
    \\   const value=lines[line];if(!value.startsWith('%'))return await current.getSuggestions(lines,line,col,options);
    \\   if(value==='%error')throw new Error('autocomplete-original-rejection');
    \\   await new Promise(resolve=>{const timer=setTimeout(resolve,250);options.signal.addEventListener('abort',()=>{aborts++;clearTimeout(timer);resolve()},{once:true})});
    \\   if(options.signal.aborted)return null;return {prefix:value,items:[{value:'one',label:'Plugin One'},{value:'two',label:'Plugin Two',description:'selected second'}]};
    \\  },
    \\  applyCompletion(...args){return current.applyCompletion(...args)}
    \\ }}));
    \\ pi.registerCommand('auto-inspect',{handler(_,ctx){ctx.ui.notify('AUTO_ABORTS:'+aborts);return {}}});
    \\ pi.registerCommand('auto-ready',{handler(_,ctx){if(!installed)throw Error('autocomplete wrapper not installed');ctx.ui.notify('AUTO_FIXTURE_READY:OWNER_INSTALLED');return {}}});
    \\}
;
test "real custom editor autocomplete asynchronous wrapper dropdown selection fallback cancellation error resize and reload" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnEditor(errors, autocomplete_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.acknowledgeStartup(&child, "/auto-ready\r", "AUTO_FIXTURE_READY:OWNER_INSTALLED");
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "%", "> %");
    try observed.wait(&child, "→ Plugin One", 0);
    try observed.send(&child, "\x1b[B", "→ Plugin Two");
    try observed.send(&child, "\t", "> two");
    try std.testing.expect(!try observed.screen.contains("Plugin One"));
    try observed.send(&child, "\x15/hel\t", "> /help");
    try observed.send(&child, "\x15%cancel", "> %cancel");
    try observed.send(&child, "\x15fresh", "> fresh");
    try std.testing.io.sleep(.fromMilliseconds(400), .awake);
    try observed.drain(&child);
    try std.testing.expect(!try observed.screen.contains("Plugin One"));
    try observed.send(&child, "\x15%error", "> %error");
    try observed.wait(&child, "autocomplete-original-rejection", 0);
    try observed.send(&child, "\x15%", "→ Plugin One");
    const before_resize = observed.screen.frames;
    try observed.screen.resize(70, 22);
    try child.resize(70, 22);
    try observed.wait(&child, "Plugin One", before_resize);
    try observed.send(&child, "\x1b", "> %");
    const before_cancel = observed.screen.frames;
    try observed.waitAbsent(&child, "Plugin One", before_cancel -| 1);
    try observed.send(&child, "\x15/reload\r", "Reloaded:");
    try observed.send(&child, "%", "→ Plugin One");
    try observed.send(&child, "\t", "> one");
    try cleanExit(&fixture, &child, &observed);
}
test "real custom editor focus modal handoff retained draft default restoration and owner disposal" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnEditor(errors, owned_editor_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.acknowledgeStartup(&child, "/owned-ready\r", "OWNED_FIXTURE_READY:OWNER_INSTALLED");
    try observed.wait(&child, "OWNED_WIDTH:100 FOCUS:true", 0);
    try observed.send(&child, "focus-draft Ω", "> focus-draft Ω");
    try observed.send(&child, "\x07", "FOCUS:false");
    const before_focus = observed.screen.frames;
    try child.send("LOST");
    try observed.wait(&child, "FOCUS:true", before_focus);
    if (!try observed.screen.contains("> focus-draft Ω")) return error.CustomEditorFocusDraftLost;
    if (try observed.screen.contains("LOST")) return error.CustomEditorUnfocusedInputDelivered;
    try child.send("\x15/editor-dialog\r");
    try observed.waitAny(&child, "EDITOR_MODAL");
    try child.send("y\r");
    try observed.wait(&child, "> modal-restored", 0);
    if (!try observed.screen.contains("OWNED_WIDTH:100 FOCUS:true")) return error.CustomEditorModalFocusNotRestored;
    const before_restore = observed.screen.frames;
    try child.send("\x12");
    try observed.waitAbsent(&child, "OWNED_WIDTH:", before_restore);
    try observed.waitAny(&child, "> modal-restored");
    if (try observed.screen.contains("OWNED_WIDTH:")) return error.CustomEditorDefaultNotRestored;
    try observed.send(&child, "\x15/editor-inspect\r", "EDITOR_DISPOSED:1");
    try cleanExit(&fixture, &child, &observed);
}

test "real native renderer mailbox updates idle durable tool slots resizes and preserves editor and scroll anchor" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnRenderer(errors, renderer_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.acknowledgeStartup(&child, "/renderer-ready\r", "RENDERER_FIXTURE_READY:OWNER_INSTALLED");
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "run-render\r", "ROW_RESULT:early:100:partial:seed:true");
    try std.testing.expect(!try observed.screen.contains("turn-complete"));
    try observed.wait(&child, "ROW_RESULT:early:100:done:seed:false", observed.screen.frames);
    try observed.wait(&child, "turn-complete", 0);
    try std.testing.expect(try observed.screen.contains("ROW_CALL:early:100:seed"));
    try observed.send(&child, "renderer-draft", "> renderer-draft");
    try observed.send(&child, "\x1b[1;5H", "history-row-000");
    // The early current-cell assertions are complete before the real idle
    // timer is admitted. CPU/PTY batching cannot supersede them beforehand.
    const before_idle_frame = observed.screen.frames;
    try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "renderer-phase-ack", .data = "observer-ready" });
    try waitFixtureSignal(&fixture, &child, "renderer-phase-rendered");
    try observed.wait(&child, "history-row-000", before_idle_frame);
    try observed.drain(&child);
    try std.testing.expect(try observed.screen.contains("history-row-000"));
    try std.testing.expect(try observed.screen.contains("> renderer-draft"));
    try observed.send(&child, "\x1b[1;5F", "ROW_RESULT:late:100:done:seed:false");
    try std.testing.expect(try observed.screen.contains("ROW_CALL:late:100:seed"));
    const before_resize = observed.screen.frames;
    try observed.screen.resize(70, 22);
    try child.resize(70, 22);
    try observed.wait(&child, "ROW_RESULT:late:70:done:seed:false", before_resize);
    try std.testing.expect(try observed.screen.contains("ROW_CALL:late:70:seed"));
    try std.testing.expect(try observed.screen.contains("> renderer-draft"));
    const cells = try observed.screen.textAlloc(std.testing.allocator);
    defer std.testing.allocator.free(cells);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, cells, "ROW_CALL:"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, cells, "ROW_RESULT:"));
    try observed.send(&child, "\x15/reload\r", "Reloaded:");
    try std.testing.expect(!try observed.screen.contains("ROW_RESULT:"));
    try cleanExit(&fixture, &child, &observed);
}

const renderer_error_extension =
    \\import fs from 'node:fs';import {Type} from '@earendil-works/pi-ai';export default pi=>{pi.registerCommand('renderer-ready',{handler(_args,ctx){ctx.ui.notify('RENDERER_FIXTURE_READY:OWNER_INSTALLED')}});pi.registerTool({name:'animated',label:'Animated',description:'Native renderer original error',parameters:Type.Object({value:Type.String()}),execute(id,args){return {content:[{type:'text',text:'done:'+args.value}]}},renderCall(args,theme,ctx){return {render(width){return ['ERROR_CALL:'+width]}}},renderResult(result,options,theme,ctx){if(!ctx.state.scheduled){ctx.state.scheduled=true;const ack=setInterval(()=>{if(!fs.existsSync('renderer-error-phase-ack'))return;clearInterval(ack);setTimeout(()=>{ctx.state.fail=true;ctx.invalidate()},700)},5)}return {render(width){if(ctx.state.fail){fs.writeFileSync('renderer-error-phase-fired','original-error');throw new Error('renderer-original-diagnostic')}return ['ERROR_RESULT:'+width]}}}})}
;

test "real native renderer idle original error keeps canonical result draft and next turn usable" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnRenderer(errors, renderer_error_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.acknowledgeStartup(&child, "/renderer-ready\r", "RENDERER_FIXTURE_READY:OWNER_INSTALLED");
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "render-error\r", "ERROR_RESULT:100");
    const initial_result_frame = observed.screen.frames;
    try observed.wait(&child, "turn-complete", 0);
    try observed.send(&child, "error-draft", "> error-draft");
    // Admit the actual idle failure only after its initial current cells,
    // completed turn and editor draft have all been observed. The 700 ms
    // timer and five-second render assertion retain their original deadlines.
    try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "renderer-error-phase-ack", .data = "observer-ready" });
    try observed.wait(&child, "renderer-original-diagnostic", initial_result_frame);
    try waitFixtureSignal(&fixture, &child, "renderer-error-phase-fired");
    try std.testing.expect(try observed.screen.contains("done:seed"));
    try std.testing.expect(try observed.screen.contains("> error-draft"));
    try observed.send(&child, "\x15next\r", "after-reload");
    try cleanExit(&fixture, &child, &observed);
}

test "real regular native tool partial callback retains canonical output and completes without group reentry" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("regular");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnRenderer(errors, renderer_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.waitAny(&child, ">");
    try child.send("regular-render\r");
    try observed.waitAny(&child, "partial:seed");
    try observed.waitAny(&child, "ROW_RESULT:early:100:done:seed:false");
    try observed.waitAny(&child, "turn-complete");
    try std.testing.expect(!observed.screen.in_alternate);
    try child.send("/quit\r");
    const term = try child.wait(5000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const stderr = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

const custom_extension =
    \\export default function(pi) {
    \\ pi.registerCommand('fixture-ready',{handler(_,ctx){ctx.ui.notify('FIXTURE_READY:HEADER_EDITOR_COMMAND_ACK');return {}}});
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
    try observed.waitAny(&child, ">");
    try std.testing.expect(try observed.screen.contains("pi (pi-zig)"));
    const startup_frame = observed.screen.frames;
    try child.send("/fixture-ready\r");
    try observed.waitStartupCommand(&child, startup_frame);
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
    \\import fs from 'node:fs';export default function(pi){pi.registerCommand('restore-focus',{async handler(_,ctx){
    \\ let h,rootInput='',baseInput='',phase='root';ctx.ui.setEditorText('restore-draft');
    \\ const afterAck=(file,delay,run)=>{const ack=setInterval(()=>{if(!fs.existsSync(file))return;clearInterval(ack);setTimeout(run,delay)},5)};
    \\ const result=await ctx.ui.custom((tui,theme,keys,done)=>{
    \\  const base={focused:false,handleInput(data){baseInput+=data;if(data==='b'){phase='cleared';h.unfocus({target:null});afterAck('focus-cleared-ack',1000,()=>{phase='root-again';h.focus();tui.requestRender()})}}};
    \\  const root={focused:false,render(){return ['RESTORE_PHASE:'+phase,'RESTORE_ROOT:'+rootInput+':'+root.focused,'RESTORE_BASE:'+baseInput+':'+base.focused]},handleInput(data){rootInput+=data;if(data==='s'){phase='stolen';tui.setFocus(base)}else if(data==='n'){phase='blocked-null';tui.setFocus(base);afterAck('focus-blocked-ack',300,()=>{tui.setFocus(null);phase='root-null-restored';tui.requestRender()})}else if(data==='d'){phase='deferred';tui.setFocus(base);h.unfocus({target:null});afterAck('focus-deferred-ack',300,()=>{tui.setFocus(null);phase='deferred-cleared';tui.requestRender();afterAck('focus-resume-ack',700,()=>{h.focus();phase='root-deferred-returned';tui.requestRender()})})}else if(data==='u'){phase='base';h.unfocus({target:base})}else if(data==='q')done('done')}};
    \\  return root;
    \\ },{overlay:true,overlayOptions:{width:60,nonCapturing:true,anchor:'top-left'},onHandle(handle){h=handle;h.focus()}});
    \\ ctx.ui.notify('RESTORE_RESULT:'+result);
    \\}})}
;

const widget_extension =
    \\let disposed=0,redraw=null;export default pi=>{
    \\ pi.on('session_start',(_,ctx)=>{
    \\  ctx.ui.setWidget('factory',(tui,theme)=>{let phase='first';const initialColumns=tui.terminal.columns;redraw=()=>{phase='changed';tui.requestRender()};return {render(width){return [theme.fg('accent','WIDGET_WIDTH:'+width+':'+phase+':COLS:'+tui.terminal.columns+':FACTORY:'+initialColumns)]},invalidate(){},dispose(){disposed++}}},{placement:'belowEditor'});
    \\  ctx.ui.setWidget('upper',(tui,theme)=>({render(width){return ['WIDGET_ABOVE:'+width]},dispose(){disposed++}}));
    \\ });
    \\ pi.registerCommand('widget-redraw',{handler(){redraw();return {}}});
    \\ pi.registerCommand('widget-replace',{handler(_,ctx){ctx.ui.setWidget('factory',(tui,theme)=>({render(width){return ['WIDGET_REPLACED:'+width+':DISPOSED:'+disposed]},dispose(){disposed++}}),{placement:'aboveEditor'});return {}}});
    \\ pi.registerCommand('widget-clear',{handler(_,ctx){ctx.ui.setWidget('factory',undefined);ctx.ui.setWidget('upper',undefined);ctx.ui.notify('WIDGET_CLEARED:DISPOSED:'+disposed);return {}}});
    \\ pi.registerCommand('widget-timer',{handler(_,ctx){setTimeout(()=>ctx.ui.setWidget('later',()=>({render(width){return ['WIDGET_IDLE:'+width]}}),{placement:'belowEditor'}),100);return {}}});
    \\ pi.registerCommand('widget-inspect',{handler(_,ctx){ctx.ui.notify('WIDGET_DISPOSED:'+disposed);return {}}});
    \\}
;

test "actual no Node native widget factories render width placement redraw replacement clearing reload and rooted teardown" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnExtension(errors, widget_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "WIDGET_WIDTH:100:first:COLS:100:FACTORY:100", 0);
    try observed.wait(&child, "WIDGET_ABOVE:100", 0);
    try observed.send(&child, "/widget-redraw\r", "WIDGET_WIDTH:100:changed:COLS:100");
    const frame = observed.screen.frames;
    try observed.screen.resize(70, 22);
    try child.resize(70, 22);
    try observed.wait(&child, "WIDGET_WIDTH:70:changed:COLS:70", frame);
    try observed.wait(&child, "WIDGET_ABOVE:70", 0);
    try observed.send(&child, "/widget-timer\r", "WIDGET_IDLE:70");
    try observed.send(&child, "/widget-replace\r", "WIDGET_REPLACED:70:DISPOSED:1");
    try std.testing.expect(!try observed.screen.contains("WIDGET_WIDTH:"));
    try observed.send(&child, "/widget-clear\r", "WIDGET_CLEARED:DISPOSED:3");
    try std.testing.expect(!try observed.screen.contains("WIDGET_REPLACED:"));
    try std.testing.expect(!try observed.screen.contains("WIDGET_ABOVE:"));
    try observed.send(&child, "/reload\r", "Reloaded:");
    try observed.wait(&child, "WIDGET_WIDTH:70:first:COLS:70:FACTORY:70", 0);
    try cleanExit(&fixture, &child, &observed);
}

test "actual no Node regular native widgets project retained factories replacement clearing and idle callback without invocation corruption" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("regular");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnExtension(errors, widget_extension);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.waitAny(&child, "WIDGET_WIDTH:100:first:COLS:100");
    try child.send("/widget-replace\r");
    try observed.waitAny(&child, "WIDGET_REPLACED:100:DISPOSED:1");
    try child.send("/widget-timer\r");
    try observed.waitAny(&child, ">");
    try child.send("/widget-inspect\r");
    try observed.waitAny(&child, "WIDGET_DISPOSED:1");
    try child.send("/widget-clear\r");
    try observed.waitAny(&child, "WIDGET_CLEARED:DISPOSED:3");
    try child.send("/quit\r");
    const term = try child.wait(5000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const stderr = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

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
    try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "focus-blocked-ack", .data = "observer-ready" });
    try observed.wait(&child, "RESTORE_PHASE:root-null-restored", observed.screen.frames);
    try std.testing.expect(try observed.screen.contains("RESTORE_ROOT:sxn:true"));
    try observed.send(&child, "d", "RESTORE_PHASE:deferred");
    try std.testing.expect(try observed.screen.contains("RESTORE_BASE::true"));
    try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "focus-deferred-ack", .data = "observer-ready" });
    try observed.wait(&child, "RESTORE_PHASE:deferred-cleared", observed.screen.frames);
    try std.testing.expect(try observed.screen.contains("RESTORE_ROOT:sxnd:false"));
    try std.testing.expect(try observed.screen.contains("RESTORE_BASE::false"));
    const no_resume_frame = observed.screen.frames;
    try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "focus-resume-ack", .data = "observer-ready" });
    try child.send("LOST");
    try observed.wait(&child, "RESTORE_PHASE:root-deferred-returned", no_resume_frame);
    try std.testing.expect(!try observed.screen.contains("LOST"));
    try observed.send(&child, "u", "RESTORE_PHASE:base");
    try observed.send(&child, "b", "RESTORE_PHASE:cleared");
    try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "focus-cleared-ack", .data = "observer-ready" });
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
fn waitFixtureSignal(fixture: *Fixture, child: *pty.Session, name: []const u8) !void {
    const end = Io.Clock.awake.now(child.io).toMilliseconds() + 5000;
    while (Io.Clock.awake.now(child.io).toMilliseconds() < end) {
        fixture.scratch.dir.access(child.io, name, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                if (try child.exited()) return error.FixtureExitedBeforePhaseAck;
                try child.io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => return err,
        };
        return;
    }
    return error.FixturePhaseAckTimeout;
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
    fn waitAllVisible(self: *Observer, child: *pty.Session, markers: []const []const u8, after_frame: usize) !void {
        // Resized editor and persistent surfaces publish separately. Observe
        // the complete current scene within the same five-second deadline.
        const end = Io.Clock.awake.now(child.io).toMilliseconds() + 5000;
        while (Io.Clock.awake.now(child.io).toMilliseconds() < end) {
            try self.drain(child);
            var complete = !self.screen.synchronized_update and self.screen.frames > after_frame;
            for (markers) |marker| complete = complete and try self.screen.contains(marker);
            if (complete) return;
            if (try child.exited()) break;
            try child.io.sleep(.fromMilliseconds(10), .awake);
        }
        const cells = try self.screen.textAlloc(std.testing.allocator);
        defer std.testing.allocator.free(cells);
        std.debug.print("Resized persistent scene incomplete; frames={d}; cells:\n{s}\n", .{ self.screen.frames, cells });
        return error.ResizedPersistentSceneIncomplete;
    }
    fn send(self: *Observer, child: *pty.Session, input: []const u8, marker: []const u8) !void {
        const frame = self.screen.frames;
        try child.send(input);
        try self.wait(child, marker, frame);
    }
    fn waitStartupCommand(self: *Observer, child: *pty.Session, after_frame: usize) !void {
        return self.waitStartupMarker(child, "FIXTURE_READY:HEADER_EDITOR_COMMAND_ACK", after_frame);
    }
    fn acknowledgeStartup(self: *Observer, child: *pty.Session, command: []const u8, marker: []const u8) !void {
        try self.waitInitialStartup(child, ">");
        try std.testing.expect(try self.screen.contains("pi (pi-zig)"));
        const frame = self.screen.frames;
        try child.send(command);
        try self.waitStartupMarker(child, marker, frame);
    }
    fn waitInitialStartup(self: *Observer, child: *pty.Session, marker: []const u8) !void {
        // Includes executable, VM and frontend ownership admission, using
        // the already established child startup budget. Render assertions
        // after admission retain their separate five-second deadlines.
        const end = Io.Clock.awake.now(child.io).toMilliseconds() + 90_000;
        while (Io.Clock.awake.now(child.io).toMilliseconds() < end) {
            try self.drain(child);
            if (!self.screen.synchronized_update and try self.screen.contains(marker)) return;
            if (try child.exited()) break;
            try child.io.sleep(.fromMilliseconds(10), .awake);
        }
        const cells = try self.screen.textAlloc(std.testing.allocator);
        defer std.testing.allocator.free(cells);
        std.debug.print("Native frontend startup missing {s}; cells:\n{s}\n", .{ marker, cells });
        return error.NativeFrontendStartupNotReady;
    }
    fn waitStartupMarker(self: *Observer, child: *pty.Session, marker: []const u8, after_frame: usize) !void {
        // Startup includes native-owner and bridge attachment after the first
        // header/editor frame. Its existing child budget is distinct from the
        // five-second current-cell render assertions that follow admission.
        const deadline = Io.Clock.awake.now(child.io).toMilliseconds() + 90_000;
        while (Io.Clock.awake.now(child.io).toMilliseconds() < deadline) {
            try self.drain(child);
            if (!self.screen.synchronized_update and self.screen.frames > after_frame and try self.screen.contains(marker)) return;
            if (try child.exited()) break;
            try child.io.sleep(.fromMilliseconds(10), .awake);
        }
        return error.FrontendStartupCommandReadinessTimedOut;
    }
    fn waitAbsent(self: *Observer, child: *pty.Session, marker: []const u8, after_frame: usize) !void {
        const end = Io.Clock.awake.now(child.io).toMilliseconds() + 5000;
        while (Io.Clock.awake.now(child.io).toMilliseconds() < end) {
            try self.drain(child);
            if (!self.screen.synchronized_update and self.screen.frames > after_frame and !try self.screen.contains(marker)) return;
            if (try child.exited()) break;
            try child.io.sleep(.fromMilliseconds(10), .awake);
        }
        const remaining_cells = try self.screen.textAlloc(std.testing.allocator);
        defer std.testing.allocator.free(remaining_cells);
        std.debug.print("Terminal cells still contain {s}:\n{s}\n", .{ marker, remaining_cells });
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

test "real fullscreen CLI applies native command and hook actions before throw at the live safe point" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnExtension(errors,
        \\export default pi=>{pi.registerCommand('reject',{handler(){pi.appendEntry('command-before-one',{value:'Ω🦊'});pi.appendEntry('command-before-two',{});pi.sendUserMessage('prethrow-live-turn');throw Error('command-original-diagnostic')}});pi.on('before_agent_start',()=>{pi.appendEntry('hook-before-three',{});throw Error('hook-original-diagnostic')})}
    );
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "/reject\r", "command-original-diagnostic");
    // The command's admitted user message must trigger a turn without another
    // keyboard event, despite its later rejection.
    try observed.wait(&child, "stream-final", 0);
    const saved = try fixture.scratch.dir.readFileAlloc(std.testing.io, "history.jsonl", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(saved);
    const first = std.mem.indexOf(u8, saved, "command-before-one") orelse return error.MissingPrethrowCommandAction;
    const second = std.mem.indexOf(u8, saved, "command-before-two") orelse return error.MissingPrethrowCommandAction;
    const third = std.mem.indexOf(u8, saved, "hook-before-three") orelse return error.MissingPrethrowHookAction;
    try std.testing.expect(first < second and second < third);
    try std.testing.expect(std.mem.indexOf(u8, saved, "Ω🦊") != null);
    try cleanExit(&fixture, &child, &observed);
}

test "native late live fullscreen command discovery completion and next agent tool turn preserve actual session evidence" {
    if (!pty.supported()) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawnLateRegistration(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "/seed\r", "late-live-seeded");
    try observed.send(&child, "/la\t", "> /late");
    try observed.send(&child, "\r", "late-live-command");
    const turn_started_ms = Io.Clock.awake.now(child.io).toMilliseconds();
    observed.send(&child, "invoke-the-new-tool\r", "late-live-turn-complete") catch |cause| {
        std.debug.print("Late tool PTY diagnostic elapsedMs={d} bytes={d} consumed={d} synchronized={any} frames={d} rawFinalMarker={any}; bounded raw tail:\n{s}\n", .{
            Io.Clock.awake.now(child.io).toMilliseconds() - turn_started_ms,
            child.output.items.len,
            observed.consumed,
            observed.screen.synchronized_update,
            observed.screen.frames,
            std.mem.indexOf(u8, child.output.items, "late-live-turn-complete") != null,
            child.output.items[child.output.items.len - @min(child.output.items.len, 16384) ..],
        });
        for ([_][]const u8{ "late-execute-witness", "stderr.log", "history.jsonl" }) |name| {
            const bytes = fixture.scratch.dir.readFileAlloc(std.testing.io, name, std.testing.allocator, .limited(1024 * 1024)) catch |read_cause| {
                std.debug.print("Late tool diagnostic {s}: {s}\n", .{ name, @errorName(read_cause) });
                continue;
            };
            defer std.testing.allocator.free(bytes);
            std.debug.print("Late tool diagnostic {s}:\n{s}\n", .{ name, bytes });
        }
        return cause;
    };
    // Final text can paint before Main finishes turn hooks and saves history.
    // The next /quit command and clean exit acknowledge that owner's finish.
    try cleanExit(&fixture, &child, &observed);
    const saved = try fixture.scratch.dir.readFileAlloc(std.testing.io, "history.jsonl", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "late-live-tool-result") != null);
    try std.testing.expect(std.mem.indexOf(u8, saved, "late-live-tool") != null);
    try std.testing.expect(std.mem.indexOf(u8, saved, "late-live-turn-complete") != null);
}
