//! Capture the actual pending VM reason before a native SDK catch or rethrow.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, mode: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    if (argc < 2) return c.JS_ThrowTypeError(context, "SDK boundary control requires target and stale reason");
    if (engine.captured_exception) |previous| engine.freeValue(previous);
    engine.captured_exception = c.JS_DupValue(context, args[1]);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    switch (mode) {
        0 => sdk.put(engine, args[0], "field", c.JS_NewInt32(context, 7)) catch |err| return sdk.fail(engine, err),
        1 => _ = sdk.length(engine, args[0]) catch |err| return sdk.fail(engine, err),
        2 => sdk.append(engine, args[0], c.JS_NewInt32(context, 7)) catch |err| return sdk.fail(engine, err),
        else => return c.JS_ThrowTypeError(context, "Invalid SDK boundary control"),
    }
    return c.pi_js_undefined();
}
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ "sdkBoundaryPut", "sdkBoundaryLength", "sdkBoundaryAppend" }, 0..) |name, index| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, invoke, name, 2, @intCast(index)));
        try sdk.put(engine, global, name, function);
    }
}
fn run(program: []const u8) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const value = try engine.eval(program, "sdk-exception-boundary-control.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(value);
}
test "native SDK boundary put captures the raw proxy reason over an old capture" {
    try run(
        \\{const raw={put:true},stale={stale:true};let calls=0,caught;
        \\const target=new Proxy({},{defineProperty(){calls++;throw raw}});
        \\try{sdkBoundaryPut(target,stale)}catch(reason){caught=reason}
        \\if(caught!==raw||calls!==1)throw Error('put lost actual pending reason');}
    );
}
test "native SDK boundary length captures the coercion reason over an old capture" {
    try run(
        \\{const raw={length:true},stale={stale:true};let reads=0,coercions=0,caught;
        \\const target={get length(){reads++;return{[Symbol.toPrimitive](){coercions++;throw raw}}}};
        \\try{sdkBoundaryLength(target,stale)}catch(reason){caught=reason}
        \\if(caught!==raw||reads!==1||coercions!==1)throw Error('length lost actual pending reason');}
    );
}
test "native SDK boundary append captures the setter reason over an old capture" {
    try run(
        \\{const raw={append:true},stale={stale:true};let reads=0,sets=0,caught;
        \\const target=new Proxy({},{get(target,key){if(key==='length'){reads++;return 0}return Reflect.get(target,key)},set(){sets++;throw raw}});
        \\try{sdkBoundaryAppend(target,stale)}catch(reason){caught=reason}
        \\if(caught!==raw||reads!==1||sets!==1)throw Error('append lost actual pending reason');}
    );
}
test "native SDK boundary append retires its owned value when length fails" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const target = try engine.eval("({get length(){throw 'length unavailable'}})", "sdk-append-length-failure.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(target);
    const value = try engine.checked(c.JS_NewObject(engine.context));
    var locally_owned = true;
    defer if (locally_owned) engine.freeValue(value);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "WeakRef");
    defer engine.freeValue(constructor);
    var arguments = [_]c.JSValue{value};
    const weak = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &arguments));
    defer engine.freeValue(weak);
    c.JS_ClearKeptObjects(engine.runtime);
    // append takes ownership on every path, including a failing length read.
    locally_owned = false;
    try std.testing.expectError(error.JavaScriptException, sdk.append(engine, target, value));
    c.JS_ClearKeptObjects(engine.runtime);
    c.JS_RunGC(engine.runtime);
    const observed = try sdk.invoke(engine, weak, "deref", &.{});
    defer engine.freeValue(observed);
    if (!c.JS_IsUndefined(observed)) {
        // Retire the old implementation's leaked original root before reporting
        // the assertion, so teardown cannot hide this failure with a GC abort.
        engine.freeValue(value);
        return error.AppendRetainedOwnedValueAfterLengthFailure;
    }
}
