//! Runtime observation of actual JS_ThrowOutOfMemory occurrences.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    fn init(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer self.deinit();
        try std.testing.expectEqual(@as(u64, 0), c.JS_PiOutOfMemoryOccurrence(self.runtime.?));
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
    }
    fn deinit(self: *Fixture) void {
        if (self.runtime) |runtime| c.JS_SetMemoryLimit(runtime, 0);
        if (self.context) |context| {
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            _ = c.JS_PiCheckExecutionTermination(context);
            c.JS_PiCancelExecutionTermination(self.runtime.?);
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            self.context = null;
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, value);
            return error.OccurrenceSetupFailed;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "actual-oom-occurrence.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    }
    fn occurrence(self: *Fixture) u64 {
        return c.JS_PiOutOfMemoryOccurrence(self.runtime.?);
    }
    fn pending(self: *Fixture) !c.JSValue {
        try std.testing.expect(c.JS_HasException(self.context.?));
        return c.JS_GetException(self.context.?);
    }
    fn expectNewOom(self: *Fixture, before: u64, result: c.JSValue) !void {
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(self.occurrence() > before);
        const reason = try self.pending();
        defer c.JS_FreeValue(self.context.?, reason);
        // Limit1 prevents allocation of the reporting Error itself.
        try std.testing.expect(c.JS_IsNull(reason));
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
        try std.testing.expect(!c.JS_PiIsExecutionTermination(reason));
    }
};
const Probe = struct {
    retired: usize = 0,
    class_id: c.JSClassID = 0,
    fn init(self: *Probe, f: *Fixture) !void {
        self.* = .{};
        _ = c.JS_NewClassID(f.runtime.?, &self.class_id);
        const definition: c.JSClassDef = .{ .class_name = "Actual OOM consumed value", .finalizer = retire };
        try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(f.runtime.?, self.class_id, &definition));
    }
    fn holder(self: *Probe, f: *Fixture) !c.JSValue {
        const value = try f.checked(c.JS_NewObjectProtoClass(f.context.?, c.pi_js_null(), self.class_id));
        _ = c.JS_SetOpaque(value, self);
        return value;
    }
};
fn retire(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const raw_owner = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
    const probe: *Probe = @ptrCast(@alignCast(raw_owner));
    _ = c.JS_SetOpaque(value, null);
    probe.retired += 1;
}

test "VM OOM occurrence starts at zero and successful intrinsic allocations do not advance it" {
    var f: Fixture = .{};
    try f.init(); defer f.deinit();
    const before = f.occurrence();
    const object = try f.checked(c.JS_NewObject(f.context.?));
    defer c.JS_FreeValue(f.context.?, object);
    const text = try f.checked(c.JS_NewString(f.context.?, "actual successful allocation"));
    defer c.JS_FreeValue(f.context.?, text);
    const array = try f.checked(c.JS_NewArray(f.context.?));
    defer c.JS_FreeValue(f.context.?, array);
    try std.testing.expectEqual(@as(u64, 0), before);
    try std.testing.expectEqual(before, f.occurrence());
}
test "VM OOM occurrence records explicit actual report without changing its ordinary reason" {
    var f: Fixture = .{};
    try f.init(); defer f.deinit();
    const before = f.occurrence();
    const result = c.JS_ThrowOutOfMemory(f.context.?);
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expectEqual(before + 1, f.occurrence());
    const reason = try f.pending();
    defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsError(reason));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(reason));
}
test "VM OOM occurrence includes the real recursive reporting allocation failure" {
    var f: Fixture = .{};
    try f.init(); defer f.deinit();
    const before = f.occurrence();
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const result = c.JS_ThrowOutOfMemory(f.context.?);
    defer c.JS_FreeValue(f.context.?, result);
    const after = f.occurrence();
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try f.expectNewOom(before, result);
    // One direct report plus at least its actual Error allocation report.
    try std.testing.expect(after >= before + 2);
}
test "VM OOM occurrence brackets an actual failed string allocation" {
    var f: Fixture = .{};
    try f.init(); defer f.deinit();
    const bytes = "actual failed intrinsic string";
    const before = f.occurrence();
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const result = c.JS_NewStringLen(f.context.?, bytes.ptr, bytes.len);
    defer c.JS_FreeValue(f.context.?, result);
    const after = f.occurrence();
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try f.expectNewOom(before, result);
    try std.testing.expectEqual(after, f.occurrence());
}
test "VM OOM occurrence brackets an actual failed intrinsic object allocation" {
    var f: Fixture = .{};
    try f.init(); defer f.deinit();
    const before = f.occurrence();
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const result = c.JS_NewObjectProto(f.context.?, c.pi_js_null());
    defer c.JS_FreeValue(f.context.?, result);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try f.expectNewOom(before, result);
}
test "VM OOM occurrence array failure consumes its actual input owner exactly once" {
    var f: Fixture = .{}; var p: Probe = .{};
    try f.init(); defer f.deinit();
    try p.init(&f);
    const holder = try p.holder(&f);
    // JS_NewArrayFrom consumes every entry on both result paths.
    const values = [_]c.JSValue{holder};
    const before = f.occurrence();
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const result = c.JS_NewArrayFrom(f.context.?, 1, &values);
    defer c.JS_FreeValue(f.context.?, result);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try f.expectNewOom(before, result);
    try std.testing.expectEqual(@as(usize, 1), p.retired);
}
test "VM OOM occurrence failed new atom uses the actual reporting path" {
    var f: Fixture = .{};
    try f.init(); defer f.deinit();
    const text = "actual_vm_oom_occurrence_atom_20261020_never_in_intrinsics";
    const before = f.occurrence();
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const atom = c.JS_NewAtomLen(f.context.?, text.ptr, text.len);
    defer c.JS_FreeAtom(f.context.?, atom);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try std.testing.expectEqual(@as(c.JSAtom, c.JS_ATOM_NULL), atom);
    try std.testing.expect(f.occurrence() > before);
    const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsNull(reason));
}
test "VM OOM occurrence shared-shape insertion failure consumes its value and leaves no property" {
    var f: Fixture = .{}; var p: Probe = .{};
    try f.init(); defer f.deinit();
    try p.init(&f);
    const object = try f.checked(c.JS_NewObject(f.context.?));
    defer c.JS_FreeValue(f.context.?, object);
    // Retaining the second identical empty shape forces the actual clone.
    const shape_peer = try f.checked(c.JS_NewObject(f.context.?));
    defer c.JS_FreeValue(f.context.?, shape_peer);
    const atom = c.JS_NewAtom(f.context.?, "actual_oom_occurrence_shape_slot");
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(f.context.?, atom);
    const holder = try p.holder(&f);
    const before = f.occurrence();
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const status = c.JS_DefinePropertyValue(f.context.?, object, atom, holder, c.JS_PROP_C_W_E);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try std.testing.expectEqual(@as(c_int, -1), status);
    try std.testing.expect(f.occurrence() > before);
    const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsNull(reason));
    try std.testing.expectEqual(@as(usize, 1), p.retired);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_HasProperty(f.context.?, object, atom));
}
test "VM OOM occurrence raw runtime allocation failure without a report does not advance" {
    var f: Fixture = .{};
    try f.init(); defer f.deinit();
    const before = f.occurrence();
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const allocation = c.js_malloc_rt(f.runtime.?, 4096);
    defer c.js_free_rt(f.runtime.?, allocation);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try std.testing.expect(allocation == null);
    try std.testing.expectEqual(before, f.occurrence());
    try std.testing.expect(!c.JS_HasException(f.context.?));
}
test "VM OOM occurrence actual intrinsic overlength RangeError leaves the occurrence unchanged" {
    var f: Fixture = .{};
    try f.init(); defer f.deinit();
    const range_prototype = try f.eval("RangeError.prototype");
    defer c.JS_FreeValue(f.context.?, range_prototype);
    const input = [_]u16{'x'};
    const before = f.occurrence();
    // This actual UTF16 API rejects len before reading input or allocating.
    // JS_NewStringLen scans input first and cannot use a short-buffer probe.
    const result = c.JS_NewStringUTF16(f.context.?, &input, @as(usize, 1) << 30);
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expectEqual(before, f.occurrence());
    const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsError(reason));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    const prototype = c.JS_GetPrototype(f.context.?, reason);
    defer c.JS_FreeValue(f.context.?, prototype);
    try std.testing.expect(!c.JS_IsException(prototype));
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, prototype, range_prototype));
}
test "VM OOM occurrence observation preserves actual ordinary and fatal pending owners without allocation" {
    inline for (.{ false, true }) |fatal| {
        var f: Fixture = .{};
        try f.init(); defer f.deinit();
        const reason = try f.checked(c.JS_NewError(f.context.?));
        defer c.JS_FreeValue(f.context.?, reason);
        if (fatal) c.JS_SetUncatchableError(f.context.?, reason);
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
        const before = f.occurrence();
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const first = f.occurrence();
        const second = f.occurrence();
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        try std.testing.expectEqual(before, first);
        try std.testing.expectEqual(before, second);
        const actual = try f.pending(); defer c.JS_FreeValue(f.context.?, actual);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, actual, reason));
        try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(actual));
    }
}
test "VM OOM occurrence is runtime-wide while separate runtime histories stay independent" {
    var first: Fixture = .{}; var second: Fixture = .{};
    try first.init(); defer first.deinit();
    try second.init(); defer second.deinit();
    const other_context = c.JS_NewContext(first.runtime.?) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(other_context);
    const before_first = first.occurrence();
    const before_second = second.occurrence();
    const result = c.JS_ThrowOutOfMemory(other_context);
    defer c.JS_FreeValue(other_context, result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expectEqual(before_first + 1, first.occurrence());
    try std.testing.expectEqual(before_second, second.occurrence());
    try std.testing.expect(c.JS_HasException(other_context));
    const reason = c.JS_GetException(other_context);
    defer c.JS_FreeValue(other_context, reason);
    try std.testing.expect(c.JS_IsError(reason));
    try std.testing.expect(!c.JS_HasException(second.context.?));
}
test "VM OOM occurrence retained historical reason and private termination add no new occurrence" {
    var f: Fixture = .{};
    try f.init(); defer f.deinit();
    const result = c.JS_ThrowOutOfMemory(f.context.?);
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsException(result));
    const historical = try f.pending();
    defer c.JS_FreeValue(f.context.?, historical);
    c.JS_SetUncatchableError(f.context.?, historical);
    const before = f.occurrence();
    const success = try f.checked(c.JS_NewString(f.context.?, "successful next operation"));
    defer c.JS_FreeValue(f.context.?, success);
    try std.testing.expectEqual(before, f.occurrence());
    c.JS_PiRequestExecutionTermination(f.runtime.?);
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.context.?));
    try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
    try std.testing.expectEqual(before, f.occurrence());
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    try std.testing.expect(!c.JS_HasException(f.context.?));
}
