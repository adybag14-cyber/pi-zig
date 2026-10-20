//! Actual consuming Boolean branch and computed-property-key retirement.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    progress: c.JSValue = undefined,
    primitive_atom: c.JSAtom = c.JS_ATOM_NULL,
    key_atom: c.JSAtom = c.JS_ATOM_NULL,
    fn init(self: *Fixture) !void {
        self.* = .{ .progress = c.pi_js_undefined() };
        self.runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer self.deinit();
        c.JS_SetMaxStackSize(self.runtime.?, 1024 * 1024);
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        self.progress = try self.eval(
            \\globalThis.progress = {after:false,caught:false,finalized:false,branch:false,bodyCalls:0,valueCalls:0};
            \\progress
        );
        const symbol = try self.eval("Symbol.toPrimitive");
        defer c.JS_FreeValue(self.context.?, symbol);
        self.primitive_atom = c.JS_ValueToAtom(self.context.?, symbol);
        if (self.primitive_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        const function = try self.checked(c.JS_NewCFunction(self.context.?, take, "take", 0));
        defer c.JS_FreeValue(self.context.?, function);
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValueStr(self.context.?,
            global_object, "take", c.JS_DupValue(self.context.?, function), c.JS_PROP_C_W_E));
    }
    fn deinit(self: *Fixture) void {
        if (self.runtime) |runtime| c.JS_SetMemoryLimit(runtime, 0);
        if (self.context) |context| {
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            _ = c.JS_PiCheckExecutionTermination(context);
            c.JS_PiCancelExecutionTermination(self.runtime.?);
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            c.JS_FreeAtom(context, self.key_atom); self.key_atom = c.JS_ATOM_NULL;
            c.JS_FreeAtom(context, self.primitive_atom); self.primitive_atom = c.JS_ATOM_NULL;
            const progress = self.progress; self.progress = c.pi_js_undefined();
            c.JS_FreeValue(context, progress);
            self.context = null;
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, value);
            return error.ConsumingOperandSetupFailed;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "actual-consuming-operand.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    }
    fn compile(self: *Fixture, comptime statements: []const u8) !c.JSValue {
        return self.eval("(function(){try{" ++ statements ++
            "}catch(reason){progress.caught=true;return reason;}" ++
            "finally{progress.finalized=true;}})");
    }
    fn ownBool(self: *Fixture, name: [*:0]const u8, expected: bool) !void {
        // The actual plain record and these primitive own fields predate entry.
        const value = c.JS_GetPropertyStr(self.context.?, self.progress, name);
        defer c.JS_FreeValue(self.context.?, value);
        try std.testing.expect(c.JS_IsBool(value));
        try std.testing.expectEqual(@as(c_int, @intFromBool(expected)), c.JS_ToBool(self.context.?, value));
    }
    fn ownNumber(self: *Fixture, name: [*:0]const u8, expected: i32) !void {
        const value = c.JS_GetPropertyStr(self.context.?, self.progress, name);
        defer c.JS_FreeValue(self.context.?, value);
        try self.number(value, expected);
    }
    fn number(self: *Fixture, value: c.JSValue, expected: i32) !void {
        try std.testing.expect(c.JS_IsNumber(value));
        var actual: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(self.context.?, &actual, value));
        try std.testing.expectEqual(expected, actual);
    }
    fn failedProgress(self: *Fixture, caught: bool) !void {
        try self.ownBool("after", false);
        try self.ownBool("caught", caught);
        try self.ownBool("finalized", caught);
        try self.ownBool("branch", false);
        try self.ownNumber("valueCalls", 0);
    }
};
const Action = enum { none, first, second, terminate };
const Probe = struct {
    context: ?*c.JSContext = null,
    enabled: bool = false,
    class_id: c.JSClassID = 0,
    next: c.JSValue = undefined,
    key: c.JSValue = undefined,
    string_hint: c.JSValue = undefined,
    reasons: [2]c.JSValue = undefined,
    action: Action = .none,
    throw_conversion: bool = false,
    retired: usize = 0,
    taken: usize = 0,
    conversions: usize = 0,
    original_receiver: bool = false,
    string_hint_seen: bool = false,
    fn init(self: *Probe, f: *Fixture) !void {
        self.* = .{ .context = f.context.?, .next = c.pi_js_undefined(),
            .key = c.pi_js_undefined(), .string_hint = c.pi_js_undefined(),
            .reasons = .{c.pi_js_undefined(), c.pi_js_undefined()} };
        errdefer self.disable();
        _ = c.JS_NewClassID(f.runtime.?, &self.class_id);
        const definition: c.JSClassDef = .{ .class_name = "Actual consuming operand", .finalizer = retire };
        try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(f.runtime.?, self.class_id, &definition));
        for (&self.reasons) |*slot| slot.* = try f.checked(c.JS_NewError(f.context.?));
        self.string_hint = try f.checked(c.JS_NewString(f.context.?, "string"));
        c.JS_SetContextOpaque(f.context.?, self);
        self.enabled = true;
    }
    fn disable(self: *Probe) void {
        self.enabled = false;
        const context = self.context orelse return;
        self.context = null;
        c.JS_SetContextOpaque(context, null);
        for ([_]*c.JSValue{ &self.next, &self.key, &self.string_hint }) |slot| {
            const value = slot.*; slot.* = c.pi_js_undefined(); c.JS_FreeValue(context, value);
        }
        for (&self.reasons) |*slot| {
            const value = slot.*; slot.* = c.pi_js_undefined(); c.JS_FreeValue(context, value);
        }
    }
    fn from(context: *c.JSContext) ?*Probe {
        const raw_owner = c.JS_GetContextOpaque(context) orelse return null;
        return @ptrCast(@alignCast(raw_owner));
    }
    fn holder(self: *Probe, f: *Fixture) !c.JSValue {
        const value = try f.checked(c.JS_NewObjectProtoClass(f.context.?, c.pi_js_null(), self.class_id));
        _ = c.JS_SetOpaque(value, self);
        return value;
    }
    fn prepare(self: *Probe, f: *Fixture, symbol_key: bool, flagged_data: bool) !void {
        self.key = if (symbol_key) try f.eval("Symbol('selected')") else
            try f.checked(c.JS_NewString(f.context.?, "selected"));
        f.key_atom = c.JS_ValueToAtom(f.context.?, self.key);
        if (f.key_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        if (flagged_data) {
            self.next = try f.checked(c.JS_NewError(f.context.?));
            c.JS_SetUncatchableError(f.context.?, self.next);
            const marker = try self.holder(f);
            try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValueStr(f.context.?,
                self.next, "nativeOwner", marker, c.JS_PROP_C_W_E));
        } else {
            self.next = try self.holder(f);
        }
        const conversion = try f.checked(c.JS_NewCFunction(f.context.?, toPrimitive, "actualKey", 1));
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValue(f.context.?,
            self.next, f.primitive_atom, conversion, c.JS_PROP_C_W_E));
    }
    fn fatal(self: *Probe, index: usize) void {
        c.JS_SetUncatchableError(self.context.?, self.reasons[index]);
    }
};
fn start(f: *Fixture, p: *Probe) !void {
    try f.init();
    errdefer f.deinit();
    try p.init(f);
}
fn retire(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const raw_owner = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
    const p: *Probe = @ptrCast(@alignCast(raw_owner));
    _ = c.JS_SetOpaque(value, null);
    p.retired += 1;
    const action = p.action; p.action = .none;
    if (!p.enabled) return;
    const context = p.context orelse return;
    switch (action) {
        .none => {},
        .first => _ = c.JS_Throw(context, c.JS_DupValue(context, p.reasons[0])),
        .second => _ = c.JS_Throw(context, c.JS_DupValue(context, p.reasons[1])),
        .terminate => {
            c.JS_PiRequestExecutionTermination(c.JS_GetRuntime(context));
            _ = c.JS_PiCheckExecutionTermination(context);
        },
    }
}
fn take(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = Probe.from(context.?) orelse return c.JS_ThrowInternalError(context, "missing operand probe");
    p.taken += 1;
    const value = p.next; p.next = c.pi_js_undefined();
    return value;
}
fn toPrimitive(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = Probe.from(context.?) orelse return c.JS_ThrowInternalError(context, "missing operand probe");
    p.conversions += 1;
    p.original_receiver = c.JS_GetClassID(receiver) == p.class_id;
    p.string_hint_seen = argc == 1 and c.JS_IsString(argv[0]) and
        c.JS_IsStrictEqual(context.?, argv[0], p.string_hint);
    if (p.throw_conversion) return c.JS_Throw(context, c.JS_DupValue(context, p.reasons[0]));
    const value = p.key; p.key = c.pi_js_undefined();
    return value;
}
const short_forward = "if(take()){progress.branch=true;}progress.after=true;return 7;";
const short_backward = "do{progress.bodyCalls+=1;}while(take());progress.after=true;return 7;";
// Every assignment is observable and emits field operations. This span exceeds
// the actual signed-byte branch range; no dead/constant padding is used.
const long_body =
    \\progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;
    \\progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;
    \\progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;
    \\progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;
    \\progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;
    \\progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;progress.bodyCalls+=1;
;
const long_forward = "if(take()){" ++ long_body ++ "}progress.after=true;return 7;";
const long_backward = "do{" ++ long_body ++ "}while(take());progress.after=true;return 7;";
const computed_key = "const result = {};result[take()] = (progress.valueCalls+=1,7);progress.after=true;return result;";
fn expectFatal(f: *Fixture, p: *Probe, function: c.JSValue, reason_index: usize, body_calls: i32) !void {
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_HasException(f.context.?));
    const reason = c.JS_GetException(f.context.?);
    defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, p.reasons[reason_index]));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try f.failedProgress(false);
    try f.ownNumber("bodyCalls", body_calls);
    try std.testing.expectEqual(@as(usize, 1), p.retired);
    try std.testing.expectEqual(@as(usize, 1), p.taken);
}
fn expectOrdinary(f: *Fixture, p: *Probe, function: c.JSValue, reason_index: usize) !void {
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(!c.JS_IsException(result));
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, result, p.reasons[reason_index]));
    try f.failedProgress(true);
    try std.testing.expectEqual(@as(usize, 1), p.retired);
}
fn expectTermination(f: *Fixture, p: *Probe, function: c.JSValue) !void {
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_HasException(f.context.?));
    try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
    const reason = c.JS_GetException(f.context.?);
    defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_PiIsExecutionTermination(reason));
    try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.runtime.?));
    try f.failedProgress(false);
    try std.testing.expectEqual(@as(usize, 1), p.retired);
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    try std.testing.expect(!c.JS_HasException(f.context.?));
}
fn expectKeySuccess(f: *Fixture, p: *Probe, function: c.JSValue) !void {
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(!c.JS_IsException(result));
    try std.testing.expect(!c.JS_HasException(f.context.?));
    const value = c.JS_GetProperty(f.context.?, result, f.key_atom);
    defer c.JS_FreeValue(f.context.?, value);
    try f.number(value, 7);
    try std.testing.expectEqual(@as(usize, 1), p.conversions);
    try std.testing.expect(p.string_hint_seen);
    try std.testing.expectEqual(@as(usize, 1), p.retired);
    try f.ownBool("after", true); try f.ownBool("caught", false); try f.ownBool("finalized", true);
    try f.ownNumber("valueCalls", 1);
}

test "VM consuming operand truthy branch retires its holder without invoking conversion" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.throw_conversion = true;
    try p.prepare(&f, false, false);
    const function = try f.compile(short_forward); defer c.JS_FreeValue(f.context.?, function);
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try f.number(result, 7);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expectEqual(@as(usize, 0), p.conversions);
    try std.testing.expectEqual(@as(usize, 1), p.retired);
    try f.ownBool("branch", true); try f.ownBool("after", true);
}
test "VM consuming operand immediate false branch values keep their actual truthiness" {
    inline for (.{ "0", "false", "null", "undefined" }) |expression| {
        var f: Fixture = .{}; var p: Probe = .{};
        try start(&f, &p); defer { p.disable(); f.deinit(); }
        p.next = try f.eval(expression);
        const function = try f.compile(short_forward); defer c.JS_FreeValue(f.context.?, function);
        const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
        defer c.JS_FreeValue(f.context.?, result);
        try f.number(result, 7);
        try std.testing.expect(!c.JS_HasException(f.context.?));
        try f.ownBool("branch", false); try f.ownBool("after", true);
        try std.testing.expectEqual(@as(usize, 0), p.retired);
    }
}
test "VM consuming operand short forward branch checks actual holder fatal before its body" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.fatal(0); p.action = .first; try p.prepare(&f, false, false);
    const function = try f.compile(short_forward); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0, 0);
    try std.testing.expectEqual(@as(usize, 0), p.conversions);
}
test "VM consuming operand short backward branch stops before a second actual loop body" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.fatal(0); p.action = .first; try p.prepare(&f, false, false);
    const function = try f.compile(short_backward); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0, 1);
}
test "VM consuming operand long forward branch checks actual holder fatal before side effects" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.fatal(0); p.action = .first; try p.prepare(&f, false, false);
    const function = try f.compile(long_forward); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0, 0);
}
test "VM consuming operand long backward branch stops before repeating its actual body" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.fatal(0); p.action = .first; try p.prepare(&f, false, false);
    const function = try f.compile(long_backward); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0, 24);
}
test "VM consuming operand ordinary Boolean cleanup enters the genuine guest catch" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.action = .first; try p.prepare(&f, false, false);
    const function = try f.compile(short_forward); defer c.JS_FreeValue(f.context.?, function);
    try expectOrdinary(&f, &p, function, 0);
}
test "VM consuming operand flagged Error truthiness is successful DATA" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    try p.prepare(&f, false, true);
    const function = try f.compile(short_forward); defer c.JS_FreeValue(f.context.?, function);
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try f.number(result, 7); try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expectEqual(@as(usize, 1), p.retired);
    try std.testing.expectEqual(@as(usize, 0), p.conversions);
    try f.ownBool("branch", true); try f.ownBool("after", true);
}
test "VM consuming operand Boolean cleanup preserves actual private termination" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.action = .terminate; try p.prepare(&f, false, false);
    const function = try f.compile(short_forward); defer c.JS_FreeValue(f.context.?, function);
    try expectTermination(&f, &p, function);
}
test "VM consuming operand computed String key retains the completed primitive after its receiver retires" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    try p.prepare(&f, false, false);
    const function = try f.compile(computed_key); defer c.JS_FreeValue(f.context.?, function);
    try expectKeySuccess(&f, &p, function);
    try std.testing.expect(p.original_receiver);
}
test "VM consuming operand computed Symbol key preserves the selected intrinsic identity" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    try p.prepare(&f, true, false);
    const function = try f.compile(computed_key); defer c.JS_FreeValue(f.context.?, function);
    try expectKeySuccess(&f, &p, function);
    try std.testing.expect(p.original_receiver);
}
test "VM consuming operand successful key conversion checks receiver fatal before value evaluation" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.fatal(0); p.action = .first; try p.prepare(&f, true, false);
    const function = try f.compile(computed_key); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0, 0);
    try std.testing.expectEqual(@as(usize, 1), p.conversions);
    try std.testing.expect(p.original_receiver and p.string_hint_seen);
}
test "VM consuming operand failed key conversion selects a later actual operand fatal" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.throw_conversion = true; p.action = .second; p.fatal(1); try p.prepare(&f, false, false);
    const function = try f.compile(computed_key); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 1, 0);
    try std.testing.expectEqual(@as(usize, 1), p.conversions);
}
test "VM consuming operand first actual conversion fatal survives a second operand fatal" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.throw_conversion = true; p.action = .second; p.fatal(0); p.fatal(1); try p.prepare(&f, false, false);
    const function = try f.compile(computed_key); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0, 0);
}
test "VM consuming operand ordinary conversion reason survives ordinary operand retirement" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.throw_conversion = true; p.action = .second; try p.prepare(&f, false, false);
    const function = try f.compile(computed_key); defer c.JS_FreeValue(f.context.?, function);
    try expectOrdinary(&f, &p, function, 0);
}
test "VM consuming operand ordinary successful-key cleanup enters the original catch" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.action = .first; try p.prepare(&f, false, false);
    const function = try f.compile(computed_key); defer c.JS_FreeValue(f.context.?, function);
    try expectOrdinary(&f, &p, function, 0);
    try std.testing.expectEqual(@as(usize, 1), p.conversions);
}
test "VM consuming operand flagged Error key receiver remains DATA during real conversion" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    try p.prepare(&f, false, true);
    const function = try f.compile(computed_key); defer c.JS_FreeValue(f.context.?, function);
    try expectKeySuccess(&f, &p, function);
}
test "VM consuming operand key retirement preserves private termination before value creation" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.action = .terminate; try p.prepare(&f, false, false);
    const function = try f.compile(computed_key); defer c.JS_FreeValue(f.context.?, function);
    try expectTermination(&f, &p, function);
    try std.testing.expectEqual(@as(usize, 1), p.conversions);
}
test "VM consuming operand precompiled Boolean completion needs no allocation" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    try p.prepare(&f, false, false);
    const function = try f.compile(short_forward); defer c.JS_FreeValue(f.context.?, function);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try f.number(result, 7);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expectEqual(@as(usize, 1), p.retired);
    try f.ownBool("branch", true); try f.ownBool("after", true);
}

const direct_drop = "take();progress.after=true;return 7;";
const literal_key_drop = "const result = {[take()]:(progress.valueCalls+=1,7)};progress.after=true;return result;";
fn expectLiteralDrop(f: *Fixture, p: *Probe, function: c.JSValue, fatal_reason: bool) !void {
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    if (fatal_reason) {
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(c.JS_HasException(f.context.?));
        const reason = c.JS_GetException(f.context.?);
        defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, p.reasons[0]));
        try std.testing.expect(c.JS_IsUncatchableError(reason));
    } else {
        try std.testing.expect(!c.JS_IsException(result));
        try std.testing.expect(!c.JS_HasException(f.context.?));
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, result, p.reasons[0]));
    }
    try f.ownBool("after", false);
    try f.ownBool("caught", !fatal_reason);
    try f.ownBool("finalized", !fatal_reason);
    // The actual literal evaluates its value before converting/retiring key.
    try f.ownNumber("valueCalls", 1);
    try std.testing.expectEqual(@as(usize, 1), p.retired);
    try std.testing.expectEqual(@as(usize, 1), p.taken);
    try std.testing.expectEqual(@as(usize, 1), p.conversions);
    try std.testing.expect(p.original_receiver and p.string_hint_seen);
}
test "VM consuming operand direct drop checks actual fatal before its next statement" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.action = .first; p.fatal(0); try p.prepare(&f, false, false);
    const function = try f.compile(direct_drop); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0, 0);
    try std.testing.expectEqual(@as(usize, 0), p.conversions);
}
test "VM consuming operand ordinary direct drop enters the original catch" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.action = .first; try p.prepare(&f, false, false);
    const function = try f.compile(direct_drop); defer c.JS_FreeValue(f.context.?, function);
    try expectOrdinary(&f, &p, function, 0);
}
test "VM consuming operand dropping flagged Error DATA does not create an event" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    try p.prepare(&f, false, true);
    const function = try f.compile(direct_drop); defer c.JS_FreeValue(f.context.?, function);
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try f.number(result, 7);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expectEqual(@as(usize, 1), p.retired);
    try std.testing.expectEqual(@as(usize, 0), p.conversions);
    try f.ownBool("after", true); try f.ownBool("caught", false); try f.ownBool("finalized", true);
}
test "VM consuming operand object literal key drop stops after its already evaluated value" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.action = .first; p.fatal(0); try p.prepare(&f, true, false);
    const function = try f.compile(literal_key_drop); defer c.JS_FreeValue(f.context.?, function);
    try expectLiteralDrop(&f, &p, function, true);
}
test "VM consuming operand ordinary object literal key drop preserves exact catch identity" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.action = .first; try p.prepare(&f, false, false);
    const function = try f.compile(literal_key_drop); defer c.JS_FreeValue(f.context.?, function);
    try expectLiteralDrop(&f, &p, function, false);
}
test "VM consuming operand direct drop preserves actual private termination" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.action = .terminate; try p.prepare(&f, false, false);
    const function = try f.compile(direct_drop); defer c.JS_FreeValue(f.context.?, function);
    try expectTermination(&f, &p, function);
}
