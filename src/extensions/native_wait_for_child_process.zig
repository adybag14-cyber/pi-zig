//! Actual Pi utils/child-process.ts waitForChildProcess. Ordinary function;
//! one live global new Promise, actual child events/streams and 100ms IDLE grace.
const x = @import("native_sdk_exec_values.zig");
const fatal = @import("native_sdk_exec_fatal.zig");
const f = @import("native_node_function.zig");
const c = x.c;
const Kind = enum(i32) { cleanup, finalize, maybeFinalizeAfterExit, armIdleTimer, onData, onStdoutEnd, onStderrEnd, onError, onExit, onClose, idle };
pub fn create(engine: *x.em.Engine) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const result = f.create(engine, "waitForChildProcess", 1, called, &.{}) catch |err| {
        const failed = @import("native_sdk.zig").fail(engine, err);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failed));
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn called(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, calledBody(&o, x.arg(args, 0)));
}
fn calledBody(o: *x.Ops, child: c.JSValue) !c.JSValue {
    const constructor = try o.global("Promise");
    const holder = try fatal.create(o);
    const executor = try o.own(try f.createArrow(o.s.engine, "", 2, executorCall, &.{ child, holder }));
    return c.JS_DupValue(o.s.engine.context, try fatal.construct(o, constructor, executor, holder));
}
fn executorCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    const result = x.owned.finishValue(&s, executorBody(&o, roots[0], x.arg(args, 0), x.arg(args, 1))) catch |err| {
        const failed = @import("native_sdk.zig").fail(engine, err); fatal.record(roots[1], &invocation);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failed));
    };
    fatal.record(roots[1], &invocation);
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn closure(o: *x.Ops, owner: c.JSValue, kind: Kind) !c.JSValue {
    const name: [*:0]const u8 = switch (kind) {
        .cleanup => "cleanup", .finalize => "finalize", .maybeFinalizeAfterExit => "maybeFinalizeAfterExit", .armIdleTimer => "armIdleTimer",
        .onData => "onData", .onStdoutEnd => "onStdoutEnd", .onStderrEnd => "onStderrEnd", .onError => "onError", .onExit => "onExit", .onClose => "onClose", .idle => "",
    };
    const length: c_int = switch (kind) { .finalize, .onError, .onExit, .onClose => 1, else => 0 };
    return o.own(try f.createArrow(o.s.engine, name, length, dispatch, &.{ owner, c.JS_NewInt32(o.s.engine.context, @intFromEnum(kind)) }));
}
fn sibling(o: *x.Ops, owner: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return o.call(try o.get(owner, name), c.pi_js_undefined(), args); }
fn streamCall(parent: *x.Ops, child: c.JSValue, channel: [*:0]const u8, method_name: [*:0]const u8, event: ?[]const u8, owner: c.JSValue, callback_name: ?[*:0]const u8) !void {
    var s: x.Scope = .{ .engine = parent.s.engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, streamCallBody(&o, child, channel, method_name, event, owner, callback_name));
}
fn streamCallBody(o: *x.Ops, child: c.JSValue, channel: [*:0]const u8, method_name: [*:0]const u8, event: ?[]const u8, owner: c.JSValue, callback_name: ?[*:0]const u8) !void {
    const stream = try o.get(child, channel); if (x.nullish(stream)) return;
    const method = try o.get(stream, method_name);
    if (event) |name| _ = try o.call(method, stream, &.{ try o.text(name), try o.get(owner, callback_name.?) })
    else _ = try o.call(method, stream, &.{});
}
fn childCall(parent: *x.Ops, child: c.JSValue, method_name: [*:0]const u8, event: []const u8, owner: c.JSValue, callback_name: [*:0]const u8) !void {
    var s: x.Scope = .{ .engine = parent.s.engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, childCallBody(&o, child, method_name, event, owner, callback_name));
}
fn childCallBody(o: *x.Ops, child: c.JSValue, method_name: [*:0]const u8, event: []const u8, owner: c.JSValue, callback_name: [*:0]const u8) !void {
    const method = try o.get(child, method_name);
    _ = try o.call(method, child, &.{ try o.text(event), try o.get(owner, callback_name) });
}
fn truthyCell(parent: *x.Ops, owner: c.JSValue, name: [*:0]const u8) !bool {
    var s: x.Scope = .{ .engine = parent.s.engine }; var o: x.Ops = .{ .s = &s };
    const value = try x.owned.finishValue(&s, truthyCellBody(&o, owner, name));
    // The helper creates an immediate Boolean, with no deallocating payload.
    return c.JS_ToBool(parent.s.engine.context, value) != 0;
}
fn truthyCellBody(o: *x.Ops, owner: c.JSValue, name: [*:0]const u8) !c.JSValue { return c.pi_js_bool(o.s.engine.context, @intFromBool(o.truthy(try o.get(owner, name)))); }
fn clearTimer(parent: *x.Ops, owner: c.JSValue) !void {
    var s: x.Scope = .{ .engine = parent.s.engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, clearTimerBody(&o, owner));
}
fn clearTimerBody(o: *x.Ops, owner: c.JSValue) !void {
    const clear = try o.global("clearTimeout");
    _ = try o.call(clear, c.pi_js_undefined(), &.{try o.get(owner, "postExitTimer")});
}
fn executorBody(o: *x.Ops, child: c.JSValue, resolve: c.JSValue, reject: c.JSValue) !c.JSValue {
    const owner = try o.cell(); try o.put(owner, "child", child); try o.put(owner, "resolve", resolve); try o.put(owner, "reject", reject);
    try o.put(owner, "settled", c.pi_js_bool(o.s.engine.context, 0)); try o.put(owner, "exited", c.pi_js_bool(o.s.engine.context, 0));
    try o.put(owner, "exitCode", c.pi_js_null()); try o.put(owner, "postExitTimer", c.pi_js_undefined());
    try o.put(owner, "stdoutEnded", c.pi_js_bool(o.s.engine.context, @intFromBool(c.JS_IsNull(try o.get(child, "stdout")))));
    try o.put(owner, "stderrEnded", c.pi_js_bool(o.s.engine.context, @intFromBool(c.JS_IsNull(try o.get(child, "stderr")))));
    // All Source const closures exist before any listener registration.
    inline for (.{ Kind.cleanup, Kind.finalize, Kind.maybeFinalizeAfterExit, Kind.armIdleTimer, Kind.onData, Kind.onStdoutEnd, Kind.onStderrEnd, Kind.onError, Kind.onExit, Kind.onClose }) |kind| try o.put(owner, @tagName(kind).ptr, try closure(o, owner, kind));
    try streamCall(o, child, "stdout", "once", "end", owner, "onStdoutEnd");
    try streamCall(o, child, "stderr", "once", "end", owner, "onStderrEnd");
    try streamCall(o, child, "stdout", "on", "data", owner, "onData");
    try streamCall(o, child, "stderr", "on", "data", owner, "onData");
    try childCall(o, child, "once", "error", owner, "onError");
    try childCall(o, child, "once", "exit", owner, "onExit");
    try childCall(o, child, "once", "close", owner, "onClose");
    return c.pi_js_undefined();
}
fn dispatch(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, dispatchBody(&o, args, roots));
}
fn cleanup(o: *x.Ops, owner: c.JSValue) !void {
    if (try truthyCell(o, owner, "postExitTimer")) {
        try clearTimer(o, owner);
        try o.put(owner, "postExitTimer", c.pi_js_undefined());
    }
    const child = try o.get(owner, "child");
    try childCall(o, child, "removeListener", "error", owner, "onError");
    try childCall(o, child, "removeListener", "exit", owner, "onExit");
    try childCall(o, child, "removeListener", "close", owner, "onClose");
    try streamCall(o, child, "stdout", "removeListener", "end", owner, "onStdoutEnd");
    try streamCall(o, child, "stderr", "removeListener", "end", owner, "onStderrEnd");
    try streamCall(o, child, "stdout", "removeListener", "data", owner, "onData");
    try streamCall(o, child, "stderr", "removeListener", "data", owner, "onData");
}
fn dispatchBody(o: *x.Ops, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var raw: i32 = 0; if (c.JS_ToInt32(o.s.engine.context, &raw, roots[1]) < 0) return @import("native_js_values.zig").capture(o.s.engine);
    const kind: Kind = @enumFromInt(raw); const owner = roots[0];
    switch (kind) {
        .cleanup => try cleanup(o, owner),
        .finalize => {
            if (o.truthy(try o.get(owner, "settled"))) return c.pi_js_undefined();
            try o.put(owner, "settled", c.pi_js_bool(o.s.engine.context, 1));
            _ = try sibling(o, owner, "cleanup", &.{});
            const child = try o.get(owner, "child");
            try streamCall(o, child, "stdout", "destroy", null, owner, null);
            try streamCall(o, child, "stderr", "destroy", null, owner, null);
            _ = try o.call(try o.get(owner, "resolve"), c.pi_js_undefined(), &.{x.arg(args, 0)});
        },
        .maybeFinalizeAfterExit => {
            if (!o.truthy(try o.get(owner, "exited")) or o.truthy(try o.get(owner, "settled"))) return c.pi_js_undefined();
            if (o.truthy(try o.get(owner, "stdoutEnded")) and o.truthy(try o.get(owner, "stderrEnded"))) _ = try sibling(o, owner, "finalize", &.{try o.get(owner, "exitCode")});
        },
        .armIdleTimer => {
            if (try truthyCell(o, owner, "postExitTimer")) try clearTimer(o, owner);
            const set_timeout = try o.global("setTimeout");
            const on_idle = try closure(o, owner, .idle); // Fresh literal for EVERY arm.
            try o.put(owner, "postExitTimer", try o.call(set_timeout, c.pi_js_undefined(), &.{ on_idle, c.JS_NewInt32(o.s.engine.context, 100) }));
        },
        .onData => if (o.truthy(try o.get(owner, "exited")) and !o.truthy(try o.get(owner, "settled"))) { _ = try sibling(o, owner, "armIdleTimer", &.{}); },
        .onStdoutEnd, .onStderrEnd => {
            try o.put(owner, if (kind == .onStdoutEnd) "stdoutEnded" else "stderrEnded", c.pi_js_bool(o.s.engine.context, 1));
            _ = try sibling(o, owner, "maybeFinalizeAfterExit", &.{});
        },
        .onError => {
            if (o.truthy(try o.get(owner, "settled"))) return c.pi_js_undefined();
            try o.put(owner, "settled", c.pi_js_bool(o.s.engine.context, 1));
            _ = try sibling(o, owner, "cleanup", &.{});
            // err is borrowed DATA. Preserve identity without flag/tag inspection.
            _ = try o.call(try o.get(owner, "reject"), c.pi_js_undefined(), &.{x.arg(args, 0)});
        },
        .onExit => {
            try o.put(owner, "exited", c.pi_js_bool(o.s.engine.context, 1)); try o.put(owner, "exitCode", x.arg(args, 0));
            _ = try sibling(o, owner, "maybeFinalizeAfterExit", &.{});
            if (!o.truthy(try o.get(owner, "settled"))) _ = try sibling(o, owner, "armIdleTimer", &.{});
        },
        .onClose => { _ = try sibling(o, owner, "finalize", &.{x.arg(args, 0)}); },
        .idle => return c.JS_DupValue(o.s.engine.context, try sibling(o, owner, "finalize", &.{try o.get(owner, "exitCode")})),
    }
    return c.pi_js_undefined();
}
