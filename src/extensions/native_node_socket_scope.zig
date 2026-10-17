//! Socket-local exception ownership across temporary/root retirement. This does
//! not change shared Scope/Engine policy. Historical diagnostics remain DATA.
const std = @import("std");
const js = @import("native_js_values.zig");
pub const c = js.c;
fn takeCaptured(engine: *js.Engine) ?c.JSValue { const result = engine.captured_exception; engine.captured_exception = null; return result; }
const Reason = struct { value: c.JSValue, fatal: bool };
pub const Cleanup = struct {
    engine: *js.Engine,
    generation: u64,
    selected: ?Reason = null,
    diagnostic: ?c.JSValue = null,
    fn fatal(self: *Cleanup, value: c.JSValue) bool {
        const tag = c.pi_js_native_allocation_error_generation(value);
        const distance = tag -% self.generation;
        const fresh = tag != 0 and distance != 0 and distance <= self.engine.native_allocation_generation -% self.generation;
        if (fresh and c.JS_IsError(value)) c.JS_SetUncatchableError(self.engine.context, value);
        return fresh or c.JS_IsUncatchableError(value);
    }
    fn rememberProducer(self: *Cleanup, reason: c.JSValue) void {
        // A raw finalizer can throw before Engine.checked observes its event.
        // Publish that ACTUAL fatal producer before discarding any other root.
        // No flag on historical diagnostic data reaches this path.
        const invocation = self.engine.native_fatal_invocation orelse return;
        if (invocation.first != null) return;
        _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason));
        _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
        self.engine.freeValue(c.JS_GetException(self.engine.context));
    }
    fn selectEvent(self: *Cleanup, owned: c.JSValue) ?c.JSValue {
        const next: Reason = .{ .value = owned, .fatal = self.fatal(owned) };
        if (next.fatal) self.rememberProducer(owned);
        if (self.selected) |prior| {
            if (!prior.fatal and next.fatal) { self.selected = next; return prior.value; }
            return owned;
        }
        self.selected = next; return null;
    }
    pub fn event(self: *Cleanup, owned: c.JSValue) void {
        if (self.selectEvent(owned)) |old| { self.engine.freeValue(old); self.collect(); }
    }
    pub fn history(self: *Cleanup, owned: c.JSValue) void {
        // A previous diagnostic cannot compete with a current ordinary error,
        // even if that DATA value retains an old uncatchable flag/private tag.
        if (self.diagnostic) |old| { self.diagnostic = owned; self.engine.freeValue(old); self.collect(); }
        else self.diagnostic = owned;
    }
    pub fn collect(self: *Cleanup) void {
        while (c.JS_HasException(self.engine.context) or self.engine.captured_exception != null) {
            const pending: ?c.JSValue = if (c.JS_HasException(self.engine.context)) c.JS_GetException(self.engine.context) else null;
            const captured = takeCaptured(self.engine);
            // Both existing events are owned/selected BEFORE either discarded
            // value is freed; every subsequent destructor is drained separately.
            const discard_pending = if (pending) |value| self.selectEvent(value) else null;
            const discard_captured = if (captured) |value| self.selectEvent(value) else null;
            if (discard_pending) |old| { self.engine.freeValue(old); self.collect(); }
            if (discard_captured) |old| { self.engine.freeValue(old); self.collect(); }
        }
    }
    pub fn captureEntry(self: *Cleanup, err: ?anyerror) void {
        const pending: ?c.JSValue = if (c.JS_HasException(self.engine.context)) c.JS_GetException(self.engine.context) else null;
        const captured = takeCaptured(self.engine);
        if (pending) |value| self.event(value);
        if (captured) |value| {
            if (err == error.JavaScriptException) self.event(value) else self.history(value);
        }
        self.collect();
    }
    pub fn release(self: *Cleanup, owned: c.JSValue) void {
        self.captureEntry(null);
        self.engine.freeValue(owned); self.collect();
    }
    pub fn publish(self: *Cleanup) void {
        if (self.selected != null) {
            if (self.diagnostic) |old| { self.diagnostic = null; self.engine.freeValue(old); self.collect(); }
            const chosen = self.selected.?; self.selected = null;
            if (chosen.fatal and c.JS_IsError(chosen.value)) c.JS_SetUncatchableError(self.engine.context, chosen.value);
            // Leave the actual event pending. Success+cleanup-error must not be
            // turned into mere diagnostic data by a later successful return.
            _ = c.JS_Throw(self.engine.context, chosen.value);
        } else if (self.diagnostic) |history_value| {
            self.diagnostic = null; self.engine.captured_exception = history_value;
        }
    }
};
pub const Scope = struct {
    engine: *js.Engine,
    inline_values: [32]c.JSValue = undefined,
    inline_count: usize = 0,
    values: std.ArrayList(c.JSValue) = .empty,
    unwind: ?c.JSValue = null,
    pub fn captureUnwind(self: *Scope, err: anyerror) void {
        if (err != error.JavaScriptException or self.unwind != null) return;
        self.unwind = if (c.JS_HasException(self.engine.context)) c.JS_GetException(self.engine.context) else takeCaptured(self.engine);
    }
    pub fn deinit(self: *Scope) void {
        self.engine.native_exception_diagnostics_suppressed += 1;
        defer self.engine.native_exception_diagnostics_suppressed -= 1;
        var cleanup: Cleanup = .{ .engine = self.engine, .generation = self.engine.native_allocation_generation };
        if (self.unwind) |value| cleanup.event(value);
        self.unwind = null;
        cleanup.captureEntry(null);
        for (self.inline_values[0..self.inline_count]) |value| cleanup.release(value);
        for (self.values.items) |value| cleanup.release(value);
        self.values.deinit(self.engine.gpa);
        cleanup.collect(); cleanup.publish();
    }
    pub fn own(self: *Scope, raw: c.JSValue) !c.JSValue {
        return self.ownSince(raw, self.engine.native_allocation_generation);
    }
    /// The generation belongs to the actual operation, BEFORE it can return
    /// an owned value plus a pending event. Shared checked would retire raw
    /// before this local first-ordinary/first-fatal reducer sees its finalizer.
    pub fn ownSince(self: *Scope, raw: c.JSValue, generation: u64) !c.JSValue {
        const pending = c.JS_HasException(self.engine.context);
        if (pending or c.JS_IsException(raw)) {
            var cleanup: Cleanup = .{ .engine = self.engine, .generation = generation };
            // A raw VM sentinel is not provenance for an older captured slot.
            // Actual callback error-union unwinds use captureUnwind instead.
            cleanup.captureEntry(null);
            cleanup.release(raw);
            cleanup.publish();
            if (c.JS_HasException(self.engine.context)) return error.JavaScriptException;
            // An exception sentinel without an actual reason is delegated to
            // the genuine Engine missing-event boundary, never old DATA flags.
        }
        const value = try self.engine.checked(raw);
        if (self.inline_count < self.inline_values.len) { self.inline_values[self.inline_count] = value; self.inline_count += 1; return value; }
        self.values.append(self.engine.gpa, value) catch |err| {
            var cleanup: Cleanup = .{ .engine = self.engine, .generation = self.engine.native_allocation_generation };
            cleanup.release(value); cleanup.publish(); return err;
        };
        return value;
    }
    pub fn get(self: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.ownSince(c.JS_GetPropertyStr(self.engine.context, receiver, name), generation); }
    pub fn global(self: *Scope, name: [*:0]const u8) !c.JSValue {
        try self.engine.checkNativeEntry();
        const generation = self.engine.native_allocation_generation;
        const root = try self.ownSince(c.JS_GetGlobalObject(self.engine.context), generation); return self.get(root, name);
    }
    pub fn text(self: *Scope, value: []const u8) !c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.ownSince(c.JS_NewStringLen(self.engine.context, value.ptr, value.len), generation); }
    pub fn object(self: *Scope) !c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.ownSince(c.JS_NewObject(self.engine.context), generation); }
    pub fn array(self: *Scope) !c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.ownSince(c.JS_NewArray(self.engine.context), generation); }
    pub fn call(self: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.ownSince(c.JS_Call(self.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)), generation); }
    pub fn construct(self: *Scope, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.ownSince(c.JS_CallConstructor(self.engine.context, constructor, @intCast(args.len), @constCast(args.ptr)), generation); }
    pub fn receiver(self: *Scope, target: c.JSValue) !c.JSValue {
        const prototype = try self.get(target, "prototype");
        const generation = self.engine.native_allocation_generation;
        return self.ownSince(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(self.engine.context, prototype) else c.JS_NewObject(self.engine.context), generation);
    }
    pub fn getIndex(self: *Scope, target: c.JSValue, index_value: u32) !c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.ownSince(c.JS_GetPropertyUint32(self.engine.context, target, index_value), generation); }
    pub fn invoke(self: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { const function = try self.get(receiver, name); return self.call(function, receiver, args); }
    pub fn put(self: *Scope, receiver: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try self.engine.checkNativeEntry(); const result = c.JS_DefinePropertyValueStr(self.engine.context, receiver, name, c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E); try self.engine.checkNativeEntry(); if (result < 0) return js.capture(self.engine); }
    pub fn set(self: *Scope, receiver: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try self.engine.checkNativeEntry(); const result = c.JS_SetPropertyStr(self.engine.context, receiver, name, c.JS_DupValue(self.engine.context, value)); try self.engine.checkNativeEntry(); if (result < 0) return js.capture(self.engine); }
    pub fn index(self: *Scope, receiver: c.JSValue, index_value: u32, value: c.JSValue) !void { try self.engine.checkNativeEntry(); const result = c.JS_DefinePropertyValueUint32(self.engine.context, receiver, index_value, c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E); try self.engine.checkNativeEntry(); if (result < 0) return js.capture(self.engine); }
    pub fn concat(self: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.ownSince(c.JS_PiBinaryOperator(self.engine.context, 0, left, right), generation); }
    pub fn stringify(self: *Scope, value: c.JSValue) !c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.ownSince(c.JS_ToString(self.engine.context, value), generation); }
    pub fn truthy(self: *Scope, value: c.JSValue) bool { return c.JS_ToBool(self.engine.context, value) == 1; }
    pub fn equal(self: *Scope, left: c.JSValue, right: c.JSValue) bool { return c.JS_IsStrictEqual(self.engine.context, left, right); }
    pub fn positive(self: *Scope, value: c.JSValue) !bool { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.truthy(try self.ownSince(c.JS_PiBinaryOperator(self.engine.context, 6, value, c.JS_NewInt32(self.engine.context, 0)), generation)); }
};

pub const Testing = if (@import("builtin").is_test) struct {
    const Payload = struct { engine: *js.Engine, reason: c.JSValue, calls: *usize, armed: *bool };
    fn finalized(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
        const payload: *Payload = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
        const engine = payload.engine; const reason = payload.reason; const armed = payload.armed.*;
        payload.calls.* += 1; engine.gpa.destroy(payload);
        if (armed) { _ = c.JS_Throw(engine.context, reason); } else c.JS_FreeValueRT(runtime, reason);
    }
    fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
        const payload: *Payload = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
        c.JS_MarkValue(runtime, payload.reason, visitor);
    }
    pub fn witness(engine: *js.Engine, reason: c.JSValue, calls: *usize, armed: *bool) !c.JSValue {
        var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
        const definition: c.JSClassDef = .{ .class_name = "Owned Socket receiver cleanup witness", .finalizer = finalized, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
        const object = try engine.checked(c.JS_NewObjectClass(engine.context, id)); errdefer engine.freeValue(object);
        const payload = try engine.gpa.create(Payload);
        payload.* = .{ .engine = engine, .reason = c.JS_DupValue(engine.context, reason), .calls = calls, .armed = armed };
        _ = c.JS_SetOpaque(object, payload); return object;
    }
} else struct {};

test "raw owned Socket result retains initial pending and fresh cleanup OOM before shared checked" {
    const Fixture = struct {
        engine: *js.Engine,
        allocator: *std.testing.FailingAllocator,
        primary: c.JSValue,
        cleanup: c.JSValue,
        initial_oom: ?c.JSValue = null,
        cleanup_oom: ?c.JSValue = null,
        witness: ?c.JSValue = null,
        initial_mode: u8,
        cleanup_mode: u8,
        finalized: usize = 0,
        calls: usize = 0,
        body_calls: usize = 0,
        armed: bool = true,
        unexpected_allocation_success: bool = false,
        fn rawOom(self: *@This()) void {
            const prior = self.allocator.fail_index;
            self.allocator.fail_index = self.allocator.alloc_index;
            const allocated = self.engine.gpa.alloc(u8, 1) catch {
                self.allocator.fail_index = prior;
                // Deliberately the NONFATAL private producer. The local
                // pre-operation generation must identify this current event.
                _ = self.engine.throwNativeOutOfMemory();
                return;
            };
            self.allocator.fail_index = prior;
            self.engine.gpa.free(allocated); self.unexpected_allocation_success = true;
        }
        fn from(value: c.JSValue) *@This() {
            return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
        }
        fn raw(_: ?*c.JSContext, receiver_value: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const self = from(receiver_value); self.calls += 1;
            const result = self.witness.?; self.witness = null;
            if (self.initial_mode == 2) {
                self.rawOom();
                const actual = c.JS_GetException(self.engine.context);
                self.initial_oom = c.JS_DupValue(self.engine.context, actual);
                _ = c.JS_Throw(self.engine.context, actual);
            } else _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, self.primary));
            return result; // Genuine owned success PLUS actual pending event.
        }
        fn final(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
            const self = from(value); self.finalized += 1;
            if (!self.armed) return;
            if (self.cleanup_mode == 2) {
                self.rawOom();
                const actual = c.JS_GetException(self.engine.context);
                self.cleanup_oom = c.JS_DupValue(self.engine.context, actual);
                _ = c.JS_Throw(self.engine.context, actual);
            } else _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, self.cleanup));
        }
        fn body(_: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            from(roots[0]).body_calls += 1; return c.pi_js_undefined();
        }
    };
    // get, call and actual newTarget.prototype receiver construction all
    // execute the unwrapped C getter; no Bfb callable pre-normalizes its result.
    for ([_]u8{ 0, 1, 2, 3 }) |operation| for ([_]u8{ 0, 1, 2 }) |initial_mode| for ([_]u8{ 0, 1, 2 }) |cleanup_mode| {
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try js.Engine.init(allocator.allocator(), .{}); defer engine.deinit();
        const primary = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(primary);
        const cleanup = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(cleanup);
        if (initial_mode == 1) c.JS_SetUncatchableError(engine.context, primary);
        if (cleanup_mode == 1) c.JS_SetUncatchableError(engine.context, cleanup);
        var fixture: Fixture = .{ .engine = engine, .allocator = &allocator, .primary = primary, .cleanup = cleanup, .initial_mode = initial_mode, .cleanup_mode = cleanup_mode };
        defer {
            fixture.armed = false;
            if (fixture.witness) |value| engine.freeValue(value);
            if (fixture.initial_oom) |value| engine.freeValue(value);
            if (fixture.cleanup_oom) |value| engine.freeValue(value);
        }
        var witness_id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &witness_id);
        const witness_def: c.JSClassDef = .{ .class_name = "Raw owned Socket result cleanup control", .finalizer = Fixture.final };
        if (c.JS_NewClass(engine.runtime, witness_id, &witness_def) < 0) return error.OutOfMemory;
        fixture.witness = try engine.checked(c.JS_NewObjectClass(engine.context, witness_id));
        _ = c.JS_SetOpaque(fixture.witness.?, &fixture);
        var owner_id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &owner_id);
        const owner_def: c.JSClassDef = .{ .class_name = "Raw Socket operation control owner" };
        if (c.JS_NewClass(engine.runtime, owner_id, &owner_def) < 0) return error.OutOfMemory;
        const target = try engine.checked(c.JS_NewObjectClass(engine.context, owner_id)); defer engine.freeValue(target);
        _ = c.JS_SetOpaque(target, &fixture);
        const getter = try engine.checked(c.JS_NewCFunction(engine.context, Fixture.raw, "raw owned getter", 0)); defer engine.freeValue(getter);
        const atom = c.JS_NewAtom(engine.context, "prototype"); defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, target, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
        // Actual construction with a Proxy newTarget exercises the complete
        // native callable receiver path, not only the local receiver helper.
        const constructor = try @import("native_node_socket_function.zig").create(engine, "OwnedRawNewTargetControl", 0, Fixture.body, &.{target}); defer engine.freeValue(constructor);
        if (c.JS_DefinePropertyValueStr(engine.context, target, "get", c.JS_DupValue(engine.context, getter), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        const proxy = try js.builtin(engine, "Proxy", &.{ constructor, target }); defer engine.freeValue(proxy);
        const history = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(history);
        c.JS_SetUncatchableError(engine.context, history);
        engine.captured_exception = c.JS_DupValue(engine.context, history);
        const generation = engine.native_allocation_generation;
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        {
            var scope: Scope = .{ .engine = engine }; defer scope.deinit();
            if (operation == 0) try std.testing.expectError(error.JavaScriptException, scope.get(target, "prototype"))
            else if (operation == 1) try std.testing.expectError(error.JavaScriptException, scope.call(getter, target, &.{}))
            else if (operation == 2) try std.testing.expectError(error.JavaScriptException, scope.receiver(target))
            else try std.testing.expectError(error.JavaScriptException, scope.ownSince(c.JS_CallConstructor2(engine.context, constructor, proxy, 0, null), generation));
        }
        try std.testing.expect(c.JS_HasException(engine.context));
        const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
        const expected = if (initial_mode == 2) fixture.initial_oom.? else if (initial_mode == 1 or cleanup_mode == 0) primary else if (cleanup_mode == 1) cleanup else fixture.cleanup_oom.?;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, expected));
        try std.testing.expectEqual(initial_mode != 0 or cleanup_mode != 0, c.JS_IsUncatchableError(actual));
        try std.testing.expectEqual(@as(usize, 1), fixture.calls);
        try std.testing.expectEqual(@as(usize, 1), fixture.finalized);
        try std.testing.expectEqual(@as(usize, 0), fixture.body_calls);
        // Bfb's real invocation already retains an initial fatal producer in
        // operation3, so its raw OOM producer must not manufacture replacement C.
        try std.testing.expectEqual(generation + @as(u64, if (initial_mode == 2) 1 else 0) + @as(u64, if (cleanup_mode == 2 and !(operation == 3 and initial_mode != 0)) 1 else 0), engine.native_allocation_generation);
        try std.testing.expect(!fixture.unexpected_allocation_success);
        if (initial_mode == 2 or cleanup_mode == 2) try std.testing.expect(allocator.has_induced_failure);
        try std.testing.expect(engine.native_fatal_invocation == null);
    };
}
