//! Exact c268 utils/shell.ts detached-child bodies. The Source Set and live
//! global process are used directly; no host-wide child registry or kill route.
const v = @import("native_public_values.zig");
const c = v.c;
const Scope = v.Scope;
const owned = v.owned;

fn expression(engine: *v.em.Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, @call(.auto, body, .{&s} ++ args));
}
fn statement(engine: *v.em.Engine, comptime body: anytype, args: anytype) !void {
    var s: Scope = .{ .engine = engine };
    return owned.finishVoid(&s, @call(.auto, body, .{&s} ++ args));
}
/// Source's empty catch discards an ordinary throw after try-expression
/// temporaries retire. Source lexical locals are held by their caller until
/// their actual BCDF lifetime ends. finishAction carries ordinary DATA.
fn attempt(engine: *v.em.Engine, comptime body: anytype, args: anytype) !bool {
    var s: Scope = .{ .engine = engine };
    var completion = owned.Completion.initVoid(engine, @call(.auto, body, .{&s} ++ args));
    completion.releaseScope(&s);
    const action = try completion.finishAction();
    const succeeded = action == .returned;
    var retired = owned.Completion.initVoid(engine, {});
    switch (action) {
        .returned, .thrown => |value| retired.release(value),
        .awaited => unreachable,
    }
    try retired.finishVoid();
    return succeeded;
}
pub fn track(engine: *v.em.Engine, tracked: c.JSValue, pid: c.JSValue) !void {
    return statement(engine, setOperation, .{ tracked, @as([*:0]const u8, "add"), pid });
}
pub fn untrack(engine: *v.em.Engine, tracked: c.JSValue, pid: c.JSValue) !void {
    return statement(engine, setOperation, .{ tracked, @as([*:0]const u8, "delete"), pid });
}
fn setOperation(s: *Scope, tracked: c.JSValue, name: [*:0]const u8, pid: c.JSValue) !void {
    _ = try v.call(s, try v.get(s, tracked, name), tracked, &.{pid});
}
fn platform(s: *Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "process"), "platform"));
}
fn windows(s: *Scope) !c.JSValue {
    const actual = try v.own(s, try expression(s.engine, platform, .{}));
    return v.boolean(s, try v.eq(s, actual, "win32"));
}
pub fn kill(engine: *v.em.Engine, bindings: c.JSValue, pid: c.JSValue) !void {
    // This condition is outside both Source try blocks. Its temporary must
    // retire before either spawn binding or process.kill is accessed.
    const selected = try expression(engine, windows, .{});
    const is_windows = c.JS_ToBool(engine.context, selected) == 1;
    if (is_windows) {
        // The uncaptured Source const child is a function local in BCDF.
        // It survives the empty catch and retires on killProcessTree's exit.
        var child = c.pi_js_undefined();
        const outcome: anyerror!void = if (attempt(engine, killWindows, .{ bindings, pid, &child })) |_| {} else |err| err;
        var completion = owned.Completion.initVoid(engine, outcome);
        completion.release(child);
        try completion.finishVoid();
        return;
    }
    if (try attempt(engine, killUnix, .{ pid, true })) return;
    _ = try attempt(engine, killUnix, .{ pid, false });
}
fn negativeOne(s: *Scope) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const generation = s.engine.native_allocation_generation;
    const result = c.JS_NewBigInt64(s.engine.context, -1);
    _ = s.engine.nativeCallbackResult(c.pi_js_undefined());
    if (c.JS_HasException(s.engine.context)) {
        const reason = c.JS_GetException(s.engine.context);
        const tag = c.pi_js_native_allocation_error_generation(reason);
        const distance = tag -% generation;
        if (tag != 0 and distance != 0 and distance <= s.engine.native_allocation_generation -% generation)
            c.JS_SetUncatchableError(s.engine.context, reason);
        _ = c.JS_Throw(s.engine.context, reason);
    }
    return boundary.finishValue(s, result);
}
fn negate(s: *Scope, input: c.JSValue) !c.JSValue {
    // Unary minus performs ToNumeric exactly once. Both subsequent branches
    // operate on that primitive; Number preserves signed zero, BigInt stays
    // BigInt. No subtraction coercion or process callee lookup is hidden here.
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const numeric = try boundary.finishValue(s, c.JS_PiToNumeric(s.engine.context, input));
    if (c.JS_IsBigInt(numeric))
        return v.duplicate(s, try v.binary(s, 2, numeric, try negativeOne(s)));
    var number: f64 = 0;
    var conversion: v.guest.Boundary = .{ .engine = s.engine };
    try conversion.begin();
    try conversion.finishStatus(c.JS_ToFloat64(s.engine.context, &number, numeric));
    return v.number(s, -number);
}
fn killUnix(s: *Scope, pid: c.JSValue, group: bool) !void {
    // Source resolves process and its kill callee before -pid is evaluated.
    const process = try v.global(s, "process");
    const callable = try v.get(s, process, "kill");
    const target = if (group) try v.own(s, try expression(s.engine, negate, .{pid})) else pid;
    _ = try v.call(s, callable, process, &.{ target, try v.text(s, "SIGKILL") });
}
fn environment(s: *Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "process"), "env"));
}
fn systemRoot(s: *Scope) !c.JSValue {
    const env = try v.own(s, try expression(s.engine, environment, .{}));
    return v.duplicate(s, try v.get(s, env, "SystemRoot"));
}
fn taskkillPath(s: *Scope, join: c.JSValue) !c.JSValue {
    const root = try v.own(s, try expression(s.engine, systemRoot, .{}));
    return v.duplicate(s, try v.call(s, join, c.pi_js_undefined(), &.{
        if (v.nullish(root)) try v.text(s, "C:\\Windows") else root,
        try v.text(s, "System32"), try v.text(s, "taskkill.exe"),
    }));
}
fn pidText(s: *Scope, pid: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, try v.global(s, "String"), c.pi_js_undefined(), &.{pid}));
}
fn taskkillArguments(s: *Scope, pid: c.JSValue) !c.JSValue {
    const args = try v.array(s);
    inline for (.{ "/F", "/T", "/PID" }, 0..) |literal, index|
        try v.index(s, args, index, try v.text(s, literal));
    try v.index(s, args, 3, try v.own(s, try expression(s.engine, pidText, .{pid})));
    return v.duplicate(s, args);
}
fn spawnTaskkill(s: *Scope, bindings: c.JSValue, pid: c.JSValue) !c.JSValue {
    // Genuine imports were captured at module initialization. The outer spawn
    // callee is resolved before evaluating join and the remaining arguments.
    const spawn = try v.get(s, bindings, "spawn");
    const join = try v.get(s, bindings, "join");
    const executable = try v.own(s, try expression(s.engine, taskkillPath, .{join}));
    const args = try v.own(s, try expression(s.engine, taskkillArguments, .{pid}));
    const options = try v.object(s);
    try v.put(s, options, "stdio", try v.text(s, "ignore"));
    try v.put(s, options, "detached", v.boolean(s, true));
    try v.put(s, options, "windowsHide", v.boolean(s, true));
    return v.duplicate(s, try v.call(s, spawn, c.pi_js_undefined(), &.{ executable, args, options }));
}
fn swallow(_: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_undefined();
}
fn consumeSpawnError(s: *Scope, child: c.JSValue) !void {
    const once = try v.get(s, child, "once");
    const event = try v.text(s, "error");
    const callback = try v.arrow(s, "", 0, swallow, &.{});
    _ = try v.call(s, once, child, &.{ event, callback });
}
fn killWindows(s: *Scope, bindings: c.JSValue, pid: c.JSValue, child: *c.JSValue) !void {
    child.* = try expression(s.engine, spawnTaskkill, .{ bindings, pid });
    try statement(s.engine, consumeSpawnError, .{child.*});
}
fn trackedLoop(iterator: *v.Iterator, bindings: c.JSValue, head: *c.JSValue) !void {
    while (try iterator.next()) |pid| {
        // BCDF assigns the new uncaptured const head before retiring the old
        // local. The preceding head remains live through next/done/value.
        const previous = head.*;
        head.* = pid;
        var assignment = owned.Completion.initVoid(iterator.engine, {});
        assignment.release(previous);
        try assignment.finishVoid();
        try kill(iterator.engine, bindings, pid);
    }
}
fn trackedBody(engine: *v.em.Engine, bindings: c.JSValue, tracked: c.JSValue, iterator: *v.Iterator, head: *c.JSValue) !void {
    try iterator.finish(trackedLoop(iterator, bindings, head));
    // Iterator records retire at the for-of exit; the final const pid local
    // remains alive through the following Source Set.clear call.
    try statement(engine, clearTracked, .{tracked});
}
pub fn killTracked(engine: *v.em.Engine, bindings: c.JSValue, tracked: c.JSValue) !void {
    var iterator = try v.Iterator.init(engine, tracked);
    var head = c.pi_js_undefined();
    var completion = owned.Completion.initVoid(engine, trackedBody(engine, bindings, tracked, &iterator, &head));
    completion.release(head);
    try completion.finishVoid();
}
fn clearTracked(s: *Scope, tracked: c.JSValue) !void {
    _ = try v.call(s, try v.get(s, tracked, "clear"), tracked, &.{});
}
