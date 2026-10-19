//! Actual native object Global cells and native phantom-handle ownership.
//! The tests use real VM roots, weak records, finalizers and collection.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});

const Token = struct { probe: *Probe, index: usize };
const Reentry = enum { none, inspect, release_strong_again, dispose_weak };
const Probe = struct {
    context: ?*c.JSContext = null,
    initialized: bool = false,
    enabled: bool = false,
    class_id: c.JSClassID = 0,
    tokens: [16]Token = undefined,
    counts: [16]usize = @splat(0),
    events: [32]usize = undefined,
    event_count: usize = 0,
    overflow: bool = false,
    reasons: [2]c.JSValue = undefined,
    throw_reason: [16]?usize = @splat(null),
    observe_on: ?usize = null,
    observed: usize = 0,
    observed_undefined: bool = false,
    target_index: usize = 0,
    target_retired_at_observation: usize = 0,
    target_live_at_observation: bool = false,
    borrowed_target: c.JSValue = undefined,
    observed_cell: ?*c.JSNativeGlobal = null,
    dispose_slot: ?*?*c.JSNativeGlobal = null,
    reentry: Reentry = .none,
    reentered: bool = false,

    fn init(self: *Probe, f: *Fixture) !void {
        self.context = f.context.?;
        const nothing = c.pi_js_undefined();
        self.borrowed_target = nothing;
        for (&self.reasons) |*slot| slot.* = nothing;
        for (&self.tokens, 0..) |*token, index| token.* = .{ .probe = self, .index = index };
        self.initialized = true;
        _ = c.JS_NewClassID(f.runtime.?, &self.class_id);
        const class_definition: c.JSClassDef = .{
            .class_name = "Actual native Global holder",
            .finalizer = finalize,
        };
        try std.testing.expectEqual(@as(c_int, 0),
            c.JS_NewClass(f.runtime.?, self.class_id, &class_definition));
        self.enabled = true;
    }
    fn reason(self: *Probe, f: *Fixture, index: usize, fatal: bool) !c.JSValue {
        const value = try f.checked(c.JS_NewError(f.context.?));
        self.reasons[index] = value;
        if (fatal) c.JS_SetUncatchableError(f.context.?, value);
        return value; // borrowed from this real external root
    }
    fn disable(self: *Probe) void {
        self.enabled = false;
        self.observe_on = null;
        self.observed_cell = null;
        self.dispose_slot = null;
        if (self.initialized) self.borrowed_target = c.pi_js_undefined();
    }
    fn releaseReasons(self: *Probe) void {
        if (!self.initialized) return;
        const context = self.context orelse return;
        for (&self.reasons) |*slot| {
            const value = slot.*;
            slot.* = c.pi_js_undefined();
            c.JS_FreeValue(context, value);
        }
        self.context = null;
    }
    fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
        const rt = runtime orelse return;
        const raw_owner = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
        const token: *Token = @ptrCast(@alignCast(raw_owner));
        const self = token.probe;
        const index = token.index;
        _ = c.JS_SetOpaque(value, null);
        self.counts[index] += 1;
        if (self.event_count < self.events.len) {
            self.events[self.event_count] = index;
            self.event_count += 1;
        } else self.overflow = true;
        if (!self.enabled) return;
        if (self.observe_on != null and self.observe_on.? == index) {
            self.observe_on = null;
            self.observed += 1;
            self.target_retired_at_observation = self.counts[self.target_index];
            // This borrowed identity is read only while its actual finalizer
            // has not run. No JS root is added to change the collection cutpoint.
            if (self.target_retired_at_observation == 0 and !c.JS_IsUndefined(self.borrowed_target))
                self.target_live_at_observation = c.JS_IsLiveObject(rt, self.borrowed_target);
            const local = c.JS_PiNativeGlobalGet(self.observed_cell);
            self.observed_undefined = c.JS_IsUndefined(local);
            c.JS_FreeValueRT(rt, local);
            switch (self.reentry) {
                .none, .inspect => {},
                .release_strong_again => {
                    c.JS_PiNativeGlobalSetWeak(self.observed_cell);
                    c.JS_PiFreeNativeGlobal(self.observed_cell);
                    self.reentered = true;
                },
                .dispose_weak => {
                    const slot = self.dispose_slot orelse return;
                    const global = slot.*;
                    slot.* = null;
                    self.observed_cell = null;
                    c.JS_PiFreeNativeGlobal(global);
                    self.reentered = true;
                },
            }
        }
        if (self.throw_reason[index]) |reason_index| {
            self.throw_reason[index] = null;
            const context = self.context orelse return;
            // The event is this actual JS_Throw, not the retained DATA flag.
            _ = c.JS_Throw(context, c.JS_DupValue(context, self.reasons[reason_index]));
        }
    }
};

const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    probe: ?*Probe = null,
    cells: [16]?*c.JSNativeGlobal = @splat(null),

    fn init(self: *Fixture, probe: *Probe) !void {
        self.* = .{};
        self.runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer self.deinit();
        c.JS_SetMaxStackSize(self.runtime.?, 1024 * 1024);
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        self.probe = probe;
        try probe.init(self);
    }
    fn deinit(self: *Fixture) void {
        if (self.probe) |probe| probe.disable();
        if (self.runtime) |runtime| c.JS_SetMemoryLimit(runtime, 0);
        // Native Globals never cross JS_FreeRuntime, including early failures.
        for (&self.cells) |*slot| {
            const cell = slot.*;
            slot.* = null;
            c.JS_PiFreeNativeGlobal(cell);
        }
        if (self.probe) |probe| { self.probe = null; probe.releaseReasons(); }
        if (self.context) |context| {
            if (c.JS_HasException(context)) {
                const reason = c.JS_GetException(context);
                c.JS_FreeValue(context, reason);
            }
            self.context = null;
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, value);
            return error.ActualNativeGlobalControlException;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "actual-native-global.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    }
    fn run(self: *Fixture, source: [:0]const u8) !void {
        const value = try self.eval(source);
        c.JS_FreeValue(self.context.?, value);
    }
    fn drop(self: *Fixture, slot: *c.JSValue) void {
        const value = slot.*;
        slot.* = c.pi_js_undefined();
        c.JS_FreeValue(self.context.?, value);
    }
    fn object(self: *Fixture) !c.JSValue {
        return self.checked(c.JS_NewObject(self.context.?));
    }
    fn holder(self: *Fixture, index: usize) !c.JSValue {
        const probe = self.probe.?;
        const value = try self.checked(c.JS_NewObjectProtoClass(self.context.?,
            c.pi_js_null(), probe.class_id));
        _ = c.JS_SetOpaque(value, &probe.tokens[index]);
        return value;
    }
    fn putOwned(self: *Fixture, receiver: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        const result = c.JS_DefinePropertyValueStr(self.context.?, receiver, name, value, c.JS_PROP_C_W_E);
        try std.testing.expectEqual(@as(c_int, 1), result);
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn put(self: *Fixture, receiver: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        return self.putOwned(receiver, name, c.JS_DupValue(self.context.?, value));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        try self.put(global_object, name, value);
    }
    fn keep(self: *Fixture, value: c.JSValue) !usize {
        for (&self.cells, 0..) |*slot, index| {
            if (slot.* != null) continue;
            const cell = c.JS_PiNewNativeGlobal(self.context.?, value) orelse
                return error.ActualNativeGlobalCreationFailed;
            slot.* = cell; // attach before checking actual pending
            try std.testing.expect(!c.JS_HasException(self.context.?));
            return index;
        }
        return error.ActualNativeGlobalCellBudget;
    }
    fn release(self: *Fixture, index: usize) void {
        const cell = self.cells[index];
        self.cells[index] = null;
        c.JS_PiFreeNativeGlobal(cell);
    }
    fn weak(self: *Fixture, index: usize) !void {
        c.JS_PiNativeGlobalSetWeak(self.cells[index]);
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn expectEmpty(self: *Fixture, index: usize) !void {
        const local = c.JS_PiNativeGlobalGet(self.cells[index]);
        defer c.JS_FreeValue(self.context.?, local);
        try std.testing.expect(c.JS_IsUndefined(local));
    }
    fn pending(self: *Fixture) !c.JSValue {
        try std.testing.expect(c.JS_HasException(self.context.?));
        return c.JS_GetException(self.context.?);
    }
    fn collect(self: *Fixture) !void {
        c.JS_RunGC(self.runtime.?);
        try std.testing.expect(!c.JS_HasException(self.context.?));
        try std.testing.expect(!self.probe.?.overflow);
    }
    fn drain(self: *Fixture) !usize {
        var count: usize = 0;
        while (c.JS_IsJobPending(self.runtime.?)) {
            if (count == 16) return error.ActualNativeGlobalJobBudget;
            var context: ?*c.JSContext = null;
            const status = c.JS_ExecutePendingJob(self.runtime.?, &context);
            try std.testing.expectEqual(@as(c_int, 1), status);
            try std.testing.expect(context == self.context.?);
            try std.testing.expect(!c.JS_HasException(self.context.?));
            count += 1;
        }
        return count;
    }
};

test "VM native Global strong root retains actual typed array identity through collection" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    var view = try f.eval("new Uint8Array([7,11,19])"); defer f.drop(&view);
    const identity = view; // borrowed only while the cell below retains it
    try f.putOwned(view, "actualMarker", try f.holder(0));
    const index = try f.keep(view);
    f.drop(&view);
    try f.collect();
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    var local = c.JS_PiNativeGlobalGet(f.cells[index]); defer f.drop(&local);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, local, identity));
    try std.testing.expectEqual(@as(c_int, c.JS_TYPED_ARRAY_UINT8), c.JS_GetTypedArrayType(local));
    const element = try f.checked(c.JS_GetPropertyUint32(f.context.?, local, 1));
    defer c.JS_FreeValue(f.context.?, element);
    var number: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.context.?, &number, element));
    try std.testing.expectEqual(@as(i32, 11), number);
    f.drop(&local);
    f.release(index);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try f.collect();
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM native Global weak transition allocates nothing and clears before target finalizer" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    var target = try f.holder(0); defer f.drop(&target);
    const index = try f.keep(target);
    probe.observe_on = 0;
    probe.observed_cell = f.cells[index];
    probe.reentry = .inspect;
    f.drop(&target);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    c.JS_PiNativeGlobalSetWeak(f.cells[index]);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 1), probe.observed);
    try std.testing.expect(probe.observed_undefined);
    try f.expectEmpty(index);
    try f.weak(index);
    f.release(index);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM native Global Get holds only its explicit Local without kept objects" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    var target = try f.holder(0); defer f.drop(&target);
    const index = try f.keep(target);
    try f.weak(index);
    var local = c.JS_PiNativeGlobalGet(f.cells[index]); defer f.drop(&local);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, local, target));
    f.drop(&target);
    try f.collect();
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    f.drop(&local);
    // No ClearKeptObjects or intervening job is used to make this retire.
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try f.expectEmpty(index);
}

test "VM native Global cells keep independent strong and weak entitlements" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    var target = try f.holder(0); defer f.drop(&target);
    const weak_index = try f.keep(target);
    const first = try f.keep(target);
    const second = try f.keep(target);
    try f.weak(weak_index);
    f.drop(&target);
    f.release(first);
    try f.collect();
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    {
        const local = c.JS_PiNativeGlobalGet(f.cells[weak_index]);
        defer c.JS_FreeValue(f.context.?, local);
        try std.testing.expect(c.JS_IsObject(local));
    }
    f.release(second);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try f.expectEmpty(weak_index);
    f.release(weak_index);
    try f.collect();
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM native Global retained real property keeps a weak target live until replacement" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    const owner = try f.object(); defer c.JS_FreeValue(f.context.?, owner);
    var target = try f.holder(0); defer f.drop(&target);
    const index = try f.keep(target);
    try f.put(owner, "child", target);
    try f.weak(index);
    f.drop(&target);
    try f.collect();
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    {
        const local = c.JS_PiNativeGlobalGet(f.cells[index]);
        defer c.JS_FreeValue(f.context.?, local);
        try std.testing.expect(c.JS_IsObject(local));
    }
    try f.putOwned(owner, "child", c.pi_js_undefined());
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try f.expectEmpty(index);
}

test "VM native Global strong root survives a real cycle that weak transition then collects" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    var target = try f.holder(0); defer f.drop(&target);
    try f.put(target, "self", target);
    const index = try f.keep(target);
    f.drop(&target);
    try f.collect();
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    try f.weak(index);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    {
        const local = c.JS_PiNativeGlobalGet(f.cells[index]);
        defer c.JS_FreeValue(f.context.?, local);
        try std.testing.expect(c.JS_IsObject(local));
    }
    try f.collect();
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try f.expectEmpty(index);
    try f.collect();
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM native Global queued zero reference target cannot be resurrected by another finalizer" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    var parent = try f.object(); defer f.drop(&parent);
    var target = try f.holder(0); defer f.drop(&target);
    var observer = try f.holder(1); defer f.drop(&observer);
    try f.put(parent, "first", target);
    try f.put(parent, "second", observer);
    const index = try f.keep(target);
    try f.weak(index);
    probe.observe_on = 1;
    probe.observed_cell = f.cells[index];
    probe.borrowed_target = target;
    probe.target_index = 0;
    probe.reentry = .inspect;
    f.drop(&target);
    f.drop(&observer);
    // free_object retires the two properties in order under DECREF.
    // The second queues at the head, so it sees first queued with refcount 0.
    f.drop(&parent);
    try std.testing.expectEqual(@as(usize, 1), probe.observed);
    try std.testing.expectEqual(@as(usize, 0), probe.target_retired_at_observation);
    try std.testing.expect(probe.target_live_at_observation);
    try std.testing.expect(probe.observed_undefined);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, probe.events[0..probe.event_count]);
    try f.expectEmpty(index);
}

test "VM native Global doomed cyclic target is absent before its own finalizer" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    // Allocation order places observer first in the actual GC object list.
    var observer = try f.holder(0); defer f.drop(&observer);
    var target = try f.holder(1); defer f.drop(&target);
    try f.put(observer, "self", observer);
    try f.put(observer, "target", target);
    try f.put(target, "self", target);
    const index = try f.keep(target);
    try f.weak(index);
    probe.observe_on = 0;
    probe.observed_cell = f.cells[index];
    probe.borrowed_target = target;
    probe.target_index = 1;
    probe.reentry = .inspect;
    f.drop(&observer);
    f.drop(&target);
    try std.testing.expectEqual(@as(usize, 0), probe.event_count);
    try f.collect();
    // The target's own self edge still gives it positive refcount while
    // observer retires. Its marked cycle must nevertheless not be revived.
    try std.testing.expectEqual(@as(usize, 1), probe.observed);
    try std.testing.expectEqual(@as(usize, 0), probe.target_retired_at_observation);
    try std.testing.expect(probe.target_live_at_observation);
    try std.testing.expect(probe.observed_undefined);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, probe.events[0..probe.event_count]);
    try f.expectEmpty(index);
    try f.collect();
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[1]);
}

test "VM native Global reset coexists with actual WeakMap WeakRef and FinalizationRegistry" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    var target = try f.holder(0); defer f.drop(&target);
    var payload = try f.holder(1); defer f.drop(&payload);
    const first = try f.keep(target);
    try f.weak(first);
    try f.publish("target", target);
    try f.publish("payload", payload);
    try f.run(
        "globalThis.finalized=0;" ++
        "globalThis.map=new WeakMap([[target,payload]]);" ++
        "globalThis.ref=new WeakRef(target);" ++
        "globalThis.registry=new FinalizationRegistry(value=>{finalized+=value});" ++
        "registry.register(target,13);delete globalThis.target;delete globalThis.payload;"
    );
    const second = try f.keep(target);
    try f.weak(second);
    f.drop(&payload);
    // Only the real public WeakRef added a kept-object root during setup.
    c.JS_ClearKeptObjects(f.runtime.?);
    f.drop(&target);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[1]);
    try f.expectEmpty(first);
    try f.expectEmpty(second);
    try f.run("if(ref.deref()!==undefined)throw Error('public weak target retained');");
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try f.run("if(finalized!==13)throw Error('actual finalization registration lost');");
    f.release(first);
    f.release(second);
    try f.collect();
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[1]);
}

test "VM native Global releasing a weak cell removes only its own embedded link" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    var target = try f.holder(0); defer f.drop(&target);
    const first = try f.keep(target);
    const middle = try f.keep(target);
    const last = try f.keep(target);
    try f.weak(first);
    try f.weak(middle);
    try f.weak(last);
    f.release(middle);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    {
        const a = c.JS_PiNativeGlobalGet(f.cells[first]); defer c.JS_FreeValue(f.context.?, a);
        const b = c.JS_PiNativeGlobalGet(f.cells[last]); defer c.JS_FreeValue(f.context.?, b);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, a, target));
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, b, target));
    }
    f.drop(&target);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try f.expectEmpty(first);
    try f.expectEmpty(last);
}

test "VM native Global strong release publishes an empty cell before reentrant native cleanup" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    var target = try f.holder(0); defer f.drop(&target);
    const index = try f.keep(target);
    probe.observe_on = 0;
    probe.observed_cell = f.cells[index];
    probe.reentry = .release_strong_again;
    f.drop(&target);
    f.release(index);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 1), probe.observed);
    try std.testing.expect(probe.observed_undefined);
    try std.testing.expect(probe.reentered);
    try std.testing.expect(f.cells[index] == null);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try f.collect();
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM native Global weak transition permits actual finalizer disposal of the cell" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    var target = try f.holder(0); defer f.drop(&target);
    const index = try f.keep(target);
    probe.observe_on = 0;
    probe.observed_cell = f.cells[index];
    probe.dispose_slot = &f.cells[index];
    probe.reentry = .dispose_weak;
    f.drop(&target);
    c.JS_PiNativeGlobalSetWeak(f.cells[index]);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 1), probe.observed);
    try std.testing.expect(probe.observed_undefined);
    try std.testing.expect(probe.reentered);
    try std.testing.expect(f.cells[index] == null);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try f.collect();
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM native Global allocation failure borrows input and publishes no cell" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    var target = try f.holder(0); defer f.drop(&target);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const raw = c.JS_PiNewNativeGlobal(f.context.?, target);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    defer c.JS_PiFreeNativeGlobal(raw);
    try std.testing.expect(raw == null);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsNull(reason));
    f.drop(&target);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try f.collect();
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM native Global rejects primitives and holds revoked proxies without lookup" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    const string = try f.checked(c.JS_NewString(f.context.?, "not an object"));
    defer c.JS_FreeValue(f.context.?, string);
    const symbol = try f.checked(c.JS_NewSymbol(f.context.?, "native Global input", false));
    defer c.JS_FreeValue(f.context.?, symbol);
    const values = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_null(), c.JS_NewInt32(f.context.?, 9), string, symbol };
    for (values) |value| {
        const raw = c.JS_PiNewNativeGlobal(f.context.?, value);
        defer c.JS_PiFreeNativeGlobal(raw);
        try std.testing.expect(raw == null);
        const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsError(reason));
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
    }
    var proxy = try f.eval(
        "globalThis.visits=0;globalThis.rev=Proxy.revocable({}," ++
        "{get(){visits++;throw Error('proxy get')},getPrototypeOf(){visits++;throw Error('proxy prototype')}});" ++
        "rev.revoke();rev.proxy;"
    );
    defer f.drop(&proxy);
    const index = try f.keep(proxy);
    const local = c.JS_PiNativeGlobalGet(f.cells[index]); defer c.JS_FreeValue(f.context.?, local);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, local, proxy));
    try f.run("if(visits!==0)throw Error('native Global invoked a proxy');");
    try f.weak(index);
}

test "VM native Global creation preserves ordinary or fatal prior pending before validation" {
    for ([_]bool{ false, true }) |fatal| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
        var target = try f.holder(0); defer f.drop(&target);
        const reason = try probe.reason(&f, 0, fatal);
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const raw = c.JS_PiNewNativeGlobal(f.context.?, if (fatal) c.pi_js_null() else target);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        defer c.JS_PiFreeNativeGlobal(raw);
        try std.testing.expect(raw == null);
        const caught = try f.pending(); defer c.JS_FreeValue(f.context.?, caught);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, caught));
        try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(caught));
        try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
        f.drop(&target);
        try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    }
}

test "VM native Global weak and strong releases preserve the first actual pending reason" {
    for ([_]bool{ false, true }) |weak_release| {
        for ([_]bool{ false, true }) |first_fatal| {
            for ([_]bool{ false, true }) |later_fatal| {
                var probe: Probe = .{};
                var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
                var target = try f.holder(0); defer f.drop(&target);
                const index = try f.keep(target);
                const first = try probe.reason(&f, 0, first_fatal);
                const later = try probe.reason(&f, 1, later_fatal);
                probe.throw_reason[0] = 1;
                f.drop(&target);
                _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, first));
                if (weak_release) c.JS_PiNativeGlobalSetWeak(f.cells[index]) else f.release(index);
                try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
                try std.testing.expectEqual(@as(usize, 1), probe.event_count);
                const caught = try f.pending(); defer c.JS_FreeValue(f.context.?, caught);
                const expected = if (!first_fatal and later_fatal) later else first;
                try std.testing.expect(c.JS_IsStrictEqual(f.context.?, expected, caught));
                try std.testing.expectEqual(first_fatal or later_fatal, c.JS_IsUncatchableError(caught));
                if (weak_release) try f.expectEmpty(index);
            }
        }
    }
}

test "VM native Global flagged retained DATA and actual cleanup throw remain distinct" {
    {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
        var value = try f.checked(c.JS_NewError(f.context.?)); defer f.drop(&value);
        c.JS_SetUncatchableError(f.context.?, value);
        try f.putOwned(value, "actualMarker", try f.holder(0));
        const identity = value; // borrowed while the actual cell retains DATA
        const index = try f.keep(value);
        f.drop(&value);
        var local = c.JS_PiNativeGlobalGet(f.cells[index]); defer f.drop(&local);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, identity, local));
        try std.testing.expect(c.JS_IsUncatchableError(local));
        try std.testing.expect(!c.JS_HasException(f.context.?));
        f.drop(&local);
        f.release(index);
        try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
        try std.testing.expect(!c.JS_HasException(f.context.?));
    }
    for ([_]bool{ false, true }) |weak_release| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
        var target = try f.holder(0); defer f.drop(&target);
        const index = try f.keep(target);
        const reason = try probe.reason(&f, 0, true);
        probe.throw_reason[0] = 0;
        f.drop(&target);
        if (weak_release) c.JS_PiNativeGlobalSetWeak(f.cells[index]) else f.release(index);
        try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
        const caught = try f.pending(); defer c.JS_FreeValue(f.context.?, caught);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, caught));
        try std.testing.expect(c.JS_IsUncatchableError(caught));
    }
}

test "VM native Global cells retire before runtime while their native probes outlive cleanup" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(&probe); defer f.deinit();
    {
        var first = try f.holder(0); defer f.drop(&first);
        var second = try f.holder(1); defer f.drop(&second);
        _ = try f.keep(first);
        const weak_index = try f.keep(second);
        try f.publish("bindingDataView", second);
        try f.weak(weak_index);
        f.drop(&first);
        f.drop(&second);
    }
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[1]);
    f.deinit();
    try std.testing.expect(f.runtime == null and f.context == null);
    for (f.cells) |cell| try std.testing.expect(cell == null);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[1]);
    try std.testing.expect(!probe.overflow);
    // The native probe is still valid; no Global operation follows teardown.
    f.deinit();
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[1]);
}
