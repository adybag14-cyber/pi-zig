//! Operation-local roots and genuine AF boundaries for Chord's Node adapter.
const em = @import("engine.zig");
pub const c = em.c;
const std = @import("std");
/// Private roots. A current VM event is normalized before the host append.
/// Error unwinding owns its first reason across root/finalizer cleanup.
pub const Scope = struct {
    engine: *em.Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    unwind: ?c.JSValue = null,
    pub fn captureUnwind(self: *Scope, err: anyerror) void {
        if (err != error.JavaScriptException or self.unwind != null) return;
        self.unwind = if (c.JS_HasException(self.engine.context)) c.JS_GetException(self.engine.context) else takeCaptured(self.engine);
    }
    pub fn deinit(self: *Scope) void {
        var cleanup: Cleanup = .{ .engine = self.engine, .generation = self.engine.native_allocation_generation };
        if (self.unwind) |reason| cleanup.offer(reason, true);
        self.unwind = null;
        // A diagnostic present on successful entry is retained as data. Only
        // the unwind/current VM event and events produced by cleanup are fatal
        // candidates; a flag on historical captured data proves no new event.
        if (c.JS_HasException(self.engine.context)) cleanup.offer(c.JS_GetException(self.engine.context), true);
        if (takeCaptured(self.engine)) |reason| cleanup.offer(reason, false);
        cleanup.collect();
        for (self.values.items) |value| { self.engine.freeValue(value); cleanup.collect(); }
        self.values.deinit(self.engine.gpa);
        cleanup.collect();
        cleanup.publish();
    }
    pub fn own(self: *Scope, raw: c.JSValue) !c.JSValue {
        const value = try current(self.engine, raw);
        self.values.append(self.engine.gpa, value) catch |err| { self.engine.freeValue(value); return err; };
        return value;
    }

    pub fn get(self: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue { try pending(self.engine); const generation = self.engine.native_allocation_generation; return self.own(try checkedSince(self.engine, c.JS_GetPropertyStr(self.engine.context, object, name), generation)); }
    pub fn global(self: *Scope, name: [*:0]const u8) !c.JSValue { try pending(self.engine); const object = c.JS_GetGlobalObject(self.engine.context); defer self.engine.freeValue(object); return self.get(object, name); }
    pub fn call(self: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue { try pending(self.engine); const generation = self.engine.native_allocation_generation; return self.own(try checkedSince(self.engine, c.JS_Call(self.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)), generation)); }

    pub fn object(self: *Scope) !c.JSValue { try pending(self.engine); return self.own(try checked(self.engine, c.JS_NewObject(self.engine.context))); }
    pub fn array(self: *Scope) !c.JSValue { try pending(self.engine); return self.own(try checked(self.engine, c.JS_NewArray(self.engine.context))); }
    pub fn text(self: *Scope, value: []const u8) !c.JSValue { try pending(self.engine); return self.own(try checked(self.engine, c.JS_NewStringLen(self.engine.context, value.ptr, value.len))); }
    pub fn put(self: *Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try pending(self.engine); const generation = self.engine.native_allocation_generation; const result = c.JS_DefinePropertyValueStr(self.engine.context, object, name, c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E); try statusSince(self.engine, result < 0, generation); }
    pub fn set(self: *Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try pending(self.engine); const generation = self.engine.native_allocation_generation; const result = c.JS_SetPropertyStr(self.engine.context, object, name, c.JS_DupValue(self.engine.context, value)); try statusSince(self.engine, result < 0, generation); }
    pub fn index(self: *Scope, object: c.JSValue, index_value: u32, value: c.JSValue) !void { try pending(self.engine); const generation = self.engine.native_allocation_generation; const result = c.JS_DefinePropertyValueUint32(self.engine.context, object, index_value, c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E); try statusSince(self.engine, result < 0, generation); }

    pub fn concat(self: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue { try pending(self.engine); const generation = self.engine.native_allocation_generation; return self.own(try checkedSince(self.engine, c.JS_PiBinaryOperator(self.engine.context, 0, left, right), generation)); }
    pub fn stringify(self: *Scope, value: c.JSValue) !c.JSValue { try pending(self.engine); const generation = self.engine.native_allocation_generation; return self.own(try checkedSince(self.engine, c.JS_ToString(self.engine.context, value), generation)); }
    pub fn truthy(self: *Scope, value: c.JSValue) bool { return c.JS_ToBool(self.engine.context, value) == 1; }
    pub fn equal(self: *Scope, left: c.JSValue, right: c.JSValue) bool { return c.JS_IsStrictEqual(self.engine.context, left, right); }
    pub fn positive(self: *Scope, value: c.JSValue) !bool { try pending(self.engine); const generation = self.engine.native_allocation_generation; const result = try self.own(try checkedSince(self.engine, c.JS_PiBinaryOperator(self.engine.context, 6, value, c.JS_NewInt32(self.engine.context, 0)), generation)); return self.truthy(result); }

};
fn takeCaptured(engine: *em.Engine) ?c.JSValue { const previous = engine.captured_exception; engine.captured_exception = null; return previous; }
/// The selected reason is owned outside both VM/Engine exception slots during
/// every native finalizer. First current fatal wins; ordinary cleanup never
/// erases it, and a later actual fatal promotes over an ordinary first error.
const Cleanup = struct {
    engine: *em.Engine,
    generation: u64,
    selected: ?c.JSValue = null,
    fatal: bool = false,
    fn offer(self: *Cleanup, reason: c.JSValue, current_event: bool) void {
        const fatal = current_event and currentFatal(self.engine, reason, self.generation);
        if (self.selected == null) { self.selected = reason; self.fatal = fatal; return; }
        if (!self.fatal and fatal) {
            const old = self.selected.?;
            self.selected = reason; self.fatal = true;
            self.engine.freeValue(old);
        } else self.engine.freeValue(reason);
    }
    fn collect(self: *Cleanup) void {
        while (true) {
            // Remove both slots before releasing either discarded owner.
            const event: ?c.JSValue = if (c.JS_HasException(self.engine.context)) c.JS_GetException(self.engine.context) else null;
            const captured = takeCaptured(self.engine);
            if (event == null and captured == null) return;
            if (event) |reason| self.offer(reason, true);
            if (captured) |reason| self.offer(reason, true);
        }
    }
    fn publish(self: *Cleanup) void {
        const reason = self.selected orelse return;
        self.selected = null;
        self.engine.native_exception_diagnostics_suppressed += 1;
        defer self.engine.native_exception_diagnostics_suppressed -= 1;
        _ = self.engine.checked(c.JS_Throw(self.engine.context, reason)) catch {};
    }
};
fn currentFatal(engine: *em.Engine, reason: c.JSValue, generation: u64) bool {
    const tag = c.pi_js_native_allocation_error_generation(reason);
    const distance = tag -% generation;
    const fresh = tag != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation;
    if (fresh) c.JS_SetUncatchableError(engine.context, reason);
    return fresh or c.JS_IsUncatchableError(reason);
}
/// first is externally owned while displaced native cleanup can raise events.
fn captureOwned(engine: *em.Engine, first: c.JSValue, generation: u64) void {
    var cleanup: Cleanup = .{ .engine = engine, .generation = generation };
    cleanup.offer(first, true);
    cleanup.collect();
    cleanup.publish();
}
pub fn current(engine: *em.Engine, owned: c.JSValue) !c.JSValue {
    return currentSince(engine, owned, engine.native_allocation_generation);
}
pub fn currentSince(engine: *em.Engine, owned: c.JSValue, generation: u64) !c.JSValue {
    if (!c.JS_HasException(engine.context)) return owned;
    const first = c.JS_GetException(engine.context);
    const previous = takeCaptured(engine);
    var cleanup: Cleanup = .{ .engine = engine, .generation = generation };
    cleanup.offer(first, true);
    // This is the pre-operation diagnostic, not a new producer event.
    if (previous) |value| cleanup.offer(value, false);
    cleanup.collect();
    engine.freeValue(owned);
    cleanup.collect();
    cleanup.publish();
    return error.JavaScriptException;
}
pub fn pending(engine: *em.Engine) !void { if (c.JS_HasException(engine.context)) { _ = try current(engine, c.pi_js_undefined()); unreachable; } }
pub fn checked(engine: *em.Engine, raw: c.JSValue) !c.JSValue {
    return checkedSince(engine, raw, engine.native_allocation_generation);
}
pub fn checkedSince(engine: *em.Engine, raw: c.JSValue, generation: u64) !c.JSValue {
    const value = try currentSince(engine, raw, generation);
    if (c.JS_IsException(value)) return error.SqliteCallbackExceptionWithoutCurrentReason;
    return value;
}
pub fn status(engine: *em.Engine, failed: bool) !void { try pending(engine); if (failed) return error.SqliteCallbackExceptionWithoutCurrentReason; }
pub fn statusSince(engine: *em.Engine, failed: bool, generation: u64) !void {
    if (c.JS_HasException(engine.context)) { _ = try currentSince(engine, c.pi_js_undefined(), generation); unreachable; }
    if (failed) return error.SqliteCallbackExceptionWithoutCurrentReason;
}
pub const af = @import("native_async_function.zig");
const body = @import("native_async_body.zig");
const js = @import("native_js_values.zig");
fn currentError(engine: *em.Engine, err: anyerror) anyerror {
    if (c.JS_HasException(engine.context)) { _ = current(engine, c.pi_js_undefined()) catch |event| return event; }
    return err;
}
pub fn guard(engine: *em.Engine, generation: u64, value: anyerror!c.JSValue) !c.JSValue {
    const owned = value catch |err| {
        const actual = currentError(engine, err);
        if (actual == error.JavaScriptException) {
            if (engine.captured_exception) |reason| try body.rethrowRecognizedAllocation(engine, reason, generation);
        }
        return actual;
    };
    return currentSince(engine, owned, generation) catch |err| { if (engine.captured_exception) |reason| try body.rethrowRecognizedAllocation(engine, reason, generation); return err; };
}
pub fn get(s: *Scope, receiver: c.JSValue, key: [*:0]const u8) !c.JSValue { const generation = s.engine.native_allocation_generation; return guard(s.engine, generation, s.get(receiver, key)); }
pub fn call(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue { const generation = s.engine.native_allocation_generation; return guard(s.engine, generation, s.call(function, receiver, args)); }
pub fn invoke(s: *Scope, receiver: c.JSValue, key: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return call(s, try get(s, receiver, key), receiver, args); }
pub fn global(s: *Scope, key: [*:0]const u8) !c.JSValue { const generation = s.engine.native_allocation_generation; return guard(s.engine, generation, s.global(key)); }
/// Actual GetPrototypeFromConstructor fallback does not consult global Object.
pub fn objectFor(s: *Scope, target: c.JSValue) !c.JSValue {
    const proto = try get(s, target, "prototype");
    return s.own(try checked(s.engine, if (c.JS_IsObject(proto)) c.JS_NewObjectProto(s.engine.context, proto) else c.JS_NewObject(s.engine.context)));
}
pub fn objectPrototype(s: *Scope) !c.JSValue {
    const object = try s.object();
    return s.own(try checked(s.engine, c.JS_GetPrototype(s.engine.context, object)));
}
pub fn construct(s: *Scope, function: c.JSValue, args: []const c.JSValue) !c.JSValue {
    try pending(s.engine);
    const generation = s.engine.native_allocation_generation;
    return s.own(try guard(s.engine, generation, checkedSince(s.engine, c.JS_CallConstructor(s.engine.context, function, @intCast(args.len), @constCast(args.ptr)), generation)));
}
pub fn set(s: *Scope, object: c.JSValue, key: [*:0]const u8, value: c.JSValue) !void {
    const generation = s.engine.native_allocation_generation;
    s.set(object, key, value) catch |err| { _ = try guard(s.engine, generation, @as(anyerror!c.JSValue, err)); };
}
pub fn caught(engine: *em.Engine, err: anyerror) !c.JSValue {
    const actual = currentError(engine, err);
    if (actual == error.OutOfMemory) return actual;
    if (actual == error.JavaScriptException) {
        if (engine.captured_exception) |reason| {
            if (c.JS_IsUncatchableError(reason)) return actual;
            engine.captured_exception = null;
            return reason;
        }
    }
    return js.typeError(engine, "Unexpected native Chord SQLite failure");
}
pub fn failure(engine: *em.Engine, err: anyerror) !af.Action { return .{ .thrown = try caught(engine, err) }; }
pub fn init(s: *Scope, state: *c.JSValue) !c.JSValue {
    try pending(s.engine);
    const owner = try s.own(try checked(s.engine, c.JS_NewObjectProto(s.engine.context, c.pi_js_null())));
    af.replaceState(s.engine, state, c.JS_DupValue(s.engine.context, owner));
    return owner;
}
pub fn wait(s: *Scope, owner: c.JSValue, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, stage: i32) !af.Action {
    try s.put(owner, "stage", c.JS_NewInt32(s.engine.context, stage));
    return .{ .awaited = c.JS_DupValue(s.engine.context, try call(s, function, receiver, args)) };
}
pub fn stage(s: *Scope, owner: c.JSValue) !i32 { var n: i32 = 0; if (c.JS_ToInt32(s.engine.context, &n, try s.get(owner, "stage")) < 0) return js.capture(s.engine); return n; }
pub fn rejected(s: *Scope, _: c.JSValue, _: c.JSValue) !void { try pending(s.engine); }
pub fn at(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
/// Only the new adapter's actual native callback boundary. Never classify DATA
/// or change shared callback policy. Promise reactions may otherwise consume a
/// direct host allocator exception before an outer native AF sees its origin.
pub fn callback(comptime operation: @import("native_node_function.zig").Callback) @import("native_node_function.zig").Callback {
    const Adapter = struct {
        fn call(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            try pending(engine);
            const generation = engine.native_allocation_generation;
            const prior = takeCaptured(engine);
            const result = operation(engine, receiver, args, roots) catch |err| {
                var selected: ?c.JSValue = if (c.JS_HasException(engine.context)) c.JS_GetException(engine.context) else if (err == error.JavaScriptException) takeCaptured(engine) else if (err == error.OutOfMemory and engine.captured_exception != null and currentFatal(engine, engine.captured_exception.?, generation)) takeCaptured(engine) else null;
                if (err == error.OutOfMemory and selected != null and c.JS_IsError(selected.?)) c.JS_SetUncatchableError(engine.context, selected.?);
                if (selected == null and err == error.OutOfMemory) { _ = engine.throwNativeOutOfMemory(); selected = c.JS_GetException(engine.context); c.JS_SetUncatchableError(engine.context, selected.?); }
                if (selected) |reason| {
                    if (prior) |old| engine.freeValue(old);
                    captureOwned(engine, reason, generation);
                    return guard(engine, generation, @as(anyerror!c.JSValue, error.JavaScriptException));
                }
                if (engine.captured_exception) |_| { if (prior) |old| engine.freeValue(old); } else engine.captured_exception = prior;
                if (err == error.JavaScriptException) return error.SqliteCallbackExceptionWithoutCurrentReason;
                return err;
            };
            const normalized = currentSince(engine, result, generation) catch |err| {
                const first = takeCaptured(engine).?;
                if (prior) |old| engine.freeValue(old);
                captureOwned(engine, first, generation);
                return guard(engine, generation, @as(anyerror!c.JSValue, err));
            };
            // The prior slot was detached before this operation. A newly
            // captured fatal therefore has a current producer, unlike history.
            if (engine.captured_exception) |reason| if (currentFatal(engine, reason, generation)) {
                engine.captured_exception = null;
                var cleanup: Cleanup = .{ .engine = engine, .generation = generation };
                cleanup.offer(reason, true);
                if (prior) |old| cleanup.offer(old, false);
                cleanup.collect();
                engine.freeValue(normalized);
                cleanup.collect();
                cleanup.publish();
                return error.JavaScriptException;
            };
            if (engine.captured_exception) |_| { if (prior) |old| engine.freeValue(old); } else engine.captured_exception = prior;
            return current(engine, normalized);
        }
    };
    return Adapter.call;
}
