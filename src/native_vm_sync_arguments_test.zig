//! Actual synchronous argument-frame controls. Literal Source functions and
//! native opt-ins run in separate fresh realms over the same VM and C holders.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const sync = @import("extensions/native_sync_arguments.zig");
const Frame = @import("extensions/native_public_lexical_frame.zig").Frame(enum { local, discarded, getter, setter });
const DefaultFrame = @import("extensions/native_public_lexical_frame.zig").Frame(enum { p, q });
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");

const Kind = enum(u8) { clear, default_clear, order, rewrite, pair, drop, cycle, local_capture, capture_clear, inspect, constructor_primitive, zero, extra, host_oom };
const Shape = enum { ordinary, method, arrow };
const Token = struct { probe: *Probe, index: usize };
const Probe = struct {
    engine: *Engine = undefined,
    holder_class: c.JSClassID = 0,
    counts: [16]u32 = @splat(0),
    made: [16]bool = @splat(false),
    visits: [16]u32 = @splat(0),
    order: [32]u32 = @splat(99),
    order_len: usize = 0,
    tokens: [16]Token = undefined,
    fatal: [16]bool = @splat(false),
    reasons: [16]?c.JSValue = @splat(null),
    cleanup_reasons: [16]?c.JSValue = @splat(null),
    cleanup_published: [16]bool = @splat(false),
    on_finalize: ?c.JSValue = null,
    callbacks_enabled: bool = true,
    fn release(self: *Probe) void {
        self.callbacks_enabled = false;
        if (self.on_finalize) |value| { self.on_finalize = null; self.engine.freeValue(value); }
        for (&self.reasons) |*entry| {
            if (entry.*) |value| { entry.* = null; self.engine.freeValue(value); }
        }
        for (&self.cleanup_reasons) |*entry| {
            if (entry.*) |value| { entry.* = null; self.engine.freeValue(value); }
        }
    }
};
fn probeFrom(value: c.JSValue) *Probe { return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?)); }
fn probeMark(runtime: ?*c.JSRuntime, value: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (probe.on_finalize) |callback| c.JS_MarkValue(runtime, callback, mark);
    for (probe.reasons) |entry| { if (entry) |reason| c.JS_MarkValue(runtime, reason, mark); }
    for (probe.cleanup_reasons) |entry| { if (entry) |reason| c.JS_MarkValue(runtime, reason, mark); }
}
fn holderFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const probe = token.probe;
    const engine = probe.engine;
    probe.counts[token.index] += 1;
    if (probe.order_len < probe.order.len) {
        probe.order[probe.order_len] = @intCast(token.index);
        probe.order_len += 1;
    }
    if (!probe.callbacks_enabled) return;
    if (probe.on_finalize) |callback| {
        probe.on_finalize = null;
        const argument = [_]c.JSValue{c.JS_NewUint32(engine.context, @intCast(token.index))};
        const result = c.JS_Call(engine.context, callback, c.pi_js_undefined(), 1, @constCast(&argument));
        var completion = v.owned.Completion.initVoid(engine, if (c.JS_IsException(result)) @as(anyerror!void, error.JavaScriptException) else {});
        if (!c.JS_IsException(result)) completion.release(result);
        completion.release(callback);
        completion.finishVoid() catch |err| { _ = @import("extensions/native_sdk.zig").fail(engine, err); };
    }
    if (probe.cleanup_reasons[token.index]) |reason| {
        // A marked retained DATA root becomes a real pending event only here.
        probe.cleanup_published[token.index] = true;
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    }
    if (probe.fatal[token.index]) {
        probe.fatal[token.index] = false;
        _ = engine.throwNativeOutOfMemoryFatal();
        if (c.JS_HasException(engine.context)) {
            const reason = c.JS_GetException(engine.context);
            probe.reasons[token.index] = c.JS_DupValue(engine.context, reason);
            _ = c.JS_Throw(engine.context, reason);
        }
    }
}
fn helper(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    engine.checkNativeEntry() catch return engine.throwCaptured();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var scope: Scope = .{ .engine = engine };
    const result = v.owned.finishValue(&scope, helperBody(&scope, probeFrom(roots[0]), magic, if (argc > 0) argv[0..@intCast(argc)] else &.{})) catch |err| @import("extensions/native_sdk.zig").fail(engine, err);
    return engine.leaveNativeInvocation(&invocation, result);
}
fn slot(s: *Scope, value: c.JSValue) !usize {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    var index: u32 = 0;
    try boundary.finishStatus(c.JS_ToUint32(s.engine.context, &index, value));
    if (index >= 16) return error.SyncArgumentControlSlot;
    return @intCast(index);
}
fn helperBody(s: *Scope, probe: *Probe, magic: c_int, args: []const c.JSValue) !c.JSValue {
    if (magic == 2) {
        const result = try v.array(s);
        for (probe.order[0..probe.order_len], 0..) |item, i| try v.index(s, result, @intCast(i), c.JS_NewUint32(s.engine.context, item));
        return v.duplicate(s, result);
    }
    if (magic == 4) { c.JS_RunGC(s.engine.runtime); try s.engine.checkNativeEntry(); return c.pi_js_undefined(); }
    if (magic == 5) {
        if (probe.on_finalize != null) return error.SyncArgumentControlAlreadyArmed;
        probe.on_finalize = c.JS_DupValue(s.engine.context, v.arg(args, 0));
        return c.pi_js_undefined();
    }
    if (magic == 6) {
        _ = s.engine.throwNativeOutOfMemoryFatal();
        const reason = c.JS_GetException(s.engine.context);
        probe.reasons[15] = c.JS_DupValue(s.engine.context, reason);
        return s.engine.checked(c.JS_Throw(s.engine.context, reason));
    }
    const index = try slot(s, v.arg(args, 0));
    if (magic == 1) return c.JS_NewUint32(s.engine.context, probe.counts[index]);
    if (magic == 3) { probe.visits[index] += 1; return c.pi_js_undefined(); }
    if (probe.made[index]) return error.SyncArgumentControlHolderReused;
    probe.made[index] = true;
    probe.tokens[index] = .{ .probe = probe, .index = index };
    const value = try v.objectClass(s, probe.holder_class);
    _ = c.JS_SetOpaque(value, &probe.tokens[index]);
    return v.duplicate(s, value);
}
fn globalCallOwned(engine: *Engine, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const result: anyerror!c.JSValue = block: {
        const callable = v.global(&scope, name) catch |err| break :block err;
        const output = v.call(&scope, callable, c.pi_js_undefined(), args) catch |err| break :block err;
        break :block v.duplicate(&scope, output);
    };
    return v.owned.finishValue(&scope, result);
}
fn make(engine: *Engine, index: u32) !c.JSValue {
    return globalCallOwned(engine, "vmMake", &.{c.JS_NewUint32(engine.context, index)});
}
fn observe(engine: *Engine, args: []const c.JSValue) !void {
    var completion = v.owned.Completion.initValue(engine, globalCallOwned(engine, "vmObserve", args));
    const result = try completion.finishValue();
    var retired = v.owned.Completion.initVoid(engine, {});
    retired.release(result);
    return retired.finishVoid();
}
fn captureRead(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const result: anyerror!c.JSValue = if (sync.read(&scope, roots[0])) |value| v.duplicate(&scope, value) else |err| err;
    return v.owned.finishValue(&scope, result);
}
fn captureWrite(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const value = v.arg(args, 0);
    try sync.assign(engine, roots[0], c.JS_DupValue(engine.context, value));
    return c.JS_DupValue(engine.context, value);
}
fn localRead(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const result: anyerror!c.JSValue = if (Frame.read(&scope, roots[0])) |value| v.duplicate(&scope, value) else |err| err;
    return v.owned.finishValue(&scope, result);
}
fn localWrite(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const value = v.arg(args, 0);
    try Frame.assign(roots[0], c.JS_DupValue(engine.context, value));
    return c.JS_DupValue(engine.context, value);
}
fn captureFunction(engine: *Engine, arguments: *sync.Arguments, setter: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const result: anyerror!c.JSValue = block: {
        const cell = arguments.capture(&scope, 0) catch |err| break :block err;
        break :block v.function.createArrow(engine, if (setter) "set" else "get", if (setter) 1 else 0, if (setter) captureWrite else captureRead, &.{cell});
    };
    return v.owned.finishValue(&scope, result);
}
fn localFunction(engine: *Engine, frame: *Frame, setter: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const result: anyerror!c.JSValue = block: {
        const cell = frame.capture(&scope, .local, "local") catch |err| break :block err;
        break :block v.function.createArrow(engine, if (setter) "setLocal" else "getLocal", if (setter) 1 else 0, if (setter) localWrite else localRead, &.{cell});
    };
    return v.owned.finishValue(&scope, result);
}
fn publish(engine: *Engine, name: [*:0]const u8, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    const result: anyerror!void = block: {
        const global = v.global(&scope, "globalThis") catch |err| break :block err;
        break :block v.set(&scope, global, name, value);
    };
    return v.owned.finishVoid(&scope, result);
}
fn rewrite(engine: *Engine, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const result: anyerror!c.JSValue = block: {
        const suffix = v.text(&scope, "") catch |err| break :block err;
        const output = v.binary(&scope, 0, value, suffix) catch |err| break :block err;
        break :block v.duplicate(&scope, output);
    };
    return v.owned.finishValue(&scope, result);
}
fn nativeBody(engine: *Engine, receiver: c.JSValue, arguments: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    var raw_kind: c_int = 0;
    std.debug.assert(c.JS_ToInt32(engine.context, &raw_kind, roots[0]) == 0);
    return v.owned.finishValue(&scope, nativeOperation(&scope, receiver, arguments, @enumFromInt(raw_kind)));
}
fn nativeOperation(s: *Scope, receiver: c.JSValue, arguments: *sync.Arguments, kind: Kind) !c.JSValue {
    switch (kind) {
        .clear => { try arguments.take(0, c.pi_js_undefined()); try observe(s.engine, &.{}); return c.pi_js_undefined(); },
        .default_clear => {
            // The actual default-parameter parser first initializes raw p,
            // then retains separate p/q LET slots through the function body.
            const frame = try arguments.createFrame(s, DefaultFrame);
            if (c.JS_IsUndefined(arguments.get(0)))
                try arguments.take(0, c.JS_DupValue(s.engine.context, try v.text(s, "")));
            try frame.take(.p, c.JS_DupValue(s.engine.context, arguments.get(0)));
            try frame.take(.q, c.JS_DupValue(s.engine.context, arguments.get(1)));
            try arguments.take(0, c.pi_js_undefined());
            try observe(s.engine, &.{});
            return c.pi_js_undefined();
        },
        .order => {
            const frame = try arguments.createFrame(s, Frame);
            try frame.take(.local, make(s.engine, 1));
            try arguments.take(0, make(s.engine, 0));
            try observe(s.engine, &.{});
            return c.pi_js_undefined();
        },
        .rewrite => { try arguments.take(0, rewrite(s.engine, arguments.get(0))); try observe(s.engine, &.{arguments.get(0)}); return c.JS_DupValue(s.engine.context, arguments.get(0)); },
        .pair => {
            const frame = try arguments.createFrame(s, Frame);
            try frame.take(.getter, captureFunction(s.engine, arguments, false));
            try frame.take(.setter, captureFunction(s.engine, arguments, true));
            const result = try v.object(s);
            try v.put(s, result, "get", frame.get(.getter));
            try v.put(s, result, "set", frame.get(.setter));
            return v.duplicate(s, result);
        },
        .drop => {
            const frame = try arguments.createFrame(s, Frame);
            try frame.take(.discarded, captureFunction(s.engine, arguments, false));
            try frame.clear(.discarded);
            try arguments.take(0, c.pi_js_undefined());
            try observe(s.engine, &.{});
            return c.pi_js_undefined();
        },
        .cycle => {
            try arguments.take(0, make(s.engine, 0));
            const getter = try v.own(s, try captureFunction(s.engine, arguments, false));
            try v.put(s, arguments.get(0), "get", getter);
            return v.duplicate(s, getter);
        },
        .local_capture => {
            const frame = try arguments.createFrame(s, Frame);
            try arguments.take(0, make(s.engine, 0));
            try frame.take(.local, make(s.engine, 1));
            try frame.take(.getter, localFunction(s.engine, frame, false));
            try publish(s.engine, "localGet", frame.get(.getter));
            try frame.take(.setter, localFunction(s.engine, frame, true));
            try publish(s.engine, "localSet", frame.get(.setter));
            return c.pi_js_undefined();
        },
        .capture_clear => {
            const frame = try arguments.createFrame(s, Frame);
            try frame.take(.getter, captureFunction(s.engine, arguments, false));
            try publish(s.engine, "parameterGet", frame.get(.getter));
            try arguments.take(0, c.pi_js_undefined());
            try observe(s.engine, &.{});
            return c.pi_js_undefined();
        },
        .inspect => {
            const result = try v.array(s);
            try v.index(s, result, 0, arguments.get(0));
            try v.index(s, result, 1, arguments.get(1));
            try v.index(s, result, 2, receiver);
            return v.duplicate(s, result);
        },
        .constructor_primitive => { try v.set(s, receiver, "p", arguments.get(0)); return c.JS_NewInt32(s.engine.context, 17); },
        .zero, .extra => {
            const frame = try arguments.createFrame(s, Frame);
            try frame.take(.local, make(s.engine, 1));
            try observe(s.engine, &.{});
            return c.pi_js_undefined();
        },
        .host_oom => {
            const frame = try arguments.createFrame(s, Frame);
            try arguments.take(0, make(s.engine, 0));
            try frame.take(.local, make(s.engine, 1));
            return error.OutOfMemory;
        },
    }
}
fn source(kind: Kind, formal_count: u16, shape: Shape) []const u8 {
    return switch (kind) {
        .clear => "globalThis.subject=function(p){p=undefined;vmObserve()}",
        .default_clear => "globalThis.subject=function(p='',q){p=undefined;vmObserve()}",
        .order => if (formal_count == 2) "globalThis.subject=function(p='',q){const local=vmMake(1);p=vmMake(0);vmObserve()}" else "globalThis.subject=function(p){const local=vmMake(1);p=vmMake(0);vmObserve()}",
        .rewrite => "globalThis.subject=function(p){p+='';vmObserve(p);return p}",
        .pair => "globalThis.subject=function(p){const get=()=>p;const set=value=>p=value;return {get,set}}",
        .drop => "globalThis.subject=function(p){let discarded=()=>p;discarded=undefined;p=undefined;vmObserve()}",
        .cycle => "globalThis.subject=function(p){p=vmMake(0);const get=()=>p;p.get=get;return get}",
        .local_capture => "globalThis.subject=function(p,q){p=vmMake(0);let local=vmMake(1);const get=()=>local;globalThis.localGet=get;const set=value=>local=value;globalThis.localSet=set}",
        .capture_clear => "globalThis.subject=function(p){const get=()=>p;globalThis.parameterGet=get;p=undefined;vmObserve()}",
        .inspect => switch (shape) {
            .ordinary => "globalThis.subject=function(p,q){return [p,q,this]}",
            .method => "globalThis.subject=({subject(p,q){return [p,q,this]}}).subject",
            .arrow => "globalThis.subject=(p,q)=>[p,q,undefined]",
        },
        .constructor_primitive => "globalThis.subject=function(p){this.p=p;return 17}",
        .zero => "globalThis.subject=function(){const local=vmMake(1);vmObserve()}",
        .extra => "globalThis.subject=function(p){const local=vmMake(1);vmObserve()}",
        .host_oom => "globalThis.subject=function(p){p=vmMake(0);const local=vmMake(1);vmOOM()}",
    };
}
fn prepareBody(s: *Scope, probe: *Probe, native: bool, kind: Kind, formal_count: u16, length: c_int, shape: Shape) !void {
    var record_class: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &record_class) == 0) return error.OutOfMemory;
    const record_definition: c.JSClassDef = .{ .class_name = "Synchronous parameter control record", .gc_mark = probeMark };
    if (c.JS_NewClass(s.engine.runtime, record_class, &record_definition) < 0) return error.OutOfMemory;
    if (c.JS_NewClassID(s.engine.runtime, &probe.holder_class) == 0) return error.OutOfMemory;
    const holder_definition: c.JSClassDef = .{ .class_name = "Actual synchronous parameter sole holder", .finalizer = holderFinalizer };
    if (c.JS_NewClass(s.engine.runtime, probe.holder_class, &holder_definition) < 0) return error.OutOfMemory;
    const record = try v.objectClass(s, record_class); _ = c.JS_SetOpaque(record, probe);
    const global = try v.global(s, "globalThis");
    inline for (.{ "vmMake", "vmCount", "vmOrder", "vmNote", "vmCollect", "vmFinalize", "vmOOM" }, 0..) |name, magic| {
        var roots = [_]c.JSValue{record};
        var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
        const function = try boundary.finishValue(s, c.JS_NewCFunctionData2(s.engine.context, helper, name, 1, magic, 1, &roots));
        try v.put(s, global, name, function);
    }
    const hooks = try v.own(s, try retirement.createNativeRetirementHooks(s.engine));
    try v.put(s, global, "syncHooks", hooks);
    if (native) {
        const definition: sync.Definition = .{
            .formal_count = formal_count,
            .callback = nativeBody,
            .hooks = if (kind == .default_clear) sync.frameHooks(DefaultFrame) else sync.frameHooks(Frame),
        };
        const roots = [_]c.JSValue{c.JS_NewInt32(s.engine.context, @intFromEnum(kind))};
        const function = try v.own(s, try switch (shape) {
            .ordinary => v.function.createWithArguments(s.engine, "subject", length, definition, &roots),
            .method => v.function.createMethodWithArguments(s.engine, "subject", length, definition, &roots),
            .arrow => v.function.createArrowWithArguments(s.engine, "subject", length, definition, &roots),
        });
        try v.put(s, global, "subject", function);
    }
}
fn run(engine: *Engine, text: []const u8) !void {
    const namespace = try engine.evalModule(text, "actual-sync-argument-control.mjs");
    engine.freeValue(namespace);
}
fn evaluate(engine: *Engine, text: []const u8) !c.JSValue {
    return engine.eval(text, "actual-sync-argument-control.js", c.JS_EVAL_TYPE_GLOBAL);
}
fn prepare(engine: *Engine, probe: *Probe, native: bool, kind: Kind, formal_count: u16, length: c_int, shape: Shape) !void {
    probe.engine = engine;
    var scope: Scope = .{ .engine = engine };
    try v.owned.finishVoid(&scope, prepareBody(&scope, probe, native, kind, formal_count, length, shape));
    try run(engine, "globalThis.vmObserve=()=>{};");
    if (!native) try run(engine, source(kind, formal_count, shape));
}
fn clean(engine: *Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn expectOrder(probe: *Probe, expected: []const u32) !void {
    try std.testing.expectEqualSlices(u32, expected, probe.order[0..probe.order_len]);
}
fn expectOwnFalse(engine: *Engine, record: c.JSValue, name: [*:0]const u8) !void {
    // Control-owned primitive data properties, with the original record held
    // independently. This read performs no guest getter or native entry check.
    const value = c.JS_GetPropertyStr(engine.context, record, name);
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsBool(value));
    try std.testing.expect(c.JS_ToBool(engine.context, value) == 0);
}
fn callPublic(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const function = try evaluate(engine, "subject");
    defer engine.freeValue(function);
    return engine.checked(c.JS_Call(engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)));
}

const Spec = struct { kind: Kind, formals: u16 = 1, length: c_int = 1, shape: Shape = .ordinary };
fn both(spec: Spec, program: []const u8, expected: ?[]const u32) !void {
    inline for (.{ false, true }) |native| {
        var probe: Probe = .{};
        const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer { probe.release(); engine.deinit(); }
        try prepare(engine, &probe, native, spec.kind, spec.formals, spec.length, spec.shape);
        try run(engine, program);
        if (expected) |order| try expectOrder(&probe, order);
        try clean(engine);
    }
}

test "VM sync arguments direct enough-argument calls mutate actual caller slots before the next observation" {
    try both(.{ .kind = .clear },
        \\globalThis.vmObserve=()=>{if(vmCount(0)!==1)throw Error("Original aliased parameter retained");vmNote(0)};
        \\subject(vmMake(0));
        \\if(vmCount(0)!==1)throw Error("Original argument retired twice or survived");
    , &.{0});
}

test "VM sync arguments public COPY_ARGV keeps borrowed input unchanged through body and return" {
    inline for (.{ false, true }) |native| {
        var probe: Probe = .{};
        const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer { probe.release(); engine.deinit(); }
        try prepare(engine, &probe, native, .clear, 1, 1, .ordinary);
        try run(engine, "globalThis.vmObserve=()=>{if(vmCount(0)!==0)throw Error('Public original input retired');vmNote(0)};");
        const input = try evaluate(engine, "vmMake(0)");
        var args = [_]c.JSValue{input};
        const output = try callPublic(engine, c.pi_js_undefined(), &args);
        engine.freeValue(output);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, input, args[0]));
        try std.testing.expectEqual(@as(u32, 0), probe.counts[0]);
        engine.freeValue(input);
        try expectOrder(&probe, &.{0});
        try clean(engine);
    }
}

test "VM sync arguments formal count remains independent of length for defaults and missing formals" {
    try both(.{ .kind = .default_clear, .formals = 2, .length = 0 },
        \\if(subject.length!==0)throw Error("Source default arity");
        \\globalThis.vmObserve=()=>{if(vmCount(0)!==0)throw Error("Missing formal did not copy")};
        \\subject(vmMake(0));
        \\if(vmCount(0)!==1)throw Error("Missing-formal caller retirement");
    , &.{0});
    try both(.{ .kind = .default_clear, .formals = 2, .length = 0 },
        \\globalThis.vmObserve=()=>{if(vmCount(0)!==0)throw Error("Default-scope initial parameter retired during body")};
        \\subject(vmMake(0),undefined);
        \\if(vmCount(0)!==1)throw Error("Default-scope initial parameter survived return");
    , &.{0});
}

test "VM sync arguments direct reassigned formal retires in actual caller after function locals" {
    try both(.{ .kind = .order },
        \\globalThis.vmObserve=()=>{if(vmCount(0)||vmCount(1))throw Error("Live frame holder retired")};
        \\subject(undefined);
        \\if(JSON.stringify(vmOrder())!=="[1,0]")throw Error("Actual aliased caller cleanup order");
    , &.{1,0});
}

test "VM sync arguments copied reassigned formal retires before original locals" {
    inline for (.{ false, true }) |native| {
        var probe: Probe = .{};
        const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer { probe.release(); engine.deinit(); }
        try prepare(engine, &probe, native, .order, 1, 1, .ordinary);
        var args = [_]c.JSValue{c.pi_js_undefined()};
        const output = try callPublic(engine, c.pi_js_undefined(), &args);
        engine.freeValue(output);
        try std.testing.expect(c.JS_IsUndefined(args[0]));
        try expectOrder(&probe, &.{0,1});
        try clean(engine);
    }
}

test "VM sync arguments missing actual argument uses copied-formal terminal order" {
    try both(.{ .kind = .order }, "subject();", &.{0,1});
    try both(.{ .kind = .order, .formals = 2, .length = 0 }, "subject(undefined);", &.{0,1});
}

test "VM sync arguments zero formal and unused extra actual arguments stay caller owned" {
    try both(.{ .kind = .zero, .formals = 0, .length = 0 },
        \\globalThis.vmObserve=()=>{if(vmCount(0)||vmCount(1))throw Error("Zero-formal live input")};
        \\subject(vmMake(0));
    , &.{1,0});
    try both(.{ .kind = .extra },
        \\globalThis.vmObserve=()=>{if(vmCount(0)||vmCount(1))throw Error("Unused extra live input")};
        \\subject(undefined,vmMake(0));
    , &.{1,0});
}

test "VM sync arguments actual Function call apply bound and spread routes keep their copy rule" {
    inline for (.{
        "subject.call(undefined,undefined)",
        "subject.apply(undefined,[undefined])",
        "Reflect.apply(subject,undefined,[undefined])",
        "subject.bind(undefined)(undefined)",
        "subject(...[undefined])",
    }) |call_text| {
        try both(.{ .kind = .order }, call_text ++ ";", &.{0,1});
    }
}

test "VM sync arguments converted original parameter retires before live observer and current value is read" {
    try both(.{ .kind = .rewrite },
        \\globalThis.vmObserve=value=>{if(value!=="converted"||vmCount(0)!==1)throw Error("Original parameter retained across next call")};
        \\function input(){const value=vmMake(0);value[Symbol.toPrimitive]=hint=>{if(hint!=="default")throw Error("Actual plus hint");return "converted"};return value}
        \\if(subject(input())!=="converted")throw Error("Read stale argv after assignment");
    , &.{0});
}

test "VM sync arguments escaped get and set share the actual parameter before and after return" {
    try both(.{ .kind = .pair },
        \\let pair=subject(vmMake(0));
        \\if(vmCount(0)||typeof pair.get!=="function"||typeof pair.set!=="function")throw Error("Escaped actual parameter");
        \\if(pair.get()!==pair.get())throw Error("Captured value identity");
        \\pair.set(vmMake(1));
        \\if(vmCount(0)!==1||vmCount(1))throw Error("Closed parameter assignment");
        \\pair=null;
        \\if(vmCount(1)!==1)throw Error("Hidden capture table retained the final value");
    , &.{0,1});
}

test "VM sync arguments dropping an unescaped capture does not duplicate the original formal" {
    try both(.{ .kind = .drop },
        \\globalThis.vmObserve=()=>{if(vmCount(0)!==1)throw Error("Dropped reference left hidden argument owner")};
        \\subject(vmMake(0));
    , &.{0});
}

test "VM sync arguments replacement is stored before old finalizer reenters captured getter" {
    try both(.{ .kind = .capture_clear },
        \\vmFinalize(index=>{if(index!==0||parameterGet()!==undefined)throw Error("Old slot visible during retirement");vmNote(1)});
        \\globalThis.vmObserve=()=>{if(vmCount(0)!==1)throw Error("Old original root retained");vmNote(2)};
        \\subject(vmMake(0));
        \\if(parameterGet()!==undefined)throw Error("Detached parameter changed");
    , &.{0});
}

test "VM sync arguments local captures detach before copied-argument finalizer mutates them" {
    try both(.{ .kind = .local_capture, .formals = 2, .length = 2 },
        \\vmFinalize(index=>{if(index!==0)throw Error("Copied parameter order");localSet(undefined);if(vmCount(1)!==0)throw Error("Original local retired with its closed cell");vmNote(1)});
        \\subject(undefined);
        \\if(localGet()!==undefined||vmCount(0)!==1||vmCount(1)!==1)throw Error("Actual detached local/original ownership");
    , &.{0,1});
}

test "VM sync arguments actual detached reference marks a reachable cycle and collects it once unreachable" {
    try both(.{ .kind = .cycle },
        \\globalThis.escaped=subject(undefined);
        \\vmCollect();
        \\if(vmCount(0)!==0||escaped().get!==escaped)throw Error("Reachable captured cycle collected");
        \\globalThis.escaped=null;
        \\vmCollect();vmCollect();
        \\if(vmCount(0)!==1)throw Error("Actual var-ref cycle not collected exactly once");
    , &.{0});
}

test "VM sync arguments methods and arrows preserve shapes and effective body receivers" {
    inline for (.{ Shape.method, Shape.arrow }) |shape| {
        try both(.{ .kind = .inspect, .formals = 2, .length = 2, .shape = shape },
            if (shape == .method)
                \\const receiver={},first={},second={};const result=Reflect.apply(subject,receiver,[first,second]);
                \\if(subject.length!==2||Object.hasOwn(subject,"prototype")||result[0]!==first||result[1]!==second||result[2]!==receiver)throw Error("Actual method receiver/shape");
                \\let failed=false;try{new subject()}catch(e){failed=e instanceof TypeError}if(!failed)throw Error("Method constructibility");
            else
                \\const receiver={},first={},second={};const result=Reflect.apply(subject,receiver,[first,second]);
                \\if(subject.length!==2||Object.hasOwn(subject,"prototype")||result[0]!==first||result[1]!==second||result[2]!==undefined)throw Error("Actual arrow receiver/shape");
                \\let failed=false;try{new subject()}catch(e){failed=e instanceof TypeError}if(!failed)throw Error("Arrow constructibility");
        , &.{});
    }
}

test "VM sync arguments constructor gets actual receiver and preserves primitive-return object selection" {
    try both(.{ .kind = .constructor_primitive },
        \\const marker={},prototype={};function Target(){};Target.prototype=prototype;
        \\const result=Reflect.construct(subject,[marker],Target);
        \\if(result.p!==marker||Object.getPrototypeOf(result)!==prototype)throw Error("Effective constructor receiver");
        \\if(!Object.hasOwn(subject,"prototype")||subject.prototype.constructor!==subject)throw Error("Ordinary constructor metadata");
    , &.{});
}

test "VM sync arguments constructor Object fallback follows actual foreign newTarget realm" {
    inline for (.{ false, true }) |native| {
        var probe: Probe = .{};
        const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer { probe.release(); engine.deinit(); }
        try prepare(engine, &probe, native, .constructor_primitive, 1, 1, .ordinary);
        const foreign = c.JS_NewContext(engine.runtime) orelse return error.OutOfMemory;
        defer c.JS_FreeContext(foreign);
        c.JS_SetContextOpaque(foreign, engine);
        const text = "(function(){function Target(){};Target.prototype=17;return Target})()";
        const target = try engine.checked(c.JS_Eval(foreign, text, text.len, "sync-foreign-target.js", c.JS_EVAL_TYPE_GLOBAL));
        defer engine.freeValue(target);
        const expected_text = "Object.prototype";
        const expected = try engine.checked(c.JS_Eval(foreign, expected_text, expected_text.len, "sync-foreign-prototype.js", c.JS_EVAL_TYPE_GLOBAL));
        defer engine.freeValue(expected);
        const function = try evaluate(engine, "subject"); defer engine.freeValue(function);
        var args = [_]c.JSValue{c.JS_NewInt32(engine.context, 37)};
        const object = try engine.checked(c.JS_CallConstructor2(engine.context, function, target, 1, &args)); defer engine.freeValue(object);
        const prototype = try engine.checked(c.JS_GetPrototype(engine.context, object)); defer engine.freeValue(prototype);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, prototype));
        try clean(engine);
    }
}

test "VM sync arguments ordinary private coercion throw preserves identity before later body" {
    try both(.{ .kind = .rewrite },
        \\globalThis.vmObserve=()=>{throw Error("Later body ran")};
        \\let reason,caught;try{subject({[Symbol.toPrimitive](){reason=syncHooks.freshPrivateData();throw reason}})}catch(error){caught=error}
        \\if(caught!==reason||!syncHooks.isUnmarkedPrivateData(reason))throw Error("Ordinary private DATA promoted by native span");
    , &.{});
}

test "VM sync arguments successful assigned private DATA stays ordinary and identical in closed reference" {
    try both(.{ .kind = .pair },
        \\const value=syncHooks.freshPrivateData();let pair=subject(undefined);
        \\if(pair.set(value)!==value||pair.get()!==value||!syncHooks.isUnmarkedPrivateData(value))throw Error("Assigned DATA promoted or copied by value");
        \\pair=null;
    , &.{});
}

test "VM sync arguments actual finalizer allocation fatal stops next body and guest catch" {
    inline for (.{ false, true }) |native| {
        var probe: Probe = .{};
        const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer { probe.release(); engine.deinit(); }
        try prepare(engine, &probe, native, .clear, 1, 1, .ordinary);
        probe.fatal[0] = true;
        const progress = try evaluate(engine, "globalThis.syncProgress={body:false,caught:false};syncProgress");
        defer engine.freeValue(progress);
        try std.testing.expectError(error.JavaScriptException, run(engine,
            \\const progress=syncProgress;globalThis.vmObserve=()=>{progress.body=true;vmNote(1)};
            \\try{subject(vmMake(0))}catch(error){progress.caught=true;vmNote(2)}
        ));
        const reason = engine.captured_exception orelse return error.MissingSyncArgumentRetirementFatal;
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, probe.reasons[0] orelse return error.MissingActualSyncArgumentFatalProducer));
        try std.testing.expectEqual(@as(u32, 1), probe.counts[0]);
        try std.testing.expectEqual(@as(u32, 0), probe.visits[1]);
        try std.testing.expectEqual(@as(u32, 0), probe.visits[2]);
        try expectOwnFalse(engine, progress, "body");
        try expectOwnFalse(engine, progress, "caught");
    }
}

test "VM sync arguments body producer fatal precedes distinct copied-argument and local pending failures" {
    inline for (.{ false, true }) |native| {
        var probe: Probe = .{};
        const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer { probe.release(); engine.deinit(); }
        try prepare(engine, &probe, native, .host_oom, 1, 1, .ordinary);
        inline for (.{0, 1}) |index| {
            const reason = try engine.checked(c.JS_NewError(engine.context));
            c.JS_SetUncatchableError(engine.context, reason);
            probe.cleanup_reasons[index] = reason;
        }
        try std.testing.expect(!c.JS_HasException(engine.context));
        const progress = try evaluate(engine, "globalThis.syncProgress={caught:false};syncProgress");
        defer engine.freeValue(progress);
        const before = engine.native_allocation_generation;
        try std.testing.expectError(error.JavaScriptException, run(engine,
            \\const progress=syncProgress;try{subject()}catch(error){progress.caught=true;vmNote(2)}
        ));
        const reason = engine.captured_exception orelse return error.MissingSyncArgumentBodyFatal;
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) == before +% 1);
        if (!native) try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, probe.reasons[15] orelse return error.MissingActualSourceBodyFatal));
        try expectOrder(&probe, &.{0,1});
        inline for (.{0, 1}) |index| {
            try std.testing.expect(probe.cleanup_published[index]);
            try std.testing.expect(!c.JS_IsStrictEqual(engine.context, reason, probe.cleanup_reasons[index].?));
        }
        try std.testing.expectEqual(@as(u32, 0), probe.visits[2]);
        try expectOwnFalse(engine, progress, "caught");
    }
}

test "VM sync arguments pending entry preserves original exception and leaves supplied slots untouched" {
    const engine = try Engine.init(std.testing.allocator, .{});
    var probe: Probe = .{};
    defer { probe.release(); engine.deinit(); }
    try prepare(engine, &probe, true, .clear, 1, 1, .ordinary);
    const function = try evaluate(engine, "subject"); defer engine.freeValue(function);
    const input = try evaluate(engine, "vmMake(0)"); defer engine.freeValue(input);
    const reason = try evaluate(engine, "({actual:'entry'})"); defer engine.freeValue(reason);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    var args = [_]c.JSValue{input};
    const output = c.JS_Call(engine.context, function, c.pi_js_undefined(), 1, &args);
    try std.testing.expect(c.JS_IsException(output));
    const observed = if (c.JS_HasException(engine.context)) c.JS_GetException(engine.context) else if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else return error.MissingOriginalPendingSyncReason;
    defer engine.freeValue(observed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, observed));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, input, args[0]));
    try std.testing.expectEqual(@as(u32, 0), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 0), probe.order_len);
}
