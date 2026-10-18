//! Canonical Socket identity and owned IPC-pipe producer. Ordinary Duplex state
//! remains authoritative; native completions, not ticks, acknowledge ownership.
//! TCP/IPC connection creation is a separate provider, never a fabricated fd.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_node_socket_scope.zig").Scope;
// Actual ordinary callable/constructor: RootBfb producer ownership plus local
// first-ordinary escrow across the complete receiver/temporary cleanup.
const fnc = @import("native_node_socket_function.zig");
const buffer = @import("node_buffer.zig");
pub const maximum_segment = 64 * 1024;
pub const Hooks = struct {
    context: *anyopaque,
    // Owner-thread entry. write must copy before return and acknowledge later;
    // all callbacks may fail synchronously without accepting the operation.
    read: *const fn (*anyopaque) anyerror!void,
    write: *const fn (*anyopaque, []const u8, u64) anyerror!void,
    // Real blocking TTY output uses one whole remaining Buffer call under the
    // console backend's global output lock. No pointer retention, VM entry,
    // completion callback, async token or synthetic nextTick from this hook.
    write_sync: ?*const fn (*anyopaque, []const u8, SyncWriteMetadata) anyerror!SyncWriteResult = null,
    // true is an already-observed native terminal state / synchronous ENOTCONN,
    // false means retain the token for actual later completion. Never infer true
    // merely from a close request, timeout or child exit.
    finish: *const fn (*anyopaque, u64) anyerror!bool,
    destroy: *const fn (*anyopaque, u64) anyerror!bool,
    referenced: *const fn (*anyopaque, bool) anyerror!void,
    // Actual transport owns error/errno/syscall translation. Preserve a captured
    // guest exception rather than coercing it or inventing a generic UV error.
    error_value: *const fn (*anyopaque, *js.Engine, anyerror) anyerror!c.JSValue,
    // Native-only lifetime: abandon retires this endpoint, never kills a child.
    // Retain before attachment; release after abandon, no Engine/JS dereference.
    retain: *const fn (*anyopaque) void,
    abandon: *const fn (*anyopaque) void,
    release: *const fn (*anyopaque) void,
};
// Borrowed only during the same owner-frame native call. Never retain these VM
// values or put them in a worker ticket. Preserve actual string/Buffer identity
// and original encoding for the genuine StreamBase dispatch route/counter.
pub const SyncWriteMetadata = struct { source: c.JSValue, encoding: c.JSValue };
pub const SyncWriteResult = struct {
    acceptedBytes: usize,
    // Source StreamBase counts dispatch independently of confirmed OS output:
    // Buffer and small-string error paths deliberately use different counts.
    dispatchedBytes: usize,
    failure: ?anyerror = null,
};
pub const HandleAdopter = struct {
    brand: c.JSClassID, owner: c.JSValue, context: *anyopaque,
    // Exact ABI: context, Engine, SAME Socket receiver, actual handle, options.
    resolve: *const fn (*anyopaque, *js.Engine, c.JSValue, c.JSValue, c.JSValue) anyerror!Hooks,
};
const Adopters = struct { engine: *js.Engine, entries: [4]?HandleAdopter = .{null} ** 4 };
fn adoptersFinalize(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const self: *Adopters = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    for (self.entries) |entry| if (entry) |value| c.JS_FreeValueRT(runtime, value.owner);
    const engine = self.engine; engine.gpa.destroy(self);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Adopters));
}
fn adoptersMark(runtime: ?*c.JSRuntime, holder: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Adopters = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    for (self.entries) |entry| if (entry) |value| c.JS_MarkValue(runtime, value.owner, visitor);
}
const State = struct {
    engine: *js.Engine, socket: c.JSValue, process: c.JSValue, buffer: c.JSValue, native_handle: c.JSValue,
    hooks: ?Hooks = null, referenced: bool = true, reading: bool = false,
    write_chunk: c.JSValue, write_callback: c.JSValue,
    final_callback: c.JSValue, destroy_callback: c.JSValue, destroy_reason: c.JSValue,
    length: usize = 0, offset: usize = 0, segment_length: usize = 0,
    sequence: u64 = 0, write_token: ?u64 = null, final_token: ?u64 = null, destroy_token: ?u64 = null,
    bytes_read: u64 = 0, bytes_written: u64 = 0, bytes_dispatched: u64 = 0,
    input_finished: bool = false, endpoint_closed: bool = false, destroy_started: bool = false, close_published: bool = false, submitting: bool = false,
    fn set(self: *State, slot: *c.JSValue, value: c.JSValue) void {
        const held = c.JS_DupValue(self.engine.context, value);
        self.engine.freeValue(slot.*); slot.* = held;
    }
    fn next(self: *State) !u64 {
        if (self.sequence == std.math.maxInt(u64)) return error.NativeSocketTokenExhausted;
        self.sequence += 1; return self.sequence;
    }
};
fn finalize(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    // Registered class callback only, never a class selected by a public value.
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    if (state.hooks) |hooks| { hooks.abandon(hooks.context); hooks.release(hooks.context); }
    inline for (.{ "socket", "process", "buffer", "native_handle", "write_chunk", "write_callback", "final_callback", "destroy_callback", "destroy_reason" }) |name| c.JS_FreeValueRT(runtime, @field(state, name));
    const engine = state.engine; engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    inline for (.{ "socket", "process", "buffer", "native_handle", "write_chunk", "write_callback", "final_callback", "destroy_callback", "destroy_reason" }) |name| c.JS_MarkValue(runtime, @field(state, name), visit);
}
fn classId(engine: *js.Engine, value: c.JSValue) !c.JSClassID {
    var id: u32 = 0; if (c.JS_ToUint32(engine.context, &id, value) < 0) return js.capture(engine); return id;
}
fn stateFor(scope: *Scope, socket: c.JSValue, roots: []const c.JSValue) !*State {
    const holder = try scope.invoke(roots[0], "get", &.{socket});
    const id = try classId(scope.engine, roots[1]);
    if (!c.JS_IsObject(holder) or c.JS_GetClassID(holder) != id) return error.NativeSocketIncompatibleReceiver;
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, id) orelse return error.NativeSocketIncompatibleReceiver));
    if (state.engine != scope.engine or !c.JS_IsStrictEqual(scope.engine.context, state.socket, socket)) return error.NativeSocketIncompatibleReceiver;
    return state;
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
fn coded(scope: *Scope, code: []const u8, message: []const u8) !c.JSValue {
    const reason = try scope.construct(try scope.global("Error"), &.{try scope.text(message)});
    try scope.put(reason, "code", try scope.text(code)); return reason;
}
fn bytes(scope: *Scope, value: c.JSValue) ![]const u8 {
    if (c.JS_GetTypedArrayType(value) != c.JS_TYPED_ARRAY_UINT8) return error.NativeSocketRequiresByteChunk;
    var offset: usize = 0; var length: usize = 0; var element: usize = 0;
    const generation = scope.engine.native_allocation_generation;
    const backing = try scope.ownSince(c.JS_GetTypedArrayBuffer(scope.engine.context, value, &offset, &length, &element), generation);
    var total: usize = 0; const data = c.JS_GetArrayBuffer(scope.engine.context, &total, backing);
    if (c.JS_HasException(scope.engine.context)) return js.capture(scope.engine);
    if (offset > total or length > total - offset or (data == null and length != 0)) return error.NativeSocketDetachedBuffer;
    return if (length == 0) &.{} else data[offset .. offset + length];
}
fn writeChunk(scope: *Scope, state: *State, input: c.JSValue, encoding: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(input)) return input;
    // handleWriteReq selects native string bindings for these EXACT switch
    // values. Buffer.from is live only in Source's fallback case (e.g. hex,
    // base64 or noncanonical direct _write encoding), not on ordinary utf8.
    var selected: ?buffer.encodings.Encoding = null;
    if (c.JS_IsString(encoding)) {
        const name = try scope.engine.toString(encoding); defer scope.engine.gpa.free(name);
        if (std.mem.eql(u8, name, "utf8") or std.mem.eql(u8, name, "utf-8")) selected = .utf8
        else if (std.mem.eql(u8, name, "latin1") or std.mem.eql(u8, name, "binary")) selected = .latin1
        else if (std.mem.eql(u8, name, "ascii")) selected = .ascii
        else if (std.mem.eql(u8, name, "ucs2") or std.mem.eql(u8, name, "ucs-2") or std.mem.eql(u8, name, "utf16le") or std.mem.eql(u8, name, "utf-16le")) selected = .utf16le;
    }
    const codec = selected orelse return scope.invoke(state.buffer, "from", &.{input, encoding});
    const text = try scope.engine.toString(input); defer scope.engine.gpa.free(text);
    const encoded = try buffer.encodings.encode(scope.engine.gpa, text, codec); defer scope.engine.gpa.free(encoded);
    return scope.own(try buffer.fromBytes(scope.engine, encoded));
}
const Submission = enum { none, pending, complete };
fn submitWrite(state: *State, metadata: ?SyncWriteMetadata) !Submission {
    const hooks = state.hooks orelse return .none; // Unconnected Socket waits for attach.
    if (state.write_token != null or nullish(state.write_callback)) return .none;
    var scope: Scope = .{ .engine = state.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const current = try bytes(&scope, state.write_chunk);
    if (current.len != state.length or state.offset > current.len) return error.NativeSocketDetachedBuffer;
    if (hooks.write_sync) |write_sync| {
        const remaining = current[state.offset..];
        // The backend owns UTF-8 carry/UTF-16 flushing across the WHOLE call.
        // A maximum_segment cut here could split a code point and release the
        // process-wide console lock between pieces, changing real TTY ordering.
        const result = result: {
            state.submitting = true; defer state.submitting = false;
            break :result try write_sync(hooks.context, remaining, metadata orelse return error.NativeSocketSynchronousMetadataRequired);
        };
        if (result.acceptedBytes > remaining.len) return error.NativeSocketInvalidSynchronousAcknowledgement;
        if (result.dispatchedBytes > remaining.len) return error.NativeSocketInvalidSynchronousDispatch;
        state.offset += result.acceptedBytes;
        state.bytes_written +|= result.acceptedBytes;
        state.bytes_dispatched +|= result.dispatchedBytes;
        if (result.failure) |failure| return failure;
        if (result.acceptedBytes != remaining.len) return error.NativeSocketIncompleteSynchronousAcknowledgement;
        return .complete;
    }
    const count = @min(maximum_segment, current.len - state.offset);
    // Native Hooks MUST copy before return. Actual Driver.beginChunk does so;
    // pending Win32 storage belongs to its retained transport/OVERLAPPED slot.
    // Do not burden every idle/unconnected guest Socket with a64KiB host slab.
    const stable = try state.engine.gpa.dupe(u8, current[state.offset .. state.offset + count]);
    defer state.engine.gpa.free(stable);
    const token = try state.next(); state.write_token = token; state.segment_length = count;
    state.submitting = true; defer state.submitting = false;
    errdefer { state.write_token = null; state.segment_length = 0; }
    try hooks.write(hooks.context, stable, token);
    state.bytes_dispatched +|= count;
    return .pending;
}
fn failureValue(state: *State, failure: anyerror, _: u64) !c.JSValue {
    const engine = state.engine;
    try engine.checkNativeEntry();
    if (failure == error.JavaScriptException) {
        // The failed guest operation's diagnostic is its ordinary thrown DATA.
        // A private tag or retained bit does not turn it into a native event.
        const reason = engine.captured_exception orelse return error.NativeSocketMissingException;
        engine.captured_exception = null;
        return reason;
    }
    if (failure == error.OutOfMemory) return error.OutOfMemory;
    const hooks = state.hooks orelse return error.NativeSocketMissingTransportError;
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const reason = try scope.own(try hooks.error_value(hooks.context, engine, failure));
    return c.JS_DupValue(engine.context, reason);
}
fn settleWrite(state: *State, reason: c.JSValue) !void {
    return settleWriteResult(state, reason, false);
}
fn settleWriteResult(state: *State, reason: c.JSValue, synchronous: bool) !void {
    var scope: Scope = .{ .engine = state.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const callback = try scope.own(c.JS_DupValue(state.engine.context, state.write_callback));
    if (!c.JS_IsFunction(state.engine.context, callback)) return error.NativeSocketWriteAcknowledgementRequired;
    // Retire roots/token BEFORE guest entry; a throwing callback is never
    // repeated and may safely enqueue another write through the real core.
    state.set(&state.write_callback, c.pi_js_undefined()); state.set(&state.write_chunk, c.pi_js_undefined());
    state.write_token = null; state.segment_length = 0;
    _ = try scope.call(callback, c.pi_js_undefined(), if (synchronous and nullish(reason)) &.{} else &.{reason});
}
fn construct(engine: *js.Engine, socket: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const context = captures[0]; const constructor = try scope.get(context, "constructor");
    const instance = c.JS_IsInstanceOf(engine.context, socket, constructor);
    if (instance < 0) return js.capture(engine);
    if (instance == 0) return c.JS_DupValue(engine.context, try scope.construct(constructor, args));
    const duplex = try scope.get(context, "Duplex"); const states = try scope.get(context, "states");
    const known_id = try scope.get(context, "classId"); const process = try scope.get(context, "process"); const buffer_ctor = try scope.get(context, "Buffer");
    const supplied = arg(args, 0);
    if (!nullish(supplied) and !c.JS_IsObject(supplied)) return js.typeError(engine, "Socket options must be an object");
    if (!nullish(supplied)) {
        inline for (.{ "objectMode", "readableObjectMode", "writableObjectMode" }) |name| if (scope.truthy(try scope.get(supplied, name))) return js.typeError(engine, "Socket does not support object mode");
    }
    const options = if (nullish(supplied)) try scope.object() else try scope.own(try js.spread(engine, supplied));
    try scope.put(options, "allowHalfOpen", if (nullish(supplied)) c.pi_js_bool(engine.context, 0) else c.pi_js_bool(engine.context, @intFromBool(scope.truthy(try scope.get(supplied, "allowHalfOpen")))));
    try scope.put(options, "autoDestroy", c.pi_js_bool(engine.context, 1));
    try scope.put(options, "decodeStrings", c.pi_js_bool(engine.context, 0));
    // Socket close(hadError) is published only after the endpoint acknowledgement.
    try scope.put(options, "emitClose", c.pi_js_bool(engine.context, 0));
    _ = try scope.call(duplex, socket, &.{options}); // Initialize THIS Socket.
    const holder = try scope.objectClass(try classId(engine, known_id));
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    var state_attached = false;
    errdefer if (!state_attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .socket = c.JS_DupValue(engine.context, socket), .process = c.JS_DupValue(engine.context, process), .buffer = c.JS_DupValue(engine.context, buffer_ctor), .native_handle = c.pi_js_undefined(), .write_chunk = c.pi_js_undefined(), .write_callback = c.pi_js_undefined(), .final_callback = c.pi_js_undefined(), .destroy_callback = c.pi_js_undefined(), .destroy_reason = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(holder, state); state_attached = true;
    _ = try scope.invoke(states, "set", &.{ socket, holder });
    try scope.put(socket, "connecting", c.pi_js_bool(engine.context, 0));
    const handle = try scope.get(options, "handle");
    if (scope.truthy(handle)) {
        const registration = try scope.get(context, "nativeAdopters");
        const registry: *Adopters = @ptrCast(@alignCast(c.JS_GetOpaque(registration, try classId(engine, captures[1])) orelse return error.NativeSocketAdopterBrand));
        if (registry.engine != engine) return error.NativeSocketAdopterOwner;
        var selected: ?Hooks = null;
        for (registry.entries) |entry| if (entry) |adopter| {
            if (c.JS_GetOpaque(handle, adopter.brand) == null) continue;
            selected = try adopter.resolve(adopter.context, engine, socket, handle, options);
            break;
        };
        const hooks = selected orelse return error.RequiredGenuineNativeSocketHandleAdoption;
        hooks.retain(hooks.context); state.hooks = hooks;
        state.set(&state.native_handle, handle);
        errdefer { state.hooks = null; hooks.abandon(hooks.context); hooks.release(hooks.context); }
        try scope.set(socket, "_handle", handle);
        if (!scope.equal(try scope.get(options, "readable"), c.pi_js_bool(engine.context, 0))) {
            if (scope.truthy(try scope.get(options, "pauseOnCreate"))) _ = try scope.invoke(socket, "pause", &.{})
            else if (!scope.truthy(try scope.get(options, "manualStart"))) _ = try scope.invoke(socket, "read", &.{c.JS_NewInt32(engine.context, 0)});
        }
    } else if (!c.JS_IsUndefined(try scope.get(options, "fd"))) return error.RequiredGenuineNativeSocketFdAdoption;
    return c.JS_DupValue(engine.context, socket);
}
fn read(engine: *js.Engine, socket: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); const state = try stateFor(&scope, socket, roots);
    state.reading = true; if (state.hooks) |hooks| if (!state.endpoint_closed) try hooks.read(hooks.context);
    return c.pi_js_undefined();
}
fn write(engine: *js.Engine, socket: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); const state = try stateFor(&scope, socket, roots);
    if (!nullish(state.write_callback)) return error.NativeSocketWriteAlreadyPending;
    const input = arg(args, 0); const callback = arg(args, 2);
    if (!c.JS_IsFunction(engine.context, callback)) return js.typeError(engine, "Socket write callback must be a function");
    if (state.hooks == null or state.endpoint_closed or state.input_finished) return js.call(engine, callback, c.pi_js_undefined(), &.{try coded(&scope, "ERR_SOCKET_CLOSED", "Socket is closed")});
    const chunk = try writeChunk(&scope, state, input, arg(args, 1));
    state.length = (try bytes(&scope, chunk)).len; state.offset = 0;
    state.set(&state.write_chunk, chunk); state.set(&state.write_callback, callback);
    const generation = engine.native_allocation_generation;
    const submitted = submitWrite(state, .{ .source = input, .encoding = arg(args, 1) }) catch |err| {
        const reason = try scope.own(try failureValue(state, err, generation));
        try settleWrite(state, reason);
        return c.pi_js_undefined();
    };
    // Outside the native-failure catch: a throwing guest completion already
    // owns its terminal call and must never be mapped/repeated as another write.
    if (submitted == .complete) try settleWriteResult(state, c.pi_js_null(), true);
    return c.pi_js_undefined();
}
fn final(engine: *js.Engine, socket: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); const state = try stateFor(&scope, socket, roots);
    const callback = arg(args, 0); if (!c.JS_IsFunction(engine.context, callback)) return js.typeError(engine, "Socket final callback must be a function");
    if (!nullish(state.final_callback)) return error.NativeSocketFinalAlreadyPending;
    const hooks = state.hooks orelse return js.call(engine, callback, c.pi_js_undefined(), &.{});
    const token = try state.next(); state.final_token = token; state.set(&state.final_callback, callback);
    state.submitting = true; defer state.submitting = false;
    errdefer { state.final_token = null; state.set(&state.final_callback, c.pi_js_undefined()); }
    if (try hooks.finish(hooks.context, token)) {
        state.final_token = null; state.input_finished = true;
        state.set(&state.final_callback, c.pi_js_undefined());
        _ = try scope.call(callback, c.pi_js_undefined(), &.{});
    }
    return c.pi_js_undefined();
}
fn closeTick(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return js.invoke(engine, roots[0], "emit", &.{ roots[1], roots[2] }); }
fn publishClosed(state: *State, reason: c.JSValue) !void {
    var scope: Scope = .{ .engine = state.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    if (state.close_published) return error.NativeSocketDuplicateClose;
    state.destroy_token = null; state.endpoint_closed = true; state.close_published = true;
    const had_error = !nullish(reason);
    const tick = try scope.own(try fnc.createArrow(state.engine, "", 0, closeTick, &.{ state.socket, try scope.text("close"), c.pi_js_bool(state.engine.context, @intFromBool(had_error)) }));
    _ = try scope.invoke(state.process, "nextTick", &.{tick});
}
fn destroy(engine: *js.Engine, socket: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); const state = try stateFor(&scope, socket, roots);
    if (state.destroy_started) return error.NativeSocketDestroyAlreadyPending;
    const callback = arg(args, 1); if (!c.JS_IsFunction(engine.context, callback)) return js.typeError(engine, "Socket destroy callback must be a function");
    state.destroy_started = true;
    state.set(&state.destroy_reason, arg(args, 0)); state.set(&state.destroy_callback, callback);
    var acknowledged = state.hooks == null;
    if (state.hooks) |hooks| {
        const token = try state.next(); state.destroy_token = token;
        state.submitting = true; defer state.submitting = false;
        errdefer { state.destroy_token = null; state.set(&state.destroy_callback, c.pi_js_undefined()); }
        acknowledged = try hooks.destroy(hooks.context, token);
    }
    // Source Socket completes stream destruction independently of actual native
    // close. The latter owns the single close(hadError), never the generic core.
    state.set(&state.destroy_callback, c.pi_js_undefined());
    _ = try scope.call(callback, c.pi_js_undefined(), &.{state.destroy_reason});
    if (acknowledged) try publishClosed(state, state.destroy_reason);
    return c.pi_js_undefined();
}
fn reference(engine: *js.Engine, socket: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); const state = try stateFor(&scope, socket, roots);
    const value = c.JS_ToBool(engine.context, roots[2]) == 1;
    if (state.hooks == null or state.destroy_started or state.endpoint_closed) {
        // Source registers the live public method for a future real connect;
        // retained context entitlement does not authorize touching a dead pipe.
        const once = try scope.get(socket, "once");
        const method = try scope.get(socket, if (value) "ref" else "unref");
        _ = try scope.call(once, socket, &.{ try scope.text("connect"), method });
        return c.JS_DupValue(engine.context, socket);
    }
    const hooks = state.hooks.?;
    try hooks.referenced(hooks.context, value);
    state.referenced = value; return c.JS_DupValue(engine.context, socket);
}
fn property(engine: *js.Engine, socket: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); const state = try stateFor(&scope, socket, roots);
    var which: i32 = 0; if (c.JS_ToInt32(engine.context, &which, roots[2]) < 0) return js.capture(engine);
    return switch (which) {
        0 => c.JS_NewFloat64(engine.context, @floatFromInt(state.bytes_read)),
        1 => writtenBytes(&scope, state),
        2 => if (state.hooks == null or state.destroy_started) c.pi_js_undefined() else c.JS_DupValue(engine.context, try scope.get(socket, "writableLength")),
        3 => c.pi_js_bool(engine.context, @intFromBool(state.hooks == null or state.destroy_started or scope.truthy(try scope.get(socket, "connecting")))),
        4 => c.JS_DupValue(engine.context, try scope.text(if (scope.truthy(try scope.get(socket, "connecting"))) "opening" else if (scope.truthy(try scope.get(socket, "readable"))) (if (scope.truthy(try scope.get(socket, "writable"))) "open" else "readOnly") else if (scope.truthy(try scope.get(socket, "writable"))) "writeOnly" else "closed")),
        else => c.JS_NewFloat64(engine.context, @floatFromInt(state.bytes_dispatched)),
    };
}
fn writtenBytes(scope: *Scope, state: *State) !c.JSValue {
    // Source reads the genuine Writable queue; this accessor deliberately does
    // not invent a parallel guest-visible queue or substitute character counts.
    const queued = try scope.get(state.socket, "writableBuffer");
    if (nullish(queued)) return c.pi_js_undefined();
    const unsent = if (!nullish(state.write_callback)) state.length - state.offset - state.segment_length else 0;
    var total = @as(f64, @floatFromInt(state.bytes_dispatched)) + @as(f64, @floatFromInt(unsent));
    var index: u32 = 0;
    while (true) : (index += 1) {
        var length: u32 = 0; if (c.JS_ToUint32(scope.engine.context, &length, try scope.get(queued, "length")) < 0) return js.capture(scope.engine);
        if (index >= length) break;
        const item = try scope.getIndex(queued, index);
        const chunk = try scope.get(item, "chunk"); const is_buffer = c.JS_IsInstanceOf(scope.engine.context, chunk, state.buffer);
        if (is_buffer < 0) return js.capture(scope.engine);
        const size = if (is_buffer == 1) try scope.get(chunk, "length") else try scope.invoke(state.buffer, "byteLength", &.{ chunk, try scope.get(item, "encoding") });
        var count: f64 = 0; if (c.JS_ToFloat64(scope.engine.context, &count, size) < 0) return js.capture(scope.engine); total += count;
    }
    return c.JS_NewFloat64(scope.engine.context, total);
}
/// Actual constructor/provider bundle. It is intentionally uninstalled until
/// native endpoint assembly and qualification are complete; not a node:net shim.
pub const Provider = struct {
    engine: *js.Engine, constructor: c.JSValue, states: c.JSValue, id: c.JSClassID,
    adopters: *Adopters,
    /// Shares the genuine constructor, opaque state brand and native adopter
    /// registry. TTY and child pipes must not manufacture competing net classes.
    pub fn clone(self: *const Provider, engine: *js.Engine) !Provider {
        if (self.engine != engine or self.adopters.engine != engine) return error.NativeSocketAdopterOwner;
        var result = self.*;
        result.constructor = c.JS_DupValue(engine.context, self.constructor);
        result.states = c.JS_DupValue(engine.context, self.states);
        return result;
    }
    /// Native composition only. owner must keep the actual context valid and
    /// resolve must validate owning Engine/canonical handle before state access.
    pub fn addHandleAdopter(self: *Provider, adopter: HandleAdopter) !void {
        if (self.adopters.engine != self.engine or adopter.brand == 0 or !c.JS_IsObject(adopter.owner)) return error.NativeSocketAdopterOwner;
        for (self.adopters.entries) |entry| if (entry) |value| { if (value.brand == adopter.brand) return error.NativeSocketAdopterAlreadyRegistered; };
        for (&self.adopters.entries) |*entry| if (entry.* == null) {
            var actual = adopter; actual.owner = c.JS_DupValue(self.engine.context, adopter.owner); entry.* = actual; return;
        };
        return error.NativeSocketAdopterCapacity;
    }
    pub fn deinit(self: *Provider) void { self.engine.freeValue(self.constructor); self.engine.freeValue(self.states); }
    pub fn createFromHandle(self: *Provider, options: c.JSValue) !Owned {
        const arguments = [_]c.JSValue{options};
        const actual = try self.engine.checked(c.JS_Call(self.engine.context, self.constructor, c.pi_js_undefined(), 1, &arguments));
        defer self.engine.freeValue(actual); return self.own(actual);
    }
    pub fn own(self: *Provider, actual: c.JSValue) !Owned {
        var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        const holder = try scope.invoke(self.states, "get", &.{actual});
        const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, self.id) orelse return error.NativeSocketMissingState));
        if (state.engine != self.engine or !scope.equal(state.socket, actual)) return error.NativeSocketIncompatibleReceiver;
        return .{ .engine = self.engine, .socket = c.JS_DupValue(self.engine.context, actual), .holder = c.JS_DupValue(self.engine.context, holder), .state = state };
    }
    pub fn createOwned(self: *Provider, options: c.JSValue, hooks: Hooks) !Owned {
        var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        var arguments = [_]c.JSValue{options};
        const socket = try scope.construct(self.constructor, &arguments);
        const holder = try scope.invoke(self.states, "get", &.{socket});
        const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, self.id) orelse return error.NativeSocketMissingState));
        if (state.engine != self.engine or !c.JS_IsStrictEqual(self.engine.context, state.socket, socket)) return error.NativeSocketIncompatibleReceiver;
        if (state.hooks != null) return error.NativeSocketHandleAlreadyAdopted;
        hooks.retain(hooks.context); state.hooks = hooks;
        errdefer {
            state.hooks = null;
            // read(0)/pause/options may have started real demand before a guest
            // throw. Failed construction retains native rollback entitlement.
            hooks.abandon(hooks.context); hooks.release(hooks.context);
        }
        if (!scope.equal(try scope.get(options, "readable"), c.pi_js_bool(self.engine.context, 0))) {
            if (scope.truthy(try scope.get(options, "pauseOnCreate"))) _ = try scope.invoke(socket, "pause", &.{}) else if (!scope.truthy(try scope.get(options, "manualStart"))) _ = try scope.invoke(socket, "read", &.{c.JS_NewInt32(self.engine.context, 0)});
        }
        return .{ .engine = self.engine, .socket = c.JS_DupValue(self.engine.context, socket), .holder = c.JS_DupValue(self.engine.context, holder), .state = state };
    }
};
pub const Owned = struct {
    engine: *js.Engine, socket: c.JSValue, holder: c.JSValue, state: *State,
    pub fn clone(self: *const Owned) Owned { return .{ .engine = self.engine, .socket = c.JS_DupValue(self.engine.context, self.socket), .holder = c.JS_DupValue(self.engine.context, self.holder), .state = self.state }; }
    pub fn deinit(self: *Owned) void { self.engine.freeValue(self.socket); self.engine.freeValue(self.holder); self.* = undefined; }
    pub fn push(self: *Owned, data: []const u8) !bool {
        var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        const copied = try scope.own(try buffer.fromBytes(self.engine, data));
        self.state.bytes_read +|= data.len;
        const accepted = scope.truthy(try scope.invoke(self.socket, "push", &.{copied})); self.state.reading = accepted; return accepted;
    }
    pub fn eof(self: *Owned) !void { var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); _ = try scope.invoke(self.socket, "push", &.{c.pi_js_null()}); }
    pub fn completeWrite(self: *Owned, token: u64, accepted: usize, reason: c.JSValue) !void {
        const state = self.state;
        if (state.submitting) return error.NativeSocketInlineCompletion;
        if (state.write_token != token or accepted > state.segment_length) return error.NativeSocketStaleCompletion;
        if (nullish(reason) and accepted != state.segment_length) return error.NativeSocketIncompleteAcknowledgement;
        state.write_token = null; state.offset += accepted; state.bytes_written +|= accepted; state.segment_length = 0;
        if (nullish(reason) and state.offset < state.length) {
            const generation = self.engine.native_allocation_generation;
            const submitted = submitWrite(state, null) catch |err| {
                var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
                const failure = try scope.own(try failureValue(state, err, generation));
                try settleWrite(state, failure);
                return;
            };
            if (submitted == .complete) try settleWriteResult(state, c.pi_js_null(), true);
            return;
        }
        try settleWrite(state, reason);
    }
    pub fn completeFinal(self: *Owned, token: u64, reason: c.JSValue) !void {
        const state = self.state;
        if (state.submitting) return error.NativeSocketInlineCompletion;
        if (state.final_token != token) return error.NativeSocketStaleCompletion;
        state.final_token = null; state.input_finished = nullish(reason);
        var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        const callback = try scope.own(c.JS_DupValue(self.engine.context, state.final_callback)); state.set(&state.final_callback, c.pi_js_undefined());
        _ = try scope.call(callback, c.pi_js_undefined(), if (nullish(reason)) &.{} else &.{reason});
    }
    pub fn completeDestroy(self: *Owned, token: u64, reason: c.JSValue) !void {
        const state = self.state;
        if (state.submitting) return error.NativeSocketInlineCompletion;
        if (state.destroy_token != token) return error.NativeSocketStaleCompletion;
        if (state.write_token != null or state.final_token != null) return error.NativeSocketOutstandingAcknowledgement;
        // Source captured isException when _destroy began. Late native cleanup
        // diagnostics cannot retroactively replace that already-delivered reason.
        _ = reason;
        try publishClosed(state, state.destroy_reason);
    }
};
pub fn createProvider(engine: *js.Engine, actual_streams: c.JSValue, actual_process: c.JSValue) !Provider {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    try buffer.install(engine);
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Owned native Socket endpoint", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const states = try scope.construct(try scope.global("WeakMap"), &.{});
    const known_id = c.JS_NewUint32(engine.context, id);
    var adopter_id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &adopter_id);
    const adopter_definition: c.JSClassDef = .{ .class_name = "Native Socket handle admission", .finalizer = adoptersFinalize, .gc_mark = adoptersMark };
    if (c.JS_NewClass(engine.runtime, adopter_id, &adopter_definition) < 0) return error.OutOfMemory;
    const adopter_holder = try scope.objectClass(adopter_id);
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Adopters)) == 0) return error.OutOfMemory;
    var adopters_attached = false;
    errdefer if (!adopters_attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Adopters));
    const adopters = try engine.gpa.create(Adopters); adopters.* = .{ .engine = engine };
    _ = c.JS_SetOpaque(adopter_holder, adopters); adopters_attached = true;
    const duplex = try scope.get(actual_streams, "Duplex"); const prototype = try scope.object();
    if (c.JS_SetPrototype(engine.context, prototype, try scope.get(duplex, "prototype")) < 0) return @as(anyerror!Provider, js.capture(engine));
    const context = try scope.object();
    try scope.put(context, "nativeAdopters", adopter_holder);
    try scope.put(context, "Duplex", duplex); try scope.put(context, "states", states); try scope.put(context, "classId", known_id); try scope.put(context, "process", actual_process);
    try scope.put(context, "Buffer", try scope.get(engine.native_module_values.get("node:buffer").?, "Buffer"));
    const constructor = try scope.own(try fnc.create(engine, "Socket", 1, construct, &.{ context, c.JS_NewUint32(engine.context, adopter_id) }));
    try scope.put(context, "constructor", constructor);
    try scope.set(constructor, "prototype", prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return @as(anyerror!Provider, js.capture(engine));
    if (c.JS_SetPrototype(engine.context, constructor, duplex) < 0) return @as(anyerror!Provider, js.capture(engine));
    // Source assigns anonymous ordinary function expressions to these members;
    // property assignment does not infer a function name from its member key.
    inline for (.{ "_read", "_write", "_final", "_destroy" }, .{ read, write, final, destroy }, .{ 1, 3, 1, 2 }) |name, callback, length| try scope.put(prototype, name, try scope.own(try fnc.create(engine, "", length, callback, &.{ states, known_id })));
    inline for (.{ "ref", "unref" }, .{ true, false }) |name, value| try scope.put(prototype, name, try scope.own(try fnc.create(engine, "", 0, reference, &.{ states, known_id, c.pi_js_bool(engine.context, @intFromBool(value)) })));
    inline for (.{ "bytesRead", "bytesWritten", "bufferSize", "pending", "readyState", "_bytesDispatched" }, 0..) |name, index| {
        const getter_name = if (index == 2 or index == 3 or index == 4) "get" else name;
        const getter = try scope.own(if (index == 3) try fnc.createMethod(engine, getter_name, 0, property, &.{ states, known_id, c.JS_NewInt32(engine.context, index) }) else try fnc.create(engine, getter_name, 0, property, &.{ states, known_id, c.JS_NewInt32(engine.context, index) }));
        const atom = c.JS_NewAtom(engine.context, name); defer c.JS_FreeAtom(engine.context, atom);
        const flags = if (index == 3) c.JS_PROP_CONFIGURABLE else if (index == 0 or index == 1 or index == 5) c.JS_PROP_ENUMERABLE else 0;
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), flags) < 0) return @as(anyerror!Provider, js.capture(engine));
    }
    return .{ .engine = engine, .constructor = c.JS_DupValue(engine.context, constructor), .states = c.JS_DupValue(engine.context, states), .id = id, .adopters = adopters };
}

test "Socket actual callable provider retains new captured fatal over success and subsequent real GPA failure" {
    const Fixture = struct {
        fn callback(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            if (c.JS_ToBool(engine.context, roots[1]) == 0) return c.pi_js_undefined();
            _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, roots[0]))) catch {};
            if (c.JS_ToBool(engine.context, roots[2]) == 1) {
                const actual = try engine.gpa.alloc(u8, 1); defer engine.gpa.free(actual);
            }
            return c.pi_js_undefined();
        }
    };
    inline for (.{ false, true }) |real_gpa_failure| {
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try js.Engine.init(allocator.allocator(), .{}); defer engine.deinit();
        const history = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(history);
        const current = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(current);
        c.JS_SetUncatchableError(engine.context, history); c.JS_SetUncatchableError(engine.context, current);
        const plain = try fnc.create(engine, "socketOldHistoryControl", 0, Fixture.callback, &.{ history, c.pi_js_bool(engine.context, 0), c.pi_js_bool(engine.context, 0) }); defer engine.freeValue(plain);
        engine.captured_exception = c.JS_DupValue(engine.context, history);
        const ignored_history = c.JS_Call(engine.context, plain, c.pi_js_undefined(), 0, null); defer engine.freeValue(ignored_history);
        try std.testing.expect(c.JS_IsUndefined(ignored_history) and !c.JS_HasException(engine.context));
        // Same producer used by actual Socket constructor/method creation.
        const function = try fnc.create(engine, "socketCurrentProducerControl", 0, Fixture.callback, &.{ current, c.pi_js_bool(engine.context, 1), c.pi_js_bool(engine.context, @intFromBool(real_gpa_failure)) }); defer engine.freeValue(function);
        const generation = engine.native_allocation_generation;
        if (real_gpa_failure) allocator.fail_index = allocator.alloc_index;
        const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null); defer engine.freeValue(result);
        allocator.fail_index = std.math.maxInt(usize);
        if (real_gpa_failure) try std.testing.expect(allocator.has_induced_failure);
        try std.testing.expect(c.JS_IsException(result));
        const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, current));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expectEqual(generation, engine.native_allocation_generation);
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
