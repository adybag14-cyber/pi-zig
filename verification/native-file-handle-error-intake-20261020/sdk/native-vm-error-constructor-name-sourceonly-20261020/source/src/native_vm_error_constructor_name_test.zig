//! Source-only controls for the bounded native Error constructor-name owner.
//! These exercise actual VM storage and JS effects. Unsupported results remain
//! dependencies of the production Node hook-exception policy, which is absent.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
const Status = c.JSPiNativeErrorConstructorNameStatus;
const Probe = struct {
    retired: usize = 0,
    exotic_calls: usize = 0,
};
fn probeOf(value: c.JSValue) ?*Probe {
    const pointer = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return null;
    return @ptrCast(@alignCast(pointer));
}
fn markerFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe = probeOf(value) orelse return;
    _ = c.JS_SetOpaque(value, null);
    probe.retired += 1;
}
fn forbiddenDescriptor(context: ?*c.JSContext, _: [*c]c.JSPropertyDescriptor,
    value: c.JSValue, _: c.JSAtom) callconv(.c) c_int
{
    const probe = probeOf(value) orelse return -1;
    probe.exotic_calls += 1;
    _ = c.JS_ThrowTypeError(context, "Constructor-name query invoked native exotic storage");
    return -1;
}
const exotic_methods: c.JSClassExoticMethods = .{ .get_own_property = forbiddenDescriptor };
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    probe: Probe = .{},
    marker_class: c.JSClassID = 0,
    exotic_class: c.JSClassID = 0,

    fn init(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer self.deinit();
        c.JS_SetMaxStackSize(self.runtime.?, 1024 * 1024);
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
    }
    fn deinit(self: *Fixture) void {
        if (self.runtime) |runtime| c.JS_SetMemoryLimit(runtime, 0);
        if (self.context) |context| {
            _ = c.JS_PiCheckExecutionTermination(context);
            c.JS_PiCancelExecutionTermination(self.runtime.?);
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            self.context = null;
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| {
            self.runtime = null;
            c.JS_FreeRuntime(runtime);
        }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, value);
            return error.NativeConstructorControlFailed;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "native-error-constructor-name.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    }
    fn publish(self: *Fixture, key: [*:0]const u8, value: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValueStr(self.context.?,
            global_object, key, c.JS_DupValue(self.context.?, value), c.JS_PROP_C_W_E));
    }
    fn name(self: *Fixture, value: c.JSValue) !c.JSValue {
        var owned = c.pi_js_undefined();
        errdefer c.JS_FreeValue(self.context.?, owned);
        try std.testing.expectEqual(@as(Status, c.JS_PI_ERROR_CONSTRUCTOR_NAME_FOUND),
            c.JS_PiGetNativeErrorConstructorName(self.context.?, value, &owned));
        try std.testing.expect(c.JS_IsString(owned));
        return owned;
    }
    fn expectText(self: *Fixture, value: c.JSValue, expected: []const u8) !void {
        try std.testing.expect(c.JS_IsString(value));
        const text = c.JS_ToCString(self.context.?, value) orelse return error.NativeNameTextFailed;
        defer c.JS_FreeCString(self.context.?, text);
        try std.testing.expectEqualStrings(expected, std.mem.span(text));
    }
    fn expectName(self: *Fixture, value: c.JSValue, expected: []const u8) !void {
        const owned = try self.name(value);
        defer c.JS_FreeValue(self.context.?, owned);
        try self.expectText(owned, expected);
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn expectStatus(self: *Fixture, value: c.JSValue, expected: Status) !void {
        // Null is not an owned heap value; every non-FOUND result must replace it.
        var owned = c.pi_js_null();
        defer c.JS_FreeValue(self.context.?, owned);
        try std.testing.expectEqual(expected,
            c.JS_PiGetNativeErrorConstructorName(self.context.?, value, &owned));
        try std.testing.expect(c.JS_IsUndefined(owned));
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn expectBool(self: *Fixture, source: [:0]const u8) !void {
        const result = try self.eval(source);
        defer c.JS_FreeValue(self.context.?, result);
        try std.testing.expect(c.JS_IsBool(result));
        try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(self.context.?, result));
    }
    fn expectNoOwnProperties(self: *Fixture, value: c.JSValue) !void {
        var entries: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        const status = c.JS_GetOwnPropertyNames(self.context.?, &entries, &count, value,
            c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK);
        defer if (entries != null) {
            for (entries[0..count]) |entry| c.JS_FreeAtom(self.context.?, entry.atom);
            c.js_free(self.context.?, @ptrCast(entries));
        };
        try std.testing.expectEqual(@as(c_int, 0), status);
        try std.testing.expectEqual(@as(u32, 0), count);
    }
    fn deleteOwn(self: *Fixture, value: c.JSValue, key: [*:0]const u8) !void {
        const atom = c.JS_NewAtom(self.context.?, key);
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(self.context.?, atom);
        try std.testing.expectEqual(@as(c_int, 1),
            c.JS_DeleteProperty(self.context.?, value, atom, c.JS_PROP_THROW));
    }
    fn newMarker(self: *Fixture) !c.JSValue {
        if (self.marker_class == 0) {
            _ = c.JS_NewClassID(self.runtime.?, &self.marker_class);
            const definition: c.JSClassDef = .{
                .class_name = "Constructor provenance lifetime witness", .finalizer = markerFinalizer,
            };
            try std.testing.expectEqual(@as(c_int, 0),
                c.JS_NewClass(self.runtime.?, self.marker_class, &definition));
        }
        const value = try self.checked(c.JS_NewObjectProtoClass(self.context.?, c.pi_js_null(), self.marker_class));
        _ = c.JS_SetOpaque(value, &self.probe);
        return value;
    }
    fn newExotic(self: *Fixture) !c.JSValue {
        if (self.exotic_class == 0) {
            _ = c.JS_NewClassID(self.runtime.?, &self.exotic_class);
            const definition: c.JSClassDef = .{
                .class_name = "Constructor provenance forbidden descriptor",
                .exotic = @constCast(&exotic_methods),
            };
            try std.testing.expectEqual(@as(c_int, 0),
                c.JS_NewClass(self.runtime.?, self.exotic_class, &definition));
        }
        const value = try self.checked(c.JS_NewObjectProtoClass(self.context.?, c.pi_js_null(), self.exotic_class));
        _ = c.JS_SetOpaque(value, &self.probe);
        return value;
    }
};

test "VM native Error constructor intrinsic families retain their native initial names" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const cases = [_]struct { expression: [:0]const u8, expected: []const u8 }{
        .{ .expression = "new Error('a')", .expected = "Error" },
        .{ .expression = "new EvalError('a')", .expected = "EvalError" },
        .{ .expression = "new RangeError('a')", .expected = "RangeError" },
        .{ .expression = "new ReferenceError('a')", .expected = "ReferenceError" },
        .{ .expression = "new SyntaxError('a')", .expected = "SyntaxError" },
        .{ .expression = "new TypeError('a')", .expected = "TypeError" },
        .{ .expression = "new URIError('a')", .expected = "URIError" },
        .{ .expression = "new AggregateError([], 'a')", .expected = "AggregateError" },
        .{ .expression = "new SuppressedError(1, 2, 'a')", .expected = "SuppressedError" },
        .{ .expression = "Error('a')", .expected = "Error" },
        .{ .expression = "RangeError('a')", .expected = "RangeError" },
        .{ .expression = "AggregateError([], 'a')", .expected = "AggregateError" },
    };
    for (cases) |item| {
        const value = try f.eval(item.expression); defer c.JS_FreeValue(f.context.?, value);
        try f.expectName(value, item.expected);
    }
}

test "VM native Error constructor direct native creation and throws record real origins" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const plain = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, plain);
    const range = try f.checked(c.JS_NewRangeError(f.context.?, "direct range")); defer c.JS_FreeValue(f.context.?, range);
    try f.expectName(plain, "Error");
    try f.expectName(range, "RangeError");
    try std.testing.expect(c.JS_IsException(c.JS_ThrowRangeError(f.context.?, "thrown range")));
    try std.testing.expect(c.JS_HasException(f.context.?));
    const actual = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, actual);
    try f.expectName(actual, "RangeError");
}

test "VM native Error constructor real VM stack exhaustion retains RangeError provenance" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const function = try f.eval("(function(){function recurse(){return 1+recurse();}try{recurse();}catch(reason){return reason;}})");
    defer c.JS_FreeValue(f.context.?, function);
    c.JS_SetMaxStackSize(f.runtime.?, 64 * 1024);
    const actual = try f.checked(c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null));
    defer c.JS_FreeValue(f.context.?, actual);
    try f.expectName(actual, "RangeError");
    const message = try f.checked(c.JS_GetPropertyStr(f.context.?, actual, "message"));
    defer c.JS_FreeValue(f.context.?, message);
    try f.expectText(message, "Maximum call stack size exceeded");
}

test "VM native Error constructor public function and Error names do not replace provenance" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {globalThis.hits=0;const fail=()=>{hits++;throw 17;};" ++
        "const e=new RangeError('a');Object.defineProperty(RangeError,'name',{get:fail});" ++
        "Object.defineProperties(e,{name:{get:fail},constructor:{get:fail}});" ++
        "e[Symbol.toStringTag]='TypeError';globalThis.second=new RangeError('b');return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.expectName(value, "RangeError");
    const second = try f.eval("second"); defer c.JS_FreeValue(f.context.?, second);
    try f.expectName(second, "RangeError");
    try f.expectBool("hits===0");
}

test "VM native Error constructor public replacement cannot redirect native intrinsic factories" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.expectBool(
        "(() => {Object.defineProperty(RangeError,'name',{value:'ChangedPublicName',configurable:true});" ++
        "RangeError.prototype.constructor=TypeError;globalThis.RangeError=TypeError;return true;})()");
    c.JS_RunGC(f.runtime.?);
    try f.expectBool("RangeError===TypeError");
    const native = try f.checked(c.JS_NewRangeError(f.context.?, "original intrinsic"));
    defer c.JS_FreeValue(f.context.?, native);
    try f.expectName(native, "RangeError");
    const public = try f.eval("new RangeError('public replacement')");
    defer c.JS_FreeValue(f.context.?, public);
    try f.expectName(public, "TypeError");
}

test "VM native Error constructor changing an Error prototype preserves base provenance" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {globalThis.hits=0;const e=new RangeError('a');" ++
        "const p={get constructor(){hits++;throw 1;},get [Symbol.toStringTag](){hits++;throw 2;}};" ++
        "Object.setPrototypeOf(e,p);return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.expectName(value, "RangeError");
    try f.expectBool("hits===0");
}

test "VM native Error constructor new inheritors suppress fast provenance with real prototype admission" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {const e=new RangeError('a');e[Symbol.toStringTag]='PromotedRange';" ++
        "globalThis.descendant=Object.create(e);return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.publish("selected", value);
    try f.expectBool("Object.getPrototypeOf(descendant)===selected");
    try f.expectName(value, "PromotedRange");
    // The original prototype-map restriction is sticky after the child retires.
    try f.expectBool("delete globalThis.descendant");
    c.JS_RunGC(f.runtime.?);
    try f.expectName(value, "PromotedRange");
}

test "VM native Error constructor explicit prototype admission uses the same original fallback" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {const e=new RangeError('a');e[Symbol.toStringTag]='ExplicitPrototype';" ++
        "globalThis.descendant={};Object.setPrototypeOf(descendant,e);return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.expectName(value, "ExplicitPrototype");
}

test "VM native Error constructor inherited data tag precedes constructor at the same level" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {const e=new RangeError('a');const p={[Symbol.toStringTag]:'InheritedTag',constructor:TypeError};" ++
        "Object.setPrototypeOf(e,p);Object.create(e);return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.expectName(value, "InheritedTag");
}

test "VM native Error constructor receiver constructor and accessor tag are never invoked" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {globalThis.hits=0;const e=new RangeError('a');" ++
        "Object.defineProperty(e,Symbol.toStringTag,{get(){hits++;throw 1;}});" ++
        "Object.defineProperty(e,'constructor',{get(){hits++;throw 2;}});" ++
        "Object.setPrototypeOf(e,{constructor:TypeError});Object.create(e);return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.expectName(value, "TypeError");
    try f.expectBool("hits===0");
}

test "VM native Error constructor prototype accessors and mutable builtin name are skipped" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {globalThis.hits=0;const fail=()=>{hits++;throw 1;};" ++
        "Object.defineProperty(RangeError,'name',{get:fail});const top=Object.create(null);" ++
        "top.constructor=RangeError;const middle=Object.create(top);" ++
        "Object.defineProperties(middle,{constructor:{get:fail},[Symbol.toStringTag]:{get:fail}});" ++
        "const e=new TypeError('a');Object.setPrototypeOf(e,middle);Object.create(e);return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.expectName(value, "RangeError");
    try f.expectBool("hits===0");
}

test "VM native Error constructor actual intrinsic Object is skipped without its public name" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {globalThis.hits=0;Object.defineProperty(Object,'name',{get(){hits++;throw 1;}});" ++
        "const top=Object.create(null);top.constructor=SyntaxError;const middle=Object.create(top);" ++
        "middle.constructor=Object;const e=new TypeError('a');Object.setPrototypeOf(e,middle);" ++
        "Object.create(e);return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.expectName(value, "SyntaxError");
    try f.expectBool("hits===0");
}

test "VM native Error constructor final native class fallback remains Error" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {const e=new RangeError('a');e.constructor=SyntaxError;e[Symbol.toStringTag]=17;" ++
        "const p=Object.create(null);p.constructor=42;Object.setPrototypeOf(e,p);Object.create(e);return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.expectName(value, "Error");
}

test "VM native Error constructor bound and Proxy constructors are skipped without traps" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {globalThis.hits=0;const top=Object.create(null);top.constructor=URIError;" ++
        "const middle=Object.create(top);middle.constructor=new Proxy(TypeError,{get(){hits++;throw 1;}});" ++
        "const low=Object.create(middle);low.constructor=RangeError.bind(null);" ++
        "const e=new Error('a');Object.setPrototypeOf(e,low);Object.create(e);hits=0;return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.expectName(value, "URIError");
    try f.expectBool("hits===0");
}

test "VM native Error constructor missing general DebugName is explicit without function name Get" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {globalThis.hits=0;function ActualUser(){}" ++
        "Object.defineProperty(ActualUser,'name',{get(){hits++;throw 1;}});" ++
        "const e=new RangeError('a');Object.setPrototypeOf(e,{constructor:ActualUser});Object.create(e);return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.expectStatus(value, c.JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED);
    try f.expectBool("hits===0");
}

test "VM native Error constructor Proxy prototype storage stays unsupported without traps" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.eval(
        "(() => {globalThis.hits=0;const fail=()=>{hits++;throw 1;};" ++
        "const p=new Proxy(Object.create(null),{get:fail,getOwnPropertyDescriptor:fail,getPrototypeOf:fail});" ++
        "const e=new RangeError('a');Object.setPrototypeOf(e,p);Object.create(e);hits=0;return e;})()");
    defer c.JS_FreeValue(f.context.?, value);
    try f.expectStatus(value, c.JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED);
    try f.expectBool("hits===0");
}

test "VM native Error constructor native exotic descriptors remain uncalled and unsupported" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const value = try f.checked(c.JS_NewRangeError(f.context.?, "native exotic"));
    defer c.JS_FreeValue(f.context.?, value);
    const exotic = try f.newExotic(); defer c.JS_FreeValue(f.context.?, exotic);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_SetPrototype(f.context.?, value, exotic));
    const child = try f.checked(c.JS_NewObjectProto(f.context.?, value));
    defer c.JS_FreeValue(f.context.?, child);
    try f.expectStatus(value, c.JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED);
    try std.testing.expectEqual(@as(usize, 0), f.probe.exotic_calls);
}

test "VM native Error constructor different new target is an explicit remaining dependency" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const cases = [_][:0]const u8{
        "(() => {class Derived extends RangeError{}const e=new Derived('a');e[Symbol.toStringTag]='RangeError';return e;})()",
        "(() => {function Other(){}return Reflect.construct(RangeError,['a'],Other);})()",
    };
    for (cases) |expression| {
        const value = try f.eval(expression); defer c.JS_FreeValue(f.context.?, value);
        try std.testing.expect(c.JS_IsError(value));
        try f.expectStatus(value, c.JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED);
    }
}

test "VM native Error constructor unrecorded physical Error allocation cannot invent provenance" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const actual = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, actual);
    const raw = try f.checked(c.JS_NewObjectProtoClass(f.context.?, c.pi_js_null(), c.JS_GetClassID(actual)));
    defer c.JS_FreeValue(f.context.?, raw);
    try std.testing.expect(c.JS_IsError(raw));
    try f.expectStatus(raw, c.JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED);
}

test "VM native Error constructor ordinary lookalikes never acquire the actual native class" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const cases = [_][:0]const u8{
        "({name:'RangeError',message:'Maximum call stack size exceeded',constructor:RangeError})",
        "Object.create(RangeError.prototype)",
        "new Proxy(new RangeError('a'),{})",
        "17",
    };
    for (cases) |expression| {
        const value = try f.eval(expression); defer c.JS_FreeValue(f.context.?, value);
        try std.testing.expect(!c.JS_IsError(value));
        try f.expectStatus(value, c.JS_PI_ERROR_CONSTRUCTOR_NAME_NOT_NATIVE_ERROR);
    }
}

test "VM native Error constructor query preserves actual ordinary and uncatchable pending owners" {
    for ([_]bool{false, true}) |fatal| {
        for ([_]bool{false, true}) |unsupported| {
            var f: Fixture = .{}; try f.init(); defer f.deinit();
            const value = try f.eval(if (unsupported)
                "(() => {class Derived extends RangeError{}return new Derived('a');})()"
            else
                "new RangeError('a')");
            defer c.JS_FreeValue(f.context.?, value);
            const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
            if (fatal) c.JS_SetUncatchableError(f.context.?, reason);
            _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
            const before_generation = c.JS_PiExecutionTerminationGeneration(f.runtime.?);
            const before_oom = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
            var owned = c.pi_js_undefined();
            defer c.JS_FreeValue(f.context.?, owned);
            const status = c.JS_PiGetNativeErrorConstructorName(f.context.?, value, &owned);
            try std.testing.expectEqual(@as(Status, if (unsupported)
                c.JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED else c.JS_PI_ERROR_CONSTRUCTOR_NAME_FOUND), status);
            try std.testing.expect(c.JS_HasException(f.context.?));
            const actual = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, actual);
            try std.testing.expect(c.JS_IsSameValue(f.context.?, actual, reason));
            try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(actual));
            try std.testing.expectEqual(before_generation, c.JS_PiExecutionTerminationGeneration(f.runtime.?));
            try std.testing.expectEqual(before_oom, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
            if (unsupported) try std.testing.expect(c.JS_IsUndefined(owned)) else try f.expectText(owned, "RangeError");
        }
    }
}

test "VM native Error constructor active and cancelled native termination state is unchanged" {
    for ([_]bool{false, true}) |cancelled| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const value = try f.checked(c.JS_NewRangeError(f.context.?, "private state"));
        defer c.JS_FreeValue(f.context.?, value);
        c.JS_PiRequestExecutionTermination(f.runtime.?);
        try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.context.?));
        if (cancelled) c.JS_PiCancelExecutionTermination(f.runtime.?);
        const before_generation = c.JS_PiExecutionTerminationGeneration(f.runtime.?);
        const owned = try f.name(value); defer c.JS_FreeValue(f.context.?, owned);
        try std.testing.expectEqual(!cancelled, c.JS_HasException(f.context.?));
        try std.testing.expectEqual(!cancelled, c.JS_PiIsExecutionTerminating(f.runtime.?));
        try std.testing.expectEqual(before_generation, c.JS_PiExecutionTerminationGeneration(f.runtime.?));
        if (!cancelled) {
            const actual = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, actual);
            try std.testing.expect(c.JS_PiIsExecutionTermination(actual));
            // Cancellation clears an event only while its exact token is pending.
            _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, actual));
            c.JS_PiCancelExecutionTermination(f.runtime.?);
            try std.testing.expect(!c.JS_HasException(f.context.?));
            try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.runtime.?));
        }
        try f.expectText(owned, "RangeError");
    }
}

test "VM native Error constructor all selected query branches allocate no VM storage" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const cases = [_]struct { expression: [:0]const u8, expected: ?[]const u8 }{
        .{ .expression = "new RangeError('a')", .expected = "RangeError" },
        .{ .expression = "(() => {const e=new TypeError('a');e[Symbol.toStringTag]='ExistingData';Object.create(e);return e;})()", .expected = "ExistingData" },
        .{ .expression = "(() => {const e=new RangeError('a');Object.setPrototypeOf(e,Object.create(null));Object.create(e);return e;})()", .expected = "Error" },
        .{ .expression = "(() => {class Derived extends RangeError{}return new Derived('a');})()", .expected = null },
    };
    for (cases) |item| {
        const value = try f.eval(item.expression); defer c.JS_FreeValue(f.context.?, value);
        const before_oom = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
        var owned = c.pi_js_undefined(); defer c.JS_FreeValue(f.context.?, owned);
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const status = c.JS_PiGetNativeErrorConstructorName(f.context.?, value, &owned);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        try std.testing.expectEqual(before_oom, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
        try std.testing.expect(!c.JS_HasException(f.context.?));
        if (item.expected) |expected| {
            try std.testing.expectEqual(@as(Status, c.JS_PI_ERROR_CONSTRUCTOR_NAME_FOUND), status);
            try f.expectText(owned, expected);
        } else {
            try std.testing.expectEqual(@as(Status, c.JS_PI_ERROR_CONSTRUCTOR_NAME_UNSUPPORTED), status);
            try std.testing.expect(c.JS_IsUndefined(owned));
        }
    }
}

test "VM native Error constructor actual native origin survives released foreign realm and retires with Error" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var foreign: ?*c.JSContext = c.JS_NewContext(f.runtime.?) orelse return error.OutOfMemory;
    defer if (foreign) |context| c.JS_FreeContext(context);
    var value = c.pi_js_undefined(); defer c.JS_FreeValue(f.context.?, value);
    var constructor = c.pi_js_undefined(); defer c.JS_FreeValue(f.context.?, constructor);
    const global_object = try f.checked(c.JS_GetGlobalObject(foreign.?));
    const selected_constructor = c.JS_GetPropertyStr(foreign.?, global_object, "Error");
    c.JS_FreeValue(foreign.?, global_object);
    constructor = try f.checked(selected_constructor);
    const marker = try f.newMarker();
    // DefinePropertyValueStr consumes the marker, including on failure.
    try std.testing.expectEqual(@as(c_int, 1),
        c.JS_DefinePropertyValueStr(foreign.?, constructor, "nativeLifetimeWitness", marker, c.JS_PROP_C_W_E));
    value = try f.checked(c.JS_NewError(foreign.?));
    {
        // The raw context has no native stack hooks or prepareStackTrace.
        // Its real ErrorData is a String, so it cannot retain the foreign realm.
        const stack_data = try f.checked(c.JS_GetPropertyStr(foreign.?, value, "stack"));
        defer c.JS_FreeValue(f.context.?, stack_data);
        try std.testing.expect(c.JS_IsString(stack_data));
    }
    try std.testing.expectEqual(@as(c_int, 1), c.JS_SetPrototype(foreign.?, value, c.pi_js_null()));
    try f.deleteOwn(value, "stack");
    try f.expectNoOwnProperties(value);
    c.JS_FreeValue(foreign.?, constructor); constructor = c.pi_js_undefined();
    c.JS_FreeContext(foreign.?); foreign = null;
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 0), f.probe.retired);
    const owned_name = try f.name(value); defer c.JS_FreeValue(f.context.?, owned_name);
    c.JS_FreeValue(f.context.?, value); value = c.pi_js_undefined();
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired);
    // The returned String is an independent owned result, not a realm handle.
    try f.expectText(owned_name, "Error");
}
