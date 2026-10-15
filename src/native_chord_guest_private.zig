//! Private native Chord child executable. It runs the real guest entry through
//! QuickJS/native modules and authenticates only its inherited scoped channel.
const std = @import("std");
const h = @import("extensions/native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const processes = @import("extensions/native_chord_process_runtime.zig");
const owner = @import("extensions/native_chord_fork_owner.zig");
const streams = @import("extensions/native_process_streams.zig");
fn guard(_: ?*anyopaque) !void {}
fn control(_: ?*anyopaque, value: streams.Control) !void {
    // Source fork uses stdin:'ignore'. There is no parent-owned input terminal.
    if (value == .raw_mode and value.raw_mode) return error.NativeChordGuestInputTerminalUnavailable;
}
fn write(raw: ?*anyopaque, stream: streams.Output, bytes: []const u8) !void {
    const runtime: *processes.Runtime = @ptrCast(@alignCast(raw.?));
    try (if (stream == .stdout) std.Io.File.stdout() else std.Io.File.stderr()).writeStreamingAll(runtime.io, bytes);
}
fn exit(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    const runtime: *processes.Runtime = @ptrCast(@alignCast(engine.native_chord_process_runtime orelse return error.NativeChordProcessRuntimeUnavailable));
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const receiver = captures[0];
    var code: u32 = 0;
    const selected = if (c.JS_IsUndefined(h.arg(args, 0))) try s.get(receiver, "exitCode") else h.arg(args, 0);
    if (!c.JS_IsUndefined(selected) and c.JS_ToUint32(engine.context, &code, selected) < 0) return js.capture(engine);
    const already_exiting = runtime.exiting;
    runtime.exiting = true;
    try h.field(&s, receiver, "exitCode", c.JS_NewUint32(engine.context, code));
    if (!already_exiting) _ = try h.invoke(&s, receiver, "emit", &.{ try s.text("exit"), c.JS_NewUint32(engine.context, code) });
    runtime.requested_exit = @truncate(code);
    const termination = try s.keep(try js.builtin(engine, "Error", &.{try s.text("Native Chord guest requested process.exit")}));
    c.JS_SetUncatchableError(engine.context, termination);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, termination));
    return js.capture(engine);
}
fn ipcReferenced(engine: *h.Engine, process: c.JSValue) !bool {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const message_listeners = try h.invoke(&s, process, "listenerCount", &.{try s.text("message")});
    const disconnect_listeners = try h.invoke(&s, process, "listenerCount", &.{try s.text("disconnect")});
    var messages: u32 = 0;
    var disconnects: u32 = 0;
    if (c.JS_ToUint32(engine.context, &messages, message_listeners) < 0 or c.JS_ToUint32(engine.context, &disconnects, disconnect_listeners) < 0) return js.capture(engine);
    return messages != 0 or disconnects != 0;
}
fn exitCode(engine: *h.Engine, process: c.JSValue) !u8 {
    const selected = try js.get(engine, process, "exitCode");
    defer engine.freeValue(selected);
    var code: u32 = 0;
    if (!c.JS_IsUndefined(selected) and c.JS_ToUint32(engine.context, &code, selected) < 0) return js.capture(engine);
    return @truncate(code);
}
pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    if (arguments.len < 4 or !std.mem.eql(u8, arguments[1], "--entry") or !std.mem.eql(u8, arguments[3], "--")) return error.NativeChordGuestArgumentsInvalid;
    const inherited = init.environ_map;
    const port_text = inherited.get(owner.port_env) orelse return error.NativeChordGuestAdmissionMissing;
    const token_text = inherited.get(owner.token_env) orelse return error.NativeChordGuestAdmissionMissing;
    const port = try std.fmt.parseInt(u16, port_text, 10);
    if (port == 0 or token_text.len != 32) return error.NativeChordGuestAdmissionInvalid;
    var token: [16]u8 = undefined;
    _ = try std.fmt.hexToBytes(&token, token_text);
    var environment = try inherited.clone(gpa);
    defer environment.deinit();
    // Never expose the private transport capability to guest process.env.
    _ = environment.swapRemove(owner.port_env);
    _ = environment.swapRemove(owner.token_env);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.appendSlice(gpa, &.{ arguments[0], arguments[2] });
    try argv.appendSlice(gpa, arguments[4..]);
    const engine = try h.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = io;
    try @import("extensions/timers.zig").install(engine, io);
    try @import("extensions/native_process.zig").install(engine, io, &environment, argv.items);
    try @import("extensions/typebox.zig").install(engine);
    try @import("extensions/native_durable_context.zig").installContextOnly(engine);
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const classes = try @import("extensions/native_chord_full_v4.zig").classes(engine);
    _ = try s.keep(classes.exports);
    _ = try s.keep(classes.bindings);
    try engine.registerValueModule("@earendil-works/chord", classes.exports);
    const runtime = try processes.Runtime.install(engine, .{ .guest_executable = arguments[0] });
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const process = try s.get(global, "process");
    try runtime.attachChild(process, port, token);
    try js.define(engine, process, "exit", try @import("extensions/native_node_function.zig").create(engine, "exit", 1, exit, &.{process}));
    const lease = try streams.bind(engine, .{ .context = runtime, .guard_fn = guard, .control_fn = control, .write_fn = write });
    defer _ = streams.unbind(engine, lease);
    try engine.registerValueModule("@earendil-works/chord/node", try s.keep(try @import("extensions/native_chord_node_api.zig").exports(engine, classes.bindings)));
    try engine.registerValueModule("@earendil-works/chord/output", try s.keep(try @import("extensions/native_chord_output.zig").exports(engine)));
    try @import("extensions/native_chord_node_loader.zig").installFilesystem(engine);
    const entry_path = if (std.mem.startsWith(u8, arguments[2], "file:")) try gpa.dupe(u8, arguments[2]) else try std.fs.path.resolve(gpa, &.{arguments[2]});
    defer gpa.free(entry_path);
    const entry_json = try std.json.Stringify.valueAlloc(gpa, entry_path, .{});
    defer gpa.free(entry_json);
    const entry_source = try std.fmt.allocPrint(gpa, "await import({s});", .{entry_json});
    defer gpa.free(entry_source);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const loaded = engine.evalModule(entry_source, "native-chord-guest-entry.mjs") catch |err| {
        if (runtime.requested_exit) |code| return code;
        if (engine.last_error) |message| try std.Io.File.stderr().writeStreamingAll(io, message);
        return err;
    };
    engine.freeValue(loaded);
    // Node's child IPC is initially unreferenced until a message/disconnect
    // listener is installed. Real childControl/ipcLink listeners keep it alive.
    while (true) {
        engine.beginInvocation();
        const observed = engine.native_owner_signal.observe();
        const controls_worked = engine.pumpControls() catch |err| {
            if (runtime.requested_exit) |code| return code;
            return err;
        };
        const jobs_worked = engine.drainReadyJobs() catch |err| {
            if (runtime.requested_exit) |code| return code;
            return err;
        };
        const timer_worked = @import("extensions/timers.zig").pumpReady(engine) catch |err| {
            if (runtime.requested_exit) |code| return code;
            return err;
        };
        _ = engine.drainReadyJobs() catch |err| {
            if (runtime.requested_exit) |code| return code;
            return err;
        };
        if (runtime.requested_exit) |code| return code;
        const deadline = try @import("extensions/timers.zig").nextReferencedDeadline(engine);
        const live_ipc = runtime.hasPending() and try ipcReferenced(engine, process);
        if (!live_ipc and !runtime.hasNativeChildren() and deadline == null) {
            _ = h.invoke(&s, process, "emit", &.{ try s.text("beforeExit"), c.JS_NewUint32(engine.context, try exitCode(engine, process)) }) catch |err| {
                if (runtime.requested_exit) |code| return code;
                return err;
            };
            _ = engine.drainReadyJobs() catch |err| {
                if (runtime.requested_exit) |code| return code;
                return err;
            };
            if (runtime.requested_exit) |code| return code;
            if (!runtime.hasNativeChildren() and !(runtime.hasPending() and try ipcReferenced(engine, process)) and try @import("extensions/timers.zig").nextReferencedDeadline(engine) == null) {
                const code = try exitCode(engine, process);
                runtime.exiting = true;
                _ = h.invoke(&s, process, "emit", &.{ try s.text("exit"), c.JS_NewUint32(engine.context, code) }) catch |err| {
                    if (runtime.requested_exit) |requested| return requested;
                    return err;
                };
                return code;
            }
            continue;
        }
        if (controls_worked or jobs_worked or timer_worked) continue;
        const now = std.Io.Clock.awake.now(io).toMilliseconds();
        const wait_ms: i64 = if (deadline) |at| @max(0, @min(10, at - now)) else 10;
        _ = try engine.native_owner_signal.waitAfter(io, observed, .{ .duration = .{ .raw = .fromMilliseconds(wait_ms), .clock = .awake } });
    }
}
