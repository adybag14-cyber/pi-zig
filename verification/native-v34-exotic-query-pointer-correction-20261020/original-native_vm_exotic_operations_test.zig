//! Source-only controls for the two opt-in exotic operation distinctions.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
const Action = enum { none, ordinary, fatal, terminate, cancelled };
const Probe = struct {
    context: ?*c.JSContext = null,
    atoms: [4]c.JSAtom = .{0, 0, 0, 0},
    marker_class: c.JSClassID = 0,
    reason: c.JSValue = undefined,
    enabled: bool = false,
    flags_calls: usize = 0,
    descriptor_calls: usize = 0,
    existence_calls: usize = 0,
    query_calls: usize = 0,
    get_calls: usize = 0,
    enum_calls: usize = 0,
    define_calls: usize = 0,
    admission_calls: usize = 0,
    marker_created: usize = 0,
    marker_retired: usize = 0,
    target_retired: usize = 0,
    trace: [128]u8 = undefined,
    trace_len: usize = 0,
    overflow: bool = false,
    use_markers: bool = false,
    return_reason: bool = false,
    allow_integrity: bool = false,
    query_action: Action = .none,
    integrity_action: Action = .none,
    last_level: c.JSPiIntegrityLevel = c.JS_PI_INTEGRITY_NONE,
    virtual_flags: c_int = c.JS_PROP_C_W_E,
    fn from(value: c.JSValue) ?*Probe {
        const pointer = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return null;
        return @ptrCast(@alignCast(pointer));
    }
    fn event(self: *Probe, value: u8) void {
        if (self.trace_len == self.trace.len) { self.overflow = true; return; }
        self.trace[self.trace_len] = value; self.trace_len += 1;
    }
    fn perform(self: *Probe, action: Action) bool {
        if (!self.enabled or action == .none) return false;
        const context = self.context.?;
        switch (action) {
            .none => unreachable,
            .ordinary => _ = c.JS_Throw(context, c.JS_DupValue(context, self.reason)),
            .fatal => {
                c.JS_SetUncatchableError(context, self.reason);
                _ = c.JS_Throw(context, c.JS_DupValue(context, self.reason));
            },
            .terminate, .cancelled => {
                c.JS_PiRequestExecutionTermination(c.JS_GetRuntime(context));
                _ = c.JS_PiCheckExecutionTermination(context);
                if (action == .cancelled) {
                    c.JS_PiCancelExecutionTermination(c.JS_GetRuntime(context));
                    _ = c.JS_Throw(context, c.JS_PiNativeTerminationResult());
                }
            },
        }
        return true;
    }
    fn query(self: *Probe, atom: c.JSAtom, flags: *c_int) c_int {
        self.query_calls += 1; self.event('q');
        if (self.perform(self.query_action)) return -1;
        if (atom == self.atoms[0] or atom == self.atoms[3]) {
            flags.* = self.virtual_flags; return 1;
        }
        if (atom == self.atoms[1]) {
            flags.* = c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE; return 1;
        }
        return 0;
    }
    fn get(self: *Probe) c.JSValue {
        self.get_calls += 1; self.event('g');
        const context = self.context.?;
        if (self.return_reason) return c.JS_DupValue(context, self.reason);
        if (!self.use_markers) return c.JS_NewInt32(context, 17);
        const value = c.JS_NewObjectProtoClass(context, c.pi_js_null(), self.marker_class);
        if (c.JS_IsException(value)) return value;
        _ = c.JS_SetOpaque(value, self); self.marker_created += 1;
        return value;
    }
};
fn targetFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const p = Probe.from(value) orelse return;
    _ = c.JS_SetOpaque(value, null); p.target_retired += 1;
}
fn markerFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const p = Probe.from(value) orelse return;
    _ = c.JS_SetOpaque(value, null); p.marker_retired += 1;
}
fn queryFlags(context: ?*c.JSContext, flags: [*c]c_int, value: c.JSValue, atom: c.JSAtom) callconv(.c) c_int {
    _ = context;
    const p = Probe.from(value) orelse return 0;
    p.flags_calls += 1;
    return p.query(atom, &flags[0]);
}
fn descriptor(context: ?*c.JSContext, output: [*c]c.JSPropertyDescriptor, value: c.JSValue, atom: c.JSAtom) callconv(.c) c_int {
    _ = context;
    const p = Probe.from(value) orelse return 0;
    p.descriptor_calls += 1;
    if (output == null) p.existence_calls += 1;
    var flags: c_int = 0;
    const present = p.query(atom, &flags);
    if (present != 1 or output == null) return present;
    const result = p.get();
    if (c.JS_IsException(result)) return -1;
    output[0] = .{ .flags = flags, .value = result,
        .getter = c.pi_js_undefined(), .setter = c.pi_js_undefined() };
    return 1;
}
fn names(context: ?*c.JSContext, table: [*c][*c]c.JSPropertyEnum, length: [*c]u32, value: c.JSValue) callconv(.c) c_int {
    const p = Probe.from(value) orelse return -1;
    p.enum_calls += 1; p.event('e');
    table[0] = null; length[0] = 0;
    const memory = c.js_malloc(context, 4 * @sizeOf(c.JSPropertyEnum)) orelse return -1;
    const owned: [*]c.JSPropertyEnum = @ptrCast(@alignCast(memory));
    for (p.atoms, 0..) |atom, index|
        owned[index] = .{ .atom = c.JS_DupAtom(context, atom), .is_enumerable = false };
    table[0] = owned; length[0] = 4;
    return 0;
}
fn getProperty(context: ?*c.JSContext, value: c.JSValue, atom: c.JSAtom, receiver: c.JSValue) callconv(.c) c.JSValue {
    _ = context; _ = receiver;
    const p = Probe.from(value) orelse return c.pi_js_undefined();
    if (atom != p.atoms[0] and atom != p.atoms[1] and atom != p.atoms[3])
        return c.pi_js_undefined();
    return p.get();
}
fn defineProperty(context: ?*c.JSContext, value: c.JSValue, atom: c.JSAtom, field: c.JSValue, getter: c.JSValue, setter: c.JSValue, flags: c_int) callconv(.c) c_int {
    _ = context; _ = atom; _ = field; _ = getter; _ = setter;
    const p = Probe.from(value) orelse return 0;
    p.define_calls += 1; p.event('d');
    if (flags & c.JS_PROP_HAS_CONFIGURABLE != 0 and flags & c.JS_PROP_CONFIGURABLE == 0)
        p.virtual_flags &= ~@as(c_int, c.JS_PROP_CONFIGURABLE);
    if (flags & c.JS_PROP_HAS_WRITABLE != 0 and flags & c.JS_PROP_WRITABLE == 0)
        p.virtual_flags &= ~@as(c_int, c.JS_PROP_WRITABLE);
    return 1;
}
fn admit(context: ?*c.JSContext, value: c.JSValue, level: c.JSPiIntegrityLevel) callconv(.c) c_int {
    _ = context;
    const p = Probe.from(value) orelse return 0;
    p.admission_calls += 1; p.last_level = level; p.event('i');
    if (p.perform(p.integrity_action)) return -1;
    return @intFromBool(p.allow_integrity);
}
const flags_methods: c.JSClassExoticMethods = .{
    .get_own_property = descriptor, .get_own_property_names = names,
    .get_property = getProperty, .get_own_property_flags = queryFlags,
};
const legacy_methods: c.JSClassExoticMethods = .{
    .get_own_property = descriptor, .get_own_property_names = names,
    .get_property = getProperty,
};
const guard_methods: c.JSClassExoticMethods = .{
    .get_own_property = descriptor, .get_own_property_names = names,
    .get_property = getProperty, .define_own_property = defineProperty,
    .get_own_property_flags = queryFlags, .prevent_extensions = admit,
};
const allow_methods: c.JSClassExoticMethods = .{ .prevent_extensions = admit };
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    probe: Probe = .{},
    objects: [4]c.JSValue = undefined,
    progress: c.JSValue = undefined,
    fn init(self: *Fixture) !void {
        self.* = .{ .objects = .{c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined()},
            .progress = c.pi_js_undefined(), .probe = .{ .reason = c.pi_js_undefined() } };
        self.runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer self.deinit();
        c.JS_SetMaxStackSize(self.runtime.?, 1024 * 1024);
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        self.probe.context = self.context.?;
        self.probe.reason = try self.checked(c.JS_NewError(self.context.?));
        const atom_names = [_][*:0]const u8{"visible", "hidden", "missing"};
        for (atom_names, 0..) |name, index| {
            self.probe.atoms[index] = c.JS_NewAtom(self.context.?, name);
            if (self.probe.atoms[index] == c.JS_ATOM_NULL) return error.OutOfMemory;
        }
        const symbol = try self.eval("Symbol('virtual')");
        defer c.JS_FreeValue(self.context.?, symbol);
        self.probe.atoms[3] = c.JS_ValueToAtom(self.context.?, symbol);
        if (self.probe.atoms[3] == c.JS_ATOM_NULL) return error.OutOfMemory;
        try self.publish("symbolKey", symbol);
        _ = c.JS_NewClassID(self.runtime.?, &self.probe.marker_class);
        const marker_definition: c.JSClassDef = .{ .class_name = "Exotic descriptor value", .finalizer = markerFinalizer };
        try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(self.runtime.?, self.probe.marker_class, &marker_definition));
        const definitions = [_]c.JSClassDef{
            .{ .class_name = "Flags opt in", .finalizer = targetFinalizer, .exotic = @constCast(&flags_methods) },
            .{ .class_name = "Legacy descriptor", .finalizer = targetFinalizer, .exotic = @constCast(&legacy_methods) },
            .{ .class_name = "Integrity rejection", .finalizer = targetFinalizer, .exotic = @constCast(&guard_methods) },
            .{ .class_name = "Integrity admission", .finalizer = targetFinalizer, .exotic = @constCast(&allow_methods) },
        };
        const global_names = [_][*:0]const u8{"target", "legacy", "guard", "admitted"};
        for (definitions, global_names, 0..) |definition, name, index| {
            var class_id: c.JSClassID = 0;
            _ = c.JS_NewClassID(self.runtime.?, &class_id);
            try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(self.runtime.?, class_id, &definition));
            self.objects[index] = try self.checked(c.JS_NewObjectProtoClass(self.context.?, c.pi_js_null(), class_id));
            _ = c.JS_SetOpaque(self.objects[index], &self.probe);
            try self.publish(name, self.objects[index]);
        }
        self.progress = try self.eval("globalThis.progress={after:false,caught:false,finalized:false};progress");
        self.probe.enabled = true;
    }
    fn deinit(self: *Fixture) void {
        self.probe.enabled = false;
        if (self.runtime) |runtime| c.JS_SetMemoryLimit(runtime, 0);
        if (self.context) |context| {
            _ = c.JS_PiCheckExecutionTermination(context);
            c.JS_PiCancelExecutionTermination(self.runtime.?);
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            for (&self.objects) |*slot| { const value = slot.*; slot.* = c.pi_js_undefined(); c.JS_FreeValue(context, value); }
            c.JS_FreeValue(context, self.progress); self.progress = c.pi_js_undefined();
            c.JS_FreeValue(context, self.probe.reason); self.probe.reason = c.pi_js_undefined();
            for (&self.probe.atoms) |*atom| { if (atom.* != c.JS_ATOM_NULL) c.JS_FreeAtom(context, atom.*); atom.* = c.JS_ATOM_NULL; }
            self.context = null; c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
        self.probe.context = null;
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, value); return error.ExoticOperationFailed;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "actual-exotic-operations.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValueStr(self.context.?, global_object, name,
            c.JS_DupValue(self.context.?, value), c.JS_PROP_C_W_E));
    }
    fn compile(self: *Fixture, comptime expression: []const u8) !c.JSValue {
        return self.eval("(function(){try{const value=" ++ expression ++
            ";progress.after=true;return value;}catch(reason){progress.caught=true;return reason;}" ++
            "finally{progress.finalized=true;}})");
    }
    fn call(self: *Fixture, function: c.JSValue) c.JSValue {
        return c.JS_Call(self.context.?, function, c.pi_js_undefined(), 0, null);
    }
    fn expectText(self: *Fixture, value: c.JSValue, expected: []const u8) !void {
        try std.testing.expect(c.JS_IsString(value));
        const text = c.JS_ToCString(self.context.?, value) orelse return error.ExoticStringFailed;
        defer c.JS_FreeCString(self.context.?, text);
        try std.testing.expectEqualStrings(expected, std.mem.span(text));
    }
    fn expectEvalText(self: *Fixture, source: [:0]const u8, expected: []const u8) !void {
        const result = try self.eval(source); defer c.JS_FreeValue(self.context.?, result);
        try self.expectText(result, expected);
    }
    fn expectEvalBool(self: *Fixture, source: [:0]const u8, expected: bool) !void {
        const result = try self.eval(source); defer c.JS_FreeValue(self.context.?, result);
        try self.expectBool(result, expected);
    }
    fn expectBool(self: *Fixture, value: c.JSValue, expected: bool) !void {
        try std.testing.expect(c.JS_IsBool(value));
        try std.testing.expectEqual(@as(c_int, @intFromBool(expected)), c.JS_ToBool(self.context.?, value));
    }
    fn expectProgress(self: *Fixture, after: bool, caught: bool, finalized: bool) !void {
        const names_list = [_][*:0]const u8{"after", "caught", "finalized"};
        for (names_list, [_]bool{after, caught, finalized}) |name, expected| {
            const value = c.JS_GetPropertyStr(self.context.?, self.progress, name);
            defer c.JS_FreeValue(self.context.?, value);
            try self.expectBool(value, expected);
        }
    }
    fn expectQuietRejection(self: *Fixture, level: c.JSPiIntegrityLevel) !void {
        try std.testing.expectEqual(@as(usize, 1), self.probe.admission_calls);
        try std.testing.expectEqual(level, self.probe.last_level);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_IsExtensible(self.context.?, self.objects[2]));
        try std.testing.expectEqual(@as(usize, 0), self.probe.enum_calls);
        try std.testing.expectEqual(@as(usize, 0), self.probe.query_calls);
        try std.testing.expectEqual(@as(usize, 0), self.probe.get_calls);
        try std.testing.expectEqual(@as(usize, 0), self.probe.define_calls);
        try std.testing.expect(!self.probe.overflow);
    }
};
fn expectAbrupt(f: *Fixture, function: c.JSValue, private: bool, active: bool) !void {
    const result = f.call(function); defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_HasException(f.context.?));
    try std.testing.expectEqual(active, c.JS_PiIsExecutionTerminating(f.runtime.?));
    const reason = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, reason);
    if (private) {
        try std.testing.expect(c.JS_PiIsExecutionTermination(reason));
        if (active) {
            _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
            c.JS_PiCancelExecutionTermination(f.runtime.?);
        }
    } else {
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, f.probe.reason));
        try std.testing.expect(c.JS_IsUncatchableError(reason));
    }
    try f.expectProgress(false, false, false);
}

test "VM exotic operations enumerable keys query flags without fetching values" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    f.probe.use_markers = true;
    try f.expectEvalText("JSON.stringify(Object.keys(target))", "[\"visible\"]");
    try std.testing.expectEqualStrings("eqqq", f.probe.trace[0..f.probe.trace_len]);
    try std.testing.expectEqual(@as(usize, 3), f.probe.flags_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.descriptor_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.get_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.marker_created);
}

test "VM exotic operations full descriptors still query then fetch an owned value" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    f.probe.use_markers = true;
    var desc: c.JSPropertyDescriptor = undefined;
    const status = c.JS_GetOwnProperty(f.context.?, &desc, f.objects[0], f.probe.atoms[0]);
    defer if (status == 1) {
        c.JS_FreeValue(f.context.?, desc.value);
        c.JS_FreeValue(f.context.?, desc.getter);
        c.JS_FreeValue(f.context.?, desc.setter);
    };
    try std.testing.expectEqual(@as(c_int, 1), status);
    try std.testing.expectEqualStrings("qg", f.probe.trace[0..f.probe.trace_len]);
    try std.testing.expectEqual(@as(usize, 0), f.probe.flags_calls);
    try std.testing.expectEqual(@as(usize, 1), f.probe.descriptor_calls);
    try std.testing.expectEqual(f.probe.marker_class, c.JS_GetClassID(desc.value));
    try std.testing.expectEqual(@as(usize, 1), f.probe.marker_created);
    try std.testing.expectEqual(@as(usize, 0), f.probe.marker_retired);
}

test "VM exotic operations existence requests retain their original descriptor callback" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try std.testing.expectEqual(@as(c_int, 1),
        c.JS_GetOwnProperty(f.context.?, null, f.objects[0], f.probe.atoms[0]));
    try std.testing.expectEqual(@as(usize, 1), f.probe.existence_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.flags_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.get_calls);
    try std.testing.expectEqualStrings("q", f.probe.trace[0..f.probe.trace_len]);
}

test "VM exotic operations unfiltered own keys enumerate without a descriptor query" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectEvalBool("(() => {const keys=Reflect.ownKeys(target);return keys.length===4&&keys[0]==='visible'&&keys[1]==='hidden'&&keys[2]==='missing'&&keys[3]===symbolKey;})()", true);
    try std.testing.expectEqualStrings("e", f.probe.trace[0..f.probe.trace_len]);
    try std.testing.expectEqual(@as(usize, 0), f.probe.flags_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.descriptor_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.get_calls);
}

test "VM exotic operations values filter each key before its actual Get" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectEvalText("JSON.stringify(Object.values(target))", "[17]");
    try std.testing.expectEqualStrings("eqgqq", f.probe.trace[0..f.probe.trace_len]);
    try std.testing.expectEqual(@as(usize, 3), f.probe.flags_calls);
    try std.testing.expectEqual(@as(usize, 1), f.probe.get_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.descriptor_calls);
}

test "VM exotic operations missing flags hook retains temporary descriptor ownership" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    f.probe.use_markers = true;
    try f.expectEvalText("JSON.stringify(Object.keys(legacy))", "[\"visible\"]");
    try std.testing.expectEqualStrings("eqgqgq", f.probe.trace[0..f.probe.trace_len]);
    try std.testing.expectEqual(@as(usize, 0), f.probe.flags_calls);
    try std.testing.expectEqual(@as(usize, 3), f.probe.descriptor_calls);
    try std.testing.expectEqual(@as(usize, 2), f.probe.marker_created);
    try std.testing.expectEqual(@as(usize, 2), f.probe.marker_retired);
}

test "VM exotic operations physical own data precedes the optional query hook" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValue(f.context.?, f.objects[0],
        f.probe.atoms[0], c.JS_NewInt32(f.context.?, 42), c.JS_PROP_C_W_E));
    try f.expectEvalBool("Object.prototype.propertyIsEnumerable.call(target,'visible')", true);
    var desc: c.JSPropertyDescriptor = undefined;
    const status = c.JS_GetOwnProperty(f.context.?, &desc, f.objects[0], f.probe.atoms[0]);
    defer if (status == 1) {
        c.JS_FreeValue(f.context.?, desc.value);
        c.JS_FreeValue(f.context.?, desc.getter);
        c.JS_FreeValue(f.context.?, desc.setter);
    };
    try std.testing.expectEqual(@as(c_int, 1), status);
    var actual: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.context.?, &actual, desc.value));
    try std.testing.expectEqual(@as(i32, 42), actual);
    try std.testing.expectEqual(@as(usize, 0), f.probe.flags_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.descriptor_calls);
}

test "VM exotic operations SET_ENUM queries both string and Symbol descriptors without Get" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var table: [*c]c.JSPropertyEnum = null;
    var length: u32 = 0;
    const status = c.JS_GetOwnPropertyNames(f.context.?, &table, &length, f.objects[0],
        c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK | c.JS_GPN_SET_ENUM);
    defer {
        if (table != null) {
            for (table[0..length]) |entry| c.JS_FreeAtom(f.context.?, entry.atom);
            c.js_free(f.context.?, @ptrCast(table));
        }
    }
    try std.testing.expectEqual(@as(c_int, 0), status);
    try std.testing.expectEqual(@as(u32, 4), length);
    for (f.probe.atoms, 0..) |atom, index| {
        try std.testing.expectEqual(atom, table[index].atom);
        try std.testing.expectEqual(index == 0 or index == 3, table[index].is_enumerable);
    }
    try std.testing.expectEqual(@as(usize, 4), f.probe.flags_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.get_calls);
    try std.testing.expectEqualStrings("eqqqq", f.probe.trace[0..f.probe.trace_len]);
}

test "VM exotic operations ordinary Proxy descriptor traps retain their original order" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectEvalText("(() => {const log=[];const object=new Proxy({x:1},{ownKeys(){log.push('keys');return ['x'];},getOwnPropertyDescriptor(t,k){log.push('desc');return Reflect.getOwnPropertyDescriptor(t,k);}});Object.keys(object);return log.join(',');})()", "keys,desc");
    try std.testing.expectEqual(@as(usize, 0), f.probe.flags_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.descriptor_calls);
}

test "VM exotic operations admitted query performs no VM allocation under heap limit" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const function = try f.eval("(function(){return Object.prototype.propertyIsEnumerable.call(target,'visible');})");
    defer c.JS_FreeValue(f.context.?, function);
    const warm = f.call(function); defer c.JS_FreeValue(f.context.?, warm);
    try f.expectBool(warm, true);
    const before_calls = f.probe.flags_calls;
    const before_oom = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const result = f.call(function);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    defer c.JS_FreeValue(f.context.?, result);
    try f.expectBool(result, true);
    try std.testing.expectEqual(before_calls + 1, f.probe.flags_calls);
    try std.testing.expectEqual(before_oom, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
    try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "VM exotic operations descriptor getter may return flagged Error DATA successfully" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    c.JS_SetUncatchableError(f.context.?, f.probe.reason);
    f.probe.return_reason = true;
    var desc: c.JSPropertyDescriptor = undefined;
    const status = c.JS_GetOwnProperty(f.context.?, &desc, f.objects[0], f.probe.atoms[0]);
    defer if (status == 1) {
        c.JS_FreeValue(f.context.?, desc.value);
        c.JS_FreeValue(f.context.?, desc.getter);
        c.JS_FreeValue(f.context.?, desc.setter);
    };
    try std.testing.expectEqual(@as(c_int, 1), status);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, desc.value, f.probe.reason));
    try std.testing.expect(c.JS_IsUncatchableError(desc.value));
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expectEqual(@as(usize, 0), f.probe.flags_calls);
}

test "VM exotic operations ordinary query failure remains the exact catchable reason" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const function = try f.compile("Object.keys(target)"); defer c.JS_FreeValue(f.context.?, function);
    f.probe.query_action = .ordinary;
    const result = f.call(function); defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, result, f.probe.reason));
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try f.expectProgress(false, true, true);
    try std.testing.expectEqual(@as(usize, 0), f.probe.get_calls);
}

test "VM exotic operations actual fatal query stops later guest catch and finally" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const function = try f.compile("Object.keys(target)"); defer c.JS_FreeValue(f.context.?, function);
    f.probe.query_action = .fatal;
    try expectAbrupt(&f, function, false, false);
    try std.testing.expectEqual(@as(usize, 1), f.probe.flags_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.get_calls);
}

test "VM exotic operations active and cancelled private query completions stay native" {
    for ([_]Action{.terminate, .cancelled}) |action| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const function = try f.compile("Object.keys(target)"); defer c.JS_FreeValue(f.context.?, function);
        f.probe.query_action = action;
        try expectAbrupt(&f, function, true, action == .terminate);
        try std.testing.expectEqual(@as(usize, 0), f.probe.get_calls);
    }
}

test "VM exotic operations Reflect prevent rejection is normal and allocation free" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectEvalBool("Reflect.preventExtensions(guard)", false);
    try f.expectQuietRejection(c.JS_PI_INTEGRITY_NONE);
    f.probe.admission_calls = 0;
    const before_oom = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const status = c.JS_PreventExtensions(f.context.?, f.objects[2]);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try std.testing.expectEqual(@as(c_int, 0), status);
    try f.expectQuietRejection(c.JS_PI_INTEGRITY_NONE);
    try std.testing.expectEqual(before_oom, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
    try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "VM exotic operations Object prevent keeps its actual throwing rejection path" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectEvalText("(() => {try{Object.preventExtensions(guard);}catch(e){return e instanceof TypeError ? e.message : 'wrong';}return 'missing';})()", "Cannot prevent extensions");
    try f.expectQuietRejection(c.JS_PI_INTEGRITY_NONE);
}

test "VM exotic operations seal rejection uses SEALED before any enumeration" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectEvalText("(() => {try{Object.seal(guard);}catch(e){return e instanceof TypeError ? e.message : 'wrong';}return 'missing';})()", "Cannot seal");
    try f.expectQuietRejection(c.JS_PI_INTEGRITY_SEALED);
}

test "VM exotic operations freeze rejection uses FROZEN before any definition" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectEvalText("(() => {try{Object.freeze(guard);}catch(e){return e instanceof TypeError ? e.message : 'wrong';}return 'missing';})()", "Cannot freeze");
    try f.expectQuietRejection(c.JS_PI_INTEGRITY_FROZEN);
}

test "VM exotic operations positive admission completes each real integrity mutation" {
    inline for (.{ .{"Object.preventExtensions(admitted)", c.JS_PI_INTEGRITY_NONE},
        .{"Object.seal(admitted)", c.JS_PI_INTEGRITY_SEALED},
        .{"Object.freeze(admitted)", c.JS_PI_INTEGRITY_FROZEN} }) |selected| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        f.probe.allow_integrity = true;
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValue(f.context.?, f.objects[3],
            f.probe.atoms[0], c.JS_NewInt32(f.context.?, 9), c.JS_PROP_C_W_E));
        const result = try f.eval(selected[0]); defer c.JS_FreeValue(f.context.?, result);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, result, f.objects[3]));
        try std.testing.expectEqual(@as(usize, 1), f.probe.admission_calls);
        try std.testing.expectEqual(@as(c.JSPiIntegrityLevel, selected[1]), f.probe.last_level);
        try std.testing.expectEqual(@as(c_int, 0), c.JS_IsExtensible(f.context.?, f.objects[3]));
        var desc: c.JSPropertyDescriptor = undefined;
        const status = c.JS_GetOwnProperty(f.context.?, &desc, f.objects[3], f.probe.atoms[0]);
        defer if (status == 1) {
            c.JS_FreeValue(f.context.?, desc.value); c.JS_FreeValue(f.context.?, desc.getter); c.JS_FreeValue(f.context.?, desc.setter);
        };
        try std.testing.expectEqual(@as(c_int, 1), status);
        try std.testing.expectEqual(selected[1] == c.JS_PI_INTEGRITY_NONE,
            desc.flags & c.JS_PROP_CONFIGURABLE != 0);
        try std.testing.expectEqual(selected[1] != c.JS_PI_INTEGRITY_FROZEN,
            desc.flags & c.JS_PROP_WRITABLE != 0);
        try std.testing.expectEqual(@as(usize, 0), f.probe.enum_calls);
    }
}

test "VM exotic operations a missing admission hook preserves legacy extension mutation" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PreventExtensions(f.context.?, f.objects[1]));
    try std.testing.expectEqual(@as(c_int, 0), c.JS_IsExtensible(f.context.?, f.objects[1]));
    try std.testing.expectEqual(@as(usize, 0), f.probe.admission_calls);
    try std.testing.expectEqual(@as(usize, 0), f.probe.enum_calls);
}

test "VM exotic operations ordinary objects and Proxy refusal retain their old behavior" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectEvalBool("(() => {const o={x:1};return Object.freeze(o)===o&&!Object.isExtensible(o)&&!Object.getOwnPropertyDescriptor(o,'x').writable;})()", true);
    try f.expectEvalBool("Reflect.preventExtensions(new Proxy({}, {preventExtensions(){return false;}}))", false);
    try f.expectEvalText("(() => {const p=new Proxy({}, {preventExtensions(){return false;}});try{Object.seal(p);}catch(e){return e.message;}return 'missing';})()", "proxy preventExtensions handler returned false");
    try std.testing.expectEqual(@as(usize, 0), f.probe.admission_calls);
}

test "VM exotic operations a Proxy forwarding trap selects only its actual prevent call" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectEvalText("(() => {const p=new Proxy(guard,{preventExtensions(t){return Reflect.preventExtensions(t);}});try{Object.seal(p);}catch(e){return e.message;}return 'missing';})()", "proxy preventExtensions handler returned false");
    try f.expectQuietRejection(c.JS_PI_INTEGRITY_NONE);
}

test "VM exotic operations nonobject integrity requests keep existing public semantics" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectEvalBool("Object.preventExtensions(1)===1&&Object.seal(null)===null&&Object.freeze('x')==='x'", true);
    try f.expectEvalBool("(() => {try{Reflect.preventExtensions(1);}catch(e){return e instanceof TypeError;}return false;})()", true);
    try std.testing.expectEqual(@as(usize, 0), f.probe.admission_calls);
}

test "VM exotic operations ordinary integrity failure preserves its exact reason" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const function = try f.compile("Object.freeze(guard)"); defer c.JS_FreeValue(f.context.?, function);
    f.probe.integrity_action = .ordinary;
    const result = f.call(function); defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, result, f.probe.reason));
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try f.expectProgress(false, true, true);
    try f.expectQuietRejection(c.JS_PI_INTEGRITY_FROZEN);
}

test "VM exotic operations actual fatal integrity failure bypasses guest cleanup" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const function = try f.compile("Object.seal(guard)"); defer c.JS_FreeValue(f.context.?, function);
    f.probe.integrity_action = .fatal;
    try expectAbrupt(&f, function, false, false);
    try f.expectQuietRejection(c.JS_PI_INTEGRITY_SEALED);
}

test "VM exotic operations active and cancelled private integrity completion bypasses handlers" {
    for ([_]Action{.terminate, .cancelled}) |action| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const function = try f.compile("Object.freeze(guard)"); defer c.JS_FreeValue(f.context.?, function);
        f.probe.integrity_action = action;
        try expectAbrupt(&f, function, true, action == .terminate);
        try f.expectQuietRejection(c.JS_PI_INTEGRITY_FROZEN);
    }
}

test "VM exotic operations normal native rejection preserves the actual prior pending owner" {
    for ([_]Action{.ordinary, .fatal, .terminate}) |action| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try std.testing.expect(f.probe.perform(action));
        const before_oom = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const status = c.JS_PreventExtensions(f.context.?, f.objects[2]);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        try std.testing.expectEqual(@as(c_int, 0), status);
        try std.testing.expect(c.JS_HasException(f.context.?));
        try std.testing.expectEqual(action == .terminate, c.JS_PiIsExecutionTerminating(f.runtime.?));
        const reason = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, reason);
        if (action == .terminate) {
            try std.testing.expect(c.JS_PiIsExecutionTermination(reason));
            _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
            c.JS_PiCancelExecutionTermination(f.runtime.?);
        } else {
            try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, f.probe.reason));
            try std.testing.expectEqual(action == .fatal, c.JS_IsUncatchableError(reason));
        }
        try std.testing.expectEqual(before_oom, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
        try f.expectQuietRejection(c.JS_PI_INTEGRITY_NONE);
    }
}

test "VM exotic operations borrowed receiver callbacks create no lasting object root" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectEvalBool("Object.prototype.propertyIsEnumerable.call(target,'visible')", true);
    try f.expectEvalBool("Reflect.preventExtensions(guard)", false);
    try std.testing.expectEqual(@as(usize, 0), f.probe.target_retired);
    try f.expectEvalBool("delete globalThis.target && delete globalThis.guard", true);
    for ([_]usize{0, 2}) |index| {
        const owned = f.objects[index]; f.objects[index] = c.pi_js_undefined();
        c.JS_FreeValue(f.context.?, owned);
    }
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 2), f.probe.target_retired);
    try std.testing.expectEqual(@as(usize, 0), f.probe.marker_created);
    try std.testing.expectEqual(@as(usize, 1), f.probe.flags_calls);
    try std.testing.expectEqual(@as(usize, 1), f.probe.admission_calls);
}
