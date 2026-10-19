//! Actual QuickJS private-slot controls for the selected Node binding Set.
//! No Node process, Source evaluation in production or substitute marker map.
const std = @import("std");
const c = @cImport({
    @cInclude("quickjs.h");
    @cInclude("engine_abi.h");
});

const Probe = struct { retired: usize = 0 };
fn retire(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    probe.retired += 1;
}

const Fixture = struct {
    runtime: *c.JSRuntime,
    context: *c.JSContext,
    key: c.JSValue,
    class_id: c.JSClassID,
    fn init() !Fixture {
        const runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer c.JS_FreeRuntime(runtime);
        c.JS_SetMaxStackSize(runtime, 1024 * 1024);
        const context = c.JS_NewContext(runtime) orelse return error.OutOfMemory;
        errdefer c.JS_FreeContext(context);
        const key = c.JS_NewPrivateSymbol(context, "node:transfer_mode");
        if (c.JS_IsException(key)) return error.PrivateKeyCreationFailed;
        errdefer c.JS_FreeValue(context, key);
        var id: c.JSClassID = 0;
        _ = c.JS_NewClassID(runtime, &id);
        const definition: c.JSClassDef = .{ .class_name = "Private slot retained value", .finalizer = retire };
        if (c.JS_NewClass(runtime, id, &definition) < 0) return error.OutOfMemory;
        return .{ .runtime = runtime, .context = context, .key = key, .class_id = id };
    }
    fn deinit(self: *Fixture) void {
        c.JS_FreeValue(self.context, self.key);
        c.JS_FreeContext(self.context);
        c.JS_FreeRuntime(self.runtime);
    }
    fn checked(_: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value)) return error.UnexpectedPrivateSlotException;
        return value;
    }
    fn eval(self: *Fixture, source: []const u8) !c.JSValue {
        const value = c.JS_Eval(self.context, source.ptr, source.len, "native-private-slot.js", c.JS_EVAL_TYPE_GLOBAL);
        return self.checked(value);
    }
    fn run(self: *Fixture, source: []const u8) !void {
        const value = try self.eval(source);
        c.JS_FreeValue(self.context, value);
        try std.testing.expect(!c.JS_HasException(self.context));
    }
    fn global(self: *Fixture, name: [:0]const u8) !c.JSValue {
        const global = try self.checked(c.JS_GetGlobalObject(self.context));
        defer c.JS_FreeValue(self.context, global);
        return self.checked(c.JS_GetPropertyStr(self.context, global, name));
    }
    fn publish(self: *Fixture, name: [:0]const u8, value: c.JSValue) !void {
        const global = try self.checked(c.JS_GetGlobalObject(self.context));
        defer c.JS_FreeValue(self.context, global);
        if (c.JS_SetPropertyStr(self.context, global, name, c.JS_DupValue(self.context, value)) < 0)
            return error.PrivateSlotPublishFailed;
    }
    fn sentinel(self: *Fixture, probe: *Probe) !c.JSValue {
        const result = try self.checked(c.JS_NewObjectClass(self.context, self.class_id));
        _ = c.JS_SetOpaque(result, probe);
        return result;
    }
    fn set(self: *Fixture, receiver: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
        // This helper, like the actual C entry, consumes value on every path.
        const result = c.JS_PiSetPrivateProperty(self.context, receiver, key, value);
        try std.testing.expectEqual(@as(c_int, 1), result);
        try std.testing.expect(!c.JS_HasException(self.context));
    }
    fn own(self: *Fixture, receiver: c.JSValue, key: c.JSValue) !?c.JSPropertyDescriptor {
        const atom = c.JS_ValueToAtom(self.context, key);
        if (atom == c.JS_ATOM_NULL) return error.PrivateSlotAtomFailed;
        defer c.JS_FreeAtom(self.context, atom);
        var descriptor: c.JSPropertyDescriptor = undefined;
        const result = c.JS_GetOwnProperty(self.context, &descriptor, receiver, atom);
        if (result < 0) return error.PrivateSlotDescriptorFailed;
        return if (result == 0) null else descriptor;
    }
    fn freeDescriptor(self: *Fixture, descriptor: c.JSPropertyDescriptor) void {
        c.JS_FreeValue(self.context, descriptor.value);
        c.JS_FreeValue(self.context, descriptor.getter);
        c.JS_FreeValue(self.context, descriptor.setter);
    }
    fn expectOwnInt(self: *Fixture, receiver: c.JSValue, key: c.JSValue, expected: i32) !void {
        const descriptor = (try self.own(receiver, key)) orelse return error.ActualOwnPrivateSlotRequired;
        defer self.freeDescriptor(descriptor);
        var value: i32 = 0;
        if (c.JS_ToInt32(self.context, &value, descriptor.value) < 0) return error.PrivateSlotValueFailed;
        try std.testing.expectEqual(expected, value);
        try std.testing.expectEqual(@as(c_int, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE),
            descriptor.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_GETSET));
    }
    fn define(self: *Fixture, receiver: c.JSValue, key: c.JSValue, value: c.JSValue, setter: c.JSValue, flags: c_int) !void {
        const atom = c.JS_ValueToAtom(self.context, key);
        if (atom == c.JS_ATOM_NULL) return error.PrivateSlotAtomFailed;
        defer c.JS_FreeAtom(self.context, atom);
        const result = c.JS_DefineProperty(self.context, receiver, atom, value, c.pi_js_undefined(), setter, flags | c.JS_PROP_THROW | c.JS_PROP_NO_EXOTIC);
        try std.testing.expectEqual(@as(c_int, 1), result);
    }
    fn takeReason(self: *Fixture) !c.JSValue {
        try std.testing.expect(c.JS_HasException(self.context));
        const reason = c.JS_GetException(self.context);
        try std.testing.expect(!c.JS_HasException(self.context));
        return reason;
    }
};

test "VM private property creates unique hidden writable configurable own slots" {
    var f = try Fixture.init(); defer f.deinit();
    const object = try f.checked(c.JS_NewObject(f.context)); defer c.JS_FreeValue(f.context, object);
    const same_description = try f.checked(c.JS_NewPrivateSymbol(f.context, "node:transfer_mode")); defer c.JS_FreeValue(f.context, same_description);
    try std.testing.expect(!c.JS_IsStrictEqual(f.context, f.key, same_description));
    try f.set(object, f.key, c.JS_NewInt32(f.context, 1));
    try f.set(object, same_description, c.JS_NewInt32(f.context, 2));
    try f.expectOwnInt(object, f.key, 1); try f.expectOwnInt(object, same_description, 2);
    try f.publish("slot", object);
    try f.run("if(Reflect.ownKeys(slot).length||Object.getOwnPropertyNames(slot).length||Object.getOwnPropertySymbols(slot).length||Object.keys(slot).length)throw Error('private key leaked');slot[Symbol.for('public')]=3;if(Reflect.ownKeys(slot).length!==1||Object.getOwnPropertySymbols(slot)[0]!==Symbol.for('public'))throw Error('public symbol changed');");
}

test "VM private property ignores an inherited setter and read only prototype slot" {
    var f = try Fixture.init(); defer f.deinit();
    const prototype = try f.checked(c.JS_NewObject(f.context)); defer c.JS_FreeValue(f.context, prototype);
    const setter = try f.eval("(globalThis.prototypeVisits=0,function(){prototypeVisits++;throw Error('inherited setter reached')})"); defer c.JS_FreeValue(f.context, setter);
    try f.define(prototype, f.key, c.pi_js_undefined(), setter, c.JS_PROP_HAS_SET | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_CONFIGURABLE);
    const child = try f.checked(c.JS_NewObjectProto(f.context, prototype)); defer c.JS_FreeValue(f.context, child);
    try f.set(child, f.key, c.JS_NewInt32(f.context, 7));
    try f.expectOwnInt(child, f.key, 7);
    try f.run("if(prototypeVisits!==0)throw Error('prototype visited');");
    const second = try f.checked(c.JS_NewPrivateSymbol(f.context, "read-only")); defer c.JS_FreeValue(f.context, second);
    try f.define(prototype, second, c.JS_NewInt32(f.context, 11), c.pi_js_undefined(),
        c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE | c.JS_PROP_HAS_CONFIGURABLE);
    try f.set(child, second, c.JS_NewInt32(f.context, 12));
    try f.expectOwnInt(child, second, 12);
    const original = (try f.own(prototype, second)).?; defer f.freeDescriptor(original);
    var number: i32 = 0; try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.context, &number, original.value));
    try std.testing.expectEqual(@as(i32, 11), number);
}

test "VM private property extends frozen ordinary objects without changing public extensibility" {
    var f = try Fixture.init(); defer f.deinit();
    const object = try f.eval("Object.freeze({publicValue:17})"); defer c.JS_FreeValue(f.context, object);
    try f.set(object, f.key, c.JS_NewInt32(f.context, 1));
    try f.expectOwnInt(object, f.key, 1);
    try f.publish("slot", object);
    try f.run("if(Object.isExtensible(slot)||!Object.isFrozen(slot)||Reflect.ownKeys(slot).join(',')!=='publicValue')throw Error('public frozen shape changed');");
    try f.set(object, f.key, c.JS_NewInt32(f.context, 2));
    try f.expectOwnInt(object, f.key, 2);
}

test "VM private property stores on the real proxy wrapper and survives revocation without traps" {
    var f = try Fixture.init(); defer f.deinit();
    const proxy = try f.eval("globalThis.target={};globalThis.trapVisits=0;globalThis.pair=Proxy.revocable(target,new Proxy({},{get(){trapVisits++;throw Error('proxy trap lookup reached')}}));pair.proxy;");
    defer c.JS_FreeValue(f.context, proxy);
    const target = try f.global("target"); defer c.JS_FreeValue(f.context, target);
    try f.set(proxy, f.key, c.JS_NewInt32(f.context, 3));
    try f.expectOwnInt(proxy, f.key, 3);
    try std.testing.expect((try f.own(target, f.key)) == null);
    try f.run("if(trapVisits!==0)throw Error('proxy trap reached');pair.revoke();");
    try f.set(proxy, f.key, c.JS_NewInt32(f.context, 4));
    const fresh = try f.checked(c.JS_NewPrivateSymbol(f.context, "after-revoke")); defer c.JS_FreeValue(f.context, fresh);
    try f.set(proxy, fresh, c.JS_NewInt32(f.context, 5));
    try f.expectOwnInt(proxy, f.key, 4); try f.expectOwnInt(proxy, fresh, 5);
    try std.testing.expect((try f.own(target, fresh)) == null);
    try f.run("if(trapVisits!==0)throw Error('revoked proxy trap reached');");
}

test "VM private property replacement retires its previous actual value exactly once" {
    var f = try Fixture.init(); defer f.deinit();
    var old: Probe = .{}; var current: Probe = .{};
    var object = try f.checked(c.JS_NewObject(f.context)); defer c.JS_FreeValue(f.context, object);
    try f.set(object, f.key, try f.sentinel(&old));
    try std.testing.expectEqual(@as(usize, 0), old.retired);
    try f.set(object, f.key, try f.sentinel(&current));
    try std.testing.expectEqual(@as(usize, 1), old.retired);
    try std.testing.expectEqual(@as(usize, 0), current.retired);
    c.JS_RunGC(f.runtime);
    try std.testing.expectEqual(@as(usize, 1), old.retired);
    c.JS_FreeValue(f.context, object); object = c.pi_js_undefined();
    try std.testing.expectEqual(@as(usize, 1), current.retired);
    c.JS_RunGC(f.runtime);
    try std.testing.expectEqual(@as(usize, 1), current.retired);
}

test "VM private property invalid receivers and keys consume values without coercion" {
    var f = try Fixture.init(); defer f.deinit();
    const object = try f.checked(c.JS_NewObject(f.context)); defer c.JS_FreeValue(f.context, object);
    const ordinary = try f.checked(c.JS_NewSymbol(f.context, "node:transfer_mode", false)); defer c.JS_FreeValue(f.context, ordinary);
    const coercible = try f.eval("globalThis.keyVisits=0;({get [Symbol.toPrimitive](){keyVisits++;throw Error('key coerced')}})");
    defer c.JS_FreeValue(f.context, coercible);
    const receivers = [_]c.JSValue{ c.pi_js_null(), c.JS_NewInt32(f.context, 1), object, object };
    const keys = [_]c.JSValue{ f.key, f.key, ordinary, coercible };
    for (receivers, keys) |receiver, key| {
        var probe: Probe = .{};
        const result = c.JS_PiSetPrivateProperty(f.context, receiver, key, try f.sentinel(&probe));
        try std.testing.expectEqual(@as(c_int, -1), result);
        try std.testing.expectEqual(@as(usize, 1), probe.retired);
        const reason = try f.takeReason(); defer c.JS_FreeValue(f.context, reason);
        try std.testing.expect(c.JS_IsError(reason));
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
    }
    try f.run("if(keyVisits!==0)throw Error('key conversion happened');");
    try std.testing.expect((try f.own(object, f.key)) == null);
}

test "VM private property respects an existing own read only descriptor and keeps the old value" {
    var f = try Fixture.init(); defer f.deinit();
    const object = try f.checked(c.JS_NewObject(f.context)); defer c.JS_FreeValue(f.context, object);
    try f.define(object, f.key, c.JS_NewInt32(f.context, 23), c.pi_js_undefined(),
        c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE | c.JS_PROP_HAS_CONFIGURABLE);
    var probe: Probe = .{};
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiSetPrivateProperty(f.context, object, f.key, try f.sentinel(&probe)));
    try std.testing.expectEqual(@as(usize, 1), probe.retired);
    const reason = try f.takeReason(); defer c.JS_FreeValue(f.context, reason);
    try std.testing.expect(c.JS_IsError(reason));
    const descriptor = (try f.own(object, f.key)).?; defer f.freeDescriptor(descriptor);
    var number: i32 = 0; try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.context, &number, descriptor.value));
    try std.testing.expectEqual(@as(i32, 23), number);
    try std.testing.expectEqual(@as(c_int, 0), descriptor.flags & c.JS_PROP_WRITABLE);
}

test "VM private property own setter receives the exact receiver value and ordinary throw" {
    var f = try Fixture.init(); defer f.deinit();
    const object = try f.checked(c.JS_NewObject(f.context)); defer c.JS_FreeValue(f.context, object);
    const reason = try f.checked(c.JS_NewObject(f.context)); defer c.JS_FreeValue(f.context, reason);
    try f.publish("slot", object); try f.publish("setterReason", reason);
    const setter = try f.eval("globalThis.setterVisits=0;(function(value){if(this!==slot||value!==41)throw Error('setter operands');setterVisits++;throw setterReason;})");
    defer c.JS_FreeValue(f.context, setter);
    try f.define(object, f.key, c.pi_js_undefined(), setter, c.JS_PROP_HAS_SET | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_CONFIGURABLE);
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiSetPrivateProperty(f.context, object, f.key, c.JS_NewInt32(f.context, 41)));
    const caught = try f.takeReason(); defer c.JS_FreeValue(f.context, caught);
    try std.testing.expect(c.JS_IsStrictEqual(f.context, reason, caught));
    try std.testing.expect(!c.JS_IsUncatchableError(caught));
    try f.run("if(setterVisits!==1)throw Error('setter replay');");
}

test "VM private property allocation failure consumes the new value and publishes no slot" {
    var f = try Fixture.init(); defer f.deinit();
    const object = try f.checked(c.JS_NewObject(f.context)); defer c.JS_FreeValue(f.context, object);
    var probe: Probe = .{};
    const value = try f.sentinel(&probe);
    c.JS_SetMemoryLimit(f.runtime, 1);
    const result = c.JS_PiSetPrivateProperty(f.context, object, f.key, value);
    c.JS_SetMemoryLimit(f.runtime, std.math.maxInt(usize));
    try std.testing.expectEqual(@as(c_int, -1), result);
    try std.testing.expectEqual(@as(usize, 1), probe.retired);
    const reason = try f.takeReason(); defer c.JS_FreeValue(f.context, reason);
    try std.testing.expect(c.JS_IsNull(reason));
    try std.testing.expect((try f.own(object, f.key)) == null);
}
