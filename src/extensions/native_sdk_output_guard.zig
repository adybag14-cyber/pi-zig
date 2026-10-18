//! Exact c268 output-guard bodies over the actual frontend stream lease.
//! Ordinary takeover/write exports and genuine async retry/backpressure/flush
//! share one retained Source module state. No caller-supplied queue is used.
const std = @import("std");
const v = @import("native_public_values.zig");
const c = v.c;
const em = v.em;
const Scope = v.Scope;
const af = v.af;
const streams = @import("native_process_streams.zig");
const caught = @import("native_agent_af_values.zig").caught;
const key = "\x00native.sdk.stdout-takeover-owner";
const Entry = struct { engine: *em.Engine, previous: ?*Entry };
threadlocal var initializing: ?*Entry = null;

pub const Exports = struct {
    take_over_stdout: c.JSValue,
    restore_stdout: c.JSValue,
    is_stdout_taken_over: c.JSValue,
    write_raw_stdout: c.JSValue,
    wait_for_raw_stdout_backpressure: c.JSValue,
    flush_raw_stdout: c.JSValue,
    pub fn deinit(self: Exports, engine: *em.Engine) void {
        inline for (std.meta.fields(Exports)) |field| engine.freeValue(@field(self, field.name));
    }
};
fn emptyExports() Exports {
    var result: Exports = undefined;
    inline for (std.meta.fields(Exports)) |field| @field(result, field.name) = c.pi_js_undefined();
    return result;
}
fn duplicateExports(engine: *em.Engine, exports: Exports) Exports {
    var result: Exports = undefined;
    inline for (std.meta.fields(Exports)) |field| @field(result, field.name) = c.JS_DupValue(engine.context, @field(exports, field.name));
    return result;
}
fn retireExports(completion: *v.owned.Completion, exports: Exports) void {
    inline for (std.meta.fields(Exports)) |field| completion.release(@field(exports, field.name));
}
const Owner = struct {
    engine: *em.Engine,
    process: c.JSValue,
    lease: streams.Lease,
    takeover: ?c.JSValue = null,
    raw_tail: c.JSValue,
    write_chunk: c.JSValue,
    exports: Exports,
};
fn finalize(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const self: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    c.JS_FreeValueRT(runtime, self.process);
    if (self.takeover) |value| c.JS_FreeValueRT(runtime, value);
    c.JS_FreeValueRT(runtime, self.raw_tail);
    c.JS_FreeValueRT(runtime, self.write_chunk);
    inline for (std.meta.fields(Exports)) |field| c.JS_FreeValueRT(runtime, @field(self.exports, field.name));
    const engine = self.engine;
    engine.gpa.destroy(self);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Owner));
}
fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    c.JS_MarkValue(runtime, self.process, visit);
    if (self.takeover) |value| c.JS_MarkValue(runtime, value, visit);
    c.JS_MarkValue(runtime, self.raw_tail, visit);
    c.JS_MarkValue(runtime, self.write_chunk, visit);
    inline for (std.meta.fields(Exports)) |field| c.JS_MarkValue(runtime, @field(self.exports, field.name), visit);
}
fn guard(self: *Owner, engine: *em.Engine) !void {
    if (self.engine != engine) return error.NativeStdoutGuardForeignEngine;
    try streams.assertLease(engine, self.lease);
    try engine.checkNativeEntry();
}
fn holderOwner(holder: c.JSValue) !*Owner {
    return @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return error.NativeStdoutGuardBrand));
}
fn owner(engine: *em.Engine, roots: []const c.JSValue) !*Owner {
    try engine.checkNativeEntry();
    // Both roots are immutable private captures, never guest arguments.
    var class_id: u32 = 0;
    if (c.JS_ToUint32(engine.context, &class_id, roots[1]) < 0) return error.JavaScriptException;
    const self: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], class_id) orelse return error.NativeStdoutGuardBrand));
    try guard(self, engine);
    return self;
}
fn expression(engine: *em.Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, @call(.auto, body, .{&s} ++ args));
}
fn statement(engine: *em.Engine, comptime body: anytype, args: anytype) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, @call(.auto, body, .{&s} ++ args));
}
fn setTakeover(self: *Owner, next: ?c.JSValue) !void {
    const previous = self.takeover;
    self.takeover = next;
    var completion = v.owned.Completion.initVoid(self.engine, {});
    if (previous) |value| completion.release(value);
    try completion.finishVoid();
}
fn setTail(self: *Owner, next: c.JSValue) !void {
    const previous = self.raw_tail;
    self.raw_tail = next;
    var completion = v.owned.Completion.initVoid(self.engine, {});
    completion.release(previous);
    try completion.finishVoid();
}

fn liveStream(engine: *em.Engine, name: [*:0]const u8) !c.JSValue {
    return expression(engine, streamBody, .{name});
}
fn streamBody(s: *Scope, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "process"), name));
}
fn streamWrite(engine: *em.Engine, name: [*:0]const u8) !c.JSValue {
    return expression(engine, streamWriteBody, .{name});
}
fn streamWriteBody(s: *Scope, name: [*:0]const u8) !c.JSValue {
    const stream = try v.own(s, try liveStream(s.engine, name));
    return v.duplicate(s, try v.get(s, stream, "write"));
}
fn boundWrite(s: *Scope, name: [*:0]const u8) !c.JSValue {
    const write = try v.own(s, try streamWrite(s.engine, name));
    const bind = try v.get(s, write, "bind");
    const receiver = try v.own(s, try liveStream(s.engine, name));
    return v.duplicate(s, try v.call(s, bind, write, &.{receiver}));
}
fn stringCall(s: *Scope, value: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, try v.global(s, "String"), c.pi_js_undefined(), &.{value}));
}
fn redirect(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    _ = try owner(engine, roots);
    return expression(engine, redirectBody, .{ args, roots[2] });
}
fn redirectBody(s: *Scope, args: []const c.JSValue, raw_stderr: c.JSValue) !c.JSValue {
    const encoding_or_callback = v.arg(args, 1);
    const callback = if (c.JS_IsFunction(s.engine.context, encoding_or_callback)) encoding_or_callback else v.arg(args, 2);
    const text = try v.own(s, try expression(s.engine, stringCall, .{v.arg(args, 0)}));
    return v.duplicate(s, try v.call(s, raw_stderr, c.pi_js_undefined(), &.{ text, callback }));
}
fn takeOver(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try owner(engine, roots);
    if (self.takeover != null) return c.pi_js_undefined();
    try statement(engine, takeOverBody, .{ self, roots });
    return c.pi_js_undefined();
}
fn takeOverBody(s: *Scope, self: *Owner, roots: []const c.JSValue) !void {
    // These three real Source lexical bindings stay alive until function exit.
    const raw_stdout = try v.own(s, try expression(s.engine, boundWrite, .{@as([*:0]const u8, "stdout")}));
    const raw_stderr = try v.own(s, try expression(s.engine, boundWrite, .{@as([*:0]const u8, "stderr")}));
    const original = try v.own(s, try streamWrite(s.engine, "stdout"));
    try statement(s.engine, replaceWrite, .{ roots, raw_stderr });
    const record = try v.object(s);
    try v.put(s, record, "rawStdoutWrite", raw_stdout);
    try v.put(s, record, "rawStderrWrite", raw_stderr);
    try v.put(s, record, "originalStdoutWrite", original);
    try setTakeover(self, v.duplicate(s, record));
}
fn replaceWrite(s: *Scope, roots: []const c.JSValue, raw_stderr: c.JSValue) !void {
    // Source resolves the assignment's LHS before creating its fresh arrow.
    const stdout = try v.own(s, try liveStream(s.engine, "stdout"));
    const redirected = try v.arrow(s, "", 3, redirect, &.{ roots[0], roots[1], raw_stderr });
    try v.set(s, stdout, "write", redirected);
}
fn restore(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try owner(engine, roots);
    if (self.takeover == null) return c.pi_js_undefined();
    try statement(engine, restoreWrite, .{self});
    try setTakeover(self, null);
    return c.pi_js_undefined();
}
fn restoreWrite(s: *Scope, self: *Owner) !void {
    const stdout = try v.own(s, try liveStream(s.engine, "stdout"));
    // A live LHS getter may reenter restore, so read the current state now.
    const record = if (self.takeover) |value| try v.own(s, v.duplicate(s, value)) else c.pi_js_undefined();
    const original = try v.get(s, record, "originalStdoutWrite");
    try v.set(s, stdout, "write", original);
}
fn isTaken(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool((try owner(engine, roots)).takeover != null));
}

fn getRawWrite(s: *Scope, self: *Owner) !c.JSValue {
    if (self.takeover) |value| {
        const record = try v.own(s, v.duplicate(s, value));
        return v.duplicate(s, try v.get(s, record, "rawStdoutWrite"));
    }
    return boundWrite(s, "stdout");
}
fn writeRaw(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try owner(engine, roots);
    const text = v.arg(args, 0);
    const empty = try expression(engine, emptyText, .{text});
    if (c.JS_ToBool(engine.context, empty) == 1) return c.pi_js_undefined();
    const next = try expression(engine, enqueueWrite, .{ self, roots, text });
    try setTail(self, next);
    try statement(engine, observeWriteFailure, .{ self, roots });
    return c.pi_js_undefined();
}
fn emptyText(s: *Scope, text: c.JSValue) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, text, "length"), c.JS_NewInt32(s.engine.context, 0)));
}
fn enqueueWrite(s: *Scope, self: *Owner, roots: []const c.JSValue, text: c.JSValue) !c.JSValue {
    const tail = try v.own(s, v.duplicate(s, self.raw_tail));
    const then = try v.get(s, tail, "then");
    const callback = try v.arrow(s, "", 0, queuedWrite, &.{ roots[0], roots[1], text });
    return v.duplicate(s, try v.call(s, then, tail, &.{callback}));
}
fn queuedWrite(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try owner(engine, roots);
    return expression(engine, callChunk, .{ self, roots[2] });
}
fn callChunk(s: *Scope, self: *Owner, text: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, self.write_chunk, c.pi_js_undefined(), &.{text}));
}
fn observeWriteFailure(s: *Scope, self: *Owner, roots: []const c.JSValue) !void {
    const tail = try v.own(s, v.duplicate(s, self.raw_tail));
    const catcher = try v.get(s, tail, "catch");
    const callback = try v.arrow(s, "", 0, exitFailure, roots);
    _ = try v.call(s, catcher, tail, &.{callback});
}
fn exitFailure(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    _ = try owner(engine, roots);
    try statement(engine, exitBody, .{});
    return c.pi_js_undefined();
}
fn exitBody(s: *Scope) !void {
    const process = try v.global(s, "process");
    const exit = try v.get(s, process, "exit");
    _ = try v.call(s, exit, process, &.{c.JS_NewInt32(s.engine.context, 1)});
}

fn isError(engine: *em.Engine, reason: c.JSValue) !bool {
    const result = try expression(engine, isErrorBody, .{reason});
    return c.JS_ToBool(engine.context, result) == 1;
}
fn isErrorBody(s: *Scope, reason: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Error");
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const result = c.JS_IsInstanceOf(s.engine.context, reason, constructor);
    try boundary.finishStatus(if (result < 0) result else 0);
    return v.boolean(s, result != 0);
}
fn normalizedError(s: *Scope, reason: c.JSValue) !c.JSValue {
    if (try isError(s.engine, reason)) return v.duplicate(s, reason);
    const constructor = try v.global(s, "Error");
    const text = try v.own(s, try expression(s.engine, stringCall, .{reason}));
    return v.duplicate(s, try v.construct(s, constructor, &.{text}));
}
fn writeExecutor(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try owner(engine, roots);
    statement(engine, executorTry, .{ self, roots, args }) catch |err| {
        const reason = try caught(engine, err);
        try statement(engine, rejectWriteError, .{ reason, v.arg(args, 1) });
    };
    return c.pi_js_undefined();
}
fn executorTry(s: *Scope, self: *Owner, roots: []const c.JSValue, args: []const c.JSValue) !void {
    const write = try v.own(s, try expression(s.engine, getRawWrite, .{self}));
    const callback = try v.arrow(s, "", 1, writeCompleted, &.{ roots[0], roots[1], v.arg(args, 0), v.arg(args, 1) });
    _ = try v.call(s, write, c.pi_js_undefined(), &.{ roots[2], callback });
}
fn rejectWriteError(s: *Scope, incoming: c.JSValue, reject: c.JSValue) !void {
    const reason = try v.own(s, incoming);
    const normalized = try v.own(s, try expression(s.engine, normalizedError, .{reason}));
    _ = try v.call(s, reject, c.pi_js_undefined(), &.{normalized});
}
fn writeCompleted(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    _ = try owner(engine, roots);
    try statement(engine, completedBody, .{ v.arg(args, 0), roots[2], roots[3] });
    return c.pi_js_undefined();
}
fn completedBody(s: *Scope, error_value: c.JSValue, resolve: c.JSValue, reject: c.JSValue) !void {
    if (v.truthy(s, error_value)) _ = try v.call(s, reject, c.pi_js_undefined(), &.{error_value})
    else _ = try v.call(s, resolve, c.pi_js_undefined(), &.{});
}
fn writePromise(s: *Scope, roots: []const c.JSValue, text: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Promise");
    const executor = try v.arrow(s, "", 2, writeExecutor, &.{ roots[0], roots[1], text });
    return v.duplicate(s, try v.construct(s, constructor, &.{executor}));
}
fn retryExecutor(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    _ = try owner(engine, roots);
    return expression(engine, retryTimer, .{v.arg(args, 0)});
}
fn retryTimer(s: *Scope, resolve: c.JSValue) !c.JSValue {
    const timer = try v.global(s, "setTimeout");
    return v.duplicate(s, try v.call(s, timer, c.pi_js_undefined(), &.{ resolve, c.JS_NewInt32(s.engine.context, 10) }));
}
fn retryPromise(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Promise");
    const executor = try v.arrow(s, "", 1, retryExecutor, roots);
    return v.duplicate(s, try v.construct(s, constructor, &.{executor}));
}
fn writeChunkBody(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    _ = try owner(engine, roots);
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, advanceChunk(&s, args, roots, state, completion, input));
}
fn advanceChunk(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const frame = try v.stateObject(s);
        try v.put(s, frame, "phase", c.JS_NewInt32(s.engine.context, 0));
        try v.put(s, frame, "error", c.pi_js_undefined());
        try v.put(s, frame, "writeError", c.pi_js_undefined());
        try v.put(s, frame, "code", c.pi_js_undefined());
        af.replaceState(s.engine, state, v.duplicate(s, frame));
        return attemptChunk(s, roots, v.arg(args, 0), frame);
    }
    const retrying = v.equal(s, try v.get(s, state.*, "phase"), c.JS_NewInt32(s.engine.context, 1));
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(s.engine);
        if (retrying) return .{ .thrown = v.duplicate(s, input) };
        return catchChunk(s, roots, state.*, input);
    }
    if (!retrying) return .{ .returned = c.pi_js_undefined() };
    // BCDF retains uncaptured catch locals across the next try and Await.
    // They reset only when that catch scope is entered again, or on exit.
    return attemptChunk(s, roots, v.arg(args, 0), state.*);
}
fn attemptChunk(s: *Scope, roots: []const c.JSValue, text: c.JSValue, frame: c.JSValue) !af.Action {
    try v.put(s, frame, "phase", c.JS_NewInt32(s.engine.context, 0));
    const promise = expression(s.engine, writePromise, .{ roots, text }) catch |err| {
        const reason = try v.own(s, try caught(s.engine, err));
        return catchChunk(s, roots, frame, reason);
    };
    return .{ .awaited = promise };
}
fn catchChunk(s: *Scope, roots: []const c.JSValue, frame: c.JSValue, reason: c.JSValue) !af.Action {
    // The catch binding is assigned first, then its body resets lexical slots
    // in reverse declaration order, matching the interpreter's scope entry.
    try v.put(s, frame, "error", reason);
    try v.put(s, frame, "code", c.pi_js_undefined());
    try v.put(s, frame, "writeError", c.pi_js_undefined());
    const write_error = try v.own(s, try expression(s.engine, normalizedError, .{reason}));
    try v.put(s, frame, "writeError", write_error);
    const code = try v.get(s, write_error, "code");
    try v.put(s, frame, "code", code);
    if (!try v.eq(s, code, "ENOBUFS") and !try v.eq(s, code, "EAGAIN") and !try v.eq(s, code, "EWOULDBLOCK"))
        return .{ .thrown = v.duplicate(s, write_error) };
    try v.put(s, frame, "phase", c.JS_NewInt32(s.engine.context, 1));
    return .{ .awaited = try expression(s.engine, retryPromise, .{roots}) };
}

fn waitBody(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const self = try owner(engine, roots);
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, advanceWait(&s, self, state, completion, input));
}
fn advanceWait(s: *Scope, self: *Owner, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(s.engine);
        return .{ .thrown = v.duplicate(s, input) };
    }
    if (completion == .start) {
        const frame = try v.stateObject(s);
        af.replaceState(s.engine, state, v.duplicate(s, frame));
    } else {
        const same = try expression(s.engine, waitMatches, .{ self, state.* });
        if (c.JS_ToBool(s.engine.context, same) == 1) return .{ .returned = c.pi_js_undefined() };
    }
    // The new while body enters before reading the next live module binding.
    try v.put(s, state.*, "tail", c.pi_js_undefined());
    try v.put(s, state.*, "tail", self.raw_tail);
    return .{ .awaited = v.duplicate(s, self.raw_tail) };
}
fn waitMatches(s: *Scope, self: *Owner, frame: c.JSValue) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, frame, "tail"), self.raw_tail));
}
fn flushBody(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const self = try owner(engine, roots);
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, advanceFlush(&s, self, state, completion, input));
}
fn advanceFlush(s: *Scope, self: *Owner, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(s.engine);
        return .{ .thrown = v.duplicate(s, input) };
    }
    if (completion == .start) {
        af.replaceState(s.engine, state, c.JS_NewInt32(s.engine.context, 1));
        return .{ .awaited = try expression(s.engine, callWait, .{self}) };
    }
    if (v.equal(s, state.*, c.JS_NewInt32(s.engine.context, 1))) {
        af.replaceState(s.engine, state, c.JS_NewInt32(s.engine.context, 2));
        return .{ .awaited = try expression(s.engine, emptyChunk, .{self}) };
    }
    return .{ .returned = c.pi_js_undefined() };
}
fn callWait(s: *Scope, self: *Owner) !c.JSValue {
    return v.duplicate(s, try v.call(s, self.exports.wait_for_raw_stdout_backpressure, c.pi_js_undefined(), &.{}));
}
fn emptyChunk(s: *Scope, self: *Owner) !c.JSValue {
    return v.duplicate(s, try v.call(s, self.write_chunk, c.pi_js_undefined(), &.{try v.text(s, "")}));
}

fn promiseResolve(s: *Scope) !c.JSValue {
    const constructor = try v.global(s, "Promise");
    return v.duplicate(s, try v.call(s, try v.get(s, constructor, "resolve"), constructor, &.{}));
}
fn resumable(s: *Scope, name: [*:0]const u8, length: c_int, body: af.Body, roots: []const c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return boundary.finishValue(s, af.createResumable(s.engine, name, length, body, roots));
}
fn createHolder(s: *Scope, actual_process: c.JSValue, lease: streams.Lease) !c.JSValue {
    var class_id: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Actual Source stdout guard owner", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(s.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    const holder = try v.objectClass(s, class_id);
    if (c.pi_js_native_memory_reserve(s.engine.native_memory_owner, @sizeOf(Owner)) == 0) return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(s.engine.native_memory_owner, @sizeOf(Owner));
    const self = try s.engine.gpa.create(Owner);
    self.* = .{
        .engine = s.engine, .process = v.duplicate(s, actual_process), .lease = lease,
        .raw_tail = c.pi_js_undefined(), .write_chunk = c.pi_js_undefined(), .exports = emptyExports(),
    };
    _ = c.JS_SetOpaque(holder, self);
    attached = true;
    const roots = [_]c.JSValue{ holder, c.JS_NewUint32(s.engine.context, class_id) };
    self.exports.take_over_stdout = v.duplicate(s, try v.ordinary(s, "takeOverStdout", 0, takeOver, &roots));
    self.exports.restore_stdout = v.duplicate(s, try v.ordinary(s, "restoreStdout", 0, restore, &roots));
    self.exports.is_stdout_taken_over = v.duplicate(s, try v.ordinary(s, "isStdoutTakenOver", 0, isTaken, &roots));
    self.exports.write_raw_stdout = v.duplicate(s, try v.ordinary(s, "writeRawStdout", 1, writeRaw, &roots));
    self.exports.wait_for_raw_stdout_backpressure = v.duplicate(s, try resumable(s, "waitForRawStdoutBackpressure", 0, waitBody, &roots));
    self.exports.flush_raw_stdout = v.duplicate(s, try resumable(s, "flushRawStdout", 0, flushBody, &roots));
    self.write_chunk = v.duplicate(s, try resumable(s, "writeRawStdoutChunk", 1, writeChunkBody, &roots));
    self.raw_tail = try expression(s.engine, promiseResolve, .{});
    try guard(self, s.engine);
    return v.duplicate(s, holder);
}
fn validateProcess(s: *Scope, actual_process: c.JSValue) !void {
    if (!v.equal(s, try v.global(s, "process"), actual_process)) return error.NativeStdoutGuardProcessChanged;
}
fn validateCached(self: *Owner, engine: *em.Engine, actual_process: c.JSValue, lease: streams.Lease) !void {
    if (self.engine != engine or !c.JS_IsStrictEqual(engine.context, self.process, actual_process)) return error.NativeStdoutGuardForeignEngine;
    if (self.lease.context != lease.context or self.lease.generation != lease.generation) return error.NativeStdoutGuardFrontendChanged;
    try guard(self, engine);
}
fn createInner(engine: *em.Engine, actual_process: c.JSValue, lease: streams.Lease) !Exports {
    var cursor = initializing;
    while (cursor) |prior| : (cursor = prior.previous) {
        if (prior.engine == engine) return error.NativeStdoutGuardInitializing;
    }
    var entry: Entry = .{ .engine = engine, .previous = initializing };
    initializing = &entry;
    defer initializing = entry.previous;
    try streams.assertLease(engine, lease);
    try statement(engine, validateProcess, .{actual_process});
    if (engine.native_module_values.get(key)) |holder| {
        const self = try holderOwner(holder);
        try validateCached(self, engine, actual_process, lease);
        return duplicateExports(engine, self.exports);
    }
    const holder = try expression(engine, createHolder, .{ actual_process, lease });
    const self = holderOwner(holder) catch |err| {
        var completion = v.owned.Completion.initVoid(engine, err);
        completion.release(holder);
        try completion.finishVoid();
        unreachable;
    };
    validateCached(self, engine, actual_process, lease) catch |err| {
        var completion = v.owned.Completion.initVoid(engine, err);
        completion.release(holder);
        try completion.finishVoid();
        unreachable;
    };
    const exports = duplicateExports(engine, self.exports);
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = v.owned.Completion.initVoid(engine, err);
        retireExports(&completion, exports);
        completion.release(holder);
        try completion.finishVoid();
        unreachable;
    };
    // All staging roots and validation have completed. The final transfer is
    // nonallocating and is followed by no registration, guest operation or free.
    engine.native_module_values.putAssumeCapacity(key, holder);
    return exports;
}
pub fn create(engine: *em.Engine, actual_process: c.JSValue, lease: streams.Lease) !Exports {
    try engine.checkNativeEntry();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    const result = createInner(engine, actual_process, lease) catch |err| {
        _ = engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err))) catch |actual| return actual;
        return err;
    };
    _ = engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())) catch |err| {
        var completion = v.owned.Completion.initVoid(engine, err);
        retireExports(&completion, result);
        try completion.finishVoid();
        unreachable;
    };
    return result;
}
