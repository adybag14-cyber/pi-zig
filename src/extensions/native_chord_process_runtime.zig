//! Opt-in native fork/process IPC facade. IO workers own only bytes and OS
//! handles; this leased owner pump alone dispatches VM callbacks.
const std = @import("std");
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const owner_mod = @import("native_chord_fork_owner.zig");
const transport = @import("native_chord_ipc_transport.zig");
const Method = enum(c_int) { spawn, send, sendControl, killTree, onControl, parentMessage, disconnect, sendError };
const Pending = struct { ticket: u64, json: ?[]u8, callback: c.JSValue };
const Entry = struct {
    runtime: *Runtime,
    id: u64,
    state: c.JSValue,
    owner: ?*owner_mod.Owner = null,
    child_endpoint: ?*transport.Endpoint = null,
    sends: std.ArrayList(Pending) = .empty,
    next_ticket: u64 = 1,
    disconnected: bool = false,
    exit_resolved: bool = false,
    failure_reported: bool = false,
    fn endpoint(self: *Entry) ?*transport.Endpoint {
        return if (self.owner) |owner| owner.ipc() else self.child_endpoint;
    }
    fn deinit(self: *Entry) void {
        const runtime = self.runtime;
        if (self.owner) |owner| owner.deinit();
        if (self.child_endpoint) |endpoint| endpoint.deinit();
        for (self.sends.items) |pending| {
            if (pending.json) |json| runtime.engine.gpa.free(json);
            runtime.engine.freeValue(pending.callback);
        }
        self.sends.deinit(runtime.engine.gpa);
        runtime.engine.freeValue(self.state);
        runtime.engine.gpa.destroy(self);
    }
};
pub const Config = struct { guest_executable: []const u8 };
pub const Runtime = struct {
    engine: *h.Engine,
    io: std.Io,
    guest_executable: []u8,
    entries: std.AutoHashMapUnmanaged(u64, *Entry) = .empty,
    next_id: u64 = 1,
    requested_exit: ?u8 = null,
    exiting: bool = false,
    pub fn install(engine: *h.Engine, config: Config) !*Runtime {
        if (engine.native_chord_process_runtime != null) return error.NativeChordProcessRuntimeAlreadyInstalled;
        const io = engine.native_io orelse return error.NativeChordProcessIoUnavailable;
        if (config.guest_executable.len == 0) return error.NativeChordGuestExecutableUnavailable;
        try @import("node_events.zig").install(engine);
        if (engine.text_encoder_class == 0) try @import("text_encoding.zig").install(engine);
        if (engine.text_decoder_class == 0) try @import("text_decoder.zig").install(engine);
        const executable = try engine.gpa.dupe(u8, config.guest_executable);
        errdefer engine.gpa.free(executable);
        const self = try engine.gpa.create(Runtime);
        self.* = .{ .engine = engine, .io = io, .guest_executable = executable };
        engine.native_chord_process_runtime = self;
        engine.native_chord_process_pump = pump;
        engine.native_chord_process_deinit = cleanup;
        return self;
    }
    fn wake(raw: ?*anyopaque) void {
        const self: *Runtime = @ptrCast(@alignCast(raw.?));
        self.engine.native_owner_signal.notify(self.io);
    }
    fn admit(self: *Runtime, state: c.JSValue) !*Entry {
        if (self.next_id > 9007199254740991) return error.NativeChordProcessIdentityExhausted;
        try self.entries.ensureUnusedCapacity(self.engine.gpa, 1);
        const entry = try self.engine.gpa.create(Entry);
        entry.* = .{ .runtime = self, .id = self.next_id, .state = c.JS_DupValue(self.engine.context, state) };
        self.next_id += 1;
        self.entries.putAssumeCapacity(entry.id, entry);
        return entry;
    }
    pub fn hasPending(self: *Runtime) bool {
        return self.entries.count() != 0;
    }
    pub fn hasNativeChildren(self: *Runtime) bool {
        var entries = self.entries.valueIterator();
        while (entries.next()) |entry| if (entry.*.owner != null) return true;
        return false;
    }
};
fn runtime(engine: *h.Engine) !*Runtime {
    return @ptrCast(@alignCast(engine.native_chord_process_runtime orelse return error.NativeChordProcessRuntimeUnavailable));
}
fn cleanup(engine: *h.Engine) void {
    const self = runtime(engine) catch return;
    // Join every leased IO task before releasing the owner signal or VM values.
    var entries = self.entries.valueIterator();
    while (entries.next()) |entry| entry.*.deinit();
    self.entries.deinit(engine.gpa);
    engine.gpa.free(self.guest_executable);
    engine.gpa.destroy(self);
    engine.native_chord_process_runtime = null;
    engine.native_chord_process_pump = null;
    engine.native_chord_process_deinit = null;
}
fn function(s: *h.Scope, state: c.JSValue, method: Method, name: [*:0]const u8, arity: c_int) !c.JSValue {
    var captures = [_]c.JSValue{state};
    return s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, name, arity, @intFromEnum(method), 1, &captures)));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return invoke(engine, captures[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(operation)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn entryOf(s: *h.Scope, state: c.JSValue) !?*Entry {
    var id: u64 = 0;
    if (c.JS_ToIndex(s.engine.context, &id, try s.get(state, "id")) < 0) return js.capture(s.engine);
    return (try runtime(s.engine)).entries.get(id);
}
fn failure(s: *h.Scope, err: anyerror) !c.JSValue {
    return s.keep(try js.builtin(s.engine, "Error", &.{try s.text(@errorName(err))}));
}
fn completeSend(s: *h.Scope, entry: *Entry, index: usize, err: ?anyerror) !void {
    const pending = entry.sends.orderedRemove(index);
    defer s.engine.freeValue(pending.callback);
    if (pending.json) |json| s.engine.gpa.free(json);
    if (c.JS_IsFunction(s.engine.context, pending.callback)) _ = try s.keep(try js.call(s.engine, pending.callback, c.pi_js_undefined(), &.{if (err) |value| try failure(s, value) else c.pi_js_null()}));
}
fn sendCompletion(engine: *h.Engine, args: []const c.JSValue) c.JSValue {
    var completion = c.pi_js_undefined();
    if (args.len > 1) for (args[1..]) |argument| {
        if (c.JS_IsFunction(engine.context, argument)) completion = argument;
    };
    return completion;
}
fn deferSendFailure(s: *h.Scope, state: c.JSValue, completion: c.JSValue, err: anyerror) !void {
    const callback_value = if (c.JS_IsFunction(s.engine.context, completion)) completion else try function(s, state, .sendError, "", 1);
    const process = try s.keep(try js.global(s.engine, "process"));
    _ = try h.invoke(s, process, "nextTick", &.{ callback_value, try failure(s, err) });
}
fn queueSend(s: *h.Scope, entry: *Entry, message: c.JSValue, completion: c.JSValue) !bool {
    if (entry.disconnected) {
        try deferSendFailure(s, entry.state, completion, error.NativeChordIpcDisconnected);
        return false;
    }
    const json_value = try s.keep(try s.engine.checked(c.JS_JSONStringify(s.engine.context, message, c.pi_js_undefined(), c.pi_js_undefined())));
    if (c.JS_IsUndefined(json_value)) {
        _ = c.JS_ThrowTypeError(s.engine.context, "IPC message must be JSON serializable");
        return js.capture(s.engine);
    }
    const json = try s.engine.toString(json_value);
    errdefer s.engine.gpa.free(json);
    if (json.len > transport.maximum_message) return error.NativeChordIpcMessageTooLarge;
    const ticket = entry.next_ticket;
    entry.next_ticket = try std.math.add(u64, ticket, 1);
    const retained_callback = c.JS_DupValue(s.engine.context, completion);
    entry.sends.append(s.engine.gpa, .{ .ticket = ticket, .json = json, .callback = retained_callback }) catch |err| {
        s.engine.freeValue(retained_callback);
        return err;
    };
    errdefer {
        const rejected = entry.sends.pop().?;
        s.engine.freeValue(rejected.callback);
    }
    if (entry.endpoint()) |endpoint| {
        const writable = endpoint.send(ticket, json) catch |err| {
            if (err != error.NativeChordIpcDisconnected) return err;
            try deferSendFailure(s, entry.state, completion, err);
            const rejected = entry.sends.pop().?;
            s.engine.freeValue(rejected.callback);
            s.engine.gpa.free(json);
            return false;
        };
        s.engine.gpa.free(json);
        entry.sends.items[entry.sends.items.len - 1].json = null;
        return writable;
    }
    return true;
}
fn invoke(engine: *h.Engine, state: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .spawn) return spawn(&s, state);
    if (method == .sendError) return js.invoke(engine, try s.get(state, "channel"), "emit", &.{ try s.text("error"), h.arg(args, 0) });
    if (method == .parentMessage) {
        const message = h.arg(args, 0);
        const options = try s.get(state, "options");
        if (!h.nullish(try s.get(options, "onMessage"))) _ = try h.invoke(&s, options, "onMessage", &.{message});
        const control = if (h.nullish(message)) c.pi_js_undefined() else try s.get(message, "chord2control");
        if (!c.JS_IsUndefined(control)) {
            var iterator = try js.Iterator.init(engine, try h.invoke(&s, try s.get(state, "controls"), "values", &.{}), try h.iteratorSymbol(&s));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |listener| {
                defer engine.freeValue(listener);
                _ = try s.keep(try js.call(engine, listener, c.pi_js_undefined(), &.{control}));
            }
        }
        return c.pi_js_undefined();
    }
    if (method == .onControl) return js.invoke(engine, try s.get(state, "controls"), "add", &.{h.arg(args, 0)});
    const entry = (try entryOf(&s, state)) orelse {
        if (method == .send) {
            try deferSendFailure(&s, state, sendCompletion(engine, args), error.NativeChordIpcDisconnected);
            return c.pi_js_bool(engine.context, 0);
        }
        return c.pi_js_undefined();
    };
    if (method == .killTree) {
        if (entry.owner) |owner| owner.killTree();
        return c.pi_js_undefined();
    }
    if (method == .disconnect) {
        if (entry.endpoint()) |endpoint| endpoint.close();
        return c.pi_js_undefined();
    }
    var message = h.arg(args, 0);
    var completion = c.pi_js_undefined();
    if (method == .sendControl) {
        if (!try h.flag(&s, try s.get(state, "channel"), "connected")) return c.pi_js_undefined();
        const envelope = try s.record();
        try h.field(&s, envelope, "chord2control", message);
        message = envelope;
        completion = try s.get(state, "ignoreSendError");
    } else {
        completion = sendCompletion(engine, args);
    }
    const writable = try queueSend(&s, entry, message, completion);
    return if (method == .sendControl) c.pi_js_undefined() else c.pi_js_bool(engine.context, @intFromBool(writable));
}
fn createChannel(s: *h.Scope, state: c.JSValue, existing: ?c.JSValue) !c.JSValue {
    const engine = s.engine;
    const channel = if (existing) |value| value else channel: {
        const module = try s.keep((try engine.requireBuiltin("node:events")) orelse return error.NativeEventEmitterUnavailable);
        const constructor = try s.get(module, "EventEmitter");
        break :channel try s.keep(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    };
    try h.field(s, channel, "connected", c.pi_js_bool(engine.context, 1));
    try h.field(s, channel, "send", try function(s, state, .send, "send", 1));
    try h.field(s, channel, "disconnect", try function(s, state, .disconnect, "disconnect", 0));
    try h.field(s, state, "channel", channel);
    return channel;
}
fn overlayEnvironment(s: *h.Scope, environment: *std.process.Environ.Map, object: c.JSValue) !void {
    if (h.nullish(object)) return;
    const keys = try h.invoke(s, try s.keep(try js.global(s.engine, "Object")), "keys", &.{object});
    var index: u32 = 0;
    while (index < try h.length(s, keys)) : (index += 1) {
        const key_value = try s.at(keys, index);
        const key = try s.engine.toString(key_value);
        defer s.engine.gpa.free(key);
        const value = try s.keep(try js.getKey(s.engine, object, key_value));
        if (c.JS_IsUndefined(value)) {
            _ = environment.swapRemove(key);
            continue;
        }
        const text = try s.engine.toString(value);
        defer s.engine.gpa.free(text);
        if (!std.process.Environ.Map.validateKeyForPut(key) or std.mem.indexOfScalar(u8, text, 0) != null) return error.NativeChordInvalidEnvironment;
        try environment.put(key, text);
    }
}
fn appendArgument(engine: *h.Engine, argv: *std.ArrayList([]const u8), text: []const u8) !void {
    const retained = try engine.gpa.dupe(u8, text);
    errdefer engine.gpa.free(retained);
    try argv.append(engine.gpa, retained);
}
fn appendValueArgument(engine: *h.Engine, argv: *std.ArrayList([]const u8), value: c.JSValue) !void {
    const retained = try engine.toString(value);
    errdefer engine.gpa.free(retained);
    try argv.append(engine.gpa, retained);
}
fn spawn(s: *h.Scope, driver: c.JSValue) !c.JSValue {
    const engine = s.engine;
    const self = try runtime(engine);
    const options = try s.get(driver, "options");
    const flags = try s.get(options, "execArgv");
    if (!h.nullish(flags) and try h.length(s, flags) != 0) return error.NativeChordExecArgvUnsupported;
    var environment: std.process.Environ.Map = .init(engine.gpa);
    defer environment.deinit();
    try overlayEnvironment(s, &environment, try s.get(try s.keep(try js.global(engine, "process")), "env"));
    _ = environment.swapRemove("CHORD2_LOCK");
    try overlayEnvironment(s, &environment, try s.get(options, "env"));
    const lock = try s.get(options, "lock");
    if (!c.JS_IsUndefined(lock)) {
        const name = try engine.toString(lock);
        defer engine.gpa.free(name);
        try environment.put("CHORD2_LOCK", name);
    }
    var argv: std.ArrayList([]const u8) = .empty;
    defer {
        for (argv.items) |value| engine.gpa.free(value);
        argv.deinit(engine.gpa);
    }
    for ([_][]const u8{ self.guest_executable, "--entry" }) |value| try appendArgument(engine, &argv, value);
    try appendValueArgument(engine, &argv, try s.get(options, "entry"));
    try appendArgument(engine, &argv, "--");
    const arguments = try s.get(options, "args");
    if (!h.nullish(arguments)) {
        var iterator = try js.Iterator.init(engine, arguments, try h.iteratorSymbol(s));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |value| {
            defer engine.freeValue(value);
            const text = try engine.toString(value);
            errdefer engine.gpa.free(text);
            try argv.append(engine.gpa, text);
        }
    }
    const state = try s.record();
    try h.field(s, state, "options", options);
    try h.field(s, state, "ignoreSendError", try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, @import("native_chord_reload_values.zig").noop, "ignoreSendError", 0, 0, 0, null))));
    try h.field(s, state, "controls", try h.set(s));
    const completion = try h.invoke(s, try s.keep(try js.global(engine, "Promise")), "withResolvers", &.{});
    try h.field(s, state, "resolveExit", try s.get(completion, "resolve"));
    const channel = try createChannel(s, state, null);
    _ = try h.invoke(s, channel, "on", &.{ try s.text("message"), try function(s, state, .parentMessage, "", 1) });
    const instance = try s.record();
    try h.field(s, instance, "link", try h.construct(s, try s.get(driver, "bindings"), "IpcLink", &.{channel}));
    try h.field(s, instance, "exited", try s.get(completion, "promise"));
    inline for (.{ .{ "send", Method.sendControl, 1 }, .{ "killTree", Method.killTree, 0 }, .{ "onControl", Method.onControl, 1 } }) |entry| try h.field(s, instance, entry[0], try function(s, state, entry[1], entry[0], entry[2]));
    const owned = try self.admit(state);
    errdefer {
        _ = self.entries.remove(owned.id);
        owned.deinit();
    }
    try h.field(s, state, "id", c.JS_NewFloat64(engine.context, @floatFromInt(owned.id)));
    owned.owner = try owner_mod.Owner.start(engine.gpa, self.io, .{ .argv = argv.items, .environment = &environment, .output_tap = c.JS_ToBool(engine.context, try s.get(options, "onOutput")) != 0, .wake = .{ .context = self, .notify = Runtime.wake } });
    try h.field(s, instance, "pid", c.JS_NewUint32(engine.context, owned.owner.?.pid));
    const initial = try s.get(options, "init");
    if (!c.JS_IsUndefined(initial)) {
        const message = try s.record();
        try h.field(s, message, "type", try s.text("init"));
        try h.field(s, message, "value", initial);
        const envelope = try s.record();
        try h.field(s, envelope, "chord2control", message);
        _ = try queueSend(s, owned, envelope, try s.get(state, "ignoreSendError"));
    }
    return s.result(instance);
}
pub fn forkDriver(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.record();
    try h.field(&s, state, "options", h.arg(args, 0));
    try h.field(&s, state, "bindings", captures[0]);
    const driver = try s.record();
    try h.field(&s, driver, "spawn", try function(&s, state, .spawn, "spawn", 0));
    return s.result(driver);
}
pub fn attachChild(self: *Runtime, channel: c.JSValue, port: u16, token: [16]u8) !void {
    var s: h.Scope = .{ .engine = self.engine };
    defer s.deinit();
    const state = try s.record();
    const entry = try self.admit(state);
    errdefer {
        _ = self.entries.remove(entry.id);
        entry.deinit();
    }
    try h.field(&s, state, "id", c.JS_NewFloat64(self.engine.context, @floatFromInt(entry.id)));
    _ = try createChannel(&s, state, channel);
    entry.child_endpoint = try owner_mod.connectChild(self.io, port, token, .{ .context = self, .notify = Runtime.wake });
}
fn disconnected(s: *h.Scope, entry: *Entry, err: ?anyerror) !void {
    if (entry.disconnected) return;
    entry.disconnected = true;
    const channel = try s.get(entry.state, "channel");
    try h.field(s, channel, "connected", c.pi_js_bool(s.engine.context, 0));
    while (entry.sends.items.len != 0) try completeSend(s, entry, 0, err orelse error.NativeChordIpcDisconnected);
    _ = try h.invoke(s, channel, "emit", &.{try s.text("disconnect")});
}
fn pump(engine: *h.Engine) !bool {
    const self = try runtime(engine);
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    // Snapshot numeric identities, since user callbacks may spawn another child.
    const ids = try engine.gpa.alloc(u64, self.entries.count());
    defer engine.gpa.free(ids);
    var keys = self.entries.keyIterator();
    var count: usize = 0;
    while (keys.next()) |id| : (count += 1) ids[count] = id.*;
    var worked = false;
    for (ids) |id| {
        const entry = self.entries.get(id) orelse continue;
        const channel = try s.get(entry.state, "channel");
        if (entry.endpoint()) |endpoint| {
            for (entry.sends.items) |*pending| if (pending.json) |json| {
                _ = endpoint.send(pending.ticket, json) catch |err| {
                    try disconnected(&s, entry, err);
                    break;
                };
                engine.gpa.free(json);
                pending.json = null;
                worked = true;
            };
            while (endpoint.take()) |owned_event| {
                var event = owned_event;
                defer event.deinit();
                worked = true;
                switch (event) {
                    .message => |json| {
                        const value = try s.keep(try engine.checked(c.JS_ParseJSON(engine.context, json.ptr, json.len, "native-chord-ipc")));
                        _ = try h.invoke(&s, channel, "emit", &.{ try s.text("message"), value });
                    },
                    .sent => |sent| {
                        for (entry.sends.items, 0..) |pending, index| if (pending.ticket == sent.ticket) {
                            try completeSend(&s, entry, index, sent.failure);
                            break;
                        };
                    },
                    .disconnected => |err| try disconnected(&s, entry, err),
                }
            }
            if (!endpoint.isConnected()) try disconnected(&s, entry, endpoint.terminalFailure());
        }
        if (entry.owner) |owner| {
            while (owner.takeOutput()) |owned_output| {
                var output = owned_output;
                defer output.deinit();
                const options = try s.get(entry.state, "options");
                const chunk = try s.keep(try @import("node_buffer.zig").fromBytes(engine, output.bytes));
                _ = try h.invoke(&s, options, "onOutput", &.{ try s.text(@tagName(output.stream)), chunk });
                try (if (output.stream == .stdout) std.Io.File.stdout() else std.Io.File.stderr()).writeStreamingAll(self.io, output.bytes);
                worked = true;
            }
            if (owner.terminalFailure()) |err| if (!entry.failure_reported) {
                entry.failure_reported = true;
                owner.killTree();
                _ = try h.invoke(&s, channel, "emit", &.{ try s.text("error"), try failure(&s, err) });
            };
            if (owner.exited()) |exit| {
                if (!entry.exit_resolved) {
                    entry.exit_resolved = true;
                    const value = try s.record();
                    try h.field(&s, value, "code", if (exit.killed) c.pi_js_null() else switch (exit.term) {
                        .exited => |code| c.JS_NewInt32(engine.context, code),
                        else => c.pi_js_null(),
                    });
                    try h.field(&s, value, "signal", if (exit.killed) try s.text("SIGKILL") else switch (exit.term) {
                        .signal => |signal| signal: {
                            const name = try std.fmt.allocPrint(engine.gpa, "SIG{s}", .{@tagName(signal)});
                            defer engine.gpa.free(name);
                            break :signal try s.text(name);
                        },
                        else => c.pi_js_null(),
                    });
                    _ = try s.keep(try js.call(engine, try s.get(entry.state, "resolveExit"), c.pi_js_undefined(), &.{value}));
                    worked = true;
                }
                if (entry.endpoint() == null) try disconnected(&s, entry, error.NativeChordIpcDisconnected);
                if (entry.disconnected and owner.outputFinished()) {
                    _ = self.entries.remove(id);
                    entry.deinit();
                }
            }
        } else if (entry.disconnected) {
            _ = self.entries.remove(id);
            entry.deinit();
        }
    }
    return worked;
}
