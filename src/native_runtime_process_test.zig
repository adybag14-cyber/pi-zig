//! Real Runtime/Host integration with the standalone native worker and no Node.
const std = @import("std");
const builtin = @import("builtin");
const runtime_mod = @import("extensions/js_runtime.zig");
const host_mod = @import("extensions/host.zig");
const ui_mod = @import("extensions/ui.zig");
const integration_mod = @import("extensions/integration.zig");

const source =
    \\import {Type} from 'typebox';
    \\export default function(pi){let calls=0;
    \\pi.on('native_hook',async(event,ctx)=>{if(!(ctx.signal instanceof AbortSignal)||event.signal!==ctx.signal)throw Error('hook signal');await new Promise(resolve=>setTimeout(resolve,1));return {prompt:'hook:'+ctx.sessionManager.getSessionId()+':'+event.value}});
    \\pi.registerTool({name:'native_tool',parameters:Type.Object({mode:Type.String()}),async execute(id,args,signal,update,ctx){
    \\ if(!(signal instanceof AbortSignal)||ctx.signal!==signal)throw Error('tool signal');
    \\ if(args.mode==='wait'){update({content:[{type:'text',text:'live-update'}],details:{callId:id,cwd:ctx.cwd,setting:pi.getSettings().marker}});if(!signal.aborted)await new Promise(resolve=>signal.addEventListener('abort',resolve,{once:true}));return {content:[{type:'text',text:'cancelled:'+id}],details:{aborted:signal.aborted,session:ctx.sessionManager.getSessionId()}}}
    \\ if(args.mode==='ignore')return new Promise(()=>{});
    \\ if(args.mode==='error')throw Error('native-owned-error');
    \\ await new Promise(resolve=>setTimeout(resolve,1));calls++;return {content:[{type:'text',text:'native:'+id+':'+calls}],details:{session:ctx.sessionManager.getSessionId(),cwd:ctx.cwd,setting:pi.getSettings().marker}};
    \\}});
    \\pi.registerProvider('native callback',{name:'Native Provider',async key(value,signal){if(!(signal instanceof AbortSignal))throw Error('provider signal');if(value==='wait'&&!signal.aborted)await new Promise(resolve=>signal.addEventListener('abort',resolve,{once:true}));return this.name+':'+value+':'+signal.aborted}});
    \\}
;

const Fixture = struct {
    tmp: std.testing.TmpDir,
    root: []u8,
    source_path: []u8,
    executable: []u8,
    environment: std.process.Environ.Map,

    fn init() !Fixture {
        const gpa = std.testing.allocator;
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        try tmp.dir.createDirPath(io, "extensions");
        try tmp.dir.writeFile(io, .{ .sub_path = "extensions/native.ts", .data = source });
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try tmp.dir.realPath(io, &buffer);
        const root = try gpa.dupe(u8, buffer[0..length]);
        errdefer gpa.free(root);
        const source_path = try std.fs.path.join(gpa, &.{ root, "extensions", "native.ts" });
        errdefer gpa.free(source_path);
        const executable = try std.fs.path.resolve(gpa, &.{ "zig-out", "bin", if (builtin.os.tag == .windows) "pi.exe" else "pi" });
        errdefer gpa.free(executable);
        var environment: std.process.Environ.Map = .init(gpa);
        errdefer environment.deinit();
        try environment.put("PATH", std.fs.path.dirname(executable).?);
        return .{ .tmp = tmp, .root = root, .source_path = source_path, .executable = executable, .environment = environment };
    }

    fn options(self: *Fixture) runtime_mod.Runtime.NativeOptions {
        return .{ .executable = self.executable, .environ_map = &self.environment };
    }

    fn noBridge(self: *Fixture) !void {
        var dir = try self.tmp.dir.openDir(std.testing.io, "extensions", .{ .iterate = true });
        defer dir.close(std.testing.io);
        var iterator = dir.iterate();
        while (try iterator.next(std.testing.io)) |entry| try std.testing.expect(!std.mem.startsWith(u8, entry.name, ".pi-zig-js-bridge-"));
    }

    fn deinit(self: *Fixture) void {
        self.environment.deinit();
        std.testing.allocator.free(self.executable);
        std.testing.allocator.free(self.source_path);
        std.testing.allocator.free(self.root);
        self.tmp.cleanup();
    }
};

fn callbackId(manifest: []const u8) ![]u8 {
    const gpa = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, manifest, .{});
    defer parsed.deinit();
    const providers = parsed.value.object.get("providers").?.array.items;
    for (providers) |provider| {
        if (std.mem.eql(u8, provider.object.get("name").?.string, "native callback")) {
            return gpa.dupe(u8, provider.object.get("config").?.object.get("key").?.object.get("__pi_callback_id").?.string);
        }
    }
    return error.NativeFixtureProviderMissing;
}

const Updates = struct {
    aborted: *bool,
    calls: usize = 0,
    json: ?[]u8 = null,

    fn raw(context: ?*anyopaque, update: []const u8) !void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        if (self.json) |previous| std.testing.allocator.free(previous);
        self.json = try std.testing.allocator.dupe(u8, update);
        self.calls += 1;
        @atomicStore(bool, self.aborted, true, .release);
    }

    fn hosted(context: ?*anyopaque, update: *const host_mod.ToolUpdate) !void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        try std.testing.expectEqualStrings("live-update", update.content);
        try raw(self, update.details_json.?);
    }

    fn deinit(self: *@This()) void {
        if (self.json) |json| std.testing.allocator.free(json);
    }
};

test "native runtime uses standalone pipes for hooks tools provider callbacks live abort and reuse without Node" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const runtime = started.runtime;
    try std.testing.expectEqual(runtime_mod.Backend.native, runtime.backend);
    try std.testing.expectEqual(@as(usize, 0), runtime.bridge_path.len);
    try fixture.noBridge();
    try runtime.setContextJson("{\"cwd\":\"native-cwd\",\"sessionId\":\"runtime-session\",\"settings\":{\"marker\":\"native-setting\"}}");
    const hook = try runtime.invokeHook("native_hook", "{\"value\":\"input\"}", "{}");
    defer gpa.free(hook);
    try std.testing.expect(std.mem.indexOf(u8, hook, "hook:runtime-session:input") != null);
    var aborted = false;
    var updates: Updates = .{ .aborted = &aborted };
    defer updates.deinit();
    const cancelled = try runtime.invokeToolCallStreaming("owned-call", "native_tool", "{\"mode\":\"wait\"}", "{}", &aborted, Updates.raw, &updates);
    defer gpa.free(cancelled);
    try std.testing.expectEqual(@as(usize, 1), updates.calls);
    try std.testing.expect(std.mem.indexOf(u8, updates.json.?, "owned-call") != null);
    try std.testing.expect(std.mem.indexOf(u8, updates.json.?, "native-setting") != null);
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "cancelled:owned-call") != null);
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "\"aborted\":true") != null);
    try std.testing.expect(!runtime.closed);
    aborted = false;
    const reused = try runtime.invokeToolCall("reused-call", "native_tool", "{\"mode\":\"plain\"}", "{}", &aborted);
    defer gpa.free(reused);
    try std.testing.expect(std.mem.indexOf(u8, reused, "native:reused-call:1") != null);
    const id = try callbackId(started.manifest_json);
    defer gpa.free(id);
    const provider = try runtime.invokeProviderMethod(id, "[\"value\"]", true, &aborted);
    defer gpa.free(provider);
    try std.testing.expect(std.mem.indexOf(u8, provider, "Native Provider:value:false") != null);
    const Abort = struct {
        fn run(task_io: std.Io, flag: *bool) std.Io.Cancelable!void {
            try task_io.sleep(.fromMilliseconds(20), .awake);
            @atomicStore(bool, flag, true, .release);
        }
    };
    var group: std.Io.Group = .init;
    group.async(io, Abort.run, .{ io, &aborted });
    defer {
        group.cancel(io);
        group.await(io) catch {};
    }
    const live = try runtime.invokeProviderMethod(id, "[\"wait\"]", true, &aborted);
    defer gpa.free(live);
    try std.testing.expect(std.mem.indexOf(u8, live, "Native Provider:wait:true") != null);
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, runtime.invokeTool("native_tool", "{\"mode\":\"error\"}", "{}"));
    try std.testing.expect(std.mem.indexOf(u8, runtime.lastError().?, "native-owned-error") != null);
    try std.testing.expect(!runtime.closed);
    try std.testing.expectError(error.NativeExtensionOperationUnsupported, runtime.invokeShortcut("unsupported", "{}"));
    try std.testing.expect(!runtime.closed);
    const after_error = try runtime.invokeTool("native_tool", "{\"mode\":\"plain\"}", "{}");
    defer gpa.free(after_error);
    try std.testing.expect(std.mem.indexOf(u8, after_error, "native:pi-zig-runtime:2") != null);
    try fixture.noBridge();
}

test "native runtime Host discovery explicitly selects native backend and forwards context and live updates" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var host: host_mod.Host = .{ .gpa = gpa, .io = std.testing.io, .script_backend = .native, .native_runtime_options = fixture.options(), .js_runtime_program = "intentionally-missing-node" };
    defer host.deinit();
    try host.setScriptContextJson("{\"cwd\":\"host-cwd\",\"sessionId\":\"host-session\",\"settings\":{\"marker\":\"host-setting\"}}");
    try host.discover(fixture.root, fixture.root, false);
    try std.testing.expectEqual(@as(usize, 1), host.extensions.items.len);
    try std.testing.expectEqual(runtime_mod.Backend.native, host.extensions.items[0].script_runtime.?.backend);
    var hooks = try host.executeHook("native_hook", "{\"value\":\"discovered\"}");
    defer hooks.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), hooks.errors.len);
    try std.testing.expect(std.mem.indexOf(u8, hooks.responses[0].json, "hook:host-session:discovered") != null);
    var aborted = false;
    var updates: Updates = .{ .aborted = &aborted };
    defer updates.deinit();
    var result = (try host.executeToolCallStreaming("host-call", "native_tool", "{\"mode\":\"wait\"}", &aborted, Updates.hosted, &updates)).?;
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("cancelled:host-call", result.content);
    try std.testing.expectEqual(@as(usize, 1), updates.calls);
    try std.testing.expect(std.mem.indexOf(u8, updates.json.?, "host-cwd") != null);
    try std.testing.expect(std.mem.indexOf(u8, updates.json.?, "host-setting") != null);
    var reused = (try host.executeTool("native_tool", "{\"mode\":\"plain\"}")).?;
    defer reused.deinit(gpa);
    try std.testing.expectEqualStrings("native:pi-zig-host:1", reused.content);
    try fixture.noBridge();
    const default_host: host_mod.Host = .{ .gpa = gpa, .io = std.testing.io };
    try std.testing.expectEqual(runtime_mod.Backend.legacy, default_host.script_backend);
}

test "native runtime timeout retires and reaps only its owned native child" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try std.testing.expect(started.runtime.child.id != null);
    started.runtime.timeout_ms = 30;
    try std.testing.expectError(error.JavaScriptExtensionTimeout, started.runtime.invokeTool("native_tool", "{\"mode\":\"ignore\"}", "{}"));
    try std.testing.expect(started.runtime.closed and started.runtime.child.id == null);
    try std.testing.expectError(error.JavaScriptExtensionClosed, started.runtime.invokeHook("native_hook", "{}", "{}"));
    try fixture.noBridge();
}

test "native runtime failed startup owns no bridge and releases every host allocation" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator, fixture: *Fixture) !void {
            const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
            defer started.runtime.deinit();
            defer gpa.free(started.manifest_json);
        }
    };
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{&fixture});
    try fixture.noBridge();
    try std.testing.expectError(error.FileNotFound, runtime_mod.Runtime.startNative(std.testing.allocator, std.testing.io, fixture.source_path, .{ .executable = "intentionally-missing-native-executable", .environ_map = &fixture.environment }));
    try fixture.noBridge();
}

const ui_source =
    \\export default function(pi){let oldUi;const events=[];
    \\pi.on('ui_prompt_start',(event)=>{events.push(event.type+':'+event.kind);pi.appendEntry('ui-event',{event:event.type})});
    \\pi.on('ui_prompt_end',(event)=>{events.push(event.type+':'+event.kind);pi.appendEntry('ui-event',{event:event.type})});
    \\pi.registerCommand('ui',{async handler(mode,ctx){
    \\ if(ctx.ui!==ctx.ui)throw Error('UI object identity');
    \\ if(mode==='roundtrip'){oldUi=ctx.ui;const result=await Promise.all([ctx.ui.select('Pick',['red','green']),ctx.ui.confirm('Okay','Continue?'),ctx.ui.input('Name','hint'),ctx.ui.editor('Edit','prefill')]);ctx.ui.setStatus('mode','active');ctx.ui.setTitle('Native title');ctx.ui.setEditorText('draft');ctx.ui.pasteToEditor('+');ctx.ui.setWidget('row',['one','two'],{placement:'belowEditor'});ctx.ui.notify('done');if(ctx.ui.getEditorText()!=='draft+')throw Error('editor read');return {message:JSON.stringify(result)}}
    \\ if(mode==='headless'){const results=await Promise.all([ctx.ui.select({toString(){throw Error('headless converted')}},[]),ctx.ui.confirm('t','m'),ctx.ui.input('t'),ctx.ui.editor('t')]);if(results[0]!==undefined||results[1]!==false||results[2]!==undefined||results[3]!==undefined)throw Error('headless defaults');return {message:'headless'}}
    \\ if(mode==='cancel'){const c=new AbortController();const pending=ctx.ui.select('Signal',['one'],{signal:c.signal});setTimeout(()=>c.abort(),5);if(await pending!==undefined)throw Error('signal default');if(await ctx.ui.confirm('Timeout','message',{timeout:5})!==false)throw Error('confirm default');if(await ctx.ui.input('Timeout input','',{timeout:5})!==undefined)throw Error('input default');return {message:'cancel-defaults'}}
    \\ if(mode==='live'){if(await ctx.ui.select('Signal',['one'],{signal:ctx.signal})!==undefined)throw Error('live abort default');return {message:'live-cancel'}}
    \\ if(mode==='human'){const result=await ctx.ui.select('Human',['one']);return {message:String(result)}}
    \\ if(mode==='fence'){return {message:'fence:'+String(await ctx.ui.select('Fence',['green']))}}
    \\ if(mode==='errors'){const original=Error('original UI conversion');for(const run of [()=>ctx.ui.select({toString(){throw original}},['a']),()=>ctx.ui.select('t',['a'],{get signal(){throw original}}),()=>ctx.ui.input('t',{toString(){throw original}}),()=>ctx.ui.confirm('t','m',{get timeout(){throw original}})]){const promise=run();if(!(promise instanceof Promise))throw Error('dialog is not asynchronous');let caught=false;try{await promise}catch(error){if(error!==original)throw Error('UI exception replaced');caught=true}if(!caught)throw Error('missing rejection')}let refused=false;try{await ctx.ui.select('Refuse',['one'])}catch(error){if(!String(error).includes('FakeRefused'))throw error;refused=true}if(!refused)throw Error('missing host error');return {message:'errors-preserved'}}
    \\ if(mode==='stale'){let caught=false;try{await oldUi.select('stale',[])}catch(error){caught=true}if(!caught)throw Error('retained UI crossed invocation');return {message:'stale-fenced'}}
    \\ if(mode==='hooks'){return {message:JSON.stringify(events)}}
    \\ return {message:String(await ctx.ui.select('Pick',['one']))};
    \\}})}
;

const DialogUi = struct {
    controller: *ui_mod.Controller,
    io: std.Io = std.testing.io,
    requests: std.atomic.Value(usize) = .init(0),
    active: std.atomic.Value(usize) = .init(0),
    cancelled: std.atomic.Value(usize) = .init(0),
    kinds: std.ArrayList([]u8) = .empty,
    prompt_bridge: ?*integration_mod.Bridge = null,
    abort_flag: ?*bool = null,
    runtime: ?*runtime_mod.Runtime = null,

    fn request(context: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args: []const u8) ![]u8 {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        if (self.active.fetchAdd(1, .acq_rel) != 0) return error.ConcurrentDialog;
        defer _ = self.active.fetchSub(1, .release);
        _ = self.requests.fetchAdd(1, .monotonic);
        try self.kinds.append(std.testing.allocator, try std.testing.allocator.dupe(u8, method));
        if (self.prompt_bridge) |observer| observer.uiPromptEvent(.start, method);
        defer if (self.prompt_bridge) |observer| observer.uiPromptEvent(.end, method);
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, args, .{});
        defer parsed.deinit();
        const title = parsed.value.object.get("title").?.string;
        if (std.mem.eql(u8, title, "Fence")) {
            const runtime = self.runtime.?;
            runtime.write_mutex.lockUncancelable(self.io);
            defer runtime.write_mutex.unlock(self.io);
            var buffer: [2048]u8 = undefined;
            var writer = runtime.child.stdin.?.writerStreaming(self.io, &buffer);
            try writer.interface.writeAll("{\"kind\":\"ui_response\",\"invocationId\":\"99999\",\"id\":1,\"ok\":true,\"result\":\"bad-invocation\"}\n");
            try writer.interface.print("{{\"kind\":\"ui_response\",\"invocationId\":\"{d}\",\"id\":4294967294,\"ok\":true,\"result\":\"bad-request\"}}\n", .{runtime.next_invocation_id - 1});
            try writer.interface.flush();
        }
        if (std.mem.eql(u8, title, "Signal") or std.mem.startsWith(u8, title, "Timeout")) {
            if (self.abort_flag) |flag| @atomicStore(bool, flag, true, .release);
            self.io.sleep(.fromMilliseconds(5000), .awake) catch |err| {
                _ = self.cancelled.fetchAdd(1, .monotonic);
                return err;
            };
        }
        if (std.mem.eql(u8, title, "Human")) try self.io.sleep(.fromMilliseconds(60), .awake);
        if (std.mem.eql(u8, title, "Refuse")) return error.FakeRefused;
        return allocator.dupe(u8, if (std.mem.eql(u8, method, "select")) "\"green\"" else if (std.mem.eql(u8, method, "confirm")) "true" else if (std.mem.eql(u8, method, "input")) "\"Ada\"" else "\"edited\"");
    }

    fn action(context: ?*anyopaque, _: std.mem.Allocator, method: []const u8, args: []const u8) !void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        try self.controller.applyAction(method, args);
    }

    fn bridge(self: *@This()) runtime_mod.UiBridge {
        return .{ .context = self, .request_fn = request, .action_fn = action };
    }

    fn deinit(self: *@This()) void {
        for (self.kinds.items) |kind| std.testing.allocator.free(kind);
        self.kinds.deinit(std.testing.allocator);
    }
};

test "native runtime UI real selector promises FIFO retained actions headless errors and stale methods" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/native.ts", .data = ui_source });
    var controller = try ui_mod.Controller.init(gpa, std.testing.io, false, 80);
    defer controller.deinit();
    var dialogs: DialogUi = .{ .controller = &controller };
    defer dialogs.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.setUiBridge(dialogs.bridge());
    dialogs.runtime = started.runtime;
    try started.runtime.setContextJson("{\"hasUI\":true,\"editorText\":\"before\"}");
    const result = try started.runtime.invokeCommand("ui", "roundtrip", "{}");
    defer gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "green") != null and std.mem.indexOf(u8, result, "Ada") != null and std.mem.indexOf(u8, result, "edited") != null);
    try std.testing.expectEqual(@as(usize, 4), dialogs.requests.load(.acquire));
    for ([_][]const u8{ "select", "confirm", "input", "editor" }, dialogs.kinds.items) |expected, actual| try std.testing.expectEqualStrings(expected, actual);
    try std.testing.expectEqualStrings("Native title", controller.title.?);
    try std.testing.expectEqualStrings("active", controller.statuses.items[0].text);
    try std.testing.expectEqualStrings("draft+", controller.pending_editor_text.?);
    try std.testing.expectEqualStrings("done", controller.notifications.items[0].message);
    try std.testing.expect(controller.widgets.items[0].placement == .below_editor);
    const fenced = try started.runtime.invokeCommand("ui", "fence", "{}");
    defer gpa.free(fenced);
    try std.testing.expect(std.mem.indexOf(u8, fenced, "fence:green") != null);
    const stale = try started.runtime.invokeCommand("ui", "stale", "{}");
    defer gpa.free(stale);
    try std.testing.expect(std.mem.indexOf(u8, stale, "stale-fenced") != null);
    const errors = try started.runtime.invokeCommand("ui", "errors", "{}");
    defer gpa.free(errors);
    try std.testing.expect(std.mem.indexOf(u8, errors, "errors-preserved") != null);
    try started.runtime.setContextJson("{\"hasUI\":false}");
    const before = dialogs.requests.load(.acquire);
    const headless = try started.runtime.invokeCommand("ui", "headless", "{}");
    defer gpa.free(headless);
    try std.testing.expect(std.mem.indexOf(u8, headless, "headless") != null);
    try std.testing.expectEqual(before, dialogs.requests.load(.acquire));
    try std.testing.expect(!started.runtime.closed and dialogs.active.load(.acquire) == 0);
    try fixture.noBridge();
}

test "native runtime UI explicit cancellation timeout and live invocation abort join managed tasks and reuse" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/native.ts", .data = ui_source });
    var controller = try ui_mod.Controller.init(gpa, std.testing.io, false, 80);
    defer controller.deinit();
    var dialogs: DialogUi = .{ .controller = &controller };
    defer dialogs.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.setUiBridge(dialogs.bridge());
    try started.runtime.setContextJson("{\"hasUI\":true}");
    const result = try started.runtime.invokeCommand("ui", "cancel", "{}");
    defer gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "cancel-defaults") != null);
    try std.testing.expectEqual(@as(usize, 3), dialogs.cancelled.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), dialogs.active.load(.acquire));
    started.runtime.timeout_ms = 30;
    const human = try started.runtime.invokeCommand("ui", "human", "{}");
    defer gpa.free(human);
    try std.testing.expect(std.mem.indexOf(u8, human, "green") != null);
    started.runtime.timeout_ms = 1000;
    // This bridge-triggered abort is delivered while the native UI task is
    // sleeping, proving pipe parsing continues independently of frontend I/O.
    var aborted = false;
    dialogs.abort_flag = &aborted;
    // Commands intentionally do not borrow an agent signal. Use a hook/tool
    // registration to verify live invocation cancellation with this same UI.
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/live.ts", .data = "export default pi=>pi.registerTool({name:'ui_live',async execute(id,args,signal,update,ctx){const value=await ctx.ui.select('Signal',['one'],{signal});return {content:value===undefined?'live-cancel':'wrong'}}})" });
    const live_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "live.ts" });
    defer gpa.free(live_path);
    const live = try runtime_mod.Runtime.startNative(gpa, std.testing.io, live_path, fixture.options());
    defer live.runtime.deinit();
    defer gpa.free(live.manifest_json);
    live.runtime.setUiBridge(dialogs.bridge());
    try live.runtime.setContextJson("{\"hasUI\":true}");
    const cancelled = try live.runtime.invokeToolCall("live-ui", "ui_live", "{}", "{}", &aborted);
    defer gpa.free(cancelled);
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "live-cancel") != null);
    try std.testing.expectEqual(@as(usize, 0), dialogs.active.load(.acquire));
    try std.testing.expect(!live.runtime.closed and !started.runtime.closed);
}

test "native runtime UI prompt hooks defer past worker lock and retain both action batches without deadlock" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/native.ts", .data = ui_source });
    var controller = try ui_mod.Controller.init(gpa, std.testing.io, false, 80);
    defer controller.deinit();
    var dialogs: DialogUi = .{ .controller = &controller };
    defer dialogs.deinit();
    var host: host_mod.Host = .{ .gpa = gpa, .io = std.testing.io, .script_backend = .native, .native_runtime_options = fixture.options() };
    defer host.deinit();
    var integration = integration_mod.Bridge.init(&host);
    defer integration.deinit();
    dialogs.prompt_bridge = &integration;
    host.setScriptUiBridge(dialogs.bridge());
    try host.setScriptContextJson("{\"hasUI\":true}");
    try host.loadPath(fixture.source_path);
    var result = (try host.executeCommand("ui", "human")).?;
    defer result.deinit(gpa);
    try std.testing.expect(!result.is_error);
    try std.testing.expectEqualStrings("green", result.message.?);
    var hooks = (try host.executeCommand("ui", "hooks")).?;
    defer hooks.deinit(gpa);
    try std.testing.expectEqualStrings("[\"ui_prompt_start:select\",\"ui_prompt_end:select\"]", hooks.message.?);
    const records = try integration.drainActions();
    defer {
        for (records) |*record| record.deinit(gpa);
        gpa.free(records);
    }
    try std.testing.expectEqual(@as(usize, 2), records.len);
    try std.testing.expectEqualStrings("append_entry", records[0].kind);
    try std.testing.expectEqualStrings("ui_prompt_start", records[0].invocation);
    try std.testing.expectEqualStrings("ui_prompt_end", records[1].invocation);
}
