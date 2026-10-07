//! Real Runtime/Host integration with the standalone native worker and no Node.
const std = @import("std");
const event_wait = @import("test_support/event_wait.zig");
const builtin = @import("builtin");
const runtime_mod = @import("extensions/js_runtime.zig");
const host_mod = @import("extensions/host.zig");
const ui_mod = @import("extensions/ui.zig");
const integration_mod = @import("extensions/integration.zig");
const provider_registry_mod = @import("extensions/provider_registry.zig");
const provider_stream_mod = @import("extensions/provider_stream.zig");
const component_protocol = @import("extensions/component_protocol.zig");
const renderer_protocol = @import("extensions/renderer_protocol.zig");

const editor_protocol = @import("extensions/editor_protocol.zig");

test "native runtime custom editor original 031b modal factory handles idle input change submit resize retirement and close" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.initSource(@import("test_support/upstream_modal_editor_031b.zig").source);
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(io, .{ .sub_path = "extensions/primary.mjs", .data = "export default pi=>{}" });
    const primary = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "primary.mjs" });
    defer gpa.free(primary);
    const Capture = struct {
        mutex: std.Io.Mutex = .init,
        wake: std.Io.Event = .unset,
        closed: std.Io.Event = .unset,
        queue: ?*editor_protocol.ControlQueue = null,
        fence: ?editor_protocol.Fence = null,
        latest: ?editor_protocol.Record = null,
        submitted: ?[]u8 = null,
        retired: bool = false,
        frames: usize = 0,
        fn record(raw: ?*anyopaque, received: editor_protocol.Record, queue: *editor_protocol.ControlQueue) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.mutex.lockUncancelable(std.testing.io);
            defer self.mutex.unlock(std.testing.io);
            self.queue = queue;
            self.fence = received.fence;
            if (received.kind == .submit) {
                if (self.submitted) |old| std.heap.page_allocator.free(old);
                self.submitted = try std.heap.page_allocator.dupe(u8, received.kind.submit);
            }
            if (received.kind == .retire) self.retired = true;
            if (received.kind == .frame) self.frames += 1;
            if (self.latest) |*old| old.deinit();
            self.latest = received;
            self.wake.set(std.testing.io);
        }
        fn close(raw: ?*anyopaque, _: u64) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.mutex.lockUncancelable(std.testing.io);
            defer self.mutex.unlock(std.testing.io);
            self.queue = null;
            self.closed.set(std.testing.io);
        }
        fn control(self: *@This(), kind: @FieldType(editor_protocol.Control, "kind")) !void {
            self.mutex.lockUncancelable(std.testing.io);
            defer self.mutex.unlock(std.testing.io);
            var value: editor_protocol.Control = .{ .gpa = std.heap.page_allocator, .fence = self.fence.?, .kind = kind };
            var transferred = false;
            defer if (!transferred) value.deinit();
            try self.queue.?.send(value);
            transferred = true;
        }
        fn expectFrame(self: *@This(), expected: []const u8, mode: []const u8, width: usize) !void {
            const deadline = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() + 3000;
            while (std.Io.Clock.awake.now(std.testing.io).toMilliseconds() < deadline) {
                self.mutex.lockUncancelable(std.testing.io);
                self.wake.reset();
                const matches = if (self.latest) |value| value.kind == .frame and value.kind.frame.width == width and std.mem.eql(u8, value.kind.frame.text, expected) and std.mem.indexOf(u8, value.kind.frame.frame.lines[value.kind.frame.frame.lines.len - 1], mode) != null else false;
                self.mutex.unlock(std.testing.io);
                if (matches) return;
                self.wake.waitTimeout(std.testing.io, .{ .duration = .{ .raw = .fromMilliseconds(200), .clock = .awake } }) catch |err| if (err != error.Timeout) return err;
            }
            return error.CustomEditorFrameTimeout;
        }
        fn deinit(self: *@This()) void {
            if (self.latest) |*value| value.deinit();
            if (self.submitted) |value| std.heap.page_allocator.free(value);
        }
    };
    var capture: Capture = .{};
    defer capture.deinit();
    const started = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{ primary, fixture.source_path }, fixture.options());
    var released = false;
    defer if (!released) started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setEditorBridge(.{ .context = &capture, .record_fn = Capture.record, .closed_fn = Capture.close });
    try started.runtime.setContextJson("{\"hasUI\":true,\"editorText\":\"draft Ω\",\"width\":55,\"height\":22}");
    const installed = try started.runtime.invokeGroupRequest(2, "{\"kind\":\"hook\",\"name\":\"session_start\",\"payload\":{}}", null);
    defer gpa.free(installed);
    try capture.expectFrame("draft Ω", "INSERT", 55);
    try capture.control(.{ .input = try std.heap.page_allocator.dupe(u8, "🦊") });
    try capture.expectFrame("draft Ω🦊", "INSERT", 55);
    try capture.control(.{ .input = try std.heap.page_allocator.dupe(u8, "\x1b") });
    try capture.expectFrame("draft Ω🦊", "NORMAL", 55);
    try capture.control(.{ .input = try std.heap.page_allocator.dupe(u8, "h") });
    try capture.control(.{ .input = try std.heap.page_allocator.dupe(u8, "i") });
    try capture.control(.{ .input = try std.heap.page_allocator.dupe(u8, "X") });
    try capture.expectFrame("draft ΩX🦊", "INSERT", 55);
    try capture.control(.{ .input = try std.heap.page_allocator.dupe(u8, "\r") });
    try capture.expectFrame("", "INSERT", 55);
    try std.testing.expectEqualStrings("draft ΩX🦊", capture.submitted.?);
    try capture.control(.{ .paste = try std.heap.page_allocator.dupe(u8, "retained Ω") });
    try capture.expectFrame("retained Ω", "INSERT", 55);
    try capture.control(.{ .resize = 35 });
    try capture.expectFrame("retained Ω", "INSERT", 35);
    // Removing the extension must retire its persistent editor although no
    // invocation owns the component anymore; stale controls cannot revive it.
    const removed = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"group_remove_source\",\"ownerId\":2}", null);
    defer gpa.free(removed);
    capture.mutex.lockUncancelable(io);
    const retired = capture.retired;
    capture.mutex.unlock(io);
    try std.testing.expect(retired);
    started.runtime.deinit();
    released = true;
    try std.testing.expect(capture.closed.isSet() and capture.queue == null and capture.frames >= 7);
    try fixture.noBridge();
}

test "native runtime renderer owner publishes idle final redraw frames resize retirement and synchronous reader close without Node" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.initSource("import {Text} from 'pi-tui';export default pi=>pi.registerTool({name:'animated',execute(){return {}},renderCall(args,theme,ctx){ctx.state.label??='early';const component=ctx.lastComponent??new Text('',0,0);component.setText('call:'+ctx.state.label);return component},renderResult(result,opts,theme,ctx){if(!ctx.state.scheduled){ctx.state.scheduled=true;setTimeout(()=>{ctx.state.label='late';ctx.invalidate()},20)}const component=ctx.lastComponent??new Text('',0,0);component.setText('result:'+ctx.state.label+':'+result.content+':'+opts.isPartial);return component}})");
    defer fixture.deinit();
    const Capture = struct {
        mutex: std.Io.Mutex = .init,
        final: std.Io.Event = .unset,
        resized: std.Io.Event = .unset,
        retired: std.Io.Event = .unset,
        closed: std.Io.Event = .unset,
        queue: ?*renderer_protocol.ControlQueue = null,
        fence: ?renderer_protocol.Fence = null,
        registrations: usize = 0,
        frames: usize = 0,
        fn record(context: ?*anyopaque, received: renderer_protocol.Record, queue: *renderer_protocol.ControlQueue) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.mutex.lockUncancelable(std.testing.io);
            defer self.mutex.unlock(std.testing.io);
            var record_value = received;
            self.queue = queue;
            if (received.kind == .register) {
                self.registrations += 1;
                const owned_id = try std.heap.page_allocator.dupe(u8, received.fence.tool_call_id);
                if (self.fence) |fence| std.heap.page_allocator.free(fence.tool_call_id);
                self.fence = received.fence;
                self.fence.?.tool_call_id = owned_id;
            } else if (received.kind == .frame) {
                self.frames += 1;
                if (received.kind.frame.slot == .result and received.kind.frame.frame.lines.len > 0 and std.mem.indexOf(u8, received.kind.frame.frame.lines[0], "result:late:done:false") != null) {
                    self.final.set(std.testing.io);
                    if (received.kind.frame.width == 55) self.resized.set(std.testing.io);
                }
            } else if (received.kind == .retire) self.retired.set(std.testing.io);
            record_value.deinit();
        }
        fn close(context: ?*anyopaque, generation: u64) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.mutex.lockUncancelable(std.testing.io);
            defer self.mutex.unlock(std.testing.io);
            self.queue = null;
            self.closed.set(std.testing.io);
            if (self.fence) |fence| try std.testing.expectEqual(fence.owner_generation, generation);
        }
        fn control(self: *@This(), kind: @FieldType(renderer_protocol.Control, "kind")) !void {
            self.mutex.lockUncancelable(std.testing.io);
            defer self.mutex.unlock(std.testing.io);
            var control_value: renderer_protocol.Control = .{ .gpa = std.heap.page_allocator, .fence = self.fence.?, .kind = kind };
            control_value.fence.tool_call_id = try std.heap.page_allocator.dupe(u8, control_value.fence.tool_call_id);
            var transferred = false;
            defer if (!transferred) control_value.deinit();
            try self.queue.?.send(control_value);
            transferred = true;
        }
        fn deinit(self: *@This()) void {
            if (self.fence) |fence| std.heap.page_allocator.free(fence.tool_call_id);
        }
    };
    var capture: Capture = .{};
    defer capture.deinit();
    const started = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{fixture.source_path}, fixture.options());
    var released = false;
    defer if (!released) started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setRendererBridge(.{ .context = &capture, .record_fn = Capture.record, .closed_fn = Capture.close });
    try started.runtime.setRendererBridge(.{ .context = &capture, .record_fn = Capture.record, .closed_fn = Capture.close });
    try std.testing.expect(!capture.closed.isSet());
    const call = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"render_tool_call\",\"name\":\"animated\",\"payload\":{\"toolCallId\":\"animated-row\",\"args\":{},\"width\":80}}", null);
    defer gpa.free(call);
    const result = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"render_tool_result\",\"name\":\"animated\",\"payload\":{\"toolCallId\":\"animated-row\",\"result\":{\"content\":\"done\"},\"isPartial\":false,\"width\":80}}", null);
    defer gpa.free(result);
    // No further Runtime invocation is sent while these owner callbacks and
    // framed records reach the reader/frontend sink.
    try event_wait.untilSet(io, &capture.final, 2000);
    try capture.control(.{ .resize = 55 });
    try event_wait.untilSet(io, &capture.resized, 2000);
    try capture.control(.retire);
    try event_wait.untilSet(io, &capture.retired, 2000);
    started.runtime.deinit();
    released = true;
    try event_wait.untilSet(io, &capture.closed, 1000);
    try std.testing.expect(capture.queue == null and capture.registrations == 1 and capture.frames >= 4);
    try fixture.noBridge();
}

fn expectNativeTextLine(expected: []const u8, width: usize, actual: []const u8) !void {
    const padded = try std.testing.allocator.alloc(u8, width);
    defer std.testing.allocator.free(padded);
    @memset(padded, ' ');
    @memcpy(padded[0..expected.len], expected);
    try std.testing.expectEqualStrings(padded, actual);
}

test "native runtime renderer sink failure closes borrowed controls original failure and owner reuse has a fresh generation" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.initSource("import {Text} from 'pi-tui';export default pi=>{pi.registerTool({name:'paint',execute(){return {}},renderCall(){return new Text('owned',0,0)}});pi.registerCommand('ping',{handler(){return {message:'live'}}})}");
    defer fixture.deinit();
    const Capture = struct {
        closed: std.Io.Event = .unset,
        calls: std.atomic.Value(usize) = .init(0),
        fn record(context: ?*anyopaque, _: renderer_protocol.Record, _: *renderer_protocol.ControlQueue) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            _ = self.calls.fetchAdd(1, .monotonic);
            // Ownership stays with Runtime on the exact sink failure.
            return error.InjectedRendererSink;
        }
        fn close(context: ?*anyopaque, _: u64) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.closed.set(std.testing.io);
        }
    };
    var capture: Capture = .{};
    const failed = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{fixture.source_path}, fixture.options());
    defer failed.runtime.deinit();
    defer gpa.free(failed.manifest_json);
    try failed.runtime.setRendererBridge(.{ .context = &capture, .record_fn = Capture.record, .closed_fn = Capture.close });
    try std.testing.expectError(error.InjectedRendererSink, failed.runtime.invokeGroupRequest(1, "{\"kind\":\"render_tool_call\",\"name\":\"paint\",\"payload\":{\"toolCallId\":\"failed-row\",\"args\":{},\"width\":80}}", null));
    try event_wait.untilSet(io, &capture.closed, 2000);
    try std.testing.expect(failed.runtime.closed and failed.runtime.child.id == null);
    const reused = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{fixture.source_path}, fixture.options());
    defer reused.runtime.deinit();
    defer gpa.free(reused.manifest_json);
    try std.testing.expect(reused.runtime.owner_generation != failed.runtime.owner_generation);
    const ping = try reused.runtime.invokeGroupRequest(1, "{\"kind\":\"command\",\"name\":\"ping\",\"rawArguments\":\"\"}", null);
    defer gpa.free(ping);
    try std.testing.expect(std.mem.indexOf(u8, ping, "live") != null);
    try std.testing.expectEqual(@as(usize, 1), capture.calls.load(.acquire));
}

test "native runtime asynchronous resolver actions retain source order through cross allocator FIFO failure and retry" {
    const actions_mod = @import("extensions/actions.zig");
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.initSource("export default pi=>pi.registerToolRenderer((name,next)=>{const base=next();return base?{...base,renderCall(args,theme,ctx){ctx.state.wrappers=(ctx.state.wrappers??0)+1;if(ctx.state.wrappers>1)pi.appendEntry('async-first',{});return base.renderCall(args,theme,ctx)}}:base})");
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(io, .{ .sub_path = "extensions/second.ts", .data = "import {Text} from 'pi-tui';export default pi=>pi.registerTool({name:'animated',execute(){return {}},renderCall(args,theme,ctx){ctx.state.calls=(ctx.state.calls??0)+1;if(ctx.state.calls===1)setTimeout(()=>ctx.invalidate(),5);else pi.appendEntry('async-second',{});return new Text('call:'+ctx.state.calls,0,0)}})" });
    const second_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second_path);
    const Capture = struct {
        frame: std.Io.Event = .unset,
        fn record(context: ?*anyopaque, received: renderer_protocol.Record, _: *renderer_protocol.ControlQueue) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            var owned = received;
            defer owned.deinit();
            if (received.kind == .frame and received.kind.frame.frame.lines.len > 0 and std.mem.indexOf(u8, received.kind.frame.frame.lines[0], "call:2") != null) self.frame.set(std.testing.io);
        }
        fn close(_: ?*anyopaque, _: u64) !void {}
    };
    var capture: Capture = .{};
    var host: host_mod.Host = .{ .gpa = gpa, .io = io, .script_backend = .native, .native_runtime_options = fixture.options() };
    defer host.deinit();
    try host.setScriptRendererBridge(.{ .context = &capture, .record_fn = Capture.record, .closed_fn = Capture.close });
    try host.loadPath(fixture.source_path);
    try host.loadPath(second_path);
    const call = (try host.renderToolCall("animated", "async-row", "{}", false, 80)).?;
    defer gpa.free(call);
    try event_wait.untilSet(io, &capture.frame, 2000);
    const limit = std.Io.Clock.awake.now(io).toMilliseconds() + 2000;
    while (host.rendererActionCount() != 2) {
        if (std.Io.Clock.awake.now(io).toMilliseconds() >= limit) return error.AsyncRendererActionsMissing;
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    var failing = std.testing.FailingAllocator.init(gpa, .{ .fail_index = 0 });
    var destination = actions_mod.Queue.init(failing.allocator(), io);
    defer destination.deinit();
    try std.testing.expectError(error.OutOfMemory, host.transferRendererActions(&destination));
    try std.testing.expectEqual(@as(usize, 2), host.rendererActionCount());
    try std.testing.expectEqual(@as(usize, 0), destination.count());
    failing.fail_index = std.math.maxInt(usize);
    try host.transferRendererActions(&destination);
    const records = try destination.drain();
    defer actions_mod.freeRecords(failing.allocator(), records);
    try std.testing.expectEqual(@as(usize, 2), records.len);
    try std.testing.expectEqualStrings("native", records[0].extension_name);
    try std.testing.expectEqualStrings("second", records[1].extension_name);
    try std.testing.expectEqualStrings("renderer_redraw", records[0].invocation);
    try std.testing.expectEqual(@as(u64, 1), records[0].sequence);
    try std.testing.expectEqual(@as(u64, 2), records[1].sequence);
    try std.testing.expectEqual(@as(usize, 0), host.rendererActionCount());
}

test "native runtime owner renders partial tool updates before callback delivery without nested group invocation" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.initSource("import {Text} from 'pi-tui';export default pi=>pi.registerTool({name:'live-render',async execute(id,args,signal,update){update({content:[{type:'text',text:'live:'+args.tag}]});await new Promise(resolve=>setTimeout(resolve,5));return {content:[{type:'text',text:'done:'+args.tag}]}},renderCall(args,theme,ctx){ctx.state.tag=args.tag;return new Text('call:'+args.tag,0,0)},renderResult(result,options,theme,ctx){const component=ctx.lastComponent??new Text('',0,0);component.setText('partial:'+options.isPartial+':'+result.content[0].text+':'+ctx.state.tag);return component}})");
    defer fixture.deinit();
    const Probe = struct {
        partial: std.Io.Event = .unset,
        updates: usize = 0,
        fn record(context: ?*anyopaque, received: renderer_protocol.Record, _: *renderer_protocol.ControlQueue) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            var owned = received;
            defer owned.deinit();
            if (received.kind == .frame and received.kind.frame.slot == .result and received.kind.frame.frame.lines.len > 0 and std.mem.indexOf(u8, received.kind.frame.frame.lines[0], "partial:true:live:seed:seed") != null) self.partial.set(std.testing.io);
        }
        fn close(_: ?*anyopaque, _: u64) !void {}
        fn update(context: ?*anyopaque, raw: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            try std.testing.expect(self.partial.isSet());
            try std.testing.expect(std.mem.indexOf(u8, raw, "live:seed") != null);
            self.updates += 1;
        }
    };
    var probe: Probe = .{};
    const started = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{fixture.source_path}, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const view = try started.runtime.extensionView(1, fixture.source_path);
    defer view.deinit();
    try started.runtime.setRendererBridge(.{ .context = &probe, .record_fn = Probe.record, .closed_fn = Probe.close });
    const call = try view.invokeRenderer("render_tool_call", "live-render", "{\"toolCallId\":\"live-row\",\"args\":{\"tag\":\"seed\"},\"width\":80}");
    defer gpa.free(call);
    const result = try view.invokeToolCallStreaming("live-row", "live-render", "{\"tag\":\"seed\"}", "{}", null, Probe.update, &probe);
    defer gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "done:seed") != null);
    try std.testing.expectEqual(@as(usize, 1), probe.updates);
    const final = try view.invokeRenderer("render_tool_result", "live-render", "{\"toolCallId\":\"live-row\",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"done:seed\"}]},\"isPartial\":false,\"width\":80}");
    defer gpa.free(final);
    try std.testing.expect(std.mem.indexOf(u8, final, "partial:false:done:seed:seed") != null);
    try std.testing.expect(!started.runtime.closed);
}

test "native runtime dirty renderer failures preserve diagnostics and allow independent commands and later redraw" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.initSource("import {Text} from 'pi-tui';export default pi=>{pi.registerTool({name:'row-error',execute(){return {}},renderCall(args,theme,ctx){ctx.state.calls=(ctx.state.calls??0)+1;if(ctx.state.calls===1)setTimeout(()=>ctx.invalidate(),5);if(ctx.state.calls===2)throw Error('row-original-failure');return ctx.lastComponent??new Text('retained',0,0)}});pi.registerCommand('ping',{handler(){return {message:'live'}}})}");
    defer fixture.deinit();
    const Probe = struct {
        failure: std.Io.Event = .unset,
        count: std.atomic.Value(usize) = .init(0),
        fn record(context: ?*anyopaque, received: renderer_protocol.Record, _: *renderer_protocol.ControlQueue) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            var owned = received;
            defer owned.deinit();
            if (received.kind == .failure) {
                try std.testing.expect(std.mem.indexOf(u8, received.kind.failure, "row-original-failure") != null);
                _ = self.count.fetchAdd(1, .monotonic);
                self.failure.set(std.testing.io);
            }
        }
        fn close(_: ?*anyopaque, _: u64) !void {}
    };
    var probe: Probe = .{};
    const started = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{fixture.source_path}, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setRendererBridge(.{ .context = &probe, .record_fn = Probe.record, .closed_fn = Probe.close });
    const call = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"render_tool_call\",\"name\":\"row-error\",\"payload\":{\"toolCallId\":\"error-row\",\"args\":{},\"width\":80}}", null);
    defer gpa.free(call);
    try event_wait.untilSet(io, &probe.failure, 2000);
    const ping = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"command\",\"name\":\"ping\",\"rawArguments\":\"\"}", null);
    defer gpa.free(ping);
    try std.testing.expect(std.mem.indexOf(u8, ping, "live") != null);
    const restored = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"render_tool_call\",\"name\":\"row-error\",\"payload\":{\"toolCallId\":\"error-row\",\"args\":{},\"width\":60}}", null);
    defer gpa.free(restored);
    try std.testing.expect(std.mem.indexOf(u8, restored, "retained") != null);
    try std.testing.expectEqual(@as(usize, 1), probe.count.load(.acquire));
    try std.testing.expect(!started.runtime.closed);
}

test "native runtime admitted custom factory and render rejection closes exactly once before any scene" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource("export default pi=>pi.registerCommand('pre-scene',{async handler(mode,ctx){const original={mode};let disposed=0;try{await ctx.ui.custom(async()=>{await new Promise(resolve=>setTimeout(resolve,1));if(mode==='factory')throw original;return {render(){throw original},dispose(){disposed++}}})}catch(error){return {message:(error===original?'original':'replaced')+':'+disposed}}throw Error('custom unexpectedly resolved')}})");
    defer fixture.deinit();
    const Probe = struct {
        scenes: std.atomic.Value(usize) = .init(0),
        closes: std.atomic.Value(usize) = .init(0),
        fail_close: bool = false,
        fn request(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) ![]u8 {
            return error.UnexpectedStandardDialog;
        }
        fn action(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) !void {}
        fn scene(context: ?*anyopaque, _: component_protocol.Scene, _: *component_protocol.ControlQueue) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            _ = self.scenes.fetchAdd(1, .monotonic);
            return error.UnexpectedFactoryScene;
        }
        fn close(context: ?*anyopaque, _: component_protocol.Fence) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            _ = self.closes.fetchAdd(1, .monotonic);
            if (self.fail_close) return error.InjectedPreSceneClose;
        }
    };
    var probe: Probe = .{};
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setContextJson("{\"hasUI\":true}");
    started.runtime.setUiBridge(.{ .context = &probe, .request_fn = Probe.request, .action_fn = Probe.action, .component_scene_fn = Probe.scene, .component_close_fn = Probe.close });
    for ([_]bool{ false, true, false }) |fail_close| for ([_][]const u8{ "render", "factory" }) |mode| {
        probe.fail_close = fail_close;
        probe.scenes.store(0, .release);
        probe.closes.store(0, .release);
        const result = try started.runtime.invokeCommand("pre-scene", mode, "{}");
        defer gpa.free(result);
        try std.testing.expect(std.mem.indexOf(u8, result, "original") != null);
        try std.testing.expect(std.mem.indexOf(u8, result, if (std.mem.eql(u8, mode, "render")) "original:1" else "original:0") != null);
        try std.testing.expectEqual(@as(usize, 0), probe.scenes.load(.acquire));
        try std.testing.expectEqual(@as(usize, 1), probe.closes.load(.acquire));
        try std.testing.expect(!started.runtime.closed);
    };
}

test "native runtime renderers prepare arguments retain row state final redraw resolver next and explicit retirement without Node" {
    const extension_source =
        \\import {Type,EventStream} from '@earendil-works/pi-ai';import {Type as SameType} from 'typebox';import {Type as AliasType} from '@sinclair/typebox';import {Text,Box} from '@earendil-works/pi-tui';if(Type!==SameType||Type!==AliasType||typeof EventStream!=='function')throw Error('schema/stream aliases');
        \\export default function(pi){let oldNext,oldInvalidate;const original={renderError:true};pi.registerMessageRenderer('default-message',()=>undefined);pi.registerEntryRenderer('hidden-entry',()=>undefined);pi.registerMessageRenderer('message',(message,options,theme)=>{if(message.content==='error')throw original;const box=new Box(options.outputPad,0);box.addChild(new Text('MESSAGE|'+message.content+'|'+options.expanded,0,0));return box});pi.registerEntryRenderer('entry',(entry,options)=>new Text('ENTRY|'+entry.data.message+'|'+options.expanded,0,0));pi.registerMarkdownTransformer((text,ctx)=>'['+ctx.messageType+':'+ctx.isStreaming+':'+ctx.availableWidth+'] '+text);pi.registerTool({name:'paint',parameters:Type.Object({value:Type.String()}),prepareArguments(args){return {value:String(args.alias??args.value)}},async execute(id,args,signal,update){update({content:[{type:'text',text:'live:'+args.value}]});return {content:[{type:'text',text:'done:'+args.value}]}},renderCall(args,theme,ctx){oldInvalidate=ctx.invalidate;ctx.state.value=args.value;ctx.state.calls=(ctx.state.calls??0)+1;const result=ctx.lastComponent??new Text('',0,0);result.setText('CALL|'+args.value+'|'+ctx.toolCallId+'|'+ctx.state.calls+'|'+ctx.cwd);return result},renderResult(result,options,theme,ctx){ctx.state.results=(ctx.state.results??0)+1;const component=ctx.lastComponent??new Text('',0,0);component.setText('RESULT|'+ctx.state.value+'|'+result.content[0].text+'|'+ctx.state.results+'|'+options.isPartial);return component}});pi.registerToolRenderer((name,next)=>{oldNext=next;return next()});pi.registerToolRenderer((name,next)=>name==='unregistered'?{renderCall(){return new Text('RESOLVED',0,0)}}:next());pi.registerCommand('renderer-stale',{handler(){let blocked=false;try{oldNext()}catch(error){blocked=true}oldInvalidate?.();return {blocked}}})}
    ;
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource(extension_source);
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setContextJson("{\"width\":80,\"cwd\":\"owned-renderer-cwd\"}");
    var manifest = try std.json.parseFromSlice(std.json.Value, gpa, started.manifest_json, .{});
    defer manifest.deinit();
    try std.testing.expect(manifest.value.object.get("hasMarkdownTransformer").?.bool and manifest.value.object.get("hasToolRenderers").?.bool);
    const fallback = try started.runtime.invokeRenderer("render_message", "default-message", "{}");
    defer gpa.free(fallback);
    try std.testing.expect(std.mem.indexOf(u8, fallback, "\"found\":false") != null);
    const hidden = try started.runtime.invokeRenderer("render_entry", "hidden-entry", "{}");
    defer gpa.free(hidden);
    try std.testing.expect(std.mem.indexOf(u8, hidden, "\"found\":true") != null and std.mem.indexOf(u8, hidden, "\"lines\":[]") != null);
    const prepared = try started.runtime.invokeRenderer("prepare_tool_arguments", "paint", "{\"args\":{\"alias\":7}}");
    defer gpa.free(prepared);
    try std.testing.expect(std.mem.indexOf(u8, prepared, "\"value\":\"7\"") != null);
    const message = try started.runtime.invokeRenderer("render_message", "message", "{\"message\":{\"content\":\"ready\"},\"expanded\":true,\"outputPad\":2,\"width\":40}");
    defer gpa.free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "MESSAGE|ready|true") != null);
    const entry = try started.runtime.invokeRenderer("render_entry", "entry", "{\"entry\":{\"data\":{\"message\":\"saved\"}},\"expanded\":false,\"width\":40}");
    defer gpa.free(entry);
    try std.testing.expect(std.mem.indexOf(u8, entry, "ENTRY|saved|false") != null);
    const markdown = try started.runtime.invokeRenderer("transform_markdown", "", "{\"markdown\":\"hello\",\"messageType\":\"assistant\",\"isStreaming\":true,\"availableWidth\":67}");
    defer gpa.free(markdown);
    try std.testing.expect(std.mem.indexOf(u8, markdown, "[assistant:true:67] hello") != null);
    const call = try started.runtime.invokeRenderer("render_tool_call", "paint", "{\"toolCallId\":\"row-owned\",\"args\":{\"value\":\"blue\"},\"width\":80}");
    defer gpa.free(call);
    try std.testing.expect(std.mem.indexOf(u8, call, "CALL|blue|row-owned|1|owned-renderer-cwd") != null);
    var call_json = try std.json.parseFromSlice(std.json.Value, gpa, call, .{});
    defer call_json.deinit();
    const generation = call_json.value.object.get("rowGeneration").?.integer;
    for ([_]bool{ true, false, false }, 0..) |partial, index| {
        const payload = try std.fmt.allocPrint(gpa, "{{\"toolCallId\":\"row-owned\",\"result\":{{\"content\":[{{\"type\":\"text\",\"text\":\"done\"}}]}},\"isPartial\":{},\"expanded\":{},\"width\":{d}}}", .{ partial, index == 2, if (index == 2) @as(usize, 64) else 80 });
        defer gpa.free(payload);
        const result = try started.runtime.invokeRenderer("render_tool_result", "paint", payload);
        defer gpa.free(result);
        const expected = try std.fmt.allocPrint(gpa, "RESULT|blue|done|{d}|{}", .{ index + 1, partial });
        defer gpa.free(expected);
        try std.testing.expect(std.mem.indexOf(u8, result, expected) != null);
    }
    const stale = try started.runtime.invokeCommand("renderer-stale", "", "{}");
    defer gpa.free(stale);
    try std.testing.expect(std.mem.indexOf(u8, stale, "\"blocked\":true") != null);
    const wrong = try std.fmt.allocPrint(gpa, "{{\"toolCallId\":\"row-owned\",\"rowGeneration\":{d}}}", .{generation + 1});
    defer gpa.free(wrong);
    const refused = try started.runtime.invokeRenderer("renderer_retire", "paint", wrong);
    defer gpa.free(refused);
    try std.testing.expect(std.mem.indexOf(u8, refused, "\"retired\":false") != null);
    const correct = try std.fmt.allocPrint(gpa, "{{\"toolCallId\":\"row-owned\",\"rowGeneration\":{d}}}", .{generation});
    defer gpa.free(correct);
    const retired = try started.runtime.invokeRenderer("renderer_retire", "paint", correct);
    defer gpa.free(retired);
    try std.testing.expect(std.mem.indexOf(u8, retired, "\"retired\":true") != null);
    const fresh = try started.runtime.invokeRenderer("render_tool_call", "paint", "{\"toolCallId\":\"row-owned\",\"args\":{\"value\":\"fresh\"},\"width\":80}");
    defer gpa.free(fresh);
    try std.testing.expect(std.mem.indexOf(u8, fresh, "CALL|fresh|row-owned|1|") != null);
    const resolved = try started.runtime.invokeRenderer("render_tool_call", "unregistered", "{\"toolCallId\":\"row-resolver\",\"args\":{},\"width\":80}");
    defer gpa.free(resolved);
    try std.testing.expect(std.mem.indexOf(u8, resolved, "RESOLVED") != null);
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, started.runtime.invokeRenderer("render_message", "message", "{\"message\":{\"content\":\"error\"}}"));
    try std.testing.expect(!started.runtime.closed);
    const reused = try started.runtime.invokeRenderer("render_entry", "entry", "{\"entry\":{\"data\":{\"message\":\"reused\"}}}");
    defer gpa.free(reused);
    try std.testing.expect(std.mem.indexOf(u8, reused, "reused") != null);
    try fixture.noBridge();
}

test "native runtime group process preserves global resolver actual component state identity and extension registrations without Node" {
    const first_source =
        \\export default function(pi){globalThis.firstApi=pi;pi.registerFlag('label',{type:'string',default:'first'});pi.registerCommand('same',{handler(_,ctx){return {message:'first:'+pi.getFlag('label')+':'+ctx.sessionManager.getSessionId()}}});pi.registerToolRenderer((name,next)=>{const base=next();if(!base)return base;return {...base,renderCall(args,theme,ctx){const actual=base.renderCall(args,theme,ctx);if(actual!==baseComponent||ctx.state!==baseState)throw Error('global resolver identity');pi.appendEntry('resolver-source',{identity:true});return actual}}})}
    ;
    const second_source =
        \\import {Type} from 'typebox';import {Text} from 'pi-tui';export default function(pi){pi.registerFlag('label',{type:'string',default:'second'});pi.registerCommand('same',{handler(_,ctx){return {message:'second:'+pi.getFlag('label')+':'+ctx.sessionManager.getSessionId()}}});pi.registerTool({name:'group-tool',parameters:Type.Object({}),execute(){return {content:'group-execute'}},renderCall(args,theme,ctx){globalThis.baseState=ctx.state;globalThis.baseComponent=ctx.lastComponent??new Text('shared-identity',0,0);return baseComponent}})}
    ;
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource(first_source);
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/second.ts", .data = second_source });
    const second_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second_path);
    const started = try runtime_mod.Runtime.startNativeGroup(gpa, std.testing.io, &.{ fixture.source_path, second_path }, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    var manifests = try std.json.parseFromSlice(std.json.Value, gpa, started.manifest_json, .{});
    defer manifests.deinit();
    try std.testing.expectEqual(@as(usize, 2), manifests.value.array.items.len);
    try std.testing.expectEqual(@as(i64, 1), manifests.value.array.items[0].object.get("extensionId").?.integer);
    try std.testing.expectEqual(@as(i64, 2), manifests.value.array.items[1].object.get("extensionId").?.integer);
    const first = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"command\",\"name\":\"same\",\"rawArguments\":\"\",\"context\":{\"sessionId\":\"one\"}}", null);
    defer gpa.free(first);
    try std.testing.expect(std.mem.indexOf(u8, first, "first:first:one") != null);
    const second = try started.runtime.invokeGroupRequest(2, "{\"kind\":\"command\",\"name\":\"same\",\"rawArguments\":\"\",\"context\":{\"sessionId\":\"two\"}}", null);
    defer gpa.free(second);
    try std.testing.expect(std.mem.indexOf(u8, second, "second:second:two") != null);
    const rendered = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"render_tool_call\",\"name\":\"group-tool\",\"payload\":{\"toolCallId\":\"group-row\",\"args\":{},\"width\":40}}", null);
    defer gpa.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "shared-identity") != null);
    var result = try std.json.parseFromSlice(std.json.Value, gpa, rendered, .{});
    defer result.deinit();
    const actions = result.value.object.get("actionQueue").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), actions.len);
    try std.testing.expectEqual(@as(i64, 1), actions[0].object.get("sourceExtensionId").?.integer);
    const executed = try started.runtime.invokeGroupRequest(2, "{\"kind\":\"tool\",\"name\":\"group-tool\",\"args\":{}}", null);
    defer gpa.free(executed);
    try std.testing.expect(std.mem.indexOf(u8, executed, "group-execute") != null);
    try std.testing.expect(!started.runtime.closed and started.runtime.child.id != null);
    try fixture.noBridge();
}

test "native runtime Host resolves actual upstream duplicate command aliases and global first tool catalog" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource("export default pi=>{pi.registerTool({name:'read',description:'first',parameters:{type:'object'},execute(){return {content:'first'}}});pi.registerCommand('same:1',{handler(){return {message:'reserved-first'}}});pi.registerCommand('same',{handler(){return {message:'first'}}});pi.registerCommand('catalog',{handler(){return {message:JSON.stringify({commands:pi.getCommands().map(c=>c.name),tools:pi.getAllTools().map(t=>t.name+':'+t.description)})}}})}");
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/second.ts", .data = "export default pi=>{pi.registerTool({name:'read',description:'second',parameters:{type:'object'},execute(){return {content:'second'}}});pi.registerCommand('same',{handler(){return {message:'second'}}})}" });
    const second_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second_path);
    var host: host_mod.Host = .{ .gpa = gpa, .io = std.testing.io, .script_backend = .native, .native_runtime_options = fixture.options() };
    defer host.deinit();
    try host.loadPath(fixture.source_path);
    try host.loadPath(second_path);
    try std.testing.expect(!host.hasCommand("same"));
    for ([_][]const u8{ "same:1", "same:2", "same:3" }, [_][]const u8{ "reserved-first", "first", "second" }) |name, expected| {
        try std.testing.expect(host.hasCommand(name));
        var result = (try host.executeCommand(name, "")).?;
        defer result.deinit(gpa);
        try std.testing.expectEqualStrings(expected, result.message.?);
    }
    var catalog = (try host.executeCommand("catalog", "")).?;
    defer catalog.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, catalog.message.?, "same:2") != null and std.mem.indexOf(u8, catalog.message.?, "same:3") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog.message.?, "read:first") != null and std.mem.indexOf(u8, catalog.message.?, "read:second") == null);
    var tool = (try host.executeTool("read", "{}")).?;
    defer tool.deinit(gpa);
    try std.testing.expectEqualStrings("first", tool.content);
    try fixture.noBridge();
}

test "native runtime group extension views own one child and preserve contexts after owner and sibling release" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource("export default pi=>pi.registerCommand('same',{handler(_,ctx){return {message:'first:'+ctx.sessionManager.getSessionId()}}})");
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/second.ts", .data = "export default pi=>pi.registerCommand('same',{handler(_,ctx){return {message:'second:'+ctx.sessionManager.getSessionId()}}})" });
    const second_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second_path);
    const started = try runtime_mod.Runtime.startNativeGroup(gpa, std.testing.io, &.{ fixture.source_path, second_path }, fixture.options());
    var owner_live = true;
    defer if (owner_live) started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const first = try started.runtime.extensionView(1, fixture.source_path);
    var first_live = true;
    defer if (first_live) first.deinit();
    const second = try started.runtime.extensionView(2, second_path);
    defer second.deinit();
    const pid = started.runtime.child.id;
    started.runtime.deinit();
    owner_live = false;
    try first.setContextJson("{\"sessionId\":\"one\"}");
    try second.setContextJson("{\"sessionId\":\"two\"}");
    const first_result = try first.invokeCommand("same", "", "{}");
    defer gpa.free(first_result);
    const second_result = try second.invokeCommand("same", "", "{}");
    defer gpa.free(second_result);
    try std.testing.expect(std.mem.indexOf(u8, first_result, "first:one") != null and std.mem.indexOf(u8, second_result, "second:two") != null);
    first.deinit();
    first_live = false;
    const reused = try second.invokeCommand("same", "", "{}");
    defer gpa.free(reused);
    try std.testing.expect(std.mem.indexOf(u8, reused, "second:two") != null);
    try std.testing.expect(second.shared_owner.?.child.id == pid and !second.shared_owner.?.closed);
    try fixture.noBridge();
}

test "native runtime Host native discovery shares one process global resolver and rolls back failed extension registrations" {
    const gpa = std.testing.allocator;
    const first_source = "export default function(pi){globalThis.firstFactories=(globalThis.firstFactories??0)+1;pi.registerToolRenderer((name,next)=>{const base=next();if(!base)return base;return {...base,renderCall(args,theme,ctx){const component=base.renderCall(args,theme,ctx);if(component!==baseComponent||ctx.state!==baseState)throw Error('Host global identity');return component}}});pi.registerMessageRenderer('duplicate',()=>({render(){return ['first-message']}}));pi.registerCommand('factory-count',{handler(){return {message:String(firstFactories)}}})}";
    const second_source = "import {Text} from 'pi-tui';export default function(pi){pi.registerTool({name:'second-tool',execute(){return {content:'second-executed'}},renderCall(args,theme,ctx){globalThis.baseState=ctx.state;globalThis.baseComponent=ctx.lastComponent??new Text('HOST-GLOBAL',0,0);return baseComponent}});pi.registerMessageRenderer('duplicate',()=>({render(){return ['second-message']}}));pi.registerCommand('second-command',{handler(){return {message:'second-command'}}})}";
    var fixture = try Fixture.initSource(first_source);
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/second.ts", .data = second_source });
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/failed.ts", .data = "export default pi=>{pi.registerMessageRenderer('failed-renderer',()=>({render(){return ['must-not-leak']}}));pi.registerToolRenderer(()=>({renderCall(){return {render(){return ['must-not-leak']}}}}));throw Error('group-factory-original')}" });
    const second_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second_path);
    const failed_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "failed.ts" });
    defer gpa.free(failed_path);
    var host: host_mod.Host = .{ .gpa = gpa, .io = std.testing.io, .script_backend = .native, .native_runtime_options = fixture.options() };
    defer host.deinit();
    try host.loadPath(fixture.source_path);
    const pid = host.native_group_runtime.?.child.id;
    try host.loadPath(second_path);
    try std.testing.expectEqual(@as(usize, 2), host.extensions.items.len);
    try std.testing.expect(host.extensions.items[0].script_runtime.?.shared_owner == host.extensions.items[1].script_runtime.?.shared_owner);
    try std.testing.expect(host.native_group_runtime.?.child.id == pid);
    var count = (try host.executeCommand("factory-count", "")).?;
    defer count.deinit(gpa);
    try std.testing.expectEqualStrings("1", count.message.?);
    const rendered = (try host.renderToolCall("second-tool", "host-group-row", "{}", false, 40)).?;
    defer gpa.free(rendered);
    try expectNativeTextLine("HOST-GLOBAL", 40, rendered);
    const message = (try host.renderMessage("duplicate", "{}", false, 0, 40)).?;
    defer gpa.free(message);
    try std.testing.expectEqualStrings("first-message", message);
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, host.loadPath(failed_path));
    try std.testing.expectEqual(@as(usize, 2), host.extensions.items.len);
    const still_rendered = (try host.renderToolCall("second-tool", "host-group-row", "{}", false, 40)).?;
    defer gpa.free(still_rendered);
    try expectNativeTextLine("HOST-GLOBAL", 40, still_rendered);
    try std.testing.expect((try host.renderMessage("failed-renderer", "{}", false, 0, 40)) == null);
    var command = (try host.executeCommand("second-command", "")).?;
    defer command.deinit(gpa);
    try std.testing.expectEqualStrings("second-command", command.message.?);
    try fixture.noBridge();
}

test "native runtime Host group actions preserve C owner origin and overwrite returned spoofed provenance" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource("export default pi=>{globalThis.originApi=pi;pi.registerCommand('first',{handler(){return {message:'first'}}})}");
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/second.ts", .data = "export default pi=>{pi.registerCommand('cross-origin',{handler(){originApi.appendEntry('from-first',{ok:true});return {message:'cross'}}});pi.registerCommand('spoof',{handler(){return {message:'spoof',actionQueue:[{type:'append_entry',customType:'spoofed',data:{},sourceExtensionName:'forged',sourceExtensionId:999}]}}})}" });
    const second_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second_path);
    var host: host_mod.Host = .{ .gpa = gpa, .io = std.testing.io, .script_backend = .native, .native_runtime_options = fixture.options() };
    defer host.deinit();
    try host.loadPath(fixture.source_path);
    try host.loadPath(second_path);
    var cross = (try host.executeCommand("cross-origin", "")).?;
    defer cross.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), cross.actions.items.len);
    try std.testing.expectEqualStrings("native", cross.actions.items[0].extension_name);
    var spoof = (try host.executeCommand("spoof", "")).?;
    defer spoof.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), spoof.actions.items.len);
    try std.testing.expectEqualStrings("second", spoof.actions.items[0].extension_name);
    var record = try std.json.parseFromSlice(std.json.Value, gpa, spoof.actions.items[0].json, .{});
    defer record.deinit();
    try std.testing.expectEqual(@as(i64, 2), record.value.object.get("sourceExtensionId").?.integer);
    try fixture.noBridge();
}

test "native runtime renderer next actions enter Bridge FIFO with actual origins ordering and reload retirement" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource("export default pi=>pi.registerToolRenderer((name,next)=>{const base=next();return base?{...base,renderCall(...args){pi.appendEntry('resolver-origin',{});return base.renderCall(...args)}}:base})");
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/second.ts", .data = "import {Text} from 'pi-tui';export default pi=>{pi.registerTool({name:'paint-origin',execute(){return {content:'tool'}},renderCall(args,theme,ctx){pi.appendEntry('base-origin',{});return new Text('origin',0,0)}});pi.registerCommand('after-render',{handler(){pi.appendEntry('command-origin',{});return {message:'after'}}})}" });
    const second_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second_path);
    var host: host_mod.Host = .{ .gpa = gpa, .io = std.testing.io, .script_backend = .native, .native_runtime_options = fixture.options() };
    defer host.deinit();
    var bridge = integration_mod.Bridge.init(&host);
    defer bridge.deinit();
    try host.loadPath(fixture.source_path);
    try host.loadPath(second_path);
    const first = (try host.renderToolCall("paint-origin", "origin-row", "{}", false, 40)).?;
    defer gpa.free(first);
    try std.testing.expectEqual(@as(usize, 2), bridge.queuedActionCount());
    var command = (try host.executeCommand("after-render", "")).?;
    defer command.deinit(gpa);
    try bridge.enqueueActions(&command.actions);
    const records = try bridge.drainActions();
    defer {
        for (records) |*record| record.deinit(gpa);
        if (records.len > 0) gpa.free(records);
    }
    try std.testing.expectEqual(@as(usize, 3), records.len);
    for ([_][]const u8{ "native", "second", "second" }, [_][]const u8{ "render_tool_call", "render_tool_call", "after-render" }, records, 0..) |origin, invocation, record, i| {
        try std.testing.expectEqualStrings(origin, record.extension_name);
        try std.testing.expectEqualStrings(invocation, record.invocation);
        try std.testing.expectEqual(@as(u64, @intCast(i + 1)), record.sequence);
    }
    const again = (try host.renderToolCall("paint-origin", "origin-row", "{}", false, 40)).?;
    defer gpa.free(again);
    try std.testing.expectEqual(@as(usize, 2), bridge.queuedActionCount());
    host.deinit();
    host = .{ .gpa = gpa, .io = std.testing.io, .script_backend = .native, .native_runtime_options = fixture.options() };
    try host.loadPath(fixture.source_path);
    const empty = try bridge.drainActions();
    defer if (empty.len > 0) gpa.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try std.testing.expect((try host.renderToolCall("paint-origin", "origin-row", "{}", false, 40)) == null);
}

test "native runtime group persistent reader and selected live signals progress with zero eager async capacity" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource("export default pi=>pi.registerCommand('ping',{handler(_,ctx){return {message:'first:'+ctx.cwd}}})");
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/second.ts", .data = "export default pi=>pi.registerTool({name:'wait',async execute(id,args,signal,update,ctx){if(ctx.signal!==signal)throw Error('signal identity');if(args.wait){update({content:'entered'});if(!signal.aborted)await new Promise(resolve=>signal.addEventListener('abort',resolve,{once:true}))}return {content:signal.aborted?'cancelled:'+ctx.cwd:'live:'+ctx.cwd}}})" });
    const second_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second_path);
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .nothing });
    defer threaded.deinit();
    const started = try runtime_mod.Runtime.startNativeGroup(gpa, threaded.io(), &.{ fixture.source_path, second_path }, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const first = try started.runtime.extensionView(1, fixture.source_path);
    defer first.deinit();
    const second = try started.runtime.extensionView(2, second_path);
    defer second.deinit();
    try first.setContextJson("{\"cwd\":\"one\"}");
    try second.setContextJson("{\"cwd\":\"two\"}");
    var aborted = false;
    const Cancel = struct {
        fn update(context: ?*anyopaque, raw: []const u8) !void {
            try std.testing.expect(std.mem.indexOf(u8, raw, "entered") != null);
            const flag: *bool = @ptrCast(@alignCast(context.?));
            @atomicStore(bool, flag, true, .release);
        }
    };
    const cancelled = try second.invokeToolCallStreaming("selected-second", "wait", "{\"wait\":true}", "{}", &aborted, Cancel.update, &aborted);
    defer gpa.free(cancelled);
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "cancelled:two") != null);
    const ping = try first.invokeCommand("ping", "", "{}");
    defer gpa.free(ping);
    try std.testing.expect(std.mem.indexOf(u8, ping, "first:one") != null);
    aborted = false;
    const reused = try second.invokeToolCall("selected-reused", "wait", "{}", "{}", &aborted);
    defer gpa.free(reused);
    try std.testing.expect(std.mem.indexOf(u8, reused, "live:two") != null);
    try std.testing.expect(started.runtime.native_read_session != null and !started.runtime.closed);
}

test "native runtime owner pumps idle due timers microtasks errors and wakes requests ahead of future timers" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource("import {writeFileSync} from 'node:fs';export default pi=>{let ready=false;setTimeout(()=>{Promise.resolve().then(()=>{ready=true;writeFileSync(new URL('./idle.marker',import.meta.url),'ready')})},5);setTimeout(()=>{throw Error('idle-original-error')},8);setTimeout(()=>{},60000);pi.registerCommand('idle',{handler(){return {message:ready?'ready':'pending'}}})}");
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNativeGroup(gpa, std.testing.io, &.{fixture.source_path}, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.timeout_ms = 1000;
    const deadline = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() + 1000;
    while (true) {
        const marker = fixture.tmp.dir.readFileAlloc(std.testing.io, "extensions/idle.marker", gpa, .limited(16)) catch |err| switch (err) {
            error.FileNotFound => {
                if (std.Io.Clock.awake.now(std.testing.io).toMilliseconds() >= deadline) return error.IdleTimerDidNotProgress;
                try std.testing.io.sleep(.fromMilliseconds(5), .awake);
                continue;
            },
            else => return err,
        };
        defer gpa.free(marker);
        // File creation and contents publication are separate operations.
        // Keep the same absolute deadline until the completed payload is visible.
        if (std.mem.eql(u8, marker, "ready")) break;
        if (std.Io.Clock.awake.now(std.testing.io).toMilliseconds() >= deadline) return error.IdleTimerDidNotProgress;
        try std.testing.io.sleep(.fromMilliseconds(5), .awake);
    }
    while (true) {
        // Host does no pipe exchange during this interval: factory timers must
        // progress on the worker owner even between independent requests.
        try std.testing.io.sleep(.fromMilliseconds(20), .awake);
        const result = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"command\",\"name\":\"idle\",\"rawArguments\":\"\"}", null);
        defer gpa.free(result);
        if (std.mem.indexOf(u8, result, "ready") != null and started.runtime.last_owner_error != null) break;
        if (std.Io.Clock.awake.now(std.testing.io).toMilliseconds() >= deadline) return error.IdleTimerDidNotProgress;
    }
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.last_owner_error.?, "idle-original-error") != null);
    try std.testing.expect(!started.runtime.closed);
    try fixture.noBridge();
}

test "native runtime group targeted unload fences retained API and renderer generations without destroying sibling owner" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource("export default pi=>pi.registerCommand('late',{handler(){let blocked=false;try{removedApi.appendEntry('late',{})}catch(error){blocked=true}return {message:blocked?'fenced':'wrong'}}})");
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/second.ts", .data = "import {Text} from 'pi-tui';export default pi=>{globalThis.removedApi=pi;pi.registerTool({name:'gone',execute(){return {content:'gone'}},renderCall(args,theme,ctx){globalThis.oldInvalidation=ctx.invalidate;return new Text('gone',0,0)}})}" });
    const second_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second_path);
    const started = try runtime_mod.Runtime.startNativeGroup(gpa, std.testing.io, &.{ fixture.source_path, second_path }, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const rendered = try started.runtime.invokeGroupRequest(2, "{\"kind\":\"render_tool_call\",\"name\":\"gone\",\"payload\":{\"toolCallId\":\"gone-row\",\"args\":{}}}", null);
    defer gpa.free(rendered);
    const removed = try started.runtime.invokeGroupRequest(2, "{\"kind\":\"group_remove_source\",\"ownerId\":2}", null);
    defer gpa.free(removed);
    const late = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"command\",\"name\":\"late\",\"rawArguments\":\"\"}", null);
    defer gpa.free(late);
    try std.testing.expect(std.mem.indexOf(u8, late, "fenced") != null);
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, started.runtime.invokeGroupRequest(2, "{\"kind\":\"command\",\"name\":\"late\",\"rawArguments\":\"\"}", null));
    try std.testing.expect(!started.runtime.closed);
    const missing = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"render_tool_call\",\"name\":\"gone\",\"payload\":{\"toolCallId\":\"gone-row\"}}", null);
    defer gpa.free(missing);
    try std.testing.expect(std.mem.indexOf(u8, missing, "\"found\":false") != null);
}

test "native runtime shared group startup and extension views release every failed host allocation" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource("export default pi=>pi.registerCommand('first',{handler(){return {message:'first'}}})");
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/second.ts", .data = "export default pi=>pi.registerCommand('second',{handler(){return {message:'second'}}})" });
    const second_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second_path);
    const Probe = struct {
        fn record(_: ?*anyopaque, received: renderer_protocol.Record, _: *renderer_protocol.ControlQueue) !void {
            var owned = received;
            owned.deinit();
        }
        fn close(_: ?*anyopaque, _: u64) !void {}
        fn run(allocator: std.mem.Allocator, input: *Fixture, second_source: []const u8) !void {
            const started = try runtime_mod.Runtime.startNativeGroup(allocator, std.testing.io, &.{ input.source_path, second_source }, input.options());
            defer started.runtime.deinit();
            defer allocator.free(started.manifest_json);
            const bridge: runtime_mod.Runtime.RendererBridge = .{ .record_fn = record, .closed_fn = close };
            try started.runtime.setRendererBridge(bridge);
            try started.runtime.setRendererBridge(bridge);
            const first = try started.runtime.extensionView(1, input.source_path);
            defer first.deinit();
            const second = try started.runtime.extensionView(2, second_source);
            defer second.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Probe.run, .{ &fixture, second_path });
    try fixture.noBridge();
}

test "native runtime record budget suspends beyond ordinary deadline and rearms after human close" {
    var budget: runtime_mod.NativeRecordBudget = .{};
    try std.testing.expectEqual(@as(?i64, 30), try budget.remaining(100, 30, false));
    try std.testing.expectEqual(@as(?i64, 1), try budget.remaining(129, 30, false));
    try std.testing.expectEqual(@as(?i64, null), try budget.remaining(129, 30, true));
    // A genuine admitted human wait can exceed the ordinary timeout by any
    // amount, independent of subprocess startup and host scheduling latency.
    try std.testing.expectEqual(@as(?i64, null), try budget.remaining(10_000, 30, true));
    try std.testing.expectEqual(@as(?i64, 30), try budget.remaining(10_001, 30, false));
    try std.testing.expectEqual(@as(?i64, 1), try budget.remaining(10_030, 30, false));
    try std.testing.expectError(error.JavaScriptExtensionTimeout, budget.remaining(10_031, 30, false));
    try std.testing.expectEqual(@as(?i64, null), try budget.remaining(20_000, 0, false));
    try std.testing.expectEqual(@as(?i64, 30), try budget.remaining(20_001, 30, false));
    var ordinary: runtime_mod.NativeRecordBudget = .{};
    _ = try ordinary.remaining(100, 30, false);
    try std.testing.expectError(error.JavaScriptExtensionTimeout, ordinary.remaining(130, 30, false));
}

test "native runtime Host production adapters prepare schema input and render native message entry markdown and tool rows" {
    const extension_source =
        \\import {Type} from '@earendil-works/pi-ai';import {Text,Box} from '@earendil-works/pi-tui';export default function(pi){pi.registerMessageRenderer('status-update',(message,{expanded,outputPad},theme)=>{const box=new Box(outputPad,0,line=>theme.bg('customMessageBg',line));box.addChild(new Text('MESSAGE|'+message.content+'|'+expanded+'|'+outputPad,0,0));return box});pi.registerEntryRenderer('status-card',(entry,{expanded})=>new Text('ENTRY|'+entry.data.message+'|'+expanded,0,0));pi.registerMarkdownTransformer((markdown,options)=>'['+options.messageType+':'+options.isStreaming+':'+options.availableWidth+'] '+markdown);pi.registerToolRenderer((name,next)=>name==='unregistered'?{renderCall(){return new Text('OWNER-LOCAL',0,0)}}:next());pi.registerTool({name:'paint',renderShell:'self',parameters:Type.Object({value:Type.String()}),prepareArguments(args){return {value:String(args.alias??args.value)}},async execute(id,args){return {content:[{type:'text',text:'done:'+args.value}],details:{}}},renderCall(args,theme,context){context.state.value=args.value;return new Text('CALL|'+args.value+'|'+context.toolCallId+'|'+context.executionStarted,0,0)},renderResult(result,{expanded,isPartial},theme,context){return new Text('RESULT|'+context.state.value+'|'+result.content[0].text+'|'+expanded+'|'+isPartial,0,0)}})}
    ;
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource(extension_source);
    defer fixture.deinit();
    var host: host_mod.Host = .{ .gpa = gpa, .io = std.testing.io, .script_backend = .native, .native_runtime_options = fixture.options() };
    defer host.deinit();
    try host.loadPath(fixture.source_path);
    try std.testing.expect(host.extensions.items[0].has_markdown_transformer);
    try std.testing.expect(host.extensions.items[0].tools[0].render_shell_self);
    const prepared = (try host.prepareToolArguments("paint", "{\"alias\":7}")).?;
    defer gpa.free(prepared);
    try std.testing.expectEqualStrings("{\"value\":\"7\"}", prepared);
    var executed = (try host.executeTool("paint", prepared)).?;
    defer executed.deinit(gpa);
    try std.testing.expectEqualStrings("done:7", executed.content);
    const message = (try host.renderMessage("status-update", "{\"role\":\"custom\",\"customType\":\"status-update\",\"content\":\"ready\"}", true, 2, 72)).?;
    defer gpa.free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "MESSAGE|ready|true|2") != null);
    const entry = (try host.renderEntry("status-card", "{\"type\":\"custom\",\"customType\":\"status-card\",\"data\":{\"message\":\"saved\"}}", false, 72)).?;
    defer gpa.free(entry);
    try expectNativeTextLine("ENTRY|saved|false", 72, entry);
    const markdown = try host.transformMarkdown("hello", "assistant", true, 67);
    defer gpa.free(markdown);
    try std.testing.expectEqualStrings("[assistant:true:67] hello", markdown);
    const call = (try host.renderToolCall("paint", "tool-17", "{\"value\":\"blue\"}", false, 72)).?;
    defer gpa.free(call);
    try expectNativeTextLine("CALL|blue|tool-17|true", 72, call);
    const result = (try host.renderToolResult("paint", "tool-17", "done:blue", false, true, false, 72)).?;
    defer gpa.free(result);
    try expectNativeTextLine("RESULT|blue|done:blue|true|false", 72, result);
    const redrawn = (try host.renderToolResult("paint", "tool-17", "done:blue", false, false, false, 40)).?;
    defer gpa.free(redrawn);
    try expectNativeTextLine("RESULT|blue|done:blue|false|false", 40, redrawn);
    try host.retireToolRenderer("paint", "tool-17", null);
    const owner_local = (try host.renderToolCall("unregistered", "tool-local", "{}", false, 40)).?;
    defer gpa.free(owner_local);
    try expectNativeTextLine("OWNER-LOCAL", 40, owner_local);
    try std.testing.expect((try host.renderMessage("unowned", "{}", false, 0, 72)) == null);
    try fixture.noBridge();
}

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

const stream_source =
    \\import {createAssistantMessageEventStream} from '@earendil-works/pi-ai';
    \\const usage={input:1,output:2,cacheRead:0,cacheWrite:0,totalTokens:3,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};
    \\const message=(content=[],stopReason='pending')=>({role:'assistant',content,api:'openai-completions',provider:'native-stream',model:'stream-model',usage,stopReason,timestamp:185});
    \\export default function(pi){let nextCalls=0,returns=0,cancelCalls=0;
    \\const events=()=>{const partial=message();return [{type:'start',partial},{type:'text_start',contentIndex:0,partial},{type:'text_delta',contentIndex:0,delta:'N',partial},{type:'text_delta',contentIndex:0,delta:'\uD83D',partial},{type:'text_delta',contentIndex:0,delta:'\uDE80',partial},{type:'text_end',contentIndex:0,content:'N🚀',partial},{type:'done',reason:'stop',message:message([{type:'text',text:'N🚀'}],'stop')}]};
    \\function stream(model,context,options){if(this.name!=='Native Stream'||!(options.signal instanceof AbortSignal)||!Object.isFrozen(model)||!Object.isFrozen(context)||!Object.isFrozen(options))throw Error('native stream inputs');let index=0;const values=events();
    \\if(context.mode==='queued'){const result=createAssistantMessageEventStream();values.forEach(value=>result.push(value));return result}
    \\if(context.mode==='getter-error')return {[Symbol.asyncIterator](){return this},get next(){throw Error('original-next-getter')},return(){returns++;throw Error('cleanup-must-not-replace-original')}};
    \\return {[Symbol.asyncIterator](){return this},next(){nextCalls++;if(context.mode==='self-remove')pi.unregisterProvider('native-stream');if(index===1&&(context.mode==='wait'||context.mode==='hostile'))return new Promise(()=>{});return Promise.resolve(index<values.length?{done:false,value:values[index++]}:{done:true})},return(){returns++;if(context.mode==='hostile')return new Promise(()=>{});if(context.mode==='cleanup-error')throw Error('cleanup-must-not-replace-original');return Promise.resolve({done:true})}}}
    \\function register(){pi.registerProvider('native-stream',{name:'Native Stream',api:'openai-completions',baseUrl:'https://unused.invalid',apiKey:'local',models:[{id:'stream-model',name:'Stream Model',reasoning:false,input:['text'],cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:4096,maxTokens:512}],streamSimple:stream,fetchDeferred:stream,cancelDeferred(model,handle,options){if(!(options.signal instanceof AbortSignal))throw Error('cancel signal');cancelCalls++}})}
    \\register();pi.registerCommand('stream-status',{handler(){return {nextCalls,returns,cancelCalls}}});pi.registerCommand('stream-replace',{handler(){register()}});pi.registerCommand('stream-remove',{handler(){pi.unregisterProvider('native-stream')}});
    \\}
;

fn streamConfig(manifest: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, manifest, .{});
    defer parsed.deinit();
    return std.json.Stringify.valueAlloc(std.testing.allocator, parsed.value.object.get("providers").?.array.items[0].object.get("config").?, .{});
}

fn streamId(config: []const u8, path: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, config, .{});
    defer parsed.deinit();
    return std.testing.allocator.dupe(u8, parsed.value.object.get(path).?.object.get("__pi_callback_id").?.string);
}

const StreamCapture = struct {
    count: u64 = 0,
    reject: bool = false,
    abort: ?*bool = null,
    entered: ?*bool = null,
    carry: bool = false,
    rocket: bool = false,
    inject_ack: ?*runtime_mod.Runtime = null,

    fn event(raw: ?*anyopaque, sequence: u64, event_json: []const u8) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        try std.testing.expectEqual(self.count + 1, sequence);
        self.count = sequence;
        if (self.entered) |flag| @atomicStore(bool, flag, true, .release);
        if (self.abort) |flag| @atomicStore(bool, flag, true, .release);
        if (self.reject) return error.NativeDeliberateConsumerRejection;
        if (self.inject_ack) |runtime| {
            runtime.write_mutex.lockUncancelable(runtime.io);
            defer runtime.write_mutex.unlock(runtime.io);
            var buffer: [1024]u8 = undefined;
            var writer = runtime.child.stdin.?.writerStreaming(runtime.io, &buffer);
            const identity = @atomicLoad(u64, &runtime.active_provider_invocation_id, .acquire);
            // Neither a stale invocation nor a stale/future sequence may reject
            // the current acknowledgement capability.
            try writer.interface.print("{{\"kind\":\"provider_stream_ack\",\"invocationId\":\"stale\",\"sequence\":{d},\"ok\":false}}\n{{\"kind\":\"provider_stream_ack\",\"invocationId\":\"{d}\",\"sequence\":{d},\"ok\":false}}\n", .{ sequence, identity, if (sequence == 1) @as(u64, 99) else sequence - 1 });
            try writer.interface.flush();
        }
        self.carry = self.carry or std.mem.indexOf(u8, event_json, "\"delta\":\"\"") != null;
        self.rocket = self.rocket or std.mem.indexOf(u8, event_json, "🚀") != null;
    }
};

fn invokeStream(runtime: *runtime_mod.Runtime, id: []const u8, mode: []const u8, aborted: ?*bool, capture: *StreamCapture) ![]u8 {
    const context = try std.fmt.allocPrint(std.testing.allocator, "{{\"messages\":[],\"mode\":{f}}}", .{std.json.fmt(mode, .{})});
    defer std.testing.allocator.free(context);
    return runtime.invokeProviderStreamSimple("native-stream", id, 1, "{\"id\":\"stream-model\",\"provider\":\"native-stream\",\"api\":\"openai-completions\"}", context, "{}", aborted, StreamCapture.event, capture);
}

test "native runtime provider streams ACK every event before next and preserve negative ACK through iterator cleanup" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource(stream_source);
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const config = try streamConfig(started.manifest_json);
    defer gpa.free(config);
    const id = try streamId(config, "streamSimple");
    defer gpa.free(id);
    var rejected: StreamCapture = .{ .reject = true };
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, invokeStream(started.runtime, id, "cleanup-error", null, &rejected));
    try std.testing.expectEqual(@as(u64, 1), rejected.count);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "NativeDeliberateConsumerRejection") != null);
    const status = try started.runtime.invokeCommand("stream-status", "", "{}");
    defer gpa.free(status);
    try std.testing.expect(std.mem.indexOf(u8, status, "\"nextCalls\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, status, "\"returns\":1") != null);
    for ([_][]const u8{ "plain", "queued" }) |mode| {
        var capture: StreamCapture = .{ .inject_ack = started.runtime };
        const summary = try invokeStream(started.runtime, id, mode, null, &capture);
        defer gpa.free(summary);
        try std.testing.expectEqual(@as(u64, 7), capture.count);
        try std.testing.expect(capture.carry and capture.rocket);
        try std.testing.expect(std.mem.indexOf(u8, summary, "\"terminal\":\"done\"") != null);
    }
    const fetch_id = try streamId(config, "fetchDeferred");
    defer gpa.free(fetch_id);
    var fetch: StreamCapture = .{};
    const fetched = try started.runtime.invokeProviderFetchDeferred("native-stream", fetch_id, 1, "{}", "{\"mode\":\"queued\"}", "{}", null, StreamCapture.event, &fetch);
    defer gpa.free(fetched);
    try std.testing.expectEqual(@as(u64, 7), fetch.count);
    const cancel_id = try streamId(config, "cancelDeferred");
    defer gpa.free(cancel_id);
    const cancelled = try started.runtime.invokeProviderCancelDeferred("native-stream", cancel_id, 1, "{}", "{}", "{}", null);
    defer gpa.free(cancelled);
    try std.testing.expect(!started.runtime.closed);
    var getter: StreamCapture = .{};
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, invokeStream(started.runtime, id, "getter-error", null, &getter));
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "original-next-getter") != null);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "cleanup-must-not-replace-original") == null);
    try fixture.noBridge();
}

test "native runtime provider generation retirement and unregister drain live iterator with bounded reuse" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.initSource(stream_source);
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.provider_stream_timeout_ms = 1500;
    const config = try streamConfig(started.manifest_json);
    defer gpa.free(config);
    const id = try streamId(config, "streamSimple");
    defer gpa.free(id);
    const Invocation = struct {
        runtime: *runtime_mod.Runtime,
        id: []const u8,
        entered: bool = false,
        failure: ?anyerror = null,
        count: u64 = 0,

        fn run(self: *@This()) void {
            var capture: StreamCapture = .{ .entered = &self.entered };
            const result = invokeStream(self.runtime, self.id, "wait", null, &capture) catch |err| {
                self.failure = err;
                self.count = capture.count;
                return;
            };
            std.testing.allocator.free(result);
        }
    };
    var invocation: Invocation = .{ .runtime = started.runtime, .id = id };
    var group: std.Io.Group = .init;
    group.async(io, Invocation.run, .{&invocation});
    defer {
        group.cancel(io);
        group.await(io) catch {};
    }
    var elapsed: usize = 0;
    while (!@atomicLoad(bool, &invocation.entered, .acquire) and elapsed < 1000) : (elapsed += 5) try io.sleep(.fromMilliseconds(5), .awake);
    try std.testing.expect(@atomicLoad(bool, &invocation.entered, .acquire));
    // Another provider's same generation must not retire this invocation.
    try std.testing.expect(started.runtime.retireProviderGeneration("different-provider", 1, 20));
    try std.testing.expect(@atomicLoad(bool, &started.runtime.active_provider_stream, .acquire));
    try std.testing.expect(started.runtime.retireProviderGeneration("native-stream", 1, 1000));
    try group.await(io);
    try std.testing.expectEqual(error.JavaScriptExtensionExecutionFailed, invocation.failure.?);
    try std.testing.expectEqual(@as(u64, 1), invocation.count);
    try std.testing.expect(!started.runtime.closed);
    var unregister: StreamCapture = .{};
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, invokeStream(started.runtime, id, "self-remove", null, &unregister));
    try std.testing.expectEqual(@as(u64, 0), unregister.count);
    try started.runtime.commitProviderCallbacks("native-stream", &.{});
    var stale: StreamCapture = .{};
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, invokeStream(started.runtime, id, "plain", null, &stale));
    const reused = try started.runtime.invokeCommand("stream-status", "", "{}");
    defer gpa.free(reused);
    try std.testing.expect(std.mem.indexOf(u8, reused, "\"returns\":2") != null);
    try std.testing.expect(!started.runtime.closed);
}

test "native runtime provider live abort retires iterator and hostile return closes only owned child" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource(stream_source);
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const config = try streamConfig(started.manifest_json);
    defer gpa.free(config);
    const id = try streamId(config, "streamSimple");
    defer gpa.free(id);
    var aborted = false;
    var capture: StreamCapture = .{ .abort = &aborted };
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, invokeStream(started.runtime, id, "wait", &aborted, &capture));
    try std.testing.expect(!started.runtime.closed);
    const status = try started.runtime.invokeCommand("stream-status", "", "{}");
    defer gpa.free(status);
    try std.testing.expect(std.mem.indexOf(u8, status, "\"returns\":1") != null);
    const healthy = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer healthy.runtime.deinit();
    defer gpa.free(healthy.manifest_json);
    aborted = false;
    capture = .{ .abort = &aborted };
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, invokeStream(started.runtime, id, "hostile", &aborted, &capture));
    try std.testing.expect(started.runtime.closed and started.runtime.child.id == null);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "PI_PROVIDER_STREAM_RETIRE_TIMEOUT") != null);
    const reused = try healthy.runtime.invokeCommand("stream-status", "", "{}");
    defer gpa.free(reused);
    try std.testing.expect(!healthy.runtime.closed);
}

test "native runtime provider production adapter streams through registry and fences callback replacement" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource(stream_source);
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const config = try streamConfig(started.manifest_json);
    defer gpa.free(config);
    const old_id = try streamId(config, "streamSimple");
    defer gpa.free(old_id);
    var registry = provider_registry_mod.Registry.init(gpa, std.testing.io, &fixture.environment, null, &.{}, &.{});
    defer registry.deinit();
    try registry.registerJsonWithRuntime("native-stream", config, started.runtime);
    var adapter = provider_stream_mod.Runtime.init(gpa, &registry);
    const messages = [_]@import("ai/root.zig").ChatMessage{.{ .role = "user", .content = "hello" }};
    var response = try adapter.complete(gpa, .{ .provider_id = "native-stream", .model_id = "stream-model", .api = "openai-completions", .api_key = "local", .base_url = "https://unused.invalid" }, &messages, "[]", null, null, null);
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("N🚀", response.content);
    try std.testing.expectEqualStrings("stop", response.stop_reason);
    try std.testing.expectEqual(@as(u64, 3), response.usage.total_tokens);
    const replacement = try started.runtime.invokeCommand("stream-replace", "", "{}");
    defer gpa.free(replacement);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, replacement, .{});
    defer parsed.deinit();
    const next_config = try std.json.Stringify.valueAlloc(gpa, parsed.value.object.get("actionQueue").?.array.items[0].object.get("config").?, .{});
    defer gpa.free(next_config);
    try registry.registerJsonWithRuntime("native-stream", next_config, started.runtime);
    var stale: StreamCapture = .{};
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, invokeStream(started.runtime, old_id, "plain", null, &stale));
    try std.testing.expectEqual(@as(u64, 0), stale.count);
    var reused = try adapter.complete(gpa, .{ .provider_id = "native-stream", .model_id = "stream-model", .api = "openai-completions", .api_key = "local", .base_url = "https://unused.invalid" }, &messages, "[]", null, null, null);
    defer reused.deinit(gpa);
    try std.testing.expectEqualStrings("N🚀", reused.content);
    try std.testing.expect(!started.runtime.closed);
}

test "native runtime URL globals module aliases filesystem and createRequire consume branded URL in TypeScript without Node" {
    const extension_source =
        \\import fs from 'node:fs';import {createRequire} from 'node:module';import {URL as NativeURL,URLSearchParams as NativeParams} from 'node:url';import {URL as AliasURL,URLSearchParams as AliasParams} from 'url';
        \\const sourceUrl: URL=new URL(import.meta.url);const marker: string='native-url-process-marker';
        \\if(NativeURL!==globalThis.URL||AliasURL!==NativeURL||NativeParams!==globalThis.URLSearchParams||AliasParams!==NativeParams)throw Error('URL alias identity');
        \\if(!fs.readFileSync(sourceUrl,'utf8').includes(marker))throw Error('branded URL filesystem');
        \\const require=createRequire(sourceUrl);if(require('node:fs').readFileSync!==fs.readFileSync||require('./native-url.json').marker!==marker)throw Error('branded URL createRequire');
        \\const url=new URL('https://example.test/path?a=1');const params=url.searchParams;params.append('a','2');if(url.search!=='?a=1&a=2'||[...params].length!==2)throw Error('linked URL params');
        \\export default function(pi){pi.on('url_probe',()=>({marker,url:url.href,source:sourceUrl.protocol}))}
    ;
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource(extension_source);
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/native-url.json", .data = "{\"marker\":\"native-url-process-marker\"}" });
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const result = try started.runtime.invokeHook("url_probe", "{}", "{}");
    defer gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "native-url-process-marker") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "https://example.test/path?a=1&a=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "file:") != null);
    try fixture.noBridge();
}

test "native runtime custom C factory frames resize input close ACK original errors and reuse without Node" {
    const extension_source =
        \\import {Text,matchesKey,Key} from '@earendil-works/pi-tui';
        \\export default function(pi){pi.registerCommand('component',{async handler(mode,ctx){let disposed=0,text='first',lastWidth=0;const original={original:true};try{const result=await ctx.ui.custom(async(tui,theme,keybindings,done)=>{await Promise.resolve();if(typeof theme.bold!=='function'||!keybindings.matches('\r','tui.select.confirm')||!matchesKey('\x03',Key.ctrl('c')))throw Error('native factory arguments');return {render(width){lastWidth=width;if(mode==='render-error')throw original;return new Text(text+':'+width,0,0).render(width)},handleInput(data){if(mode==='input-error')throw original;if(data==='q')done({text,width:lastWidth});else{text=data;tui.requestRender()}},invalidate(){},dispose(){disposed++}}});return {result,disposed}}catch(error){return {caught:error===original,disposed}}}})}
    ;
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource(extension_source);
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setContextJson("{\"hasUI\":true,\"width\":40,\"height\":15}");
    const Ui = struct {
        frames: usize = 0,
        closes: usize = 0,
        resized: bool = false,
        updated: bool = false,
        mode: enum { normal, input_error, render_error } = .normal,
        fn request(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) ![]u8 {
            return error.UnexpectedStandardDialog;
        }
        fn action(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) !void {}
        fn scene(context: ?*anyopaque, received: component_protocol.Scene, queue: *component_protocol.ControlQueue) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            var owned = received;
            var consumed = false;
            defer if (consumed) owned.deinit();
            self.frames += 1;
            self.resized = self.resized or received.width == 23;
            for (received.frame.lines) |line| self.updated = self.updated or std.mem.indexOf(u8, line, "updated:23") != null;
            const input: []const u8 = if (self.mode == .input_error) "error" else if (!self.resized) "" else if (!self.updated) "updated" else "q";
            if (input.len == 0) try queue.send(.{ .gpa = std.heap.page_allocator, .fence = received.fence, .kind = .{ .resize = .{ .width = 23, .height = 9 } } }) else {
                var control: component_protocol.Control = .{ .gpa = std.heap.page_allocator, .fence = received.fence, .kind = .{ .input = try std.heap.page_allocator.dupe(u8, input) } };
                var transferred = false;
                defer if (!transferred) control.deinit();
                try queue.send(control);
                transferred = true;
            }
            consumed = true;
        }
        fn close(context: ?*anyopaque, _: component_protocol.Fence) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.closes += 1;
        }
    };
    var ui: Ui = .{};
    started.runtime.setUiBridge(.{ .context = &ui, .request_fn = Ui.request, .action_fn = Ui.action, .component_scene_fn = Ui.scene, .component_close_fn = Ui.close });
    const result = try started.runtime.invokeCommand("component", "normal", "{}");
    defer gpa.free(result);
    try std.testing.expect(ui.frames >= 3 and ui.resized and ui.updated);
    try std.testing.expectEqual(@as(usize, 1), ui.closes);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"text\":\"updated\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"width\":23") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"disposed\":1") != null);
    ui = .{ .mode = .input_error };
    const input_error = try started.runtime.invokeCommand("component", "input-error", "{}");
    defer gpa.free(input_error);
    try std.testing.expect(std.mem.indexOf(u8, input_error, "\"caught\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, input_error, "\"disposed\":1") != null);
    try std.testing.expectEqual(@as(usize, 1), ui.closes);
    ui = .{ .mode = .render_error };
    const render_error = try started.runtime.invokeCommand("component", "render-error", "{}");
    defer gpa.free(render_error);
    try std.testing.expect(std.mem.indexOf(u8, render_error, "\"caught\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, render_error, "\"disposed\":1") != null);
    try std.testing.expectEqual(@as(usize, 0), ui.frames);
    try std.testing.expect(!started.runtime.closed);
    try fixture.noBridge();
}

test "native runtime model publication retains update receiver async catalog rejected stale abort and old closures" {
    const extension_source =
        \\export default function(pi){let saved,updates=0;const config={models:[{id:'initial'}],async getModels(){return this.models},async refreshModels(ctx){if(!Object.isFrozen(ctx)||!Object.isFrozen(ctx.credential)||!Object.isFrozen(ctx.stored))throw Error('mutable refresh');saved=ctx.publish;const original={publication:true};if(ctx.stored.mode==='error'){try{await ctx.publish({get persist(){throw original}})}catch(error){if(error!==original)throw Error('publication error identity');return [{id:'caught'}]}throw Error('missing rejection')}const publication={receiver:'publication',persist:{etag:'owned'},get update(){if(ctx.stored.mode==='unregister')pi.unregisterProvider('native-models');return function(){if(this!==publication)throw Error('update receiver');updates++;config.models=[{id:'updated'}]}}};const accepted=await ctx.publish(publication);if(!accepted)return [{id:'rejected'}]}};pi.registerProvider('native-models',config);pi.registerCommand('models-status',{async handler(mode){if(mode==='stale'){let blocked=false;try{await saved({update(){updates+=100}})}catch(error){blocked=true}return {blocked,updates}}return {updates}}})}
    ;
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource(extension_source);
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const config = try streamConfig(started.manifest_json);
    defer gpa.free(config);
    const callback = try streamId(config, "refreshModels");
    defer gpa.free(callback);
    const Ui = struct {
        flag: *bool,
        accept: bool = true,
        abort: bool = false,
        cancelled: bool = false,
        published: usize = 0,
        catalogs: usize = 0,
        fn request(context: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args: []const u8) ![]u8 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, args, .{});
            defer parsed.deinit();
            if (std.mem.eql(u8, method, "provider_models_publish")) {
                self.published += 1;
                try std.testing.expect(parsed.value.object.get("hasPersist").?.bool);
                if (self.abort) {
                    @atomicStore(bool, self.flag, true, .release);
                    std.testing.io.sleep(.fromMilliseconds(5000), .awake) catch |err| {
                        self.cancelled = true;
                        return err;
                    };
                    return error.PublicationAbortDidNotCancel;
                }
            } else {
                try std.testing.expectEqualStrings("provider_models_catalog", method);
                self.catalogs += 1;
                try std.testing.expectEqualStrings("updated", parsed.value.object.get("models").?.array.items[0].object.get("id").?.string);
            }
            return allocator.dupe(u8, if (self.accept) "true" else "false");
        }
        fn action(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) !void {}
        fn bridge(self: *@This()) runtime_mod.UiBridge {
            return .{ .context = self, .request_fn = request, .action_fn = action };
        }
    };
    var aborted = false;
    var ui: Ui = .{ .flag = &aborted };
    const normal = "{\"generation\":1,\"allowNetwork\":false,\"credential\":{\"owned\":true},\"stored\":{}}";
    const first = try started.runtime.invokeProviderRefreshModels(callback, "native-models", normal, &aborted, ui.bridge());
    defer gpa.free(first);
    try std.testing.expect(std.mem.indexOf(u8, first, "updated") != null);
    try std.testing.expectEqual(@as(usize, 1), ui.published);
    try std.testing.expectEqual(@as(usize, 1), ui.catalogs);
    const stale = try started.runtime.invokeCommand("models-status", "stale", "{}");
    defer gpa.free(stale);
    try std.testing.expect(std.mem.indexOf(u8, stale, "\"blocked\":true") != null and std.mem.indexOf(u8, stale, "\"updates\":1") != null);
    ui.accept = false;
    const rejected = try started.runtime.invokeProviderRefreshModels(callback, "native-models", normal, &aborted, ui.bridge());
    defer gpa.free(rejected);
    try std.testing.expect(std.mem.indexOf(u8, rejected, "rejected") != null);
    try std.testing.expectEqual(@as(usize, 1), ui.catalogs);
    const caught = try started.runtime.invokeProviderRefreshModels(callback, "native-models", "{\"generation\":2,\"allowNetwork\":false,\"credential\":{},\"stored\":{\"mode\":\"error\"}}", &aborted, ui.bridge());
    defer gpa.free(caught);
    try std.testing.expect(std.mem.indexOf(u8, caught, "caught") != null);
    ui.accept = true;
    ui.abort = true;
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, started.runtime.invokeProviderRefreshModels(callback, "native-models", normal, &aborted, ui.bridge()));
    try std.testing.expect(ui.cancelled and !started.runtime.closed);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "Operation aborted") != null);
    aborted = false;
    ui.abort = false;
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, started.runtime.invokeProviderRefreshModels(callback, "native-models", "{\"generation\":3,\"allowNetwork\":false,\"credential\":{},\"stored\":{\"mode\":\"unregister\"}}", &aborted, ui.bridge()));
    const status = try started.runtime.invokeCommand("models-status", "", "{}");
    defer gpa.free(status);
    try std.testing.expect(std.mem.indexOf(u8, status, "\"updates\":1") != null);
    try std.testing.expect(!started.runtime.closed);
    try fixture.noBridge();
}

test "native runtime OAuth provider receiver original errors actions live abort managed prompt and reuse" {
    const extension_source =
        \\export default function(pi){let calls=0,oldCallbacks;pi.registerProvider('native-oauth',{oauth:{owner:'receiver',async login(callbacks){if(this.owner!=='receiver'||!(callbacks.signal instanceof AbortSignal))throw Error('OAuth receiver/signal');calls++;if(calls===1){oldCallbacks=callbacks;const original={conversion:true};let caught=false;try{await callbacks.onPrompt({get message(){throw original}})}catch(error){caught=error===original}if(!caught)throw Error('OAuth conversion identity');callbacks.onAuth({url:'https://login.invalid',instructions:'open'});callbacks.onDeviceCode({verification_uri:'https://device.invalid',user_code:'owned',interval_seconds:7});callbacks.onProgress('progress');return {access:await callbacks.onPrompt({message:'Tenant?',secret:true}),refresh:await callbacks.onManualCodeInput(),team:await callbacks.onSelect({title:'Team?',options:[{id:'a',label:'A'},{value:'b',label:'B'}]}),caught}}if(calls===2){await callbacks.onPrompt({message:'Abort'});throw Error('abort resolved')}if(calls===3){let stale=false;try{oldCallbacks.onProgress('late')}catch(error){stale=true}return {access:'reused',stale}}throw Error('oauth-original-failure')}}})}
    ;
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource(extension_source);
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const config = try streamConfig(started.manifest_json);
    defer gpa.free(config);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, config, .{});
    defer parsed.deinit();
    const callback = parsed.value.object.get("oauth").?.object.get("login").?.object.get("__pi_callback_id").?.string;
    const Ui = struct {
        flag: *bool,
        requests: usize = 0,
        actions: usize = 0,
        cancelled: bool = false,
        abort: bool = false,
        fn request(context: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args: []const u8) ![]u8 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.requests += 1;
            if (self.abort) {
                @atomicStore(bool, self.flag, true, .release);
                std.testing.io.sleep(.fromMilliseconds(5000), .awake) catch |err| {
                    self.cancelled = true;
                    return err;
                };
                return error.AbortDidNotCancelPrompt;
            }
            var request_value = try std.json.parseFromSlice(std.json.Value, allocator, args, .{});
            defer request_value.deinit();
            if (std.mem.eql(u8, method, "oauth_prompt")) {
                try std.testing.expect(request_value.value.object.get("secret").?.bool);
                return allocator.dupe(u8, "\"tenant\"");
            }
            return allocator.dupe(u8, if (std.mem.eql(u8, method, "oauth_manual_code")) "\"manual\"" else "\"b\"");
        }
        fn action(context: ?*anyopaque, _: std.mem.Allocator, method: []const u8, _: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            try std.testing.expect(std.mem.startsWith(u8, method, "oauth_"));
            self.actions += 1;
        }
        fn bridge(self: *@This()) runtime_mod.UiBridge {
            return .{ .context = self, .request_fn = request, .action_fn = action };
        }
    };
    var flag = false;
    var ui: Ui = .{ .flag = &flag };
    const first = try started.runtime.invokeProviderOAuthLogin(callback, &flag, ui.bridge());
    defer gpa.free(first);
    try std.testing.expectEqual(@as(usize, 3), ui.requests);
    try std.testing.expectEqual(@as(usize, 3), ui.actions);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"caught\":true") != null and std.mem.indexOf(u8, first, "tenant") != null and std.mem.indexOf(u8, first, "manual") != null);
    var first_json = try std.json.parseFromSlice(std.json.Value, gpa, first, .{});
    defer first_json.deinit();
    try std.testing.expectEqual(@as(usize, 3), first_json.value.object.get("actionQueue").?.array.items.len);
    ui.abort = true;
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, started.runtime.invokeProviderOAuthLogin(callback, &flag, ui.bridge()));
    try std.testing.expect(ui.cancelled and !started.runtime.closed);
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "Operation aborted") != null);
    flag = false;
    ui.abort = false;
    const reused = try started.runtime.invokeProviderOAuthLogin(callback, &flag, ui.bridge());
    defer gpa.free(reused);
    try std.testing.expect(std.mem.indexOf(u8, reused, "reused") != null and std.mem.indexOf(u8, reused, "\"stale\":true") != null);
    try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, started.runtime.invokeProviderOAuthLogin(callback, &flag, ui.bridge()));
    try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "oauth-original-failure") != null);
    try fixture.noBridge();
}

test "native runtime custom overlay handles geometry key release hidden input fences and original callback errors" {
    const extension_source =
        \\export default function(pi){let oldHandle;pi.registerCommand('overlay',{async handler(mode,ctx){let disposed=0,optionCalls=0,inputs=0,handle,initialBounds;const original={overlayError:true};try{const result=await ctx.ui.custom((tui,theme,keys,done)=>({wantsKeyRelease:true,render(width){return ['overlay:'+width,'second','third','fourth']},handleInput(data){inputs++;if(data==='q')done({inputs,bounds:handle.getBounds(),optionCalls,initialBounds})},invalidate(){},dispose(){disposed++}}),{overlay:true,overlayOptions(){optionCalls++;return {width:'50%',maxHeight:3,margin:1,anchor:'bottom-right'}},onHandle(value){handle=value;oldHandle=value;initialBounds=value.getBounds();if(mode==='error')throw original;value.setHidden(true);value.unfocus();setTimeout(()=>{value.setHidden(false);value.focus()},10)}});return {result,disposed,staleHidden:oldHandle.isHidden(),staleFocused:oldHandle.isFocused()}}catch(error){return {caught:error===original,disposed}}}})}
    ;
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource(extension_source);
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, std.testing.io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setContextJson("{\"hasUI\":true,\"width\":80,\"height\":24}");
    const Ui = struct {
        visible: usize = 0,
        hidden: bool = false,
        closes: usize = 0,
        fail: bool = false,
        fn request(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) ![]u8 {
            return error.UnexpectedStandardDialog;
        }
        fn action(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) !void {}
        fn scene(context: ?*anyopaque, received: component_protocol.Scene, queue: *component_protocol.ControlQueue) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            var owned = received;
            var consumed = false;
            defer if (consumed) owned.deinit();
            try std.testing.expect(received.wants_key_release);
            const layout = received.overlay orelse return error.MissingOverlayLayout;
            try std.testing.expect(layout.capture_input);
            if (layout.hidden) {
                self.hidden = true;
                try std.testing.expect(!received.focused and received.frame.lines.len == 0);
            } else {
                self.visible += 1;
                try std.testing.expect(received.focused);
                try std.testing.expectEqual(@as(usize, 40), layout.width);
                try std.testing.expectEqual(@as(usize, 3), layout.height);
                try std.testing.expectEqual(@as(usize, 20), layout.row);
                try std.testing.expectEqual(@as(usize, 39), layout.column);
                try std.testing.expectEqual(@as(usize, 3), received.frame.lines.len);
                try std.testing.expectEqualStrings("overlay:40", received.frame.lines[0]);
            }
            if (layout.hidden or (self.hidden and !self.fail)) {
                var control: component_protocol.Control = .{ .gpa = std.heap.page_allocator, .fence = received.fence, .kind = .{ .input = try std.heap.page_allocator.dupe(u8, if (layout.hidden) "ignored" else "q") } };
                var transferred = false;
                defer if (!transferred) control.deinit();
                try queue.send(control);
                transferred = true;
            }
            consumed = true;
        }
        fn close(context: ?*anyopaque, _: component_protocol.Fence) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.closes += 1;
        }
    };
    var ui: Ui = .{};
    started.runtime.setUiBridge(.{ .context = &ui, .request_fn = Ui.request, .action_fn = Ui.action, .component_scene_fn = Ui.scene, .component_close_fn = Ui.close });
    const result = try started.runtime.invokeCommand("overlay", "normal", "{}");
    defer gpa.free(result);
    try std.testing.expect(ui.hidden and ui.visible >= 1);
    try std.testing.expectEqual(@as(usize, 1), ui.closes);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"inputs\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"optionCalls\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"disposed\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"staleHidden\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"staleFocused\":false") != null);
    ui = .{ .fail = true };
    const failure = try started.runtime.invokeCommand("overlay", "error", "{}");
    defer gpa.free(failure);
    try std.testing.expect(std.mem.indexOf(u8, failure, "\"caught\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, failure, "\"disposed\":1") != null);
    try std.testing.expectEqual(@as(usize, 1), ui.closes);
    try std.testing.expect(!started.runtime.closed);
    try fixture.noBridge();
}

test "native runtime custom human wait live invocation abort negative close ACK and headless defaults stay bounded" {
    const extension_source =
        \\export default pi=>pi.registerTool({name:'component-wait',async execute(id,args,signal,update,ctx){let disposed=0;try{const result=await ctx.ui.custom((tui,theme,keys,done)=>{if(args.mode==='factory-wait')return new Promise(()=>{});return {render(){return ['waiting:'+id]},handleInput(data){if(data==='q')done('selected')},invalidate(){},dispose(){disposed++}}});return {content:[{type:'text',text:result===undefined?'cancelled':result}],details:{disposed,aborted:signal.aborted}}}catch(error){return {content:[{type:'text',text:'close-error:'+error.message}],details:{disposed}}}}})
    ;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.initSource(extension_source);
    defer fixture.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setContextJson("{\"hasUI\":true}");
    const Ui = struct {
        flag: *bool,
        mode: enum { human, abort, negative_ack } = .human,
        delay: std.Io.Group = .init,
        frames: usize = 0,
        closes: usize = 0,
        fn request(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) ![]u8 {
            return error.UnexpectedStandardDialog;
        }
        fn action(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) !void {}
        fn delayed(queue: *component_protocol.ControlQueue, fence: component_protocol.Fence) std.Io.Cancelable!void {
            try std.testing.io.sleep(.fromMilliseconds(80), .awake);
            var control: component_protocol.Control = .{ .gpa = std.heap.page_allocator, .fence = fence, .kind = .{ .input = std.heap.page_allocator.dupe(u8, "q") catch return } };
            var transferred = false;
            defer if (!transferred) control.deinit();
            queue.send(control) catch return;
            transferred = true;
        }
        fn scene(context: ?*anyopaque, received: component_protocol.Scene, queue: *component_protocol.ControlQueue) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            var frame = received;
            self.frames += 1;
            if (self.mode == .abort) @atomicStore(bool, self.flag, true, .release) else try self.delay.concurrent(std.testing.io, delayed, .{ queue, received.fence });
            frame.deinit();
        }
        fn close(context: ?*anyopaque, _: component_protocol.Fence) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.closes += 1;
            try self.delay.await(std.testing.io);
            if (self.mode == .negative_ack) return error.InjectedComponentCloseFailure;
        }
        fn deinit(self: *@This()) void {
            self.delay.cancel(std.testing.io);
        }
    };
    var aborted = false;
    var ui: Ui = .{ .flag = &aborted };
    defer ui.deinit();
    started.runtime.setUiBridge(.{ .context = &ui, .request_fn = Ui.request, .action_fn = Ui.action, .component_scene_fn = Ui.scene, .component_close_fn = Ui.close });
    const human = try started.runtime.invokeToolCall("human", "component-wait", "{}", "{}", &aborted);
    defer gpa.free(human);
    try std.testing.expect(std.mem.indexOf(u8, human, "selected") != null);
    try std.testing.expect(std.mem.indexOf(u8, human, "\"disposed\":1") != null);
    try std.testing.expectEqual(@as(usize, 1), ui.closes);
    ui.mode = .abort;
    const cancelled = try started.runtime.invokeToolCall("abort", "component-wait", "{}", "{}", &aborted);
    defer gpa.free(cancelled);
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "cancelled") != null);
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "\"aborted\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "\"disposed\":1") != null);
    aborted = false;
    ui.mode = .negative_ack;
    const failure = try started.runtime.invokeToolCall("negative", "component-wait", "{}", "{}", &aborted);
    defer gpa.free(failure);
    try std.testing.expect(std.mem.indexOf(u8, failure, "InjectedComponentCloseFailure") != null);
    try std.testing.expect(std.mem.indexOf(u8, failure, "\"disposed\":1") != null);
    try std.testing.expect(!started.runtime.closed);
    try started.runtime.setContextJson("{\"hasUI\":false}");
    const headless = try started.runtime.invokeTool("component-wait", "{}", "{}");
    defer gpa.free(headless);
    try std.testing.expect(std.mem.indexOf(u8, headless, "cancelled") != null);
    try std.testing.expect(std.mem.indexOf(u8, headless, "\"disposed\":0") != null);
    try started.runtime.setContextJson("{\"hasUI\":true}");
    started.runtime.timeout_ms = 30;
    try std.testing.expectError(error.JavaScriptExtensionTimeout, started.runtime.invokeTool("component-wait", "{\"mode\":\"factory-wait\"}", "{}"));
    try std.testing.expect(started.runtime.closed and started.runtime.child.id == null);
}

const Fixture = struct {
    tmp: std.testing.TmpDir,
    root: []u8,
    source_path: []u8,
    executable: []u8,
    environment: std.process.Environ.Map,

    fn init() !Fixture {
        return initSource(source);
    }

    fn initSource(extension_source: []const u8) !Fixture {
        const gpa = std.testing.allocator;
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        try tmp.dir.createDirPath(io, "extensions");
        try tmp.dir.writeFile(io, .{ .sub_path = "extensions/native.ts", .data = extension_source });
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try tmp.dir.realPath(io, &buffer);
        const root = try gpa.dupe(u8, buffer[0..length]);
        errdefer gpa.free(root);
        const source_path = try std.fs.path.join(gpa, &.{ root, "extensions", "native.ts" });
        errdefer gpa.free(source_path);
        const executable = try @import("test_support/pty.zig").executablePath(gpa, io, if (builtin.os.tag == .windows) "zig-out/bin/pi.exe" else "zig-out/bin/pi");
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
    const missing = try std.fs.path.join(std.testing.allocator, &.{ fixture.root, "intentionally-missing-native-executable" });
    defer std.testing.allocator.free(missing);
    try std.testing.expectError(error.FileNotFound, runtime_mod.Runtime.startNative(std.testing.allocator, std.testing.io, fixture.source_path, .{ .executable = missing, .environ_map = &fixture.environment }));
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

test "native runtime reader and human dialogs progress with zero eager async capacity" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extensions/native.ts", .data = ui_source });
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .nothing });
    defer threaded.deinit();
    const io = threaded.io();
    var controller = try ui_mod.Controller.init(gpa, io, false, 80);
    defer controller.deinit();
    var dialogs: DialogUi = .{ .controller = &controller, .io = io };
    defer dialogs.deinit();
    const started = try runtime_mod.Runtime.startNative(gpa, io, fixture.source_path, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.setUiBridge(dialogs.bridge());
    try started.runtime.setContextJson("{\"hasUI\":true}");
    const human = try started.runtime.invokeCommand("ui", "human", "{}");
    defer gpa.free(human);
    try std.testing.expect(std.mem.indexOf(u8, human, "green") != null);
    started.runtime.timeout_ms = 1000;
    const cancelled = try started.runtime.invokeCommand("ui", "cancel", "{}");
    defer gpa.free(cancelled);
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "cancel-defaults") != null);
    try std.testing.expectEqual(@as(usize, 3), dialogs.cancelled.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), dialogs.active.load(.acquire));
    try std.testing.expect(!started.runtime.closed);
    const reused = try started.runtime.invokeCommand("ui", "roundtrip", "{}");
    defer gpa.free(reused);
    try std.testing.expect(std.mem.indexOf(u8, reused, "Ada") != null);
}

test "native runtime startup releases its exact worker when concurrency is unavailable" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .nothing, .concurrent_limit = .nothing });
    defer threaded.deinit();
    try std.testing.expectError(error.ConcurrencyUnavailable, runtime_mod.Runtime.startNative(std.testing.allocator, threaded.io(), fixture.source_path, fixture.options()));
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

test "native runtime custom prompt hooks retain live UI context and publish both statuses after close ACK" {
    const gpa = std.testing.allocator;
    var fixture = try Fixture.initSource("export default function(pi){let starts=0,ends=0;pi.on('ui_prompt_start',(_,ctx)=>{starts++;ctx.ui.setStatus('custom-life','start'+starts+'-end'+ends)});pi.on('ui_prompt_end',(_,ctx)=>{ends++;ctx.ui.setStatus('custom-life','start'+starts+'-end'+ends)});pi.registerCommand('custom-hooks',{async handler(_,ctx){await ctx.ui.custom((tui,theme,keys,done)=>({render(){return ['owned']},handleInput(){done()},dispose(){}}));return {message:'closed'}}})}");
    defer fixture.deinit();
    var controller = try ui_mod.Controller.init(gpa, std.testing.io, false, 80);
    defer controller.deinit();
    var host: host_mod.Host = .{ .gpa = gpa, .io = std.testing.io, .script_backend = .native, .native_runtime_options = fixture.options() };
    defer host.deinit();
    var integration = integration_mod.Bridge.init(&host);
    defer integration.deinit();
    const Ui = struct {
        closes: usize = 0,
        fn prompt(context: ?*anyopaque, event: ui_mod.PromptEvent, method: []const u8) void {
            const bridge: *integration_mod.Bridge = @ptrCast(@alignCast(context.?));
            bridge.uiPromptEvent(event, method);
        }
        fn scene(_: ?*anyopaque, received: component_protocol.Scene, queue: *component_protocol.ControlQueue) !void {
            var control: component_protocol.Control = .{ .gpa = std.heap.page_allocator, .fence = received.fence, .kind = .{ .input = try std.heap.page_allocator.dupe(u8, "done") } };
            var transferred = false;
            defer if (!transferred) control.deinit();
            try queue.send(control);
            transferred = true;
            var owned = received;
            owned.deinit();
        }
        fn close(context: ?*anyopaque, _: component_protocol.Fence) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.closes += 1;
        }
    };
    var ui: Ui = .{};
    controller.bindPromptEvents(Ui.prompt, &integration);
    controller.bindComponentScenes(Ui.scene, Ui.close, &ui);
    host.setScriptUiBridge(controller.bridge());
    try host.setScriptContextJson("{\"hasUI\":true}");
    try host.loadPath(fixture.source_path);
    var result = (try host.executeCommand("custom-hooks", "")).?;
    defer result.deinit(gpa);
    try std.testing.expect(!result.is_error);
    try std.testing.expectEqual(@as(usize, 1), ui.closes);
    try std.testing.expectEqual(@as(usize, 1), controller.statuses.items.len);
    try std.testing.expectEqualStrings("custom-life", controller.statuses.items[0].key);
    try std.testing.expectEqualStrings("start1-end1", controller.statuses.items[0].text);
    try std.testing.expectEqual(@as(usize, 0), host.ui_prompt_events.items.len);
}

test "native runtime rejected callbacks preserve admitted action order origin and reuse for singleton and group owners without Node" {
    const actions_mod = @import("extensions/actions.zig");
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.initSource("export default pi=>{globalThis.firstApi=pi;let saved;pi.registerCommand('reject',{async handler(raw,ctx){saved=ctx;pi.appendEntry('before-one',{sourceExtensionName:'spoof'});if(globalThis.secondApi)secondApi.appendEntry('before-two',{});await Promise.resolve();pi.setSessionName('before-three');throw Error('prethrow-original:'+raw)}});pi.registerCommand('reuse',{handler(){let stale=false;try{saved.cwd}catch(error){stale=true}return {message:String(stale)}}});pi.on('before_agent_start',()=>{pi.appendEntry('hook-before',{});throw Error('hook-original')});pi.registerTool({name:'reject-tool',execute(){pi.appendEntry('tool-before',{});throw Error('tool-original')}})}");
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(io, .{ .sub_path = "extensions/second.ts", .data = "export default pi=>{globalThis.secondApi=pi;pi.registerCommand('second',{handler(){return {}}})}" });
    const second_path = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second_path);
    for ([_]bool{ false, true }) |group| {
        const started = if (group)
            try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{ fixture.source_path, second_path }, fixture.options())
        else
            try runtime_mod.Runtime.startNative(gpa, io, fixture.source_path, fixture.options());
        defer started.runtime.deinit();
        defer gpa.free(started.manifest_json);
        try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, if (group)
            started.runtime.invokeGroupRequest(1, "{\"kind\":\"command\",\"name\":\"reject\",\"rawArguments\":\"payload\"}", null)
        else
            started.runtime.invokeCommand("reject", "payload", "{}"));
        try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "prethrow-original:payload") != null);
        var queue = actions_mod.Queue.init(gpa, io);
        defer queue.deinit();
        var failing = std.testing.FailingAllocator.init(gpa, .{ .fail_index = 0 });
        var unavailable = actions_mod.Queue.init(failing.allocator(), io);
        defer unavailable.deinit();
        try std.testing.expectError(error.OutOfMemory, started.runtime.transferRendererActions(&unavailable));
        try std.testing.expectEqual(@as(usize, if (group) 3 else 2), started.runtime.rendererActionCount());
        try started.runtime.transferRendererActions(&queue);
        const records = try queue.drain();
        defer {
            for (records) |*record| record.deinit(gpa);
            gpa.free(records);
        }
        try std.testing.expectEqual(@as(usize, if (group) 3 else 2), records.len);
        try std.testing.expectEqualStrings("append_entry", records[0].kind);
        try std.testing.expectEqualStrings("native", records[0].extension_name);
        if (group) try std.testing.expectEqualStrings("second", records[1].extension_name);
        try std.testing.expectEqualStrings("set_session_name", records[records.len - 1].kind);
        for (records, 0..) |record, index| try std.testing.expectEqual(@as(u64, index + 1), record.sequence);
        const reused = if (group)
            try started.runtime.invokeGroupRequest(1, "{\"kind\":\"command\",\"name\":\"reuse\",\"rawArguments\":\"\"}", null)
        else
            try started.runtime.invokeCommand("reuse", "", "{}");
        defer gpa.free(reused);
        try std.testing.expect(std.mem.indexOf(u8, reused, "true") != null);
        try std.testing.expectEqual(@as(usize, 0), started.runtime.rendererActionCount());
        try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, if (group)
            started.runtime.invokeGroupRequest(1, "{\"kind\":\"hook\",\"name\":\"before_agent_start\",\"payload\":{}}", null)
        else
            started.runtime.invokeHook("before_agent_start", "{}", "{}"));
        try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "hook-original") != null);
        try std.testing.expectError(error.JavaScriptExtensionExecutionFailed, if (group)
            started.runtime.invokeGroupRequest(1, "{\"kind\":\"tool\",\"name\":\"reject-tool\",\"payload\":{}}", null)
        else
            started.runtime.invokeTool("reject-tool", "{}", "{}"));
        try std.testing.expect(std.mem.indexOf(u8, started.runtime.lastError().?, "tool-original") != null);
        try started.runtime.transferRendererActions(&queue);
        const trailing = try queue.drain();
        defer {
            for (trailing) |*record| record.deinit(gpa);
            gpa.free(trailing);
        }
        try std.testing.expectEqual(@as(usize, 2), trailing.len);
        try std.testing.expect(std.mem.indexOf(u8, trailing[0].json, "hook-before") != null);
        try std.testing.expect(std.mem.indexOf(u8, trailing[1].json, "tool-before") != null);
        try std.testing.expect(!started.runtime.closed);
    }
    try fixture.noBridge();
}

test "native runtime qualified registry preserves chat facade live shared provider precedence typed identity removal and stale contexts without Node" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try Fixture.initSource(
        \\import {createModels} from '@earendil-works/pi-ai';import {createModels as alias} from 'pi-ai';
        \\export default pi=>{if(createModels!==alias)throw Error('model alias identity');
        \\const chat={id:'same',provider:'shared'},image={id:'same',type:'image',provider:'shared'};globalThis.firstProvider={id:'shared',auth:{apiKey:{async check(){return {type:'api_key'}}}},getModels(){return [chat]},getAllModels(){if(this!==firstProvider)throw Error('first receiver');return [chat,image]}};pi.registerProvider(firstProvider);
        \\pi.registerProvider('named',{api:'openai-completions',apiKey:'fixture-key',models:[{id:'chat'},{id:'image',type:'image',api:'openrouter-images'},{id:'classifier',type:'classifier',api:'typesafe-system-one'}]});
        \\pi.registerCommand('inspect',{async handler(_,ctx){const r=ctx.modelRegistry;globalThis.savedRegistry=r;if(r!==ctx.modelRegistry)throw Error('registry identity');const chats=r.getAll(),images=r.getModelsOfType('image'),classifiers=r.getModelsOfType('classifier'),available=await r.getAvailableOfType('image');return {message:JSON.stringify({chats:chats.map(m=>m.provider+'/'+m.id),images:images.map(m=>m.provider+'/'+m.id),classifiers:classifiers.map(m=>m.provider+'/'+m.id),available:available.map(m=>m.provider+'/'+m.id),identity:r.findOfType('image','shared','same')===secondImage,receiver:r.getRegisteredNativeProvider('shared')===secondProvider,configured:r.getAvailable().map(m=>m.provider+'/'+m.id)})}}});
        \\pi.registerCommand('late',{handler(_,ctx){const model={id:'late',provider:'shared'};const replacement={id:'shared',auth:{apiKey:{check(){return {type:'api_key'}}}},getModels(){if(this!==replacement)throw Error('replacement receiver');return [model]},getAllModels(){return [model]}};pi.registerProvider(replacement);return {message:ctx.modelRegistry.getAll().map(m=>m.id).join(',')}}});
        \\pi.registerCommand('remove',{handler(_,ctx){pi.unregisterProvider('shared');return {message:String(ctx.modelRegistry.getProvider('shared')===undefined)}}});
        \\pi.registerCommand('stale',{handler(_,ctx){let rejected=false;try{savedRegistry.getAll()}catch(error){rejected=true}return {message:String(rejected),models:ctx.modelRegistry.getAll().map(m=>m.id)}}});
        \\}
    );
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(io, .{ .sub_path = "extensions/second.ts", .data = "export default pi=>{globalThis.secondImage={id:'same',type:'image',provider:'shared'};globalThis.secondProvider={id:'shared',auth:{apiKey:{async check(){return {type:'api_key'}}}},getModels(){if(this!==secondProvider)throw Error('second receiver');return [{id:'second',provider:'shared'}]},getAllModels(){return [this.getModels()[0],secondImage]}};pi.registerProvider(secondProvider);pi.registerCommand('stale',{handler(_,ctx){let rejected=false;try{savedRegistry.getAll()}catch(error){rejected=true}return {message:String(rejected),models:ctx.modelRegistry.getAll().map(m=>m.id)}}})}" });
    const second = try std.fs.path.join(gpa, &.{ fixture.root, "extensions", "second.ts" });
    defer gpa.free(second);
    const started = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{ fixture.source_path, second }, fixture.options());
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    try started.runtime.setContextJson("{\"models\":[{\"id\":\"base-chat\",\"provider\":\"base\"},{\"id\":\"base-image\",\"provider\":\"base\",\"type\":\"image\"}],\"configuredProviders\":[\"base\",\"named\"]}");
    const inspected = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"command\",\"name\":\"inspect\",\"rawArguments\":\"\"}", null);
    defer gpa.free(inspected);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, inspected, .{});
    defer parsed.deinit();
    var details = try std.json.parseFromSlice(std.json.Value, gpa, parsed.value.object.get("message").?.string, .{});
    defer details.deinit();
    try std.testing.expect(details.value.object.get("identity").?.bool and details.value.object.get("receiver").?.bool);
    try std.testing.expectEqual(@as(usize, 3), details.value.object.get("chats").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 3), details.value.object.get("images").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 1), details.value.object.get("classifiers").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 3), details.value.object.get("available").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 2), details.value.object.get("configured").?.array.items.len);
    const unloaded = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"group_remove_source\",\"ownerId\":2}", null);
    defer gpa.free(unloaded);
    const stale = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"command\",\"name\":\"stale\",\"rawArguments\":\"\"}", null);
    defer gpa.free(stale);
    try std.testing.expect(std.mem.indexOf(u8, stale, "true") != null and std.mem.indexOf(u8, stale, "same") != null and std.mem.indexOf(u8, stale, "second") == null);
    const late = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"command\",\"name\":\"late\",\"rawArguments\":\"\"}", null);
    defer gpa.free(late);
    try std.testing.expect(std.mem.indexOf(u8, late, "late") != null and std.mem.indexOf(u8, late, "second") == null);
    const removed = try started.runtime.invokeGroupRequest(1, "{\"kind\":\"command\",\"name\":\"remove\",\"rawArguments\":\"\"}", null);
    defer gpa.free(removed);
    try std.testing.expect(std.mem.indexOf(u8, removed, "true") != null);

    try fixture.noBridge();
}
