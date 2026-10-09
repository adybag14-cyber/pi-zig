const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const scopes = @import("extensions/native_async_scope.zig");
const timers = @import("extensions/timers.zig");
const c = engine_mod.c;
const Capture = struct {
    active: usize = 0,
    starts: [4]usize = .{0} ** 4,
    ends: [4]usize = .{0} ** 4,
    all_started_at_first_end: bool = false,
    fn mark(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
        const engine = engine_mod.Engine.fromContext(context.?);
        const self: *Capture = @ptrCast(@alignCast(engine.host_data.?));
        scopes.requireLive(engine) catch return c.JS_ThrowTypeError(context, "retired scope");
        if (argc != 1 or self.active == 0 or self.active > 4) return c.JS_ThrowTypeError(context, "missing invocation scope");
        const index = self.active - 1;
        if (c.JS_ToBool(context, args[0]) != 0) {
            self.ends[index] += 1;
            if (self.ends[0] + self.ends[1] + self.ends[2] + self.ends[3] == 1) self.all_started_at_first_end = std.mem.allEqual(usize, &self.starts, 1);
        } else self.starts[index] += 1;
        return c.JS_NewInt64(context, @intCast(self.active));
    }
};
const Invocation = struct {
    capture: *Capture,
    id: usize,
    fn enter(raw: ?*anyopaque) void {
        const self: *Invocation = @ptrCast(@alignCast(raw.?));
        self.capture.active = self.id;
    }
    fn leave(raw: ?*anyopaque) void {
        const self: *Invocation = @ptrCast(@alignCast(raw.?));
        self.capture.active = 0;
    }
};
test "native async scope admits four promises before completion and preserves each timer and await owner" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try timers.install(engine, std.testing.io);
    var capture: Capture = .{};
    engine.host_data = &capture;
    defer engine.host_data = null;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const mark = try engine.checked(c.JS_NewCFunction(engine.context, Capture.mark, "mark", 1));
    if (c.JS_SetPropertyStr(engine.context, global, "mark", mark) < 0) return error.JavaScriptException;
    var invocations: [4]Invocation = undefined;
    var tokens: [4]c.JSValue = .{c.pi_js_undefined()} ** 4;
    defer for (tokens) |token| {
        scopes.retire(engine, token);
        engine.freeValue(token);
    };
    for (&invocations, &tokens, 0..) |*invocation, *token, index| {
        invocation.* = .{ .capture = &capture, .id = index + 1 };
        token.* = try scopes.create(engine, invocation, Invocation.enter, Invocation.leave);
        const guard = scopes.enter(engine, token.*);
        defer guard.restore();
        const source = try std.fmt.allocPrint(std.testing.allocator, "globalThis.p{d}=(async()=>{{const id=mark(false);await new Promise(resolve=>setTimeout(resolve,10));await Promise.resolve();if(mark(true)!==id)throw Error('owner changed');return id;}})();", .{index + 1});
        defer std.testing.allocator.free(source);
        const started = try engine.eval(source, "scoped-start.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(started);
    }
    const all = try engine.eval("Promise.all([p1,p2,p3,p4])", "scoped-finish.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(all);
    const value = engine.awaitValue(all) catch |err| {
        std.debug.print("scope failure {s}: {s}, active={d}, starts={any}, ends={any}\n", .{ @errorName(err), engine.last_error orelse "", capture.active, capture.starts, capture.ends });
        return err;
    };
    defer engine.freeValue(value);
    const encoded = try engine.stringify(value);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("[1,2,3,4]", encoded);
    try std.testing.expect(capture.all_started_at_first_end);
    try std.testing.expectEqual(@as(usize, 0), capture.active);
    try std.testing.expectEqualSlices(usize, &.{ 1, 1, 1, 1 }, &capture.ends);
}
