//! Private actual generic manager/control/kernel-lock factories. Native fork backend is a separate required export.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const lock_api = @import("native_chord_process_lock.zig");
fn lockCallback(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    return lock_api.acquire(engine, captures[0], h.arg(args, 0)) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
pub fn exports(engine: *h.Engine, bindings: c.JSValue) !c.JSValue {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const value = try s.record();
    const function = @import("native_node_function.zig");
    try js.define(engine, value, "createHostManager", try function.create(engine, "createHostManager", 1, @import("native_chord_manager.zig").create, &.{bindings}));
    try js.define(engine, value, "childControl", try function.create(engine, "childControl", 0, @import("native_chord_child_control.zig").API(lock_api.acquire).create, &.{bindings}));
    const lock = try s.keep(try function.create(engine, "processLock", 1, lockCallback, &.{bindings}));
    const async_prototype = try s.keep(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, lock, async_prototype) < 0) return js.capture(engine);
    try h.field(&s, value, "processLock", lock);
    return s.result(value);
}
