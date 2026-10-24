//! Original runner.ts emitProjectTrustEvent with intrinsic native Await.
//! Snapshot every extension before dispatch; preserve ordinary iterators, catches,
//! live error formatting and close order. No fake extension or context is made.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const af = v.af;
const caught = @import("native_agent_af_values.zig").caught;
const cache_key = "pi-private:actual-sdk-project-trust-event";
const Local = enum { errors, ext, handlers, handler, handler_result, caught_error };
const Loop = enum { outer, inner };
const ReturnPhase = enum { none, inner, outer };
const Iterator = struct {
    receiver: c.JSValue,
    next: c.JSValue,
    active: bool = false,
};

const State = struct {
    engine: *Engine,
    owner: c.JSValue,
    locals: [6]c.JSValue,
    outer: Iterator,
    inner: Iterator,
    return_value: c.JSValue,
    return_phase: ReturnPhase = .none,
    closed: bool = false,
    steps: usize = 0,

    fn create(s: *Scope) !*State {
        var class_id: c.JSClassID = 0;
        if (c.JS_NewClassID(s.engine.runtime, &class_id) == 0) return error.OutOfMemory;
        const definition: c.JSClassDef = .{
            .class_name = "Actual project trust event activation",
            .finalizer = finalize, .gc_mark = mark,
        };
        if (c.JS_NewClass(s.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
        const owner = try v.objectClass(s, class_id);
        if (c.pi_js_native_memory_reserve(s.engine.native_memory_owner, @sizeOf(State)) == 0)
            return error.OutOfMemory;
        errdefer c.pi_js_native_memory_release(s.engine.native_memory_owner, @sizeOf(State));
        const self = try s.engine.gpa.create(State);
        const empty: Iterator = .{ .receiver = c.pi_js_undefined(), .next = c.pi_js_undefined() };
        self.* = .{ .engine = s.engine, .owner = owner,
            .locals = @splat(c.pi_js_undefined()), .outer = empty, .inner = empty,
            .return_value = c.pi_js_undefined() };
        _ = c.JS_SetOpaque(owner, self);
        return self;
    }
    fn from(owner: c.JSValue) *State {
        return @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
    }
    fn get(self: *const State, comptime name: Local) c.JSValue {
        return self.locals[@intFromEnum(name)];
    }
    fn take(self: *State, comptime name: Local, incoming: anyerror!c.JSValue) !void {
        try self.replace(&self.locals[@intFromEnum(name)], incoming);
    }
    fn replace(self: *State, slot: *c.JSValue, incoming: anyerror!c.JSValue) !void {
        const next = try incoming;
        const previous = slot.*;
        slot.* = next;
        var selected = v.owned.Completion.initVoid(self.engine, {});
        selected.release(previous);
        return selected.finishVoid();
    }
    fn iterator(self: *State, comptime which: Loop) *Iterator {
        return if (which == .outer) &self.outer else &self.inner;
    }
    fn retire(slot: *c.JSValue, selected: *v.owned.Completion) void {
        const previous = slot.*; slot.* = c.pi_js_undefined(); selected.release(previous);
    }
    fn close(self: *State, selected: *v.owned.Completion) void {
        if (self.closed) return;
        self.closed = true;
        // Original uncaptured function locals retire in declaration order.
        for (&self.locals) |*slot| retire(slot, selected);
        // In an actual fatal exit the VM retains its operand stack. emit_return
        // rotates the return operand below the iterator currently being closed.
        if (self.return_phase == .outer) retire(&self.return_value, selected);
        retire(&self.outer.receiver, selected);
        retire(&self.outer.next, selected);
        if (self.return_phase != .outer) retire(&self.return_value, selected);
        retire(&self.inner.receiver, selected);
        retire(&self.inner.next, selected);
    }
    fn terminal(engine: *Engine, owner: c.JSValue) !void {
        if (!c.JS_IsLiveObject(engine.runtime, owner)) return;
        const raw = c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return;
        const self: *State = @ptrCast(@alignCast(raw));
        var selected = v.owned.Completion.initVoid(engine, {});
        self.close(&selected);
        return selected.finishVoid();
    }
    fn freeSlot(runtime: ?*c.JSRuntime, slot: *c.JSValue) void {
        const value = slot.*; slot.* = c.pi_js_undefined(); c.JS_FreeValueRT(runtime, value);
    }
    fn finalize(runtime: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
        const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
        for (&self.locals) |*slot| freeSlot(runtime, slot);
        if (self.return_phase == .outer) freeSlot(runtime, &self.return_value);
        freeSlot(runtime, &self.outer.receiver);
        freeSlot(runtime, &self.outer.next);
        if (self.return_phase != .outer) freeSlot(runtime, &self.return_value);
        freeSlot(runtime, &self.inner.receiver);
        freeSlot(runtime, &self.inner.next);
        const engine = self.engine;
        engine.gpa.destroy(self);
        c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
    }
    fn mark(runtime: ?*c.JSRuntime, owner: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
        const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
        for (self.locals) |value| c.JS_MarkValue(runtime, value, visit);
        c.JS_MarkValue(runtime, self.outer.receiver, visit);
        c.JS_MarkValue(runtime, self.outer.next, visit);
        c.JS_MarkValue(runtime, self.inner.receiver, visit);
        c.JS_MarkValue(runtime, self.inner.next, visit);
        c.JS_MarkValue(runtime, self.return_value, visit);
    }
};

/// Owned genuine AsyncFunction, for the original runner import binding.
pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |existing| return h.duplicate(engine, existing);
    const candidate = try h.expression(engine, createBody, .{});
    if (engine.native_module_values.get(cache_key)) |existing| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, existing));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var selected = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        selected.release(candidate);
        return selected.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn createBody(s: *Scope) !c.JSValue {
    const snapshot = try v.ordinary(s, "snapshotEventHandlers", 2, snapshotCall, &.{});
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const function = try boundary.finishValue(s,
        af.createResumableWithClose(s.engine, "emitProjectTrustEvent", 3, emit, &.{snapshot}, State.terminal));
    return v.duplicate(s, function);
}
fn snapshotCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    _: []const c.JSValue) !c.JSValue
{
    return h.expression(engine, snapshotBody, .{ v.arg(args, 0), v.arg(args, 1) });
}
fn snapshotBody(s: *Scope, extensions: c.JSValue, event: c.JSValue) !c.JSValue {
    const map = try v.get(s, extensions, "map");
    const callback = try v.arrow(s, "", 1, snapshotRowCall, &.{event});
    return v.duplicate(s, try v.call(s, map, extensions, &.{callback}));
}
fn snapshotRowCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    return h.expression(engine, snapshotRowBody, .{ v.arg(args, 0), roots[0] });
}
fn snapshotRowBody(s: *Scope, ext: c.JSValue, event: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "ext", ext);
    const selected = try h.expression(s.engine, selectHandlersBody, .{ ext, event });
    const sliced = try v.own(s, try h.expression(s.engine, sliceHandlersBody, .{selected}));
    try v.put(s, result, "handlers", if (v.nullish(sliced)) try v.array(s) else sliced);
    return v.duplicate(s, result);
}
fn selectHandlersBody(s: *Scope, ext: c.JSValue, event: c.JSValue) !c.JSValue {
    const handlers = try v.get(s, ext, "handlers");
    return v.duplicate(s, try v.invoke(s, handlers, "get", &.{event}));
}
fn sliceHandlersBody(s: *Scope, incoming: c.JSValue) !c.JSValue {
    const selected = try v.own(s, incoming);
    if (v.nullish(selected)) return c.pi_js_undefined();
    // The call receiver retires after its called method, before row definition.
    return try h.expression(s.engine, callSliceBody, .{selected});
}
fn callSliceBody(s: *Scope, selected: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.invoke(s, selected, "slice", &.{}));
}
fn snapshotEntry(s: *Scope, snapshot: c.JSValue, extensions_result: c.JSValue) !c.JSValue {
    const extensions = try v.get(s, extensions_result, "extensions");
    return v.duplicate(s, try v.call(s, snapshot, c.pi_js_undefined(),
        &.{ extensions, try v.text(s, "project_trust") }));
}
fn emptyErrors(s: *Scope) !c.JSValue { return v.duplicate(s, try v.array(s)); }

fn iteratorCallBody(s: *Scope, iterable: c.JSValue) !c.JSValue {
    const method = try v.key(s, iterable, try v.iteratorSymbol(s));
    if (!c.JS_IsFunction(s.engine.context, method)) return v.typeError(s, "value is not iterable");
    return v.duplicate(s, try v.call(s, method, iterable, &.{}));
}
fn iteratorObjectBody(s: *Scope, incoming: c.JSValue) !c.JSValue {
    const iterable = try v.own(s, incoming);
    // GetIterator's called method retires before result validation; the original
    // iterable operand retires only after the iterator has been produced.
    const receiver = try v.own(s, try h.expression(s.engine, iteratorCallBody, .{iterable}));
    if (!c.JS_IsObject(receiver)) return v.typeError(s, "not an object");
    return v.duplicate(s, receiver);
}
fn startLoop(state: *State, comptime which: Loop, incoming: c.JSValue) !void {
    const record = state.iterator(which);
    // Retire the iterable operand before Get(next), as js_for_of_start does.
    try state.replace(&record.receiver, h.expression(state.engine, iteratorObjectBody, .{incoming}));
    try state.replace(&record.next, h.get(state.engine, record.receiver, "next"));
    record.active = true; // The actual iterator catch record now exists.
}
fn doneBody(s: *Scope, result: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.get(s, result, "done")));
}
fn nextBody(s: *Scope, receiver: c.JSValue, next_function: c.JSValue, done: *bool) !c.JSValue {
    const result = try v.call(s, next_function, receiver, &.{});
    if (!c.JS_IsObject(result)) return v.typeError(s, "iterator must return an object");
    done.* = h.truthy(s.engine, try h.expression(s.engine, doneBody, .{result}));
    return if (done.*) c.pi_js_undefined() else v.duplicate(s, try v.get(s, result, "value"));
}
fn nextLoop(state: *State, comptime which: Loop) !?c.JSValue {
    const record = state.iterator(which);
    try v.poll(state.engine, &state.steps);
    var s: Scope = .{ .engine = state.engine };
    var done = false;
    const result = v.owned.finishValue(&s, nextBody(&s, record.receiver, record.next, &done)) catch |err| {
        record.active = false;
        // Step/value errors discard the receiver and never call this iterator's
        // return. Its cached next operand is retired by the enclosing unwind.
        var selected = v.owned.Completion.initVoid(state.engine, err);
        State.retire(&record.receiver, &selected);
        try selected.finishVoid();
        unreachable;
    };
    if (!done) return result;
    record.active = false;
    var selected = v.owned.Completion.initValue(state.engine, result);
    State.retire(&record.receiver, &selected);
    const terminal = try selected.finishValue();
    state.engine.freeValue(terminal); // primitive undefined
    return null;
}
fn finishDone(state: *State, comptime which: Loop) !void {
    try state.replace(&state.iterator(which).next, c.pi_js_undefined());
}
fn invokeReturnBody(s: *Scope, receiver: c.JSValue, called: *bool) !c.JSValue {
    const method = try v.get(s, receiver, "return");
    if (v.nullish(method)) return c.pi_js_undefined();
    called.* = true;
    return v.duplicate(s, try v.call(s, method, receiver, &.{}));
}
fn closeBody(s: *Scope, receiver: c.JSValue, validate_result: bool) !void {
    var called = false;
    // JS_CallFree retires the method before checking the returned object.
    const result = try v.own(s, try h.expression(s.engine, invokeReturnBody, .{ receiver, &called }));
    if (called and validate_result and !c.JS_IsObject(result)) return v.typeError(s, "not an object");
}
fn closeNormal(state: *State, comptime which: Loop) !void {
    const record = state.iterator(which);
    const active = record.active;
    record.active = false;
    try state.replace(&record.next, c.pi_js_undefined());
    if (active) try h.statement(state.engine, closeBody, .{ record.receiver, true });
    try state.replace(&record.receiver, c.pi_js_undefined());
}
fn preservedCloseBody(s: *Scope, receiver: c.JSValue, incoming: c.JSValue) !af.Action {
    const original = try v.own(s, incoming);
    closeBody(s, receiver, false) catch |err| {
        _ = try v.own(s, try caught(s.engine, err));
    };
    return .{ .thrown = v.duplicate(s, original) };
}
fn closeAbrupt(state: *State, comptime which: Loop, incoming: c.JSValue) !c.JSValue {
    const record = state.iterator(which);
    const active = record.active; record.active = false;
    var next_retirement = v.owned.Completion.initAction(state.engine, .{ .thrown = incoming });
    State.retire(&record.next, &next_retirement);
    const original = switch (try next_retirement.finishAction()) {
        .thrown => |reason| reason, .returned, .awaited => unreachable,
    };
    const selected_action: af.Action = if (active) blk: {
        var s: Scope = .{ .engine = state.engine };
        break :blk try v.owned.finishAction(&s, preservedCloseBody(&s, record.receiver, original));
    } else .{ .thrown = original };
    var receiver_retirement = v.owned.Completion.initAction(state.engine, selected_action);
    State.retire(&record.receiver, &receiver_retirement);
    return switch (try receiver_retirement.finishAction()) {
        .thrown => |reason| reason, .returned, .awaited => unreachable,
    };
}
fn retireReturn(state: *State, incoming: c.JSValue) !c.JSValue {
    var selected = v.owned.Completion.initAction(state.engine, .{ .thrown = incoming });
    State.retire(&state.return_value, &selected);
    return switch (try selected.finishAction()) {
        .thrown => |reason| reason, .returned, .awaited => unreachable,
    };
}
fn abrupt(state: *State, err: anyerror) !af.Action {
    // Actual fatal events bypass ordinary catch and IteratorClose. The terminal
    // owner then retires the remaining actual locals/operand roots in VM order.
    var reason = try caught(state.engine, err);
    reason = try closeAbrupt(state, .inner, reason);
    if (state.return_phase != .outer) reason = try retireReturn(state, reason);
    reason = try closeAbrupt(state, .outer, reason);
    if (state.return_phase == .outer) reason = try retireReturn(state, reason);
    return .{ .thrown = reason };
}

fn bindOuterBody(s: *Scope, state: *State, incoming: c.JSValue) !void {
    const value = try v.own(s, incoming);
    // Original object binding boxes once, so both Gets share their receiver.
    const row = try v.guest.toObject(s, value);
    try state.take(.ext, h.get(s.engine, row, "ext"));
    try state.take(.handlers, h.get(s.engine, row, "handlers"));
}
fn attemptHandler(engine: *Engine, handler: c.JSValue, event: c.JSValue, context: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine };
    const outcome: anyerror!af.Action = if (v.call(&s, handler, c.pi_js_undefined(), &.{ event, context })) |value|
        .{ .returned = v.duplicate(&s, value) } else |err| err;
    return v.owned.finishAction(&s, outcome);
}
fn inspectBody(s: *Scope, state: *State) !af.Action {
    const result = state.get(.handler_result);
    if (try h.fieldEqual(s.engine, result, "trusted", "undecided"))
        return .{ .returned = c.pi_js_undefined() };
    // Original accepts every non-undecided result without yes/no validation.
    const returned = try v.object(s);
    try v.put(s, returned, "result", result);
    try v.put(s, returned, "errors", state.get(.errors));
    return .{ .returned = v.duplicate(s, returned) };
}
fn inspectResult(state: *State) !af.Action {
    var s: Scope = .{ .engine = state.engine };
    return v.owned.finishAction(&s, inspectBody(&s, state));
}
fn isErrorBody(s: *Scope, value: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Error");
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const result = c.JS_IsInstanceOf(s.engine.context, value, constructor);
    try boundary.finishStatus(result);
    return v.boolean(s, result != 0);
}
fn errorMessageBody(s: *Scope, value: c.JSValue) !c.JSValue {
    const is_error = h.truthy(s.engine, try h.expression(s.engine, isErrorBody, .{value}));
    return v.duplicate(s, if (is_error) try v.get(s, value, "message") else
        try v.call(s, try v.global(s, "String"), c.pi_js_undefined(), &.{value}));
}
fn errorStackBody(s: *Scope, value: c.JSValue) !c.JSValue {
    const is_error = h.truthy(s.engine, try h.expression(s.engine, isErrorBody, .{value}));
    return if (is_error) v.duplicate(s, try v.get(s, value, "stack")) else c.pi_js_undefined();
}
fn reportBody(s: *Scope, state: *State, event: c.JSValue) !void {
    const errors = state.get(.errors);
    const push = try v.get(s, errors, "push");
    const row = try v.object(s);
    try v.put(s, row, "extensionPath", try v.get(s, state.get(.ext), "path"));
    try v.put(s, row, "event", try v.get(s, event, "type"));
    const reason = state.get(.caught_error);
    const message = try v.own(s, try h.expression(s.engine, errorMessageBody, .{reason}));
    try v.put(s, row, "error", message);
    // This is a second live Error lookup/instanceof, after message/coercion.
    const stack = try v.own(s, try h.expression(s.engine, errorStackBody, .{reason}));
    try v.put(s, row, "stack", stack);
    _ = try v.call(s, push, errors, &.{row});
}
fn report(state: *State, event: c.JSValue) !void {
    return h.statement(state.engine, reportBody, .{ state, event });
}
fn normalReturn(state: *State, incoming: c.JSValue) !af.Action {
    try state.replace(&state.return_value, incoming);
    state.return_phase = .inner;
    try closeNormal(state, .inner);
    state.return_phase = .outer;
    try closeNormal(state, .outer);
    const returned = state.return_value;
    state.return_value = c.pi_js_undefined();
    state.return_phase = .none;
    return .{ .returned = returned };
}
fn afterHandler(state: *State, event: c.JSValue) !?af.Action {
    switch (try inspectResult(state)) {
        .returned => |value| {
            if (c.JS_IsUndefined(value)) return null;
            return try normalReturn(state, value);
        },
        .thrown => |reason| {
            try state.take(.caught_error, reason);
            try report(state, event);
            return null;
        },
        .awaited => unreachable,
    }
}
fn emptyResult(s: *Scope, errors: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "errors", errors);
    return v.duplicate(s, result);
}
fn dispatch(state: *State, args: []const c.JSValue, roots: []const c.JSValue,
    completion: af.Completion, input: c.JSValue) !af.Action
{
    const engine = state.engine;
    const event = v.arg(args, 1);
    const context = v.arg(args, 2);
    switch (completion) {
        .start => {
            try state.take(.errors, h.expression(engine, emptyErrors, .{}));
            const snapshot = try h.expression(engine, snapshotEntry, .{ roots[0], v.arg(args, 0) });
            try startLoop(state, .outer, snapshot);
        },
        .fulfilled => {
            try state.take(.handler_result, c.JS_DupValue(engine.context, input));
            if (try afterHandler(state, event)) |action| return action;
        },
        .rejected => {
            // Await rejection is borrowed DATA, including a historical private
            // tag or flag. Actual pending completion was checked at body entry.
            try state.take(.caught_error, c.JS_DupValue(engine.context, input));
            try report(state, event);
        },
    }
    while (true) {
        if (!state.inner.active) {
            const next_outer = try nextLoop(state, .outer);
            if (next_outer) |row| {
                try h.statement(engine, bindOuterBody, .{ state, row });
                // The nested lexical-head scope is entered for each outer body.
                try state.take(.handler, c.pi_js_undefined());
                try startLoop(state, .inner, c.JS_DupValue(engine.context, state.get(.handlers)));
            } else {
                try finishDone(state, .outer);
                return .{ .returned = try h.expression(engine, emptyResult, .{state.get(.errors)}) };
            }
        }
        const next_inner = try nextLoop(state, .inner);
        if (next_inner) |handler| {
            try state.take(.handler, handler);
            // Source enters its try body after assigning the next loop head.
            try state.take(.handler_result, c.pi_js_undefined());
            switch (try attemptHandler(engine, state.get(.handler), event, context)) {
                .returned => |value| return .{ .awaited = value },
                .thrown => |reason| {
                    try state.take(.caught_error, reason);
                    try report(state, event);
                },
                .awaited => unreachable,
            }
        } else try finishDone(state, .inner);
    }
}
fn emit(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue,
    owner_slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action
{
    if (completion == .rejected)
        try @import("native_async_body.zig").enterRejectedContinuation(engine);
    var s: Scope = .{ .engine = engine };
    const state = if (completion == .start) block: {
        const created = State.create(&s) catch |err| return v.owned.finishAction(&s, err);
        af.replaceState(engine, owner_slot, v.duplicate(&s, created.owner));
        break :block created;
    } else State.from(owner_slot.*);
    const outcome = dispatch(state, args, roots, completion, input) catch |err|
        return v.owned.finishAction(&s, abrupt(state, err));
    return v.owned.finishAction(&s, outcome);
}
