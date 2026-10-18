//! Catalog operations over the canonical SDK guest and root ownership contracts.
pub const em = @import("engine.zig");
pub const c = em.c;
pub const af = @import("native_async_function.zig");
pub const owned = @import("native_sdk_owned_completion.zig");
pub const guest = @import("native_sdk_guest_operation.zig");
pub const Scope = @import("native_models_stream_scope.zig").Scope;
const nf = @import("native_node_function.zig");
pub const Ops = struct {
    s: *Scope,
    pub fn own(o: *Ops, value: c.JSValue) !c.JSValue { return owned.ownRoot(o.s, value); }
    pub fn get(o: *Ops, target: c.JSValue, name: [*:0]const u8) !c.JSValue { return guest.get(o.s, target, name); }
    pub fn at(o: *Ops, target: c.JSValue, position: u32) !c.JSValue { return guest.at(o.s, target, position); }
    pub fn key(o: *Ops, target: c.JSValue, value: c.JSValue) !c.JSValue {
        var boundary: guest.Boundary = .{ .engine = o.s.engine }; try boundary.begin();
        const atom = c.JS_ValueToAtom(o.s.engine.context, value);
        defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(o.s.engine.context, atom);
        try boundary.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
        return guest.getAtom(o.s, target, atom);
    }
    pub fn global(o: *Ops, name: [*:0]const u8) !c.JSValue { return guest.global(o.s, name); }
    pub fn iteratorSymbol(o: *Ops) !c.JSValue {
        var boundary: guest.Boundary = .{ .engine = o.s.engine }; try boundary.begin();
        return boundary.finishValue(o.s, c.JS_GetIteratorSymbol(o.s.engine.context));
    }
    pub fn call(o: *Ops, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue { return guest.call(o.s, function, receiver, args); }
    pub fn invoke(o: *Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return guest.invoke(o.s, receiver, name, args); }
    /// A method expression retires before its caller starts the next Source expression.
    pub fn invokeOwned(o: *Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
        return owned.finishValue(&s, invokeBody(&local, receiver, name, args));
    }
    fn invokeBody(o: *Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        return c.JS_DupValue(o.s.engine.context, try o.invoke(receiver, name, args));
    }
    pub fn globalInvokeOwned(o: *Ops, name: [*:0]const u8, method: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
        return owned.finishValue(&s, globalInvokeBody(&local, name, method, args));
    }
    fn globalInvokeBody(o: *Ops, name: [*:0]const u8, method: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return o.invokeOwned(try o.global(name), method, args); }
    pub fn fieldOwned(o: *Ops, target: c.JSValue, first: [*:0]const u8, second: [*:0]const u8) !c.JSValue {
        var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
        return owned.finishValue(&s, fieldBody(&local, target, first, second));
    }
    fn fieldBody(o: *Ops, target: c.JSValue, first: [*:0]const u8, second: [*:0]const u8) !c.JSValue { return c.JS_DupValue(o.s.engine.context, try o.get(try o.get(target, first), second)); }
    pub fn beforeAllocation(o: *Ops) !u64 { try o.s.engine.checkNativeEntry(); return o.s.engine.native_allocation_generation; }
    pub fn allocation(o: *Ops, value: c.JSValue, generation: u64) !c.JSValue {
        const e = o.s.engine;
        _ = e.nativeCallbackResult(c.pi_js_undefined());
        if (c.JS_HasException(e.context)) {
            const reason = c.JS_GetException(e.context);
            const tag = c.pi_js_native_allocation_error_generation(reason); const distance = tag -% generation;
            if (tag != 0 and distance != 0 and distance <= e.native_allocation_generation -% generation) c.JS_SetUncatchableError(e.context, reason);
            _ = c.JS_Throw(e.context, reason);
            var completion = owned.Completion.initValue(e, @as(anyerror!c.JSValue, error.JavaScriptException));
            if (!c.JS_IsException(value)) completion.release(value);
            return o.own(try completion.finishValue());
        }
        return o.own(try e.checked(value));
    }
    pub fn text(o: *Ops, bytes: []const u8) !c.JSValue { const generation = try o.beforeAllocation(); return o.allocation(c.JS_NewStringLen(o.s.engine.context, bytes.ptr, bytes.len), generation); }
    pub fn object(o: *Ops) !c.JSValue { const generation = try o.beforeAllocation(); return o.allocation(c.JS_NewObject(o.s.engine.context), generation); }
    pub fn cell(o: *Ops) !c.JSValue { const generation = try o.beforeAllocation(); return o.allocation(c.JS_NewObjectProto(o.s.engine.context, c.pi_js_null()), generation); }
    pub fn array(o: *Ops) !c.JSValue { const generation = try o.beforeAllocation(); return o.allocation(c.JS_NewArray(o.s.engine.context), generation); }
    pub fn construct(o: *Ops, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue { return guest.construct(o.s, constructor, args); }
    pub fn has(o: *Ops, target: c.JSValue, name: [*:0]const u8) !bool {
        const e = o.s.engine; const generation = try o.beforeAllocation();
        const atom = c.JS_NewAtom(e.context, name);
        if (atom == c.JS_ATOM_NULL) { _ = try o.allocation(c.JS_EXCEPTION, generation); unreachable; }
        defer c.JS_FreeAtom(e.context, atom);
        var boundary: guest.Boundary = .{ .engine = e }; try boundary.begin();
        const result = c.JS_HasProperty(e.context, target, atom); try boundary.finishStatus(result);
        return result != 0;
    }
    pub fn callback(o: *Ops, name: [*:0]const u8, length: c_int, function: nf.Callback, roots: []const c.JSValue, arrow: bool) !c.JSValue {
        return o.own(try (if (arrow) nf.createArrow(o.s.engine, name, length, function, roots) else nf.create(o.s.engine, name, length, function, roots)));
    }
    pub fn put(o: *Ops, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { return guest.put(o.s, target, name, value); }
    pub fn index(o: *Ops, target: c.JSValue, position: u32, value: c.JSValue) !void { return guest.index(o.s, target, position, value); }
    pub fn binary(o: *Ops, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue { return guest.binary(o.s, operation, left, right); }
    pub fn concat(o: *Ops, left: c.JSValue, right: c.JSValue) !c.JSValue { return o.binary(@intFromEnum(@import("native_image_arithmetic.zig").Operation.add), left, right); }
    pub fn compare(o: *Ops, operation: @import("native_image_arithmetic.zig").Operation, left: c.JSValue, right: c.JSValue) !bool { return o.truthy(try o.binary(@intFromEnum(operation), left, right)); }
    pub fn stringify(o: *Ops, value: c.JSValue) !c.JSValue { return guest.stringify(o.s, value); }
    pub fn truthy(o: *Ops, value: c.JSValue) bool { return c.JS_ToBool(o.s.engine.context, value) == 1; }
    pub fn equal(o: *Ops, a: c.JSValue, b: c.JSValue) bool { return c.JS_IsStrictEqual(o.s.engine.context, a, b); }
    pub fn optional(o: *Ops, value: c.JSValue, name: [*:0]const u8) !c.JSValue { return if (nullish(value)) c.pi_js_undefined() else o.get(value, name); }
    pub const FieldTest = enum { undefined_value, string_value, truthy_value };
    pub fn fieldTest(o: *Ops, target: c.JSValue, name: [*:0]const u8, comptime kind: FieldTest) !bool {
        var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
        return o.truthy(try owned.finishValue(&s, fieldTestBody(&local, target, name, kind)));
    }
    fn fieldTestBody(o: *Ops, target: c.JSValue, name: [*:0]const u8, comptime kind: FieldTest) !c.JSValue {
        const value = try o.get(target, name);
        const passed = switch (kind) { .undefined_value => c.JS_IsUndefined(value), .string_value => c.JS_IsString(value), .truthy_value => o.truthy(value) };
        return c.pi_js_bool(o.s.engine.context, @intFromBool(passed));
    }
    pub fn isArray(o: *Ops, value: c.JSValue) !bool {
        var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
        return o.truthy(try owned.finishValue(&s, isArrayBody(&local, value)));
    }
    fn isArrayBody(o: *Ops, value: c.JSValue) !c.JSValue {
        return c.pi_js_bool(o.s.engine.context, @intFromBool(o.truthy(try o.invoke(try o.global("Array"), "isArray", &.{value}))));
    }
    pub fn typeError(o: *Ops, message: [*:0]const u8) anyerror {
        const generation = o.beforeAllocation() catch |err| return err;
        _ = o.allocation(c.JS_ThrowTypeError(o.s.engine.context, "%s", message), generation) catch |err| return err;
        unreachable;
    }
};
pub fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
