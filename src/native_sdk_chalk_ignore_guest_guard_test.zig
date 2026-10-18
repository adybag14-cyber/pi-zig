//! Prepared same-operation provenance controls. Native DATA creation is an
//! actual successful C callback; a separate actual fatal producer is contrasted.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_chalk_scope.zig").Scope;
const owned = @import("extensions/native_sdk_owned_completion.zig");
const chalk = @import("extensions/native_sdk_chalk.zig");
const ignore = @import("extensions/native_sdk_ignore708.zig");
const c = em.c;
fn makeData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(context); // Successful private DATA; no active B1.
}
fn makeFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return em.Engine.fromContext(context.?).throwNativeOutOfMemoryFatal();
}
fn makeRetainedFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemoryFatal();
    engine.freeValue(c.JS_GetException(context));
    // Actual B1 was published by the producer. Empty VM pending plus success
    // must not erase it; this callback does not clear any Error flag.
    return c.JS_NewInt32(context, 42);
}
fn put(scope: *Scope, global: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try scope.put(global, name, try scope.own(value)); }
fn setup(scope: *Scope) !c.JSValue {
    const engine = scope.engine;
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try put(scope, global, "bindingMakePrivateData", try engine.checked(c.JS_NewCFunction(engine.context, makeData, "bindingMakePrivateData", 0)));
    try put(scope, global, "bindingMakeActualFatal", try engine.checked(c.JS_NewCFunction(engine.context, makeFatal, "bindingMakeActualFatal", 0)));
    try put(scope, global, "bindingMakeRetainedFatal", try engine.checked(c.JS_NewCFunction(engine.context, makeRetainedFatal, "bindingMakeRetainedFatal", 0)));
    return global;
}
const Route = enum { get, call, construct, set, define, stringify, concat };
fn invoke(scope: *Scope, target: c.JSValue, route: Route) !void {
    switch (route) {
        .get => _ = try scope.get(target, "value"),
        .call => _ = try scope.call(target, c.pi_js_undefined(), &.{}),
        .construct => _ = try scope.construct(target, &.{}),
        .set => try scope.set(target, "value", c.pi_js_undefined()),
        .define => try scope.put(target, "value", c.pi_js_undefined()),
        .stringify => _ = try scope.stringify(target),
        .concat => _ = try scope.concat(try scope.text("prefix"), target),
    }
}
test "native private Chalk Ignore guest operations keep same-operation private DATA throws ordinary" {
    const cases = .{
        .{ Route.get, "({get value(){const A=bindingMakePrivateData();globalThis.bindingA=A;throw A}})" },
        .{ Route.call, "(()=>{const A=bindingMakePrivateData();globalThis.bindingA=A;throw A})" },
        .{ Route.construct, "(function(){const A=bindingMakePrivateData();globalThis.bindingA=A;throw A})" },
        .{ Route.set, "({set value(input){const A=bindingMakePrivateData();globalThis.bindingA=A;throw A}})" },
        .{ Route.define, "new Proxy({},{defineProperty(){const A=bindingMakePrivateData();globalThis.bindingA=A;throw A}})" },
        .{ Route.stringify, "({toString(){const A=bindingMakePrivateData();globalThis.bindingA=A;throw A}})" },
        .{ Route.concat, "({[Symbol.toPrimitive](){const A=bindingMakePrivateData();globalThis.bindingA=A;throw A}})" },
    };
    inline for (cases) |case| {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        var scope: Scope = .{ .engine = engine };
        try owned.finishVoid(&scope, dataCase(&scope, case[0], case[1]));
    }
}
fn dataCase(scope: *Scope, route: Route, source: []const u8) !void {
    const engine = scope.engine;
    const global = try setup(scope);
    const target = try scope.own(try engine.eval(source, "binding-same-operation-data.js", c.JS_EVAL_TYPE_GLOBAL));
    const generation = engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, invoke(scope, target, route));
    try std.testing.expect(engine.native_fatal_invocation == null);
    const caught = engine.captured_exception orelse return error.MissingSameOperationData;
    engine.captured_exception = null;
    _ = try scope.own(caught);
    try std.testing.expect(engine.native_allocation_generation != generation);
    try std.testing.expect(c.pi_js_native_allocation_error_generation(caught) != 0);
    try std.testing.expect(!c.JS_IsUncatchableError(caught));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(scope.equal(caught, try scope.get(global, "bindingA")));
}
test "native private Chalk Ignore same-get and same-call actual fatal producers retain current event" {
    inline for (.{ Route.get, Route.call }) |route| {
        inline for ([_]bool{ false, true }) |clear_slot| {
            const engine = try em.Engine.init(std.testing.allocator, .{});
            defer engine.deinit();
            var scope: Scope = .{ .engine = engine };
            try owned.finishVoid(&scope, fatalCase(&scope, route, clear_slot));
        }
    }
}
fn fatalCase(scope: *Scope, comptime route: Route, comptime clear_slot: bool) !void {
    const engine = scope.engine;
    _ = try setup(scope);
    const producer = if (clear_slot) "bindingMakeRetainedFatal()" else "bindingMakeActualFatal()";
    const source = if (route == .get) "({get value(){return " ++ producer ++ "}})" else "(()=>" ++ producer ++ ")";
    const target = try scope.own(try engine.eval(source, "binding-same-operation-fatal.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectError(error.JavaScriptException, invoke(scope, target, route));
    try std.testing.expect(engine.native_fatal_invocation == null);
    const caught = engine.captured_exception orelse return error.MissingActualNativeFatal;
    engine.captured_exception = null;
    _ = try scope.own(caught);
    try std.testing.expect(c.JS_IsUncatchableError(caught));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(caught) != 0);
    try std.testing.expect(scope.equal(caught, engine.native_allocation_exception.?));
}
fn platform(engine: *em.Engine) !void {
    var env: std.process.Environ.Map = .init(std.testing.allocator);
    defer env.deinit();
    try env.put("FORCE_COLOR", "0");
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &env, &.{"private-chalk-ignore-guest-controls"});
    try @import("extensions/native_node_os.zig").install(engine);
}
test "native genuine private Chalk Ignore consumed operations preserve same-operation DATA" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try platform(engine);
    var scope: Scope = .{ .engine = engine };
    try owned.finishVoid(&scope, consumed(&scope));
}
fn consumed(scope: *Scope) !void {
    const engine = scope.engine;
    const global = try setup(scope);
    const actual_chalk = try scope.own(try chalk.createDefault(engine));
    const actual_ignore = try scope.own(try ignore.createDefault(engine));
    try std.testing.expect(scope.equal(actual_chalk, try scope.own(try chalk.createDefault(engine))));
    try std.testing.expect(scope.equal(actual_ignore, try scope.own(try ignore.createDefault(engine))));
    try scope.put(global, "privateChalkGuest", actual_chalk);
    try scope.put(global, "privateIgnoreGuest", actual_ignore);
    const result = try engine.evalModule(
        \\const fail=()=>{const A=bindingMakePrivateData();globalThis.bindingA=A;throw A};
        \\const check=operation=>{let caught;try{operation()}catch(error){caught=error}if(caught!==bindingA)throw Error('private supplier DATA identity lost')};
        \\check(()=>privateChalkGuest.constructor({get level(){return fail()}}));
        \\const originalSafe=Number.isSafeInteger;try{Number.isSafeInteger=fail;check(()=>privateChalkGuest.constructor({level:1}))}finally{Number.isSafeInteger=originalSafe}
        \\check(()=>privateChalkGuest.yellow({[Symbol.toPrimitive]:fail}));
        \\check(()=>privateIgnoreGuest().add([{get pattern(){return fail()}}]));
        \\const originalTest=RegExp.prototype.test;try{RegExp.prototype.test=fail;check(()=>privateIgnoreGuest().add(['x']))}finally{RegExp.prototype.test=originalTest}
        \\const matcher=privateIgnoreGuest();matcher._rules._basenameCount={[Symbol.toPrimitive]:fail};check(()=>matcher.add(['x']));
        \\const colored=privateChalkGuest.constructor({level:1}).yellow('x');if(colored!=='\x1b[33mx\x1b[39m')throw Error('real ANSI wrapper changed');
        \\const ordinary=privateIgnoreGuest().add(['*.tmp','!keep.tmp']);if(!ordinary.ignores('x.tmp')||ordinary.ignores('keep.tmp'))throw Error('real ignore matching changed');
        \\export const complete=true;
    , "actual-private-suppliers-same-operation.mjs");
    _ = try scope.own(result);
    const reason = try scope.get(global, "bindingA");
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
}
