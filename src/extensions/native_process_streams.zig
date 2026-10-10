//! Owner-thread terminal streams for Source ProcessTerminal. These adapters
//! never read the worker's framed stdin or write to its framed stdout.
//! The authenticated parent frontend supplies input, resize and output sinks.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub const Output = enum { stdout, stderr };
pub const Control = union(enum) { raw_mode: bool, @"resume", pause, encoding: []const u8 };
pub const Bridge = struct {
    context: ?*anyopaque,
    guard_fn: *const fn (?*anyopaque) anyerror!void,
    /// Encoding and byte slices are borrowed only for the callback duration.
    control_fn: *const fn (?*anyopaque, Control) anyerror!void,
    write_fn: *const fn (?*anyopaque, Output, []const u8) anyerror!void,
    is_shift_pressed_fn: ?*const fn (?*anyopaque) anyerror!bool = null,
    enable_vt_input_fn: ?*const fn (?*anyopaque) anyerror!bool = null,
};
pub const Lease = struct { context: ?*anyopaque, generation: u64 };
const State = struct { engine: *js.Engine, bridge: ?Bridge = null, generation: u64 = 0, input: c.JSValue, output: c.JSValue, errors: c.JSValue, raw_method: c.JSValue, paused: bool = true, explicitly_paused: bool = false, utf8: bool = false, resume_scheduled: bool = false, pending: std.ArrayList(u8) = .empty };
const private_module = "#pi-native-process-terminal-streams";
const Method = enum(c_int) { setRawMode, setEncoding, @"resume", pause, isPaused, writeOutput, writeErrors };
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ "input", "output", "errors", "raw_method" }) |name| c.JS_FreeValueRT(runtime, @field(owned, name));
    owned.pending.deinit(owned.engine.gpa);
    owned.engine.gpa.destroy(owned);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ "input", "output", "errors", "raw_method" }) |name| c.JS_MarkValue(runtime, @field(owned, name), marker);
}
fn state(engine: *js.Engine) !*State {
    const holder = engine.native_module_values.get(private_module) orelse return error.NativeTerminalStreamsUnavailable;
    return @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)).?));
}
fn checkBridge(owned: *State) !Bridge {
    const bridge = owned.bridge orelse return error.NativeTerminalStreamsNotBound;
    try bridge.guard_fn(bridge.context);
    return bridge;
}
pub fn bind(engine: *js.Engine, bridge: Bridge) !Lease {
    try bridge.guard_fn(bridge.context);
    const owned = try state(engine);
    owned.generation = try std.math.add(u64, owned.generation, 1);
    if (owned.bridge != null) {
        owned.pending.clearRetainingCapacity();
        owned.paused = true;
        owned.explicitly_paused = false;
        owned.resume_scheduled = false;
    }
    owned.bridge = bridge;
    return .{ .context = bridge.context, .generation = owned.generation };
}
/// Retired frontend generations cannot detach a newer frontend's stream sink.
pub fn unbind(engine: *js.Engine, lease: Lease) bool {
    const owned = state(engine) catch return false;
    const bridge = owned.bridge orelse return false;
    if (bridge.context != lease.context or owned.generation != lease.generation) return false;
    owned.bridge = null;
    owned.pending.clearRetainingCapacity();
    owned.paused = true;
    owned.explicitly_paused = false;
    owned.resume_scheduled = false;
    return true;
}
pub fn hydrateDimensions(engine: *js.Engine, columns: u32, rows: u32) !void {
    const owned = try state(engine);
    try v.set(engine, owned.output, "columns", c.JS_NewUint32(engine.context, columns));
    try v.set(engine, owned.output, "rows", c.JS_NewUint32(engine.context, rows));
}
pub fn hydrateInput(engine: *js.Engine, is_raw: bool, is_tty: bool) !void {
    const owned = try state(engine);
    if (is_tty) {
        try js.define(engine, owned.input, "setRawMode", c.JS_DupValue(engine.context, owned.raw_method));
        try v.set(engine, owned.input, "isRaw", c.pi_js_bool(engine.context, @intFromBool(is_raw)));
        try v.set(engine, owned.input, "isTTY", c.pi_js_bool(engine.context, 1));
    } else {
        inline for (.{ "setRawMode", "isRaw", "isTTY" }) |name| try removeProperty(engine, owned.input, name);
    }
}
fn removeProperty(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8) !void {
    const atom = c.JS_NewAtom(engine.context, name);
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, object, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
}
/// Pipe output has unavailable dimensions and no isTTY property. Zero console
/// dimensions remain zero; ProcessTerminal applies its own Source fallback.
pub fn hydrateOutput(engine: *js.Engine, stdout_tty: bool, stderr_tty: bool, columns: ?u32, rows: ?u32) !void {
    const owned = try state(engine);
    if (stdout_tty) try v.set(engine, owned.output, "isTTY", c.pi_js_bool(engine.context, 1)) else try removeProperty(engine, owned.output, "isTTY");
    if (stderr_tty) try v.set(engine, owned.errors, "isTTY", c.pi_js_bool(engine.context, 1)) else try removeProperty(engine, owned.errors, "isTTY");
    if (columns) |value| try v.set(engine, owned.output, "columns", c.JS_NewUint32(engine.context, value)) else try removeProperty(engine, owned.output, "columns");
    if (rows) |value| try v.set(engine, owned.output, "rows", c.JS_NewUint32(engine.context, value)) else try removeProperty(engine, owned.output, "rows");
}
pub fn isShiftPressed(engine: *js.Engine) !bool {
    const bridge = try checkBridge(try state(engine));
    const query = bridge.is_shift_pressed_fn orelse return false;
    return query(bridge.context);
}
pub fn enableVirtualTerminalInput(engine: *js.Engine) !bool {
    const bridge = try checkBridge(try state(engine));
    const enable = bridge.enable_vt_input_fn orelse return false;
    return enable(bridge.context);
}
pub fn deliverResize(engine: *js.Engine, columns: u32, rows: u32) !void {
    const owned = try state(engine);
    _ = try checkBridge(owned);
    try hydrateDimensions(engine, columns, rows);
    const event = try v.text(engine, "resize");
    defer engine.freeValue(event);
    const returned = try js.invoke(engine, owned.output, "emit", &.{event});
    engine.freeValue(returned);
}
fn emitInput(owned: *State) !void {
    const engine = owned.engine;
    if (owned.paused or owned.resume_scheduled or owned.pending.items.len == 0) return;
    // Keep an incomplete UTF8 suffix until the next authenticated input frame,
    // as a real stdin.setEncoding('utf8') decoder does across read boundaries.
    var count = owned.pending.items.len;
    if (owned.utf8) {
        var cursor = count;
        while (cursor > 0 and count - cursor < 3 and owned.pending.items[cursor - 1] & 0xc0 == 0x80) cursor -= 1;
        if (cursor > 0) {
            const start = cursor - 1;
            const first = owned.pending.items[start];
            const needed: usize = if (first >= 0xc2 and first <= 0xdf) 2 else if (first >= 0xe0 and first <= 0xef) 3 else if (first >= 0xf0 and first <= 0xf4) 4 else 1;
            if (count - start < needed) count = start;
        }
    }
    if (count == 0) return;
    const value = if (owned.utf8) try engine.checked(c.JS_NewStringLen(engine.context, owned.pending.items.ptr, count)) else blk: {
        break :blk try @import("node_buffer.zig").fromBytes(engine, owned.pending.items[0..count]);
    };
    defer engine.freeValue(value);
    // Consume before emitting so listener reentry can safely append input.
    std.mem.copyForwards(u8, owned.pending.items[0 .. owned.pending.items.len - count], owned.pending.items[count..]);
    owned.pending.items.len -= count;
    const event = try v.text(engine, "data");
    defer engine.freeValue(event);
    const returned = try js.invoke(engine, owned.input, "emit", &.{ event, value });
    engine.freeValue(returned);
}
pub fn deliverInput(engine: *js.Engine, bytes: []const u8) !void {
    const owned = try state(engine);
    _ = try checkBridge(owned);
    if (bytes.len > 1024 * 1024 or owned.pending.items.len > 1024 * 1024 - bytes.len) return error.NativeTerminalInputQueueLimit;
    try owned.pending.appendSlice(engine.gpa, bytes);
    try emitInput(owned);
}
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native terminal stream: %s", @as([*:0]const u8, @errorName(err)));
}
fn call(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], c.JS_GetClassID(data[0])).?));
    return operation(owned, receiver, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
fn resumed(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(data[0], c.JS_GetClassID(data[0])).?));
    var queued_generation: u64 = 0;
    if (c.JS_ToBigUint64(context, &queued_generation, data[1]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    if (owned.generation != queued_generation) return c.pi_js_undefined();
    owned.resume_scheduled = false;
    _ = checkBridge(owned) catch return c.pi_js_undefined();
    emitInput(owned) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn operation(owned: *State, receiver: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const engine = owned.engine;
    if (method == .isPaused) return c.pi_js_bool(engine.context, @intFromBool(owned.explicitly_paused));
    const bridge = try checkBridge(owned);
    switch (method) {
        .setRawMode => {
            const enabled = v.truthy(engine, v.arg(args, 0));
            try bridge.control_fn(bridge.context, .{ .raw_mode = enabled });
            try v.set(engine, owned.input, "isRaw", c.pi_js_bool(engine.context, @intFromBool(enabled)));
        },
        .setEncoding => {
            const encoding = if (c.JS_IsUndefined(v.arg(args, 0))) try engine.gpa.dupe(u8, "utf8") else try engine.toString(v.arg(args, 0));
            defer engine.gpa.free(encoding);
            if (!std.ascii.eqlIgnoreCase(encoding, "utf8") and !std.ascii.eqlIgnoreCase(encoding, "utf-8")) return error.NativeTerminalEncodingUnsupported;
            try bridge.control_fn(bridge.context, .{ .encoding = encoding });
            owned.utf8 = true;
        },
        .@"resume" => {
            try bridge.control_fn(bridge.context, .@"resume");
            owned.paused = false;
            owned.explicitly_paused = false;
            if (!owned.resume_scheduled) {
                const holder = engine.native_module_values.get(private_module).?;
                const generation = try engine.checked(c.JS_NewBigUint64(engine.context, owned.generation));
                defer engine.freeValue(generation);
                var data = [_]c.JSValue{ holder, generation };
                const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, resumed, "resume_", 0, 0, 2, &data));
                defer engine.freeValue(callback);
                const process = try js.global(engine, "process");
                defer engine.freeValue(process);
                const returned = try js.invoke(engine, process, "nextTick", &.{callback});
                engine.freeValue(returned);
                owned.resume_scheduled = true;
            }
        },
        .pause => {
            try bridge.control_fn(bridge.context, .pause);
            owned.paused = true;
            owned.explicitly_paused = true;
        },
        .writeOutput, .writeErrors => {
            const value = v.arg(args, 0);
            const bytes = try outputBytes(engine, value);
            defer engine.gpa.free(bytes);
            try bridge.write_fn(bridge.context, if (method == .writeOutput) .stdout else .stderr, bytes);
            const callback = if (c.JS_IsFunction(engine.context, v.arg(args, 1))) v.arg(args, 1) else v.arg(args, 2);
            if (c.JS_IsFunction(engine.context, callback)) {
                const process = try js.global(engine, "process");
                defer engine.freeValue(process);
                const returned = try js.invoke(engine, process, "nextTick", &.{callback});
                engine.freeValue(returned);
            }
            return c.pi_js_bool(engine.context, 1);
        },
        .isPaused => unreachable,
    }
    return c.JS_DupValue(engine.context, receiver);
}
pub fn outputBytes(engine: *js.Engine, value: c.JSValue) ![]u8 {
    if (c.JS_GetTypedArrayType(value) == c.JS_TYPED_ARRAY_UINT8) {
        var offset: usize = 0;
        var length: usize = 0;
        var element: usize = 0;
        const backing = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, value, &offset, &length, &element));
        defer engine.freeValue(backing);
        var total: usize = 0;
        const pointer = c.JS_GetArrayBuffer(engine.context, &total, backing);
        if ((pointer == null and length > 0) or offset > total or length > total - offset) return error.NativeTerminalDetachedBuffer;
        return engine.gpa.dupe(u8, if (length == 0) &.{} else pointer[offset .. offset + length]);
    }
    if (!c.JS_IsString(value)) return js.typeError(engine, "Terminal output must be a string or Buffer");
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    return @import("binary_encoding.zig").encode(engine.gpa, text, .utf8);
}
fn makeMethod(engine: *js.Engine, holder: c.JSValue, name: [*:0]const u8, length: c_int, operation_value: Method) !c.JSValue {
    var data = [_]c.JSValue{holder};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, call, name, length, @intFromEnum(operation_value), 1, &data));
}
fn inputOn(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(values[0], c.JS_GetClassID(values[0])).?));
    const returned = try js.call(engine, values[1], receiver, args);
    errdefer engine.freeValue(returned);
    const data = try v.text(engine, "data");
    defer engine.freeValue(data);
    if (c.JS_IsStrictEqual(engine.context, v.arg(args, 0), data) and !owned.explicitly_paused) {
        // Node Readable.on('data') starts flow on the next tick and still calls
        // the public resume method when the stream is already flowing.
        const resumed_value = try js.invoke(engine, receiver, "resume", &.{});
        engine.freeValue(resumed_value);
    }
    return returned;
}
pub fn install(engine: *js.Engine, process: c.JSValue) !void {
    if (engine.native_module_values.contains(private_module)) return;
    try @import("node_events.zig").install(engine);
    try @import("node_buffer.zig").install(engine);
    const event_exports = engine.native_module_values.get("node:events").?;
    const emitter = try js.get(engine, event_exports, "EventEmitter");
    defer engine.freeValue(emitter);
    const input = try engine.checked(c.JS_CallConstructor(engine.context, emitter, 0, null));
    defer engine.freeValue(input);
    const output = try engine.checked(c.JS_CallConstructor(engine.context, emitter, 0, null));
    defer engine.freeValue(output);
    const errors = try engine.checked(c.JS_CallConstructor(engine.context, emitter, 0, null));
    defer engine.freeValue(errors);
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native private terminal stream binding", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const holder = try engine.checked(c.JS_NewObjectClass(engine.context, class));
    defer engine.freeValue(holder);
    const owned = try engine.gpa.create(State);
    owned.* = .{ .engine = engine, .input = c.JS_DupValue(engine.context, input), .output = c.JS_DupValue(engine.context, output), .errors = c.JS_DupValue(engine.context, errors), .raw_method = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(holder, owned);
    inline for (.{ .{ "setRawMode", 1, Method.setRawMode }, .{ "setEncoding", 1, Method.setEncoding }, .{ "resume", 0, Method.@"resume" }, .{ "pause", 0, Method.pause }, .{ "isPaused", 0, Method.isPaused } }) |entry| try js.define(engine, input, entry[0], try makeMethod(engine, holder, entry[0], entry[1], entry[2]));
    owned.raw_method = try js.get(engine, input, "setRawMode");
    const emitter_on = try js.get(engine, input, "on");
    defer engine.freeValue(emitter_on);
    const on = try @import("native_node_function.zig").create(engine, "on", 2, inputOn, &.{ holder, emitter_on });
    defer engine.freeValue(on);
    try js.define(engine, input, "on", c.JS_DupValue(engine.context, on));
    try js.define(engine, input, "addListener", c.JS_DupValue(engine.context, on));
    try js.define(engine, input, "isRaw", c.pi_js_bool(engine.context, 0));
    try js.define(engine, output, "write", try makeMethod(engine, holder, "write", 3, .writeOutput));
    try js.define(engine, errors, "write", try makeMethod(engine, holder, "write", 3, .writeErrors));
    try js.define(engine, process, "stdin", c.JS_DupValue(engine.context, input));
    try js.define(engine, process, "stdout", c.JS_DupValue(engine.context, output));
    try js.define(engine, process, "stderr", c.JS_DupValue(engine.context, errors));
    try engine.registerValueModule(private_module, holder);
}
