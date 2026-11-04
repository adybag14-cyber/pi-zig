//! SDK guest-capable operations. A failed guest call's diagnostic is ordinary
//! DATA; private tags, flags and generation spans never establish its cause.
//! The caller records its final outcome before retiring its Scope (C435).
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const owned = @import("native_sdk_owned_completion.zig");
pub const c = em.c;

/// Initialize INACTIVE at the caller's stable address, then begin BEFORE the
/// raw operation. Never copy/move an active record or hold it across Await.
/// finishValue consumes the owned output and returns a Scope-rooted BORROW.
/// The enclosing real native invocation must span later Scope retirement.
pub const Boundary = struct {
    engine: *em.Engine,
    invocation: em.Engine.NativeInvocation = .{},
    active: bool = false,

    pub fn begin(self: *Boundary) !void {
        std.debug.assert(!self.active);
        self.engine.native_exception_diagnostics_suppressed += 1;
        self.engine.enterNativeInvocation(&self.invocation);
        self.active = true;
        // The stable owner must exist before entry can capture an ordinary
        // diagnostic or record a private event. Failed begin pops itself:
        // callers using "try begin()" do not owe a second finish.
        self.engine.checkNativeEntry() catch |err| return self.finishError(err);
    }
    fn finishError(self: *Boundary, err: anyerror) anyerror {
        std.debug.assert(self.active);
        self.active = false;
        defer self.engine.native_exception_diagnostics_suppressed -= 1;
        const result = self.engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined());
        if (self.invocation.terminated) return error.ExecutionTerminated;
        if (c.JS_IsException(result) and err != error.OutOfMemory and err != error.ExecutionTerminated)
            return error.JavaScriptException;
        return err;
    }
    fn close(self: *Boundary, result: c.JSValue) anyerror!c.JSValue {
        std.debug.assert(self.active);
        // Ordinary diagnostics are captured only while this owner is live.
        // Scope owns its result before this sentinel closes the boundary.
        const checked = self.engine.checked(result) catch |err| return self.failure(err);
        self.active = false;
        defer self.engine.native_exception_diagnostics_suppressed -= 1;
        const finished = self.engine.leaveNativeInvocation(&self.invocation, checked);
        if (self.invocation.terminated) return error.ExecutionTerminated;
        if (c.JS_IsException(finished)) return error.JavaScriptException;
        return finished;
    }
    fn failure(self: *Boundary, err: anyerror) anyerror!c.JSValue {
        if (err == error.OutOfMemory) {
            _ = self.engine.throwNativeOutOfMemoryFatal();
        } else if (err != error.JavaScriptException and err != error.ExecutionTerminated) {
            _ = sdk.fail(self.engine, err);
        }
        if (err != error.ExecutionTerminated) {
            self.engine.checkNativeEntry() catch |current| return self.finishError(
                if (err == error.OutOfMemory) err else current);
        }
        // No checked(), diagnostic capture or fresh-request poll after pop.
        return self.finishError(err);
    }
    pub fn finishValue(self: *Boundary, scope: anytype, result: anyerror!c.JSValue) anyerror!c.JSValue {
        std.debug.assert(scope.engine == self.engine);
        const raw = result catch |err| return self.failure(err);
        const checked = self.engine.checked(raw) catch |err| return self.failure(err);
        const rooted = owned.ownRoot(scope, checked) catch |err| return self.failure(err);
        _ = try self.close(c.pi_js_undefined());
        return rooted;
    }
    pub fn finishVoid(self: *Boundary, result: anyerror!void) anyerror!void {
        result catch |err| { _ = try self.failure(err); unreachable; };
        _ = try self.close(c.pi_js_undefined());
    }
    pub fn finishStatus(self: *Boundary, status: c_int) anyerror!void {
        if (status < 0) {
            // checked() distinguishes a real actual event from a broken raw
            // callback contract, still under the stable diagnostic owner.
            _ = self.engine.checked(c.pi_js_exception()) catch |err| return self.finishVoid(err);
            unreachable;
        }
        return self.finishVoid({});
    }
};

pub fn get(s: anytype, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, native_guest_0: { s.engine.checkNativeEntry() catch |err| break :native_guest_0 err; break :native_guest_0 c.JS_GetPropertyStr(s.engine.context, target, name); });
}
pub fn getAtom(s: anytype, target: c.JSValue, atom: c.JSAtom) !c.JSValue {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, native_guest_0: { s.engine.checkNativeEntry() catch |err| break :native_guest_0 err; break :native_guest_0 c.JS_GetProperty(s.engine.context, target, atom); });
}
pub fn at(s: anytype, target: c.JSValue, position: u32) !c.JSValue {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, native_guest_0: { s.engine.checkNativeEntry() catch |err| break :native_guest_0 err; break :native_guest_0 c.JS_GetPropertyUint32(s.engine.context, target, position); });
}
pub fn global(s: anytype, name: [*:0]const u8) !c.JSValue {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    const object = try boundary.finishValue(s, c.JS_GetGlobalObject(s.engine.context));
    return get(s, object, name);
}
pub fn call(s: anytype, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, native_guest_0: { s.engine.checkNativeEntry() catch |err| break :native_guest_0 err; break :native_guest_0 c.JS_Call(s.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)); });
}
pub fn invoke(s: anytype, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return call(s, try get(s, receiver, name), receiver, args);
}
pub fn construct(s: anytype, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, native_guest_0: { s.engine.checkNativeEntry() catch |err| break :native_guest_0 err; break :native_guest_0 c.JS_CallConstructor(s.engine.context, constructor, @intCast(args.len), @constCast(args.ptr)); });
}
/// Source assignment (distinct from an own C_W_E data definition).
pub fn set(s: anytype, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishStatus(c.JS_SetPropertyStr(s.engine.context, target, name, c.JS_DupValue(s.engine.context, value)));
}
pub fn put(s: anytype, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishStatus(c.JS_DefinePropertyValueStr(s.engine.context, target, name, c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E));
}
pub fn index(s: anytype, target: c.JSValue, position: u32, value: c.JSValue) !void {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishStatus(c.JS_DefinePropertyValueUint32(s.engine.context, target, position, c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E));
}
pub fn binary(s: anytype, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, native_guest_0: { s.engine.checkNativeEntry() catch |err| break :native_guest_0 err; break :native_guest_0 c.JS_PiBinaryOperator(s.engine.context, operation, left, right); });
}
pub fn stringify(s: anytype, value: c.JSValue) !c.JSValue {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, native_guest_0: { s.engine.checkNativeEntry() catch |err| break :native_guest_0 err; break :native_guest_0 c.JS_ToString(s.engine.context, value); });
}
pub fn toObject(s: anytype, value: c.JSValue) !c.JSValue {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, native_guest_0: { s.engine.checkNativeEntry() catch |err| break :native_guest_0 err; break :native_guest_0 c.JS_ToObject(s.engine.context, value); });
}
pub fn increment(s: anytype, value: c.JSValue) !c.JSValue {
    var boundary: Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, native_guest_0: { s.engine.checkNativeEntry() catch |err| break :native_guest_0 err; break :native_guest_0 c.JS_PiIncrement(s.engine.context, value); });
}
