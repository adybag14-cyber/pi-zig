//! Actual suspended async-frame retirement controls in the linked C runtime.
//! The source cases execute literal async functions; no expected Node snapshot
//! or private DATA classifier substitutes for their observable root order.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const af = v.af;
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const Mode = enum { returned, thrown, abandoned, body_fatal };
const Token = struct { probe: *Probe, slot: usize };
const Probe = struct {
    engine: *Engine,
    mode: Mode,
    arrow: bool = false,
    holder_class: c.JSClassID = 0,
    tokens: [6]Token = undefined,
    made: [6]bool = @splat(false),
    counts: [6]u32 = @splat(0),
    order: [8]u8 = @splat(255),
    length: usize = 0,
    resumed: usize = 0,
    observed: usize = 0,
    adoption_calls: usize = 0,
    adoption_counts: [6]u32 = @splat(99),
    cleanup_events: bool = false,
    first: c.JSValue = c.pi_js_undefined(),
    second: c.JSValue = c.pi_js_undefined(),
    prior: c.JSValue = c.pi_js_undefined(),
    body_reason: c.JSValue = c.pi_js_undefined(),
    fn deinit(self: *Probe) void {
        self.cleanup_events = false;
        self.engine.freeValue(self.first); self.engine.freeValue(self.second);
        self.engine.freeValue(self.prior); self.engine.freeValue(self.body_reason);
        self.engine.deinit();
        active = null;
    }
    fn token(self: *Probe, slot: usize) !c.JSValue {
        if (slot >= self.tokens.len or self.made[slot]) return error.InvalidRetirementToken;
        const result = try self.engine.checked(c.JS_NewObjectClass(self.engine.context, self.holder_class));
        self.made[slot] = true;
        _ = c.JS_SetOpaque(result, &self.tokens[slot]);
        return result;
    }
};
var active: ?*Probe = null;
fn release(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const p = token.probe;
    p.counts[token.slot] += 1;
    if (p.length < p.order.len) p.order[p.length] = @intCast(token.slot);
    p.length += 1;
    // Real C finalizer events at the argument and local releases. The actual
    // pending owner must keep the first fatal while still retiring all roots.
    if (p.cleanup_events and (token.slot == 0 or token.slot == 2))
        _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, if (token.slot == 0) p.first else p.second));
}
fn make(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    var slot: u32 = 0;
    if (argc == 0 or c.JS_ToUint32(context, &slot, argv[0]) < 0) return c.JS_EXCEPTION;
    return active.?.token(slot) catch |err| c.JS_ThrowInternalError(context, "Retirement token: %s", @as([*:0]const u8, @errorName(err)));
}
fn observe(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = active.?;
    if (argc != 3 or !c.JS_IsObject(argv[0]) or !c.JS_IsObject(argv[1]) or !c.JS_IsObject(argv[2]))
        return c.JS_ThrowInternalError(context, "Missing actual capture, receiver, or local");
    if (p.counts[2] != 0 or p.counts[3] != 0 or p.counts[4] != 0 or (p.arrow and p.counts[5] != 0))
        return c.JS_ThrowInternalError(context, "Frame root retired before resumed body");
    const effective: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(argv[1], p.holder_class) orelse
        return c.JS_ThrowInternalError(context, "Missing effective this holder")));
    if (effective.probe != p or effective.slot != @as(usize, if (p.arrow) 5 else 4))
        return c.JS_ThrowInternalError(context, "Async arrow used call receiver instead of lexical this");
    p.observed += 1;
    return c.pi_js_undefined();
}
fn adoption(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = active.?; p.adoption_calls += 1; p.adoption_counts = p.counts;
    return c.pi_js_undefined();
}
fn factory(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, factoryBody(&s, v.arg(args, 0)));
}
fn factoryBody(s: *Scope, captured: c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return v.duplicate(s, try boundary.finishValue(s, af.createResumable(s.engine, "", 2, nativeBody, &.{captured})));
}
fn observeBody(s: *Scope, captured: c.JSValue, receiver: c.JSValue, local: c.JSValue) !void {
    _ = try v.call(s, try v.global(s, "vmObserve"), c.pi_js_undefined(), &.{ captured, receiver, local });
}
fn nativeBody(engine: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, advance(&s, receiver, roots, state, completion, input));
}
fn advance(s: *Scope, receiver: c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const p = active.?;
    if (completion == .start) {
        // The VM alone owns this local until settlement/abandonment. Do not
        // close it early in the body: adoption must still observe it alive.
        af.replaceState(s.engine, state, try p.token(2));
        return .{ .awaited = if (p.mode == .abandoned) v.duplicate(s, try v.global(s, "vmGate")) else c.pi_js_undefined() };
    }
    p.resumed += 1;
    if (completion == .rejected) return .{ .thrown = v.duplicate(s, input) };
    if (p.mode == .body_fatal) {
        _ = s.engine.throwNativeOutOfMemoryFatal(); // Actual current native producer.
        const reason = c.JS_GetException(s.engine.context);
        p.body_reason = v.duplicate(s, reason);
        _ = try s.engine.checked(c.JS_Throw(s.engine.context, reason));
        unreachable;
    }
    var observation: Scope = .{ .engine = s.engine };
    try v.owned.finishVoid(&observation, observeBody(&observation, roots[0], receiver, state.*));
    const output = v.duplicate(s, try v.global(s, "vmReturn"));
    return if (p.mode == .thrown) .{ .thrown = output } else .{ .returned = output };
}
fn evaluate(engine: *Engine, source: []const u8) !c.JSValue {
    return engine.eval(source, "actual-async-frame-retirement.js", c.JS_EVAL_TYPE_GLOBAL);
}
fn run(engine: *Engine, source: []const u8) !void { engine.freeValue(try evaluate(engine, source)); }
fn setup(p: *Probe, native: bool, mode: Mode) !void {
    p.* = .{ .engine = p.engine, .mode = mode };
    active = p;
    for (&p.tokens, 0..) |*item, i| item.* = .{ .probe = p, .slot = i };
    _ = c.JS_NewClassID(p.engine.runtime, &p.holder_class);
    const definition: c.JSClassDef = .{ .class_name = "Actual async argument local capture receiver holder", .finalizer = release };
    if (c.JS_NewClass(p.engine.runtime, p.holder_class, &definition) < 0) return error.OutOfMemory;
    var s: Scope = .{ .engine = p.engine };
    try v.owned.finishVoid(&s, install(&s));
    try run(p.engine, switch (mode) {
        .returned, .body_fatal =>
            "globalThis.sourceFactory=captured=>async function(a,b){const local=vmMake(2);await undefined;vmObserve(captured,this,local);return vmReturn};",
        .thrown =>
            "globalThis.sourceFactory=captured=>async function(a,b){const local=vmMake(2);await undefined;vmObserve(captured,this,local);throw vmReturn};",
        .abandoned =>
            "globalThis.sourceFactory=captured=>async function(a,b){const local=vmMake(2);await vmGate;vmObserve(captured,this,local);return vmReturn};",
    });
    try run(p.engine, if (native) "globalThis.selectedFactory=nativeFactory;globalThis.vmReturn=17;"
        else "globalThis.selectedFactory=sourceFactory;globalThis.vmReturn=17;");
    if (mode == .abandoned) try run(p.engine, "globalThis.vmGate=new Promise(()=>{});");
}
fn install(s: *Scope) !void {
    const global = try v.global(s, "globalThis");
    try v.put(s, global, "vmMake", try v.own(s, try s.engine.checked(c.JS_NewCFunction(s.engine.context, make, "vmMake", 1))));
    try v.put(s, global, "vmObserve", try v.own(s, try s.engine.checked(c.JS_NewCFunction(s.engine.context, observe, "vmObserve", 3))));
    try v.put(s, global, "vmAdoption", try v.own(s, try s.engine.checked(c.JS_NewCFunction(s.engine.context, adoption, "vmAdoption", 0))));
    try v.put(s, global, "nativeFactory", try v.arrow(s, "nativeFactory", 1, factory, &.{}));
}
fn start(p: *Probe) !c.JSValue {
    try run(p.engine,
        "globalThis.vmPending=Reflect.apply(selectedFactory(vmMake(3)),vmMake(4),[vmMake(0),vmMake(1)]);void 0;");
    const pending = try evaluate(p.engine, "vmPending");
    errdefer p.engine.freeValue(pending);
    c.JS_PromiseMarkAsHandled(p.engine.context, pending);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
    try std.testing.expectEqual(@as(usize, 0), p.length);
    return pending;
}
fn executeOne(p: *Probe) !void {
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(p.engine.runtime, &context) > 0);
    try std.testing.expect(!c.JS_HasException(p.engine.context));
    try std.testing.expect(!c.JS_IsJobPending(p.engine.runtime));
    p.engine.finishJob();
}
fn sequence(p: *Probe) !void {
    const expected: []const u8 = if (p.arrow) &.{ 0, 1, 2, 3, 5, 4 } else &.{ 0, 1, 2, 3, 4 };
    try std.testing.expectEqual(expected.len, p.length);
    try std.testing.expectEqualSlices(u8, expected, p.order[0..p.length]);
    for (p.counts, 0..) |count, i| try std.testing.expectEqual(@as(u32, if (p.made[i]) 1 else 0), count);
}
fn fatalValues(p: *Probe) !void {
    p.first = try p.engine.checked(c.JS_NewError(p.engine.context));
    p.second = try p.engine.checked(c.JS_NewError(p.engine.context));
    p.prior = try p.engine.checked(c.JS_NewError(p.engine.context));
    c.JS_SetUncatchableError(p.engine.context, p.first);
    c.JS_SetUncatchableError(p.engine.context, p.second);
    c.JS_SetUncatchableError(p.engine.context, p.prior);
    p.cleanup_events = true;
}
fn fatalJob(p: *Probe, expected: c.JSValue) !void {
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(p.engine.runtime, &context) < 0);
    try std.testing.expect(c.JS_HasException(p.engine.context));
    const reason = c.JS_GetException(p.engine.context); defer p.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, reason, expected));
    try sequence(p);
}

test "VM async retirement arguments locals captures and receiver follow actual Source order after Await" {
    inline for (.{ false, true }) |native| {
        var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .mode = .returned };
        defer p.deinit(); try setup(&p, native, .returned);
        const pending = try start(&p); defer p.engine.freeValue(pending);
        try executeOne(&p); try sequence(&p);
        try std.testing.expectEqual(@as(usize, 1), p.observed);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(p.engine.context, pending));
    }
}
test "VM async retirement genuine return adoption observes argument local capture and receiver still alive" {
    inline for (.{ false, true }) |native| {
        var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .mode = .returned };
        defer p.deinit(); try setup(&p, native, .returned);
        try run(p.engine, "globalThis.vmReturn={get then(){vmAdoption();return undefined}};");
        const pending = try start(&p); defer p.engine.freeValue(pending);
        try executeOne(&p); try sequence(&p);
        try std.testing.expectEqual(@as(usize, 1), p.adoption_calls);
        for (p.adoption_counts) |count| try std.testing.expectEqual(@as(u32, 0), count);
    }
}
test "VM async retirement ordinary thrown identity survives argument before local cleanup" {
    inline for (.{ false, true }) |native| {
        var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .mode = .thrown };
        defer p.deinit(); try setup(&p, native, .thrown);
        try run(p.engine, "globalThis.vmReturn={ordinary:'actual throw reason'};");
        const expected = try evaluate(p.engine, "vmReturn"); defer p.engine.freeValue(expected);
        const pending = try start(&p); defer p.engine.freeValue(pending);
        try executeOne(&p); try sequence(&p);
        try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(p.engine.context, pending));
        const actual = c.JS_PromiseResult(p.engine.context, pending); defer p.engine.freeValue(actual);
        try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, actual, expected));
        try std.testing.expect(!c.JS_IsUncatchableError(actual));
    }
}
test "VM async retirement abandoned real suspension terminates arguments locals captures then receiver" {
    inline for (.{ false, true }) |native| {
        var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .mode = .abandoned };
        defer p.deinit(); try setup(&p, native, .abandoned);
        const pending = try start(&p); defer p.engine.freeValue(pending);
        try std.testing.expect(!c.JS_IsJobPending(p.engine.runtime));
        // The real awaited Promise owns its reactions, which own the suspended
        // coroutine. Dropping its last external root invokes terminate, with
        // no GC-order guess and without settling the distinct outer Promise.
        try run(p.engine, "delete globalThis.vmGate;");
        try sequence(&p);
        try std.testing.expectEqual(@as(usize, 0), p.observed);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
    }
}
test "VM async retirement first actual argument cleanup fatal wins later local event after settlement" {
    inline for (.{ Mode.returned, Mode.thrown }) |mode| {
        var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .mode = mode };
        defer p.deinit(); try setup(&p, true, mode);
        const pending = try start(&p); defer p.engine.freeValue(pending);
        try fatalValues(&p); try fatalJob(&p, p.first);
        try std.testing.expectEqual(@as(usize, 1), p.resumed);
        try std.testing.expectEqual(if (mode == .returned) c.JS_PROMISE_FULFILLED else c.JS_PROMISE_REJECTED,
            c.JS_PromiseState(p.engine.context, pending));
    }
}
test "VM async retirement preexisting current fatal prevents resumed body and precedes all cleanup events" {
    var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .mode = .returned };
    defer p.deinit(); try setup(&p, true, .returned);
    const pending = try start(&p); defer p.engine.freeValue(pending);
    try fatalValues(&p);
    _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, p.prior));
    try fatalJob(&p, p.prior);
    try std.testing.expectEqual(@as(usize, 0), p.resumed);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
}
test "VM async retirement actual native body allocation fatal survives argument and local cleanup" {
    var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .mode = .body_fatal };
    defer p.deinit(); try setup(&p, true, .body_fatal);
    const pending = try start(&p); defer p.engine.freeValue(pending);
    try fatalValues(&p);
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(p.engine.runtime, &context) < 0);
    const reason = c.JS_GetException(p.engine.context); defer p.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, reason, p.body_reason));
    try sequence(&p);
    try std.testing.expectEqual(@as(usize, 1), p.resumed);
    try std.testing.expect(p.engine.native_fatal_invocation == null);
}

fn arrowFactory(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return v.owned.finishValue(&scope, arrowFactoryBody(&scope, receiver, v.arg(args, 0)));
}
fn arrowFactoryBody(s: *Scope, lexical_this: c.JSValue, captured: c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return v.duplicate(s, try boundary.finishValue(s,
        af.createResumableArrow(s.engine, "", 2, nativeBody, &.{captured}, lexical_this)));
}
fn installArrowFactory(s: *Scope) !void {
    try v.put(s, try v.global(s, "globalThis"), "nativeArrowFactory",
        try v.ordinary(s, "nativeArrowFactory", 1, arrowFactory, &.{}));
}
fn setupArrow(p: *Probe, native: bool, mode: Mode) !void {
    try setup(p, native, mode);
    p.arrow = true;
    var scope: Scope = .{ .engine = p.engine };
    try v.owned.finishVoid(&scope, installArrowFactory(&scope));
    // captured is referenced before lexical this in the literal arrow body,
    // so its actual closed var-ref holder precedes the lexical-this holder.
    try run(p.engine, if (mode == .abandoned)
        "globalThis.sourceArrowFactory=function(captured){return async(a,b)=>{const local=vmMake(2);await vmGate;vmObserve(captured,this,local);return vmReturn}};"
        else
        "globalThis.sourceArrowFactory=function(captured){return async(a,b)=>{const local=vmMake(2);await undefined;vmObserve(captured,this,local);return vmReturn}};");
    try run(p.engine, if (native) "globalThis.selectedArrowFactory=nativeArrowFactory;"
        else "globalThis.selectedArrowFactory=sourceArrowFactory;");
}
fn startArrow(p: *Probe) !c.JSValue {
    // The ordinary factory's receiver becomes lexical this. The distinct
    // receiver passed to the resulting arrow still belongs to its real frame.
    try run(p.engine,
        "globalThis.vmPending=Reflect.apply(Reflect.apply(selectedArrowFactory,vmMake(5),[vmMake(3)]),vmMake(4),[vmMake(0),vmMake(1)]);void 0;");
    const pending = try evaluate(p.engine, "vmPending");
    errdefer p.engine.freeValue(pending);
    c.JS_PromiseMarkAsHandled(p.engine.context, pending);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
    try std.testing.expectEqual(@as(usize, 0), p.length);
    for (p.made) |made| try std.testing.expect(made);
    return pending;
}
test "VM async retirement arrow keeps distinct call receiver and lexical this through Await and adoption" {
    inline for (.{ false, true }) |native| {
        var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .mode = .returned };
        defer p.deinit(); try setupArrow(&p, native, .returned);
        try run(p.engine, "globalThis.vmReturn={get then(){vmAdoption();return undefined}};");
        const pending = try startArrow(&p); defer p.engine.freeValue(pending);
        // Exercise the actual suspended-frame GC traversal with both receiver
        // identities still live. Retirement itself remains reference-driven.
        c.JS_RunGC(p.engine.runtime);
        try std.testing.expectEqual(@as(usize, 0), p.length);
        try executeOne(&p); try sequence(&p);
        try std.testing.expectEqual(@as(usize, 1), p.observed);
        try std.testing.expectEqual(@as(usize, 1), p.adoption_calls);
        for (p.adoption_counts) |count| try std.testing.expectEqual(@as(u32, 0), count);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(p.engine.context, pending));
    }
}
test "VM async retirement abandoned arrow releases captures lexical this then ignored call receiver" {
    inline for (.{ false, true }) |native| {
        var p: Probe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .mode = .abandoned };
        defer p.deinit(); try setupArrow(&p, native, .abandoned);
        const pending = try startArrow(&p); defer p.engine.freeValue(pending);
        try std.testing.expect(!c.JS_IsJobPending(p.engine.runtime));
        try run(p.engine, "delete globalThis.vmGate;");
        try sequence(&p);
        try std.testing.expectEqual(@as(usize, 0), p.observed);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
    }
}


const CloseFrame = @import("extensions/native_public_lexical_frame.zig").Frame(enum { local, captured });
const CloseMode = enum { returned, abandoned, failed_close };
const CloseToken = struct { probe: *CloseProbe, slot: usize };
const CloseProbe = struct {
    engine: *Engine,
    mode: CloseMode = .returned,
    escape: bool = false,
    arrow: bool = false,
    async_frame: bool = false,
    drop_callback: bool = false,
    cycle_callback: bool = false,
    holder_class: c.JSClassID = 0,
    tokens: [4]CloseToken = undefined,
    made: [4]bool = @splat(false),
    counts: [4]u32 = @splat(0),
    order: [8]u8 = @splat(255),
    length: usize = 0,
    resumed: usize = 0,
    hook_calls: usize = 0,
    hook_counts: [4]u32 = @splat(99),
    hook_promise_state: c_int = -1,
    adoption_calls: usize = 0,
    adoption_counts: [4]u32 = @splat(99),
    pending: c.JSValue = c.pi_js_undefined(), // Borrowed from the test's real Promise root.
    first: c.JSValue = c.pi_js_undefined(),
    second: c.JSValue = c.pi_js_undefined(),
    prior: c.JSValue = c.pi_js_undefined(),
    cleanup_events: bool = false,
    fn token(self: *CloseProbe, slot: usize) !c.JSValue {
        if (slot >= self.tokens.len or self.made[slot]) return error.InvalidCloseToken;
        const result = try self.engine.checked(c.JS_NewObjectClass(self.engine.context, self.holder_class));
        self.made[slot] = true;
        _ = c.JS_SetOpaque(result, &self.tokens[slot]);
        return result;
    }
    fn deinit(self: *CloseProbe) void {
        self.cleanup_events = false;
        self.engine.freeValue(self.first); self.engine.freeValue(self.second); self.engine.freeValue(self.prior);
        self.pending = c.pi_js_undefined();
        self.engine.deinit();
        close_active = null;
    }
};
var close_active: ?*CloseProbe = null;
fn closeRelease(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const token: *CloseToken = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const p = token.probe;
    p.counts[token.slot] += 1;
    if (p.length < p.order.len) p.order[p.length] = @intCast(token.slot);
    p.length += 1;
    if (p.cleanup_events and (token.slot == 0 or token.slot == 1))
        _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, if (token.slot == 0) p.first else p.second));
}
fn closeMake(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    var slot: u32 = 0;
    if (argc == 0 or c.JS_ToUint32(context, &slot, argv[0]) < 0) return c.JS_EXCEPTION;
    return close_active.?.token(slot) catch |err|
        c.JS_ThrowInternalError(context, "Close token: %s", @as([*:0]const u8, @errorName(err)));
}
fn closeAdoption(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = close_active.?;
    p.adoption_calls += 1; p.adoption_counts = p.counts;
    return c.pi_js_undefined();
}
fn closeCaptured(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return v.owned.finishValue(&scope, closeCapturedBody(&scope, roots[0]));
}
fn closeCapturedBody(scope: *Scope, binding: c.JSValue) !c.JSValue {
    return v.duplicate(scope, try CloseFrame.read(scope, binding));
}
fn closeState(engine: *Engine, owner: c.JSValue) !void {
    const p = close_active.?;
    p.hook_calls += 1; p.hook_counts = p.counts;
    if (!c.JS_IsUndefined(p.pending)) p.hook_promise_state = c.JS_PromiseState(engine.context, p.pending);
    if (p.mode == .failed_close) {
        // An actual pending ordinary failure before close must still leave the
        // C owner responsible for every state/function/receiver root.
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, p.prior));
        return error.JavaScriptException;
    }
    return CloseFrame.closeAtAsyncTerminal(engine, owner);
}
fn closeNative(engine: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue, owner: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    return v.owned.finishAction(&scope, closeAdvance(&scope, owner, completion, input));
}
fn closeAdvance(scope: *Scope, owner: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const p = close_active.?;
    if (completion == .start) {
        const frame = if (p.async_frame) try CloseFrame.createAsync(scope) else try CloseFrame.create(scope);
        // Install the genuine VM state before any subsequent producer can fail.
        af.replaceState(scope.engine, owner, v.duplicate(scope, frame.owner));
        try frame.take(.local, p.token(1));
        try frame.take(.captured, p.token(2));
        if (p.escape or p.cycle_callback) {
            var expression: Scope = .{ .engine = scope.engine };
            try v.owned.finishVoid(&expression, leaseCaptureBody(&expression, frame));
            if (p.drop_callback) {
                var deletion: Scope = .{ .engine = scope.engine };
                try v.owned.finishVoid(&deletion, leaseDropBody(&deletion));
            }
        }
        return .{ .awaited = if (p.mode == .abandoned)
            v.duplicate(scope, try v.global(scope, "closeGate")) else c.pi_js_undefined() };
    }
    p.resumed += 1;
    if (completion == .rejected) return .{ .thrown = v.duplicate(scope, input) };
    return .{ .returned = v.duplicate(scope, try v.global(scope, "closeReturn")) };
}
fn closeInstall(scope: *Scope) !void {
    const global = try v.global(scope, "globalThis");
    try v.put(scope, global, "closeMake", try v.own(scope, try scope.engine.checked(
        c.JS_NewCFunction(scope.engine.context, closeMake, "closeMake", 1))));
    try v.put(scope, global, "closeAdoption", try v.own(scope, try scope.engine.checked(
        c.JS_NewCFunction(scope.engine.context, closeAdoption, "closeAdoption", 0))));
    var boundary: v.guest.Boundary = .{ .engine = scope.engine }; try boundary.begin();
    const function = try boundary.finishValue(scope, if (close_active.?.arrow)
        af.createResumableArrowWithClose(scope.engine, "", 1, closeNative, &.{}, c.pi_js_undefined(), closeState)
        else af.createResumableWithClose(scope.engine, "", 1, closeNative, &.{}, closeState));
    try v.put(scope, global, "closeNative", function);
}
fn closeSetup(p: *CloseProbe, native: bool) !void {
    close_active = p;
    for (&p.tokens, 0..) |*item, i| item.* = .{ .probe = p, .slot = i };
    _ = c.JS_NewClassID(p.engine.runtime, &p.holder_class);
    const definition: c.JSClassDef = .{ .class_name = "Actual terminal close argument and binding holder", .finalizer = closeRelease };
    if (c.JS_NewClass(p.engine.runtime, p.holder_class, &definition) < 0) return error.OutOfMemory;
    var scope: Scope = .{ .engine = p.engine };
    try v.owned.finishVoid(&scope, closeInstall(&scope));
    try run(p.engine, if (p.escape)
        if (p.arrow)
            "globalThis.closeSource=async arg=>{const local=closeMake(1);const captured=closeMake(2);globalThis.closeEscaped=()=>captured;await undefined;return closeReturn};"
        else
            "globalThis.closeSource=async function(arg){const local=closeMake(1);const captured=closeMake(2);globalThis.closeEscaped=()=>captured;await undefined;return closeReturn};"
        else if (p.mode == .abandoned)
            "globalThis.closeSource=async function(arg){const local=closeMake(1);const captured=closeMake(2);await closeGate;return closeReturn};"
        else
            "globalThis.closeSource=async function(arg){const local=closeMake(1);const captured=closeMake(2);await undefined;return closeReturn};");
    try run(p.engine, if (native) "globalThis.closeSelected=closeNative;globalThis.closeReturn=23;"
        else "globalThis.closeSelected=closeSource;globalThis.closeReturn=23;");
    if (p.mode == .abandoned) try run(p.engine, "globalThis.closeGate=new Promise(()=>{});");
}
fn closeStart(p: *CloseProbe) !c.JSValue {
    try run(p.engine, "globalThis.closePending=Reflect.apply(closeSelected,closeMake(3),[closeMake(0)]);void 0;");
    const pending = try evaluate(p.engine, "closePending");
    errdefer p.engine.freeValue(pending);
    p.pending = pending;
    c.JS_PromiseMarkAsHandled(p.engine.context, pending);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
    try std.testing.expectEqual(@as(usize, 0), p.length);
    for (p.made) |made| try std.testing.expect(made);
    return pending;
}
fn closeOne(p: *CloseProbe) !void {
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(p.engine.runtime, &context) > 0);
    try std.testing.expect(!c.JS_HasException(p.engine.context));
    try std.testing.expect(!c.JS_IsJobPending(p.engine.runtime));
    p.engine.finishJob();
}
fn closeOrder(p: *CloseProbe, expected: []const u8) !void {
    try std.testing.expectEqual(expected.len, p.length);
    try std.testing.expectEqualSlices(u8, expected, p.order[0..p.length]);
    for (p.counts) |count| try std.testing.expectEqual(@as(u32, 1), count);
}
fn closeFatalValues(p: *CloseProbe) !void {
    p.first = try p.engine.checked(c.JS_NewError(p.engine.context));
    p.second = try p.engine.checked(c.JS_NewError(p.engine.context));
    p.prior = try p.engine.checked(c.JS_NewError(p.engine.context));
    c.JS_SetUncatchableError(p.engine.context, p.first);
    c.JS_SetUncatchableError(p.engine.context, p.second);
    c.JS_SetUncatchableError(p.engine.context, p.prior);
    p.cleanup_events = true;
}
fn closeJobFailure(p: *CloseProbe, expected: c.JSValue, fatal: bool) !void {
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(p.engine.runtime, &context) < 0);
    try std.testing.expect(c.JS_HasException(p.engine.context));
    const reason = c.JS_GetException(p.engine.context); defer p.engine.freeValue(reason);
    try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, reason, expected));
    try std.testing.expectEqual(@as(usize, 1), p.hook_calls);
    try std.testing.expectEqualSlices(u32, &.{ 1, 0, 0, 0 }, &p.hook_counts);
    try closeOrder(p, &.{ 0, 1, 2, 3 });
}

test "VM async retirement terminal Frame close follows adoption and leaves escaped cells holding only captures" {
    inline for (.{ false, true }) |native| {
      inline for (.{ false, true }) |arrow| {
        var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .escape = true, .arrow = arrow };
        defer p.deinit(); try closeSetup(&p, native);
        try run(p.engine, "globalThis.closeReturn={get then(){closeAdoption();return undefined}};");
        const pending = try closeStart(&p); defer p.engine.freeValue(pending);
        try closeOne(&p);
        try std.testing.expectEqual(@as(usize, 1), p.adoption_calls);
        try std.testing.expectEqualSlices(u32, &.{ 0, 0, 0, 0 }, &p.adoption_counts);
        try std.testing.expectEqualSlices(u32, &.{ 1, 1, 0, 1 }, &p.counts);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(p.engine.context, pending));
        if (native) {
            try std.testing.expectEqual(@as(usize, 1), p.hook_calls);
            try std.testing.expectEqualSlices(u32, &.{ 1, 0, 0, 0 }, &p.hook_counts);
            try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, p.hook_promise_state);
        }
        const captured = try evaluate(p.engine, "closeEscaped()");
        const token: *CloseToken = @ptrCast(@alignCast(c.JS_GetOpaque(captured, p.holder_class) orelse return error.MissingClosedCapture));
        try std.testing.expectEqual(@as(usize, 2), token.slot);
        p.engine.freeValue(captured);
        try std.testing.expectEqual(@as(u32, 0), p.counts[2]);
        try run(p.engine, "delete globalThis.closeEscaped;");
        try closeOrder(&p, &.{ 0, 1, 3, 2 });
      }
    }
}
test "VM async retirement terminal Frame close runs once for abandoned actual Await without escaped cells" {
    inline for (.{ false, true }) |native| {
        var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .mode = .abandoned };
        defer p.deinit(); try closeSetup(&p, native);
        const pending = try closeStart(&p); defer p.engine.freeValue(pending);
        try std.testing.expect(!c.JS_IsJobPending(p.engine.runtime));
        try run(p.engine, "delete globalThis.closeGate;");
        try closeOrder(&p, &.{ 0, 1, 2, 3 });
        try std.testing.expectEqual(@as(usize, 0), p.resumed);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
        if (native) {
            try std.testing.expectEqual(@as(usize, 1), p.hook_calls);
            try std.testing.expectEqualSlices(u32, &.{ 1, 0, 0, 0 }, &p.hook_counts);
            try std.testing.expectEqual(c.JS_PROMISE_PENDING, p.hook_promise_state);
        }
    }
}
test "VM async retirement terminal close preserves first argument fatal and still retires every local" {
    var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}) };
    defer p.deinit(); try closeSetup(&p, true);
    const pending = try closeStart(&p); defer p.engine.freeValue(pending);
    try closeFatalValues(&p); try closeJobFailure(&p, p.first, true);
    try std.testing.expectEqual(@as(usize, 1), p.resumed);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, p.hook_promise_state);
}
test "VM async retirement terminal close runs under preexisting fatal without resuming a body" {
    var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}) };
    defer p.deinit(); try closeSetup(&p, true);
    const pending = try closeStart(&p); defer p.engine.freeValue(pending);
    try closeFatalValues(&p);
    _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, p.prior));
    try closeJobFailure(&p, p.prior, true);
    try std.testing.expectEqual(@as(usize, 0), p.resumed);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, p.hook_promise_state);
}
test "VM async retirement failed terminal hook cannot bypass state and receiver root retirement" {
    var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .mode = .failed_close };
    defer p.deinit(); try closeSetup(&p, true);
    p.prior = try p.engine.checked(c.JS_NewError(p.engine.context));
    const pending = try closeStart(&p); defer p.engine.freeValue(pending);
    try closeJobFailure(&p, p.prior, false);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, p.hook_promise_state);
}


// An opted-in asynchronous Frame borrows its capture lookup slots. Escaping
// cells, not that table, retain the real coroutine through a C GC lease.
fn leaseCaptureBody(scope: *Scope, frame: *CloseFrame) !void {
    const target = if (close_active.?.cycle_callback) frame.get(.local) else try v.global(scope, "globalThis");
    const binding = try frame.capture(scope, .captured, "captured");
    const callback = try v.arrow(scope, "", 0, closeCaptured, &.{binding});
    try v.put(scope, target, if (close_active.?.cycle_callback) "cycle" else "closeEscaped", callback);
}
fn leaseDropBody(scope: *Scope) !void {
    const target = try v.global(scope, "globalThis");
    const atom = c.JS_NewAtom(scope.engine.context, "closeEscaped");
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(scope.engine.context, atom);
    var boundary: v.guest.Boundary = .{ .engine = scope.engine }; try boundary.begin();
    try boundary.finishStatus(c.JS_DeleteProperty(scope.engine.context, target, atom, 0));
}
const LeaseShape = enum { escaped, dropped, cycle };
fn leaseSetup(p: *CloseProbe, native: bool, shape: LeaseShape, mode: CloseMode) !void {
    p.async_frame = true;
    p.escape = shape != .cycle;
    p.drop_callback = shape == .dropped;
    p.cycle_callback = shape == .cycle;
    p.mode = mode;
    try closeSetup(p, native);
    // These are literal original-language async functions. Both engines use
    // the same actual C holder objects; no trace snapshot substitutes for them.
    const source = switch (shape) {
        .escaped => if (mode == .abandoned)
            "globalThis.closeSource=async function(arg){const local=closeMake(1);const captured=closeMake(2);globalThis.closeEscaped=()=>captured;await closeGate;return closeReturn};"
            else if (p.arrow)
            "globalThis.closeSource=async arg=>{const local=closeMake(1);const captured=closeMake(2);globalThis.closeEscaped=()=>captured;await undefined;return closeReturn};"
            else
            "globalThis.closeSource=async function(arg){const local=closeMake(1);const captured=closeMake(2);globalThis.closeEscaped=()=>captured;await undefined;return closeReturn};",
        .dropped => if (mode == .abandoned)
            "globalThis.closeSource=async function(arg){const local=closeMake(1);const captured=closeMake(2);globalThis.closeEscaped=()=>captured;delete globalThis.closeEscaped;await closeGate;return closeReturn};"
            else
            "globalThis.closeSource=async function(arg){const local=closeMake(1);const captured=closeMake(2);globalThis.closeEscaped=()=>captured;delete globalThis.closeEscaped;await undefined;return closeReturn};",
        .cycle => if (mode == .abandoned)
            "globalThis.closeSource=async function(arg){const local=closeMake(1);const captured=closeMake(2);local.cycle=()=>captured;await closeGate;return closeReturn};"
            else
            "globalThis.closeSource=async function(arg){const local=closeMake(1);const captured=closeMake(2);local.cycle=()=>captured;await undefined;return closeReturn};",
    };
    try run(p.engine, source);
    if (!native) try run(p.engine, "globalThis.closeSelected=closeSource;");
}
fn leaseReadCapture(p: *CloseProbe) !void {
    const value = try evaluate(p.engine, "closeEscaped()");
    defer p.engine.freeValue(value);
    const token: *CloseToken = @ptrCast(@alignCast(c.JS_GetOpaque(value, p.holder_class) orelse return error.MissingLeaseCapture));
    try std.testing.expectEqual(@as(usize, 2), token.slot);
    try std.testing.expect(token.probe == p);
}
fn leaseCounts(p: *CloseProbe, expected: [4]u32) !void {
    try std.testing.expectEqualSlices(u32, &expected, &p.counts);
}
fn leaseCollect(p: *CloseProbe) !void {
    try std.testing.expect(!c.JS_IsJobPending(p.engine.runtime));
    c.JS_RunGC(p.engine.runtime);
    try std.testing.expect(!c.JS_HasException(p.engine.context));
    p.engine.finishJob();
}

test "VM async retirement escaped open cell retains actual coroutine after the awaited gate is removed" {
    inline for (.{ false, true }) |native| {
        var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}) };
        defer p.deinit(); try leaseSetup(&p, native, .escaped, .abandoned);
        const pending = try closeStart(&p); defer p.engine.freeValue(pending);
        try run(p.engine, "delete globalThis.closeGate;");
        try leaseCounts(&p, .{ 0, 0, 0, 0 });
        try leaseCollect(&p);
        try leaseCounts(&p, .{ 0, 0, 0, 0 });
        try std.testing.expectEqual(@as(usize, 0), p.hook_calls);
        try leaseReadCapture(&p);
        try run(p.engine, "delete globalThis.closeEscaped;");
        try closeOrder(&p, &.{ 0, 1, 2, 3 });
        try std.testing.expectEqual(@as(usize, if (native) 1 else 0), p.hook_calls);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
        try leaseCollect(&p);
        try closeOrder(&p, &.{ 0, 1, 2, 3 });
    }
}
test "VM async retirement dropped callback leaves no artificial owning capture-table cycle" {
    inline for (.{ false, true }) |native| {
        var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}) };
        defer p.deinit(); try leaseSetup(&p, native, .dropped, .abandoned);
        const pending = try closeStart(&p); defer p.engine.freeValue(pending);
        try leaseCollect(&p); try leaseCounts(&p, .{ 0, 0, 0, 0 });
        try run(p.engine, "delete globalThis.closeGate;");
        // Retirement must be immediate when the actual awaited owner is gone;
        // requiring GC here would conceal an extra Frame -> Cell owner.
        try closeOrder(&p, &.{ 0, 1, 2, 3 });
        try std.testing.expectEqual(@as(usize, if (native) 1 else 0), p.hook_calls);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
    }
}
test "VM async retirement actual lease survives live GC and disconnects after final return adoption" {
    inline for (.{ false, true }) |native| {
      inline for (.{ false, true }) |arrow| {
        var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}), .arrow = arrow };
        defer p.deinit(); try leaseSetup(&p, native, .escaped, .returned);
        try run(p.engine, "globalThis.closeReturn={get then(){closeAdoption();return undefined}};");
        const pending = try closeStart(&p); defer p.engine.freeValue(pending);
        // The real queued reaction is still active; this GC checks all edges.
        c.JS_RunGC(p.engine.runtime);
        try leaseCounts(&p, .{ 0, 0, 0, 0 });
        try closeOne(&p);
        try std.testing.expectEqual(@as(usize, 1), p.adoption_calls);
        try std.testing.expectEqualSlices(u32, &.{ 0, 0, 0, 0 }, &p.adoption_counts);
        try leaseCounts(&p, .{ 1, 1, 0, 1 });
        try leaseCollect(&p); try leaseReadCapture(&p);
        try leaseCounts(&p, .{ 1, 1, 0, 1 });
        try std.testing.expectEqual(@as(usize, if (native) 1 else 0), p.hook_calls);
        if (native) try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, p.hook_promise_state);
        try run(p.engine, "delete globalThis.closeEscaped;");
        try closeOrder(&p, &.{ 0, 1, 3, 2 });
      }
    }
}
test "VM async retirement real unreachable local callback coroutine cycle collects exactly once" {
    inline for (.{ false, true }) |native| {
        var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}) };
        defer p.deinit(); try leaseSetup(&p, native, .cycle, .abandoned);
        const pending = try closeStart(&p); defer p.engine.freeValue(pending);
        try run(p.engine, "delete globalThis.closeGate;");
        try leaseCounts(&p, .{ 0, 0, 0, 0 });
        try std.testing.expectEqual(@as(usize, 0), p.hook_calls);
        // Actual graph: coroutine -> local holder -> callback -> open capture
        // -> coroutine. No global callback root or invented retirement call.
        try leaseCollect(&p);
        try leaseCounts(&p, .{ 1, 1, 1, 1 });
        try std.testing.expectEqual(@as(usize, 4), p.length);
        try std.testing.expectEqual(@as(usize, if (native) 1 else 0), p.hook_calls);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
        // GC order is deliberately not an oracle; each actual root must retire
        // once, including when the state or cell was already finalized.
        try leaseCollect(&p);
        try leaseCounts(&p, .{ 1, 1, 1, 1 });
        try std.testing.expectEqual(@as(usize, 4), p.length);
    }
}
test "VM async retirement reachable callback cycle closes at real completion without waiting for GC" {
    inline for (.{ false, true }) |native| {
        var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}) };
        defer p.deinit(); try leaseSetup(&p, native, .cycle, .returned);
        const pending = try closeStart(&p); defer p.engine.freeValue(pending);
        c.JS_RunGC(p.engine.runtime);
        try leaseCounts(&p, .{ 0, 0, 0, 0 });
        try closeOne(&p);
        try closeOrder(&p, &.{ 0, 1, 2, 3 });
        try std.testing.expectEqual(@as(usize, if (native) 1 else 0), p.hook_calls);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(p.engine.context, pending));
        try leaseCollect(&p);
        try closeOrder(&p, &.{ 0, 1, 2, 3 });
    }
}
test "VM async retirement actual fatal closes the lease while escaped cells keep only their captured value" {
    var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}) };
    defer p.deinit(); try leaseSetup(&p, true, .escaped, .returned);
    const pending = try closeStart(&p); defer p.engine.freeValue(pending);
    try closeFatalValues(&p);
    _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, p.prior));
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(p.engine.runtime, &context) < 0);
    const reason = c.JS_GetException(p.engine.context); defer p.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, reason, p.prior));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(usize, 0), p.resumed);
    try std.testing.expectEqual(@as(usize, 1), p.hook_calls);
    try leaseCounts(&p, .{ 1, 1, 0, 1 });
    p.cleanup_events = false;
    try std.testing.expect(p.engine.native_fatal_invocation == null);
    try leaseCollect(&p); try leaseReadCapture(&p);
    try run(p.engine, "delete globalThis.closeEscaped;");
    try closeOrder(&p, &.{ 0, 1, 3, 2 });
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(p.engine.context, pending));
}
test "VM async retirement activation lease rejects unrelated frames without consuming borrowed state or pending" {
    var p: CloseProbe = .{ .engine = try Engine.init(std.testing.allocator, .{}) };
    defer p.deinit(); try closeSetup(&p, true);
    const state = try p.token(1);
    const denied = c.JS_PiRetainNativeAsyncActivation(p.engine.context, state);
    try std.testing.expect(c.JS_IsException(denied));
    const reason = c.JS_GetException(p.engine.context); defer p.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsError(reason));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(u32, 0), p.counts[1]);
    _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, reason));
    const still_denied = c.JS_PiRetainNativeAsyncActivation(p.engine.context, state);
    try std.testing.expect(c.JS_IsException(still_denied));
    const retained = c.JS_GetException(p.engine.context); defer p.engine.freeValue(retained);
    try std.testing.expect(c.JS_IsStrictEqual(p.engine.context, reason, retained));
    p.engine.freeValue(state);
    try std.testing.expectEqual(@as(u32, 1), p.counts[1]);
    try std.testing.expectEqual(@as(usize, 0), p.hook_calls);
}
