//! Public application owners: scoped guest operations and explicit completion
//! retirement. The actual source expression chooses each Scope's lifetime.
pub const em = @import("engine.zig");
pub const c = em.c;
pub const Scope = @import("native_models_stream_scope.zig").Scope;
pub const owned = @import("native_sdk_owned_completion.zig");
pub const guest = @import("native_sdk_guest_operation.zig");
pub const function = @import("native_node_function.zig");
pub const af = @import("native_async_function.zig");
const agent = @import("native_agent_af_values.zig");

pub const get = guest.get;
pub const at = guest.at;
pub const global = guest.global;
pub const call = guest.call;
pub const construct = guest.construct;
pub const set = guest.set;
pub const put = guest.put;
pub const index = guest.index;
pub const binary = guest.binary;
pub const stringify = guest.stringify;

pub fn poll(engine: *em.Engine, steps: *usize) !void {
    try engine.checkNativeEntry();
    return @import("native_node_commonjs_interrupt.zig").step(engine, steps);
}
pub fn own(s: *Scope, value: c.JSValue) !c.JSValue { return owned.ownRoot(s, value); }
pub fn arg(args: []const c.JSValue, position: usize) c.JSValue { return if (position < args.len) args[position] else c.pi_js_undefined(); }
pub fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
pub fn truthy(s: *Scope, value: c.JSValue) bool { return c.JS_ToBool(s.engine.context, value) == 1; }
pub fn equal(s: *Scope, a: c.JSValue, b: c.JSValue) bool { return c.JS_IsStrictEqual(s.engine.context, a, b); }
pub fn number(s: *Scope, value: f64) c.JSValue { return c.JS_NewFloat64(s.engine.context, value); }
pub fn boolean(s: *Scope, value: bool) c.JSValue { return c.JS_NewBool(s.engine.context, value); }
pub fn duplicate(s: *Scope, value: c.JSValue) c.JSValue { return c.JS_DupValue(s.engine.context, value); }

fn allocation(s: *Scope, boundary: *guest.Boundary, value: c.JSValue, generation: u64) !c.JSValue {
    // Canonical catalog raw-producer check. This span begins immediately before
    // a non-guest JS_New* operation, never around ToPropertyKey/get/call.
    _ = s.engine.nativeCallbackResult(c.pi_js_undefined());
    if (c.JS_HasException(s.engine.context)) {
        const reason = c.JS_GetException(s.engine.context);
        const tag = c.pi_js_native_allocation_error_generation(reason);
        const distance = tag -% generation;
        if (tag != 0 and distance != 0 and distance <= s.engine.native_allocation_generation -% generation)
            c.JS_SetUncatchableError(s.engine.context, reason);
        _ = c.JS_Throw(s.engine.context, reason);
        var completion = owned.Completion.initValue(s.engine, @as(anyerror!c.JSValue, error.JavaScriptException));
        if (!c.JS_IsException(value)) completion.release(value);
        return boundary.finishValue(s, completion.finishValue());
    }
    return boundary.finishValue(s, value);
}
pub fn text(s: *Scope, bytes: []const u8) !c.JSValue {
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const generation = s.engine.native_allocation_generation;
    return allocation(s, &boundary, c.JS_NewStringLen(s.engine.context, bytes.ptr, bytes.len), generation);
}
pub fn object(s: *Scope) !c.JSValue {
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const generation = s.engine.native_allocation_generation;
    return allocation(s, &boundary, c.JS_NewObject(s.engine.context), generation);
}
pub fn stateObject(s: *Scope) !c.JSValue {
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const generation = s.engine.native_allocation_generation;
    return allocation(s, &boundary, c.JS_NewObjectProto(s.engine.context, c.pi_js_null()), generation);
}
pub fn array(s: *Scope) !c.JSValue {
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const generation = s.engine.native_allocation_generation;
    return allocation(s, &boundary, c.JS_NewArray(s.engine.context), generation);
}
pub fn key(s: *Scope, target: c.JSValue, property: c.JSValue) !c.JSValue {
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const atom = c.JS_ValueToAtom(s.engine.context, property);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try boundary.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
    return guest.getAtom(s, target, atom);
}
pub fn iteratorSymbol(s: *Scope) !c.JSValue {
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, c.JS_GetIteratorSymbol(s.engine.context));
}
pub fn ordinary(s: *Scope, name: [*:0]const u8, length: c_int, callback: function.Callback, roots: []const c.JSValue) !c.JSValue {
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, function.create(s.engine, name, length, callback, roots));
}
pub fn arrow(s: *Scope, name: [*:0]const u8, length: c_int, callback: function.Callback, roots: []const c.JSValue) !c.JSValue {
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, function.createArrow(s.engine, name, length, callback, roots));
}
pub fn method(s: *Scope, name: [*:0]const u8, length: c_int, callback: function.Callback, roots: []const c.JSValue) !c.JSValue {
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, function.createMethod(s.engine, name, length, callback, roots));
}
pub fn typeError(s: *Scope, message: [*:0]const u8) anyerror {
    var boundary: guest.Boundary = .{ .engine = s.engine }; boundary.begin() catch |err| return err;
    const generation = s.engine.native_allocation_generation;
    _ = allocation(s, &boundary, c.JS_ThrowTypeError(s.engine.context, "%s", message), generation) catch |err| return err;
    unreachable;
}
pub fn eq(s: *Scope, value: c.JSValue, literal: []const u8) !bool {
    if (!c.JS_IsString(value)) return false;
    var local: Scope = .{ .engine = s.engine };
    const result: anyerror!c.JSValue = body: {
        const comparison = equal(&local, value, text(&local, literal) catch |err| break :body err);
        break :body boolean(&local, comparison);
    };
    return truthy(s, try owned.finishValue(&local, result));
}
pub fn invokeOwned(engine: *em.Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, invokeBody(&s, receiver, name, args));
}
fn invokeBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return duplicate(s, try call(s, try get(s, receiver, name), receiver, args));
}
pub fn invoke(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return own(s, try invokeOwned(s.engine, receiver, name, args));
}
pub fn invokeTextOwned(engine: *em.Engine, receiver: c.JSValue, name: [*:0]const u8, literal: []const u8) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, invokeTextBody(&s, receiver, name, literal));
}
fn invokeTextBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, literal: []const u8) !c.JSValue {
    const callable = try get(s, receiver, name);
    return duplicate(s, try call(s, callable, receiver, &.{try text(s, literal)}));
}
pub fn testText(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, literal: []const u8) !bool {
    var local: Scope = .{ .engine = s.engine };
    return truthy(s, try owned.finishValue(&local, testTextBody(&local, receiver, name, literal)));
}
fn testTextBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, literal: []const u8) !c.JSValue {
    const value = try own(s, try invokeTextOwned(s.engine, receiver, name, literal));
    return boolean(s, truthy(s, value));
}

/// Owns the actual iterator record. The iterator-method expression is retired
/// before the next getter; each result object is retired before the body starts.
pub const Iterator = struct {
    engine: *em.Engine,
    receiver: c.JSValue,
    next_function: c.JSValue,
    closed: bool = false,
    steps: usize = 0,
    pub fn init(engine: *em.Engine, iterable: c.JSValue) !Iterator {
        return initOwned(engine, c.JS_DupValue(engine.context, iterable));
    }
    pub fn initOwned(engine: *em.Engine, incoming: c.JSValue) !Iterator {
        var expression: Scope = .{ .engine = engine };
        const receiver_owned = try owned.finishValue(&expression, acquireOwned(&expression, incoming));
        return initReceiver(engine, receiver_owned);
    }
    fn acquireOwned(s: *Scope, incoming: c.JSValue) !c.JSValue {
        const iterable = try own(s, incoming);
        return acquireIterator(s.engine, iterable);
    }
    fn initReceiver(engine: *em.Engine, incoming: c.JSValue) !Iterator {
        var s: Scope = .{ .engine = engine };
        const receiver = try own(&s, incoming);
        const outcome: anyerror!c.JSValue = if (get(&s, receiver, "next")) |next_function| duplicate(&s, next_function) else |err| err;
        const receiver_owned = duplicate(&s, receiver);
        var completion = owned.Completion.initValue(engine, outcome);
        completion.releaseScope(&s);
        const next_function = completion.finishValue() catch |err| {
            var failed = owned.Completion.initVoid(engine, err);
            failed.release(receiver_owned); try failed.finishVoid(); unreachable;
        };
        return .{ .engine = engine, .receiver = receiver_owned, .next_function = next_function };
    }
    pub fn next(self: *Iterator) !?c.JSValue {
        poll(self.engine, &self.steps) catch |err| { self.closed = true; return err; };
        var s: Scope = .{ .engine = self.engine };
        var done = false;
        const result = owned.finishValue(&s, nextBody(&s, self, &done)) catch |err| { self.closed = true; return err; };
        if (done) { self.closed = true; self.engine.freeValue(result); return null; }
        return result;
    }
    fn nextBody(s: *Scope, self: *Iterator, done: *bool) !c.JSValue {
        const result = try call(s, self.next_function, self.receiver, &.{});
        if (!c.JS_IsObject(result)) return typeError(s, "iterator must return an object");
        done.* = truthy(s, try get(s, result, "done"));
        return if (done.*) c.pi_js_undefined() else duplicate(s, try get(s, result, "value"));
    }
    pub fn finish(self: *Iterator, result: anyerror!void) !void {
        const selected: anyerror!void = if (result) |_| {} else |err| self.closeAbrupt(err);
        var completion = owned.Completion.initVoid(self.engine, selected);
        completion.release(self.receiver); self.receiver = c.pi_js_undefined();
        completion.release(self.next_function); self.next_function = c.pi_js_undefined();
        return completion.finishVoid();
    }
    fn closeAbrupt(self: *Iterator, err: anyerror) !void {
        if (self.closed) return err;
        self.closed = true;
        const original = try agent.caught(self.engine, err);
        var s: Scope = .{ .engine = self.engine };
        return owned.finishVoid(&s, closePreservingBody(&s, self.receiver, original));
    }
    fn closePreservingBody(s: *Scope, receiver: c.JSValue, original: c.JSValue) !void {
        _ = try own(s, original);
        closeBody(s, receiver) catch |close_err| {
            const displaced = try agent.caught(s.engine, close_err);
            _ = try own(s, displaced);
        };
        _ = try s.engine.checked(c.JS_Throw(s.engine.context, duplicate(s, original)));
        unreachable;
    }
    fn closeBody(s: *Scope, receiver: c.JSValue) !void {
        const callable = try get(s, receiver, "return");
        if (nullish(callable)) return;
        _ = try call(s, callable, receiver, &.{});
        // With an original Throw completion, a normal return value is ignored.
    }
};
fn acquireIterator(engine: *em.Engine, iterable: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, acquireIteratorBody(&s, iterable));
}
fn acquireIteratorBody(s: *Scope, iterable: c.JSValue) !c.JSValue {
    const callable = try key(s, iterable, try iteratorSymbol(s));
    if (!c.JS_IsFunction(s.engine.context, callable)) return typeError(s, "value is not iterable");
    const receiver = try call(s, callable, iterable, &.{});
    if (!c.JS_IsObject(receiver)) return typeError(s, "not an object");
    return duplicate(s, receiver);
}
