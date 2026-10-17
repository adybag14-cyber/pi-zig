//! Owner-thread value and dependency operations for the pinned get-tsconfig port.
pub const std = @import("std");
pub const v = @import("native_ai_provider_values.zig");
pub const c = v.c;
pub const Scope = v.Scope;
pub const functions = @import("native_node_function.zig");
pub fn arg(args: []const c.JSValue, i: usize) c.JSValue { return if (i < args.len) args[i] else c.pi_js_undefined(); }
pub fn n(s: *Scope, i: i64) c.JSValue { return c.JS_NewInt64(s.engine.context, i); }
pub fn key(s: *Scope, value: c.JSValue, name: c.JSValue) !c.JSValue { return s.own(try v.js.getKey(s.engine, value, name)); }
pub fn at(s: *Scope, value: c.JSValue, i: u32) !c.JSValue { return v.at(s, value, i); }
pub fn eq(s: *Scope, value: c.JSValue, text: []const u8) !bool { return s.equal(value, try s.text(text)); }
pub fn call(s: *Scope, state: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.call(try s.get(state, name), c.pi_js_undefined(), args); }
pub fn path(s: *Scope, state: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.invoke(try s.get(state, "path"), name, args); }
pub fn array(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array(); for (values, 0..) |value, i| try s.index(result, @intCast(i), value); return result;
}
pub fn push(s: *Scope, target: c.JSValue, value: c.JSValue) !void { _ = try s.invoke(target, "push", &.{value}); }
pub fn length(s: *Scope, value: c.JSValue) !u32 { return v.length(s, value); }
pub fn starts(s: *Scope, value: c.JSValue, prefix: []const u8) !bool { return s.truthy(try s.invoke(value, "startsWith", &.{try s.text(prefix)})); }
pub fn relative(s: *Scope, state: c.JSValue, value: c.JSValue) !bool {
    return s.truthy(try s.invoke(try s.get(state, "relativePattern"), "test", &.{value}));
}
pub fn regexp(s: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try s.text(pattern), try s.text(flags) };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
pub fn slash(s: *Scope, value: c.JSValue) !c.JSValue {
    if (try starts(s, value, "\\\\?\\")) return value;
    const replace = try s.get(value, "replace"); const pattern = try regexp(s, "\\\\", "g");
    return s.call(replace, value, &.{ pattern, try s.text("/") });
}
pub fn slashCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); return c.JS_DupValue(engine.context, try slash(&s, arg(args, 0)));
}
pub fn normalizeRelative(s: *Scope, state: c.JSValue, value: c.JSValue) !c.JSValue {
    const normalized = try slash(s, value); return if (try relative(s, state, normalized)) normalized else s.concat(try s.text("./"), try s.stringify(normalized));
}
pub fn pathRelative(s: *Scope, state: c.JSValue, from: c.JSValue, to: c.JSValue) !c.JSValue { return normalizeRelative(s, state, try path(s, state, "relative", &.{from, to})); }
pub fn remove(s: *Scope, value: c.JSValue, name: [*:0]const u8) !void { return v.remove(s, value, name); }
pub fn errorValue(s: *Scope, kind: [*:0]const u8, message: c.JSValue) !c.JSValue { return s.own(try v.js.builtin(s.engine, kind, &.{message})); }
pub fn throw(s: *Scope, kind: [*:0]const u8, message: c.JSValue) anyerror {
    const reason = errorValue(s, kind, message) catch |err| return err;
    _ = s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason))) catch |err| return err; unreachable;
}
pub fn quota(s: *Scope, message: []const u8) anyerror {
    const reason = errorValue(s, "RangeError", s.text(message) catch |err| return err) catch |err| return err;
    c.JS_SetUncatchableError(s.engine.context, reason);
    _ = s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason))) catch |err| return err; unreachable;
}
pub fn ordinary(engine: *v.em.Engine, failure: anyerror, generation: u64) !void {
    if (failure == error.OutOfMemory) return failure;
    if (failure == error.JavaScriptException) if (engine.captured_exception) |reason| {
        try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation);
        if (c.JS_IsUncatchableError(reason)) return failure;
    };
}
pub fn tick(engine: *v.em.Engine, steps: *usize) !void {
    steps.* +|= 1;
    if (engine.cancelled.load(.acquire) or (steps.* % 256 == 0 and blk: { engine.interrupts +|= 1; break :blk engine.interrupts > engine.options.interrupt_budget; })) {
        _ = c.JS_ThrowInternalError(engine.context, "interrupted"); const reason = c.JS_GetException(engine.context);
        c.JS_SetUncatchableError(engine.context, reason); _ = try engine.checked(c.JS_Throw(engine.context, reason)); unreachable;
    }
}
pub fn Boundary(comptime callback: functions.Callback) type { return struct {
    pub fn invoke(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
        const generation = engine.native_allocation_generation;
        return callback(engine, receiver, args, roots) catch |err| {
            if (err == error.JavaScriptException) if (engine.captured_exception) |reason| @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| return fatal;
            return err;
        };
    }
}; }
pub fn cached(s: *Scope, state: c.JSValue, cache: c.JSValue, method: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const values = try array(s, args);
    const cache_key = try s.concat(try s.concat(try s.text(std.mem.span(method)), try s.text(":")), try s.invoke(values, "join", &.{try s.text(":")}));
    const previous = try s.invoke(cache, "get", &.{cache_key});
    if (!c.JS_IsUndefined(previous)) return previous;
    const reflect = try s.global("Reflect"); const apply = try s.get(reflect, "apply");
    const function = try s.get(try s.get(state, "fsMethods"), method);
    const result = try s.call(apply, reflect, &.{ function, try s.get(state, "fs"), values });
    _ = try s.invoke(cache, "set", &.{ cache_key, result }); return result;
}
pub fn exists(s: *Scope, state: c.JSValue, cache: c.JSValue, file: c.JSValue) !bool { return s.truthy(try cached(s, state, cache, "existsSync", &.{file})); }
pub fn isKind(s: *Scope, state: c.JSValue, cache: c.JSValue, file: c.JSValue, method: [*:0]const u8) !bool { return s.truthy(try s.invoke(try cached(s, state, cache, "statSync", &.{file}), method, &.{})); }
pub fn read(s: *Scope, state: c.JSValue, cache: c.JSValue, file: c.JSValue) !c.JSValue { return s.own(try @import("native_tsconfig_jsonc.zig").parse(s.engine, try cached(s, state, cache, "readFileSync", &.{ file, try s.text("utf8") }))); }
pub fn findUp(engine: *v.em.Engine, state: c.JSValue, search: c.JSValue, name: c.JSValue, cache: c.JSValue) !c.JSValue {
    var current = c.JS_DupValue(engine.context, search); defer engine.freeValue(current); var steps: usize = 0;
    while (true) {
        var s: Scope = .{ .engine = engine }; defer s.deinit(); try tick(engine, &steps);
        const candidate = try s.invoke(try s.get(try s.get(state, "path"), "posix"), "join", &.{ current, name });
        if (try exists(&s, state, cache, candidate)) return c.JS_DupValue(engine.context, candidate);
        const parent = try path(&s, state, "dirname", &.{current}); if (s.equal(parent, current)) return c.pi_js_undefined();
        const held = c.JS_DupValue(engine.context, parent); engine.freeValue(current); current = held;
    }
}
