//! Additive real allocator/root-retirement controls; no Source output invented.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const owned = @import("extensions/native_sdk_owned_completion.zig");
const Prompt = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const Provider = @import("extensions/native_models_stream_scope.zig").Scope;
const Mode = enum { ordinary, guarded_raw, low_private };
const Growth = enum { initial_alloc, resize_and_alloc };

/// Counts the actual allocator calls while delegating ALL results to Zig's
/// real FailingAllocator. Both remap/resize refusal and fallback alloc failure
/// are observable; no synthetic error union replaces ArrayList.append.
const AllocatorProbe = struct {
    failing: *std.testing.FailingAllocator,
    allocs: usize = 0, resizes: usize = 0, remaps: usize = 0,
    fn allocator(self: *AllocatorProbe) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(context: *anyopaque, length: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *AllocatorProbe = @ptrCast(@alignCast(context)); self.allocs += 1;
        return self.failing.allocator().rawAlloc(length, alignment, ra);
    }
    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, length: usize, ra: usize) bool {
        const self: *AllocatorProbe = @ptrCast(@alignCast(context)); self.resizes += 1;
        return self.failing.allocator().rawResize(memory, alignment, length, ra);
    }
    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, length: usize, ra: usize) ?[*]u8 {
        const self: *AllocatorProbe = @ptrCast(@alignCast(context)); self.remaps += 1;
        return self.failing.allocator().rawRemap(memory, alignment, length, ra);
    }
    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *AllocatorProbe = @ptrCast(@alignCast(context)); self.failing.allocator().rawFree(memory, alignment, ra);
    }
    fn reset(self: *AllocatorProbe) void { self.allocs = 0; self.resizes = 0; self.remaps = 0; }
};
const Emission = struct {
    engine: *em.Engine, mode: Mode, ordinary: c.JSValue,
    first: ?c.JSValue = null, emitted: ?c.JSValue = null,
    calls: usize = 0, marked_at_birth: bool = false,
    generation_at_entry: u64 = 0,
    fn deinit(self: *Emission) void {
        if (self.first) |value| self.engine.freeValue(value);
        if (self.emitted) |value| self.engine.freeValue(value);
    }
};
fn emit(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *Emission = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    self.calls += 1; self.generation_at_entry = self.engine.native_allocation_generation;
    if (self.engine.native_allocation_exception) |first| self.first = c.JS_DupValue(self.engine.context, first);
    switch (self.mode) {
        .ordinary => _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, self.ordinary)),
        .guarded_raw => { _ = self.engine.throwNativeOutOfMemory(); },
        .low_private => {
            // Deliberately lower-level privileged native producer: the actual
            // VM creates B, then the embedding's private birth tag is applied.
            // This bypasses Engine's intentional first-fatal short circuit to
            // exercise a genuinely distinct raw pending B under held fatal A.
            // No user DATA/name/prototype is tagged and no fake B is observed.
            _ = c.JS_ThrowOutOfMemory(self.engine.context);
            const next = c.JS_GetException(self.engine.context);
            self.engine.native_allocation_generation +%= 1;
            if (self.engine.native_allocation_generation == 0) self.engine.native_allocation_generation = 1;
            c.pi_js_mark_native_allocation_error(next, self.engine.native_allocation_generation);
            _ = c.JS_Throw(self.engine.context, next);
        },
    }
    if (c.JS_HasException(self.engine.context)) {
        const current = c.JS_GetException(self.engine.context);
        self.marked_at_birth = c.JS_IsUncatchableError(current);
        self.emitted = c.JS_DupValue(self.engine.context, current);
        _ = c.JS_Throw(self.engine.context, current);
    }
}
fn carrier(self: *Emission) !c.JSValue {
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(self.engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "SDK actual incoming root carrier", .finalizer = emit };
    if (c.JS_NewClass(self.engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const value = try self.engine.checked(c.JS_NewObjectClass(self.engine.context, id));
    _ = c.JS_SetOpaque(value, self); return value;
}
fn oldData(engine: *em.Engine) !c.JSValue {
    _ = engine.throwNativeOutOfMemory();
    const value = c.JS_GetException(engine.context);
    c.JS_SetUncatchableError(engine.context, value);
    return value;
}
fn fill(comptime T: type, scope: *T, growth: Growth) !void {
    if (comptime @hasField(T, "inline_values")) {
        for (0..scope.inline_values.len) |_| _ = try owned.ownRoot(scope, c.pi_js_undefined());
    }
    if (growth == .resize_and_alloc) {
        try scope.values.ensureTotalCapacity(scope.engine.gpa, 8);
        const count = scope.values.capacity;
        for (0..count) |_| _ = try owned.ownRoot(scope, c.pi_js_undefined());
    }
}
fn appendFailure(comptime T: type, growth: Growth, mode: Mode, history: bool) !void {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var probe: AllocatorProbe = .{ .failing = &failing };
    const engine = try em.Engine.init(probe.allocator(), .{}); defer engine.deinit();
    var scope: T = .{ .engine = engine };
    try fill(T, &scope, growth);
    const ordinary = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(ordinary);
    var emission: Emission = .{ .engine = engine, .mode = mode, .ordinary = ordinary }; defer emission.deinit();
    const incoming = try carrier(&emission); // Exactly one owned reference.
    const historical: ?c.JSValue = if (history) try oldData(engine) else null;
    defer if (historical) |value| engine.freeValue(value);
    const old_tag = if (historical) |value| c.pi_js_native_allocation_error_generation(value) else 0;
    if (historical) |value| engine.captured_exception = c.JS_DupValue(engine.context, value);
    const before_generation = engine.native_allocation_generation;
    const original_len = scope.values.items.len;
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    probe.reset();
    const result = owned.ownRoot(&scope, incoming);
    failing.fail_index = std.math.maxInt(usize);
    failing.resize_fail_index = std.math.maxInt(usize);
    if (result) |_| return error.ExpectedActualAppendFailure else |err| try std.testing.expect(err == error.JavaScriptException);
    try std.testing.expect(failing.has_induced_failure and probe.allocs != 0);
    if (growth == .resize_and_alloc) try std.testing.expect(probe.remaps + probe.resizes != 0);
    try std.testing.expectEqual(original_len, scope.values.items.len);
    try std.testing.expectEqual(@as(usize, 1), emission.calls);
    const first = emission.first orelse return error.OomWasNotPublishedBeforeCarrierRelease;
    const actual = engine.captured_exception orelse return error.MissingActualRootAllocationError;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, actual));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    const first_tag = c.pi_js_native_allocation_error_generation(first);
    try std.testing.expect(first_tag != 0 and first_tag -% before_generation != 0);
    if (historical) |value| {
        try std.testing.expect(!c.JS_IsStrictEqual(engine.context, value, actual));
        try std.testing.expect(c.JS_IsUncatchableError(value));
        try std.testing.expectEqual(old_tag, c.pi_js_native_allocation_error_generation(value));
    }
    const emitted = emission.emitted orelse return error.MissingActualCarrierCleanupEvent;
    switch (mode) {
        .ordinary => try std.testing.expect(c.JS_IsStrictEqual(engine.context, ordinary, emitted)),
        .guarded_raw => {
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, emitted));
            try std.testing.expect(emission.marked_at_birth);
            try std.testing.expectEqual(emission.generation_at_entry, engine.native_allocation_generation);
        },
        .low_private => {
            try std.testing.expect(!c.JS_IsStrictEqual(engine.context, first, emitted));
            try std.testing.expect(!emission.marked_at_birth);
            try std.testing.expect(c.pi_js_native_allocation_error_generation(emitted) != 0);
        },
    }
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try owned.finishVoid(&scope, {});
}
test "SDK owned completion ownRoot actual alloc failure precedes sole incoming cleanup" {
    inline for (.{ Prompt, Provider }) |T| for ([_]Mode{ .ordinary, .guarded_raw, .low_private }) |mode|
        try appendFailure(T, .initial_alloc, mode, false);
}
test "SDK owned completion ownRoot actual resize fallback alloc failure retains first producer" {
    inline for (.{ Prompt, Provider }) |T| for ([_]Mode{ .ordinary, .guarded_raw, .low_private }) |mode|
        try appendFailure(T, .resize_and_alloc, mode, false);
}
test "SDK owned completion ownRoot historical flagged captured DATA cannot mask typed append OOM" {
    inline for (.{ Prompt, Provider }) |T| for ([_]Growth{ .initial_alloc, .resize_and_alloc }) |growth|
        try appendFailure(T, growth, .ordinary, true);
}
test "SDK owned completion ownRoot stored flagged private DATA stays data with unchanged history" {
    inline for (.{ Prompt, Provider }) |T| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const data = try oldData(engine); defer engine.freeValue(data);
        const tag = c.pi_js_native_allocation_error_generation(data);
        engine.captured_exception = c.JS_DupValue(engine.context, data);
        var scope: T = .{ .engine = engine };
        const value = try owned.ownRoot(&scope, c.JS_DupValue(engine.context, data));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, value, data));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, data, engine.captured_exception.?));
        try std.testing.expect(c.JS_IsUncatchableError(data));
        try std.testing.expectEqual(tag, c.pi_js_native_allocation_error_generation(data));
        try std.testing.expect(!c.JS_HasException(engine.context) and engine.native_fatal_invocation == null);
        try owned.finishVoid(&scope, {});
    }
}
test "SDK owned completion ownRoot pending ordinary entry owns reason before incoming retirement" {
    inline for (.{ Prompt, Provider }) |T| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var probe: AllocatorProbe = .{ .failing = &failing };
        const engine = try em.Engine.init(probe.allocator(), .{}); defer engine.deinit();
        var scope: T = .{ .engine = engine };
        const original = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(original);
        const later = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(later);
        var emission: Emission = .{ .engine = engine, .ordinary = later, .mode = .ordinary }; defer emission.deinit();
        const incoming = try carrier(&emission);
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, original));
        failing.fail_index = failing.alloc_index; probe.reset();
        const result = owned.ownRoot(&scope, incoming);
        failing.fail_index = std.math.maxInt(usize);
        if (result) |_| return error.ExpectedPendingEntry else |err| try std.testing.expect(err == error.JavaScriptException);
        try std.testing.expectEqual(@as(usize, 0), probe.allocs + probe.remaps + probe.resizes);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.captured_exception.?));
        try std.testing.expectEqual(@as(usize, 1), emission.calls);
        try owned.finishVoid(&scope, {});
    }
}
test "SDK owned completion ownRoot ordinary entry permits a new raw pending fatal during retirement" {
    inline for (.{ Prompt, Provider }) |T| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var scope: T = .{ .engine = engine };
        const original = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(original);
        const unused = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(unused);
        var emission: Emission = .{ .engine = engine, .ordinary = unused, .mode = .guarded_raw }; defer emission.deinit();
        const incoming = try carrier(&emission);
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, original));
        try std.testing.expectError(error.JavaScriptException, owned.ownRoot(&scope, incoming));
        const actual = engine.captured_exception orelse return error.MissingActualEntryCleanupFatal;
        const emitted = emission.emitted orelse return error.MissingActualEntryRawBirth;
        try std.testing.expect(!emission.marked_at_birth);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, emitted));
        try std.testing.expect(!c.JS_IsStrictEqual(engine.context, actual, original));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(actual) != 0);
        try owned.finishVoid(&scope, {});
    }
}
test "SDK owned completion ownRoot preserves an independently recorded actual fatal over diagnostic DATA" {
    inline for (.{ Prompt, Provider }) |T| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var probe: AllocatorProbe = .{ .failing = &failing };
        const engine = try em.Engine.init(probe.allocator(), .{}); defer engine.deinit();
        var scope: T = .{ .engine = engine };
        const data = try oldData(engine); defer engine.freeValue(data);
        const ordinary = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(ordinary);
        var emission: Emission = .{ .engine = engine, .ordinary = ordinary, .mode = .ordinary }; defer emission.deinit();
        const incoming = try carrier(&emission);
        var outer: em.Engine.NativeInvocation = .{};
        engine.enterNativeInvocation(&outer);
        defer if (outer.active) {
            const terminal = engine.leaveNativeInvocation(&outer, c.pi_js_undefined());
            if (c.JS_IsException(terminal) and c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
        };
        _ = engine.throwNativeOutOfMemoryFatal();
        const original = c.JS_GetException(engine.context); defer engine.freeValue(original);
        engine.captured_exception = c.JS_DupValue(engine.context, data);
        failing.fail_index = failing.alloc_index; probe.reset();
        const result = owned.ownRoot(&scope, incoming);
        failing.fail_index = std.math.maxInt(usize);
        if (result) |_| return error.ExpectedActualPriorFatal else |err| try std.testing.expect(err == error.JavaScriptException);
        try std.testing.expectEqual(@as(usize, 0), probe.allocs + probe.remaps + probe.resizes);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.captured_exception.?));
        try std.testing.expect(engine.native_fatal_invocation == &outer and outer.active);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, outer.first.?));
        try std.testing.expectError(error.JavaScriptException, engine.checked(engine.leaveNativeInvocation(&outer, c.pi_js_undefined())));
        try std.testing.expect(engine.native_fatal_invocation == null);
        try owned.finishVoid(&scope, {});
    }
}
