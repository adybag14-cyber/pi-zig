//! Actual mutable AsyncFunction formals: literal Source and native bodies run
//! in separate fresh Engines over the same sole C holders and real Await.
//! Defaults/prologue locals and mutable captured parameters are separate work.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const af = @import("extensions/native_async_function.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const Frame = @import("extensions/native_public_lexical_frame.zig").Frame(enum { local, reason });
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const Mode = enum { values, cycle, five, retained, zero, replace, caught, clear, body_fatal, pending_store };
const Token = struct { probe: *Probe, slot: usize };
const Probe = struct {
    engine: *Engine,
    native: bool,
    mode: Mode,
    holder_class: c.JSClassID = 0,
    tokens: [16]Token = undefined,
    made: [16]bool = @splat(false),
    counts: [16]u32 = @splat(0),
    order: [32]u8 = @splat(255),
    length: usize = 0,
    phase: usize = 0,
    starts: usize = 0,
    resumes: usize = 0,
    supplied: [4]usize = @splat(999),
    observed: usize = 0,
    observed_slots: [4][5]i32 = @splat(@splat(-1)),
    observed_counts: [4][16]u32 = @splat(@splat(99)),
    hook_calls: usize = 0,
    hook_counts: [16]u32 = @splat(99),
    hook_promise_state: c_int = -1,
    adoption_calls: usize = 0,
    adoption_counts: [16]u32 = @splat(99),
    current: ?*af.Arguments = null, // Borrowed only within the actual callback.
    observe_replacement: bool = false,
    replacement_seen: bool = false,
    replacement_checks: usize = 0,
    raw_pending_store: bool = false,
    pending_slot_unchanged: bool = false,
    pending_incoming_retired: bool = false,
    fatal: [16]bool = @splat(false),
    reasons: [16]?c.JSValue = @splat(null),
    cleanup_reasons: [16]?c.JSValue = @splat(null),
    cleanup_published: [16]bool = @splat(false),
    callbacks_enabled: bool = true,
    pending: c.JSValue,
    prior: c.JSValue,
    fn init(engine: *Engine, native: bool, mode: Mode) Probe {
        const empty = c.pi_js_undefined();
        return .{ .engine = engine, .native = native, .mode = mode, .pending = empty, .prior = empty };
    }
    fn deinit(self: *Probe) void {
        self.callbacks_enabled = false;
        self.current = null;
        self.pending = c.pi_js_undefined();
        for (&self.reasons) |*entry| { if (entry.*) |reason| { entry.* = null; self.engine.freeValue(reason); } }
        for (&self.cleanup_reasons) |*entry| { if (entry.*) |reason| { entry.* = null; self.engine.freeValue(reason); } }
        self.engine.freeValue(self.prior);
        self.engine.deinit();
        active = null;
    }
};
var active: ?*Probe = null;
fn tokenSlot(value: c.JSValue, probe: *Probe) i32 {
    const raw = c.JS_GetOpaque(value, probe.holder_class) orelse return -1;
    const token: *Token = @ptrCast(@alignCast(raw));
    return if (token.probe == probe) @intCast(token.slot) else -1;
}
fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const p = token.probe;
    p.counts[token.slot] += 1;
    if (p.length < p.order.len) p.order[p.length] = @intCast(token.slot);
    p.length += 1;
    if (!p.callbacks_enabled) return;
    if (p.observe_replacement and token.slot == 0) {
        p.replacement_checks += 1;
        if (p.current) |arguments| p.replacement_seen = tokenSlot(arguments.get(0), p) == 1;
    }
    if (p.cleanup_reasons[token.slot]) |reason| {
        p.cleanup_published[token.slot] = true;
        _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, reason));
    }
    if (p.fatal[token.slot]) {
        p.fatal[token.slot] = false;
        _ = p.engine.throwNativeOutOfMemoryFatal();
        if (c.JS_HasException(p.engine.context)) {
            const reason = c.JS_GetException(p.engine.context);
            p.reasons[token.slot] = c.JS_DupValue(p.engine.context, reason);
            _ = c.JS_Throw(p.engine.context, reason);
        }
    }
}
fn index(s: *Scope, value: c.JSValue) !usize {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    var slot: u32 = 0;
    try boundary.finishStatus(c.JS_ToUint32(s.engine.context, &slot, value));
    if (slot >= 16) return error.MutableAsyncArgumentControlSlot;
    return @intCast(slot);
}
fn helper(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    engine.checkNativeEntry() catch return engine.throwCaptured();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var scope: Scope = .{ .engine = engine };
    const result = v.owned.finishValue(&scope, helperBody(&scope, magic, if (argc > 0) argv[0..@intCast(argc)] else &.{})) catch |err|
        @import("extensions/native_sdk.zig").fail(engine, err);
    return engine.leaveNativeInvocation(&invocation, result);
}
fn helperBody(s: *Scope, magic: c_int, args: []const c.JSValue) !c.JSValue {
    const p = active.?;
    if (magic == 2) {
        const result = try v.array(s);
        for (p.order[0..p.length], 0..) |item, position| try v.index(s, result, @intCast(position), c.JS_NewUint32(s.engine.context, item));
        return v.duplicate(s, result);
    }
    if (magic == 3) {
        if (p.observed >= p.observed_slots.len) return error.TooManyAsyncArgumentObservations;
        for (0..5) |position| p.observed_slots[p.observed][position] = tokenSlot(v.arg(args, position), p);
        p.observed_counts[p.observed] = p.counts;
        p.observed += 1;
        return c.pi_js_undefined();
    }
    if (magic == 4) {
        p.adoption_calls += 1; p.adoption_counts = p.counts;
        return c.pi_js_undefined();
    }
    if (magic == 5) {
        _ = s.engine.throwNativeOutOfMemoryFatal();
        const reason = c.JS_GetException(s.engine.context);
        p.reasons[15] = c.JS_DupValue(s.engine.context, reason);
        return s.engine.checked(c.JS_Throw(s.engine.context, reason));
    }
    const slot = try index(s, v.arg(args, 0));
    if (magic == 1) return c.JS_NewUint32(s.engine.context, p.counts[slot]);
    if (p.made[slot]) return error.AsyncArgumentHolderReused;
    const result = try v.objectClass(s, p.holder_class);
    p.made[slot] = true;
    _ = c.JS_SetOpaque(result, &p.tokens[slot]);
    return v.duplicate(s, result);
}
fn callBody(s: *Scope, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const callable = try v.global(s, name);
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), args));
}
fn callOwned(engine: *Engine, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return v.owned.finishValue(&scope, callBody(&scope, name, args));
}
fn makeOwned(engine: *Engine, slot: u32) !c.JSValue {
    return callOwned(engine, "amMake", &.{c.JS_NewUint32(engine.context, slot)});
}
fn observe(engine: *Engine, args: []const c.JSValue) !void {
    var completion = v.owned.Completion.initValue(engine, callOwned(engine, "amObserve", args));
    const result = try completion.finishValue();
    var retirement_completion = v.owned.Completion.initVoid(engine, {});
    retirement_completion.release(result);
    return retirement_completion.finishVoid();
}
fn ownedGlobal(engine: *Engine, name: [*:0]const u8) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const result: anyerror!c.JSValue = if (v.global(&scope, name)) |value| v.duplicate(&scope, value) else |err| err;
    return v.owned.finishValue(&scope, result);
}
fn closeState(engine: *Engine, owner: c.JSValue) !void {
    const p = active.?;
    p.hook_calls += 1; p.hook_counts = p.counts;
    if (!c.JS_IsUndefined(p.pending)) p.hook_promise_state = c.JS_PromiseState(engine.context, p.pending);
    return Frame.closeAtAsyncTerminal(engine, owner);
}
fn nativeBody(engine: *Engine, receiver: c.JSValue, arguments: *af.Arguments, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const p = active.?;
    p.current = arguments;
    defer p.current = null;
    const entry = if (completion == .start) 0 else p.resumes + 1;
    if (entry < p.supplied.len) p.supplied[entry] = arguments.supplied.len;
    var scope: Scope = .{ .engine = engine };
    return v.owned.finishAction(&scope, advance(&scope, receiver, arguments, state, completion, input));
}
fn startFrame(s: *Scope, state: *c.JSValue) !*Frame {
    const frame = try Frame.createAsync(s);
    af.replaceState(s.engine, state, v.duplicate(s, frame.owner));
    return frame;
}
fn advance(s: *Scope, receiver: c.JSValue, arguments: *af.Arguments, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const p = active.?;
    if (completion == .start) {
        p.starts += 1; p.phase = 1;
        const frame = try startFrame(s, state);
        if (p.mode != .values and p.mode != .caught) try frame.take(.local, makeOwned(s.engine, 6));
        if (p.mode == .cycle) {
            try arguments.take(0, makeOwned(s.engine, 3));
            try arguments.take(2, makeOwned(s.engine, 4));
        } else if (p.mode == .retained) try arguments.take(2, makeOwned(s.engine, 4));
        return .{ .awaited = if (p.mode == .values) c.pi_js_undefined() else try ownedGlobal(s.engine, "amGate") };
    }
    p.resumes += 1;
    const frame = Frame.from(state.*);
    if (p.mode == .caught and p.phase == 1) {
        if (completion == .rejected) {
            try frame.copy(.reason, input);
            try arguments.copy(2, frame.get(.reason));
        }
        p.phase = 2;
        return .{ .awaited = c.pi_js_undefined() };
    }
    if (completion == .rejected) return .{ .thrown = v.duplicate(s, input) };
    switch (p.mode) {
        .values => {
            try arguments.take(2, c.JS_NewInt32(s.engine.context, 17));
            const result = try v.array(s);
            inline for (0..3) |position| try v.index(s, result, position, arguments.get(position));
            try v.index(s, result, 3, c.JS_NewUint32(s.engine.context, @intCast(arguments.supplied.len)));
            try v.index(s, result, 4, receiver);
            return .{ .returned = v.duplicate(s, result) };
        },
        .cycle => {
            try observe(s.engine, &.{arguments.get(0), arguments.get(1), arguments.get(2), receiver, frame.get(.local)});
            try arguments.take(0, makeOwned(s.engine, 5));
            try observe(s.engine, &.{arguments.get(0), arguments.get(1), arguments.get(2), receiver, frame.get(.local)});
        },
        .five => {
            if (p.phase == 1) {
                try arguments.take(2, makeOwned(s.engine, 2));
                try arguments.take(3, makeOwned(s.engine, 3));
                try arguments.take(4, makeOwned(s.engine, 4));
                p.phase = 2;
                return .{ .awaited = c.pi_js_undefined() };
            }
            try observe(s.engine, &.{arguments.get(2), arguments.get(3), arguments.get(4), receiver, frame.get(.local)});
            try arguments.take(2, c.pi_js_undefined());
        },
        .retained => try observe(s.engine, &.{arguments.get(0), arguments.get(1), arguments.get(2), receiver, frame.get(.local)}),
        .zero => try observe(s.engine, &.{}),
        .replace => {
            try arguments.take(0, makeOwned(s.engine, 1));
            try observe(s.engine, &.{arguments.get(0), arguments.get(1), arguments.get(2), receiver, frame.get(.local)});
        },
        .caught => return .{ .returned = v.duplicate(s, arguments.get(2)) },
        .clear => {
            try arguments.take(0, c.pi_js_undefined());
            try observe(s.engine, &.{});
        },
        .body_fatal => {
            const output = try callOwned(s.engine, "amOOM", &.{});
            var completed = v.owned.Completion.initVoid(s.engine, {}); completed.release(output); try completed.finishVoid();
            try observe(s.engine, &.{});
        },
        .pending_store => {
            const before = arguments.get(2);
            const incoming = try makeOwned(s.engine, 4);
            _ = c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, p.prior));
            const failure: anyerror!void = if (p.raw_pending_store) block: {
                const status = c.JS_PiAsyncArgumentSet(s.engine.context, arguments.frame, 2, incoming);
                break :block if (status < 0) @as(anyerror!void, error.JavaScriptException) else {};
            } else arguments.take(2, incoming);
            p.pending_slot_unchanged = c.JS_IsStrictEqual(s.engine.context, before, arguments.get(2));
            p.pending_incoming_retired = p.counts[4] == 1;
            try failure;
            return error.PendingStoreUnexpectedlySucceeded;
        },
    }
    return .{ .returned = try ownedGlobal(s.engine, "amReturn") };
}
fn source(mode: Mode) []const u8 {
    return switch (mode) {
        .values => "\"use strict\";globalThis.subject=async function(a,b,c){await undefined;c=17;return [a,b,c,arguments.length,this]};Object.defineProperty(subject,'length',{value:0});",
        .cycle => "\"use strict\";globalThis.subject=async function(a,b,c){const local=amMake(6);a=amMake(3);c=amMake(4);await amGate;amObserve(a,b,c,this,local);a=amMake(5);amObserve(a,b,c,this,local);return amReturn};",
        .five => "\"use strict\";globalThis.subject=async function(a,b,c,d,e){const local=amMake(6);await amGate;c=amMake(2);d=amMake(3);e=amMake(4);await undefined;amObserve(c,d,e,this,local);c=undefined;return amReturn};",
        .retained => "\"use strict\";globalThis.subject=async function(a,b,c){const local=amMake(6);c=amMake(4);await amGate;amObserve(a,b,c,this,local);return amReturn};",
        .zero => "\"use strict\";globalThis.subject=async function(){const local=amMake(6);await amGate;amObserve();return amReturn};",
        .replace => "\"use strict\";globalThis.subject=async function(a,b,c){const local=amMake(6);await amGate;a=amMake(1);amObserve(a,b,c,this,local);return amReturn};",
        .caught => "\"use strict\";globalThis.subject=async function(a,b,c){try{await amGate}catch(reason){c=reason}await undefined;return c};",
        .clear => "\"use strict\";globalThis.subject=async function(a,b,c){const local=amMake(6);await amGate;try{a=undefined;amObserve()}catch(reason){amProgress.caught=true}return 17};",
        .body_fatal => "\"use strict\";globalThis.subject=async function(a,b,c){const local=amMake(6);await amGate;try{amOOM();amObserve()}catch(reason){amProgress.caught=true}return 17};",
        .pending_store => unreachable,
    };
}
fn evaluate(engine: *Engine, text: []const u8) !c.JSValue {
    return engine.eval(text, "actual-mutable-async-arguments.js", c.JS_EVAL_TYPE_GLOBAL);
}
fn run(engine: *Engine, text: []const u8) !void { engine.freeValue(try evaluate(engine, text)); }
const Spec = struct { mode: Mode, formals: u16 = 3, length: c_int = 3, arrow: bool = false };
fn setup(p: *Probe, comptime spec: Spec) !void {
    active = p;
    for (&p.tokens, 0..) |*token, position| token.* = .{ .probe = p, .slot = position };
    if (c.JS_NewClassID(p.engine.runtime, &p.holder_class) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Actual mutable async formal sole holder", .finalizer = finalize };
    if (c.JS_NewClass(p.engine.runtime, p.holder_class, &definition) < 0) return error.OutOfMemory;
    var scope: Scope = .{ .engine = p.engine };
    try v.owned.finishVoid(&scope, setupBody(&scope, p, spec));
    try run(p.engine, "globalThis.amGate=undefined;globalThis.amReturn=23;");
    if (!p.native) {
        if (spec.arrow) try run(p.engine,
            "\"use strict\";globalThis.sourceArrowFactory=function(){return async(a,b,c)=>{const local=amMake(6);c=amMake(4);await amGate;amObserve(a,b,c,this,local);return amReturn}};globalThis.subject=Reflect.apply(sourceArrowFactory,amMake(9),[]);")
        else try run(p.engine, source(spec.mode));
    }
}
fn setupBody(s: *Scope, p: *Probe, comptime spec: Spec) !void {
    const global = try v.global(s, "globalThis");
    inline for (.{ "amMake", "amCount", "amOrder", "amObserve", "amAdoption", "amOOM" }, 0..) |name, magic| {
        var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
        const callable = try boundary.finishValue(s, c.JS_NewCFunctionData2(s.engine.context, helper, name, 1, magic, 0, null));
        try v.put(s, global, name, callable);
    }
    try v.put(s, global, "amHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
    if (p.native) {
        const definition: af.ArgumentDefinition = .{ .formal_count = spec.formals, .body = nativeBody, .close = closeState };
        const lexical_this = if (spec.arrow) try v.own(s, try makeOwned(s.engine, 9)) else c.pi_js_undefined();
        const function = try v.own(s, try if (spec.arrow)
            af.createResumableArrowWithArguments(s.engine, "subject", spec.length, definition, &.{}, lexical_this)
            else af.createResumableWithArguments(s.engine, "subject", spec.length, definition, &.{}));
        try v.put(s, global, "subject", function);
    }
}
fn start(p: *Probe, program: []const u8) !c.JSValue {
    try run(p.engine, program);
    const pending = try evaluate(p.engine, "amPending");
    errdefer p.engine.freeValue(pending);
    c.JS_PromiseMarkAsHandled(p.engine.context, pending);
    p.pending = pending; // Borrowed until the test releases this root.
    return pending;
}
fn job(p: *Probe) !void {
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(p.engine.runtime, &context) > 0);
    try std.testing.expect(!c.JS_HasException(p.engine.context));
    p.engine.finishJob();
}
fn done(p: *Probe, pending: c.JSValue, expected_state: c_int) !void {
    try std.testing.expectEqual(expected_state, c.JS_PromiseState(p.engine.context, pending));
    try std.testing.expect(!c.JS_IsJobPending(p.engine.runtime));
    try std.testing.expect(!c.JS_HasException(p.engine.context));
    try std.testing.expect(p.current == null);
    try std.testing.expect(p.engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), p.engine.native_exception_diagnostics_suppressed);
}
fn allRetired(p: *Probe) !void {
    for (p.counts, 0..) |count, position| try std.testing.expectEqual(@as(u32, if (p.made[position]) 1 else 0), count);
}
fn expectOrder(p: *Probe, expected: []const u8) !void {
    try std.testing.expectEqualSlices(u8, expected, p.order[0..p.length]);
}
fn ownFalse(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !void {
    const value = c.JS_GetPropertyStr(engine.context, object, name);
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsBool(value));
    try std.testing.expect(c.JS_ToBool(engine.context, value) == 0);
}
fn fatalJob(p: *Probe) !c.JSValue {
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(p.engine.runtime, &context) < 0);
    try std.testing.expect(c.JS_HasException(p.engine.context));
    const reason = c.JS_GetException(p.engine.context);
    errdefer p.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(p.current == null);
    try std.testing.expect(p.engine.native_fatal_invocation == null);
    return reason;
}

test "VM async arguments supplied count and initialized formals remain independent of observable length" {
    inline for (.{ false, true }) |native| {
        inline for (.{
            .{ @as(usize, 0), "globalThis.amPending=Reflect.apply(subject,null,[]);void 0;" },
            .{ @as(usize, 1), "globalThis.amPending=Reflect.apply(subject,null,[11]);void 0;" },
            .{ @as(usize, 2), "globalThis.amPending=Reflect.apply(subject,null,[11,22]);void 0;" },
            .{ @as(usize, 4), "globalThis.amPending=Reflect.apply(subject,null,[11,22,33,44]);void 0;" },
        }) |row| {
            var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .values); defer p.deinit();
            try setup(&p, .{ .mode = .values, .length = 0 });
            try run(p.engine, "if(subject.length!==0||Object.hasOwn(subject,'prototype')||Object.getPrototypeOf(subject)!==Object.getPrototypeOf(async()=>{}))throw Error('Actual async function shape');");
            const pending = try start(&p, row[1]); defer p.engine.freeValue(pending);
            try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
            try job(&p); try done(&p, pending, c.JS_PROMISE_FULFILLED);
            const result = c.JS_PromiseResult(p.engine.context, pending); defer p.engine.freeValue(result);
            const expected = [_]c.JSValue{
                if (row[0] > 0) c.JS_NewInt32(p.engine.context, 11) else c.pi_js_undefined(),
                if (row[0] > 1) c.JS_NewInt32(p.engine.context, 22) else c.pi_js_undefined(),
                c.JS_NewInt32(p.engine.context, 17), c.JS_NewUint32(p.engine.context, @intCast(row[0])),
            };
            for (expected, 0..) |value, position| {
                const actual = c.JS_GetPropertyUint32(p.engine.context, result, @intCast(position)); defer p.engine.freeValue(actual);
                try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, value, actual));
            }
            const receiver = c.JS_GetPropertyUint32(p.engine.context, result, 4); defer p.engine.freeValue(receiver);
            try std.testing.expect(c.JS_IsNull(receiver));
            if (native) {
                try std.testing.expectEqual(row[0], p.supplied[0]);
                try std.testing.expectEqual(row[0], p.supplied[1]);
            }
        }
    }
}
test "VM async arguments assignments before and after real Await use the same original formal slots" {
    inline for (.{ false, true }) |native| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .cycle); defer p.deinit();
        try setup(&p, .{ .mode = .cycle });
        const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0),amMake(1)]);void 0;"); defer p.engine.freeValue(pending);
        try std.testing.expectEqual(@as(u32, 1), p.counts[0]);
        inline for (.{1, 3, 4, 6, 7}) |slot| try std.testing.expectEqual(@as(u32, 0), p.counts[slot]);
        try job(&p); try done(&p, pending, c.JS_PROMISE_FULFILLED); try allRetired(&p);
        try std.testing.expectEqual(@as(usize, 2), p.observed);
        try std.testing.expectEqualSlices(i32, &.{3, 1, 4, 7, 6}, &p.observed_slots[0]);
        try std.testing.expectEqualSlices(i32, &.{5, 1, 4, 7, 6}, &p.observed_slots[1]);
        try std.testing.expectEqual(@as(u32, 0), p.observed_counts[0][3]);
        try std.testing.expectEqual(@as(u32, 1), p.observed_counts[1][3]);
        try expectOrder(&p, &.{0, 3, 5, 1, 4, 6, 7});
    }
}
test "VM async arguments missing fourth and fifth formals retain assignments through another actual Await and GC" {
    inline for (.{ false, true }) |native| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .five); defer p.deinit();
        try setup(&p, .{ .mode = .five, .formals = 5, .length = 5 });
        const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0),amMake(1)]);void 0;"); defer p.engine.freeValue(pending);
        try job(&p);
        try std.testing.expect(c.JS_IsJobPending(p.engine.runtime));
        inline for (.{0, 1, 2, 3, 4, 6, 7}) |slot| {
            try std.testing.expect(p.made[slot]);
            try std.testing.expectEqual(@as(u32, 0), p.counts[slot]);
        }
        c.JS_RunGC(p.engine.runtime);
        inline for (.{0, 1, 2, 3, 4, 6, 7}) |slot| try std.testing.expectEqual(@as(u32, 0), p.counts[slot]);
        try job(&p); try done(&p, pending, c.JS_PROMISE_FULFILLED); try allRetired(&p);
        try std.testing.expectEqualSlices(i32, &.{2, 3, 4, 7, 6}, &p.observed_slots[0]);
        try expectOrder(&p, &.{2, 0, 1, 3, 4, 6, 7});
        if (native) try std.testing.expectEqualSlices(usize, &.{2, 2, 2}, p.supplied[0..3]);
    }
}
test "VM async arguments unused supplied extras remain owned after overwritten formals and retire before locals" {
    inline for (.{ false, true }) |native| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .cycle); defer p.deinit();
        try setup(&p, .{ .mode = .cycle });
        const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0),amMake(1),amMake(2),amMake(8)]);void 0;"); defer p.engine.freeValue(pending);
        try std.testing.expectEqual(@as(u32, 1), p.counts[0]);
        try std.testing.expectEqual(@as(u32, 1), p.counts[2]);
        try std.testing.expectEqual(@as(u32, 0), p.counts[8]);
        try job(&p); try done(&p, pending, c.JS_PROMISE_FULFILLED); try allRetired(&p);
        try std.testing.expectEqual(@as(u32, 0), p.observed_counts[0][8]);
        try std.testing.expectEqual(@as(u32, 0), p.observed_counts[1][8]);
        if (native) {
            try std.testing.expectEqualSlices(usize, &.{4, 4}, p.supplied[0..2]);
            inline for (.{1, 4, 5, 8}) |slot| try std.testing.expectEqual(@as(u32, 1), p.hook_counts[slot]);
            inline for (.{6, 7}) |slot| try std.testing.expectEqual(@as(u32, 0), p.hook_counts[slot]);
        }
    }
}
test "VM async arguments zero declared formals still retain every supplied argument through suspension" {
    inline for (.{ false, true }) |native| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .zero); defer p.deinit();
        try setup(&p, .{ .mode = .zero, .formals = 0, .length = 0 });
        const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0),amMake(1)]);void 0;"); defer p.engine.freeValue(pending);
        try std.testing.expectEqual(@as(u32, 0), p.counts[0]);
        try std.testing.expectEqual(@as(u32, 0), p.counts[1]);
        try job(&p); try done(&p, pending, c.JS_PROMISE_FULFILLED); try allRetired(&p);
        try expectOrder(&p, &.{0, 1, 6, 7});
        if (native) try std.testing.expectEqualSlices(usize, &.{2, 2}, p.supplied[0..2]);
    }
}
test "VM async arguments store publishes the replacement before the sole prior holder finalizer reads its actual slot" {
    var p = Probe.init(try Engine.init(std.testing.allocator, .{}), true, .replace); defer p.deinit();
    try setup(&p, .{ .mode = .replace });
    p.observe_replacement = true;
    const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0)]);void 0;"); defer p.engine.freeValue(pending);
    try std.testing.expect(p.current == null);
    try std.testing.expectEqual(@as(usize, 0), p.replacement_checks);
    try job(&p); try done(&p, pending, c.JS_PROMISE_FULFILLED);
    try std.testing.expectEqual(@as(usize, 1), p.replacement_checks);
    try std.testing.expect(p.replacement_seen);
    try std.testing.expectEqualSlices(i32, &.{1, -1, -1, 7, 6}, &p.observed_slots[0]);
    try expectOrder(&p, &.{0, 1, 6, 7}); try allRetired(&p);
}
test "VM async arguments actual caught private Await rejection can initialize a missing formal and return after another Await" {
    inline for (.{ false, true }) |native| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .caught); defer p.deinit();
        try setup(&p, .{ .mode = .caught });
        try run(p.engine, "globalThis.amReason=amHooks.freshPrivateData();globalThis.amGate=Promise.reject(amReason);");
        const expected = try evaluate(p.engine, "amReason"); defer p.engine.freeValue(expected);
        const pending = try start(&p, "globalThis.amPending=subject();void 0;"); defer p.engine.freeValue(pending);
        try job(&p); try std.testing.expect(c.JS_IsJobPending(p.engine.runtime));
        try job(&p); try done(&p, pending, c.JS_PROMISE_FULFILLED);
        const result = c.JS_PromiseResult(p.engine.context, pending); defer p.engine.freeValue(result);
        try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, result, expected));
        try run(p.engine, "if(!amHooks.isUnmarkedPrivateData(amReason))throw Error('Assigned private DATA was promoted');");
        if (native) try std.testing.expectEqualSlices(usize, &.{0, 0, 0}, p.supplied[0..3]);
    }
}
test "VM async arguments uncaught ordinary Await rejection preserves raw identity while expanded formals retire" {
    inline for (.{ false, true }) |native| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .retained); defer p.deinit();
        try setup(&p, .{ .mode = .retained });
        try run(p.engine, "globalThis.amReason=amHooks.freshPrivateData();globalThis.amGate=Promise.reject(amReason);");
        const expected = try evaluate(p.engine, "amReason"); defer p.engine.freeValue(expected);
        const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0),amMake(1)]);void 0;"); defer p.engine.freeValue(pending);
        try job(&p); try done(&p, pending, c.JS_PROMISE_REJECTED); try allRetired(&p);
        const result = c.JS_PromiseResult(p.engine.context, pending); defer p.engine.freeValue(result);
        try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, result, expected));
        try std.testing.expectEqual(@as(usize, 0), p.observed);
        try run(p.engine, "if(!amHooks.isUnmarkedPrivateData(amReason))throw Error('Forwarded rejection was promoted');");
    }
}
test "VM async arguments genuine return adoption sees current formals alive before ordered terminal close" {
    inline for (.{ false, true }) |native| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .retained); defer p.deinit();
        try setup(&p, .{ .mode = .retained });
        try run(p.engine, "globalThis.amReturn={get then(){amAdoption();return undefined}};");
        const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0),amMake(1)]);void 0;"); defer p.engine.freeValue(pending);
        try job(&p); try done(&p, pending, c.JS_PROMISE_FULFILLED); try allRetired(&p);
        try std.testing.expectEqual(@as(usize, 1), p.adoption_calls);
        inline for (.{0, 1, 4, 6, 7}) |slot| try std.testing.expectEqual(@as(u32, 0), p.adoption_counts[slot]);
        try expectOrder(&p, &.{0, 1, 4, 6, 7});
        if (native) {
            try std.testing.expectEqual(@as(usize, 1), p.hook_calls);
            inline for (.{0, 1, 4}) |slot| try std.testing.expectEqual(@as(u32, 1), p.hook_counts[slot]);
            inline for (.{6, 7}) |slot| try std.testing.expectEqual(@as(u32, 0), p.hook_counts[slot]);
            try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, p.hook_promise_state);
        }
    }
}
test "VM async arguments missing assigned formal is marked during live GC and retires on actual gate abandonment" {
    inline for (.{ false, true }) |native| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .retained); defer p.deinit();
        try setup(&p, .{ .mode = .retained });
        try run(p.engine, "globalThis.amGate=new Promise(()=>{});");
        const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0),amMake(1)]);void 0;"); defer p.engine.freeValue(pending);
        try std.testing.expect(!c.JS_IsJobPending(p.engine.runtime));
        c.JS_RunGC(p.engine.runtime);
        inline for (.{0, 1, 4, 6, 7}) |slot| try std.testing.expectEqual(@as(u32, 0), p.counts[slot]);
        try run(p.engine, "delete globalThis.amGate;");
        try allRetired(&p);
        // A real Promise/reaction finalizer already runs inside DECREF; the
        // existing head-inserted queue observes these releases in reverse.
        try expectOrder(&p, &.{7, 6, 4, 1, 0});
        try std.testing.expectEqual(@as(usize, 0), p.observed);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
        if (native) {
            try std.testing.expectEqual(@as(usize, 1), p.hook_calls);
            try std.testing.expectEqual(@as(usize, 0), p.resumes);
        }
    }
}
test "VM async arguments real arrow keeps lexical this separate from the supplied receiver while formals mutate" {
    inline for (.{ false, true }) |native| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .retained); defer p.deinit();
        try setup(&p, .{ .mode = .retained, .arrow = true });
        const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0),amMake(1)]);delete globalThis.subject;void 0;"); defer p.engine.freeValue(pending);
        inline for (.{0, 1, 4, 6, 7, 9}) |slot| try std.testing.expectEqual(@as(u32, 0), p.counts[slot]);
        try job(&p); try done(&p, pending, c.JS_PROMISE_FULFILLED); try allRetired(&p);
        try std.testing.expectEqualSlices(i32, &.{0, 1, 4, 9, 6}, &p.observed_slots[0]);
        try expectOrder(&p, &.{0, 1, 4, 6, 9, 7});
    }
}
const LegacyObservation = struct { calls: usize = 0, null_result: bool = false, actual_pending: bool = false };
var legacy_observation: LegacyObservation = .{};
fn legacyProbe(engine: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, _: af.Completion, _: c.JSValue) !af.Action {
    legacy_observation.calls += 1;
    legacy_observation.null_result = c.JS_PiGetNativeAsyncArguments(engine.context) == null;
    legacy_observation.actual_pending = c.JS_HasException(engine.context);
    if (!legacy_observation.null_result) return error.LegacyAsyncExposedMutableArguments;
    return error.JavaScriptException;
}
test "VM async arguments current getter rejects absent and legacy invocations while preserving an entry exception" {
    const engine = try Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try std.testing.expect(c.JS_PiGetNativeAsyncArguments(engine.context) == null);
    try std.testing.expect(c.JS_HasException(engine.context));
    const absent = c.JS_GetException(engine.context); defer engine.freeValue(absent);
    try std.testing.expect(!c.JS_IsUncatchableError(absent));
    const original = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(original);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, original));
    try std.testing.expect(c.JS_PiGetNativeAsyncArguments(engine.context) == null);
    const preserved = c.JS_GetException(engine.context); defer engine.freeValue(preserved);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, preserved));
    legacy_observation = .{};
    defer legacy_observation = .{};
    const function = try af.createResumable(engine, "legacy", 0, legacyProbe, &.{}); defer engine.freeValue(function);
    const pending = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null)); defer engine.freeValue(pending);
    c.JS_PromiseMarkAsHandled(engine.context, pending);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, pending));
    try std.testing.expectEqual(@as(usize, 1), legacy_observation.calls);
    try std.testing.expect(legacy_observation.null_result);
    try std.testing.expect(legacy_observation.actual_pending);
    try std.testing.expect(!c.JS_HasException(engine.context));
}
test "VM async arguments pending call entry leaves the original supplied slot and body untouched" {
    var p = Probe.init(try Engine.init(std.testing.allocator, .{}), true, .clear); defer p.deinit();
    try setup(&p, .{ .mode = .clear });
    const function = try evaluate(p.engine, "subject"); defer p.engine.freeValue(function);
    const supplied = try evaluate(p.engine, "amMake(0)"); defer p.engine.freeValue(supplied);
    const original = try p.engine.checked(c.JS_NewError(p.engine.context)); defer p.engine.freeValue(original);
    _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, original));
    var args = [_]c.JSValue{supplied};
    const output = c.JS_Call(p.engine.context, function, c.pi_js_undefined(), 1, &args);
    try std.testing.expect(c.JS_IsException(output));
    const reason = c.JS_GetException(p.engine.context); defer p.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, original, reason));
    try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, supplied, args[0]));
    try std.testing.expectEqual(@as(usize, 0), p.starts);
    try std.testing.expectEqual(@as(u32, 0), p.counts[0]);
}
test "VM async arguments pending store consumes its incoming owner without changing the selected formal" {
    inline for (.{ false, true }) |raw| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), true, .pending_store); defer p.deinit();
        try setup(&p, .{ .mode = .pending_store });
        p.raw_pending_store = raw;
        p.prior = try p.engine.checked(c.JS_NewError(p.engine.context));
        const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0),amMake(1),amMake(2)]);void 0;"); defer p.engine.freeValue(pending);
        try job(&p); try done(&p, pending, c.JS_PROMISE_REJECTED);
        try std.testing.expect(p.pending_slot_unchanged);
        try std.testing.expect(p.pending_incoming_retired);
        try allRetired(&p);
        const reason = c.JS_PromiseResult(p.engine.context, pending); defer p.engine.freeValue(reason);
        try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, p.prior, reason));
    }
}
test "VM async arguments actual assignment finalizer fatal prevents the next body and guest catch after Await" {
    inline for (.{ false, true }) |native| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .clear); defer p.deinit();
        try setup(&p, .{ .mode = .clear });
        const progress = try evaluate(p.engine, "globalThis.amProgress={body:false,caught:false};amProgress"); defer p.engine.freeValue(progress);
        try run(p.engine, "globalThis.amObserve=()=>{amProgress.body=true};");
        const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0)]);void 0;"); defer p.engine.freeValue(pending);
        p.fatal[0] = true;
        const before = p.engine.native_allocation_generation;
        const reason = try fatalJob(&p); defer p.engine.freeValue(reason);
        try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, reason, p.reasons[0] orelse return error.MissingAsyncAssignmentFatalProducer));
        try std.testing.expectEqual(before +% 1, c.pi_js_native_allocation_error_generation(reason));
        try ownFalse(p.engine, progress, "body"); try ownFalse(p.engine, progress, "caught");
        try allRetired(&p);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
    }
}
test "VM async arguments actual body fatal wins later parameter and local cleanup events with every root retired" {
    var p = Probe.init(try Engine.init(std.testing.allocator, .{}), true, .body_fatal); defer p.deinit();
    try setup(&p, .{ .mode = .body_fatal });
    const progress = try evaluate(p.engine, "globalThis.amProgress={body:false,caught:false};amProgress"); defer p.engine.freeValue(progress);
    try run(p.engine, "globalThis.amObserve=()=>{amProgress.body=true};");
    inline for (.{0, 6}) |slot| {
        const reason = try p.engine.checked(c.JS_NewError(p.engine.context));
        c.JS_SetUncatchableError(p.engine.context, reason); p.cleanup_reasons[slot] = reason;
    }
    const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0)]);void 0;"); defer p.engine.freeValue(pending);
    const before = p.engine.native_allocation_generation;
    const reason = try fatalJob(&p); defer p.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, reason, p.reasons[15] orelse return error.MissingAsyncBodyFatalProducer));
    try std.testing.expectEqual(before +% 1, c.pi_js_native_allocation_error_generation(reason));
    inline for (.{0, 6}) |slot| {
        try std.testing.expect(p.cleanup_published[slot]);
        try std.testing.expect(!c.JS_IsStrictEqual(p.engine.context, reason, p.cleanup_reasons[slot].?));
    }
    try ownFalse(p.engine, progress, "body"); try ownFalse(p.engine, progress, "caught");
    try allRetired(&p); try expectOrder(&p, &.{0, 6, 7});
}
test "VM async arguments current fatal before the second resume retires all assigned missing slots without body entry" {
    inline for (.{ false, true }) |native| {
        var p = Probe.init(try Engine.init(std.testing.allocator, .{}), native, .five); defer p.deinit();
        try setup(&p, .{ .mode = .five, .formals = 5, .length = 5 });
        const pending = try start(&p, "globalThis.amPending=Reflect.apply(subject,amMake(7),[amMake(0),amMake(1)]);void 0;"); defer p.engine.freeValue(pending);
        try job(&p);
        try std.testing.expectEqual(@as(usize, if (native) 1 else 0), p.resumes);
        p.prior = try p.engine.checked(c.JS_NewError(p.engine.context));
        c.JS_SetUncatchableError(p.engine.context, p.prior);
        _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, p.prior));
        const reason = try fatalJob(&p); defer p.engine.freeValue(reason);
        try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, p.prior, reason));
        try std.testing.expectEqual(@as(usize, if (native) 1 else 0), p.resumes);
        try std.testing.expectEqual(@as(usize, 0), p.observed);
        try std.testing.expectEqual(@as(usize, if (native) 1 else 0), p.hook_calls);
        // Pending-job admission skips the body and frees its resolving handler.
        // Retirement is already inside DECREF: ascending root releases enter the
        // queue at its head, so their finalizers run in reverse release order.
        if (native) {
            for ([_]usize{ 0, 1, 2, 3, 4, 6, 7 }) |slot|
                try std.testing.expectEqual(@as(u32, 0), p.hook_counts[slot]);
            try std.testing.expectEqual(c.JS_PROMISE_PENDING, p.hook_promise_state);
        }
        try expectOrder(&p, &.{7, 6, 4, 3, 2, 1, 0}); try allRetired(&p);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
    }
}
