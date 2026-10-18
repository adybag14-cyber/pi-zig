//! Private CVM operations for the actual SDK Git source parser. Catch policy
//! is attached to the operation that failed, never to a later arbitrary value.
const v = @import("native_ai_provider_values.zig");
pub const c = v.c;
pub const Scope = v.Scope;
pub const em = v.em;
const allocation = @import("native_async_body.zig");
pub const owned = @import("native_sdk_owned_completion.zig");
pub const iterators = struct {
    pub const v = @import("native_ai_provider_values.zig");
    pub const budget = @import("native_mlly_values.zig").budget;
    pub fn advance(engine: *em.Engine, iterator: *v.js.Iterator) !?c.JSValue {
        try budget(engine, &iterator.native_steps);
        var s: Scope = .{ .engine = engine };
        const result = try owned.finishValue(&s, advanceBody(&s, iterator));
        if (iterator.closed) { engine.freeValue(result); return null; }
        return result;
    }
    fn advanceBody(s: *Scope, iterator: *v.js.Iterator) !c.JSValue {
        errdefer iterator.closed = true;
        var o: Ops = .{ .s = s };
        const step = try o.call(iterator.next_function, iterator.iterator, &.{});
        if (!c.JS_IsObject(step)) return v.js.typeError(s.engine, "Iterator result is not an object");
        if (o.truthy(try o.get(step, "done"))) { iterator.closed = true; return c.pi_js_undefined(); }
        return c.JS_DupValue(s.engine.context, try o.get(step, "value"));
    }
    pub fn closeNormal(engine: *em.Engine, iterator: *v.js.Iterator) !void {
        var s: Scope = .{ .engine = engine };
        return owned.finishVoid(&s, closeBody(&s, iterator, true));
    }
    fn closeBody(s: *Scope, iterator: *v.js.Iterator, validate: bool) !void {
        if (iterator.closed) return;
        iterator.closed = true;
        var o: Ops = .{ .s = s };
        const method = try o.get(iterator.iterator, "return");
        if (nullish(method)) return;
        const result = try o.call(method, iterator.iterator, &.{});
        if (validate and !c.JS_IsObject(result)) return v.js.typeError(s.engine, "Iterator return result is not an object");
    }
    pub fn closeAbrupt(engine: *em.Engine, iterator: *v.js.Iterator, failure: anyerror, _: u64) anyerror {
        var completion = owned.Completion.initVoid(engine, @as(anyerror!void, failure));
        var s: Scope = .{ .engine = engine };
        // A normal return result is not validated for throw completion. The
        // original is already owned outside the diagnostic/pending slots.
        owned.finishVoid(&s, closeBody(&s, iterator, false)) catch {};
        completion.finishVoid() catch |err| return err;
        unreachable;
    }
};
pub fn duplicate(engine: *em.Engine, result: anyerror!c.JSValue) anyerror!c.JSValue { return c.JS_DupValue(engine.context, try result); }
fn guarded(engine: *em.Engine, generation: u64, result: anyerror!c.JSValue) !c.JSValue { return result catch |err| return current(engine, err, generation); }
pub fn initIterator(parent: *Scope, iterable: c.JSValue) !v.js.Iterator {
    var s: Scope = .{ .engine = parent.engine };
    const result = iteratorBody(&s, iterable);
    if (result) |actual| {
        owned.finishVoid(&s, {}) catch |err| {
            var failure = owned.Completion.initVoid(parent.engine, @as(anyerror!void, err));
            failure.release(actual.next_function); failure.release(actual.iterator);
            failure.finishVoid() catch |outcome| return outcome; unreachable;
        };
        return actual;
    } else |err| { try owned.finishVoid(&s, @as(anyerror!void, err)); unreachable; }
}
fn iteratorBody(s: *Scope, iterable: c.JSValue) !v.js.Iterator {
    var o: Ops = .{ .s = s };
    const symbol = try o.own(try s.engine.checked(c.JS_GetIteratorSymbol(s.engine.context)));
    const method = try o.key(iterable, symbol);
    const value = try o.call(method, iterable, &.{});
    if (!c.JS_IsObject(value)) return v.js.typeError(s.engine, "Iterator is not an object");
    const next = try o.get(value, "next");
    return .{ .engine = s.engine, .iterator = c.JS_DupValue(s.engine.context, value), .next_function = c.JS_DupValue(s.engine.context, next) };
}
pub fn finishNative(scope: *Scope, result: anytype) anyerror!@typeInfo(@TypeOf(result)).error_union.payload {
    const T = @typeInfo(@TypeOf(result)).error_union.payload;
    var value: T = undefined;
    const status: anyerror!void = if (result) |returned| blk: { value = returned; break :blk {}; } else |err| err;
    try owned.finishVoid(scope, status);
    return value;
}
pub fn retireIterator(engine: *em.Engine, iterator: *v.js.Iterator, result: anyerror!void) !void {
    var completion = owned.Completion.initVoid(engine, result);
    completion.release(iterator.next_function);
    completion.release(iterator.iterator);
    iterator.next_function = c.pi_js_undefined(); iterator.iterator = c.pi_js_undefined();
    return completion.finishVoid();
}
pub fn retireNative(engine: *em.Engine, actual: *v.js.Iterator, result: anytype) anyerror!@typeInfo(@TypeOf(result)).error_union.payload {
    const T = @typeInfo(@TypeOf(result)).error_union.payload;
    var value: T = undefined;
    const status: anyerror!void = if (result) |returned| blk: { value = returned; break :blk {}; } else |err| err;
    try retireIterator(engine, actual, status);
    return value;
}
pub const Ops = struct {
    s: *Scope,
    pub fn own(o: *Ops, value: c.JSValue) !c.JSValue {
        if (o.s.inline_count < o.s.inline_values.len) {
            o.s.inline_values[o.s.inline_count] = value; o.s.inline_count += 1; return value;
        }
        o.s.values.append(o.s.engine.gpa, value) catch |err| {
            // Direct allocator failure is published BEFORE releasing the
            // transferred root; its finalizer cannot replace the native OOM.
            var failure = owned.Completion.initValue(o.s.engine, @as(anyerror!c.JSValue, err));
            failure.release(value);
            return failure.finishValue();
        };
        return value;
    }
    pub fn text(o: *Ops, text_value: []const u8) !c.JSValue { try o.s.engine.checkNativeEntry(); return o.own(try allocated(o.s.engine, c.JS_NewStringLen(o.s.engine.context, text_value.ptr, text_value.len))); }
    pub fn object(o: *Ops) !c.JSValue { try o.s.engine.checkNativeEntry(); return o.own(try allocated(o.s.engine, c.JS_NewObject(o.s.engine.context))); }
    pub fn array(o: *Ops) !c.JSValue { try o.s.engine.checkNativeEntry(); return o.own(try allocated(o.s.engine, c.JS_NewArray(o.s.engine.context))); }
    pub fn get(o: *Ops, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        if (c.JS_IsNull(target) or c.JS_IsUndefined(target)) {
            _ = o.s.engine.checked(c.JS_ThrowTypeError(o.s.engine.context, "Cannot read properties of %s (reading '%s')", @as([*:0]const u8, if (c.JS_IsNull(target)) "null" else "undefined"), name)) catch |err| return err;
            unreachable;
        }
        const generation = o.s.engine.native_allocation_generation;
        return o.own(v.js.get(o.s.engine, target, name) catch |err| return current(o.s.engine, err, generation));
    }
    pub fn key(o: *Ops, target: c.JSValue, name: c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        const generation = o.s.engine.native_allocation_generation;
        return o.own(v.js.getKey(o.s.engine, target, name) catch |err| return current(o.s.engine, err, generation));
    }
    pub fn at(o: *Ops, target: c.JSValue, index: u32) !c.JSValue { return o.key(target, c.JS_NewUint32(o.s.engine.context, index)); }
    pub fn global(o: *Ops, name: [*:0]const u8) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        const global_object = c.JS_GetGlobalObject(o.s.engine.context);
        const generation = o.s.engine.native_allocation_generation;
        var completion = owned.Completion.initValue(o.s.engine, guarded(o.s.engine, generation, v.js.get(o.s.engine, global_object, name)));
        completion.release(global_object);
        return o.own(try completion.finishValue());
    }
    pub fn call(o: *Ops, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        const generation = o.s.engine.native_allocation_generation;
        return o.own(v.js.call(o.s.engine, function, receiver, args) catch |err| return current(o.s.engine, err, generation));
    }
    pub fn invoke(o: *Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return o.call(try o.get(receiver, name), receiver, args); }
    pub fn sliceAfter(o: *Ops, receiver: c.JSValue, position: c.JSValue) !c.JSValue { const method = try o.get(receiver, "slice"); return o.call(method, receiver, &.{try o.binary(0, position, o.number(1))}); }
    pub fn sliceToAfter(o: *Ops, receiver: c.JSValue, position: c.JSValue) !c.JSValue { const method = try o.get(receiver, "slice"); return o.call(method, receiver, &.{ o.number(0), try o.binary(0, position, o.number(1)) }); }
    pub fn construct(o: *Ops, function: c.JSValue, args: []const c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        const generation = o.s.engine.native_allocation_generation;
        return o.own(o.s.engine.checked(c.JS_CallConstructor(o.s.engine.context, function, @intCast(args.len), @constCast(args.ptr))) catch |err| return current(o.s.engine, err, generation));
    }
    pub fn put(o: *Ops, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        try o.s.engine.checkNativeEntry();
        if (c.JS_DefinePropertyValueStr(o.s.engine.context, target, name, c.JS_DupValue(o.s.engine.context, value), c.JS_PROP_C_W_E) < 0) return allocationFailure(o.s.engine);
        try o.s.engine.checkNativeEntry();
    }
    pub fn index(o: *Ops, target: c.JSValue, index: u32, value: c.JSValue) !void {
        try o.s.engine.checkNativeEntry();
        if (c.JS_DefinePropertyValueUint32(o.s.engine.context, target, index, c.JS_DupValue(o.s.engine.context, value), c.JS_PROP_C_W_E) < 0) return allocationFailure(o.s.engine);
        try o.s.engine.checkNativeEntry();
    }
    pub fn set(o: *Ops, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        try o.s.engine.checkNativeEntry();
        const generation = o.s.engine.native_allocation_generation;
        o.s.set(target, name, value) catch |err| return current(o.s.engine, err, generation);
        o.s.engine.checkNativeEntry() catch |err| return current(o.s.engine, err, generation);
    }
    pub fn stringify(o: *Ops, value: c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        const generation = o.s.engine.native_allocation_generation;
        return o.own(o.s.engine.checked(c.JS_ToString(o.s.engine.context, value)) catch |err| return current(o.s.engine, err, generation));
    }
    pub fn binary(o: *Ops, operation: c_int, a: c.JSValue, b: c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        const generation = o.s.engine.native_allocation_generation;
        return o.own(o.s.engine.checked(c.JS_PiBinaryOperator(o.s.engine.context, operation, a, b)) catch |err| return current(o.s.engine, err, generation));
    }
    pub fn compare(o: *Ops, operation: c_int, a: c.JSValue, b: c.JSValue) !bool { return o.truthy(try o.binary(operation, a, b)); }
    pub fn truthy(o: *Ops, value: c.JSValue) bool { return o.s.truthy(value); }
    pub fn equal(o: *Ops, value: c.JSValue, text_value: []const u8) !bool { return o.s.equal(value, try o.text(text_value)); }
    pub fn number(o: *Ops, value: i32) c.JSValue { return c.JS_NewInt32(o.s.engine.context, value); }
    pub fn regex(o: *Ops, pattern: []const u8, flags: []const u8) !c.JSValue {
        return o.construct(o.s.engine.intrinsic_regexp_constructor, &.{ try o.text(pattern), try o.text(flags) });
    }
    pub fn test(o: *Ops, pattern: []const u8, flags: []const u8, value: c.JSValue) !bool { return o.truthy(try o.invoke(try o.regex(pattern, flags), "test", &.{value})); }
    pub fn replace(o: *Ops, value: c.JSValue, pattern: []const u8, flags: []const u8, replacement: []const u8) !c.JSValue {
        const function = try o.get(value, "replace");
        return o.call(function, value, &.{ try o.regex(pattern, flags), try o.text(replacement) });
    }
    pub fn match(o: *Ops, value: c.JSValue, pattern: []const u8) !c.JSValue {
        const function = try o.get(value, "match"); return o.call(function, value, &.{try o.regex(pattern, "")});
    }
    pub fn template(o: *Ops, pieces: []const c.JSValue) !c.JSValue {
        var result = try o.text("");
        for (pieces) |piece| result = try o.binary(0, result, try o.stringify(piece));
        return result;
    }
    pub fn append(o: *Ops, target: *c.JSValue, value: c.JSValue) !void { target.* = try o.binary(0, target.*, try o.stringify(value)); }
    pub fn decode(o: *Ops, value: c.JSValue) !c.JSValue { return o.call(try o.global("decodeURIComponent"), c.pi_js_undefined(), &.{value}); }
};
/// These three direct allocation APIs cannot execute a guest constructor. Their
/// JS_EXCEPTION result is a concrete native allocation failure, not name/tag
/// inspection of an arbitrary guest value. Preserve the actual owned reason.
fn allocated(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsException(value)) return engine.checked(value);
    const reason = c.JS_GetException(engine.context);
    c.JS_SetUncatchableError(engine.context, reason);
    return engine.checked(c.JS_Throw(engine.context, reason));
}
pub fn allocationFailure(engine: *em.Engine) anyerror {
    const reason = c.JS_GetException(engine.context); c.JS_SetUncatchableError(engine.context, reason);
    _ = engine.checked(c.JS_Throw(engine.context, reason)) catch |err| return err; unreachable;
}
pub fn current(engine: *em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.JavaScriptException) {
        if (c.JS_HasException(engine.context)) { const captured = v.js.capture(engine); if (captured != error.JavaScriptException) return captured; }
        if (engine.captured_exception) |reason| {
            if (c.JS_IsUncatchableError(reason)) return err;
            allocation.rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| return fatal;
        }
    }
    return err;
}
/// Transfer one actual ordinary catch reason. Every VM operation above already
/// classified its own failure boundary, so an outer catch never widens it.
pub fn takeOrdinary(engine: *em.Engine, err: anyerror) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    if (c.JS_HasException(engine.context)) { const captured = v.js.capture(engine); if (captured != error.JavaScriptException) return captured; }
    const reason = engine.captured_exception orelse return error.MissingActualGitParserCatchReason;
    if (c.JS_IsUncatchableError(reason)) return err;
    engine.captured_exception = null;
    return reason;
}
pub fn swallow(engine: *em.Engine, err: anyerror) !void {
    const reason = try takeOrdinary(engine, err);
    var completion = owned.Completion.initVoid(engine, {});
    completion.release(reason);
    return completion.finishVoid();
}
pub fn throwReason(engine: *em.Engine, reason: c.JSValue) anyerror { _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch |err| return err; unreachable; }
pub fn nullish(value: c.JSValue) bool { return v.nullish(value); }
